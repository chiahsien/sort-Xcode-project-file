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
import os
import re
import sys
import tempfile
from pathlib import Path

__version__ = "0.1.0"

# ---------------------------------------------------------------------------
# Compiled regex patterns
# ---------------------------------------------------------------------------

# Matches: children = (, buildConfigurations = (, targets = (, etc.
REGEX_ARRAY_START = re.compile(
    r"""^
    (\s*)                           # capture leading whitespace
    (children|buildConfigurations|targets|packageProductDependencies|packageReferences)
    \s* = \s* \( \s*$               # = ( with optional whitespace
    """,
    re.VERBOSE,
)

# Matches: files = (
REGEX_FILES_ARRAY = re.compile(
    r"""^
    (\s*)                           # capture leading whitespace
    files \s* = \s* \( \s*$         # files = (
    """,
    re.VERBOSE,
)

# Matches child/target/config entries: A1B2C3D4E5F6789012345678 /* Name */,
REGEX_CHILD_ENTRY = re.compile(
    r"""^
    \s*                             # optional leading whitespace
    [A-Fa-f0-9]{24}                 # Xcode object ID
    \s+ /\* \s*                     # comment start
    (.+?)                           # capture name (non-greedy)
    \s* \*/ ,                       # comment end and comma
    $
    """,
    re.VERBOSE,
)

# Matches file entries: A1B2C3D4E5F6789012345678 /* Name in Sources */,
REGEX_FILE_ENTRY = re.compile(
    r"""^
    \s*                             # optional leading whitespace
    [A-Fa-f0-9]{24}                 # Xcode object ID
    \s+ /\* \s*                     # comment start
    (.+?)                           # capture filename (non-greedy)
    \s* \*/ \s+ in \s+              # comment end, " in " keyword
    """,
    re.VERBOSE,
)

# Tokenizer for natural sort: splits into digit and non-digit runs
_TOKENIZE = re.compile(r"(\d+|[^\d]+)")

_KNOWN_FILES: set[str] = {"create_hash_table"}
_KNOWN_FILES_LC: set[str] = {f.lower() for f in _KNOWN_FILES}

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
# Natural sort key
#
# Tokenizes a string into digit/non-digit runs and builds a comparison key.
# Digit runs compare numerically; ties broken by string length (shorter first,
# so "1" < "01" < "001"). Non-digit runs compare lexically (or case-folded).
# ---------------------------------------------------------------------------
def natural_sort_key(s: str, case_insensitive: bool = False) -> list[tuple]:
    tokens = _TOKENIZE.findall(s) if s else []
    key: list[tuple] = []
    for token in tokens:
        if token.isdigit():
            key.append((0, int(token), len(token)))
        else:
            text = token.lower() if case_insensitive else token
            key.append((1, text))
    return key


def extract_filename(line: str, pattern: re.Pattern) -> str:
    m = pattern.search(line)
    return m.group(1) if m else ""


def is_directory(filename: str, case_insensitive: bool = False) -> bool:
    if "." in filename:
        return False
    lookup = _KNOWN_FILES_LC if case_insensitive else _KNOWN_FILES
    name = filename.lower() if case_insensitive else filename
    return name not in lookup


def uniq(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result


def children_sort_key(line: str, case_insensitive: bool = False) -> tuple:
    name = extract_filename(line, REGEX_CHILD_ENTRY)
    return (not is_directory(name, case_insensitive), natural_sort_key(name, case_insensitive))


def files_sort_key(line: str, case_insensitive: bool = False) -> tuple:
    name = extract_filename(line, REGEX_FILE_ENTRY)
    return tuple(natural_sort_key(name, case_insensitive))


def read_array_entries(
    lines: list[str],
    start_index: int,
    end_marker: str,
    project_file: Path,
    array_name: str,
) -> tuple[list[str], str, int]:
    entries: list[str] = []
    i = start_index
    escaped_marker = re.escape(end_marker)

    while i < len(lines):
        line = lines[i]
        if re.match(escaped_marker + r"\s*$", line):
            return entries, line, i + 1
        entries.append(line)
        i += 1

    raise RuntimeError(
        f"Unexpected end of file while parsing {array_name} array in {project_file}"
    )


# ---------------------------------------------------------------------------
# Atomic file write using temp file + os.replace()
#
# os.replace() is atomic on POSIX — no unlink before rename needed
# (fixes the data-loss window in the original Perl unlink+rename sequence).
# ---------------------------------------------------------------------------
def write_file(target: Path, content: str) -> None:
    fd, tmp_path = tempfile.mkstemp(
        prefix=f".{target.name}.",
        dir=target.parent,
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, str(target))
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def sort_project_file(
    project_file: Path,
    *,
    case_insensitive: bool = False,
    check_only: bool = False,
    print_warnings: bool = True,
) -> bool:
    content = project_file.read_text(encoding="utf-8")
    lines = content.split("\n")

    output: list[str] = []
    i = 0

    while i < len(lines):
        line = lines[i]

        if REGEX_FILES_ARRAY.match(line):
            indent_match = REGEX_FILES_ARRAY.match(line)
            indent = indent_match.group(1) if indent_match else ""
            output.append(line)
            i += 1

            end_marker = indent + ");"
            array_lines, end_line, next_index = read_array_entries(
                lines, i, end_marker, project_file, "files"
            )
            i = next_index

            unique_lines = uniq(array_lines)
            sorted_lines = sorted(
                unique_lines,
                key=lambda ln: files_sort_key(ln, case_insensitive),
            )
            output.extend(sorted_lines)
            output.append(end_line)

        elif REGEX_ARRAY_START.match(line):
            m = REGEX_ARRAY_START.match(line)
            indent = m.group(1) if m else ""
            array_name = m.group(2) if m else ""
            output.append(line)
            i += 1

            end_marker = indent + ");"
            array_lines, end_line, next_index = read_array_entries(
                lines, i, end_marker, project_file, array_name
            )
            i = next_index

            unique_lines = uniq(array_lines)
            sorted_lines = sorted(
                unique_lines,
                key=lambda ln: children_sort_key(ln, case_insensitive),
            )
            output.extend(sorted_lines)
            output.append(end_line)

        # PBXFrameworksBuildPhase: pass through without sorting (order matters)
        elif "Begin PBXFrameworksBuildPhase section" in line:
            output.append(line)
            i += 1
            while i < len(lines):
                fw_line = lines[i]
                output.append(fw_line)
                i += 1
                if "End PBXFrameworksBuildPhase section" in fw_line:
                    break

        else:
            output.append(line)
            i += 1

    sorted_content = "\n".join(output)

    if check_only:
        return content == sorted_content

    if content != sorted_content:
        write_file(project_file, sorted_content)

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
