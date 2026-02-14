import os
import shutil
import tempfile
import unittest
from pathlib import Path

from tests._helpers import sorter

FIXTURES_DIR = Path(__file__).parent / "fixtures"


class TestSortProject(unittest.TestCase):

    def _sort_and_read(self, fixture_name, **kwargs):
        src = FIXTURES_DIR / fixture_name
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = Path(tmpdir) / "project.pbxproj"
            shutil.copy2(src, dest)
            sorter.sort_project_file(dest, **kwargs)
            return dest.read_text(encoding="utf-8")

    def _expected(self, fixture_name):
        return (FIXTURES_DIR / fixture_name).read_text(encoding="utf-8")

    def test_basic_sort_case_sensitive(self):
        result = self._sort_and_read("basic_unsorted.pbxproj")
        expected = self._expected("basic_sorted.pbxproj")
        self.assertEqual(result, expected)

    def test_basic_sort_case_insensitive(self):
        result = self._sort_and_read("basic_unsorted.pbxproj", case_insensitive=True)
        expected = self._expected("basic_ci_sorted.pbxproj")
        self.assertEqual(result, expected)

    def test_frameworks_preserved(self):
        result = self._sort_and_read("with_frameworks.pbxproj")
        expected = self._expected("with_frameworks_sorted.pbxproj")
        self.assertEqual(result, expected)

    def test_duplicates_removed(self):
        result = self._sort_and_read("with_duplicates.pbxproj")
        expected = self._expected("with_duplicates_sorted.pbxproj")
        self.assertEqual(result, expected)

    def test_empty_arrays(self):
        result = self._sort_and_read("empty_arrays.pbxproj")
        expected = self._expected("empty_arrays_sorted.pbxproj")
        self.assertEqual(result, expected)

    def test_idempotent(self):
        expected = self._expected("basic_sorted.pbxproj")
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = Path(tmpdir) / "project.pbxproj"
            shutil.copy2(FIXTURES_DIR / "basic_sorted.pbxproj", dest)
            sorter.sort_project_file(dest)
            result = dest.read_text(encoding="utf-8")
        self.assertEqual(result, expected)

    def test_check_mode_sorted(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = Path(tmpdir) / "project.pbxproj"
            shutil.copy2(FIXTURES_DIR / "basic_sorted.pbxproj", dest)
            is_sorted = sorter.sort_project_file(dest, check_only=True)
        self.assertTrue(is_sorted)

    def test_check_mode_unsorted(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = Path(tmpdir) / "project.pbxproj"
            shutil.copy2(FIXTURES_DIR / "basic_unsorted.pbxproj", dest)
            is_sorted = sorter.sort_project_file(dest, check_only=True)
        self.assertFalse(is_sorted)

    def test_check_mode_does_not_modify(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = Path(tmpdir) / "project.pbxproj"
            shutil.copy2(FIXTURES_DIR / "basic_unsorted.pbxproj", dest)
            original = dest.read_text(encoding="utf-8")
            sorter.sort_project_file(dest, check_only=True)
            after = dest.read_text(encoding="utf-8")
        self.assertEqual(original, after)


if __name__ == "__main__":
    unittest.main()
