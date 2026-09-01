#!/usr/bin/env python3
"""Issue #78 R1 characterization: the ANI candidate key-record parsing contract.

Pins the real _parse_candidate_key_record() directly against synthetic
bytearrays only: no full ANI-file parsing, no real X4 data, and no
interpretation of key-record field semantics. Slot identity and byte offsets
come from the production _ANI_KEY_RECORD_CANDIDATE_SLOTS map; slot indexes
refer only to candidate types and positions, never to field meanings.
"""
from __future__ import annotations

import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    AniDescriptorError,
    _ANI_KEY_RECORD_CANDIDATE_SLOTS,
    _ANI_KEY_RECORD_SIZE,
    _parse_candidate_key_record,
)

_SLOT_COUNT = len(_ANI_KEY_RECORD_CANDIDATE_SLOTS)
_UNSET_VALUE = 0
_UNSET_RAW_BITS = "0x00000000"


def _slot_index(candidate_type: str, last: bool = False) -> int:
    """Index into the production slot map of the first or last slot of a type."""

    matches = [
        index
        for index, slot in enumerate(_ANI_KEY_RECORD_CANDIDATE_SLOTS)
        if slot["candidate_type"] == candidate_type
    ]
    if not matches:
        raise AssertionError(f"no candidate {candidate_type} slot present")
    return matches[-1] if last else matches[0]


class AniKeyRecordContractTests(unittest.TestCase):
    def test_wrong_record_sizes_raise_unsupported_ani_key_framing(self) -> None:
        for size in (0, 127, 129):
            with self.subTest(size=size):
                with self.assertRaises(AniDescriptorError) as caught:
                    _parse_candidate_key_record(b"\x00" * size)

                self.assertEqual(caught.exception.code, "unsupported_ani_key_framing")
                self.assertEqual(
                    caught.exception.details["candidate_record_size"], size
                )

    def test_all_zero_record_decodes_one_zero_value_and_raw_bits_per_slot(self) -> None:
        values, raw_bits = _parse_candidate_key_record(
            b"\x00" * _ANI_KEY_RECORD_SIZE
        )

        self.assertEqual(len(values), _SLOT_COUNT)
        self.assertEqual(len(raw_bits), _SLOT_COUNT)
        self.assertEqual(
            list(zip(values, raw_bits)),
            [(_UNSET_VALUE, _UNSET_RAW_BITS)] * _SLOT_COUNT,
        )

    def test_typed_slot_decoding_preserves_exact_raw_bits(self) -> None:
        first_float32 = _slot_index("float32_le")
        first_enum32 = _slot_index("enum32_le")
        int32 = _slot_index("int32_le")
        last_uint32 = _slot_index("uint32_le", last=True)
        set_indexes = {first_float32, first_enum32, int32, last_uint32}

        record = bytearray(_ANI_KEY_RECORD_SIZE)
        assignments = (
            (first_float32, "<f", 1.5),
            (first_enum32, "<i", -7),
            (int32, "<i", -9),
            (last_uint32, "<I", 0xFFFFFFFF),
        )
        for index, format, value in assignments:
            offset = int(_ANI_KEY_RECORD_CANDIDATE_SLOTS[index]["byte_offset"])
            record[offset : offset + 4] = struct.pack(format, value)

        values, raw_bits = _parse_candidate_key_record(bytes(record))

        self.assertEqual(values[first_float32], 1.5)
        self.assertEqual(values[first_enum32], -7)
        self.assertEqual(values[int32], -9)
        self.assertEqual(values[last_uint32], 0xFFFFFFFF)
        self.assertEqual(raw_bits[first_float32], "0x3fc00000")
        self.assertEqual(raw_bits[first_enum32], "0xfffffff9")
        self.assertEqual(raw_bits[int32], "0xfffffff7")
        self.assertEqual(raw_bits[last_uint32], "0xffffffff")
        for index in range(_SLOT_COUNT):
            if index in set_indexes:
                continue
            self.assertEqual(values[index], _UNSET_VALUE)
            self.assertEqual(raw_bits[index], _UNSET_RAW_BITS)


if __name__ == "__main__":
    unittest.main()
