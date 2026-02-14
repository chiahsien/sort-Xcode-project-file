#!/usr/bin/env python3

# Copyright (C) 2026 Nelson.
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
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER AND CONTRIBUTORS "AS IS" AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY
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
#   --check               exit 0 if sorted, exit 1 if unsorted (no file modification)
#   --version             show version and exit
#   -h, --help            show help
#   -w, --no-warnings     suppress warnings
#
# NOTE: Build-phase order-sensitive arrays (e.g., buildPhases) are NOT sorted by this script.

import argparse
import sys
from pathlib import Path

__version__ = "0.1.0"

# ---------------------------------------------------------------------------
# Usage text — matches Perl version's format, printed to stderr with exit 1
# ---------------------------------------------------------------------------
_USAGE_TEXT = """\
Usage: sort-Xcode-project-file.py [options] path/to/project.pbxproj [path/to/project.pbxproj ...]
  -h, --help              show this help message
  -w, --no-warnings       suppress warnings (default: show warnings)
  --case-insensitive      enable case-insensitive sorting (default: disabled)
  --case-sensitive        explicit alias to force case-sensitive sorting
  --check                 check if files are sorted (exit 0 = sorted, exit 1 = unsorted)
  --version               show version and exit

Notes:
  - Default behavior is case-sensitive sorting (original behavior).
  - Use --case-insensitive to enable case-insensitive natural sorting
"""


# ---------------------------------------------------------------------------
# Stub: sort_project_file
#
# Purpose:
#   Placeholder for the core sorting logic (Phase 2). Currently a no-op
#   that will be replaced with the full state machine port.
#
# Parameters:
#   project_file   - path to project.pbxproj file (Path object)
#   case_insensitive - whether to use case-insensitive sorting
#   check_only     - if True, compare but don't write (Phase 2)
#   print_warnings - whether to print warnings to stderr
#
# Returns:
#   True if file was already sorted (or was sorted successfully),
#   False if file needed sorting and --check was used
# ---------------------------------------------------------------------------
def sort_project_file(
    project_file: Path,
    *,
    case_insensitive: bool = False,
    check_only: bool = False,
    print_warnings: bool = True,
) -> bool:
    # TODO: Phase 2 — port sort logic from Perl
    return True


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="sort-Xcode-project-file.py",
        add_help=False,  # We handle --help ourselves to match Perl exit code
    )

    case_group = parser.add_mutually_exclusive_group()
    case_group.add_argument(
        "--case-insensitive",
        action="store_true",
        default=False,
        help="enable case-insensitive sorting (default: disabled)",
    )
    case_group.add_argument(
        "--case-sensitive",
        action="store_true",
        default=False,
        help="explicit alias to force case-sensitive sorting",
    )

    # Warnings: -w / --no-warnings suppresses (default: warnings ON)
    parser.add_argument(
        "-w", "--no-warnings",
        action="store_true",
        default=False,
        help="suppress warnings (default: show warnings)",
    )

    # Custom --help: Perl prints to stderr and exits 1 (argparse defaults to stdout/exit 0)
    parser.add_argument(
        "-h", "--help",
        action="store_true",
        default=False,
        help="show this help message",
    )

    # Check mode: exit 0 if sorted, exit 1 if unsorted (no file modification)
    parser.add_argument(
        "--check",
        action="store_true",
        default=False,
        help="check if files are sorted (exit 0 = sorted, exit 1 = unsorted)",
    )

    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {__version__}",
    )

    parser.add_argument(
        "files",
        nargs="*",
        metavar="project.pbxproj",
        help="Xcode project.pbxproj file(s) to sort",
    )

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.help:
        print(_USAGE_TEXT, end="", file=sys.stderr)
        return 1

    if not args.files:
        print(
            "ERROR: No Xcode project files (project.pbxproj) listed on command-line.",
            file=sys.stderr,
        )
        print(_USAGE_TEXT, end="", file=sys.stderr)
        return 1

    case_insensitive = args.case_insensitive
    print_warnings = not args.no_warnings
    check_only = args.check

    all_sorted = True

    for project_file_str in args.files:
        project_file = Path(project_file_str)

        if project_file.name.endswith(".xcodeproj"):
            project_file = project_file / "project.pbxproj"

        if project_file.name != "project.pbxproj":
            if print_warnings:
                print(
                    f"WARNING: Not an Xcode project file: {project_file}",
                    file=sys.stderr,
                )
            continue

        if not project_file.is_file():
            print(
                f"ERROR: File not found: {project_file}",
                file=sys.stderr,
            )
            continue

        was_sorted = sort_project_file(
            project_file,
            case_insensitive=case_insensitive,
            check_only=check_only,
            print_warnings=print_warnings,
        )

        if not was_sorted:
            all_sorted = False

    if check_only and not all_sorted:
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
