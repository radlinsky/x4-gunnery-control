"""Generic candidate key-record and channel analysis for the Issue #78 census tools."""
from __future__ import annotations

import math
import struct
from collections import Counter

from census_ani_parser import (
    _ANI_CHANNEL_COUNT_FIELDS,
    _ANI_KEY_RECORD_CANDIDATE_SLOTS,
    _candidate_float32_decode,
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


_DESCRIPTOR_RAW_BIT_DISTRIBUTION_LIMIT = 256


def _descriptor_offset_148_raw_uint(descriptor: dict[str, object]) -> int:
    field = descriptor["descriptor_offset_148"]
    return int(str(field["raw_bits"]), 16)


def _descriptor_offset_148_float(descriptor: dict[str, object]) -> float:
    return struct.unpack(
        "<f", struct.pack("<I", _descriptor_offset_148_raw_uint(descriptor))
    )[0]


def _summarize_descriptor_offset_148_values(
    unique_descriptors: dict[tuple[str, int], dict[str, object]],
) -> dict[str, object]:
    raw_bit_counts = Counter(
        str(descriptor["descriptor_offset_148"]["raw_bits"])
        for descriptor in unique_descriptors.values()
    )
    values = [
        _descriptor_offset_148_float(descriptor)
        for descriptor in unique_descriptors.values()
    ]
    finite_count = sum(math.isfinite(value) for value in values)
    numeric_zero_count = sum(math.isfinite(value) and value == 0 for value in values)
    numeric_nonzero_count = sum(
        math.isfinite(value) and value != 0 for value in values
    )
    distribution_is_complete = (
        len(raw_bit_counts) <= _DESCRIPTOR_RAW_BIT_DISTRIBUTION_LIMIT
    )
    distribution = None
    if distribution_is_complete:
        distribution = [
            {
                "raw_bits": raw_bits,
                "candidate_float32_decode": _candidate_float32_decode(
                    int(raw_bits, 16)
                ),
                "descriptor_count": raw_bit_counts[raw_bits],
            }
            for raw_bits in sorted(raw_bit_counts)
        ]
    return {
        "descriptor_count": len(values),
        "finite_count": finite_count,
        "non_finite_count": len(values) - finite_count,
        "numeric_zero_count": numeric_zero_count,
        "numeric_nonzero_count": numeric_nonzero_count,
        "positive_zero_raw_bit_count": raw_bit_counts["0x00000000"],
        "negative_zero_raw_bit_count": raw_bit_counts["0x80000000"],
        "distinct_raw_bit_pattern_count": len(raw_bit_counts),
        "raw_bit_pattern_distribution_limit": (
            _DESCRIPTOR_RAW_BIT_DISTRIBUTION_LIMIT
        ),
        "raw_bit_pattern_distribution_is_complete": distribution_is_complete,
        "raw_bit_pattern_distribution": distribution,
    }


_DESCRIPTOR_SLOT_024_RAW_RELATIONSHIPS = (
    "no_keys",
    "equals_both",
    "equals_first",
    "equals_last",
    "other",
)
_DESCRIPTOR_SLOT_024_NUMERIC_RELATIONSHIPS = (
    "no_keys",
    "non_finite",
    "equals_both",
    "equals_first",
    "equals_last",
    "greater_than_sequence_maximum",
    "less_than_sequence_minimum",
    "other",
)


def _classify_descriptor_slot_024_raw_relationship(
    descriptor_raw_bits: str, records: list[dict[str, object]]
) -> str:
    if not records:
        return "no_keys"
    first_equal = descriptor_raw_bits == str(records[0]["raw_bits"][6])
    last_equal = descriptor_raw_bits == str(records[-1]["raw_bits"][6])
    if first_equal and last_equal:
        return "equals_both"
    if first_equal:
        return "equals_first"
    if last_equal:
        return "equals_last"
    return "other"


def _classify_descriptor_slot_024_numeric_relationship(
    descriptor_value: float, records: list[dict[str, object]]
) -> str:
    if not records:
        return "no_keys"
    values = [float(record["raw_values"][6]) for record in records]
    if not math.isfinite(descriptor_value) or not all(
        math.isfinite(value) for value in values
    ):
        return "non_finite"
    first_equal = descriptor_value == values[0]
    last_equal = descriptor_value == values[-1]
    if first_equal and last_equal:
        return "equals_both"
    if first_equal:
        return "equals_first"
    if last_equal:
        return "equals_last"
    if descriptor_value > max(values):
        return "greater_than_sequence_maximum"
    if descriptor_value < min(values):
        return "less_than_sequence_minimum"
    return "other"


def _summarize_descriptor_slot_024_relationships(
    unique_descriptors: dict[tuple[str, int], dict[str, object]],
) -> list[dict[str, object]]:
    candidate_channels = []
    for channel_index, field in enumerate(_ANI_CHANNEL_COUNT_FIELDS):
        key_count_distribution = {
            "no_keys": 0,
            "one_key": 0,
            "multiple_keys": 0,
        }
        raw_relationships = {
            relationship: 0
            for relationship in _DESCRIPTOR_SLOT_024_RAW_RELATIONSHIPS
        }
        numeric_relationships = {
            relationship: 0
            for relationship in _DESCRIPTOR_SLOT_024_NUMERIC_RELATIONSHIPS
        }
        for descriptor in unique_descriptors.values():
            records = _candidate_channel_records(descriptor, field)
            if not records:
                key_count_distribution["no_keys"] += 1
            elif len(records) == 1:
                key_count_distribution["one_key"] += 1
            else:
                key_count_distribution["multiple_keys"] += 1
            raw_relationships[
                _classify_descriptor_slot_024_raw_relationship(
                    str(descriptor["descriptor_offset_148"]["raw_bits"]), records
                )
            ] += 1
            numeric_relationships[
                _classify_descriptor_slot_024_numeric_relationship(
                    _descriptor_offset_148_float(descriptor), records
                )
            ] += 1
        candidate_channels.append(
            {
                "candidate_channel_id": f"candidate_channel_{channel_index}",
                "candidate_channel_count_field_index": channel_index,
                "key_count_distribution": key_count_distribution,
                "raw_bit_relationship_distribution": raw_relationships,
                "numeric_relationship_distribution": numeric_relationships,
            }
        )
    return candidate_channels


_CANDIDATE_MAIN_SLOT_INDEXES = (0, 1, 2)
_CANDIDATE_MAIN_SLOT_IDS = tuple(
    str(_ANI_KEY_RECORD_CANDIDATE_SLOTS[index]["slot_id"])
    for index in _CANDIDATE_MAIN_SLOT_INDEXES
)


def _candidate_main_component_observations(
    records: list[dict[str, object]],
) -> list[dict[str, object]]:
    observations = []
    for slot_index in _CANDIDATE_MAIN_SLOT_INDEXES:
        raw_bits = [str(record["raw_bits"][slot_index]) for record in records]
        values = [float(record["raw_values"][slot_index]) for record in records]
        finite_values = [value for value in values if math.isfinite(value)]
        observations.append(
            {
                "slot_id": str(
                    _ANI_KEY_RECORD_CANDIDATE_SLOTS[slot_index]["slot_id"]
                ),
                "changes_by_exact_raw_bits": len(set(raw_bits)) > 1,
                "distinct_raw_bit_pattern_count": len(set(raw_bits)),
                "raw_bit_sequence": raw_bits,
                "candidate_numeric_extrema": {
                    "finite_count": len(finite_values),
                    "non_finite_count": len(values) - len(finite_values),
                    "minimum": min(finite_values) if finite_values else None,
                    "maximum": max(finite_values) if finite_values else None,
                },
            }
        )
    return observations


def _restriction_correlation_descriptor_record(
    component: str,
    descriptor: dict[str, object],
    restrictions: list[dict[str, object]],
    membership_count: int,
) -> dict[str, object]:
    records = _candidate_channel_records(
        descriptor, _ANI_CHANNEL_COUNT_FIELDS[1]
    )
    component_observations = _candidate_main_component_observations(records)
    mask = "".join(
        "1" if observation["changes_by_exact_raw_bits"] else "0"
        for observation in component_observations
    )
    return {
        "component": component,
        "descriptor_index": int(descriptor["descriptor_index"]),
        "part": descriptor["part"],
        "subname": descriptor["subname"],
        "source_connection": descriptor["source_connection"],
        "selected_endpoint_membership_count": membership_count,
        "candidate_channel_1_key_count": len(records),
        "changing_component_mask": mask,
        "candidate_main_components": component_observations,
        "restriction_count": len(restrictions),
        "restriction_type_tokens": [
            restriction["type_token"] for restriction in restrictions
        ],
        "authored_restrictions": restrictions,
        "raw_and_authored_evidence_classification": "shipped-source",
        "identity_join_evidence_classification": "shipped-source",
    }


def _restriction_cohort_summary(
    descriptors: list[dict[str, object]],
) -> dict[str, object]:
    cross_tab = Counter()
    source_connections: dict[tuple[str, str], bool] = {}
    ambiguous_cases = []
    for descriptor in descriptors:
        restrictions = descriptor["authored_restrictions"]
        source_connections[
            (str(descriptor["component"]), str(descriptor["source_connection"]))
        ] = bool(restrictions)
        if restrictions:
            for restriction in restrictions:
                cross_tab[
                    (
                        restriction["type_token"],
                        descriptor["changing_component_mask"],
                    )
                ] += 1
        else:
            cross_tab[(None, descriptor["changing_component_mask"])] += 1

        reasons = []
        if len(restrictions) > 1:
            reasons.append("multiple_authored_restrictions")
        elif len(restrictions) == 1:
            token = restrictions[0]["type_token"]
            if token is None:
                reasons.append("missing_restriction_type_token")
            elif token not in ("rotation_x", "rotation_y"):
                reasons.append("single_other_restriction_type_token")
        if reasons:
            ambiguous_cases.append(
                {
                    "component": descriptor["component"],
                    "descriptor_index": descriptor["descriptor_index"],
                    "source_connection": descriptor["source_connection"],
                    "restriction_count": len(restrictions),
                    "restriction_type_tokens": descriptor[
                        "restriction_type_tokens"
                    ],
                    "reasons": reasons,
                }
            )

    def cross_tab_sort_key(item: tuple[tuple[object, str], int]) -> tuple[str, str]:
        (token, mask), _ = item
        return ("" if token is None else str(token), mask)

    return {
        "evidence_classification": "shipped-source",
        "selected_descriptor_memberships": sum(
            int(descriptor["selected_endpoint_membership_count"])
            for descriptor in descriptors
        ),
        "unique_descriptor_count": len(descriptors),
        "descriptors": descriptors,
        "restriction_type_token_by_changing_component_mask": [
            {
                "restriction_type_token": token,
                "changing_component_mask": mask,
                "restriction_record_or_unrestricted_descriptor_count": count,
            }
            for (token, mask), count in sorted(
                cross_tab.items(), key=cross_tab_sort_key
            )
        ],
        "cross_tab_counting_rule": (
            "one count per authored restriction record; an unrestricted"
            " descriptor contributes one null-token count"
        ),
        "unique_source_connection_restriction_counts": {
            "restricted": sum(source_connections.values()),
            "unrestricted": len(source_connections)
            - sum(source_connections.values()),
        },
        "ambiguous_or_multiple_restriction_cases": ambiguous_cases,
    }


def _single_restriction_comparison(
    token: str,
    primary: list[dict[str, object]],
    control: list[dict[str, object]],
) -> dict[str, object]:
    corresponding_index = 0 if token == "rotation_x" else 1
    matching_primary = [
        descriptor
        for descriptor in primary
        if descriptor["restriction_type_tokens"] == [token]
    ]
    matching_control = [
        descriptor
        for descriptor in control
        if descriptor["restriction_type_tokens"] == [token]
    ]
    other_indexes = [
        index for index in _CANDIDATE_MAIN_SLOT_INDEXES if index != corresponding_index
    ]
    observations = []
    for descriptor in matching_primary + matching_control:
        components = descriptor["candidate_main_components"]
        restriction = descriptor["authored_restrictions"][0]
        observations.append(
            {
                "cohort": (
                    "primary_changing_main_triple"
                    if descriptor in matching_primary
                    else "identical_main_triple_control"
                ),
                "component": descriptor["component"],
                "descriptor_index": descriptor["descriptor_index"],
                "source_connection": descriptor["source_connection"],
                "changing_component_mask": descriptor[
                    "changing_component_mask"
                ],
                "authored_min": restriction["authored_min"],
                "authored_max": restriction["authored_max"],
                "corresponding_candidate_component": components[
                    corresponding_index
                ],
                "other_candidate_components": [
                    components[index] for index in other_indexes
                ],
            }
        )
    return {
        "evidence_classification": "inference",
        "observation_values_evidence_classification": "shipped-source",
        "coordinate_name_correspondence_only": (
            "rotation_x token to slot_000; rotation_y token to slot_004;"
            " no axis, unit, or sign semantics assigned"
        ),
        "corresponding_candidate_component": _CANDIDATE_MAIN_SLOT_IDS[
            corresponding_index
        ],
        "primary_descriptor_count": len(matching_primary),
        "control_descriptor_count": len(matching_control),
        "corresponding_component_changed_count": sum(
            descriptor["candidate_main_components"][corresponding_index][
                "changes_by_exact_raw_bits"
            ]
            for descriptor in matching_primary
        ),
        "other_component_changed_counts": {
            _CANDIDATE_MAIN_SLOT_IDS[index]: sum(
                descriptor["candidate_main_components"][index][
                    "changes_by_exact_raw_bits"
                ]
                for descriptor in matching_primary
            )
            for index in other_indexes
        },
        "observations": observations,
    }


def _build_channel_1_restriction_correlation(
    unique_descriptors: dict[tuple[str, int], dict[str, object]],
    membership_counts: Counter[tuple[str, int]],
    component_to_macros: list[dict[str, object]],
) -> dict[str, object]:
    restrictions_by_connection = {
        (str(component["component"]), str(connection["name"])): connection[
            "authored_restrictions"
        ]
        for component in component_to_macros
        if component["component_class"] == "turret"
        for connection in component["connections"]
    }
    primary = []
    control = []
    for identity, descriptor in sorted(unique_descriptors.items()):
        channel_records = _candidate_channel_records(
            descriptor, _ANI_CHANNEL_COUNT_FIELDS[1]
        )
        if len(channel_records) <= 1:
            continue
        record = _restriction_correlation_descriptor_record(
            identity[0],
            descriptor,
            restrictions_by_connection[
                (identity[0], str(descriptor["source_connection"]))
            ],
            membership_counts[identity],
        )
        if record["changing_component_mask"] == "000":
            control.append(record)
        else:
            primary.append(record)

    single_comparisons = {
        token: _single_restriction_comparison(token, primary, control)
        for token in ("rotation_x", "rotation_y")
    }
    primary_single_xy = [
        descriptor
        for descriptor in primary
        if descriptor["restriction_type_tokens"]
        in (["rotation_x"], ["rotation_y"])
    ]
    control_single_xy = [
        descriptor
        for descriptor in control
        if descriptor["restriction_type_tokens"]
        in (["rotation_x"], ["rotation_y"])
    ]
    expected_masks = {"rotation_x": "100", "rotation_y": "010"}
    represented_tokens = {
        descriptor["restriction_type_tokens"][0]
        for descriptor in primary_single_xy
    }
    strong = (
        bool(primary)
        and len(primary_single_xy) == len(primary)
        and represented_tokens == set(expected_masks)
        and all(
            descriptor["changing_component_mask"]
            == expected_masks[descriptor["restriction_type_tokens"][0]]
            for descriptor in primary_single_xy
        )
        and not control_single_xy
    )
    reasons = []
    if len(primary_single_xy) != len(primary):
        reasons.append("primary_contains_non_single_rotation_x_or_y_cases")
    if represented_tokens != set(expected_masks):
        reasons.append("both_rotation_x_and_rotation_y_not_represented_in_primary")
    if any(
        descriptor["changing_component_mask"]
        != expected_masks[descriptor["restriction_type_tokens"][0]]
        for descriptor in primary_single_xy
    ):
        reasons.append("single_restriction_primary_masks_are_not_one_to_one")
    if control_single_xy:
        reasons.append("same_single_restriction_tokens_occur_in_identical_triple_controls")
    return {
        "evidence_classification": "inference",
        "raw_ani_and_authored_restriction_evidence_classification": (
            "shipped-source"
        ),
        "identity_join_evidence_classification": "shipped-source",
        "x4converter_label_lead": {
            "label": "rotation_euler",
            "evidence_classification": "third-party-technique",
            "semantic_promotion": "not_permitted_by_this_study",
        },
        "candidate_channel_identity": "candidate_channel_1",
        "candidate_main_slot_ids": list(_CANDIDATE_MAIN_SLOT_IDS),
        "primary_cohort_rule": (
            "more than one candidate channel 1 key and at least one of"
            " slots 000/004/008 changes by exact raw bits"
        ),
        "control_cohort_rule": (
            "more than one candidate channel 1 key and slots 000/004/008"
            " are all identical by exact raw bits"
        ),
        "primary_changing_main_triple_cohort": _restriction_cohort_summary(
            primary
        ),
        "identical_main_triple_control_cohort": _restriction_cohort_summary(
            control
        ),
        "single_rotation_x_or_y_restriction_comparisons": single_comparisons,
        "semantic_discriminator_assessment": {
            "evidence_classification": "inference",
            "status": (
                "strong_one_to_one_observed"
                if strong
                else "not_strong_one_to_one"
            ),
            "reasons": reasons,
            "semantic_conclusion": "none",
        },
        "forbidden_semantic_claims": [
            "Euler order",
            "units",
            "sign",
            "interpolation",
            "pivot",
            "transform composition",
            "runtime behavior",
        ],
    }
