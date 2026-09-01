"""Generic candidate key-record and channel analysis for the Issue #78 census tools."""
from __future__ import annotations

import math
from collections import Counter

from census_ani_parser import (
    _ANI_CHANNEL_COUNT_FIELDS,
    _ANI_KEY_RECORD_CANDIDATE_SLOTS,
)

_ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOT_INDEXES = (0, 1, 2)
_ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOTS = tuple(
    _ANI_KEY_RECORD_CANDIDATE_SLOTS[index]
    for index in _ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOT_INDEXES
)


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
            channel_records = _candidate_channel_records(descriptor, field)
            key_count = len(channel_records)
            if key_count == 0:
                classification = "zero_keys"
            elif key_count == 1:
                classification = "one_key"
            else:
                classification = "multiple_keys_" + (
                    _classify_candidate_multi_key_triples(channel_records)
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


_CANDIDATE_MULTI_KEY_TRIPLE_CLASSES = (
    "identical_raw_bit_triples",
    "changing_raw_bit_triples",
)
_CANDIDATE_NUMERIC_ORDERING_SHAPES = (
    "all_equal",
    "strictly_increasing",
    "nondecreasing",
    "other",
)


def _candidate_channel_records(
    descriptor: dict[str, object], field: str
) -> list[dict[str, object]]:
    record_range = descriptor["key_data"]["channels"][field]["record_range"]
    return [
        record
        for record in descriptor["_candidate_raw_key_records"]
        if int(record_range["start"])
        <= int(record["record_index"])
        < int(record_range["end_exclusive"])
    ]


def _classify_candidate_multi_key_triples(
    records: list[dict[str, object]],
) -> str:
    raw_bit_triples = {
        tuple(
            str(record["raw_bits"][slot_index])
            for slot_index in _ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOT_INDEXES
        )
        for record in records
    }
    return (
        "identical_raw_bit_triples"
        if len(raw_bit_triples) == 1
        else "changing_raw_bit_triples"
    )


def _candidate_slot_pattern_inventory(
    descriptor_records: list[tuple[dict[str, object], list[dict[str, object]]]],
    slot_index: int,
) -> dict[str, object]:
    raw_bits = [
        str(record["raw_bits"][slot_index])
        for _, records in descriptor_records
        for record in records
    ]
    raw_bit_counts = Counter(raw_bits)
    descriptor_pattern_counts = [
        len({str(record["raw_bits"][slot_index]) for record in records})
        for _, records in descriptor_records
    ]
    return {
        "slot_id": str(_ANI_KEY_RECORD_CANDIDATE_SLOTS[slot_index]["slot_id"]),
        "record_count": len(raw_bits),
        "raw_bit_zero_count": raw_bit_counts["0x00000000"],
        "raw_bit_nonzero_count": len(raw_bits) - raw_bit_counts["0x00000000"],
        "distinct_raw_bit_pattern_count": len(raw_bit_counts),
        "raw_bit_pattern_distribution": [
            {"raw_bits": bits, "record_count": raw_bit_counts[bits]}
            for bits in sorted(raw_bit_counts)
        ],
        "constant_across_all_records": (
            len(raw_bit_counts) == 1 if raw_bits else None
        ),
        "descriptors_with_constant_raw_bits": sum(
            count == 1 for count in descriptor_pattern_counts
        ),
        "descriptors_with_differing_raw_bits": sum(
            count > 1 for count in descriptor_pattern_counts
        ),
    }


def _candidate_numeric_ordering_shape(values: list[float]) -> str:
    if not all(math.isfinite(value) for value in values):
        return "other"
    if all(value == values[0] for value in values[1:]):
        return "all_equal"
    if all(left < right for left, right in zip(values, values[1:])):
        return "strictly_increasing"
    if all(left <= right for left, right in zip(values, values[1:])):
        return "nondecreasing"
    return "other"


def _summarize_candidate_channel_metadata(
    descriptor_records: list[tuple[dict[str, object], list[dict[str, object]]]],
) -> dict[str, object]:
    records = [record for _, group in descriptor_records for record in group]
    enum_triplets = Counter(
        (
            tuple(str(record["raw_bits"][slot_index]) for slot_index in (3, 4, 5)),
            tuple(int(record["raw_values"][slot_index]) for slot_index in (3, 4, 5)),
        )
        for record in records
    )
    slot_024 = _candidate_slot_pattern_inventory(descriptor_records, 6)
    slot_024_values = [float(record["raw_values"][6]) for record in records]
    slot_024["finite_count"] = sum(
        math.isfinite(value) for value in slot_024_values
    )
    slot_024["non_finite_count"] = len(slot_024_values) - int(
        slot_024["finite_count"]
    )
    ordering_shapes = {
        shape: {"descriptor_count": 0, "key_record_count": 0}
        for shape in _CANDIDATE_NUMERIC_ORDERING_SHAPES
    }
    for _, group in descriptor_records:
        shape = _candidate_numeric_ordering_shape(
            [float(record["raw_values"][6]) for record in group]
        )
        ordering_shapes[shape]["descriptor_count"] += 1
        ordering_shapes[shape]["key_record_count"] += len(group)
    slot_024["descriptor_numeric_ordering_shapes"] = ordering_shapes
    return {
        "descriptor_count": len(descriptor_records),
        "key_record_count": len(records),
        "candidate_enum_triplet_distribution": [
            {
                "raw_bits": list(raw_triplet),
                "candidate_values": list(value_triplet),
                "record_count": enum_triplets[(raw_triplet, value_triplet)],
            }
            for raw_triplet, value_triplet in sorted(enum_triplets)
        ],
        "slot_024": slot_024,
        "slots_028_072": [
            _candidate_slot_pattern_inventory(descriptor_records, slot_index)
            for slot_index in range(7, 19)
        ],
        "slots_076_124": [
            _candidate_slot_pattern_inventory(descriptor_records, slot_index)
            for slot_index in range(19, 32)
        ],
    }


def _inventory_candidate_multi_key_metadata(
    unique_descriptors: dict[tuple[str, int], dict[str, object]],
    selected_descriptor_memberships: int,
    *,
    include_patterns: bool,
) -> dict[str, object]:
    candidate_channels = []
    for channel_index, field in enumerate(_ANI_CHANNEL_COUNT_FIELDS):
        grouped: dict[
            str, list[tuple[dict[str, object], list[dict[str, object]]]]
        ] = {classification: [] for classification in _CANDIDATE_MULTI_KEY_TRIPLE_CLASSES}
        for descriptor in unique_descriptors.values():
            records = _candidate_channel_records(descriptor, field)
            if len(records) <= 1:
                continue
            grouped[_classify_candidate_multi_key_triples(records)].append(
                (descriptor, records)
            )
        if include_patterns:
            classifications = {
                classification: _summarize_candidate_channel_metadata(
                    grouped[classification]
                )
                for classification in _CANDIDATE_MULTI_KEY_TRIPLE_CLASSES
            }
        else:
            classifications = {
                classification: {
                    "descriptor_count": len(grouped[classification]),
                    "key_record_count": sum(
                        len(records) for _, records in grouped[classification]
                    ),
                }
                for classification in _CANDIDATE_MULTI_KEY_TRIPLE_CLASSES
            }
        candidate_channels.append(
            {
                "candidate_channel_id": f"candidate_channel_{channel_index}",
                "candidate_channel_count_field_index": channel_index,
                "multiple_key_descriptors": classifications,
            }
        )
    return {
        "selected_descriptor_memberships": selected_descriptor_memberships,
        "unique_selected_descriptors": len(unique_descriptors),
        "candidate_channels": candidate_channels,
    }


def _candidate_main_triple_changing_mask(
    records: list[dict[str, object]],
) -> str:
    return "".join(
        "1"
        if len(
            {
                str(record["raw_bits"][slot_index])
                for record in records
            }
        )
        > 1
        else "0"
        for slot_index in _ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOT_INDEXES
    )
