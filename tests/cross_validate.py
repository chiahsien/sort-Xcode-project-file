#!/usr/bin/env python3
"""Cross-validate Perl and Python sort scripts produce identical output.

Usage:
    python3 tests/cross_validate.py
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
PERL_SCRIPT = PROJECT_ROOT / "sort-Xcode-project-file.pl"
PYTHON_SCRIPT = PROJECT_ROOT / "sort-Xcode-project-file.py"
FIXTURES_DIR = Path(__file__).parent / "fixtures"

UNSORTED_FIXTURES = [
    "basic_unsorted.pbxproj",
    "with_frameworks.pbxproj",
    "with_duplicates.pbxproj",
    "empty_arrays.pbxproj",
]


def run_perl(filepath):
    subprocess.run(
        ["perl", str(PERL_SCRIPT), str(filepath)],
        check=True,
        capture_output=True,
    )


def run_python(filepath):
    subprocess.run(
        [sys.executable, str(PYTHON_SCRIPT), str(filepath)],
        check=True,
        capture_output=True,
    )


def cross_validate(fixture_name, case_insensitive=False):
    src = FIXTURES_DIR / fixture_name
    label = fixture_name
    if case_insensitive:
        label += " (case-insensitive)"

    with tempfile.TemporaryDirectory() as tmpdir:
        perl_file = Path(tmpdir) / "perl" / "project.pbxproj"
        python_file = Path(tmpdir) / "python" / "project.pbxproj"
        perl_file.parent.mkdir()
        python_file.parent.mkdir()

        shutil.copy2(src, perl_file)
        shutil.copy2(src, python_file)

        perl_args = ["perl", str(PERL_SCRIPT)]
        python_args = [sys.executable, str(PYTHON_SCRIPT)]
        if case_insensitive:
            perl_args.append("--case-insensitive")
            python_args.append("--case-insensitive")
        perl_args.append(str(perl_file))
        python_args.append(str(python_file))

        subprocess.run(perl_args, check=True, capture_output=True)
        subprocess.run(python_args, check=True, capture_output=True)

        perl_output = perl_file.read_text(encoding="utf-8")
        python_output = python_file.read_text(encoding="utf-8")

        if perl_output == python_output:
            print(f"  PASS  {label}")
            return True
        else:
            print(f"  FAIL  {label}")
            perl_lines = perl_output.splitlines()
            python_lines = python_output.splitlines()
            for i, (pl, pyl) in enumerate(zip(perl_lines, python_lines)):
                if pl != pyl:
                    print(f"    First diff at line {i + 1}:")
                    print(f"      Perl:   {pl!r}")
                    print(f"      Python: {pyl!r}")
                    break
            return False


def main():
    print("Cross-validating Perl vs Python sort scripts...")
    print()
    all_pass = True

    for fixture in UNSORTED_FIXTURES:
        if not cross_validate(fixture):
            all_pass = False
        if not cross_validate(fixture, case_insensitive=True):
            all_pass = False

    print()
    if all_pass:
        print("All cross-validation checks passed.")
        return 0
    else:
        print("Some cross-validation checks FAILED.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
