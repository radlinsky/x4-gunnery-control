#!/usr/bin/env python3
"""Issue #78 R1 characterization: the basic ANI header/framing error contract.

Pins the real _parse_ani_descriptors() against tiny synthetic tempfile files
only: no real X4 data, no production changes, no descriptor string contents,
and no key records. Headers are built with
struct.pack("<4I", descriptor_count, key_offset, version, header_padding),
matching the little-endian header layout the census module expects.
"""
from __future__ import annotations

import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    AniDescriptorError,
    _parse_ani_descriptors,
)

_ANI_HEADER_SIZE = 16
_ANI_DESCRIPTOR_SIZE = 160


def _header(
    descriptor_count: int, key_offset: int, version: int, header_padding: int
) -> bytes:
    """Build one raw ANI header exactly as the census module expects it."""

    return struct.pack("<4I", descriptor_count, key_offset, version, header_padding)


class AniHeaderContractTests(unittest.TestCase):
    def test_missing_file_raises_unreadable_ani_resource(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "missing.ANI"

            with self.assertRaises(AniDescriptorError) as caught:
                _parse_ani_descriptors(path)

            self.assertEqual(caught.exception.code, "unreadable_ani_resource")

    def test_file_shorter_than_header_raises_truncated_ani_header(self) -> None:
        for size in (0, 8, 15):
            with self.subTest(size=size), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "short.ANI"
                path.write_bytes(b"\x00" * size)

                with self.assertRaises(AniDescriptorError) as caught:
                    _parse_ani_descriptors(path)

                self.assertEqual(caught.exception.code, "truncated_ani_header")

    def test_header_version_not_one_raises_unsupported_ani_layout(self) -> None:
        for version in (0, 2):
            with self.subTest(version=version), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "wrong_version.ANI"
                path.write_bytes(_header(0, _ANI_HEADER_SIZE, version, 0))

                with self.assertRaises(AniDescriptorError) as caught:
                    _parse_ani_descriptors(path)

                self.assertEqual(caught.exception.code, "unsupported_ani_layout")

    def test_declared_descriptor_without_section_raises_truncated_section(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "missing_section.ANI"
            path.write_bytes(
                _header(1, _ANI_HEADER_SIZE + _ANI_DESCRIPTOR_SIZE, 1, 0)
            )

            with self.assertRaises(AniDescriptorError) as caught:
                _parse_ani_descriptors(path)

            self.assertEqual(caught.exception.code, "truncated_ani_descriptor_section")

    def test_key_offset_past_descriptor_table_raises_unsupported_ani_layout(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            table_end = _ANI_HEADER_SIZE + _ANI_DESCRIPTOR_SIZE
            path = Path(tmp) / "bad_key_offset.ANI"
            path.write_bytes(
                _header(1, table_end + _ANI_DESCRIPTOR_SIZE, 1, 0)
                + b"\x00" * _ANI_DESCRIPTOR_SIZE
            )

            with self.assertRaises(AniDescriptorError) as caught:
                _parse_ani_descriptors(path)

            self.assertEqual(caught.exception.code, "unsupported_ani_layout")


if __name__ == "__main__":
    unittest.main()
