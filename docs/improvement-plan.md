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

### 4. Expand `%isFile` Known Files List

**Problem:** Only `create_hash_table` is listed. Common extension-less files in iOS/macOS projects are misclassified as directories.

**Missing entries (at minimum):**
```
Makefile Podfile Cartfile Gemfile Rakefile Fastfile
Brewfile Dangerfile LICENSE README CHANGELOG
```

**Effort:** Trivial

---

### 5. Stdin/Stdout Pipeline Support

**Problem:** Can't use in pipelines: `cat project.pbxproj | sort-Xcode-project-file.py > sorted.pbxproj`

**Proposal:** Accept `-` as a filename to read from stdin and write to stdout. Pairs naturally with `--dry-run`.

**Effort:** Low

---

### 6. Feedback on Changes

**Problem:** The script is completely silent on success. Users don't know if anything actually changed, or how many duplicates were removed.

**Proposal:**
- Default: print a one-line summary when changes were made (e.g., `Sorted 5 arrays, removed 2 duplicates in project.pbxproj`)
- `--quiet`: suppress all output (for pre-commit hooks that want silence)
- `--verbose`: detailed per-section report

**Effort:** Low — track counts during the sort loop, print at end

---

### 7. ~~Better Error Message for Missing Files~~ ✅ Completed

Python port validates file existence with `Path.exists()` before processing, with a clear error message.

---

## 🟢 Low Value / Nice to Have

### 8. Verify PBXFrameworksBuildPhase Files Array Bypass ✅ Covered

Test `test_frameworks_preserved` in `tests/test_sort_project.py` confirms PBXFrameworksBuildPhase `files` arrays are not sorted.

---

### 9. Recursive Directory Search

**Proposal:** Add `--recursive` flag to find and sort all `project.pbxproj` files under a given directory. Useful for monorepos with multiple Xcode projects.

**Effort:** Low — `pathlib.Path.rglob()` handles recursive search

---

### 10. ~~Version Flag~~ ✅ Completed

Python port includes `--version` flag (`1.0.0`).

---

## Priority Order (Recommended)

| Order | Item | Status |
|-------|------|--------|
| 1 | #3 Fix atomic write | ✅ Completed |
| 2 | #7 Better error for missing files | ✅ Completed |
| 3 | #4 Expand `%isFile` / `KNOWN_FILES` | Open |
| 4 | #1 Add test suite | ✅ Completed |
| 5 | #2 Check mode | ✅ Completed |
| 6 | #10 Version flag | ✅ Completed |
| 7 | #6 Feedback on changes | Open |
| 8 | #5 Stdin/stdout support | Open |
| 9 | #8 PBXFrameworksBuildPhase test | ✅ Covered |
| 10 | #9 Recursive search | Open |
