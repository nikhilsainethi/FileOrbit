"""Regression checks for package-verification assertions; no converters required."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("package_verifier", Path(__file__).with_name("verify-package.py"))
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class OfficeOCRSentinelTests(unittest.TestCase):
    sentinel = "FileOrbit packaged Office round-trip 73915"

    def test_contiguous_sentence(self):
        self.assertTrue(verifier.contains_office_ocr_sentinel(self.sentinel, self.sentinel))

    def test_vision_separate_numeric_block_from_ci(self):
        recognized = "FILEORBIT PACKAGED OFFICE ROUND TRIP\nUNICODE CHECK CAF S\n73915"
        self.assertTrue(verifier.contains_office_ocr_sentinel(recognized, self.sentinel))

    def test_missing_word_is_rejected(self):
        self.assertFalse(verifier.contains_office_ocr_sentinel("FileOrbit Office round-trip 73915", self.sentinel))

    def test_missing_marker_is_rejected(self):
        self.assertFalse(verifier.contains_office_ocr_sentinel("FileOrbit packaged Office round-trip", self.sentinel))

    def test_wrong_marker_is_rejected(self):
        self.assertFalse(verifier.contains_office_ocr_sentinel("FileOrbit packaged Office round-trip 73916", self.sentinel))

    def test_marker_substring_is_rejected(self):
        self.assertFalse(verifier.contains_office_ocr_sentinel("FileOrbit packaged Office round-trip 739150", self.sentinel))

    def test_reordered_sentence_is_rejected(self):
        self.assertFalse(verifier.contains_office_ocr_sentinel("Office packaged FileOrbit round-trip 73915", self.sentinel))


if __name__ == "__main__":
    unittest.main()
