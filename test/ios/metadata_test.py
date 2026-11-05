"""Protect conservative ASCII app names for SideStore App ID registration."""

import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class SideStoreMetadataTest(unittest.TestCase):
    def test_registration_names_are_ascii_letters_digits_and_spaces(self):
        with (ROOT / "ios/Runner/Info.plist").open("rb") as source:
            metadata = plistlib.load(source)
        # The installed SideStore stable build forwards Unicode letters to
        # Apple's appIdName parameter; our Korean display name was rejected.
        # Keep both the preferred name and the fallback conservatively ASCII.
        for key in ("CFBundleDisplayName", "CFBundleName"):
            with self.subTest(key=key):
                name = metadata[key]
                self.assertIsInstance(name, str)
                self.assertRegex(name, r"\A[A-Za-z0-9]+(?: [A-Za-z0-9]+)*\Z")
                self.assertEqual(name, name.strip())


if __name__ == "__main__":
    unittest.main()
