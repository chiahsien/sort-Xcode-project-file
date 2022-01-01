# sort-Xcode-project-file

This Perl script is a fork from [sort-Xcode-project-file](https://github.com/WebKit/webkit/blob/main/Tools/Scripts/sort-Xcode-project-file) with some modifications.

## What's different

- Bypass `PBXFrameworksBuildPhase` section because this order is important for some projects.
- Sort `targets` list in project.
- Sort `packageReferences` list in project.
- Sort `buildConfigurations` list in each target.
- Case-sensitive sorting.

## Usage

**Please backup Xcode project file before using this script.** You can execute following command to sort a project file:

`perl sort-Xcode-project-file.pl <path-to-xcodeproj-file>`

You can use it to sort Xcode project file before committing it to git version control. Sorting project file can decrease the merging conflict possibility.

It is recommended to do it everytime when a project is about to be committed, git's `pre-commit` hook can do that for us.

### 1.

Create a `Scripts` directory in project root directory, and put `sort-Xcode-project-file.pl` into `Scripts` directory.

### 2.

Put following codes into `.git/hooks/pre-commit` file.

```bash
#!/bin/sh
#
# Following script is to sort Xcode project files, and add them back to version control.
# The reason to sort project file is that it can decrease project.pbxproj file merging conflict possibility.
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

Put following line into `.gitattributes` file then commit it.

```
*.pbxproj merge=union
```

## To-Do

- [ ] Sort file names numerically.
  `1, 2, 10, 11` instead of `1, 10, 11, 2`.
- [ ] Command line option to bypass `PBXFrameworksBuildPhase` section or not.

## License

MIT license.
