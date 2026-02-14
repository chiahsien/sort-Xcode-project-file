#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Nelson. See LICENSE file for details.
#
# Based on WebKit's sort-Xcode-project-file (BSD-licensed).

"""Sort sections of Xcode project.pbxproj files to reduce merge conflicts.

Sorts children, files, targets, buildConfigurations, packageProductDependencies,
and packageReferences arrays using natural (human) sort order. Removes duplicate
entries and preserves PBXFrameworksBuildPhase order (link order matters).

Default sorting is case-sensitive. Use ``--case-insensitive`` to fold case.
Build-phase order-sensitive arrays (e.g. buildPhases) are NOT sorted.
"""

import argparse
import os
import re
import sys
import tempfile
from pathlib import Path

__version__ = "1.0.0"

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
# ---------------------------------------------------------------------------
def natural_sort_key(s: str, case_insensitive: bool = False) -> list[tuple]:
    """Build a sort key that orders strings in natural (human) order.

    Tokenizes *s* into digit and non-digit runs.  Digit runs compare
    numerically; ties are broken by string length so that fewer leading
    zeros sort first (``"1" < "01" < "001"``).  Non-digit runs compare
    lexicographically (or case-folded when *case_insensitive* is True).
    """
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
    """Return the captured filename from *line* using *pattern*, or ``""``."""
    m = pattern.search(line)
    return m.group(1) if m else ""


def is_directory(filename: str, case_insensitive: bool = False) -> bool:
    """Heuristic: a name without a file extension is treated as a directory.

    Names listed in ``_KNOWN_FILES`` are exceptions (known to be files
    despite having no extension, e.g. ``create_hash_table``).
    """
    if "." in filename:
        return False
    lookup = _KNOWN_FILES_LC if case_insensitive else _KNOWN_FILES
    name = filename.lower() if case_insensitive else filename
    return name not in lookup


def uniq(items: list[str]) -> list[str]:
    """Deduplicate *items* by exact string match, preserving first occurrence order."""
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result


def children_sort_key(line: str, case_insensitive: bool = False) -> tuple:
    """Sort key for children/targets/configs: directories first, then natural sort."""
    name = extract_filename(line, REGEX_CHILD_ENTRY)
    return (not is_directory(name, case_insensitive), natural_sort_key(name, case_insensitive))


def files_sort_key(line: str, case_insensitive: bool = False) -> tuple:
    """Sort key for build-phase file entries: natural sort only."""
    name = extract_filename(line, REGEX_FILE_ENTRY)
    return tuple(natural_sort_key(name, case_insensitive))


def read_array_entries(
    lines: list[str],
    start_index: int,
    end_marker: str,
    project_file: Path,
    array_name: str,
) -> tuple[list[str], str, int]:
    """Collect array body lines from *start_index* until *end_marker* is found.

    Returns:
        A tuple of (entries, closing_line, next_index).

    Raises:
        RuntimeError: If EOF is reached before the closing marker.
    """
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
# Atomic file write
# ---------------------------------------------------------------------------
def write_file(target: Path, content: str) -> None:
    """Write *content* to *target* atomically via a temp file and ``os.replace()``.

    On POSIX, ``os.replace()`` is atomic — there is no window where the
    target file is missing.  The temp file is cleaned up on any failure.
    """
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
    """Sort arrays in *project_file* in-place and return whether it was already sorted.

    When *check_only* is True the file is not modified; the return value
    indicates whether the content is already in sorted order.
    """
    content = project_file.read_text(encoding="utf-8")
    lines = content.split("\n")

    output: list[str] = []
    i = 0

    while i < len(lines):
        line = lines[i]

        files_match = REGEX_FILES_ARRAY.match(line)
        if files_match:
            indent = files_match.group(1)
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
            continue

        array_match = REGEX_ARRAY_START.match(line)
        if array_match:
            indent = array_match.group(1)
            array_name = array_match.group(2)
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
            continue

        # PBXFrameworksBuildPhase: pass through without sorting (order matters)
        if "Begin PBXFrameworksBuildPhase section" in line:
            output.append(line)
            i += 1
            while i < len(lines):
                fw_line = lines[i]
                output.append(fw_line)
                i += 1
                if "End PBXFrameworksBuildPhase section" in fw_line:
                    break
            continue

        output.append(line)
        i += 1

    sorted_content = "\n".join(output)

    if check_only:
        return content == sorted_content

    if content != sorted_content:
        write_file(project_file, sorted_content)

    return True


def build_parser() -> argparse.ArgumentParser:
    """Create the CLI argument parser."""
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

    parser.add_argument(
        "-w", "--no-warnings",
        action="store_true",
        default=False,
        help="suppress warnings (default: show warnings)",
    )

    # Custom --help: prints to stderr and exits 1 (matching Perl behavior)
    parser.add_argument(
        "-h", "--help",
        action="store_true",
        default=False,
        help="show this help message",
    )

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
    """Entry point. Parse arguments, process each file, and return an exit code."""
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
