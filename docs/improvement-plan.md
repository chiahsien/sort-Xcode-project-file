# Improvement Plan

Analysis date: 2026-02-14

## 🔴 High Value

### 1. ~~Add Test Suite~~ ✅ Completed

Implemented in Python port (Phase 4): 54 unit/integration tests + cross-validation script. Run with `python3 -m unittest discover tests -v`.

---

### 2. ~~Check Mode~~ ✅ Completed

Implemented in Python port: `--check` flag exits 0 if sorted, 1 if unsorted. No file modification.

`--dry-run` was considered but rejected — `.pbxproj` files are thousands of lines long, dumping sorted output to stdout is not useful for human review. `--check` answers the only question that matters: "does this file need sorting?"

---

### 3. ~~Fix `write_file` Atomic Write~~ ✅ Completed

Python port uses `os.replace()` (truly atomic on POSIX) — no `unlink` before `rename`. Also includes `os.fsync()` and `BaseException` cleanup.

---

## 🟡 Medium Value

### 4. ~~Expand `%isFile` Known Files List~~ ✅ Completed

Expanded `_KNOWN_FILES` from 1 entry to 12: `Brewfile`, `Cartfile`, `CHANGELOG`, `create_hash_table`, `Dangerfile`, `Fastfile`, `Gemfile`, `LICENSE`, `Makefile`, `Podfile`, `Rakefile`, `README`.

---

### 5. ~~Stdin/Stdout Pipeline Support~~ ✅ Completed

Accept `-` as a filename to read from stdin and write to stdout. Works with `--check` mode. Core sorting logic extracted into `sort_project_content()` pure function.

---

### 6. ~~Feedback on Changes~~ ❌ Cancelled

Decided against — script should remain silent by default for pre-commit hook usage. `--check` already provides the only feedback needed (exit code).

---

### 7. ~~Better Error Message for Missing Files~~ ✅ Completed

Python port validates file existence with `Path.exists()` before processing, with a clear error message.

---

## 🟢 Low Value / Nice to Have

### 8. Verify PBXFrameworksBuildPhase Files Array Bypass ✅ Covered

Test `test_frameworks_preserved` in `tests/test_sort_project.py` confirms PBXFrameworksBuildPhase `files` arrays are not sorted.

---

### 9. ~~Recursive Directory Search~~ ✅ Completed

Added `--recursive` / `-r` flag using `pathlib.Path.rglob("project.pbxproj")`. Useful for monorepos with multiple Xcode projects.

---

### 10. ~~Version Flag~~ ✅ Completed

Python port includes `--version` flag (`1.0.0`).

---

## Priority Order (Recommended)

| Order | Item | Status |
|-------|------|--------|
| 1 | #3 Fix atomic write | ✅ Completed |
| 2 | #7 Better error for missing files | ✅ Completed |
| 3 | #4 Expand `KNOWN_FILES` | ✅ Completed |
| 4 | #1 Add test suite | ✅ Completed |
| 5 | #2 Check mode | ✅ Completed |
| 6 | #10 Version flag | ✅ Completed |
| 7 | #6 Feedback on changes | ❌ Cancelled |
| 8 | #5 Stdin/stdout support | ✅ Completed |
| 9 | #8 PBXFrameworksBuildPhase test | ✅ Covered |
| 10 | #9 Recursive search | ✅ Completed |
