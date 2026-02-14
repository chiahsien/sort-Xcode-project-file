# sort-Xcode-project-file

A tool to sort sections of Xcode `project.pbxproj` files, reducing merge conflicts in version control.

Forked from [WebKit's sort-Xcode-project-file](https://github.com/WebKit/webkit/blob/main/Tools/Scripts/sort-Xcode-project-file) with extended functionality.

## Features

- Sort `children` arrays throughout the project (directories before files)
- Sort `files` arrays in build phases
- Sort `targets`, `buildConfigurations`, `packageProductDependencies`, and `packageReferences` arrays
- Preserve `PBXFrameworksBuildPhase` order (link order matters)
- Remove duplicate references automatically
- Natural (human) sorting for names/filenames (e.g., `file2` < `file10`)
- Case-sensitive sorting by default (original WebKit behavior)
- Option for case-insensitive sorting: `--case-insensitive`
- `--check` mode for CI pipelines (exit 0 if sorted, exit 1 if unsorted)
- Stdin/stdout pipeline support (`-`)
- Recursive directory search (`-r` / `--recursive`)
- Atomic file writes — never leaves a `.pbxproj` in a corrupted state

## Requirements

- macOS with Xcode Command Line Tools installed (`xcode-select --install`)
- Python 3.9+ (ships with Xcode CLT on macOS Monterey 12 through Sequoia 15)

## Usage

```bash
python3 sort-Xcode-project-file.py MyApp.xcodeproj
python3 sort-Xcode-project-file.py path/to/project.pbxproj
```

Both `.xcodeproj` directories and `project.pbxproj` files are accepted.

### Options

| Flag | Description |
|------|-------------|
| `-` | Read from stdin, write to stdout |
| `--case-insensitive` | Enable case-insensitive sorting (default is case-sensitive) |
| `--case-sensitive` | Explicit alias to force case-sensitive sorting |
| `--check` | Check if file is already sorted (exit 0 = sorted, exit 1 = unsorted) |
| `-r`, `--recursive` | Recursively find and sort all `project.pbxproj` under directories |
| `--version` | Show version and exit |
| `-w`, `--no-warnings` | Suppress warning messages |
| `-h`, `--help` | Show help |

### Examples

```bash
# Sort a single project
python3 sort-Xcode-project-file.py MyApp.xcodeproj

# CI check — fails if unsorted
python3 sort-Xcode-project-file.py --check MyApp.xcodeproj

# Sort all projects in a monorepo
python3 sort-Xcode-project-file.py -r .

# Pipe through stdin/stdout
cat project.pbxproj | python3 sort-Xcode-project-file.py - > sorted.pbxproj

# Check stdin without modifying anything
cat project.pbxproj | python3 sort-Xcode-project-file.py --check -
```

## Pre-commit Hook

Sort Xcode project files automatically before each commit to reduce merge conflicts.

**1.** Create a `Scripts` directory in your project root and copy `sort-Xcode-project-file.py` into it.

**2.** Create `.git/hooks/pre-commit` with the following content:

```bash
#!/bin/sh

echo 'Sorting Xcode project files'

GIT_ROOT=$(git rev-parse --show-toplevel)
sorter="$GIT_ROOT/Scripts/sort-Xcode-project-file.py"

git diff --name-only --cached | grep "project.pbxproj" | while IFS= read -r filePath; do
  fullFilePath="$GIT_ROOT/$filePath"
  python3 "$sorter" "$fullFilePath"
  git add "$fullFilePath"
done

echo 'Done sorting Xcode project files'
```

**3.** Make it executable:

```bash
chmod +x .git/hooks/pre-commit
```

**4.** *(Optional)* Add to `.gitattributes` to reduce merge conflicts further:

```
*.pbxproj merge=union
```

> **Note:** `merge=union` tells Git to keep both sides of a conflict automatically. This works well for sorted `.pbxproj` files but can produce invalid results on non-sorted ones. Use this tool consistently to avoid issues.

## Running Tests

```bash
python3 -m unittest discover tests -v    # Run all 70 tests
```

## License

MIT license.
