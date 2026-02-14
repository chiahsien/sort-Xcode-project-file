# Migration Plan: Perl → Python 3

Created: 2026-02-14

## Goal

Rewrite `sort-Xcode-project-file.pl` (Perl 5) into `sort-Xcode-project-file.py` (Python 3), with:
- **Zero pip dependencies** — stdlib only
- **Identical output** — given the same input, both versions must produce byte-for-byte identical results
- **Zero setup** — runs on stock macOS with Xcode CLT installed

## Target Environment

| Item | Value |
|------|-------|
| Minimum Python | **3.9** (macOS ships 3.9.6 via Xcode CLT since Monterey 12 through Sequoia 15) |
| Shebang | `#!/usr/bin/env python3` |
| OS | macOS only (POSIX `os.replace()` is atomic) |
| Prerequisite | Xcode Command Line Tools (`xcode-select --install`) |

## Stdlib Modules to Use

| Module | Replaces (Perl) | Purpose |
|--------|------------------|---------|
| `argparse` | `Getopt::Long` | CLI argument parsing |
| `re` | Perl regex | Compiled regex patterns |
| `os` | — | `os.replace()` for atomic rename |
| `pathlib` | `File::Basename`, `File::Spec` | Path manipulation |
| `tempfile` | `File::Temp` | Atomic write via temp file |
| `sys` | — | `sys.stderr`, `sys.exit()` |

No other modules needed. No `typing` import required (use Python 3.9+ built-in generics: `list[str]`, `tuple[...]`).

---

## Phase 1: Scaffold & CLI

### 1.1 Create `sort_xcode_project_file.py`

- Shebang: `#!/usr/bin/env python3`
- License header (same BSD + MIT dual license)
- `if __name__ == "__main__":` entry point

### 1.2 Port CLI parsing (Perl lines 107-156)

| Perl | Python |
|------|--------|
| `GetOptions('h\|help' => ...)` | `argparse.ArgumentParser()` |
| `'case-insensitive!'` | `--case-insensitive` / `--case-sensitive` (mutually exclusive group) |
| `'w\|warnings!'` | `--no-warnings` / `-w` |
| `exit 1` on no args | `parser.error()` |

**Behavioral parity checklist:**
- [ ] No args → error message to stderr, exit 1
- [ ] `--help` → usage to stderr, exit 1 (Perl prints to stderr, not stdout)
- [ ] `.xcodeproj` path → auto-append `/project.pbxproj`
- [ ] Non-`project.pbxproj` filename → warning to stderr, skip
- [ ] Multiple files → process each sequentially

### 1.3 Incorporate improvement-plan items into the new version

These items from `docs/improvement-plan.md` should be built into the Python version from the start:

| Item | How |
|------|-----|
| #2 `--check` | Add to argparse; compare sorted output to original, exit 0 if sorted / exit 1 if unsorted |
| #7 File existence check | `Path.exists()` before processing |
| #10 `--version` | `parser.add_argument('--version', ...)` |

---

## Phase 2: Core Logic Port

### 2.1 Regex patterns (Perl lines 60-92)

Port all four compiled regexes using `re.compile(..., re.VERBOSE)`:

```
REGEX_ARRAY_START    → children|buildConfigurations|targets|packageProductDependencies|packageReferences
REGEX_FILES_ARRAY    → files = (
REGEX_CHILD_ENTRY    → 24-hex-char ID /* name */,
REGEX_FILE_ENTRY     → 24-hex-char ID /* name in Phase */,
```

**Critical**: Perl `$` in `/x` mode matches end-of-string. Python `$` in `re.VERBOSE` also matches end-of-string (or before trailing `\n` with `re.MULTILINE`). Since we match against individual lines (no `\n`), behavior is identical. Do NOT add `re.MULTILINE`.

### 2.2 `sort_project_file()` (Perl lines 176-243)

Line-by-line port of the state machine:

```python
def sort_project_file(path: Path, ...) -> None:
    content = path.read_text(encoding="utf-8")
    lines = content.split("\n")  # Perl: split(/\n/, $content, -1)
    output = []
    i = 0
    while i < len(lines):
        # ... same if/elif/else structure
```

**Critical split behavior**: Perl `split(/\n/, $content, -1)` preserves trailing empty strings. Python `str.split("\n")` also preserves them. ✅ Identical.

**Output joining**: Perl `join("\n", @output)`. Python `"\n".join(output)`. ✅ Identical.

### 2.3 `read_array_entries()` (Perl lines 265-280)

Direct port. End marker matching uses `re.escape()` (equivalent to Perl `\Q...\E`):

```python
if re.match(re.escape(end_marker) + r"\s*$", line):
```

### 2.4 `extract_filename()` (Perl lines 299-302)

```python
def extract_filename(line: str, pattern: re.Pattern) -> str:
    m = pattern.search(line)
    return m.group(1) if m else ""
```

### 2.5 `is_directory()` (Perl lines 328-344)

```python
KNOWN_FILES = {"create_hash_table"}
KNOWN_FILES_LC = {f.lower() for f in KNOWN_FILES}

def is_directory(filename: str, case_insensitive: bool) -> bool:
    if "." in filename:  # has extension → file
        return False
    lookup = KNOWN_FILES_LC if case_insensitive else KNOWN_FILES
    name = filename.lower() if case_insensitive else filename
    return name not in lookup
```

**Parity note**: Perl checks `m/\.([^.]+)$/` — matches a dot followed by non-dot chars at end. Python `"." in filename` is slightly different (matches dots anywhere). However, for the purpose of "has a file extension", the result is the same: any dot means it has an extension. The Perl regex technically requires at least one non-dot char after the last dot, but filenames ending with a dot are not valid in practice. ✅ Functionally identical for all realistic inputs.

### 2.6 Sort comparators (Perl lines 366-409)

Perl uses `sort comparator_func @list`. Python uses `sorted(list, key=key_func)` or `functools.cmp_to_key()`.

**Recommended approach**: Use `sorted()` with `key=` function (more Pythonic, avoids `cmp_to_key` overhead):

```python
def children_sort_key(line: str) -> tuple:
    name = extract_filename(line, REGEX_CHILD_ENTRY)
    return (not is_directory(name), natural_sort_key(name))

def files_sort_key(line: str) -> tuple:
    name = extract_filename(line, REGEX_FILE_ENTRY)
    return natural_sort_key(name)
```

Tuple comparison gives directory-before-file ordering: `(False, ...)` < `(True, ...)`.

### 2.7 `natural_cmp()` → `natural_sort_key()` (Perl lines 450-498)

This is the most critical function to port correctly. The Perl version is a comparator (`-1, 0, 1`); the Python version should be a sort key.

**Perl algorithm (must be replicated exactly):**
1. Tokenize: `(\d+|[^\d]+)` — split into digit/non-digit runs
2. Digit runs: compare as integers; if equal, shorter string first (leading zeros)
3. Non-digit runs: `cmp` (or `lc cmp lc` if case-insensitive)
4. Fewer tokens sorts first

**Python sort key approach:**

```python
_TOKENIZE = re.compile(r"(\d+|[^\d]+)")

def natural_sort_key(s: str, case_insensitive: bool = False) -> list:
    tokens = _TOKENIZE.findall(s or "")
    key = []
    for token in tokens:
        if token.isdigit():
            # (0, numeric_value, length) — length handles leading zeros
            key.append((0, int(token), len(token)))
        else:
            text = token.lower() if case_insensitive else token
            # (1, 0, text) — type=1 puts non-digit after digit in same position
            key.append((1, 0, text))
    return key
```

**⚠️ Leading zeros subtlety**: Perl says `length("01") <=> length("1")` → shorter first, so `"1" < "01" < "001"`. The Python key must include `len(token)` as a tiebreaker for numeric tokens.

**⚠️ Case-insensitive subtlety**: In Perl, when `$CASE_INSENSITIVE` is on and `lc($a) eq lc($b)`, the tokens are considered equal and comparison continues to next token. The Python `key` approach handles this correctly because equal keys produce equal tuples.

**Verification test cases (MUST all pass):**

| Input A | Input B | Case-sensitive | Case-insensitive |
|---------|---------|----------------|------------------|
| `"file2"` | `"file10"` | A < B | A < B |
| `"File"` | `"file"` | A < B | A == B |
| `"file01"` | `"file1"` | A > B (longer digit run) | A > B |
| `""` | `"a"` | A < B | A < B |
| `"abc"` | `"abc"` | A == B | A == B |
| `"a1b"` | `"a2b"` | A < B | A < B |
| `"file"` | `"file2"` | A < B | A < B |
| `"1"` | `"01"` | A < B | A < B |

**Wait — verify the Perl leading zeros behavior:**
Perl line 474: `return length($part_x) <=> length($part_y)` — shorter length sorts first.
So `"1"` (length 1) < `"01"` (length 2). Confirmed: `"1" < "01" < "001"`.

### 2.8 `uniq()` (Perl lines 531-534)

```python
def uniq(items: list[str]) -> list[str]:
    seen = set()
    result = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result
```

Perl's `uniq` deduplicates by exact string match (entire line, including whitespace). Python version must do the same.

### 2.9 PBXFrameworksBuildPhase passthrough (Perl lines 221-232)

```python
elif "Begin PBXFrameworksBuildPhase section" in line:
    output.append(line)
    i += 1
    while i < len(lines):
        fw_line = lines[i]
        output.append(fw_line)
        i += 1
        if "End PBXFrameworksBuildPhase section" in fw_line:
            break
```

Using `in` instead of regex — simpler and functionally equivalent (Perl regex `^(.*)Begin PBXFrameworksBuildPhase section(.*)$` matches the substring anywhere in the line).

---

## Phase 3: File I/O

### 3.1 `read_file()` → `Path.read_text()`

```python
content = Path(filepath).read_text(encoding="utf-8")
```

**Encoding note**: `.pbxproj` files are UTF-8 (Xcode default since Xcode 3.2). Explicit `encoding="utf-8"` is correct.

### 3.2 `write_file()` — truly atomic (fixes improvement-plan #3)

```python
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
        os.replace(tmp_path, str(target))  # Atomic on POSIX
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
```

**Key differences from Perl version:**
- No `unlink` before `rename` — `os.replace()` atomically overwrites
- `os.fsync()` ensures data is on disk before rename
- `BaseException` catch for cleanup (handles `KeyboardInterrupt` too)

---

## Phase 4: Testing

### 4.1 Test infrastructure

```
tests/
├── __init__.py
├── test_natural_sort.py      # natural_sort_key edge cases
├── test_is_directory.py      # extension heuristic + known files
├── test_sort_project.py      # end-to-end sorting
├── test_dedup.py             # uniq behavior
├── test_cli.py               # argparse, exit codes, stderr
└── fixtures/
    ├── basic.pbxproj          # simple project file
    ├── basic_sorted.pbxproj   # expected output
    ├── with_frameworks.pbxproj # PBXFrameworksBuildPhase
    ├── with_duplicates.pbxproj
    └── empty_arrays.pbxproj
```

Run with:
```bash
python3 -m pytest tests/          # if pytest available
python3 -m unittest discover tests  # stdlib only, always works
```

### 4.2 Cross-validation against Perl version

Before removing the Perl version, run both against the same set of real `.pbxproj` files and `diff` the output:

```bash
# For each test fixture:
cp fixture.pbxproj /tmp/perl_test.pbxproj
cp fixture.pbxproj /tmp/python_test.pbxproj
perl sort-Xcode-project-file.pl /tmp/perl_test.pbxproj
python3 sort_xcode_project_file.py /tmp/python_test.pbxproj
diff /tmp/perl_test.pbxproj /tmp/python_test.pbxproj
# Must produce no diff
```

### 4.3 Cases to specifically test for parity

| Test case | Why |
|-----------|-----|
| Empty `children = ( );` | Edge case: zero entries |
| Single-entry array | No sorting needed, but must not corrupt |
| Entries with spaces in names | Regex capture groups must handle |
| Entries with special chars (`+`, `(`, `)`) | Ensure regex doesn't break |
| Multiple `files = (` in different sections | Each sorted independently |
| `files = (` inside PBXFrameworksBuildPhase | Must NOT be sorted |
| Duplicate entries | Removed, first occurrence kept |
| Already-sorted file | Output must be identical to input (idempotency) |
| `--case-insensitive` vs default | Sort order differs |
| File with no trailing newline | `split` behavior must match |
| File with trailing newline | `split` behavior must match |

---

## Phase 5: Integration

### 5.1 Update pre-commit hook example in README

```bash
# Before (Perl):
perl $sorter $fullFilePath

# After (Python):
python3 $sorter $fullFilePath
```

### 5.2 File naming

| Option | Pros | Cons |
|--------|------|------|
| `sort_xcode_project_file.py` | Python convention (underscores) | Different from current name |
| `sort-Xcode-project-file.py` | Matches current name | Not importable as module |
| `sort-Xcode-project-file` (no ext) | Clean CLI tool name | Less obvious it's Python |

**Recommendation**: `sort-Xcode-project-file.py` — maintains name recognition, `.py` extension makes language clear. Not importable as a module, but this is a CLI tool, not a library.

### 5.3 Transition plan

1. Add Python version alongside Perl version
2. Cross-validate on real projects (Phase 4.2)
3. Update README to reference Python version
4. Keep Perl version for one release cycle, then remove
5. Update AGENTS.md to reflect Python codebase

### 5.4 Update AGENTS.md and improvement-plan.md

- AGENTS.md: rewrite for Python conventions (naming, style, testing commands)
- improvement-plan.md: mark items #2, #3, #7, #10 as completed (built into Python version)

---

## Migration Checklist (Summary)

| # | Task | Status |
|---|------|--------|
| 1 | Scaffold: shebang, license, `__main__` | ☐ |
| 2 | CLI: `argparse` with all flags + `--check`, `--version` | ☐ |
| 3 | Regex: port all 4 compiled patterns | ☐ |
| 4 | `sort_project_file()`: state machine | ☐ |
| 5 | `read_array_entries()` | ☐ |
| 6 | `extract_filename()` | ☐ |
| 7 | `is_directory()` + `KNOWN_FILES` set | ☐ |
| 8 | `natural_sort_key()` — most critical | ☐ |
| 9 | Sort key functions: `children_sort_key`, `files_sort_key` | ☐ |
| 10 | `uniq()` | ☐ |
| 11 | PBXFrameworksBuildPhase passthrough | ☐ |
| 12 | `read_file()` via `Path.read_text()` | ☐ |
| 13 | `write_file()` — truly atomic with `os.replace()` | ☐ |
| 14 | File existence validation before processing | ☐ |
| 15 | Test fixtures (`.pbxproj` files) | ☐ |
| 16 | Unit tests: `natural_sort_key` | ☐ |
| 17 | Unit tests: `is_directory` | ☐ |
| 18 | Unit tests: `uniq` | ☐ |
| 19 | Integration tests: end-to-end sorting | ☐ |
| 20 | Integration tests: CLI flags and exit codes | ☐ |
| 21 | Cross-validation: Perl vs Python output diff | ☐ |
| 22 | Update README | ☐ |
| 23 | Update AGENTS.md | ☐ |
| 24 | Update improvement-plan.md | ☐ |
