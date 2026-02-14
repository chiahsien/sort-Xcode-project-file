# AGENTS.md — sort-Xcode-project-file

## Project Overview

CLI tool that sorts sections of Xcode `project.pbxproj` files to reduce merge conflicts. Forked from WebKit's sort-Xcode-project-file with extended functionality.

Available in two versions (producing byte-for-byte identical output):
- **Python 3** (primary): `sort-Xcode-project-file.py` (~423 lines)
- **Perl 5** (legacy): `sort-Xcode-project-file.pl` (~593 lines)

**License:** MIT (file headers carry BSD from original WebKit; LICENSE file is MIT)

## Build / Run / Test Commands

### Run the script (Python — primary)
```bash
python3 sort-Xcode-project-file.py <path-to-project.pbxproj>
python3 sort-Xcode-project-file.py <path-to-project.xcodeproj>
python3 sort-Xcode-project-file.py --case-insensitive <path>
python3 sort-Xcode-project-file.py --check <path>         # CI mode: exit 0 if sorted
```

### Run the script (Perl — legacy)
```bash
perl sort-Xcode-project-file.pl <path-to-project.pbxproj>
```

### Tests
```bash
python3 -m unittest discover tests -v    # Run all 54 tests
python3 tests/cross_validate.py          # Cross-validate Perl vs Python output (requires perl)
```

### Verify syntax
```bash
python3 -c "import py_compile; py_compile.compile('sort-Xcode-project-file.py', doraise=True)"
perl -c sort-Xcode-project-file.pl
```

## Architecture

### Python version (`sort-Xcode-project-file.py`)

```
sort-Xcode-project-file.py    # Everything lives here
├── CLI parsing                # argparse (lines 42-110)
├── Main loop                  # Iterates args.files (lines 112-140)
├── Regex patterns             # re.compile with re.VERBOSE (lines 54-90)
├── sort_project_file()        # Core: read → parse → sort → write (lines 150-230)
├── read_array_entries()       # Extract array contents between ( and ); (lines 240-260)
├── extract_filename()         # Regex-based filename extraction (lines 270-280)
├── is_directory()             # Heuristic: no extension = directory (lines 290-310)
├── children_sort_key()        # Sort key: dirs first, then natural sort (lines 320-330)
├── files_sort_key()           # Sort key: natural sort only (lines 340-350)
├── natural_sort_key()         # Natural (alphanumeric) sort key (lines 360-390)
├── uniq()                     # Deduplicate preserving order (lines 400-410)
└── write_file()               # Atomic write via tempfile + os.replace() (lines 415-423)
```

### Test suite (`tests/`)

```
tests/
├── __init__.py                    # Package marker
├── _helpers.py                    # importlib-based import of hyphenated script name
├── test_natural_sort.py           # 15 tests for natural_sort_key()
├── test_is_directory.py           # 7 tests for is_directory()
├── test_dedup.py                  # 7 tests for uniq()
├── test_extract_filename.py       # 5 tests for extract_filename()
├── test_sort_project.py           # 9 integration tests (sort, idempotency, check mode)
├── test_cli.py                    # 12 CLI tests via subprocess (exit codes, flags)
├── cross_validate.py              # Standalone cross-validation script (Perl vs Python)
└── fixtures/
    ├── basic_unsorted.pbxproj     # Unsorted input fixture
    ├── basic_sorted.pbxproj       # Expected output (case-sensitive)
    ├── basic_ci_sorted.pbxproj    # Expected output (case-insensitive)
    ├── with_frameworks.pbxproj    # PBXFrameworksBuildPhase fixture
    ├── with_frameworks_sorted.pbxproj
    ├── with_duplicates.pbxproj    # Duplicate entries fixture
    ├── with_duplicates_sorted.pbxproj
    ├── empty_arrays.pbxproj       # Empty arrays fixture
    └── empty_arrays_sorted.pbxproj
```

### Key Regex Patterns (compiled, module level)
| Variable | Matches |
|---|---|
| `REGEX_ARRAY_START` | `children = (`, `buildConfigurations = (`, `targets = (`, etc. |
| `REGEX_FILES_ARRAY` | `files = (` |
| `REGEX_CHILD_ENTRY` | `HEXID /* Name */,` |
| `REGEX_FILE_ENTRY` | `HEXID /* Name in BuildPhase */,` |

### Sorting Rules
- **children/targets/configs/packages**: Directories sort before files; natural sort within groups
- **files arrays**: Natural sort only (no directory priority)
- **PBXFrameworksBuildPhase**: Preserved as-is (NOT sorted — order matters)
- **Duplicates**: Removed before sorting (first occurrence kept)

## Code Style Guidelines (Python)

### Imports — Stdlib Only
Only use Python standard library modules. Current imports:
- `argparse`, `os`, `re`, `sys`, `tempfile`, `pathlib.Path`

Do NOT add pip dependencies. This script must run with stock Python on macOS.

### Naming Conventions
| Element | Convention | Examples |
|---|---|---|
| Functions | `snake_case` | `sort_project_file`, `write_file`, `extract_filename` |
| Sort key functions | `snake_case` | `children_sort_key`, `files_sort_key` |
| Local variables | `snake_case` | `project_file`, `end_marker` |
| Constants/regex | `UPPER_SNAKE_CASE` | `REGEX_ARRAY_START`, `KNOWN_FILES` |
| Module-level sets | `UPPER_SNAKE_CASE` | `KNOWN_FILES`, `KNOWN_FILES_LC` |

### Regex Style
- Use `re.compile(..., re.VERBOSE)` stored in module-level constants
- Use verbose mode with comments explaining each part
- Match the same patterns as the Perl version exactly

### Documentation Style
Every function should have a docstring:
```python
def function_name(param: type) -> return_type:
    """Brief description.

    Purpose:
        What it does and why.

    Args:
        param: Description.

    Returns:
        What is returned.
    """
```

### Error Handling
- Use `sys.exit(1)` for fatal errors with message to stderr
- Use `try/except/finally` for recoverable operations (see `write_file`)
- Use `print(..., file=sys.stderr)` for warnings, gated by `print_warnings` flag
- Clean up temp files in error paths

### File I/O
- Read: `Path.read_text(encoding="utf-8")`
- Write: **always atomic** — write to temp file, then `os.replace()` over original
- Use `tempfile.mkstemp()` for temp files; handle cleanup on failure
- `os.replace()` is truly atomic on POSIX (no `unlink` needed)

### Formatting
- Indentation: 4 spaces (no tabs)
- Line length: soft limit ~100 characters
- Blank line between logical sections
- Separator comments (`# ---...---`) between function groups
- Type hints using Python 3.9+ built-in generics (`list[str]`, not `List[str]`)

## Code Style Guidelines (Perl — legacy)

### Perl Pragmas (mandatory)
```perl
use strict;
use warnings;
```

### Modules — Core Only
Only use Perl core modules: `File::Basename`, `File::Spec`, `File::Temp`, `Getopt::Long`

### Naming Conventions
| Element | Convention | Examples |
|---|---|---|
| Subroutines | `snake_case` | `sort_project_file`, `read_file` |
| Sort comparators | `camelCase` (legacy) | `sortChildrenByFileName` |
| Local variables | `$camelCase` | `$projectFile`, `$aFileName` |
| Global flags | `$UPPER_CASE` | `$CASE_INSENSITIVE` |
| Constants/regex | `$REGEX_UPPER_CASE` | `$REGEX_ARRAY_START` |

## Critical Constraints

1. **No external dependencies** — must work with stock Python/Perl on macOS
2. **PBXFrameworksBuildPhase must never be sorted** — framework link order is significant
3. **Atomic file writes** — never leave a `.pbxproj` in a corrupted state
4. **Backward compatible** — default behavior (case-sensitive) must match original WebKit script
5. **The script modifies files in-place** — always test against a copy
6. **Output parity** — Python and Perl versions must produce byte-for-byte identical output

## CLI Flags Reference

| Flag | Python | Perl | Effect |
|---|---|---|---|
| `--case-insensitive` | ✅ | ✅ | Case-insensitive natural sort |
| `--case-sensitive` | ✅ | ✅ | Force case-sensitive (default) |
| `--check` | ✅ | ❌ | Exit 0 if sorted, exit 1 if not (no modification) |
| `--version` | ✅ | ❌ | Show version and exit |
| `-w` / `--no-warnings` | ✅ | ✅ | Suppress warning messages |
| `-h` / `--help` | ✅ | ✅ | Show usage and exit |

## Known Limitations & Improvement Plan

See [`docs/improvement-plan.md`](docs/improvement-plan.md) for a prioritized list of improvements.

## Commit Style

Based on git history, use conventional commits:
```
fix: escape special characters in regex comments
feat: enhance sorting functionality with case-insensitive option
refactor: improve variable scope management and extract helper functions
docs: add comprehensive POD documentation and improve inline comments
style: standardize code style for consistency
test: add comprehensive test suite for Python port
```
Prefixes: `fix:`, `feat:`, `refactor:`, `docs:`, `style:`, `test:`
