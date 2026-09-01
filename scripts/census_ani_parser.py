"""Bounded ANI header, descriptor, and candidate key-record parsing for the Issue #78 census tools."""
from __future__ import annotations

import math
import struct
from collections import Counter
from pathlib import Path

_ANI_HEADER_SIZE = 16
_ANI_DESCRIPTOR_SIZE = 160
_ANI_STRING_SIZE = 64
_ANI_DESCRIPTOR_OFFSET_148 = 148
_ANI_KEY_RECORD_SIZE = 128
_ANI_CHANNEL_COUNT_FIELDS = (
    "position",
    "rotation",
    "scale",
    "pre_scale",
    "post_scale",
)

# Candidate types and order only. The slot names deliberately encode byte
# offsets rather than meanings. X4Converter supplies the third-party layout
# lead; shipped ANI values do not establish field semantics.
_ANI_KEY_RECORD_CANDIDATE_TYPES = (
    ("float32_le",) * 3
    + ("enum32_le",) * 3
    + ("float32_le",) * 18
    + ("int32_le",)
    + ("float32_le",) * 6
    + ("uint32_le",)
)
_ANI_KEY_RECORD_CANDIDATE_SLOTS = tuple(
    {
        "slot_id": f"slot_{byte_offset:03d}",
        "byte_offset": byte_offset,
        "width_bytes": 4,
        "candidate_type": candidate_type,
    }
    for byte_offset, candidate_type in zip(
        range(0, _ANI_KEY_RECORD_SIZE, 4), _ANI_KEY_RECORD_CANDIDATE_TYPES
    )
)
_ANI_KEY_RECORD_CANDIDATE_BYTE_COUNTS = Counter(
    byte_index
    for slot in _ANI_KEY_RECORD_CANDIDATE_SLOTS
    for byte_index in range(
        int(slot["byte_offset"]),
        int(slot["byte_offset"]) + int(slot["width_bytes"]),
    )
)
_ANI_KEY_RECORD_CANDIDATE_UNACCOUNTED_BYTES = tuple(
    byte_index
    for byte_index in range(_ANI_KEY_RECORD_SIZE)
    if _ANI_KEY_RECORD_CANDIDATE_BYTE_COUNTS[byte_index] == 0
)
_ANI_KEY_RECORD_CANDIDATE_OVERLAPPING_BYTES = tuple(
    byte_index
    for byte_index in range(_ANI_KEY_RECORD_SIZE)
    if _ANI_KEY_RECORD_CANDIDATE_BYTE_COUNTS[byte_index] > 1
)


class AniDescriptorError(Exception):
    """A bounded ANI header/descriptor-layout failure."""

    def __init__(self, code: str, message: str, **details: object):
        self.code = code
        self.message = message
        self.details = details
        super().__init__(message)


def _decode_ani_descriptor_string(
    field: bytes, field_name: str, descriptor_index: int
) -> str:
    if b"\0" not in field:
        raise AniDescriptorError(
            "invalid_ani_descriptor_string",
            "ANI descriptor string has no NUL terminator within its fixed field",
            descriptor_index=descriptor_index,
            descriptor_field=field_name,
        )
    encoded = field.split(b"\0", 1)[0]
    if not encoded:
        raise AniDescriptorError(
            "invalid_ani_descriptor_string",
            "ANI descriptor string is empty",
            descriptor_index=descriptor_index,
            descriptor_field=field_name,
        )
    try:
        value = encoded.decode("ascii")
    except UnicodeDecodeError as exc:
        raise AniDescriptorError(
            "invalid_ani_descriptor_string",
            "ANI descriptor string is not ASCII",
            descriptor_index=descriptor_index,
            descriptor_field=field_name,
        ) from exc
    if any(ord(character) < 32 or ord(character) > 126 for character in value):
        raise AniDescriptorError(
            "invalid_ani_descriptor_string",
            "ANI descriptor string contains a non-printable ASCII character",
            descriptor_index=descriptor_index,
            descriptor_field=field_name,
        )
    return value


def _parse_candidate_key_record(record: bytes) -> tuple[list[float | int], list[str]]:
    """Parse one complete candidate record as raw typed slots only."""

    if (
        _ANI_KEY_RECORD_CANDIDATE_UNACCOUNTED_BYTES
        or _ANI_KEY_RECORD_CANDIDATE_OVERLAPPING_BYTES
    ):
        raise AniDescriptorError(
            "unsupported_candidate_ani_key_layout",
            "candidate ANI key slot map does not account for every byte exactly once",
            unaccounted_bytes=list(_ANI_KEY_RECORD_CANDIDATE_UNACCOUNTED_BYTES),
            overlapping_bytes=list(_ANI_KEY_RECORD_CANDIDATE_OVERLAPPING_BYTES),
        )
    if len(record) != _ANI_KEY_RECORD_SIZE:
        raise AniDescriptorError(
            "unsupported_ani_key_framing",
            "candidate ANI key record is not exactly 128 bytes",
            candidate_record_size=len(record),
        )
    values: list[float | int] = []
    raw_bits: list[str] = []
    for slot in _ANI_KEY_RECORD_CANDIDATE_SLOTS:
        offset = int(slot["byte_offset"])
        candidate_type = str(slot["candidate_type"])
        format_character = {
            "float32_le": "f",
            "enum32_le": "i",
            "int32_le": "i",
            "uint32_le": "I",
        }[candidate_type]
        values.append(struct.unpack_from("<" + format_character, record, offset)[0])
        raw_bits.append(f"0x{struct.unpack_from('<I', record, offset)[0]:08x}")
    return values, raw_bits


def _candidate_float32_decode(raw_bits: int) -> dict[str, object]:
    value = struct.unpack("<f", struct.pack("<I", raw_bits))[0]
    if math.isnan(value):
        return {"kind": "nan", "value": None}
    if math.isinf(value):
        return {
            "kind": "positive_infinity" if value > 0 else "negative_infinity",
            "value": None,
        }
    return {"kind": "finite", "value": value}


def _parse_ani_descriptors(path: Path) -> list[dict[str, object]]:
    """Parse ANI v1 descriptors and assign candidate fixed key-record ranges."""

    try:
        data = path.read_bytes()
    except OSError as exc:
        raise AniDescriptorError(
            "unreadable_ani_resource", f"resolved ANI resource could not be read: {exc}"
        ) from exc
    if len(data) < _ANI_HEADER_SIZE:
        raise AniDescriptorError("truncated_ani_header", "ANI header is truncated")

    descriptor_count, key_offset, version, header_padding = struct.unpack_from("<4I", data)
    if version != 1 or header_padding != 0:
        raise AniDescriptorError(
            "unsupported_ani_layout",
            "ANI header version or reserved field is unsupported",
            ani_version=version,
            header_padding=header_padding,
        )
    descriptor_end = _ANI_HEADER_SIZE + descriptor_count * _ANI_DESCRIPTOR_SIZE
    if descriptor_end > len(data):
        raise AniDescriptorError(
            "truncated_ani_descriptor_section",
            "ANI descriptor section is truncated",
            descriptor_count=descriptor_count,
            descriptor_end=descriptor_end,
            file_size=len(data),
        )
    if key_offset != descriptor_end:
        raise AniDescriptorError(
            "unsupported_ani_layout",
            "ANI key-data offset does not exactly follow the fixed descriptor table",
            descriptor_count=descriptor_count,
            expected_key_offset=descriptor_end,
            key_offset=key_offset,
        )

    descriptors: list[dict[str, object]] = []
    seen: set[tuple[str, str]] = set()
    for index in range(descriptor_count):
        offset = _ANI_HEADER_SIZE + index * _ANI_DESCRIPTOR_SIZE
        part = _decode_ani_descriptor_string(
            data[offset : offset + _ANI_STRING_SIZE], "part", index
        )
        subname = _decode_ani_descriptor_string(
            data[
                offset + _ANI_STRING_SIZE : offset + 2 * _ANI_STRING_SIZE
            ],
            "subname",
            index,
        )
        channel_count_values = struct.unpack_from("<5I", data, offset + 128)
        channel_counts = dict(zip(_ANI_CHANNEL_COUNT_FIELDS, channel_count_values))
        descriptor_offset_148_raw_bits = struct.unpack_from(
            "<I", data, offset + _ANI_DESCRIPTOR_OFFSET_148
        )[0]
        descriptor_padding = struct.unpack_from("<2I", data, offset + 152)
        if descriptor_padding != (0, 0):
            raise AniDescriptorError(
                "unsupported_ani_layout",
                "ANI descriptor reserved fields are non-zero",
                descriptor_index=index,
                descriptor_padding=list(descriptor_padding),
            )
        identity = (part, subname)
        if identity in seen:
            raise AniDescriptorError(
                "duplicate_ani_descriptor",
                "ANI contains a duplicate exact (part, subname) descriptor identity",
                descriptor_index=index,
                part=part,
                subname=subname,
            )
        seen.add(identity)
        descriptors.append(
            {
                "descriptor_index": index,
                "part": part,
                "subname": subname,
                "channel_counts": channel_counts,
                "descriptor_offset_148": {
                    "byte_offset_within_descriptor": _ANI_DESCRIPTOR_OFFSET_148,
                    "width_bytes": 4,
                    "raw_bits": f"0x{descriptor_offset_148_raw_bits:08x}",
                    "candidate_float32_decode": _candidate_float32_decode(
                        descriptor_offset_148_raw_bits
                    ),
                    "raw_bits_evidence_classification": "shipped-source",
                    "candidate_decode_evidence_classification": (
                        "third-party-technique"
                    ),
                },
            }
        )

    total_key_records = sum(
        int(descriptor["channel_counts"][field])
        for descriptor in descriptors
        for field in _ANI_CHANNEL_COUNT_FIELDS
    )
    expected_file_size = key_offset + total_key_records * _ANI_KEY_RECORD_SIZE
    if expected_file_size > len(data):
        raise AniDescriptorError(
            "truncated_ani_key_section",
            "ANI key section is shorter than its descriptor channel counts require",
            key_offset=key_offset,
            key_record_size=_ANI_KEY_RECORD_SIZE,
            expected_key_records=total_key_records,
            expected_file_size=expected_file_size,
            file_size=len(data),
        )
    if expected_file_size < len(data):
        raise AniDescriptorError(
            "unconsumed_ani_key_section",
            "ANI contains bytes outside the uniquely framed descriptor key records",
            key_offset=key_offset,
            key_record_size=_ANI_KEY_RECORD_SIZE,
            expected_key_records=total_key_records,
            expected_file_size=expected_file_size,
            file_size=len(data),
            unconsumed_bytes=len(data) - expected_file_size,
        )

    key_record_cursor = 0
    byte_cursor = key_offset
    for descriptor in descriptors:
        descriptor_record_start = key_record_cursor
        descriptor_byte_start = byte_cursor
        channels: dict[str, object] = {}
        for field in _ANI_CHANNEL_COUNT_FIELDS:
            record_count = int(descriptor["channel_counts"][field])
            record_start = key_record_cursor
            byte_start = byte_cursor
            key_record_cursor += record_count
            byte_cursor += record_count * _ANI_KEY_RECORD_SIZE
            channels[field] = {
                "record_count": record_count,
                "record_range": {
                    "start": record_start,
                    "end_exclusive": key_record_cursor,
                },
                "byte_range": {
                    "start": byte_start,
                    "end_exclusive": byte_cursor,
                },
            }
        descriptor["key_data"] = {
            "record_range": {
                "start": descriptor_record_start,
                "end_exclusive": key_record_cursor,
            },
            "byte_range": {
                "start": descriptor_byte_start,
                "end_exclusive": byte_cursor,
            },
            "channels": channels,
        }

    if key_record_cursor != total_key_records or byte_cursor != len(data):
        raise AniDescriptorError(
            "unsupported_ani_key_framing",
            "ANI key-record ranges do not form one exact non-overlapping file span",
            assigned_key_records=key_record_cursor,
            expected_key_records=total_key_records,
            assigned_file_end=byte_cursor,
            file_size=len(data),
        )

    for descriptor in descriptors:
        record_range = descriptor["key_data"]["record_range"]
        raw_records = []
        for record_index in range(
            int(record_range["start"]), int(record_range["end_exclusive"])
        ):
            record_offset = key_offset + record_index * _ANI_KEY_RECORD_SIZE
            raw_values, raw_bits = _parse_candidate_key_record(
                data[record_offset : record_offset + _ANI_KEY_RECORD_SIZE]
            )
            raw_records.append(
                {
                    "record_index": record_index,
                    "byte_offset": record_offset,
                    "raw_values": raw_values,
                    "raw_bits": raw_bits,
                }
            )
        descriptor["_candidate_raw_key_records"] = raw_records
    return descriptors
