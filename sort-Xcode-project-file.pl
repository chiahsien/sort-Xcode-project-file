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

# Script to case-sensitive sort certain sections and arrays in Xcode project.pbxproj files.
# Enhancements compared to original:
# - Accepts lowercase hex object IDs (more robust)
# - Adds sorting for "Begin ... section" blocks such as PBXFileReference, PBXBuildFile, PBXGroup,
#   XCBuildConfiguration, PBXVariantGroup, PBXReferenceProxy, PBXContainerItemProxy, PBXTargetDependency.
# - More robust block parsing that balances braces to support multi-line entries.
#
# NOTE: This script deliberately does NOT sort buildPhases arrays (their order is build-order-sensitive).
# Use caution adding more automatic sorting behaviour.

use strict;
use warnings;

use File::Basename;
use File::Spec;
use File::Temp qw(tempfile);
use Getopt::Long;

# Allow list: names of "Begin ... section" sections we will parse and sort block entries for.
# These are safe-to-sort sections (reordering entries shouldn't change Xcode behaviour).
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
my %isFile = map { $_ => 1 } qw(
    create_hash_table
);

my $printWarnings = 1;
my $showHelp;

my $getOptionsResult = GetOptions(
    'h|help'         => \$showHelp,
    'w|warnings!'    => \$printWarnings,
);

if (scalar(@ARGV) == 0 && !$showHelp) {
    print STDERR "ERROR: No Xcode project files (project.pbxproj) listed on command-line.\n";
    undef $getOptionsResult;
}

if (!$getOptionsResult || $showHelp) {
    print STDERR <<'__END__';
Usage: sort-Xcode-project-file.pl [options] path/to/project.pbxproj [path/to/project.pbxproj ...]
  -h|--help           show this help message
  -w|--[no-]warnings  show or suppress warnings (default: show warnings)

This script sorts certain arrays and sections inside project.pbxproj files to
reduce spurious diffs in version control. It preserves ordering for build-phase
arrays that are order-sensitive (e.g. buildPhases).
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

    my ($OUT, $tempFileName) = tempfile(
        basename($projectFile) . "-XXXXXXXX",
        DIR => dirname($projectFile),
        UNLINK => 0,
    );

    # Clean up temp file in case of die()
    $SIG{__DIE__} = sub {
        close(IN) if defined fileno(IN);
        close($OUT) if defined fileno($OUT);
        unlink($tempFileName);
    };

    open(IN, "< $projectFile") || die "Could not open $projectFile: $!";
    while (my $line = <IN>) {
        # Sort files section (array named files = (...); ).
        if ($line =~ /^(\s*)files = \(\s*$/) {
            print $OUT $line;
            my $endMarker = $1 . ");";
            my @files;
            while (my $fileLine = <IN>) {
                if ($fileLine =~ /^\Q$endMarker\E\s*$/) {
                    $endMarker = $fileLine;
                    last;
                }
                push @files, $fileLine;
            }

            # Remove duplicate lines then sort.
            my @uniqueLines = uniq(@files);
            print $OUT sort sortFilesByFileName @uniqueLines;
            print $OUT $endMarker;
        }
        # Sort children, buildConfigurations, targets, packageProductDependencies, and packageReferences sections (array-form).
        elsif ($line =~ /^(\s*)(children|buildConfigurations|targets|packageProductDependencies|packageReferences) = \(\s*$/) {
            print $OUT $line;
            my $endMarker = $1 . ");";
            my @children;
            while (my $childLine = <IN>) {
                if ($childLine =~ /^\Q$endMarker\E\s*$/) {
                    $endMarker = $childLine;
                    last;
                }
                push @children, $childLine;
            }

            # Remove duplicate lines then sort.
            my @uniqueLines = uniq(@children);
            print $OUT sort sortChildrenByFileName @uniqueLines;
            print $OUT $endMarker;
        }
        # Handle "Begin ... section" blocks; if section is in our sortable list, parse entries and sort by name
        elsif ($line =~ /Begin\s+(\S+)\s+section/) {
            my $sectionName = $1;
            print $OUT $line; # print the Begin ... line as-is

            # Read everything until the corresponding End ... section line
            if ($sortable_sections{$sectionName}) {
                # We will parse entries inside this section and sort them.
                my @entries;
                my $prefix = ''; # prefix lines that precede an entry (comments, blank lines)
                while (my $sectionLine = <IN>) {
                    # If we reached the End ... section, break and print end marker later
                    if ($sectionLine =~ /End\s+\Q$sectionName\E\s+section/) {
                        # print sorted entries then the end marker
                        my @unique = uniq(@entries);
                        print $OUT sort sortBlocksByName @unique;
                        print $OUT $sectionLine;
                        last;
                    }

                    # Detect a block entry that begins with an object id comment, e.g. "  123ABC... /* Name */ = {"
                    if ($sectionLine =~ /^\s*([A-Fa-f0-9]{24})\s+\/\*\s*(.+?)\s*\*\/\s*=\s*(\{)?/) {
                        # Start a new entry; include any prefix lines (comments/blank) that preceded it
                        my $entry = $prefix . $sectionLine;
                        $prefix = '';

                        # If there's an opening brace, the entry may be multi-line. Balance braces.
                        if (index($sectionLine, '{') != -1) {
                            my $open = () = $sectionLine =~ /\{/g;
                            my $close = () = $sectionLine =~ /\}/g;
                            my $braceCount = $open - $close;
                            while ($braceCount > 0) {
                                my $nl = <IN>;
                                last unless defined $nl;
                                $entry .= $nl;
                                $open += () = $nl =~ /\{/g;
                                $close += () = $nl =~ /\}/g;
                                $braceCount = $open - $close;
                            }
                        }
                        # If not a brace block, the entry likely ends on this line (single-line entry); we already have it.
                        push @entries, $entry;
                    } else {
                        # Not the start of an entry: accumulate into prefix to attach to next entry,
                        # preserving comments and spacing that belong to the following entry.
                        $prefix .= $sectionLine;
                    }
                }
            } else {
                # Not a section we automatically sort: passthrough until End ... section (preserve original order)
                while (my $sectionLine = <IN>) {
                    print $OUT $sectionLine;
                    if ($sectionLine =~ /End\s+\Q$sectionName\E\s+section/) {
                        last;
                    }
                }
            }
        }
        # Ignore whole PBXFrameworksBuildPhase section (preserve original ordering)
        elsif ($line =~ /^(.*)Begin PBXFrameworksBuildPhase section(.*)$/) {
            print $OUT $line;
            while (my $ignoreLine = <IN>) {
                print $OUT $ignoreLine;
                if ($ignoreLine =~ /^(.*)End PBXFrameworksBuildPhase section(.*)$/) {
                    last;
                }
            }
        }
        # Other lines: passthrough
        else {
            print $OUT $line;
        }
    }
    close(IN);
    close($OUT);

    unlink($projectFile) || die "Could not delete $projectFile: $!";
    rename($tempFileName, $projectFile) || die "Could not rename $tempFileName to $projectFile: $!";
}

exit 0;

# -----------------------------------------------------------------------------
# Comparator used to sort block entries (Begin ... section entries).
# Tries to extract a human-friendly name for sorting:
# 1) comment after object id: "/* Name */"
# 2) name = "..." inside the block
# 3) path = "..." inside the block
# 4) fallback: whole entry string
# Special handling for UnifiedSourceN names: numeric compare on trailing number.
# -----------------------------------------------------------------------------
sub sortBlocksByName($$)
{
    my ($a, $b) = @_;
    my $aName = extract_name_from_block($a);
    my $bName = extract_name_from_block($b);

    # Handle directories vs files as in children sorting: treat items without suffix as directories
    my $aSuffix = $1 if $aName =~ m/\.([^.]+)$/;
    my $bSuffix = $1 if $bName =~ m/\.([^.]+)$/;
    my $aIsDirectory = !$aSuffix && !$isFile{$aName};
    my $bIsDirectory = !$bSuffix && !$isFile{$bName};
    return $bIsDirectory <=> $aIsDirectory if $aIsDirectory != $bIsDirectory;

    if ($aName =~ /^UnifiedSource(\d+)/ && $bName =~ /^UnifiedSource(\d+)/) {
        my $aNumber = $1 if $aName =~ /^UnifiedSource(\d+)/;
        my $bNumber = $1 if $bName =~ /^UnifiedSource(\d+)/;
        return $aNumber <=> $bNumber if $aNumber != $bNumber;
    }

    # Default: case-sensitive lexical comparison. Uncomment to enable case-insensitive:
    # return lc($aName) cmp lc($bName) if lc($aName) ne lc($bName);
    return $aName cmp $bName;
}

# Extract a name from a block entry string.
sub extract_name_from_block {
    my ($block) = @_;
    # Try to find comment after object id: "/* Name */"
    if ($block =~ /^\s*[A-Fa-f0-9]{24}\s+\/\*\s*(.+?)\s*\*\/\s*=/m) {
        return $1;
    }
    # Fallback: look for name = "..."
    if ($block =~ /name\s*=\s*"(.*?)"/m) {
        return $1;
    }
    # Fallback: look for path = "..."
    if ($block =~ /path\s*=\s*"(.*?)"/m) {
        return $1;
    }
    # Last resort: return the first non-whitespace line trimmed
    if ($block =~ /^\s*(\S.*)$/m) {
        return $1;
    }
    return $block;
}

# -----------------------------------------------------------------------------
# Existing comparators for array-style entries (files / children).
# Updated regex to accept lowercase hex IDs too.
# -----------------------------------------------------------------------------
sub sortChildrenByFileName($$)
{
    my ($a, $b) = @_;
    my $aFileName = $1 if $a =~ /^\s*[A-Fa-f0-9]{24}\s+\/\*\s*(.+?)\s*\*\/,$/;
    my $bFileName = $1 if $b =~ /^\s*[A-Fa-f0-9]{24}\s+\/\*\s*(.+?)\s*\*\/,$/;
    my $aSuffix = $1 if $aFileName =~ m/\.([^.]+)$/;
    my $bSuffix = $1 if $bFileName =~ m/\.([^.]+)$/;
    my $aIsDirectory = !$aSuffix && !$isFile{$aFileName};
    my $bIsDirectory = !$bSuffix && !$isFile{$bFileName};
    return $bIsDirectory <=> $aIsDirectory if $aIsDirectory != $bIsDirectory;
    if ($aFileName =~ /^UnifiedSource\d+/ && $bFileName =~ /^UnifiedSource\d+/) {
        my $aNumber = $1 if $aFileName =~ /^UnifiedSource(\d+)/;
        my $bNumber = $1 if $bFileName =~ /^UnifiedSource(\d+)/;
        return $aNumber <=> $bNumber if $aNumber != $bNumber;
    }
    # Uncomment below line to have case-insensitive sorting.
    # return lc($aFileName) cmp lc($bFileName) if lc($aFileName) ne lc($bFileName);
    return $aFileName cmp $bFileName;
}

sub sortFilesByFileName($$)
{
    my ($a, $b) = @_;
    my $aFileName = $1 if $a =~ /^\s*[A-Fa-f0-9]{24}\s+\/\*\s*(.+?)\s*\*\/\s+in\s+/;
    my $bFileName = $1 if $b =~ /^\s*[A-Fa-f0-9]{24}\s+\/\*\s*(.+?)\s*\*\/\s+in\s+/;
    if ($aFileName =~ /^UnifiedSource\d+/ && $bFileName =~ /^UnifiedSource\d+/) {
        my $aNumber = $1 if $aFileName =~ /^UnifiedSource(\d+)/;
        my $bNumber = $1 if $bFileName =~ /^UnifiedSource(\d+)/;
        return $aNumber <=> $bNumber if $aNumber != $bNumber;
    }
    # Uncomment below line to have case-insensitive sorting.
    # return lc($aFileName) cmp lc($bFileName) if lc($aFileName) ne lc($bFileName);
    return $aFileName cmp $bFileName;
}

# Subroutine to remove duplicate items in an array while preserving first occurrence order.
# https://perlmaven.com/unique-values-in-an-array-in-perl
sub uniq {
  my %seen;
  return grep { !$seen{$_}++ } @_;
}
