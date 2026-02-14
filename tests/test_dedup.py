import unittest

from tests._helpers import sorter


class TestUniq(unittest.TestCase):

    def test_basic_dedup(self):
        self.assertEqual(sorter.uniq(["a", "b", "a", "c", "b"]), ["a", "b", "c"])

    def test_all_same(self):
        self.assertEqual(sorter.uniq(["x", "x", "x"]), ["x"])

    def test_empty(self):
        self.assertEqual(sorter.uniq([]), [])

    def test_single(self):
        self.assertEqual(sorter.uniq(["a"]), ["a"])

    def test_preserves_first_occurrence_order(self):
        self.assertEqual(
            sorter.uniq(["c", "b", "a", "b", "c"]),
            ["c", "b", "a"],
        )

    def test_whitespace_sensitive(self):
        self.assertEqual(sorter.uniq(["a ", "a"]), ["a ", "a"])

    def test_no_duplicates(self):
        self.assertEqual(sorter.uniq(["a", "b", "c"]), ["a", "b", "c"])


if __name__ == "__main__":
    unittest.main()
