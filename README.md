# sort-Xcode-project-file

A tool to sort sections of Xcode `project.pbxproj` files, reducing merge conflicts in version control.

Forked from [WebKit's sort-Xcode-project-file](https://github.com/WebKit/webkit/blob/main/Tools/Scripts/sort-Xcode-project-file) with extended functionality.

## Features

- Bypass `PBXFrameworksBuildPhase` section (preserve original order, important for some projects)
- Sort `children` arrays throughout the project (directories before files)
- Sort `files` arrays in build phases
- Sort `targets` list in project
- Sort `packageProductDependencies` and `packageReferences` lists in project
- Sort `buildConfigurations` list in each target
- Case-sensitive sorting by default (preserves original behavior)
- Option to enable case-insensitive sorting: `--case-insensitive`
- Remove duplicate references automatically
- Natural (human) sorting for names/filenames (e.g., `file2` < `file10`)
- `--check` mode for CI pipelines (exit 0 if sorted, exit 1 if unsorted)
- Atomic file writes — never leaves a `.pbxproj` in a corrupted state

## Requirements

- macOS with Xcode Command Line Tools installed (`xcode-select --install`)
- Python 3.9+ (ships with Xcode CLT on macOS Monterey 12 through Sequoia 15)

## Usage

**Please backup Xcode project file before using this script.** You can execute the following command to sort a project file:

```bash
python3 sort-Xcode-project-file.py <path-to-xcodeproj-or-project.pbxproj>
```

### Options

| Flag | Description |
|------|-------------|
| `--case-insensitive` | Enable case-insensitive sorting (default is case-sensitive) |
| `--case-sensitive` | Explicit alias to force case-sensitive sorting |
| `--check` | Check if file is already sorted (exit 0 = sorted, exit 1 = unsorted) |
| `--version` | Show version and exit |
| `-w`, `--no-warnings` | Suppress warning messages |
| `-h`, `--help` | Show help |

### CI Usage

Use `--check` in CI pipelines to enforce sorted project files:

```bash
python3 sort-Xcode-project-file.py --check MyApp.xcodeproj
```

Exit code 0 means the file is already sorted; exit code 1 means it needs sorting.

## Pre-commit Hook Setup

You can use this tool to sort Xcode project files before committing to git. Sorting project files decreases merge conflict probability.

### 1.

Create a `Scripts` directory in project root directory, and put `sort-Xcode-project-file.py` into `Scripts` directory.

### 2.

Put the following code into `.git/hooks/pre-commit` file.

```bash
#!/bin/sh
#
# Following script is to sort Xcode project files, and add them back to version control.
# The reason to sort project file is that it can decrease project.pbxproj file merging conflict possibility.
#
echo 'Sorting Xcode project files'

GIT_ROOT=$(git rev-parse --show-toplevel)
sorter="$GIT_ROOT/Scripts/sort-Xcode-project-file.py"
modifiedProjectFiles=( $(git diff --name-only --cached | grep "project.pbxproj") )

for filePath in ${modifiedProjectFiles[@]}; do
  fullFilePath="$GIT_ROOT/$filePath"
  python3 $sorter $fullFilePath
  git add $fullFilePath
done

echo 'Done sorting Xcode project files'

exit 0
```

### 3.

Put following line into `.gitattributes` file then commit it.

```
*.pbxproj merge=union
```

## Running Tests

```bash
python3 -m unittest discover tests    # Run all tests (54 tests)
python3 tests/cross_validate.py       # Cross-validate Python vs Perl output
```

## Legacy Perl Version

The original Perl version (`sort-Xcode-project-file.pl`) is still available. The Python version produces byte-for-byte identical output.

```bash
perl sort-Xcode-project-file.pl <path-to-xcodeproj-or-project.pbxproj>
```

## License

MIT license.
