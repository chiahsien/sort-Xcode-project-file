import unittest

from tests._helpers import sorter


class TestExtractFilename(unittest.TestCase):

    def test_child_entry(self):
        line = "\t\t\t\tAABBCCDD00112233EEFF4455 /* AppDelegate.m */,"
        self.assertEqual(sorter.extract_filename(line, sorter.REGEX_CHILD_ENTRY), "AppDelegate.m")

    def test_child_entry_with_spaces(self):
        line = "\t\t\t\tAABBCCDD00112233EEFF4455 /* My File.m */,"
        self.assertEqual(sorter.extract_filename(line, sorter.REGEX_CHILD_ENTRY), "My File.m")

    def test_child_entry_directory(self):
        line = "\t\t\t\tAABBCCDD00112233EEFF4455 /* Models */,"
        self.assertEqual(sorter.extract_filename(line, sorter.REGEX_CHILD_ENTRY), "Models")

    def test_no_match_returns_empty(self):
        self.assertEqual(sorter.extract_filename("random text", sorter.REGEX_CHILD_ENTRY), "")

    def test_file_entry_no_match_real_xcode_format(self):
        # Real Xcode format: /* Name in Sources */, -- "in" is inside comment
        # The regex expects /* Name */ in Sources, so this should NOT match
        line = "\t\t\t\tAABBCCDD00112233EEFF4455 /* Main.swift in Sources */,"
        self.assertEqual(sorter.extract_filename(line, sorter.REGEX_FILE_ENTRY), "")


if __name__ == "__main__":
    unittest.main()
