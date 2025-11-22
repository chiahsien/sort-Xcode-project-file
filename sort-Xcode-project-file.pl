#!/usr/bin/env perl

# Copyright (C) 2007-2021 Apple Inc.  All rights reserved.
# Copyright (C) 2021-2026 Nelson.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1.  Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
# 2.  Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
# 3.  Neither the name of Apple Inc. ("Apple") nor the names of
#     its contributors may be used to endorse or promote products derived
#     from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY APPLE AND ITS CONTRIBUTORS "AS IS" AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL APPLE OR ITS CONTRIBUTORS BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Script to sort certain sections and arrays in Xcode project.pbxproj files.
# Behavior and flags:
# - Default sorting is case-sensitive (preserves original behavior).
# - Optionally enable case-insensitive sorting with --case-insensitive.
# - The case-insensitive flag affects both natural sorting and directory-vs-file lookups.
#
# Use with:
#   --case-insensitive    enable case-insensitive sorting (default: disabled)
#   --case-sensitive      explicit alias to force case-sensitive sorting
#   -h, --help            show help
#   -w, --no-warnings     suppress warnings
#
# NOTE: Build-phase order-sensitive arrays (e.g., buildPhases) are NOT sorted by this script.

use strict;
use warnings;

use File::Basename;
use File::Spec;
use File::Temp qw(tempfile);
use Getopt::Long;

# Maximum iterations when parsing brace-balanced blocks to prevent infinite loops
use constant MAX_BRACE_ITERATIONS => 10000;

# Xcode object ID format: 24 hexadecimal characters
use constant XCODE_OBJECT_ID => qr/[A-Fa-f0-9]{24}/;

# Compiled regex patterns for better performance and readability
my $REGEX_ARRAY_START = qr/^
    (\s*)                           # capture leading whitespace
    (children|buildConfigurations|targets|packageProductDependencies|packageReferences)
    \s* = \s* \( \s*$               # array opening
/x;

my $REGEX_FILES_ARRAY = qr/^
    (\s*)                           # capture leading whitespace
    files \s* = \s* \( \s*$         # files array opening
/x;

my $REGEX_CHILD_ENTRY = qr/^
    \s*                             # optional leading whitespace
    [A-Fa-f0-9]{24}                 # Xcode object ID (24 hex chars)
    \s+ \/\* \s*                    # space and comment start
    (.+?)                           # capture filename (non-greedy)
    \s* \*\/ ,                      # comment end and comma
    $                               # end of line
/x;

my $REGEX_FILE_ENTRY = qr/^
    \s*                             # optional leading whitespace
    [A-Fa-f0-9]{24}                 # Xcode object ID (24 hex chars)
    \s+ \/\* \s*                    # space and comment start
    (.+?)                           # capture filename (non-greedy)
    \s* \*\/ \s+ in \s+             # comment end, "in", and phase name follows
/x;

my $REGEX_BLOCK_ENTRY = qr/^
    \s*                             # optional leading whitespace
    ([A-Fa-f0-9]{24})               # capture object ID (24 hex chars)
    \s+ \/\* \s*                    # space and comment start
    (.+?)                           # capture name (non-greedy)
    \s* \*\/ \s* = \s*              # comment end and equals sign
    (\{)?                           # optional opening brace (capture for multi-line detection)
/mx;  # m flag: ^ and $ match line boundaries within string

my $REGEX_BLOCK_NAME_COMMENT = qr/^
    \s*                             # optional leading whitespace
    [A-Fa-f0-9]{24}                 # Xcode object ID (24 hex chars)
    \s+ \/\* \s*                    # space and comment start
    (.+?)                           # capture name (non-greedy)
    \s* \*\/ \s* =                  # comment end and equals sign
/mx;

# Allow list: names of "Begin ... section" sections we will parse and sort block entries for.
# These are considered safe-to-sort (reordering entries shouldn't change Xcode behaviour).
my %sortable_sections = map { $_ => 1 } qw(
    PBXFileReference
    PBXBuildFile
    PBXGroup
    PBXVariantGroup
    PBXReferenceProxy
    PBXContainerItemProxy
    PBXTargetDependency
    XCBuildConfiguration
    XCConfigurationList
);

# Some files without extensions, so they can sort with other files.
# Otherwise, names without extensions are assumed to be groups or directories and sorted last.
# Keep original-cased keys by default; a lowercase map is built for case-insensitive lookups.
my %isFile = map { $_ => 1 } qw(
    create_hash_table
);
my %isFile_lc = map { lc($_) => 1 } keys %isFile;

# Flags / options
my $printWarnings = 1;
my $showHelp;

# Default: case-sensitive sorting. Provide --case-insensitive to enable.
my $CASE_INSENSITIVE = 0;

my $getOptionsResult = GetOptions(
    'h|help'             => \$showHelp,
    'w|warnings!'        => \$printWarnings,
    # --case-insensitive enables case-insensitive sorting
    'case-insensitive!'  => \$CASE_INSENSITIVE,
    # convenience alias: --case-sensitive forces case-sensitive (sets variable to 0)
    'case-sensitive'     => sub { $CASE_INSENSITIVE = 0 },
);

if (scalar(@ARGV) == 0 && !$showHelp) {
    print STDERR "ERROR: No Xcode project files (project.pbxproj) listed on command-line.\n";
    undef $getOptionsResult;
}

if (!$getOptionsResult || $showHelp) {
    print STDERR <<'__END__';
Usage: sort-Xcode-project-file.pl [options] path/to/project.pbxproj [path/to/project.pbxproj ...]
  -h|--help               show this help message
  -w|--[no-]warnings      show or suppress warnings (default: show warnings)
  --case-insensitive      enable case-insensitive sorting (default: disabled)
  --case-sensitive        explicit alias to force case-sensitive sorting

Notes:
  - Default behavior is case-sensitive sorting (original behavior).
  - Use --case-insensitive to enable case-insensitive natural sorting
    (e.g. "file2" < "file10", case ignored for alphabetic parts).
__END__
    exit 1;
}

for my $projectFile (@ARGV) {
    if (basename($projectFile) =~ /\.xcodeproj$/) {
        $projectFile = File::Spec->catfile($projectFile, "project.pbxproj");
    }

    if (basename($projectFile) ne "project.pbxproj") {
        print STDERR "WARNING: Not an Xcode project file: $projectFile\n" if $printWarnings;
        next;
    }

    # Use CLEANUP => 1 for automatic temp file cleanup on normal and abnormal exits
    my ($OUT, $tempFileName) = tempfile(
        basename($projectFile) . "-XXXXXXXX",
        DIR => dirname($projectFile),
        UNLINK => 0,  # We'll handle deletion manually for better control
    );

    # Process file in eval block for proper error handling and cleanup
    eval {
        open(my $IN, '<', $projectFile) or die "Could not open $projectFile: $!";

        while (my $line = <$IN>) {
            # Check for read errors
            if (!defined $line && !eof($IN)) {
                die "Error reading from $projectFile: $!";
            }
            last unless defined $line;

            # Sort files section (array named files = (...); ).
            if ($line =~ $REGEX_FILES_ARRAY) {
                my $indent = $1;
                print $OUT $line or die "Error writing to $tempFileName: $!";

                my $endMarker = $indent . ");";
                my @files = read_array_entries($IN, $endMarker, $projectFile, 'files');

                # Remove duplicate lines then sort.
                my @uniqueLines = uniq(@files);
                print $OUT sort sortFilesByFileName @uniqueLines or die "Error writing to $tempFileName: $!";
                print $OUT $endMarker or die "Error writing to $tempFileName: $!";
            }
            # Sort children, buildConfigurations, targets, packageProductDependencies, and packageReferences sections (array-form).
            elsif ($line =~ $REGEX_ARRAY_START) {
                my $indent = $1;
                my $arrayName = $2;
                print $OUT $line or die "Error writing to $tempFileName: $!";

                my $endMarker = $indent . ");";
                my @children = read_array_entries($IN, $endMarker, $projectFile, $arrayName);

                # Remove duplicate lines then sort.
                my @uniqueLines = uniq(@children);
                print $OUT sort sortChildrenByFileName @uniqueLines or die "Error writing to $tempFileName: $!";
                print $OUT $endMarker or die "Error writing to $tempFileName: $!";
            }
            # Handle "Begin ... section" blocks; if section is in our sortable list, parse entries and sort by name
            elsif ($line =~ /Begin\s+(\S+)\s+section/) {
                my $sectionName = $1;
                print $OUT $line or die "Error writing to $tempFileName: $!";

                # Read everything until the corresponding End ... section line
                if ($sortable_sections{$sectionName}) {
                    # We will parse entries inside this section and sort them.
                    my @entries;
                    reset_block_prefix();  # Ensure clean state for new section

                    # Parse all entries in this section
                    while (my $sectionLine = <$IN>) {
                        if (!defined $sectionLine) {
                            die "Unexpected end of file while parsing $sectionName section in $projectFile";
                        }

                        # If we reached the End ... section, break and print end marker later
                        if ($sectionLine =~ /End\s+\Q$sectionName\E\s+section/) {
                            # Filter out any undefined or empty entries, remove duplicates, then sort
                            my @validEntries = grep { defined $_ && $_ ne '' } @entries;
                            my @unique = uniq(@validEntries);
                            print $OUT sort sortBlocksByName @unique or die "Error writing to $tempFileName: $!";
                            print $OUT $sectionLine or die "Error writing to $tempFileName: $!";
                            last;
                        }

                        # Try to parse as a block entry
                        my $entry = parse_block_entry($IN, $sectionLine, $projectFile, $tempFileName);
                        if (defined $entry && $entry ne '') {
                            push @entries, $entry;
                        }
                    }
                } else {
                    # Not a section we automatically sort: passthrough until End ... section (preserve original order)
                    while (my $sectionLine = <$IN>) {
                        if (!defined $sectionLine) {
                            die "Unexpected end of file while passing through $sectionName section in $projectFile";
                        }
                        print $OUT $sectionLine or die "Error writing to $tempFileName: $!";
                        if ($sectionLine =~ /End\s+\Q$sectionName\E\s+section/) {
                            last;
                        }
                    }
                }
            }
            # Ignore whole PBXFrameworksBuildPhase section (preserve original ordering)
            elsif ($line =~ /^(.*)Begin PBXFrameworksBuildPhase section(.*)$/) {
                print $OUT $line or die "Error writing to $tempFileName: $!";
                while (my $ignoreLine = <$IN>) {
                    if (!defined $ignoreLine) {
                        die "Unexpected end of file while parsing PBXFrameworksBuildPhase section in $projectFile";
                    }
                    print $OUT $ignoreLine or die "Error writing to $tempFileName: $!";
                    if ($ignoreLine =~ /^(.*)End PBXFrameworksBuildPhase section(.*)$/) {
                        last;
                    }
                }
            }
            # Other lines: passthrough
            else {
                print $OUT $line or die "Error writing to $tempFileName: $!";
            }
        }

        close($IN) or die "Error closing $projectFile: $!";
        close($OUT) or die "Error closing $tempFileName: $!";

        # Atomically replace original file
        unlink($projectFile) or die "Could not delete $projectFile: $!";
        rename($tempFileName, $projectFile) or die "Could not rename $tempFileName to $projectFile: $!";
    };

    # Handle any errors during processing
    if ($@) {
        my $error = $@;
        # Attempt cleanup
        close($OUT) if defined fileno($OUT);
        if (-e $tempFileName) {
            unlink($tempFileName) or warn "Could not clean up temporary file $tempFileName: $!";
        }
        die "Failed to process $projectFile: $error";
    }
}

exit 0;

# -----------------------------------------------------------------------------
# Read array entries until end marker is found
#
# Purpose:
#   Read lines from an array declaration (e.g., "files = ( ... );") until
#   the closing marker is found, with proper error handling.
#
# Parameters:
#   $IN          - input file handle
#   $endMarker   - the closing marker to look for (e.g., "    );")
#   $projectFile - project file name (for error messages)
#   $arrayName   - name of array being parsed (for error messages)
#
# Returns:
#   Array of lines read (not including the end marker)
#   Updates $endMarker reference to include actual line read
# -----------------------------------------------------------------------------
sub read_array_entries {
    my ($IN, $endMarker, $projectFile, $arrayName) = @_;
    my @entries;

    while (my $line = <$IN>) {
        if (!defined $line) {
            die "Unexpected end of file while parsing $arrayName array in $projectFile";
        }
        if ($line =~ /^\Q$endMarker\E\s*$/) {
            $_[1] = $line;  # Update the end marker to the actual line read
            last;
        }
        push @entries, $line;
    }

    return @entries;
}

# -----------------------------------------------------------------------------
# Parse a block entry from the input stream
#
# Purpose:
#   Extract a complete block entry, handling both single-line and multi-line
#   (brace-balanced) entries. Also preserves preceding comments/blank lines.
#
# Parameters:
#   $IN           - input file handle
#   $sectionLine  - current line being processed
#   $projectFile  - project file name (for error messages)
#   $tempFileName - temp file name (for error messages)
#
# Returns:
#   Complete entry string if this is a block entry, undef otherwise
#
# Note:
#   Uses a package-level variable to maintain prefix state between calls
# -----------------------------------------------------------------------------
{
    # Package-level variable to accumulate prefix lines between entries
    # Scoped to this block to prevent access from outside
    my $prefix = '';

    sub parse_block_entry {
        my ($IN, $sectionLine, $projectFile, $tempFileName) = @_;

        # Detect a block entry that begins with an object id comment
        if ($sectionLine =~ $REGEX_BLOCK_ENTRY) {
            my ($objectId, $name, $hasBrace) = ($1, $2, $3);

            # Start a new entry; include any prefix lines (comments/blank) that preceded it
            my $entry = $prefix . $sectionLine;
            $prefix = '';  # Reset prefix for next entry

            # If there's an opening brace, the entry may be multi-line. Balance braces.
            if (defined $hasBrace) {
                my $braceCount = count_braces($sectionLine);
                my $iterations = 0;

                while ($braceCount > 0) {
                    # Safety check: prevent infinite loop on malformed files
                    if (++$iterations > MAX_BRACE_ITERATIONS) {
                        die "Exceeded maximum iterations ($iterations) while parsing brace-balanced block in $projectFile. File may be malformed.";
                    }

                    my $nextLine = <$IN>;
                    if (!defined $nextLine) {
                        die "Unexpected end of file while parsing brace-balanced block in $projectFile (unmatched braces)";
                    }

                    $entry .= $nextLine;
                    $braceCount += count_braces($nextLine);
                }
            }

            return $entry;
        } else {
            # Not the start of an entry: accumulate into prefix to attach to next entry,
            # preserving comments and spacing that belong to the following entry.
            $prefix .= $sectionLine;
            return;  # Explicitly return undef for consistency
        }
    }

    # Helper sub to reset prefix state (useful when starting a new section)
    sub reset_block_prefix {
        $prefix = '';
    }
}

# -----------------------------------------------------------------------------
# Count net braces in a line (opening braces minus closing braces)
#
# Parameters:
#   $line - line of text to analyze
#
# Returns:
#   Integer: positive if more opening braces, negative if more closing braces
# -----------------------------------------------------------------------------
sub count_braces {
    my ($line) = @_;
    my $open = () = $line =~ /\{/g;
    my $close = () = $line =~ /\}/g;
    return $open - $close;
}

# -----------------------------------------------------------------------------
# Comparator used to sort block entries (Begin ... section entries).
# Tries to extract a human-friendly name for sorting:
# 1) comment after object id: "/* Name */"
# 2) name = "..." inside the block
# 3) path = "..." inside the block
# 4) fallback: whole entry string
# Natural sorting is applied to names so numeric substrings compare numerically.
#
# Parameters:
#   ($a, $b) - each is a string containing the full block text for a single entry.
#
# Returns:
#   -1, 0, 1 as per Perl comparison convention.
# -----------------------------------------------------------------------------
sub sortBlocksByName($)
{
    my ($a, $b) = @_;
    my $aName = extract_name_from_block($a);
    my $bName = extract_name_from_block($b);

    # Handle directories vs files as in children sorting: treat items without suffix as directories.
    # When case-insensitive mode is enabled, normalize the lookup key for %isFile.
    my $aSuffix = (defined $aName && $aName =~ m/\.([^.]+)$/) ? $1 : undef;
    my $bSuffix = (defined $bName && $bName =~ m/\.([^.]+)$/) ? $1 : undef;

    my $aIsDirectory = !defined $aSuffix && !($CASE_INSENSITIVE ? $isFile_lc{lc($aName // '')} : $isFile{$aName // ''});
    my $bIsDirectory = !defined $bSuffix && !($CASE_INSENSITIVE ? $isFile_lc{lc($bName // '')} : $isFile{$bName // ''});
    return $bIsDirectory <=> $aIsDirectory if $aIsDirectory != $bIsDirectory;

    # Use natural comparison for all names (respects $CASE_INSENSITIVE).
    return natural_cmp($aName // '', $bName // '');
}

# -----------------------------------------------------------------------------
# Extract a name from a block entry string.
#
# Purpose:
#   Produce a human-friendly key for sorting a PBX block entry.
#
# Parameters:
#   $block - full text of a block entry (may be single-line or multi-line).
#
# Returns:
#   A string representing the extracted name/key. The search order is:
#     1) comment after object id: "/* Name */" (preferred)
#     2) name = "..." inside the block
#     3) path = "..." inside the block
#     4) first non-empty line of the block
# -----------------------------------------------------------------------------
sub extract_name_from_block {
    my ($block) = @_;

    # Handle undefined or empty blocks
    return '' if !defined $block || $block eq '';

    # Try to find comment after object id: "/* Name */"
    if ($block =~ $REGEX_BLOCK_NAME_COMMENT) {
        return $1;
    }

    # Fallback: look for name = "..."
    if ($block =~ /name \s* = \s* "(.*?)"/mx) {
        return $1;
    }

    # Fallback: look for path = "..."
    if ($block =~ /path \s* = \s* "(.*?)"/mx) {
        return $1;
    }

    # Last resort: return the first non-whitespace line trimmed
    if ($block =~ /^\s*(\S.*)$/m) {
        return $1;
    }

    return $block;
}

# sortChildrenByFileName:
# Parameters:
#   ($a, $b) - each is a single line string representing an entry within a
#              "children = ( ... );" or similar array. Typical form:
#                "        012345... /* Foo.m */,"
#
# Returns:
#   -1, 0, 1 following Perl comparison semantics.
#
# Behavior:
#   - Extracts the filename from the comment portion of the entry.
#   - Applies directory-vs-file heuristic as in the original script.
#   - Uses natural_cmp() for full natural ordering (numeric parts compared numerically).
sub sortChildrenByFileName($)
{
    my ($a, $b) = @_;

    my $aFileName = $a =~ $REGEX_CHILD_ENTRY ? $1 : '';
    my $bFileName = $b =~ $REGEX_CHILD_ENTRY ? $1 : '';

    my $aSuffix = $1 if $aFileName =~ m/\.([^.]+)$/;
    my $bSuffix = $1 if $bFileName =~ m/\.([^.]+)$/;
    my $aIsDirectory = !$aSuffix && !($CASE_INSENSITIVE ? $isFile_lc{lc($aFileName)} : $isFile{$aFileName});
    my $bIsDirectory = !$bSuffix && !($CASE_INSENSITIVE ? $isFile_lc{lc($bFileName)} : $isFile{$bFileName});
    return $bIsDirectory <=> $aIsDirectory if $aIsDirectory != $bIsDirectory;

    # Natural compare for any filenames (handles numeric substrings correctly).
    return natural_cmp($aFileName, $bFileName);
}

# sortFilesByFileName:
# Parameters:
#   ($a, $b) - each is a single line string representing an entry within a
#              "files = ( ... );" array. Typical form:
#                "        012345... /* Foo.m in Sources */,"
#
# Returns:
#   -1, 0, 1 following Perl comparison semantics.
#
# Behavior:
#   - Extracts the filename from the comment portion before " in ".
#   - Uses natural_cmp() for natural ordering.
sub sortFilesByFileName($$)
{
    my ($a, $b) = @_;
    my $aFileName = $1 if $a =~ /^\s*[A-Fa-f0-9]{24}\s+\/\*\s*(.+?)\s*\*\/\s+in\s+/;
    my $bFileName = $1 if $b =~ /^\s*[A-Fa-f0-9]{24}\s+\/\*\s*(.+?)\s*\*\/\s+in\s+/;
    $aFileName //= '';
    $bFileName //= '';

    # Natural compare for any filenames (handles numeric substrings correctly).
    return natural_cmp($aFileName, $bFileName);
}

# -----------------------------------------------------------------------------
# Natural string comparator:
# Splits strings into runs of digits and non-digits. Compares runs pairwise:
# - If both runs are numeric, compare numerically (as integers), and if equal,
#   shorter digit-run (fewer leading zeros) is considered smaller.
# - Otherwise, compare lexically. If case-insensitive mode is enabled, non-digit
#   runs are compared in lowercase.
# If all common runs are equal, the one with fewer remaining tokens sorts first.
#
# Parameters:
#   $x, $y - two strings to compare
#
# Returns:
#   -1, 0, 1 following Perl comparison semantics.
# -----------------------------------------------------------------------------
sub natural_cmp {
    my ($x, $y) = @_;
    $x //= '';
    $y //= '';
    return 0 if $x eq $y;

    # Tokenize into digit and non-digit runs. Preserve order.
    my @xa = ($x =~ /(\d+|[^\d]+)/g);
    my @ya = ($y =~ /(\d+|[^\d]+)/g);

    while (@xa && @ya) {
        my $pa = shift @xa;
        my $pb = shift @ya;

        if ($pa =~ /^\d+$/ && $pb =~ /^\d+$/) {
            # Compare numerically
            my $na = $pa + 0;
            my $nb = $pb + 0;
            if ($na != $nb) {
                return $na <=> $nb;
            }
            # If numeric values equal (e.g. "001" vs "1"), prefer shorter digit run (fewer leading zeros)
            if (length($pa) != length($pb)) {
                return length($pa) <=> length($pb);
            }
            next; # equal numeric and equal length -> continue
        } else {
            # Non-numeric comparison:
            if ($CASE_INSENSITIVE) {
                my $la = lc($pa);
                my $lb = lc($pb);
                if ($la ne $lb) {
                    return $la cmp $lb;
                }
            } else {
                if ($pa ne $pb) {
                    return $pa cmp $pb;
                }
            }
            next;
        }
    }

    # If one has remaining runs, the shorter (fewer remaining tokens) sorts first.
    return scalar(@xa) <=> scalar(@ya);
}

# Subroutine to remove duplicate items in an array while preserving first occurrence order.
# https://perlmaven.com/unique-values-in-an-array-in-perl
#
# Parameters:
#   A list of strings (array)
#
# Returns:
#   A list containing only the first occurrence of each unique string, in the
#   original relative order.
sub uniq {
  my %seen;
  return grep { !$seen{$_}++ } @_;
}
