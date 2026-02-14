# AGENTS.md — sort-Xcode-project-file

## Project Overview

CLI tool that sorts sections of Xcode `project.pbxproj` files to reduce merge conflicts. Forked from WebKit's sort-Xcode-project-file with extended functionality.

- **Script**: `sort-Xcode-project-file.py` (~503 lines, Python 3.9+, stdlib only)

**License:** MIT

## Build / Run / Test Commands

### Run the script
```bash
python3 sort-Xcode-project-file.py <path-to-project.pbxproj>
python3 sort-Xcode-project-file.py <path-to-project.xcodeproj>
python3 sort-Xcode-project-file.py --case-insensitive <path>
python3 sort-Xcode-project-file.py --check <path>         # CI mode: exit 0 if sorted
python3 sort-Xcode-project-file.py -r <directory>          # Recursive search
cat project.pbxproj | python3 sort-Xcode-project-file.py - > sorted.pbxproj  # Stdin/stdout
```

### Tests
```bash
python3 -m unittest discover tests -v    # Run all 70 tests
```

### Verify syntax
```bash
python3 -c "import py_compile; py_compile.compile('sort-Xcode-project-file.py', doraise=True)"
```

## Architecture

```
sort-Xcode-project-file.py    # Everything lives here (~503 lines)
├── Regex patterns             # re.compile with re.VERBOSE (lines 31-76)
├── natural_sort_key()         # Natural (alphanumeric) sort key (line 115)
├── extract_filename()         # Regex-based filename extraction (line 134)
├── is_directory()             # Heuristic: no extension = directory (line 140)
├── uniq()                     # Deduplicate preserving order (line 153)
├── children_sort_key()        # Sort key: dirs first, then natural sort (line 164)
├── files_sort_key()           # Sort key: natural sort only (line 170)
├── read_array_entries()       # Extract array contents between ( and ); (line 176)
├── write_file()               # Atomic write via tempfile + os.replace() (line 210)
├── sort_project_content()     # Core sorting logic (pure function) (line 234)
├── sort_project_file()        # Read → sort_project_content → write (line 315)
├── build_parser()             # argparse CLI definition (line 343)
└── main()                     # Entry point: parse args, process files (line 409)
```

### Test suite (`tests/`)

```
tests/
├── __init__.py                    # Package marker
├── _helpers.py                    # importlib-based import of hyphenated script name
├── test_natural_sort.py           # 15 tests for natural_sort_key()
├── test_is_directory.py           # 9 tests for is_directory()
├── test_dedup.py                  # 7 tests for uniq()
├── test_extract_filename.py       # 5 tests for extract_filename()
├── test_sort_project.py           # 16 integration tests (sort, idempotency, check mode, edge cases)
├── test_cli.py                    # 19 CLI tests via subprocess (exit codes, flags, stdin, recursive)
└── fixtures/
    ├── basic_unsorted.pbxproj     # Unsorted input fixture
    ├── basic_sorted.pbxproj       # Expected output (case-sensitive)
    ├── basic_ci_sorted.pbxproj    # Expected output (case-insensitive)
    ├── with_frameworks.pbxproj    # PBXFrameworksBuildPhase fixture
    ├── with_frameworks_sorted.pbxproj
    ├── with_duplicates.pbxproj    # Duplicate entries fixture
    ├── with_duplicates_sorted.pbxproj
    ├── empty_arrays.pbxproj       # Empty arrays fixture
    ├── empty_arrays_sorted.pbxproj
    ├── with_spm_packages.pbxproj  # SPM packageProductDependencies/packageReferences
    ├── with_spm_packages_sorted.pbxproj
    ├── with_special_chars.pbxproj # Filenames with +, long names
    ├── with_special_chars_sorted.pbxproj
    ├── with_multi_fw_targets.pbxproj     # Multiple FW build phases
    ├── with_multi_fw_targets_sorted.pbxproj
    ├── with_nested_groups.pbxproj        # Nested children arrays, empty packageReferences
    └── with_nested_groups_sorted.pbxproj
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

## Critical Constraints

1. **No external dependencies** — must work with stock Python 3.9+ on macOS
2. **PBXFrameworksBuildPhase must never be sorted** — framework link order is significant
3. **Atomic file writes** — never leave a `.pbxproj` in a corrupted state
4. **Backward compatible** — default behavior (case-sensitive) must match original WebKit script
5. **The script modifies files in-place** — always test against a copy

## CLI Flags Reference

| Flag | Effect |
|---|---|
| `-` | Read from stdin, write to stdout |
| `--case-insensitive` | Case-insensitive natural sort |
| `--case-sensitive` | Force case-sensitive (default) |
| `--check` | Exit 0 if sorted, exit 1 if not (no modification) |
| `-r` / `--recursive` | Recursively find and sort all `project.pbxproj` under directories |
| `--version` | Show version and exit |
| `-w` / `--no-warnings` | Suppress warning messages |
| `-h` / `--help` | Show usage and exit |

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
