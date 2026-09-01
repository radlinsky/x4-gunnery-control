#!/usr/bin/env python3
"""Issue #78 R1 characterization: the ANI descriptor-string decoding contract.

Pins the real _decode_ani_descriptor_string() directly against raw bytes
only: no ANI-file parsing, no key records, no real X4 data, and no
production changes.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    AniDescriptorError,
    _decode_ani_descriptor_string,
)

_DESCRIPTOR_INDEX = 3
_FIELD_NAME = "muzzle_name"


class AniDescriptorStringContractTests(unittest.TestCase):
    def _assert_invalid(self, field: bytes) -> None:
        """Assert the failure code and that both detail keys are preserved."""
        with self.assertRaises(AniDescriptorError) as caught:
            _decode_ani_descriptor_string(
                field, _FIELD_NAME, _DESCRIPTOR_INDEX
            )
        self.assertEqual(
            caught.exception.code, "invalid_ani_descriptor_string"
        )
        self.assertEqual(
            caught.exception.details["descriptor_index"], _DESCRIPTOR_INDEX
        )
        self.assertEqual(
            caught.exception.details["descriptor_field"], _FIELD_NAME
        )

    def test_printable_ascii_before_nul_returns_text_before_first_nul(self) -> None:
        self.assertEqual(
            _decode_ani_descriptor_string(
                b"muzzle_01\0", _FIELD_NAME, _DESCRIPTOR_INDEX
            ),
            "muzzle_01",
        )
        self.assertEqual(
            _decode_ani_descriptor_string(b"abc\0def\0", "name", 7),
            "abc",
        )

    def test_field_without_nul_raises_invalid_ani_descriptor_string(self) -> None:
        self._assert_invalid(b"muzzle_01")
        self._assert_invalid(b"")

    def test_nul_as_first_byte_raises_invalid_ani_descriptor_string(self) -> None:
        self._assert_invalid(b"\0muzzle_01")
        self._assert_invalid(b"\0")

    def test_non_ascii_byte_before_nul_raises_invalid_ani_descriptor_string(
        self,
    ) -> None:
        self._assert_invalid(b"m\xf8zzle_01\0")

    def test_non_printable_ascii_byte_before_nul_raises_invalid_ani_descriptor_string(
        self,
    ) -> None:
        self._assert_invalid(b"m\x1bzzle_01\0")
        self._assert_invalid(b"m\x7fzzle_01\0")


if __name__ == "__main__":
    unittest.main()
