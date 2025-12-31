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

# -----------------------------------------------------------------------------
# Compiled regex patterns for better performance and readability
# -----------------------------------------------------------------------------

# Matches array declarations like:
#   children = (
#   buildConfigurations = (
#   targets = (
my $REGEX_ARRAY_START = qr/^
    (\s*)                           # capture leading whitespace - indentation level
    (children|buildConfigurations|targets|packageProductDependencies|packageReferences)
    \s* = \s* \( \s*$               # equals sign, opening paren, optional whitespace
/x;

# Matches files array declaration:
#   files = (
my $REGEX_FILES_ARRAY = qr/^
    (\s*)                           # capture leading whitespace - indentation level
    files \s* = \s* \( \s*$          # files keyword, equals, opening paren
/x;

# Matches child/target/config entries in arrays:
#   A1B2C3D4E5F6789012345678 /* AppDelegate.m */,
my $REGEX_CHILD_ENTRY = qr/^
    \s*                             # optional leading whitespace
    [A-Fa-f0-9]{24}                 # Xcode object ID - 24 hex chars
    \s+ \/\* \s*                    # space and comment start
    (.+?)                           # capture filename or name - non-greedy
    \s* \*\/ ,                      # comment end and trailing comma
    $                               # end of line
/x;

# Matches file entries in files arrays:
#   A1B2C3D4E5F6789012345678 /* AppDelegate.m in Sources */,
my $REGEX_FILE_ENTRY = qr/^
    \s*                             # optional leading whitespace
    [A-Fa-f0-9]{24}                 # Xcode object ID - 24 hex chars
    \s+ \/\* \s*                    # space and comment start
    (.+?)                           # capture filename - non-greedy
    \s* \*\/ \s+ in \s+             # comment end, in keyword, and build phase follows
/x;

# Files without extensions that should be treated as files (not directories).
#
# Why this is needed:
# - Normally, items without extensions are assumed to be directories/folders
# - These specific names are actually executable files (scripts, binaries)
# - Examples: Makefile, create_hash_table, Rakefile
#
# The %isFile hash uses original case; %isFile_lc provides case-insensitive lookups
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

    sort_project_file($projectFile);
}

exit 0;

# -----------------------------------------------------------------------------
# Sort Xcode project file in-place
#
# Purpose:
#   Read project.pbxproj file, sort specific arrays (children, files, etc.),
#   and write back sorted content. Reduces merge conflicts in version control.
#
# Sorting rules:
#   - children arrays: sort by filename, directories before files
#   - files arrays: sort by filename, no directory priority
#   - PBXFrameworksBuildPhase: preserve original order (not sorted)
#   - Removes duplicate entries before sorting
#
# Parameters:
#   $projectFile - path to project.pbxproj file
#
# Dies on error with descriptive message
# -----------------------------------------------------------------------------
sub sort_project_file {
    my ($projectFile) = @_;

    # Read entire file content
    my $content = read_file($projectFile);
    my @lines = split(/\n/, $content, -1);

    my @output;
    my $i = 0;

    while ($i < @lines) {
        my $line = $lines[$i];

        # Sort files section (array named files = (...); ).
        if ($line =~ $REGEX_FILES_ARRAY) {
            my $indent = $1;
            push @output, $line;
            $i++;

            my $endMarker = $indent . ");";
            my ($arrayLines, $endLine, $nextIndex) = read_array_entries(\@lines, $i, $endMarker, $projectFile, 'files');
            $i = $nextIndex;

            # Remove duplicate lines then sort.
            my @uniqueLines = uniq(@$arrayLines);
            push @output, sort sortFilesByFileName @uniqueLines;
            push @output, $endLine;
        }
        # Sort children, buildConfigurations, targets, packageProductDependencies, and packageReferences sections (array-form).
        elsif ($line =~ $REGEX_ARRAY_START) {
            my $indent = $1;
            my $arrayName = $2;
            push @output, $line;
            $i++;

            my $endMarker = $indent . ");";
            my ($arrayLines, $endLine, $nextIndex) = read_array_entries(\@lines, $i, $endMarker, $projectFile, $arrayName);
            $i = $nextIndex;

            # Remove duplicate lines then sort.
            my @uniqueLines = uniq(@$arrayLines);
            push @output, sort sortChildrenByFileName @uniqueLines;
            push @output, $endLine;
        }
        # Ignore whole PBXFrameworksBuildPhase section (preserve original ordering)
        elsif ($line =~ /^(.*)Begin PBXFrameworksBuildPhase section(.*)$/) {
            push @output, $line;
            $i++;

            while ($i < @lines) {
                my $frameworkLine = $lines[$i];
                push @output, $frameworkLine;
                $i++;
                if ($frameworkLine =~ /^(.*)End PBXFrameworksBuildPhase section(.*)$/) {
                    last;
                }
            }
        }
        # Other lines: passthrough
        else {
            push @output, $line;
            $i++;
        }
    }

    # Write sorted content back
    write_file($projectFile, join("\n", @output));
}

# -----------------------------------------------------------------------------
# Read array entries until end marker is found
#
# Purpose:
#   Read lines from an array declaration (e.g., "files = ( ... );") until
#   the closing marker is found, with proper error handling.
#
# Parameters:
#   $lines       - reference to array of all lines
#   $startIndex  - index to start reading from
#   $endMarker   - the closing marker to look for (e.g., "    );")
#   $projectFile - project file name (for error messages)
#   $arrayName   - name of array being parsed (for error messages)
#
# Returns:
#   ($arrayLines, $endLine, $nextIndex)
#   - $arrayLines: array reference of lines read (not including end marker)
#   - $endLine: the actual end marker line found
#   - $nextIndex: index of next line to process after end marker
# -----------------------------------------------------------------------------
sub read_array_entries {
    my ($lines, $startIndex, $endMarker, $projectFile, $arrayName) = @_;
    my @entries;
    my $i = $startIndex;

    while ($i < @$lines) {
        my $line = $lines->[$i];
        if ($line =~ /^\Q$endMarker\E\s*$/) {
            return (\@entries, $line, $i + 1);
        }
        push @entries, $line;
        $i++;
    }

    die "Unexpected end of file while parsing $arrayName array in $projectFile";
}

# -----------------------------------------------------------------------------
# Extract filename from a line using a regex pattern
#
# Purpose:
#   Common helper to extract filename from comment portions of Xcode entries.
#
# Parameters:
#   $line    - line to parse
#   $pattern - compiled regex pattern with a capture group for filename
#
# Returns:
#   Extracted filename string, or empty string if pattern doesn't match
#
# Examples:
#   extract_filename("  012345... /* Foo.m */,", $REGEX_CHILD_ENTRY) => "Foo.m"
#   extract_filename("  012345... /* Bar.h in Headers */,", $REGEX_FILE_ENTRY) => "Bar.h"
# -----------------------------------------------------------------------------
sub extract_filename {
    my ($line, $pattern) = @_;
    return $line =~ $pattern ? $1 : '';
}

# -----------------------------------------------------------------------------
# Check if a filename represents a directory
#
# Purpose:
#   Determine if a filename should be treated as a directory based on:
#   1. Lack of file extension
#   2. Not being in the "known files without extensions" list
#
# Parameters:
#   $fileName - filename to check
#
# Returns:
#   1 if filename represents a directory, 0 otherwise
#
# Examples:
#   is_directory("MyFolder")           => 1
#   is_directory("MyFile.m")           => 0
#   is_directory("create_hash_table")  => 0 (known file without extension)
#
# Global Variables:
#   $CASE_INSENSITIVE - affects lookup in %isFile hash
#   %isFile           - case-sensitive known files list
#   %isFile_lc        - case-insensitive known files list
# -----------------------------------------------------------------------------
sub is_directory {
    my ($fileName) = @_;

    # Extract file extension (suffix after last dot)
    my $hasSuffix = $fileName =~ m/\.([^.]+)$/;

    # If it has an extension, it's a file
    return 0 if $hasSuffix;

    # No extension: check if it's a known file
    my $isKnownFile = $CASE_INSENSITIVE
        ? $isFile_lc{lc($fileName)}
        : $isFile{$fileName};

    # If it's a known file, it's not a directory
    return !$isKnownFile;
}

# sortChildrenByFileName:
#
# Purpose:
#   Comparator for sorting entries in children, buildConfigurations, targets,
#   packageProductDependencies, and packageReferences arrays.
#
# Parameters:
#   ($a, $b) - each is a single line string representing an entry. Typical form:
#                "        012345... /* Foo.m */,"
#
# Returns:
#   -1, 0, 1 following Perl comparison semantics.
#
# Sorting behavior:
#   1. Directories sort before files
#   2. Within same type (dir/file), uses natural sorting on filename
#
# Examples:
#   "Models/" < "AppDelegate.m"  (directory before file)
#   "file2.m" < "file10.m"       (natural sort: 2 < 10)
sub sortChildrenByFileName($$)
{
    my ($a, $b) = @_;

    my $aFileName = extract_filename($a, $REGEX_CHILD_ENTRY);
    my $bFileName = extract_filename($b, $REGEX_CHILD_ENTRY);

    my $aIsDirectory = is_directory($aFileName);
    my $bIsDirectory = is_directory($bFileName);
    return $bIsDirectory <=> $aIsDirectory if $aIsDirectory != $bIsDirectory;

    # Natural compare for any filenames (handles numeric substrings correctly).
    return natural_cmp($aFileName, $bFileName);
}

# sortFilesByFileName:
#
# Purpose:
#   Comparator for sorting entries in the files array.
#
# Parameters:
#   ($a, $b) - each is a single line string representing a file entry. Typical form:
#                "        012345... /* Foo.m in Sources */,"
#
# Returns:
#   -1, 0, 1 following Perl comparison semantics.
#
# Sorting behavior:
#   - Extracts filename from comment (text before " in BuildPhase")
#   - Uses natural sorting on filename (no directory priority)
#
# Note:
#   Unlike sortChildrenByFileName, this does NOT prioritize directories,
#   as files arrays typically don't contain directory entries.
sub sortFilesByFileName($$)
{
    my ($a, $b) = @_;

    my $aFileName = extract_filename($a, $REGEX_FILE_ENTRY);
    my $bFileName = extract_filename($b, $REGEX_FILE_ENTRY);

    # Natural compare for any filenames (handles numeric substrings correctly).
    return natural_cmp($aFileName, $bFileName);
}

# -----------------------------------------------------------------------------
# Natural string comparator with case-sensitivity support
#
# Purpose:
#   Compare two strings using natural (alphanumeric) sorting where numeric
#   parts are compared numerically rather than lexically.
#
# Algorithm:
#   1. Split each string into alternating runs of digits and non-digits
#      Example: "file10b" -> ["file", "10", "b"]
#   2. Compare runs pairwise from left to right:
#      - If both runs are numeric: compare as integers
#        * If equal numerically, prefer shorter string (fewer leading zeros)
#        * Example: "01" < "1" (when numeric values equal)
#      - If either run is non-numeric: compare lexically
#        * Use lowercase comparison if $CASE_INSENSITIVE is enabled
#   3. If all common runs are equal, shorter array (fewer parts) sorts first
#
# Parameters:
#   $x, $y - Two strings to compare
#
# Returns:
#   -1 if $x < $y
#    0 if $x == $y
#    1 if $x > $y
#
# Examples:
#   Case-sensitive mode:
#     natural_cmp("file2", "file10")     => -1  (2 < 10)
#     natural_cmp("File", "file")        => -1  ('F' < 'f' in ASCII)
#     natural_cmp("file01", "file1")     => -1  (same value, "01" is longer)
#
#   Case-insensitive mode:
#     natural_cmp("File2", "file10")     => -1  (2 < 10, case ignored)
#     natural_cmp("File", "file")        =>  0  (equal when ignoring case)
#
# Global Variables:
#   $CASE_INSENSITIVE - If true, non-digit runs are compared case-insensitively
# -----------------------------------------------------------------------------
sub natural_cmp {
    my ($x, $y) = @_;
    $x //= '';
    $y //= '';
    return 0 if $x eq $y;

    # Tokenize into digit and non-digit runs. Preserve order.
    # Example: "abc123def45" -> ("abc", "123", "def", "45")
    my @tokens_x = ($x =~ /(\d+|[^\d]+)/g);
    my @tokens_y = ($y =~ /(\d+|[^\d]+)/g);

    while (@tokens_x && @tokens_y) {
        my $part_x = shift @tokens_x;
        my $part_y = shift @tokens_y;

        if ($part_x =~ /^\d+$/ && $part_y =~ /^\d+$/) {
            # Both parts are numeric: compare as integers
            my $num_x = $part_x + 0;
            my $num_y = $part_y + 0;
            if ($num_x != $num_y) {
                return $num_x <=> $num_y;
            }
            # If numeric values equal (e.g. "001" vs "1"), prefer shorter digit run
            # This handles leading zeros: "1" < "01" < "001"
            if (length($part_x) != length($part_y)) {
                return length($part_x) <=> length($part_y);
            }
            next; # equal numeric value and equal length -> continue to next part
        } else {
            # Non-numeric comparison (at least one part is non-numeric):
            if ($CASE_INSENSITIVE) {
                my $lower_x = lc($part_x);
                my $lower_y = lc($part_y);
                if ($lower_x ne $lower_y) {
                    return $lower_x cmp $lower_y;
                }
            } else {
                if ($part_x ne $part_y) {
                    return $part_x cmp $part_y;
                }
            }
            next;
        }
    }

    # If one string has remaining parts, the shorter one (fewer parts) sorts first
    # Example: "file" < "file2" (["file"] vs ["file", "2"])
    return scalar(@tokens_x) <=> scalar(@tokens_y);
}

# -----------------------------------------------------------------------------
# Remove duplicate items while preserving first occurrence order
#
# Purpose:
#   Eliminate duplicate entries from an array while maintaining the order
#   in which unique items first appeared.
#
# Algorithm:
#   Uses a hash to track seen items. The grep function filters out items
#   that have been seen before (where $seen{$_}++ returns a true value).
#
# Parameters:
#   @_ - List of items (typically strings)
#
# Returns:
#   List containing only the first occurrence of each unique item, in
#   their original relative order.
#
# Examples:
#   uniq("a", "b", "a", "c", "b") => ("a", "b", "c")
#   uniq("x", "x", "x")           => ("x")
#   uniq()                        => ()
#
# Reference:
#   https://perlmaven.com/unique-values-in-an-array-in-perl
#
# Note:
#   This is a simple implementation suitable for most cases. For very large
#   arrays or when memory is a concern, consider using List::Util's uniq()
#   function from Perl 5.26+.
# -----------------------------------------------------------------------------
sub uniq {
  my %seen;
  return grep { !$seen{$_}++ } @_;
}

# -----------------------------------------------------------------------------
# Read entire file content into string
#
# Parameters:
#   $file - path to file to read
#
# Returns:
#   String containing entire file content
#
# Dies on error with descriptive message
# -----------------------------------------------------------------------------
sub read_file {
    my ($file) = @_;
    open(my $fh, '<', $file) or die "Could not open $file: $!";
    my $content = do { local $/; <$fh> };
    close($fh) or die "Could not close $file: $!";
    return $content;
}

# -----------------------------------------------------------------------------
# Write content to file atomically using temporary file
#
# Purpose:
#   Safely write content by creating temp file first, then atomically
#   replacing the original. Ensures no data corruption on failure.
#
# Parameters:
#   $file    - path to file to write
#   $content - string content to write
#
# Dies on error with descriptive message. On error, attempts to clean up
# temporary file before dying.
# -----------------------------------------------------------------------------
sub write_file {
    my ($file, $content) = @_;

    my ($fh, $tempFile) = tempfile(
        basename($file) . "-XXXXXXXX",
        DIR => dirname($file),
        UNLINK => 0,
    );

    eval {
        print $fh $content or die "Could not write to $tempFile: $!";
        close($fh) or die "Could not close $tempFile: $!";

        unlink($file) or die "Could not delete $file: $!";
        rename($tempFile, $file) or die "Could not rename $tempFile to $file: $!";
    };

    if ($@) {
        my $error = $@;
        close($fh) if defined fileno($fh);
        unlink($tempFile) if -e $tempFile;
        die "Failed to write $file: $error";
    }
}
