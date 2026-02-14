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

    def test_stdin_pipe(self):
        unsorted = (FIXTURES_DIR / "basic_unsorted.pbxproj").read_text()
        expected = (FIXTURES_DIR / "basic_sorted.pbxproj").read_text()
        r = run_script("-", input=unsorted)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, expected)

    def test_stdin_check_sorted(self):
        content = (FIXTURES_DIR / "basic_sorted.pbxproj").read_text()
        r = run_script("--check", "-", input=content)
        self.assertEqual(r.returncode, 0)

    def test_stdin_check_unsorted(self):
        content = (FIXTURES_DIR / "basic_unsorted.pbxproj").read_text()
        r = run_script("--check", "-", input=content)
        self.assertEqual(r.returncode, 1)

    def test_stdin_case_insensitive(self):
        unsorted = (FIXTURES_DIR / "basic_unsorted.pbxproj").read_text()
        expected = (FIXTURES_DIR / "basic_ci_sorted.pbxproj").read_text()
        r = run_script("--case-insensitive", "-", input=unsorted)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, expected)

    def test_recursive_finds_nested(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            d1 = os.path.join(tmpdir, "A.xcodeproj")
            d2 = os.path.join(tmpdir, "sub", "B.xcodeproj")
            os.makedirs(d1)
            os.makedirs(d2)
            src = FIXTURES_DIR / "basic_unsorted.pbxproj"
            shutil.copy2(src, os.path.join(d1, "project.pbxproj"))
            shutil.copy2(src, os.path.join(d2, "project.pbxproj"))
            r = run_script("--recursive", tmpdir)
            self.assertEqual(r.returncode, 0)
            expected = (FIXTURES_DIR / "basic_sorted.pbxproj").read_text()
            self.assertEqual(
                Path(d1, "project.pbxproj").read_text(), expected
            )
            self.assertEqual(
                Path(d2, "project.pbxproj").read_text(), expected
            )

    def test_recursive_check_mode(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            d1 = os.path.join(tmpdir, "A.xcodeproj")
            os.makedirs(d1)
            shutil.copy2(
                FIXTURES_DIR / "basic_sorted.pbxproj",
                os.path.join(d1, "project.pbxproj"),
            )
            r = run_script("--recursive", "--check", tmpdir)
            self.assertEqual(r.returncode, 0)

    def test_recursive_check_unsorted(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            d1 = os.path.join(tmpdir, "App.xcodeproj")
            os.makedirs(d1)
            shutil.copy2(
                FIXTURES_DIR / "basic_unsorted.pbxproj",
                os.path.join(d1, "project.pbxproj"),
            )
            r = run_script("--recursive", "--check", tmpdir)
            self.assertEqual(r.returncode, 1)


if __name__ == "__main__":
    unittest.main()
