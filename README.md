# sort-Xcode-project-file

This Perl script is a fork from [sort-Xcode-project-file](https://github.com/WebKit/webkit/blob/main/Tools/Scripts/sort-Xcode-project-file) with some modifications.

## What's different

- Ignore `PBXFrameworksBuildPhase` section.
- Sort `targets` list for project.
- Sort `buildConfigurations` list for each target.
- Case-sensitive sorting.

## Usage

`perl sort-Xcode-project-file.pl <path-to-xcodeproj-file>`

You can use it to sort Xcode project file before committing it to git version control. Sorting project file can reduce merging conflict possibility.

### 1.

Create a `Scripts` directory in project root directory, and put `sort-Xcode-project-file.pl` into `Scripts` directory.

### 2.

Put following codes into `.git/hooks/pre-commit`.

```bash
#!/bin/sh
#
# Following script is to sort Xcode project files, and add them back to version control.
# The reason to sort project file is that it can reduce project.pbxproj file merging conflict possibility.
#
echo 'Sorting Xcode project files'

GIT_ROOT=$(git rev-parse --show-toplevel)
sorter="$GIT_ROOT/Scripts/sort-Xcode-project-file.pl"
modifiedProjectFiles=( $(git diff --name-only --cached | grep "project.pbxproj") )

for filePath in ${modifiedProjectFiles[@]}; do
  fullFilePath="$GIT_ROOT/$filePath"
  perl $sorter $fullFilePath
  git add $fullFilePath
done

echo 'Done sorting Xcode project files'

exit 0
```

### 3.

Put following line into `.gitattributes` then commit it.

```
*.pbxproj merge=union
```

## License

MIT license.
