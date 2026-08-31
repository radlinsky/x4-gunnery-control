#!/usr/bin/env python3
"""Build the Issue #72 macro-driven X4 9.00 turret asset census.

This tool stops at exact authored connection paths, firing-endpoint connection
identities, ANI descriptor/source-part identity, descriptor channel counts,
candidate key-record byte ownership, and raw candidate typed-slot patterns. It
does not assign key-record field semantics or interpret transforms, timing,
interpolation, pivots, axes, joints, descriptor relevance, active pose, or
prospective muzzle position.
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path
from typing import Iterable, Mapping, Sequence

REQUIRED_SOURCE_SETS = (
    "base",
    "ego_dlc_split",
    "ego_dlc_terran",
    "ego_dlc_pirate",
    "ego_dlc_boron",
    "ego_dlc_timelines",
    "ego_dlc_mini_01",
    "ego_dlc_mini_02",
)
_INCLUDED_CLASSES = frozenset(("turret", "missileturret"))
_ANI_HEADER_SIZE = 16
_ANI_DESCRIPTOR_SIZE = 160
_ANI_STRING_SIZE = 64
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
_ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOTS = (
    _ANI_KEY_RECORD_CANDIDATE_SLOTS[:3]
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


class CensusError(Exception):
    """A fail-closed census error with deterministic machine-readable details."""

    def __init__(self, anomalies: Iterable[dict[str, object]]):
        self.anomalies = sorted(
            anomalies,
            key=lambda item: (
                str(item.get("code", "")),
                str(item.get("source_set", "")),
                str(item.get("source_file", "")),
                str(item.get("macro", "")),
                str(item.get("component", "")),
            ),
        )
        self.codes = tuple(str(item["code"]) for item in self.anomalies)
        super().__init__(render_json({"status": "error", "anomalies": self.anomalies}).rstrip())


def _anomaly(code: str, message: str, **details: object) -> dict[str, object]:
    return {"code": code, "message": message, **details}


def _validate_source_sets(source_sets: Mapping[str, Path]) -> dict[str, Path]:
    anomalies: list[dict[str, object]] = []
    expected = set(REQUIRED_SOURCE_SETS)
    supplied = set(source_sets)

    for name in sorted(expected - supplied):
        anomalies.append(
            _anomaly("missing_required_source_set", "required official source set was not supplied", source_set=name)
        )
    for name in sorted(supplied - expected):
        anomalies.append(
            _anomaly("unexpected_source_set", "source set is outside the Issue #72 official set", source_set=name)
        )

    normalized: dict[str, Path] = {}
    for name in REQUIRED_SOURCE_SETS:
        if name not in source_sets:
            continue
        path = Path(source_sets[name])
        if not path.is_dir():
            anomalies.append(
                _anomaly(
                    "unavailable_required_source_set",
                    "required official source-set directory is unavailable",
                    source_set=name,
                )
            )
        elif not _xml_files(path):
            anomalies.append(
                _anomaly(
                    "empty_required_source_set",
                    "required official source-set directory contains no XML source",
                    source_set=name,
                )
            )
        else:
            normalized[name] = path

    if anomalies:
        raise CensusError(anomalies)
    return normalized


def _validate_resource_sets(resource_sets: Mapping[str, Path]) -> dict[str, Path]:
    anomalies: list[dict[str, object]] = []
    expected = set(REQUIRED_SOURCE_SETS)
    supplied = set(resource_sets)

    for name in sorted(expected - supplied):
        anomalies.append(
            _anomaly(
                "missing_required_resource_set",
                "required official ANI resource set was not supplied",
                source_set=name,
            )
        )
    for name in sorted(supplied - expected):
        anomalies.append(
            _anomaly(
                "unexpected_resource_set",
                "ANI resource set is outside the Issue #72 official set",
                source_set=name,
            )
        )

    normalized: dict[str, Path] = {}
    for name in REQUIRED_SOURCE_SETS:
        if name not in resource_sets:
            continue
        path = Path(resource_sets[name])
        if not path.is_dir():
            anomalies.append(
                _anomaly(
                    "unavailable_required_resource_set",
                    "required official ANI resource-set directory is unavailable",
                    source_set=name,
                )
            )
        elif not _ani_files(path):
            anomalies.append(
                _anomaly(
                    "empty_required_resource_set",
                    "required official ANI resource-set directory contains no ANI resources",
                    source_set=name,
                )
            )
        else:
            normalized[name] = path

    if anomalies:
        raise CensusError(anomalies)
    return normalized


def _xml_files(root: Path) -> list[Path]:
    return sorted(
        (path for path in root.rglob("*") if path.is_file() and path.suffix.lower() == ".xml"),
        key=lambda path: path.relative_to(root).as_posix(),
    )


def _ani_files(root: Path) -> list[Path]:
    return sorted(
        (path for path in root.rglob("*") if path.is_file() and path.suffix.lower() == ".ani"),
        key=lambda path: path.relative_to(root).as_posix(),
    )


def _normalized_resource_identity(value: str) -> str:
    """Normalize only separators and case for resource identity comparison."""

    return value.replace("\\", "/").casefold()


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


def _summarize_candidate_raw_key_records(
    records: list[dict[str, object]],
) -> dict[str, object]:
    slot_distributions: list[dict[str, object]] = []
    constant_slots: list[str] = []
    zero_constant_slots: list[str] = []
    anomalies: list[dict[str, object]] = []
    for slot_index, slot in enumerate(_ANI_KEY_RECORD_CANDIDATE_SLOTS):
        values = [record["raw_values"][slot_index] for record in records]
        raw_bits = [str(record["raw_bits"][slot_index]) for record in records]
        distinct_raw_bits = sorted(set(raw_bits))
        constant_raw_bits = (
            distinct_raw_bits[0] if len(distinct_raw_bits) == 1 and records else None
        )
        zero_count = sum(value == 0 for value in values)
        distribution: dict[str, object] = {
            **slot,
            "value_count": len(values),
        }
        if slot["candidate_type"] == "float32_le":
            finite_count = sum(math.isfinite(float(value)) for value in values)
            non_finite_count = len(values) - finite_count
            distribution.update(
                {
                    "finite_count": finite_count,
                    "non_finite_count": non_finite_count,
                }
            )
            if non_finite_count:
                anomalies.append(
                    {
                        "code": "candidate_non_finite_float_values",
                        "slot_id": slot["slot_id"],
                        "count": non_finite_count,
                        "evidence_classification": "inference",
                    }
                )
        distribution.update(
            {
                "zero_count": zero_count,
                "nonzero_count": len(values) - zero_count,
                "distinct_raw_bit_patterns": len(distinct_raw_bits),
                "constant_raw_bits": constant_raw_bits,
            }
        )
        if slot["candidate_type"] != "float32_le":
            value_counts = Counter(int(value) for value in values)
            distribution["integer_value_distribution"] = [
                {"value": value, "count": value_counts[value]}
                for value in sorted(value_counts)
            ]
        if constant_raw_bits is not None:
            constant_slots.append(str(slot["slot_id"]))
            if zero_count == len(values):
                zero_constant_slots.append(str(slot["slot_id"]))
        slot_distributions.append(distribution)
    return {
        "candidate_assigned_key_records": len(records),
        "slots": slot_distributions,
        "constant_slots": constant_slots,
        "reserved_looking_zero_constant_slot_candidates": zero_constant_slots,
        "distinct_candidate_typed_structural_anomalies": anomalies,
    }


_CANDIDATE_CHANNEL_DYNAMICS_CLASSIFICATIONS = (
    "zero_keys",
    "one_key",
    "multiple_keys_identical_raw_bit_triples",
    "multiple_keys_changing_raw_bit_triples",
)


def _summarize_candidate_channel_dynamics(
    unique_descriptors: dict[tuple[str, int], dict[str, object]],
    selected_descriptor_memberships: int,
) -> dict[str, object]:
    candidate_channels = [
        {
            "candidate_channel_id": f"candidate_channel_{channel_index}",
            "candidate_channel_count_field_index": channel_index,
            "classifications": {
                classification: {"descriptor_count": 0, "key_record_count": 0}
                for classification in _CANDIDATE_CHANNEL_DYNAMICS_CLASSIFICATIONS
            },
        }
        for channel_index in range(len(_ANI_CHANNEL_COUNT_FIELDS))
    ]
    candidate_assigned_key_records = 0
    for descriptor in unique_descriptors.values():
        records = descriptor["_candidate_raw_key_records"]
        candidate_assigned_key_records += len(records)
        for channel_index, field in enumerate(_ANI_CHANNEL_COUNT_FIELDS):
            candidate_channel = descriptor["key_data"]["channels"][field]
            record_range = candidate_channel["record_range"]
            channel_records = [
                record
                for record in records
                if int(record_range["start"])
                <= int(record["record_index"])
                < int(record_range["end_exclusive"])
            ]
            key_count = int(candidate_channel["record_count"])
            if key_count == 0:
                classification = "zero_keys"
            elif key_count == 1:
                classification = "one_key"
            else:
                raw_bit_triples = {
                    tuple(
                        str(record["raw_bits"][slot_index])
                        for slot_index in range(
                            len(_ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOTS)
                        )
                    )
                    for record in channel_records
                }
                classification = (
                    "multiple_keys_identical_raw_bit_triples"
                    if len(raw_bit_triples) == 1
                    else "multiple_keys_changing_raw_bit_triples"
                )
            bucket = candidate_channels[channel_index]["classifications"][
                classification
            ]
            bucket["descriptor_count"] += 1
            bucket["key_record_count"] += key_count
    return {
        "selected_descriptor_memberships": selected_descriptor_memberships,
        "unique_selected_descriptors": len(unique_descriptors),
        "candidate_assigned_key_records": candidate_assigned_key_records,
        "candidate_channels": candidate_channels,
    }


def _strip_candidate_raw_key_records(value: object) -> None:
    if isinstance(value, dict):
        value.pop("_candidate_raw_key_records", None)
        for child in value.values():
            _strip_candidate_raw_key_records(child)
    elif isinstance(value, list):
        for child in value:
            _strip_candidate_raw_key_records(child)


def _direct_children(element: ET.Element, tag: str) -> list[ET.Element]:
    return [child for child in element if child.tag == tag]


def _resolve_connection_hierarchy(
    records: list[dict[str, object]],
    *,
    component: str,
    source_set: object,
    source_file: object,
) -> tuple[list[dict[str, object]], dict[str, list[str]], list[dict[str, object]]]:
    """Resolve explicit connection-parent joins without interpreting their semantics."""

    anomalies: list[dict[str, object]] = []
    records_by_name: dict[str, list[dict[str, object]]] = defaultdict(list)
    source_part_owners: dict[str, list[str]] = defaultdict(list)
    for record in records:
        name = str(record["name"])
        valid_name = bool(name)
        if not valid_name:
            anomalies.append(
                _anomaly(
                    "malformed_connection_identity",
                    "authored component connection has no non-empty exact name",
                    component=component,
                    source_set=source_set,
                    source_file=source_file,
                )
            )
        else:
            records_by_name[name].append(record)
        for part_value in record["direct_owned_parts"]:
            part = str(part_value)
            if not part:
                anomalies.append(
                    _anomaly(
                        "invalid_source_part_ownership",
                        "authored connection-owned part requires an exact non-empty part name",
                        component=component,
                        connection=name,
                        part=part,
                        source_set=source_set,
                        source_file=source_file,
                    )
                )
                continue
            if valid_name:
                source_part_owners[part].append(name)

    for name, definitions in sorted(records_by_name.items()):
        if len(definitions) > 1:
            anomalies.append(
                _anomaly(
                    "duplicate_connection_identity",
                    "component connection identity is authored more than once",
                    component=component,
                    connection=name,
                    definition_count=len(definitions),
                    source_set=source_set,
                    source_file=source_file,
                )
            )
    if anomalies:
        return [], source_part_owners, anomalies

    parent_by_connection: dict[str, str | None] = {}
    parent_part_by_connection: dict[str, str | None] = {}
    for name, definitions in sorted(records_by_name.items()):
        record = definitions[0]
        parent_value = record["parent_part"]
        parent_part = None if parent_value is None or parent_value == "" else str(parent_value)
        parent_part_by_connection[name] = parent_part
        if parent_part is None:
            parent_by_connection[name] = None
            continue
        owners = source_part_owners.get(parent_part, [])
        distinct_owners = sorted(set(owners))
        if not distinct_owners:
            anomalies.append(
                _anomaly(
                    "unresolved_parent_part_reference",
                    "connection parent-part reference has no owning connection",
                    component=component,
                    connection=name,
                    parent_part=parent_part,
                    source_set=source_set,
                    source_file=source_file,
                )
            )
        elif len(distinct_owners) > 1:
            anomalies.append(
                _anomaly(
                    "ambiguous_parent_part_reference",
                    "connection parent-part reference has multiple owning connections",
                    component=component,
                    connection=name,
                    parent_part=parent_part,
                    owning_connections=distinct_owners,
                    source_set=source_set,
                    source_file=source_file,
                )
            )
        elif distinct_owners[0] == name:
            anomalies.append(
                _anomaly(
                    "self_parenting_connection",
                    "connection resolves its parent-part reference to itself",
                    component=component,
                    connection=name,
                    parent_part=parent_part,
                    source_set=source_set,
                    source_file=source_file,
                )
            )
        else:
            parent_by_connection[name] = distinct_owners[0]
    if anomalies:
        return [], source_part_owners, anomalies

    paths: dict[str, list[str]] = {}
    reported_cycles: set[frozenset[str]] = set()
    for start in sorted(records_by_name):
        if start in paths:
            continue
        trail: list[str] = []
        positions: dict[str, int] = {}
        current = start
        while current not in paths:
            if current in positions:
                cycle = trail[positions[current] :]
                identity = frozenset(cycle)
                if identity not in reported_cycles:
                    reported_cycles.add(identity)
                    anomalies.append(
                        _anomaly(
                            "connection_cycle",
                            "connection parent graph contains a cycle",
                            component=component,
                            connections=sorted(cycle),
                            source_set=source_set,
                            source_file=source_file,
                        )
                    )
                break
            positions[current] = len(trail)
            trail.append(current)
            parent = parent_by_connection[current]
            if parent is None:
                root_to_leaf = list(reversed(trail))
                for index, name in enumerate(root_to_leaf):
                    paths[name] = root_to_leaf[: index + 1]
                break
            if parent not in records_by_name:
                anomalies.append(
                    _anomaly(
                        "unresolvable_connection_graph",
                        "resolved parent connection is absent from the component graph",
                        component=component,
                        connection=current,
                        parent_connection=parent,
                        source_set=source_set,
                        source_file=source_file,
                    )
                )
                break
            current = parent
        else:
            path = list(paths[current])
            for name in reversed(trail):
                path = path + [name]
                paths[name] = path

    if anomalies or len(paths) != len(records_by_name):
        if not anomalies:
            anomalies.append(
                _anomaly(
                    "unresolvable_connection_graph",
                    "not every component connection resolves to an authored root",
                    component=component,
                    source_set=source_set,
                    source_file=source_file,
                )
            )
        return [], source_part_owners, anomalies

    connections = []
    for name, definitions in sorted(records_by_name.items()):
        record = definitions[0]
        path = paths[name]
        connections.append(
            {
                "name": name,
                "parent_part": parent_part_by_connection[name],
                "parent_connection": parent_by_connection[name],
                "direct_owned_parts": sorted(str(part) for part in record["direct_owned_parts"]),
                "authored_attributes": {
                    str(key): str(value)
                    for key, value in sorted(record["authored_attributes"].items())
                },
                "authored_tags": record["authored_tags"],
                "tag_tokens": [str(token) for token in record["tag_tokens"]],
                "root_to_connection_path": path,
                "depth": len(path) - 1,
            }
        )
    return connections, source_part_owners, anomalies


_FIRING_ENDPOINT_TAG_BY_COMPONENT_CLASS = {
    "turret": "laser",
    "missileturret": "rocket",
}


def _classify_firing_endpoints(
    connections: list[dict[str, object]],
    *,
    component: str,
    component_class: str,
    macros: list[str],
    macro_classes: list[str],
    source_set: object,
    source_file: object,
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    """Classify only explicit engine-facing endpoint tag evidence."""

    anomalies: list[dict[str, object]] = []
    expected_tag = _FIRING_ENDPOINT_TAG_BY_COMPONENT_CLASS.get(component_class)
    if expected_tag is None:
        anomalies.append(
            _anomaly(
                "unsupported_endpoint_component_class",
                "referenced component class has no source-backed firing-endpoint tag criterion",
                component=component,
                component_class=component_class,
                source_set=source_set,
                source_file=source_file,
            )
        )
        return [], anomalies
    if macro_classes != [component_class]:
        anomalies.append(
            _anomaly(
                "ambiguous_endpoint_class_accounting",
                "component and referring macro classes do not establish one endpoint role",
                component=component,
                component_class=component_class,
                macro_classes=macro_classes,
                macros=macros,
                source_set=source_set,
                source_file=source_file,
            )
        )
        return [], anomalies

    endpoint_tags = set(_FIRING_ENDPOINT_TAG_BY_COMPONENT_CLASS.values())
    endpoints = []
    for connection in connections:
        tokens = [str(token) for token in connection["tag_tokens"]]
        role_tokens = sorted(endpoint_tags.intersection(tokens))
        duplicated_role_tokens = sorted(
            token for token in endpoint_tags if tokens.count(token) > 1
        )
        if duplicated_role_tokens:
            anomalies.append(
                _anomaly(
                    "malformed_endpoint_evidence",
                    "connection repeats an engine-facing firing-endpoint tag token",
                    component=component,
                    connection=connection["name"],
                    component_class=component_class,
                    tag_attribute=connection["authored_tags"],
                    repeated_tag_tokens=duplicated_role_tokens,
                    source_set=source_set,
                    source_file=source_file,
                )
            )
            continue
        if role_tokens and role_tokens != [expected_tag]:
            anomalies.append(
                _anomaly(
                    "ambiguous_endpoint_evidence",
                    "connection firing-endpoint tag evidence conflicts with its component class",
                    component=component,
                    connection=connection["name"],
                    component_class=component_class,
                    expected_tag_token=expected_tag,
                    endpoint_tag_tokens=role_tokens,
                    tag_attribute=connection["authored_tags"],
                    source_set=source_set,
                    source_file=source_file,
                )
            )
            continue
        if role_tokens == [expected_tag]:
            endpoints.append(
                {
                    "component": component,
                    "component_class": component_class,
                    "macros": macros,
                    "macro_classes": macro_classes,
                    "connection": connection["name"],
                    "authored_evidence": {
                        "tag_attribute": connection["authored_tags"],
                        "tag_token": expected_tag,
                    },
                    "root_to_endpoint_connection_path": connection[
                        "root_to_connection_path"
                    ],
                }
            )
    if not endpoints and not anomalies:
        anomalies.append(
            _anomaly(
                "missing_firing_endpoint_identity",
                "component has no connection carrying its source-backed firing-endpoint tag token",
                component=component,
                component_class=component_class,
                expected_tag_token=expected_tag,
                source_set=source_set,
                source_file=source_file,
            )
        )
    return endpoints, anomalies


def _join_authored_animation_selectors(
    animations: list[dict[str, str]],
    ani_descriptors: list[dict[str, object]],
) -> list[dict[str, object]]:
    """Join only exact connection-local animation names and ANI subnames."""

    selectors = []
    for animation in animations:
        connection = animation["connection"]
        name = animation["name"]
        matches = [
            descriptor
            for descriptor in ani_descriptors
            if descriptor["source_connection"] == connection
            and descriptor["subname"] == name
        ]
        selectors.append(
            {
                "connection": connection,
                "name": name,
                "descriptor_match_count": len(matches),
                "connection_ani_descriptors": matches,
            }
        )
    return selectors


def _derive_endpoint_source_paths(
    endpoints: list[dict[str, object]],
    connections: list[dict[str, object]],
    ani_descriptors: list[dict[str, object]],
    authored_animation_selectors: list[dict[str, object]] | None = None,
    *,
    component: str,
    source_set: object,
    source_file: object,
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    """Join exact traversed connection edges, source parts, and ANI identities."""

    anomalies: list[dict[str, object]] = []
    connections_by_name = {
        str(connection["name"]): connection for connection in connections
    }

    for descriptor in ani_descriptors:
        owner_name = str(descriptor["source_connection"])
        part = str(descriptor["part"])
        owner = connections_by_name.get(owner_name)
        if owner is None or part not in [
            str(item) for item in owner["direct_owned_parts"]
        ]:
            anomalies.append(
                _anomaly(
                    "contradictory_descriptor_path_identity",
                    "ANI descriptor source connection does not own its exact source part",
                    component=component,
                    part=part,
                    subname=descriptor["subname"],
                    source_connection=owner_name,
                    source_set=source_set,
                    source_file=source_file,
                )
            )

    selectors = authored_animation_selectors or []
    resolved: list[dict[str, object]] = []
    for endpoint in endpoints:
        endpoint_name = str(endpoint["connection"])
        path = [
            str(connection)
            for connection in endpoint["root_to_endpoint_connection_path"]
        ]
        if not path or path[-1] != endpoint_name or any(
            connection not in connections_by_name for connection in path
        ):
            anomalies.append(
                _anomaly(
                    "unresolvable_endpoint_connection_path",
                    "firing endpoint has no exact resolved root-to-endpoint connection path",
                    component=component,
                    endpoint_connection=endpoint_name,
                    root_to_endpoint_connection_path=path,
                    source_set=source_set,
                    source_file=source_file,
                )
            )
            continue

        edges: list[dict[str, str]] = []
        valid = True
        for parent_name, child_name in zip(path, path[1:]):
            parent = connections_by_name[parent_name]
            child = connections_by_name[child_name]
            child_parent = child["parent_connection"]
            child_parent_part = child["parent_part"]
            owned_parts = [str(part) for part in parent["direct_owned_parts"]]
            if (
                child_parent != parent_name
                or child_parent_part is None
                or str(child_parent_part) not in owned_parts
            ):
                anomalies.append(
                    _anomaly(
                        "invalid_endpoint_edge_ownership",
                        "endpoint path edge is not backed by exact parent-connection part ownership",
                        component=component,
                        endpoint_connection=endpoint_name,
                        parent_connection=parent_name,
                        child_connection=child_name,
                        child_parent_connection=child_parent,
                        child_parent_part=child_parent_part,
                        parent_owned_parts=owned_parts,
                        source_set=source_set,
                        source_file=source_file,
                    )
                )
                valid = False
                break
            edges.append(
                {
                    "parent_connection": parent_name,
                    "child_connection": child_name,
                    "child_parent_part": str(child_parent_part),
                }
            )
        if not valid:
            continue

        memberships: list[dict[str, object]] = []
        for edge_index, edge in enumerate(edges):
            for descriptor in ani_descriptors:
                if not (
                    descriptor["source_connection"] == edge["parent_connection"]
                    and descriptor["part"] == edge["child_parent_part"]
                ):
                    continue
                memberships.append(
                    {
                        "descriptor_index": descriptor["descriptor_index"],
                        "part": descriptor["part"],
                        "subname": descriptor["subname"],
                        "channel_counts": descriptor["channel_counts"],
                        "key_data": descriptor["key_data"],
                        "_candidate_raw_key_records": descriptor[
                            "_candidate_raw_key_records"
                        ],
                        "source_connection": descriptor["source_connection"],
                        "root_to_source_connection_path": descriptor[
                            "root_to_source_connection_path"
                        ],
                        "endpoint_path_edge_index": edge_index,
                    }
                )

        selector_occurrences: list[dict[str, object]] = []
        selected_memberships: list[dict[str, object]] = []
        edge_index_by_parent = {
            edge["parent_connection"]: edge_index
            for edge_index, edge in enumerate(edges)
        }
        path_selectors = sorted(
            (
                selector
                for selector in selectors
                if str(selector["connection"]) in edge_index_by_parent
            ),
            key=lambda selector: (
                edge_index_by_parent[str(selector["connection"])],
                str(selector["name"]),
            ),
        )
        for selector in path_selectors:
            source_connection = str(selector["connection"])
            if int(selector["descriptor_match_count"]) == 0:
                anomalies.append(
                    _anomaly(
                        "unresolved_endpoint_path_animation_selector",
                        "endpoint-path authored animation selector has no exact connection-local ANI descriptor subname match",
                        component=component,
                        endpoint_connection=endpoint_name,
                        source_connection=source_connection,
                        animation_name=selector["name"],
                        source_set=source_set,
                        source_file=source_file,
                    )
                )
                valid = False
                continue

            edge_index = edge_index_by_parent[source_connection]
            path_matches = [
                descriptor
                for descriptor in memberships
                if descriptor["source_connection"] == source_connection
                and descriptor["subname"] == selector["name"]
            ]
            evidence = {
                "connection": source_connection,
                "name": selector["name"],
            }
            selector_occurrences.append(
                {
                    "source_connection": source_connection,
                    "animation_name": selector["name"],
                    "endpoint_path_edge_index": edge_index,
                    "authored_selector_evidence": evidence,
                    "selector_connection_descriptor_match_count": selector[
                        "descriptor_match_count"
                    ],
                    "selector_connection_ani_descriptors": selector[
                        "connection_ani_descriptors"
                    ],
                    "selected_endpoint_path_ani_descriptor_memberships": path_matches,
                }
            )
            selected_memberships.extend(
                {
                    **descriptor,
                    "authored_selector_evidence": evidence,
                    "selector_connection_descriptor_match_count": selector[
                        "descriptor_match_count"
                    ],
                }
                for descriptor in path_matches
            )
        if not valid:
            continue

        selected_identities = {
            (
                descriptor["part"],
                descriptor["subname"],
                descriptor["source_connection"],
                descriptor["endpoint_path_edge_index"],
            )
            for descriptor in selected_memberships
        }
        unselected_memberships = [
            descriptor
            for descriptor in memberships
            if (
                descriptor["part"],
                descriptor["subname"],
                descriptor["source_connection"],
                descriptor["endpoint_path_edge_index"],
            )
            not in selected_identities
        ]
        resolved.append(
            {
                **endpoint,
                "traversed_connection_edges": edges,
                "source_part_path": [edge["child_parent_part"] for edge in edges],
                "ani_descriptor_memberships": memberships,
                "authored_animation_selector_occurrences": selector_occurrences,
                "selected_ani_descriptor_memberships": selected_memberships,
                "unselected_ani_descriptor_memberships": unselected_memberships,
            }
        )

    if anomalies:
        return [], anomalies
    return resolved, []


def build_census(
    source_sets: Mapping[str, Path], resource_sets: Mapping[str, Path]
) -> dict[str, object]:
    """Return a deterministic census or raise CensusError on any unsafe input."""

    roots = _validate_source_sets(source_sets)
    resource_roots = _validate_resource_sets(resource_sets)
    anomalies: list[dict[str, object]] = []
    ani_resources_by_stem: dict[str, list[dict[str, object]]] = defaultdict(list)
    ani_inventory_counts_by_source_set: dict[str, int] = {}
    for source_set in REQUIRED_SOURCE_SETS:
        resource_root = resource_roots[source_set]
        ani_files = _ani_files(resource_root)
        ani_inventory_counts_by_source_set[source_set] = len(ani_files)
        for path in ani_files:
            relative = path.relative_to(resource_root).as_posix()
            ani_resource = (
                relative if source_set == "base" else f"extensions/{source_set}/{relative}"
            )
            ani_resources_by_stem[_normalized_resource_identity(ani_resource[:-4])].append(
                {
                    "ani_source_set": source_set,
                    "ani_resource": ani_resource,
                    "_ani_path": path,
                }
            )
    component_definitions: dict[str, list[dict[str, object]]] = defaultdict(list)
    macro_records: list[dict[str, str]] = []

    for source_set in REQUIRED_SOURCE_SETS:
        root = roots[source_set]
        for path in _xml_files(root):
            relative = path.relative_to(root).as_posix()
            try:
                xml_root = ET.parse(path).getroot()
            except (ET.ParseError, OSError) as exc:
                anomalies.append(
                    _anomaly(
                        "malformed_xml",
                        f"XML source could not be parsed: {exc}",
                        source_set=source_set,
                        source_file=relative,
                    )
                )
                continue

            for component in xml_root.iter("component"):
                name = component.get("name", "").strip()
                if name:
                    component_definitions[name].append(
                        {
                            "component": name,
                            "component_class": component.get("class", "").strip(),
                            "source_set": source_set,
                            "source_file": relative,
                            "geometry_sources": [
                                child.get("geometry", "")
                                for child in _direct_children(component, "source")
                                if "geometry" in child.attrib
                            ],
                            "connection_records": [
                                {
                                    "name": connection.get("name", ""),
                                    "parent_part": connection.get("parent"),
                                    "authored_attributes": dict(connection.attrib),
                                    "authored_tags": connection.get("tags"),
                                    "tag_tokens": (
                                        connection.get("tags", "").split()
                                        if "tags" in connection.attrib
                                        else []
                                    ),
                                    "direct_owned_parts": [
                                        part.get("name", "")
                                        for parts in _direct_children(connection, "parts")
                                        for part in _direct_children(parts, "part")
                                    ],
                                }
                                for connections in _direct_children(component, "connections")
                                for connection in _direct_children(connections, "connection")
                            ],
                            "authored_connection_animations": [
                                {
                                    "connection": connection.get("name", ""),
                                    "name": animation.get("name", ""),
                                }
                                for connections in _direct_children(component, "connections")
                                for connection in _direct_children(connections, "connection")
                                for animations in _direct_children(connection, "animations")
                                for animation in _direct_children(animations, "animation")
                            ],
                        }
                    )

            for macro in xml_root.iter("macro"):
                macro_class = macro.get("class", "")
                if macro_class not in _INCLUDED_CLASSES:
                    continue

                name = macro.get("name", "").strip()
                if not name:
                    anomalies.append(
                        _anomaly(
                            "malformed_macro_record",
                            "included equipment macro has no non-empty name",
                            source_set=source_set,
                            source_file=relative,
                        )
                    )
                    continue

                component_children = _direct_children(macro, "component")
                if len(component_children) != 1:
                    anomalies.append(
                        _anomaly(
                            "missing_component_reference" if not component_children else "malformed_component_reference",
                            "included equipment macro must contain exactly one direct component reference",
                            source_set=source_set,
                            source_file=relative,
                            macro=name,
                        )
                    )
                    continue

                component = component_children[0].get("ref", "").strip()
                if not component:
                    anomalies.append(
                        _anomaly(
                            "missing_component_reference",
                            "included equipment macro has no non-empty component ref",
                            source_set=source_set,
                            source_file=relative,
                            macro=name,
                        )
                    )
                    continue

                macro_records.append(
                    {
                        "name": name,
                        "class": macro_class,
                        "source_set": source_set,
                        "source_file": relative,
                        "component": component,
                    }
                )

    records_by_name: dict[str, list[dict[str, str]]] = defaultdict(list)
    for record in macro_records:
        records_by_name[record["name"]].append(record)

    unique_records: list[dict[str, str]] = []
    for name in sorted(records_by_name):
        records = records_by_name[name]
        if len(records) != 1:
            signatures = sorted({(record["class"], record["component"]) for record in records})
            conflicting = len(signatures) > 1
            anomalies.append(
                _anomaly(
                    "conflicting_duplicate_macro_identity" if conflicting else "duplicate_macro_identity",
                    "equipment macro identity has multiple conflicting definitions"
                    if conflicting
                    else "equipment macro identity is defined more than once",
                    macro=name,
                    definitions=[
                        {
                            "class": record["class"],
                            "component": record["component"],
                            "source_set": record["source_set"],
                            "source_file": record["source_file"],
                        }
                        for record in sorted(
                            records,
                            key=lambda item: (item["source_set"], item["source_file"], item["class"], item["component"]),
                        )
                    ],
                )
            )
            continue
        unique_records.append(records[0])

    referenced_components = sorted({record["component"] for record in unique_records})
    for component in referenced_components:
        definitions = component_definitions.get(component, [])
        if not definitions:
            referring = sorted(record["name"] for record in unique_records if record["component"] == component)
            anomalies.append(
                _anomaly(
                    "unresolved_component_reference",
                    "equipment macro references no component definition in the official source set",
                    component=component,
                    macros=referring,
                )
            )
        elif len(definitions) > 1:
            anomalies.append(
                _anomaly(
                    "multiple_component_definitions",
                    "referenced component identity has multiple full definitions",
                    component=component,
                    definitions=sorted(
                        definitions,
                        key=lambda item: (
                            str(item["source_set"]),
                            str(item["source_file"]),
                            str(item["component_class"]),
                        ),
                    ),
                )
            )
        else:
            definition = definitions[0]
            if not definition["component_class"]:
                anomalies.append(
                    _anomaly(
                        "malformed_component_definition",
                        "referenced component definition has no non-empty class",
                        component=component,
                        source_set=definition["source_set"],
                        source_file=definition["source_file"],
                    )
                )

            connections, source_part_owners, connection_anomalies = (
                _resolve_connection_hierarchy(
                    definition["connection_records"],
                    component=component,
                    source_set=definition["source_set"],
                    source_file=definition["source_file"],
                )
            )
            anomalies.extend(connection_anomalies)
            definition["connections"] = connections
            definition["source_parts"] = [
                {
                    "part": part,
                    "owning_connection_count": len(owners),
                    "distinct_owning_connection_count": len(set(owners)),
                    "owning_connections": sorted(owners),
                }
                for part, owners in sorted(source_part_owners.items())
            ]

            authored_animations = []
            for animation in definition["authored_connection_animations"]:
                connection = str(animation["connection"])
                name = str(animation["name"])
                if not connection or not name:
                    anomalies.append(
                        _anomaly(
                            "invalid_authored_connection_animation",
                            "authored connection animation requires exact non-empty connection and animation names",
                            component=component,
                            connection=connection,
                            animation_name=name,
                            source_set=definition["source_set"],
                            source_file=definition["source_file"],
                        )
                    )
                    continue
                authored_animations.append({"connection": connection, "name": name})
            authored_animation_identity_counts = Counter(
                (animation["connection"], animation["name"])
                for animation in authored_animations
            )
            for (connection, name), count in sorted(
                authored_animation_identity_counts.items()
            ):
                if count > 1:
                    anomalies.append(
                        _anomaly(
                            "duplicate_authored_animation_selector_identity",
                            "connection contains the same exact authored animation selector more than once",
                            component=component,
                            connection=connection,
                            animation_name=name,
                            occurrence_count=count,
                            source_set=definition["source_set"],
                            source_file=definition["source_file"],
                        )
                    )
            definition["authored_connection_animations"] = sorted(
                authored_animations, key=lambda item: (item["connection"], item["name"])
            )
            if connection_anomalies:
                continue

            referring_records = sorted(
                (record for record in unique_records if record["component"] == component),
                key=lambda record: record["name"],
            )
            referring_macros = [record["name"] for record in referring_records]
            referring_macro_classes = sorted(
                {record["class"] for record in referring_records}
            )
            firing_endpoints, endpoint_anomalies = _classify_firing_endpoints(
                connections,
                component=component,
                component_class=str(definition["component_class"]),
                macros=referring_macros,
                macro_classes=referring_macro_classes,
                source_set=definition["source_set"],
                source_file=definition["source_file"],
            )
            definition["firing_endpoints"] = firing_endpoints
            anomalies.extend(endpoint_anomalies)

            geometry_sources = definition["geometry_sources"]
            if not geometry_sources:
                anomalies.append(
                    _anomaly(
                        "missing_geometry_source",
                        "referenced component has no direct source carrying a geometry attribute",
                        component=component,
                        source_set=definition["source_set"],
                        source_file=definition["source_file"],
                    )
                )
            elif len(geometry_sources) > 1:
                anomalies.append(
                    _anomaly(
                        "multiple_geometry_sources",
                        "referenced component has multiple direct geometry-source candidates",
                        component=component,
                        source_set=definition["source_set"],
                        source_file=definition["source_file"],
                        geometry_sources=geometry_sources,
                    )
                )
            elif not str(geometry_sources[0]).strip():
                anomalies.append(
                    _anomaly(
                        "empty_geometry_source",
                        "referenced component direct geometry attribute is empty",
                        component=component,
                        source_set=definition["source_set"],
                        source_file=definition["source_file"],
                    )
                )
            else:
                definition["geometry_source"] = geometry_sources[0]
                matches = ani_resources_by_stem.get(
                    _normalized_resource_identity(str(geometry_sources[0])), []
                )
                if not matches:
                    anomalies.append(
                        _anomaly(
                            "unresolved_ani_resource",
                            "geometry source matches no enumerated official ANI resource stem",
                            component=component,
                            geometry_source=geometry_sources[0],
                            source_set=definition["source_set"],
                            source_file=definition["source_file"],
                        )
                    )
                elif len(matches) > 1:
                    anomalies.append(
                        _anomaly(
                            "multiple_ani_resources",
                            "geometry source matches multiple enumerated official ANI resources",
                            component=component,
                            geometry_source=geometry_sources[0],
                            source_set=definition["source_set"],
                            source_file=definition["source_file"],
                            matches=[
                                {
                                    "ani_source_set": match["ani_source_set"],
                                    "ani_resource": match["ani_resource"],
                                }
                                for match in sorted(
                                    matches,
                                    key=lambda item: (
                                        str(item["ani_source_set"]),
                                        str(item["ani_resource"]),
                                    ),
                                )
                            ],
                        )
                    )
                else:
                    match = matches[0]
                    definition["ani_source_set"] = match["ani_source_set"]
                    definition["ani_resource"] = match["ani_resource"]
                    try:
                        definition["ani_descriptors"] = _parse_ani_descriptors(
                            Path(match["_ani_path"])
                        )
                    except AniDescriptorError as exc:
                        anomalies.append(
                            _anomaly(
                                exc.code,
                                exc.message,
                                component=component,
                                ani_source_set=match["ani_source_set"],
                                ani_resource=match["ani_resource"],
                                source_set=definition["source_set"],
                                source_file=definition["source_file"],
                                **exc.details,
                            )
                        )
                    else:
                        connection_paths = {
                            str(record["name"]): record["root_to_connection_path"]
                            for record in definition["connections"]
                        }
                        joined_descriptors = []
                        absent_parts = set()
                        for descriptor in definition["ani_descriptors"]:
                            part = str(descriptor["part"])
                            owners = source_part_owners.get(part, [])
                            distinct_owners = sorted(set(owners))
                            if not distinct_owners:
                                absent_parts.add(part)
                                anomalies.append(
                                    _anomaly(
                                        "unresolved_descriptor_source_path",
                                        "ANI descriptor part has no owning component connection",
                                        component=component,
                                        part=part,
                                        subname=descriptor["subname"],
                                        source_set=definition["source_set"],
                                        source_file=definition["source_file"],
                                    )
                                )
                                continue
                            if len(distinct_owners) > 1:
                                anomalies.append(
                                    _anomaly(
                                        "ambiguous_descriptor_source_path",
                                        "ANI descriptor part has multiple owning component connections",
                                        component=component,
                                        part=part,
                                        subname=descriptor["subname"],
                                        owning_connections=distinct_owners,
                                        source_set=definition["source_set"],
                                        source_file=definition["source_file"],
                                    )
                                )
                                continue
                            owner = distinct_owners[0]
                            if owner not in connection_paths:
                                anomalies.append(
                                    _anomaly(
                                        "unresolvable_descriptor_source_path",
                                        "ANI descriptor owner has no resolved root connection path",
                                        component=component,
                                        part=part,
                                        subname=descriptor["subname"],
                                        owning_connection=owner,
                                        source_set=definition["source_set"],
                                        source_file=definition["source_file"],
                                    )
                                )
                                continue
                            joined_descriptors.append(
                                {
                                    "descriptor_index": descriptor["descriptor_index"],
                                    "part": part,
                                    "subname": descriptor["subname"],
                                    "channel_counts": descriptor["channel_counts"],
                                    "key_data": descriptor["key_data"],
                                    "_candidate_raw_key_records": descriptor[
                                        "_candidate_raw_key_records"
                                    ],
                                    "source_connection": owner,
                                    "root_to_source_connection_path": connection_paths[owner],
                                }
                            )
                        definition["ani_descriptors"] = joined_descriptors
                        definition["descriptor_parts_absent_from_source_parts"] = sorted(
                            absent_parts
                        )
                        authored_animation_selectors = (
                            _join_authored_animation_selectors(
                                definition["authored_connection_animations"],
                                joined_descriptors,
                            )
                        )
                        definition["authored_connection_animations"] = (
                            authored_animation_selectors
                        )
                        endpoint_paths, endpoint_path_anomalies = (
                            _derive_endpoint_source_paths(
                                definition["firing_endpoints"],
                                definition["connections"],
                                joined_descriptors,
                                authored_animation_selectors,
                                component=component,
                                source_set=definition["source_set"],
                                source_file=definition["source_file"],
                            )
                        )
                        definition["firing_endpoints"] = endpoint_paths
                        anomalies.extend(endpoint_path_anomalies)

    if anomalies:
        raise CensusError(anomalies)

    equipment_macros = sorted(unique_records, key=lambda record: record["name"])
    inverted: dict[str, list[str]] = defaultdict(list)
    for record in equipment_macros:
        inverted[record["component"]].append(record["name"])

    component_to_macros = []
    for component, macros in sorted(inverted.items()):
        definition = component_definitions[component][0]
        component_to_macros.append(
            {
                "component": component,
                "component_class": definition["component_class"],
                "source_set": definition["source_set"],
                "source_file": definition["source_file"],
                "geometry_source": definition["geometry_source"],
                "ani_source_set": definition["ani_source_set"],
                "ani_resource": definition["ani_resource"],
                "connections": definition["connections"],
                "firing_endpoints": definition["firing_endpoints"],
                "ani_descriptors": definition["ani_descriptors"],
                "source_parts": definition["source_parts"],
                "authored_connection_animations": definition[
                    "authored_connection_animations"
                ],
                "descriptor_parts_absent_from_source_parts": definition[
                    "descriptor_parts_absent_from_source_parts"
                ],
                "macro_count": len(macros),
                "macros": sorted(macros),
            }
        )
    cardinalities = Counter(entry["macro_count"] for entry in component_to_macros)
    geometry_inverted: dict[str, list[str]] = defaultdict(list)
    for record in component_to_macros:
        geometry_inverted[str(record["geometry_source"])].append(str(record["component"]))
    geometry_source_to_components = [
        {
            "geometry_source": geometry_source,
            "component_count": len(components),
            "components": sorted(components),
        }
        for geometry_source, components in sorted(geometry_inverted.items())
    ]
    geometry_cardinalities = Counter(
        entry["component_count"] for entry in geometry_source_to_components
    )
    ani_inverted: dict[tuple[str, str], dict[str, set[str]]] = defaultdict(
        lambda: {"geometry_sources": set(), "components": set()}
    )
    for record in component_to_macros:
        key = (str(record["ani_source_set"]), str(record["ani_resource"]))
        ani_inverted[key]["geometry_sources"].add(str(record["geometry_source"]))
        ani_inverted[key]["components"].add(str(record["component"]))
    ani_resource_to_geometry_sources_components = []
    for (ani_source_set, ani_resource), identities in sorted(ani_inverted.items()):
        geometry_sources = sorted(identities["geometry_sources"])
        components = sorted(identities["components"])
        ani_resource_to_geometry_sources_components.append(
            {
                "ani_source_set": ani_source_set,
                "ani_resource": ani_resource,
                "geometry_source_count": len(geometry_sources),
                "geometry_sources": geometry_sources,
                "component_count": len(components),
                "components": components,
            }
        )
    ani_geometry_cardinalities = Counter(
        entry["geometry_source_count"] for entry in ani_resource_to_geometry_sources_components
    )
    ani_component_cardinalities = Counter(
        entry["component_count"] for entry in ani_resource_to_geometry_sources_components
    )
    cross_source_set_ani_bindings = [
        {
            "component": record["component"],
            "component_source_set": record["source_set"],
            "geometry_source": record["geometry_source"],
            "ani_source_set": record["ani_source_set"],
            "ani_resource": record["ani_resource"],
        }
        for record in component_to_macros
        if record["source_set"] != record["ani_source_set"]
    ]
    firing_endpoints = [
        endpoint
        for record in component_to_macros
        for endpoint in record["firing_endpoints"]
    ]
    firing_endpoint_counts = Counter(
        len(record["firing_endpoints"]) for record in component_to_macros
    )
    firing_endpoint_evidence_patterns = Counter(
        (
            str(endpoint["component_class"]),
            str(endpoint["authored_evidence"]["tag_token"]),
            str(endpoint["authored_evidence"]["tag_attribute"]),
        )
        for endpoint in firing_endpoints
    )
    endpoint_path_depths = Counter(
        len(endpoint["source_part_path"]) for endpoint in firing_endpoints
    )
    endpoint_path_descriptor_joins = Counter(
        len(endpoint["ani_descriptor_memberships"]) for endpoint in firing_endpoints
    )
    descriptor_endpoint_path_memberships = sum(
        len(endpoint["ani_descriptor_memberships"])
        for endpoint in firing_endpoints
    )
    all_component_descriptors = {
        (
            str(record["component"]),
            str(descriptor["part"]),
            str(descriptor["subname"]),
        )
        for record in component_to_macros
        for descriptor in record["ani_descriptors"]
    }
    descriptors_on_endpoint_paths = {
        (
            str(endpoint["component"]),
            str(descriptor["part"]),
            str(descriptor["subname"]),
        )
        for endpoint in firing_endpoints
        for descriptor in endpoint["ani_descriptor_memberships"]
    }
    authored_animation_selectors = [
        selector
        for record in component_to_macros
        for selector in record["authored_connection_animations"]
    ]
    authored_animation_selector_cardinalities = Counter(
        int(selector["descriptor_match_count"])
        for selector in authored_animation_selectors
    )
    authored_animation_selectors_with_zero_descriptor_matches = [
        {
            "component": record["component"],
            "connection": selector["connection"],
            "animation_name": selector["name"],
        }
        for record in component_to_macros
        for selector in record["authored_connection_animations"]
        if int(selector["descriptor_match_count"]) == 0
    ]
    authored_animation_selected_descriptor_identities = {
        (
            str(record["component"]),
            str(descriptor["part"]),
            str(descriptor["subname"]),
        )
        for record in component_to_macros
        for selector in record["authored_connection_animations"]
        for descriptor in selector["connection_ani_descriptors"]
    }
    endpoint_path_selector_occurrences = [
        (endpoint, selector)
        for endpoint in firing_endpoints
        for selector in endpoint["authored_animation_selector_occurrences"]
    ]
    endpoint_path_selector_cardinalities = Counter(
        int(selector["selector_connection_descriptor_match_count"])
        for _, selector in endpoint_path_selector_occurrences
    )
    selected_endpoint_path_descriptor_memberships = [
        (endpoint, descriptor)
        for endpoint in firing_endpoints
        for descriptor in endpoint["selected_ani_descriptor_memberships"]
    ]
    selected_endpoint_path_descriptor_identities = {
        (
            str(endpoint["component"]),
            str(descriptor["part"]),
            str(descriptor["subname"]),
        )
        for endpoint, descriptor in selected_endpoint_path_descriptor_memberships
    }
    selected_descriptor_counts_by_endpoint = Counter(
        len(endpoint["selected_ani_descriptor_memberships"])
        for endpoint in firing_endpoints
    )
    selected_channel_count_families_by_class = {
        component_class: Counter(
            tuple(int(descriptor["channel_counts"][field]) for field in _ANI_CHANNEL_COUNT_FIELDS)
            for endpoint, descriptor in selected_endpoint_path_descriptor_memberships
            if endpoint["component_class"] == component_class
        )
        for component_class in sorted(_INCLUDED_CLASSES)
    }
    selected_key_data_accounting_by_class = {}
    selected_candidate_slot_distributions_by_class = {}
    selected_candidate_channel_dynamics_by_class = {}
    for component_class in sorted(_INCLUDED_CLASSES):
        memberships = [
            descriptor
            for endpoint, descriptor in selected_endpoint_path_descriptor_memberships
            if endpoint["component_class"] == component_class
        ]
        key_records = sum(
            int(descriptor["key_data"]["record_range"]["end_exclusive"])
            - int(descriptor["key_data"]["record_range"]["start"])
            for descriptor in memberships
        )
        selected_key_data_accounting_by_class[component_class] = {
            "selected_descriptor_memberships": len(memberships),
            "opaque_key_records": key_records,
            "opaque_key_bytes": key_records * _ANI_KEY_RECORD_SIZE,
        }
        unique_descriptors: dict[tuple[str, int], dict[str, object]] = {}
        for endpoint, descriptor in selected_endpoint_path_descriptor_memberships:
            if endpoint["component_class"] != component_class:
                continue
            identity = (
                str(endpoint["component"]), int(descriptor["descriptor_index"])
            )
            unique_descriptors.setdefault(identity, descriptor)
        raw_records = [
            raw_record
            for descriptor in unique_descriptors.values()
            for raw_record in descriptor["_candidate_raw_key_records"]
        ]
        selected_candidate_slot_distributions_by_class[component_class] = {
            "selected_descriptor_memberships": len(memberships),
            "unique_selected_descriptors": len(unique_descriptors),
            **_summarize_candidate_raw_key_records(raw_records),
        }
        selected_candidate_channel_dynamics_by_class[component_class] = (
            _summarize_candidate_channel_dynamics(
                unique_descriptors, len(memberships)
            )
        )

    # Raw per-record values are needed only to produce the aggregate inventory;
    # keep the public census structural and bounded.
    _strip_candidate_raw_key_records(component_to_macros)

    def render_channel_count_families(
        families: Counter[tuple[int, ...]],
    ) -> list[dict[str, object]]:
        return [
            {
                "channel_counts": dict(zip(_ANI_CHANNEL_COUNT_FIELDS, family)),
                "selected_descriptor_memberships": families[family],
            }
            for family in sorted(families)
        ]
    connection_depths = Counter(
        int(connection["depth"])
        for record in component_to_macros
        for connection in record["connections"]
    )
    root_counts = Counter(
        sum(connection["parent_connection"] is None for connection in record["connections"])
        for record in component_to_macros
    )
    descriptor_source_path_joins = sum(
        len(record["ani_descriptors"]) for record in component_to_macros
    )
    descriptor_pairs = [
        (str(descriptor["part"]), str(descriptor["subname"]))
        for record in component_to_macros
        for descriptor in record["ani_descriptors"]
    ]
    descriptor_count_cardinalities = Counter(
        len(record["ani_descriptors"]) for record in component_to_macros
    )
    source_part_owning_connection_cardinalities = Counter(
        int(source_part["owning_connection_count"])
        for record in component_to_macros
        for source_part in record["source_parts"]
    )
    source_part_distinct_owning_connection_cardinalities = Counter(
        int(source_part["distinct_owning_connection_count"])
        for record in component_to_macros
        for source_part in record["source_parts"]
    )
    descriptor_parts_absent_from_component_source_parts = [
        {"component": record["component"], "part": part}
        for record in component_to_macros
        for part in record["descriptor_parts_absent_from_source_parts"]
    ]
    macro_component_class_mismatches = []
    for record in equipment_macros:
        definition = component_definitions[record["component"]][0]
        if record["class"] != definition["component_class"]:
            macro_component_class_mismatches.append(
                {
                    "macro": record["name"],
                    "macro_class": record["class"],
                    "macro_source_set": record["source_set"],
                    "macro_source_file": record["source_file"],
                    "component": record["component"],
                    "component_class": definition["component_class"],
                    "component_source_set": definition["source_set"],
                    "component_source_file": definition["source_file"],
                }
            )
    counts_by_source_set = {}
    for source_set in REQUIRED_SOURCE_SETS:
        records = [record for record in equipment_macros if record["source_set"] == source_set]
        counts_by_source_set[source_set] = {
            "equipment_macros": len(records),
            "turret_macros": sum(record["class"] == "turret" for record in records),
            "missileturret_macros": sum(record["class"] == "missileturret" for record in records),
        }

    return {
        "schema_version": 13,
        "x4_version": "9.00",
        "official_source_sets": list(REQUIRED_SOURCE_SETS),
        "official_resource_sets": list(REQUIRED_SOURCE_SETS),
        "counts": {
            "equipment_macros": len(equipment_macros),
            "turret_macros": sum(record["class"] == "turret" for record in equipment_macros),
            "missileturret_macros": sum(record["class"] == "missileturret" for record in equipment_macros),
            "unique_components": len(component_to_macros),
            "unique_geometry_sources": len(geometry_source_to_components),
            "unique_ani_resources": len(ani_resource_to_geometry_sources_components),
            "cross_source_set_ani_bindings": len(cross_source_set_ani_bindings),
            "ani_descriptor_pairs_total": len(descriptor_pairs),
            "unique_ani_descriptor_pairs": len(set(descriptor_pairs)),
            "source_part_ownerships": sum(
                int(source_part["owning_connection_count"])
                for record in component_to_macros
                for source_part in record["source_parts"]
            ),
            "component_source_parts": sum(
                len(record["source_parts"]) for record in component_to_macros
            ),
            "unique_source_part_names": len(
                {
                    str(source_part["part"])
                    for record in component_to_macros
                    for source_part in record["source_parts"]
                }
            ),
            "authored_connection_animations": len(authored_animation_selectors),
            "authored_animation_selected_descriptor_identities": len(
                authored_animation_selected_descriptor_identities
            ),
            "endpoint_path_animation_selector_occurrences": len(
                endpoint_path_selector_occurrences
            ),
            "conventional_endpoint_path_animation_selector_occurrences": sum(
                endpoint["component_class"] == "turret"
                for endpoint, _ in endpoint_path_selector_occurrences
            ),
            "missileturret_endpoint_path_animation_selector_occurrences": sum(
                endpoint["component_class"] == "missileturret"
                for endpoint, _ in endpoint_path_selector_occurrences
            ),
            "selected_endpoint_path_descriptor_identities": len(
                selected_endpoint_path_descriptor_identities
            ),
            "selected_endpoint_path_descriptor_memberships": len(
                selected_endpoint_path_descriptor_memberships
            ),
            "conventional_selected_endpoint_path_descriptor_memberships": sum(
                endpoint["component_class"] == "turret"
                for endpoint, _ in selected_endpoint_path_descriptor_memberships
            ),
            "missileturret_selected_endpoint_path_descriptor_memberships": sum(
                endpoint["component_class"] == "missileturret"
                for endpoint, _ in selected_endpoint_path_descriptor_memberships
            ),
            "path_local_descriptors_left_unselected": sum(
                len(endpoint["unselected_ani_descriptor_memberships"])
                for endpoint in firing_endpoints
            ),
            "conventional_path_local_descriptors_left_unselected": sum(
                len(endpoint["unselected_ani_descriptor_memberships"])
                for endpoint in firing_endpoints
                if endpoint["component_class"] == "turret"
            ),
            "missileturret_path_local_descriptors_left_unselected": sum(
                len(endpoint["unselected_ani_descriptor_memberships"])
                for endpoint in firing_endpoints
                if endpoint["component_class"] == "missileturret"
            ),
            "unresolved_endpoint_path_animation_selectors": 0,
            "connection_identities": sum(
                len(record["connections"]) for record in component_to_macros
            ),
            "firing_endpoint_identities": len(firing_endpoints),
            "conventional_firing_endpoints": sum(
                endpoint["component_class"] == "turret"
                for endpoint in firing_endpoints
            ),
            "missileturret_firing_endpoints": sum(
                endpoint["component_class"] == "missileturret"
                for endpoint in firing_endpoints
            ),
            "components_with_zero_or_ambiguous_endpoint_identity": 0,
            "traversed_endpoint_part_occurrences": sum(
                len(endpoint["source_part_path"]) for endpoint in firing_endpoints
            ),
            "descriptor_endpoint_path_memberships": descriptor_endpoint_path_memberships,
            "descriptors_on_at_least_one_endpoint_path": len(
                descriptors_on_endpoint_paths
            ),
            "descriptors_only_off_endpoint_paths": len(
                all_component_descriptors - descriptors_on_endpoint_paths
            ),
            "unresolved_or_ambiguous_endpoint_path_identities": 0,
            "descriptor_source_path_joins": descriptor_source_path_joins,
            "unresolved_or_ambiguous_parent_identities": 0,
            "unresolved_or_ambiguous_descriptor_path_identities": 0,
            "descriptor_parts_absent_from_component_source_parts": len(
                descriptor_parts_absent_from_component_source_parts
            ),
        },
        "counts_by_source_set": counts_by_source_set,
        "ani_inventory_counts_by_source_set": ani_inventory_counts_by_source_set,
        "equipment_macros": equipment_macros,
        "component_to_macros": component_to_macros,
        "component_macro_cardinality": {str(key): cardinalities[key] for key in sorted(cardinalities)},
        "ani_descriptor_count_cardinality": {
            str(key): descriptor_count_cardinalities[key]
            for key in sorted(descriptor_count_cardinalities)
        },
        "authored_animation_selector_identity_rule": {
            "evidence_classification": "shipped-source",
            "structural_rule": "same exact source connection and case-sensitive direct animation name equals ANI descriptor subname",
            "shipped_source_corpus_evidence": {
                "authored_connection_animation_records": len(
                    authored_animation_selectors
                ),
                "records_with_exact_descriptor_matches": sum(
                    int(selector["descriptor_match_count"]) > 0
                    for selector in authored_animation_selectors
                ),
            },
            "corroboration": {
                "evidence_classification": "third-party-technique",
                "source": "X4Converter 0be4b494089ba7719d4c5d351e63160ef3843ef5 X4ConverterTools/src/ani/AnimFile.cpp",
                "finding": "converter copies a direct connection animation name into ANI subname metadata",
            },
        },
        "authored_animation_selector_descriptor_cardinality": {
            str(key): authored_animation_selector_cardinalities[key]
            for key in sorted(authored_animation_selector_cardinalities)
        },
        "authored_animation_selectors_with_zero_descriptor_matches": (
            authored_animation_selectors_with_zero_descriptor_matches
        ),
        "endpoint_path_selector_connection_descriptor_cardinality": {
            str(key): endpoint_path_selector_cardinalities[key]
            for key in sorted(endpoint_path_selector_cardinalities)
        },
        "endpoint_selected_descriptor_count_distribution": {
            str(key): selected_descriptor_counts_by_endpoint[key]
            for key in sorted(selected_descriptor_counts_by_endpoint)
        },
        "ani_key_data_framing": {
            "structural_framing": {
                "evidence_classification": "shipped-source",
                "x4_version": "9.00",
                "record_size_bytes": _ANI_KEY_RECORD_SIZE,
                "key_section_termination": "exactly at end of file",
                "invariant": (
                    "descriptor-table end offset"
                    " + sum(all descriptor channel counts) * record_size_bytes"
                    " == file size"
                ),
                "linked_ani_resources": len(
                    ani_resource_to_geometry_sources_components
                ),
                "resources_with_exact_framing": len(
                    ani_resource_to_geometry_sources_components
                ),
                "exceptions": [],
                # The invariant is a sum over all channel counts, so it is
                # blind to how those records are ordered on disk. It cannot
                # corroborate descriptor or channel byte order.
                "does_not_discriminate": ["descriptor_order", "channel_order"],
            },
            "key_ownership_order": {
                "evidence_classification": "third-party-technique",
                "descriptor_order": "descriptor table index order",
                "channel_order": list(_ANI_CHANNEL_COUNT_FIELDS),
                "note": (
                    "byte order of descriptor and channel key records is not"
                    " discriminated by the shipped-source structural invariant;"
                    " the parser assigns key-record ranges in this order per the"
                    " third-party lead only"
                ),
                "third_party_lead": {
                    "source": "X4Converter 0be4b494089ba7719d4c5d351e63160ef3843ef5 X4ConverterTools/src/ani/AnimFile.cpp, AnimDesc.cpp, and Keyframe.h",
                },
            },
        },
        "ani_key_record_field_inventory": {
            "candidate_slot_layout": {
                "evidence_classification": "third-party-technique",
                "source": (
                    "X4Converter 0be4b494089ba7719d4c5d351e63160ef3843ef5"
                    " X4ConverterTools/include/X4ConverterTools/ani/Keyframe.h"
                    " and X4ConverterTools/src/ani/Keyframe.cpp"
                ),
                "record_size_bytes": _ANI_KEY_RECORD_SIZE,
                "covered_byte_range": {"start": 0, "end_exclusive": 128},
                "unaccounted_bytes": list(
                    _ANI_KEY_RECORD_CANDIDATE_UNACCOUNTED_BYTES
                ),
                "overlapping_bytes": list(
                    _ANI_KEY_RECORD_CANDIDATE_OVERLAPPING_BYTES
                ),
                "slots": list(_ANI_KEY_RECORD_CANDIDATE_SLOTS),
                "semantic_claim": "none",
            },
            "candidate_assigned_shipped_value_distributions": {
                "evidence_classification": "inference",
                "shipped_source_basis": {
                    "evidence_classification": "shipped-source",
                    "finding": "raw 128-byte records and their bit patterns",
                },
                "candidate_decode_basis": {
                    "evidence_classification": "third-party-technique",
                    "finding": (
                        "record assignment, slot order, and candidate scalar types"
                    ),
                },
                "semantic_claim": "none",
                "conventional": selected_candidate_slot_distributions_by_class[
                    "turret"
                ],
                "missileturret": selected_candidate_slot_distributions_by_class[
                    "missileturret"
                ],
            },
            "reserved_looking_classification": {
                "evidence_classification": "inference",
                "criterion": (
                    "slot is raw-bit constant and its raw numeric values all"
                    " compare equal to zero"
                ),
                "semantic_claim": "none",
            },
        },
        "selected_descriptor_candidate_channel_dynamics": {
            "evidence_classification": "inference",
            "candidate_channel_ownership_order": {
                "evidence_classification": "third-party-technique",
                "source": (
                    "X4Converter 0be4b494089ba7719d4c5d351e63160ef3843ef5"
                    " X4ConverterTools/src/ani/AnimFile.cpp, AnimDesc.cpp,"
                    " and Keyframe.h"
                ),
                "candidate_channel_count_field_indexes": list(
                    range(len(_ANI_CHANNEL_COUNT_FIELDS))
                ),
            },
            "candidate_raw_bit_triple": {
                "evidence_classification": "third-party-technique",
                "source": (
                    "X4Converter 0be4b494089ba7719d4c5d351e63160ef3843ef5"
                    " X4ConverterTools/include/X4ConverterTools/ani/Keyframe.h"
                    " and X4ConverterTools/src/ani/Keyframe.cpp"
                ),
                "slot_ids": [
                    str(slot["slot_id"])
                    for slot in _ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOTS
                ],
                "equality_rule": "exact ordered raw-bit triple equality",
            },
            "semantic_claim": "none",
            "conventional": selected_candidate_channel_dynamics_by_class[
                "turret"
            ],
            "missileturret": selected_candidate_channel_dynamics_by_class[
                "missileturret"
            ],
        },
        "selected_endpoint_path_descriptor_channel_count_families": {
            "conventional": render_channel_count_families(
                selected_channel_count_families_by_class["turret"]
            ),
            "missileturret": render_channel_count_families(
                selected_channel_count_families_by_class["missileturret"]
            ),
        },
        "selected_endpoint_path_descriptor_key_data_accounting": {
            "conventional": selected_key_data_accounting_by_class["turret"],
            "missileturret": selected_key_data_accounting_by_class[
                "missileturret"
            ],
        },
        "endpoint_paths_by_selected_descriptor_cardinality": {
            "zero": selected_descriptor_counts_by_endpoint[0],
            "one": selected_descriptor_counts_by_endpoint[1],
            "multiple": sum(
                count
                for selected, count in selected_descriptor_counts_by_endpoint.items()
                if selected > 1
            ),
        },
        "endpoint_paths_by_selected_descriptor_cardinality_by_component_class": {
            component_class: {
                "zero": sum(
                    not endpoint["selected_ani_descriptor_memberships"]
                    for endpoint in firing_endpoints
                    if endpoint["component_class"] == component_class
                ),
                "one": sum(
                    len(endpoint["selected_ani_descriptor_memberships"]) == 1
                    for endpoint in firing_endpoints
                    if endpoint["component_class"] == component_class
                ),
                "multiple": sum(
                    len(endpoint["selected_ani_descriptor_memberships"]) > 1
                    for endpoint in firing_endpoints
                    if endpoint["component_class"] == component_class
                ),
            }
            for component_class in sorted(
                _FIRING_ENDPOINT_TAG_BY_COMPONENT_CLASS
            )
        },
        "unresolved_endpoint_path_animation_selectors": [],
        "firing_endpoint_criterion": {
            "evidence_classification": "shipped-source",
            "structural_rule": "exact direct connection tag token selected by exact component class",
            "component_class_to_tag_token": {
                key: _FIRING_ENDPOINT_TAG_BY_COMPONENT_CLASS[key]
                for key in sorted(_FIRING_ENDPOINT_TAG_BY_COMPONENT_CLASS)
            },
        },
        "firing_endpoints": firing_endpoints,
        "firing_endpoint_count_distribution": {
            str(key): firing_endpoint_counts[key]
            for key in sorted(firing_endpoint_counts)
        },
        "firing_endpoint_evidence_patterns": [
            {
                "component_class": component_class,
                "tag_token": tag_token,
                "exact_tag_attribute": tag_attribute,
                "endpoint_count": count,
            }
            for (component_class, tag_token, tag_attribute), count in sorted(
                firing_endpoint_evidence_patterns.items()
            )
        ],
        "endpoint_path_depth_distribution": {
            str(key): endpoint_path_depths[key] for key in sorted(endpoint_path_depths)
        },
        "endpoint_path_descriptor_join_distribution": {
            str(key): endpoint_path_descriptor_joins[key]
            for key in sorted(endpoint_path_descriptor_joins)
        },
        "endpoint_paths_by_descriptor_join_cardinality": {
            "zero": endpoint_path_descriptor_joins[0],
            "one": endpoint_path_descriptor_joins[1],
            "multiple": sum(
                count
                for joins, count in endpoint_path_descriptor_joins.items()
                if joins > 1
            ),
        },
        "unresolved_or_ambiguous_endpoint_path_identities": [],
        "components_with_zero_or_ambiguous_endpoint_identity": [],
        "component_root_count_distribution": {
            str(key): root_counts[key] for key in sorted(root_counts)
        },
        "connection_depth_distribution": {
            str(key): connection_depths[key] for key in sorted(connection_depths)
        },
        "unresolved_or_ambiguous_parent_identities": [],
        "unresolved_or_ambiguous_descriptor_path_identities": [],
        "source_part_owning_connection_cardinality": {
            str(key): source_part_owning_connection_cardinalities[key]
            for key in sorted(source_part_owning_connection_cardinalities)
        },
        "source_part_distinct_owning_connection_cardinality": {
            str(key): source_part_distinct_owning_connection_cardinalities[key]
            for key in sorted(source_part_distinct_owning_connection_cardinalities)
        },
        "descriptor_parts_absent_from_component_source_parts": (
            descriptor_parts_absent_from_component_source_parts
        ),
        "geometry_source_to_components": geometry_source_to_components,
        "geometry_source_component_cardinality": {
            str(key): geometry_cardinalities[key] for key in sorted(geometry_cardinalities)
        },
        "ani_resource_to_geometry_sources_components": ani_resource_to_geometry_sources_components,
        "ani_resource_geometry_source_cardinality": {
            str(key): ani_geometry_cardinalities[key] for key in sorted(ani_geometry_cardinalities)
        },
        "ani_resource_component_cardinality": {
            str(key): ani_component_cardinalities[key] for key in sorted(ani_component_cardinalities)
        },
        "cross_source_set_ani_bindings": cross_source_set_ani_bindings,
        "macro_component_class_mismatches": macro_component_class_mismatches,
        "anomalies": [],
    }


def _parse_historical_components(root: Path, cache_name: str) -> dict[str, list[dict[str, str]]]:
    if not root.is_dir():
        raise CensusError(
            [_anomaly("missing_historical_cache", "required historical cache is unavailable", cache=cache_name)]
        )
    files = _xml_files(root)
    if not files:
        raise CensusError(
            [_anomaly("empty_historical_cache", "historical cache contains no XML source", cache=cache_name)]
        )

    definitions: dict[str, list[dict[str, str]]] = defaultdict(list)
    anomalies: list[dict[str, object]] = []
    for path in files:
        relative = path.relative_to(root).as_posix()
        try:
            xml_root = ET.parse(path).getroot()
        except (ET.ParseError, OSError) as exc:
            anomalies.append(
                _anomaly(
                    "malformed_historical_xml",
                    f"historical XML source could not be parsed: {exc}",
                    cache=cache_name,
                    source_file=relative,
                )
            )
            continue
        for component in xml_root.iter("component"):
            name = component.get("name", "").strip()
            if not name:
                continue
            definitions[name].append(
                {
                    "component_class": component.get("class", "").strip(),
                    "source_file": relative,
                }
            )
    if anomalies:
        raise CensusError(anomalies)
    if not definitions:
        raise CensusError(
            [
                _anomaly(
                    "no_historical_component_definitions",
                    "historical cache XML contains no full component definitions",
                    cache=cache_name,
                )
            ]
        )
    return definitions


def _group_current_components(
    components: set[str],
    component_records: Mapping[str, dict[str, object]],
    macro_classes: Mapping[str, str],
) -> dict[str, dict[str, list[str]]]:
    by_source_set: dict[str, set[str]] = defaultdict(set)
    by_macro_class: dict[str, set[str]] = defaultdict(set)
    by_component_class: dict[str, set[str]] = defaultdict(set)
    for component in sorted(components):
        record = component_records[component]
        by_source_set[str(record["source_set"])].add(component)
        by_component_class[str(record["component_class"])].add(component)
        for macro in record["macros"]:
            by_macro_class[macro_classes[str(macro)]].add(component)
    return {
        "by_current_source_set": {key: sorted(values) for key, values in sorted(by_source_set.items())},
        "by_macro_class": {key: sorted(values) for key, values in sorted(by_macro_class.items())},
        "by_component_class": {key: sorted(values) for key, values in sorted(by_component_class.items())},
    }


def _group_historical_components(
    components: set[str], definitions: Mapping[str, list[dict[str, str]]]
) -> dict[str, object]:
    by_class: dict[str, set[str]] = defaultdict(set)
    unknown: list[str] = []
    for component in sorted(components):
        classes = {definition["component_class"] for definition in definitions.get(component, [])}
        classes.discard("")
        if not classes:
            unknown.append(component)
        for component_class in classes:
            by_class[component_class].add(component)
    return {
        "by_component_class": {key: sorted(values) for key, values in sorted(by_class.items())},
        "component_class_unavailable": unknown,
    }


def _comparison(components: set[str], groups: dict[str, object]) -> dict[str, object]:
    return {"count": len(components), "components": sorted(components), "groups": groups}


def _current_historical_comparison(
    components: set[str],
    component_records: Mapping[str, dict[str, object]],
    macro_classes: Mapping[str, str],
    historical_definitions: Mapping[str, list[dict[str, str]]],
) -> dict[str, object]:
    comparison = _comparison(
        components, _group_current_components(components, component_records, macro_classes)
    )
    comparison["historical_groups"] = _group_historical_components(components, historical_definitions)
    comparison["component_class_mismatches"] = [
        {
            "component": component,
            "current_component_class": component_records[component]["component_class"],
            "historical_component_classes": sorted(
                {
                    definition["component_class"]
                    for definition in historical_definitions.get(component, [])
                    if definition["component_class"]
                }
            ),
        }
        for component in sorted(components)
        if {str(component_records[component]["component_class"])}
        != {
            definition["component_class"]
            for definition in historical_definitions.get(component, [])
            if definition["component_class"]
        }
    ]
    return comparison


def build_reconciliation(
    census: Mapping[str, object], old79_root: Path, platform_sweep_root: Path
) -> dict[str, object]:
    """Reconcile current macro-referenced components with preserved historical caches."""

    old79_root = Path(old79_root)
    platform_sweep_root = Path(platform_sweep_root)
    if old79_root.resolve() == platform_sweep_root.resolve():
        raise CensusError(
            [
                _anomaly(
                    "historical_cache_paths_not_distinct",
                    "old79 and platform-sweep caches must be separate directories",
                )
            ]
        )
    old_definitions = _parse_historical_components(old79_root, "old79")
    platform_definitions = _parse_historical_components(platform_sweep_root, "platform_sweep")
    component_records = {
        str(record["component"]): record for record in census["component_to_macros"]  # type: ignore[index]
    }
    macro_classes = {
        str(record["name"]): str(record["class"]) for record in census["equipment_macros"]  # type: ignore[index]
    }

    current = set(component_records)
    old79 = set(old_definitions)
    platform = set(platform_definitions)
    historical_union = old79 | platform

    current_intersection_old = current & old79
    current_only_old = current - old79
    old_only = old79 - current
    current_intersection_platform = current & platform
    current_only_union = current - historical_union
    historical_union_only = historical_union - current
    current_intersection_union = current & historical_union

    partition_valid = (
        not (current_intersection_old & current_only_old)
        and (current_intersection_old | current_only_old) == current
        and not (current_intersection_old & old_only)
        and (current_intersection_old | old_only) == old79
    )
    if not partition_valid:
        raise CensusError(
            [_anomaly("reconciliation_partition_error", "old79/current set partition invariant failed")]
        )

    merged_historical: dict[str, list[dict[str, str]]] = defaultdict(list)
    for definitions in (old_definitions, platform_definitions):
        for component, records in definitions.items():
            merged_historical[component].extend(records)

    current_only_provenance = all(
        component_records[component].get("component_class")
        and component_records[component].get("source_set")
        and component_records[component].get("source_file")
        and component_records[component].get("macros")
        for component in current_only_old
    )
    recovered_by_platform = current_only_old & platform
    union_partition_valid = (
        not (recovered_by_platform & current_only_union)
        and (recovered_by_platform | current_only_union) == current_only_old
        and not (current_intersection_union & current_only_union)
        and (current_intersection_union | current_only_union) == current
        and not (current_intersection_union & historical_union_only)
        and (current_intersection_union | historical_union_only) == historical_union
    )
    if not union_partition_valid:
        raise CensusError(
            [_anomaly("reconciliation_partition_error", "historical-union set partition invariant failed")]
        )
    intersection_source_counts = Counter(
        str(component_records[component]["source_set"]) for component in current_intersection_old
    )
    current_only_source_counts = Counter(
        str(component_records[component]["source_set"]) for component in current_only_old
    )
    old_only_details = []
    for component in sorted(old_only):
        classes = sorted(
            {
                definition["component_class"]
                for definition in old_definitions[component]
                if definition["component_class"]
            }
        )
        old_only_details.append({"component": component, "component_classes": classes})
    intersection_summary = ", ".join(
        f"{source_set}={count}" for source_set, count in sorted(intersection_source_counts.items())
    ) or "none"
    current_only_summary = ", ".join(
        f"{source_set}={count}" for source_set, count in sorted(current_only_source_counts.items())
    ) or "none"
    old_only_summary = ", ".join(
        f"{item['component']} ({'/'.join(item['component_classes']) or 'class unavailable'})"
        for item in old_only_details
    ) or "none"
    reason = (
        f"The current macro-driven census contains {len(current)} exact referenced component identities. "
        f"The old79 cache contains {len(old79)} XML-declared identities: {len(current_intersection_old)} "
        f"intersect current (current definition source sets: {intersection_summary}) and {len(old_only)} are "
        f"old79-only ({old_only_summary}). The numerical difference is exactly {len(current_only_old)} "
        f"current-only minus {len(old_only)} old79-only = {len(current) - len(old79)}; current-only "
        f"definition source sets are {current_only_summary}. The platform sweep contains "
        f"{len(recovered_by_platform)} of the current-only identities; {len(current_only_union)} current "
        f"identities are absent from both historical caches. Every current-only identity has an explicit "
        f"current equipment-macro reference and one exact full component definition with class, source set, "
        f"and source file."
    )

    historical_records = {}
    for name, definitions in (("old79", old_definitions), ("platform_sweep", platform_definitions)):
        historical_records[name] = {
            "component_count": len(definitions),
            "components": [
                {
                    "component": component,
                    "component_classes": sorted(
                        {record["component_class"] for record in records if record["component_class"]}
                    ),
                    "source_files": sorted({record["source_file"] for record in records}),
                }
                for component, records in sorted(definitions.items())
            ],
        }

    return {
        "schema_version": 1,
        "x4_version": census["x4_version"],
        "current_component_count": len(current),
        "historical_sources": historical_records,
        "comparisons": {
            "current_intersection_old79": _current_historical_comparison(
                current_intersection_old, component_records, macro_classes, old_definitions
            ),
            "current_only_vs_old79": _comparison(
                current_only_old, _group_current_components(current_only_old, component_records, macro_classes)
            ),
            "old79_only": _comparison(old_only, _group_historical_components(old_only, old_definitions)),
            "current_intersection_platform_sweep": _current_historical_comparison(
                current_intersection_platform, component_records, macro_classes, platform_definitions
            ),
            "current_only_vs_historical_union": _comparison(
                current_only_union,
                _group_current_components(current_only_union, component_records, macro_classes),
            ),
            "historical_union_only": _comparison(
                historical_union_only,
                _group_historical_components(historical_union_only, merged_historical),
            ),
        },
        "resolution": {
            "current_minus_old79_count": len(current) - len(old79),
            "current_only_vs_old79_count": len(current_only_old),
            "old79_only_count": len(old_only),
            "old79_is_subset_of_current": not old_only,
            "current_intersection_old79_by_current_source_set": {
                key: intersection_source_counts[key] for key in sorted(intersection_source_counts)
            },
            "current_only_vs_old79_by_current_source_set": {
                key: current_only_source_counts[key] for key in sorted(current_only_source_counts)
            },
            "old79_only_details": old_only_details,
            "current_only_found_in_platform_sweep_count": len(recovered_by_platform),
            "current_only_absent_from_historical_union_count": len(current_only_union),
            "all_current_only_have_exact_provenance": bool(current_only_provenance),
            "reason": reason,
        },
        "anomalies": [],
    }


def render_json(report: object) -> str:
    return json.dumps(report, indent=2, sort_keys=True, ensure_ascii=True) + "\n"


def _parse_source_set(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected NAME=PATH")
    name, raw_path = value.split("=", 1)
    if not name or not raw_path:
        raise argparse.ArgumentTypeError("expected non-empty NAME=PATH")
    return name, Path(raw_path)


def _arguments(argv: Sequence[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Census official X4 9.00 turret/missile-turret macros and referenced components."
    )
    parser.add_argument(
        "--source-set",
        action="append",
        default=[],
        metavar="NAME=PATH",
        type=_parse_source_set,
        help="repeat exactly once for base and each required official extension XML root",
    )
    parser.add_argument(
        "--resource-set",
        action="append",
        default=[],
        metavar="NAME=PATH",
        type=_parse_source_set,
        help="repeat exactly once for each complete official ANI resource root",
    )
    parser.add_argument("--output", type=Path, help="write census JSON here instead of stdout")
    parser.add_argument("--old79-components", type=Path, help="preserved old 79-component cache")
    parser.add_argument("--platform-sweep", type=Path, help="preserved platform-sweep cache")
    parser.add_argument("--reconciliation-output", type=Path, help="write historical reconciliation JSON here")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _arguments(argv)
    source_sets: dict[str, Path] = {}
    resource_sets: dict[str, Path] = {}
    duplicate_arguments: list[dict[str, object]] = []
    for name, path in args.source_set:
        if name in source_sets:
            duplicate_arguments.append(
                _anomaly("duplicate_source_set_argument", "source set was supplied more than once", source_set=name)
            )
        source_sets[name] = path
    for name, path in args.resource_set:
        if name in resource_sets:
            duplicate_arguments.append(
                _anomaly(
                    "duplicate_resource_set_argument",
                    "ANI resource set was supplied more than once",
                    source_set=name,
                )
            )
        resource_sets[name] = path

    try:
        if duplicate_arguments:
            raise CensusError(duplicate_arguments)
        reconciliation_arguments = (args.old79_components, args.platform_sweep, args.reconciliation_output)
        if any(reconciliation_arguments) and not all(reconciliation_arguments):
            raise CensusError(
                [
                    _anomaly(
                        "incomplete_reconciliation_arguments",
                        "old79, platform-sweep, and reconciliation output must be supplied together",
                    )
                ]
            )
        report = build_census(source_sets, resource_sets)
        reconciliation = (
            build_reconciliation(report, args.old79_components, args.platform_sweep)
            if all(reconciliation_arguments)
            else None
        )
    except CensusError as exc:
        sys.stderr.write(str(exc) + "\n")
        return 2

    output = render_json(report)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)
    if reconciliation is not None:
        args.reconciliation_output.parent.mkdir(parents=True, exist_ok=True)
        args.reconciliation_output.write_text(render_json(reconciliation), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
