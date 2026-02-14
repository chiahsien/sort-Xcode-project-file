# AGENTS.md — sort-Xcode-project-file

## Project Overview

Single-file Perl script that sorts sections of Xcode `project.pbxproj` files to reduce merge conflicts. Forked from WebKit's sort-Xcode-project-file with extended functionality.

**Primary file:** `sort-Xcode-project-file.pl` (~593 lines)
**Language:** Perl 5 (requires 5.10+; tested with 5.34)
**License:** MIT (file headers carry BSD from original WebKit; LICENSE file is MIT)

## Build / Run / Test Commands

### Run the script
```bash
perl sort-Xcode-project-file.pl <path-to-project.pbxproj>
perl sort-Xcode-project-file.pl <path-to-project.xcodeproj>
perl sort-Xcode-project-file.pl --case-insensitive <path>
```

### Verify syntax (no formal test suite exists)
```bash
perl -c sort-Xcode-project-file.pl          # Compile check
perl -w sort-Xcode-project-file.pl --help    # Verify CLI parsing
```

### Lint
```bash
# No linter configured. For optional static analysis:
# perlcritic --severity 4 sort-Xcode-project-file.pl
```

### Tests
There is **no test suite**. The project has no test directory, no test files, and no test harness. Validation is manual — run the script against a `.pbxproj` file and inspect output.

If adding tests, use Perl's built-in `Test::More`:
```bash
perl -Ilib t/some_test.t           # Run single test
prove t/                           # Run all tests (if created)
```

## Architecture

```
sort-Xcode-project-file.pl   # Everything lives here
├── CLI parsing               # Getopt::Long (lines 107-141)
├── Main loop                 # Iterates ARGV files (lines 143-156)
├── sort_project_file()       # Core: read → parse → sort → write (lines 176-243)
├── read_array_entries()      # Extract array contents between ( and ); (lines 265-280)
├── extract_filename()        # Regex-based filename extraction (lines 299-302)
├── is_directory()            # Heuristic: no extension = directory (lines 328-344)
├── sortChildrenByFileName()  # Comparator: dirs first, then natural sort (lines 366-379)
├── sortFilesByFileName()     # Comparator: natural sort only (lines 400-409)
├── natural_cmp()             # Natural (alphanumeric) string comparison (lines 450-498)
├── uniq()                    # Deduplicate preserving order (lines 531-534)
├── read_file()               # Slurp file to string (lines 547-553)
└── write_file()              # Atomic write via temp file (lines 569-592)
```

### Key Regex Patterns (compiled, top of file)
| Variable | Matches |
|---|---|
| `$REGEX_ARRAY_START` | `children = (`, `buildConfigurations = (`, `targets = (`, etc. |
| `$REGEX_FILES_ARRAY` | `files = (` |
| `$REGEX_CHILD_ENTRY` | `HEXID /* Name */,` |
| `$REGEX_FILE_ENTRY` | `HEXID /* Name in BuildPhase */,` |

### Sorting Rules
- **children/targets/configs/packages**: Directories sort before files; natural sort within groups
- **files arrays**: Natural sort only (no directory priority)
- **PBXFrameworksBuildPhase**: Preserved as-is (NOT sorted — order matters)
- **Duplicates**: Removed before sorting (first occurrence kept)

## Code Style Guidelines

### Perl Pragmas (mandatory)
```perl
use strict;
use warnings;
```
Every file must begin with these. No exceptions.

### Modules — Core Only
Only use Perl core modules. Current imports:
- `File::Basename`, `File::Spec`, `File::Temp`, `Getopt::Long`

Do NOT add CPAN dependencies. This script must run with a stock Perl installation.

### Naming Conventions
| Element | Convention | Examples |
|---|---|---|
| Subroutines | `snake_case` | `sort_project_file`, `read_file`, `extract_filename` |
| Sort comparators | `camelCase` (legacy) | `sortChildrenByFileName`, `sortFilesByFileName` |
| Local variables | `$camelCase` | `$projectFile`, `$aFileName`, `$endMarker` |
| Global flags | `$UPPER_CASE` | `$CASE_INSENSITIVE` |
| Constants/regex | `$REGEX_UPPER_CASE` | `$REGEX_ARRAY_START`, `$REGEX_FILE_ENTRY` |
| Hashes (lookup) | `%camelCase` | `%isFile`, `%isFile_lc` |

**Note:** The codebase has two naming styles for subs (snake_case for newer, camelCase for sort comparators). New code should use `snake_case`. Do not rename existing comparators — they follow Perl sort prototype conventions.

### Regex Style
- Use compiled regex (`qr/.../x`) stored in package-level variables
- Use `/x` verbose mode with comments explaining each part
- Use named semantic groups where helpful
- Escape special characters properly in comments

Example from codebase:
```perl
my $REGEX_CHILD_ENTRY = qr/^
    \s*                             # optional leading whitespace
    [A-Fa-f0-9]{24}                 # Xcode object ID - 24 hex chars
    \s+ \/\* \s*                    # space and comment start
    (.+?)                           # capture filename - non-greedy
    \s* \*\/ ,                      # comment end and trailing comma
    $                               # end of line
/x;
```

### Documentation Style
Every subroutine must have a block comment header with:
```perl
# -----------------------------------------------------------------------------
# Brief description
#
# Purpose:
#   What it does and why
#
# Parameters:
#   $param - description
#
# Returns:
#   What is returned
#
# Examples:
#   function_call("input") => "output"
# -----------------------------------------------------------------------------
```

### Error Handling
- Use `die` with descriptive messages for fatal errors: `die "Could not open $file: $!";`
- Use `eval { ... }; if ($@) { ... }` for recoverable operations (see `write_file`)
- Use `warn` / `print STDERR` for non-fatal warnings, gated by `$printWarnings`
- Clean up resources (close filehandles, delete temp files) in error paths

### File I/O
- Read: slurp entire file via `local $/` idiom
- Write: **always atomic** — write to temp file, then rename over original
- Use `File::Temp` for temp files; handle cleanup on failure

### Formatting
- Indentation: 4 spaces (no tabs)
- Opening brace for subs: same line or next line (both present in codebase; prefer same line for new code)
- Line length: soft limit ~100 characters
- Blank line between logical sections
- Separator comments (`# ---...---`) between subroutines

### Sort Comparator Prototypes
Sort comparators use the `($$)` prototype:
```perl
sub sortChildrenByFileName($$) {
    my ($a, $b) = @_;
    ...
}
```
This is required for Perl's `sort` function. Do not remove the prototype.

## Critical Constraints

1. **No CPAN dependencies** — must work with stock Perl on macOS
2. **PBXFrameworksBuildPhase must never be sorted** — framework link order is significant
3. **Atomic file writes** — never leave a `.pbxproj` in a corrupted state
4. **Backward compatible** — default behavior (case-sensitive) must match original WebKit script
5. **The script modifies files in-place** — always test against a copy

## CLI Flags Reference

| Flag | Effect |
|---|---|
| `--case-insensitive` | Case-insensitive natural sort |
| `--case-sensitive` | Force case-sensitive (default) |
| `-w` / `--no-warnings` | Suppress warning messages |
| `-h` / `--help` | Show usage and exit |

## Known Limitations & Improvement Plan

See [`docs/improvement-plan.md`](docs/improvement-plan.md) for a prioritized list of improvements. Key items:

- **No test suite** — the highest priority gap; all changes should be validated manually until tests exist
- **No dry-run / check mode** — the script always modifies files in-place; no way to preview or use in CI lint checks
- **`write_file` is not truly atomic** — the current `unlink` + `rename` sequence has a data-loss window (fix: remove the `unlink`)
- **`%isFile` known files list is incomplete** — only `create_hash_table`; common extension-less files (Makefile, Podfile, etc.) are misclassified as directories

When implementing any item from the plan, update the plan file to reflect completion.

## Commit Style

Based on git history, use conventional commits:
```
fix: escape special characters in regex comments
feat: enhance sorting functionality with case-insensitive option
refactor: improve variable scope management and extract helper functions
docs: add comprehensive POD documentation and improve inline comments
style: standardize code style for consistency
```
Prefixes: `fix:`, `feat:`, `refactor:`, `docs:`, `style:`
