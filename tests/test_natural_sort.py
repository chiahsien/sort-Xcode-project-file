import unittest

from tests._helpers import sorter


class TestNaturalSortKey(unittest.TestCase):

    def _lt(self, a, b, ci=False):
        self.assertLess(
            sorter.natural_sort_key(a, case_insensitive=ci),
            sorter.natural_sort_key(b, case_insensitive=ci),
        )

    def _eq(self, a, b, ci=False):
        self.assertEqual(
            sorter.natural_sort_key(a, case_insensitive=ci),
            sorter.natural_sort_key(b, case_insensitive=ci),
        )

    def test_basic_alphabetical(self):
        self._lt("abc", "def")

    def test_numeric_comparison(self):
        self._lt("file2", "file10")

    def test_leading_zeros(self):
        self._lt("1", "01")
        self._lt("01", "001")
        self._lt("1", "001")

    def test_empty_string(self):
        self._lt("", "a")

    def test_mixed_tokens(self):
        self._lt("a1b", "a2b")

    def test_shorter_prefix(self):
        self._lt("file", "file2")

    def test_case_sensitive_uppercase_first(self):
        self._lt("File", "file")

    def test_case_insensitive_equal(self):
        self._eq("File", "file", ci=True)

    def test_pure_digits(self):
        self._lt("2", "10")

    def test_all_non_digits(self):
        self._lt("aaa", "bbb")

    def test_complex_multi_token(self):
        self._lt("img12_v2", "img12_v10")

    def test_equal_strings(self):
        self._eq("abc", "abc")
        self._eq("file10", "file10")

    def test_case_insensitive_numeric(self):
        self._lt("File2", "file10", ci=True)

    def test_empty_vs_empty(self):
        self._eq("", "")


if __name__ == "__main__":
    unittest.main()
