import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = str(Path(__file__).parent.parent / "sort-Xcode-project-file.py")
FIXTURES_DIR = Path(__file__).parent / "fixtures"


def run_script(*args, **kwargs):
    return subprocess.run(
        [sys.executable, SCRIPT, *args],
        capture_output=True,
        text=True,
        **kwargs,
    )


class TestCLI(unittest.TestCase):

    def test_no_args_exit_1(self):
        r = run_script()
        self.assertEqual(r.returncode, 1)
        self.assertIn("ERROR", r.stderr)

    def test_help_exit_1(self):
        r = run_script("--help")
        self.assertEqual(r.returncode, 1)
        self.assertIn("Usage:", r.stderr)

    def test_version_exit_0(self):
        r = run_script("--version")
        self.assertEqual(r.returncode, 0)

    def test_check_sorted_exit_0(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = os.path.join(tmpdir, "project.pbxproj")
            shutil.copy2(FIXTURES_DIR / "basic_sorted.pbxproj", dest)
            r = run_script("--check", dest)
        self.assertEqual(r.returncode, 0)

    def test_check_unsorted_exit_1(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = os.path.join(tmpdir, "project.pbxproj")
            shutil.copy2(FIXTURES_DIR / "basic_unsorted.pbxproj", dest)
            r = run_script("--check", dest)
        self.assertEqual(r.returncode, 1)

    def test_case_insensitive_accepted(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = os.path.join(tmpdir, "project.pbxproj")
            shutil.copy2(FIXTURES_DIR / "basic_sorted.pbxproj", dest)
            r = run_script("--case-insensitive", "--check", dest)
        self.assertIn(r.returncode, (0, 1))

    def test_case_sensitive_accepted(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = os.path.join(tmpdir, "project.pbxproj")
            shutil.copy2(FIXTURES_DIR / "basic_sorted.pbxproj", dest)
            r = run_script("--case-sensitive", "--check", dest)
        self.assertEqual(r.returncode, 0)

    def test_mutual_exclusion(self):
        r = run_script("--case-insensitive", "--case-sensitive", "dummy")
        self.assertNotEqual(r.returncode, 0)

    def test_nonexistent_file(self):
        r = run_script("/nonexistent/project.pbxproj")
        self.assertIn("ERROR", r.stderr)

    def test_xcodeproj_auto_appends(self):
        r = run_script("/nonexistent/MyApp.xcodeproj")
        self.assertIn("project.pbxproj", r.stderr)

    def test_no_warnings_flag(self):
        r = run_script("-w", "/nonexistent/something.txt")
        self.assertNotIn("WARNING", r.stderr)

    def test_non_pbxproj_warns(self):
        with tempfile.NamedTemporaryFile(suffix=".txt") as f:
            r = run_script(f.name)
        self.assertIn("WARNING", r.stderr)


if __name__ == "__main__":
    unittest.main()
