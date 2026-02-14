import unittest

from tests._helpers import sorter


class TestIsDirectory(unittest.TestCase):

    def test_has_extension_is_file(self):
        self.assertFalse(sorter.is_directory("AppDelegate.m"))
        self.assertFalse(sorter.is_directory("Info.plist"))
        self.assertFalse(sorter.is_directory("file.swift"))

    def test_no_extension_is_directory(self):
        self.assertTrue(sorter.is_directory("Models"))
        self.assertTrue(sorter.is_directory("Resources"))
        self.assertTrue(sorter.is_directory("Alpha"))

    def test_known_file_case_sensitive(self):
        self.assertFalse(sorter.is_directory("create_hash_table"))

    def test_known_file_case_mismatch_sensitive(self):
        self.assertTrue(sorter.is_directory("CREATE_HASH_TABLE", case_insensitive=False))

    def test_known_file_case_insensitive(self):
        self.assertFalse(sorter.is_directory("CREATE_HASH_TABLE", case_insensitive=True))
        self.assertFalse(sorter.is_directory("Create_Hash_Table", case_insensitive=True))

    def test_dot_in_middle(self):
        self.assertFalse(sorter.is_directory("file.name.ext"))

    def test_single_char_extension(self):
        self.assertFalse(sorter.is_directory("file.m"))
        self.assertFalse(sorter.is_directory("file.h"))


if __name__ == "__main__":
    unittest.main()
