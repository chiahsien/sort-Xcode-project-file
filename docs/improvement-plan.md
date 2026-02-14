# Improvement Plan

Analysis date: 2026-02-14

## 🔴 High Value

### 1. Add Test Suite

**Problem:** A tool that modifies `.pbxproj` files in-place has zero automated tests. One regression can break a team's Xcode project.

**Scope:**
- Create `t/` directory with `Test::More`-based tests
- Prepare small `.pbxproj` fixture files covering edge cases
- Test cases needed:
  - Sorting correctness for each array type (children, files, targets, buildConfigurations, packageProductDependencies, packageReferences)
  - PBXFrameworksBuildPhase is preserved (NOT sorted)
  - Duplicate removal logic
  - `natural_cmp` edge cases: empty strings, pure numbers, leading zeros, mixed case
  - `--case-insensitive` flag behavior
  - `is_directory` heuristic with known files list
  - Atomic write cleanup on failure
  - Already-sorted file produces identical output (idempotency)
- Run with: `prove t/`

**Effort:** Medium — need to craft realistic fixture files

---

### 2. Check Mode

**Problem:** No way to use in CI pipelines to enforce sorted project files.

**Proposal:**
- `--check`: exit 0 if already sorted, exit 1 if changes needed (CI-friendly)

`--dry-run` was considered but rejected — `.pbxproj` files are thousands of lines long, dumping sorted output to stdout is not useful for human review. `--check` answers the only question that matters: "does this file need sorting?"

**Effort:** Low — the core logic already produces sorted output in `@output`; just compare against original

---

### 3. Fix `write_file` Atomic Write

**Problem (line 582-583):**
```perl
unlink($file) or die "Could not delete $file: $!";
rename($tempFile, $file) or die "Could not rename $tempFile to $file: $!";
```
If the process crashes between `unlink` and `rename`, the original file is gone. On POSIX, `rename()` atomically replaces the target — the `unlink` is unnecessary and creates a data-loss window.

**Fix:**
```perl
rename($tempFile, $file) or die "Could not rename $tempFile to $file: $!";
```
Remove the `unlink` line entirely.

**Effort:** Trivial — one line deletion, but high impact on safety

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

**Problem:** Can't use in pipelines: `cat project.pbxproj | perl sort-Xcode-project-file.pl > sorted.pbxproj`

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

### 7. Better Error Message for Missing Files

**Problem (line 143-154):** If a non-existent path is passed, the error surfaces from `read_file` as a low-level `Could not open ...` message.

**Fix:** Validate file existence before calling `sort_project_file`:
```perl
unless (-f $projectFile) {
    print STDERR "ERROR: File not found: $projectFile\n";
    next;
}
```

**Effort:** Trivial

---

## 🟢 Low Value / Nice to Have

### 8. Verify PBXFrameworksBuildPhase Files Array Bypass

**Problem:** The `files = (` regex is checked before `Begin PBXFrameworksBuildPhase`, but PBXFrameworksBuildPhase sections are handled by passthrough (the entire section block is copied verbatim). In practice this works because pbxproj format always has the section header before its contents. But there's no test proving this.

**Action:** Add a test with a PBXFrameworksBuildPhase fixture containing a `files = (` array to confirm it's not sorted.

**Effort:** Low (just a test case)

---

### 9. Recursive Directory Search

**Proposal:** Add `--recursive` flag to find and sort all `project.pbxproj` files under a given directory. Useful for monorepos with multiple Xcode projects.

**Effort:** Low — `File::Find` is a core module

---

### 10. Version Flag

**Problem:** No `--version` flag. Makes bug reports and hook debugging harder.

**Proposal:** Add `$VERSION` variable and `--version` CLI flag.

**Effort:** Trivial

---

## Priority Order (Recommended)

| Order | Item | Why |
|-------|------|-----|
| 1 | #3 Fix atomic write | One-line fix, eliminates data-loss risk |
| 2 | #7 Better error for missing files | Trivial, improves UX |
| 3 | #4 Expand `%isFile` | Trivial, fixes misclassification |
| 4 | #1 Add test suite | Foundation for all future changes |
| 5 | #2 Dry-run / check mode | Enables CI adoption, lowers barrier |
| 6 | #10 Version flag | Trivial, good practice |
| 7 | #6 Feedback on changes | Better UX |
| 8 | #5 Stdin/stdout support | Flexibility |
| 9 | #8 PBXFrameworksBuildPhase test | Safety verification |
| 10 | #9 Recursive search | Nice to have |
