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
import math
import struct
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path
from typing import Mapping, Sequence

from census_ani_analysis import (
    _ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOTS,
    _ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOT_INDEXES,
    _CANDIDATE_CHANNEL_DYNAMICS_CLASSIFICATIONS,
    _CANDIDATE_MULTI_KEY_TRIPLE_CLASSES,
    _CANDIDATE_NUMERIC_ORDERING_SHAPES,
    _candidate_channel_records,
    _candidate_main_triple_changing_mask,
    _candidate_numeric_ordering_shape,
    _candidate_slot_pattern_inventory,
    _classify_candidate_multi_key_triples,
    _inventory_candidate_multi_key_metadata,
    _summarize_candidate_channel_dynamics,
    _summarize_candidate_channel_metadata,
    _summarize_candidate_raw_key_records,
)
from census_ani_parser import (
    AniDescriptorError,
    _ANI_CHANNEL_COUNT_FIELDS,
    _ANI_DESCRIPTOR_OFFSET_148,
    _ANI_DESCRIPTOR_SIZE,
    _ANI_HEADER_SIZE,
    _ANI_KEY_RECORD_CANDIDATE_BYTE_COUNTS,
    _ANI_KEY_RECORD_CANDIDATE_OVERLAPPING_BYTES,
    _ANI_KEY_RECORD_CANDIDATE_SLOTS,
    _ANI_KEY_RECORD_CANDIDATE_TYPES,
    _ANI_KEY_RECORD_CANDIDATE_UNACCOUNTED_BYTES,
    _ANI_KEY_RECORD_SIZE,
    _ANI_STRING_SIZE,
    _candidate_float32_decode,
    _decode_ani_descriptor_string,
    _parse_ani_descriptors,
    _parse_candidate_key_record,
)
from census_common import (
    REQUIRED_SOURCE_SETS,
    CensusError,
    _anomaly,
    render_json,
)
from census_eligibility import (
    _build_combat_conventional_turret_eligibility,
    _purpose_tokens,
)
from census_endpoint_paths import (
    _FIRING_ENDPOINT_TAG_BY_COMPONENT_CLASS,
    _classify_firing_endpoints,
    _derive_endpoint_source_paths,
    _join_authored_animation_selectors,
    _resolve_connection_hierarchy,
)
from census_identity import (
    _INCLUDED_CLASSES,
    _authored_numeric_attributes,
    _authored_restriction_limit,
    _build_ani_resource_inventory,
    _collect_xml_identities,
    _direct_children,
    _normalized_resource_identity,
    _parse_authored_connection_offset,
    _parse_authored_connection_restrictions,
    _resolve_component_identity,
    _resolve_geometry_ani_resource_identity,
    _resolve_macro_identities,
    _validate_authored_animation_selectors,
)
from census_sources import (
    _validate_resource_sets,
    _validate_source_sets,
    _xml_files,
)

_DESCRIPTOR_RAW_BIT_DISTRIBUTION_LIMIT = 256
_ACCEPTED_TURRET_ACTIVE_CHANGING_CASE_BASELINE = (444, 2, 2)


def _subname_candidate_channel_summary(
    descriptors: list[dict[str, object]],
) -> list[dict[str, object]]:
    candidate_channels = []
    for channel_index, field in enumerate(_ANI_CHANNEL_COUNT_FIELDS):
        classifications = {
            classification: {"descriptor_count": 0, "key_record_count": 0}
            for classification in _CANDIDATE_CHANNEL_DYNAMICS_CLASSIFICATIONS
        }
        multi_key_masks: Counter[str] = Counter()
        multi_key_mask_records: Counter[str] = Counter()
        descriptor_records = []
        for descriptor in descriptors:
            records = _candidate_channel_records(descriptor, field)
            key_count = len(records)
            if key_count == 0:
                classification = "zero_keys"
            elif key_count == 1:
                classification = "one_key"
            else:
                classification = "multiple_keys_" + (
                    _classify_candidate_multi_key_triples(records)
                )
                mask = _candidate_main_triple_changing_mask(records)
                multi_key_masks[mask] += 1
                multi_key_mask_records[mask] += key_count
            classifications[classification]["descriptor_count"] += 1
            classifications[classification]["key_record_count"] += key_count
            if records:
                descriptor_records.append((descriptor, records))

        metadata = _summarize_candidate_channel_metadata(descriptor_records)
        candidate_channels.append(
            {
                "candidate_channel_id": f"candidate_channel_{channel_index}",
                "candidate_channel_count_field_index": channel_index,
                "classifications": classifications,
                "multi_key_main_triple_masks": [
                    {
                        "changing_mask_slots_000_004_008": mask,
                        "descriptor_count": multi_key_masks[mask],
                        "key_record_count": multi_key_mask_records[mask],
                    }
                    for mask in sorted(multi_key_masks)
                ],
                "observed_candidate_metadata": {
                    "candidate_enum_triplet_distribution": metadata[
                        "candidate_enum_triplet_distribution"
                    ],
                    "slot_024_raw_bit_pattern_distribution": metadata[
                        "slot_024"
                    ]["raw_bit_pattern_distribution"],
                    "slot_024_ordering_shapes": metadata["slot_024"][
                        "descriptor_numeric_ordering_shapes"
                    ],
                },
            }
        )
    return candidate_channels


def _subname_inventory_for_class(
    unique_descriptors: dict[tuple[str, int], dict[str, object]],
    membership_counts: Counter[tuple[str, int]],
) -> dict[str, object]:
    descriptors_by_subname: dict[
        str, list[tuple[tuple[str, int], dict[str, object]]]
    ] = defaultdict(list)
    for identity, descriptor in unique_descriptors.items():
        descriptors_by_subname[str(descriptor["subname"])].append(
            (identity, descriptor)
        )

    subnames = []
    for subname in sorted(descriptors_by_subname):
        identity_descriptors = sorted(descriptors_by_subname[subname])
        descriptors = [descriptor for _, descriptor in identity_descriptors]
        components = sorted({identity[0] for identity, _ in identity_descriptors})
        source_connections = sorted(
            {
                (identity[0], str(descriptor["source_connection"]))
                for identity, descriptor in identity_descriptors
            }
        )
        family_descriptors: dict[tuple[int, ...], list[tuple[str, int]]] = (
            defaultdict(list)
        )
        for identity, descriptor in identity_descriptors:
            family = tuple(
                int(descriptor["channel_counts"][field])
                for field in _ANI_CHANNEL_COUNT_FIELDS
            )
            family_descriptors[family].append(identity)
        subnames.append(
            {
                "subname": subname,
                "subname_evidence_classification": "shipped-source",
                "selected_endpoint_memberships": sum(
                    membership_counts[identity]
                    for identity, _ in identity_descriptors
                ),
                "unique_descriptor_count": len(identity_descriptors),
                "unique_component_count": len(components),
                "components": components,
                "unique_source_connection_count": len(source_connections),
                "source_connections": [
                    {
                        "component": component,
                        "source_connection": source_connection,
                    }
                    for component, source_connection in source_connections
                ],
                "channel_count_families": [
                    {
                        "candidate_channel_key_counts": list(family),
                        "unique_descriptor_count": len(
                            family_descriptors[family]
                        ),
                        "selected_endpoint_memberships": sum(
                            membership_counts[identity]
                            for identity in family_descriptors[family]
                        ),
                    }
                    for family in sorted(family_descriptors)
                ],
                "candidate_channels": _subname_candidate_channel_summary(
                    descriptors
                ),
            }
        )
    return {
        "selected_endpoint_memberships": sum(membership_counts.values()),
        "unique_descriptor_count": len(unique_descriptors),
        "exact_case_sensitive_subname_count": len(subnames),
        "subnames": subnames,
    }


def _focused_literal_turret_active(
    conventional_inventory: dict[str, object],
) -> dict[str, object]:
    active = next(
        (
            entry
            for entry in conventional_inventory["subnames"]
            if entry["subname"] == "turret_active"
        ),
        None,
    )
    channel_ids = [
        f"candidate_channel_{index}"
        for index in range(len(_ANI_CHANNEL_COUNT_FIELDS))
    ]
    if active is None:
        present_channel_ids = []
        absent_by_present_channel = []
    else:
        present_channel_ids = [
            channel["candidate_channel_id"]
            for channel in active["candidate_channels"]
            if sum(
                classification["key_record_count"]
                for classification in channel["classifications"].values()
            )
            > 0
        ]
        absent_by_present_channel = []
        for channel in active["candidate_channels"]:
            channel_id = channel["candidate_channel_id"]
            if channel_id not in present_channel_ids:
                continue
            absent_multi_key_classifications = [
                classification
                for classification in (
                    "multiple_keys_identical_raw_bit_triples",
                    "multiple_keys_changing_raw_bit_triples",
                )
                if channel["classifications"][classification][
                    "descriptor_count"
                ]
                == 0
            ]
            absent_ordering_shapes = [
                shape
                for shape in _CANDIDATE_NUMERIC_ORDERING_SHAPES
                if channel["observed_candidate_metadata"][
                    "slot_024_ordering_shapes"
                ][shape]["descriptor_count"]
                == 0
            ]
            absent_by_present_channel.append(
                {
                    "candidate_channel_id": channel_id,
                    "absent_multi_key_classifications": (
                        absent_multi_key_classifications
                    ),
                    "absent_slot_024_ordering_shapes": absent_ordering_shapes,
                }
            )
    absent_channel_ids = [
        channel_id
        for channel_id in channel_ids
        if channel_id not in present_channel_ids
    ]
    return {
        "literal_subname": "turret_active",
        "present": active is not None,
        "conventional_inventory": active,
        "present_candidate_channels": present_channel_ids,
        "absent_candidate_channels": absent_channel_ids,
        "absent_metadata_forms": {
            "candidate_channels_without_enum_triplet_values": absent_channel_ids,
            "candidate_channels_without_slot_024_values": absent_channel_ids,
            "by_present_candidate_channel": absent_by_present_channel,
        },
        "absence_scope_statement": {
            "evidence_classification": "inference",
            "finding": (
                "absence can narrow later proof scope but does not prove"
                " runtime irrelevance"
            ),
        },
        "literal_token_semantic_claim": "none",
    }


def _build_subname_candidate_channel_inventory(
    selected_unique_descriptors_by_class: dict[
        str, dict[tuple[str, int], dict[str, object]]
    ],
    selected_endpoint_path_descriptor_memberships: list[
        tuple[dict[str, object], dict[str, object]]
    ],
) -> dict[str, object]:
    membership_counts_by_class = {
        component_class: Counter(
            (
                str(endpoint["component"]),
                int(descriptor["descriptor_index"]),
            )
            for endpoint, descriptor in selected_endpoint_path_descriptor_memberships
            if endpoint["component_class"] == component_class
        )
        for component_class in sorted(_INCLUDED_CLASSES)
    }
    conventional = _subname_inventory_for_class(
        selected_unique_descriptors_by_class["turret"],
        membership_counts_by_class["turret"],
    )
    missile = _subname_inventory_for_class(
        selected_unique_descriptors_by_class["missileturret"],
        membership_counts_by_class["missileturret"],
    )
    missile["non_decision_driving"] = True
    return {
        "evidence_classification": "inference",
        "raw_subname_counts_and_bits_evidence_classification": "shipped-source",
        "candidate_channel_ownership_and_layout_evidence_classification": (
            "third-party-technique"
        ),
        "descriptor_identity": ["component", "descriptor_index"],
        "subname_grouping_rule": "exact case-sensitive equality",
        "candidate_channel_semantic_claim": "none",
        "conventional": conventional,
        "focused_literal_turret_active": _focused_literal_turret_active(
            conventional
        ),
        "missileturret_accounting": missile,
    }


def _candidate_first_three_change_case(
    descriptor: dict[str, object],
    relationship: dict[str, object],
    channel_index: int,
) -> dict[str, object]:
    field = _ANI_CHANNEL_COUNT_FIELDS[channel_index]
    records = _candidate_channel_records(descriptor, field)
    reported_slot_indexes = tuple(range(7))
    first_three_slot_changes = []
    for slot_index in _ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOT_INDEXES:
        raw_bits = [str(record["raw_bits"][slot_index]) for record in records]
        candidate_values = [
            float(record["raw_values"][slot_index]) for record in records
        ]
        raw_bits_change = len(set(raw_bits)) > 1
        candidate_numeric_values_change = any(
            value != candidate_values[0] for value in candidate_values[1:]
        )
        if candidate_numeric_values_change:
            classification = "numerically_different"
        elif raw_bits_change:
            classification = "stored_representation_only"
        else:
            classification = "unchanged"
        first_three_slot_changes.append(
            {
                "slot_id": _ANI_KEY_RECORD_CANDIDATE_SLOTS[slot_index]["slot_id"],
                "raw_bits_change": raw_bits_change,
                "candidate_numeric_values_change": candidate_numeric_values_change,
                "change_classification": classification,
            }
        )

    return {
        "evidence_classification": "inference",
        "semantic_claim": "none",
        "candidate_channel_id": f"candidate_channel_{channel_index}",
        "equipment_macros": list(relationship["equipment_macros"]),
        "turret_component_asset": relationship["component"],
        "descriptor_index": relationship["descriptor_index"],
        "ani_descriptor": {
            "part": relationship["part"],
            "subname": relationship["literal_subname"],
        },
        "component_connection": relationship["source_connection"],
        "root_to_component_connection_path": list(
            relationship["root_to_source_connection_path"]
        ),
        "same_name_ancestor_coverage_relationship": (
            "same_connection"
            if relationship["same_connection_selector"]
            else "strict_ancestor_distance_"
            + str(relationship["nearest_ancestor_same_subname_selector_distance"])
        ),
        "same_name_selector_relationships": list(
            relationship["same_subname_selector_relationships"]
        ),
        "key_count_family": [
            int(descriptor["channel_counts"][count_field])
            for count_field in _ANI_CHANNEL_COUNT_FIELDS
        ],
        "muzzle_endpoint_membership_count": relationship[
            "endpoint_membership_count"
        ],
        "muzzle_endpoint_memberships": list(
            relationship["muzzle_endpoint_memberships"]
        ),
        "first_three_slot_changes": first_three_slot_changes,
        "numerically_different_change_occurs": any(
            item["change_classification"] == "numerically_different"
            for item in first_three_slot_changes
        ),
        "stored_representation_only_change_occurs": any(
            item["change_classification"] == "stored_representation_only"
            for item in first_three_slot_changes
        ),
        "key_records": [
            {
                "candidate_channel_record_index": local_index,
                "ani_record_index": record["record_index"],
                "slots": {
                    str(_ANI_KEY_RECORD_CANDIDATE_SLOTS[slot_index]["slot_id"]): {
                        "raw_bits": record["raw_bits"][slot_index],
                        "candidate_type": _ANI_KEY_RECORD_CANDIDATE_SLOTS[
                            slot_index
                        ]["candidate_type"],
                        "candidate_value": record["raw_values"][slot_index],
                    }
                    for slot_index in reported_slot_indexes
                },
            }
            for local_index, record in enumerate(records)
        ],
    }


def _build_changing_turret_active_case_inventory(
    cohort: list[
        tuple[
            tuple[str, int],
            dict[str, object],
            dict[str, object],
            int,
        ]
    ],
    expected_baseline: tuple[int, int, int] | None,
) -> dict[str, object]:
    cases_by_channel: dict[int, list[dict[str, object]]] = {0: [], 1: []}
    changing_channels_by_identity: dict[tuple[str, int], set[int]] = defaultdict(set)
    identity_details: dict[tuple[str, int], dict[str, object]] = {}
    for identity, descriptor, relationship, _ in cohort:
        identity_details[identity] = relationship
        for channel_index in (0, 1):
            records = _candidate_channel_records(
                descriptor, _ANI_CHANNEL_COUNT_FIELDS[channel_index]
            )
            if len(records) <= 1 or _classify_candidate_multi_key_triples(
                records
            ) != "changing_raw_bit_triples":
                continue
            cases_by_channel[channel_index].append(
                _candidate_first_three_change_case(
                    descriptor, relationship, channel_index
                )
            )
            changing_channels_by_identity[identity].add(channel_index)

    for cases in cases_by_channel.values():
        cases.sort(
            key=lambda case: (
                str(case["turret_component_asset"]),
                int(case["descriptor_index"]),
            )
        )
    actual_counts = tuple(len(cases_by_channel[index]) for index in (0, 1))
    if expected_baseline is None:
        reconciliation_status = "not_enforced"
    else:
        expected_cohort, expected_channel_0, expected_channel_1 = expected_baseline
        expected_counts = (expected_channel_0, expected_channel_1)
        if len(cohort) != expected_cohort or actual_counts != expected_counts:
            raise CensusError(
                [
                    _anomaly(
                        "accepted_turret_active_changing_case_baseline_mismatch",
                        "current source does not match the required accepted turret_active changing-case baseline",
                        expected_cohort_unique_descriptors=expected_cohort,
                        actual_cohort_unique_descriptors=len(cohort),
                        expected_candidate_channel_0_descriptors=expected_channel_0,
                        actual_candidate_channel_0_descriptors=actual_counts[0],
                        expected_candidate_channel_1_descriptors=expected_channel_1,
                        actual_candidate_channel_1_descriptors=actual_counts[1],
                    )
                ]
            )
        reconciliation_status = "pass"

    both_identities = sorted(
        identity
        for identity, channels in changing_channels_by_identity.items()
        if channels == {0, 1}
    )
    return {
        "evidence_classification": "inference",
        "raw_stored_values_evidence_classification": "shipped-source",
        "candidate_numeric_decode_evidence_classification": (
            "third-party-technique"
        ),
        "semantic_claim": "none",
        "cohort_unique_descriptor_count": len(cohort),
        "accepted_changing_descriptor_counts": {
            "candidate_channel_0": actual_counts[0],
            "candidate_channel_1": actual_counts[1],
        },
        "reconciliation_status": reconciliation_status,
        "candidate_channels": [
            {
                "candidate_channel_id": f"candidate_channel_{channel_index}",
                "changing_descriptor_count": len(cases_by_channel[channel_index]),
                "changing_descriptors": cases_by_channel[channel_index],
            }
            for channel_index in (0, 1)
        ],
        "descriptors_changing_in_both_candidate_channels_0_and_1": [
            {
                "component": identity[0],
                "descriptor_index": identity[1],
                "part": identity_details[identity]["part"],
                "subname": identity_details[identity]["literal_subname"],
            }
            for identity in both_identities
        ],
        "meaning_boundary": (
            "stored-value differences and candidate numeric decodes identify"
            " cases only; their X4 meanings remain unresolved"
        ),
    }


def _build_ancestry_covered_turret_active_candidate_channel_inventory(
    cohort: list[
        tuple[
            tuple[str, int],
            dict[str, object],
            dict[str, object],
            int,
        ]
    ],
    expected_changing_case_baseline: tuple[int, int, int] | None = None,
) -> dict[str, object]:
    family_counts: Counter[tuple[int, ...]] = Counter()
    family_memberships: Counter[tuple[int, ...]] = Counter()
    relation_family_counts: Counter[
        tuple[bool, int | None, tuple[int, ...]]
    ] = Counter()
    relation_family_memberships: Counter[
        tuple[bool, int | None, tuple[int, ...]]
    ] = Counter()
    descriptors = []
    raw_descriptors = []
    for identity, descriptor, relationship, membership_count in cohort:
        family = tuple(
            int(descriptor["channel_counts"][field])
            for field in _ANI_CHANNEL_COUNT_FIELDS
        )
        if bool(relationship["same_connection_selector"]):
            structural_relation = "same_connection"
        else:
            structural_relation = "strict_ancestor_distance_" + str(
                relationship["nearest_ancestor_same_subname_selector_distance"]
            )
        family_counts[family] += 1
        family_memberships[family] += membership_count
        relation_key = (
            bool(relationship["same_connection_selector"]),
            relationship["nearest_ancestor_same_subname_selector_distance"],
            family,
        )
        relation_family_counts[relation_key] += 1
        relation_family_memberships[relation_key] += membership_count
        raw_descriptors.append(descriptor)
        descriptors.append(
            {
                "component": identity[0],
                "descriptor_index": identity[1],
                "part": str(descriptor["part"]),
                "source_connection": str(descriptor["source_connection"]),
                "root_to_source_connection_path": list(
                    descriptor["root_to_source_connection_path"]
                ),
                "structural_relation": structural_relation,
                "candidate_channel_key_counts": list(family),
                "endpoint_membership_count": membership_count,
            }
        )

    candidate_channels = _subname_candidate_channel_summary(raw_descriptors)
    for channel_index, field in enumerate(_ANI_CHANNEL_COUNT_FIELDS):
        channel = candidate_channels[channel_index]
        multi_descriptor_records = []
        metadata_varies = False
        enum_raw_values = {
            slot_id: set()
            for slot_id in ("slot_012", "slot_016", "slot_020")
        }
        for descriptor in raw_descriptors:
            records = _candidate_channel_records(descriptor, field)
            for record in records:
                for slot_index, slot_id in zip((3, 4, 5), enum_raw_values):
                    enum_raw_values[slot_id].add(str(record["raw_bits"][slot_index]))
            if len(records) <= 1:
                continue
            multi_descriptor_records.append((descriptor, records))
            if any(
                len({str(record["raw_bits"][slot_index]) for record in records}) > 1
                for slot_index in range(3, len(_ANI_KEY_RECORD_CANDIDATE_SLOTS))
            ):
                metadata_varies = True
        multi_metadata = _summarize_candidate_channel_metadata(
            multi_descriptor_records
        )
        channel["multi_key_metadata"] = {
            "slots_028_072": multi_metadata["slots_028_072"],
            "slots_076_124": multi_metadata["slots_076_124"],
        }
        channel["proof_scope"] = {
            "evidence_classification": "inference",
            "candidate_channel_id": channel["candidate_channel_id"],
            "records_occur": any(
                item["key_record_count"] > 0
                for item in channel["classifications"].values()
            ),
            "changing_main_triples_occur": channel["classifications"][
                "multiple_keys_changing_raw_bit_triples"
            ]["descriptor_count"] > 0,
            "multi_key_metadata_varies": metadata_varies,
            "enum_raw_values": {
                slot_id: sorted(values)
                for slot_id, values in enum_raw_values.items()
            },
        }

    endpoint_membership_count = sum(item[3] for item in cohort)
    family_rows = [
        {
            "candidate_channel_key_counts": list(family),
            "unique_descriptor_count": family_counts[family],
            "endpoint_membership_count": family_memberships[family],
        }
        for family in sorted(family_counts)
    ]
    relation_family_rows = [
        {
            "same_connection_selector": same_connection,
            "nearest_strict_ancestor_distance": ancestor_distance,
            "candidate_channel_key_counts": list(family),
            "unique_descriptor_count": relation_family_counts[
                (same_connection, ancestor_distance, family)
            ],
            "endpoint_membership_count": relation_family_memberships[
                (same_connection, ancestor_distance, family)
            ],
        }
        for same_connection, ancestor_distance, family in sorted(
            relation_family_counts,
            key=lambda item: (
                not item[0],
                -1 if item[1] is None else int(item[1]),
                item[2],
            ),
        )
    ]
    channel_3_or_4 = {
        f"candidate_channel_{index}": {
            "records_occur": candidate_channels[index]["proof_scope"]["records_occur"],
            "descriptor_count_with_records": sum(
                item["descriptor_count"]
                for name, item in candidate_channels[index]["classifications"].items()
                if name != "zero_keys"
            ),
            "key_record_count": sum(
                item["key_record_count"]
                for item in candidate_channels[index]["classifications"].values()
            ),
        }
        for index in (3, 4)
    }
    paranid_descriptors = [
        descriptor
        for descriptor in descriptors
        if descriptor["component"] == "turret_par_l_beam_01_mk1"
        and descriptor["descriptor_index"] in (12, 22)
    ]
    return {
        "evidence_classification": "inference",
        "raw_ani_subname_path_evidence_classification": "shipped-source",
        "candidate_channel_field_layout_evidence_classification": (
            "third-party-technique"
        ),
        "semantic_claim": "none",
        "literal_subname": "turret_active",
        "literal_name_match_rule": "exact case-sensitive equality",
        "descriptor_identity": ["component", "descriptor_index"],
        "cohort_rule": (
            "unique conventional endpoint-path descriptors with same-connection"
            " or strict-ancestor exact same-subname structural coverage"
        ),
        "missileturrets_excluded_from_cohort": True,
        "unique_descriptor_count": len(cohort),
        "endpoint_membership_count": endpoint_membership_count,
        "descriptors": descriptors,
        "channel_count_families": family_rows,
        "candidate_channels": candidate_channels,
        "structural_relation_channel_family_cross_tab": relation_family_rows,
        "proof_scope_matrix": [
            channel["proof_scope"] for channel in candidate_channels
        ],
        "candidate_channels_3_or_4_occurrence": channel_3_or_4,
        "paranid_l_beam_descriptors_12_and_22": paranid_descriptors,
        "changing_first_three_stored_values_inventory": (
            _build_changing_turret_active_case_inventory(
                cohort, expected_changing_case_baseline
            )
        ),
        "proof_scope_boundary": (
            "absence may narrow later proof scope but does not establish runtime"
            " irrelevance; structural coverage does not establish runtime use"
        ),
    }


def _build_same_subname_structural_relationship_coverage(
    component_to_macros: list[dict[str, object]],
    firing_endpoints: list[dict[str, object]],
    expected_turret_active_changing_case_baseline: (
        tuple[int, int, int] | None
    ) = None,
) -> dict[str, object]:
    """Inventory exact-name selector locations relative to conventional path descriptors."""

    components = {
        str(record["component"]): record
        for record in component_to_macros
        if record["component_class"] == "turret"
    }
    membership_counts: Counter[tuple[str, int]] = Counter()
    endpoints_by_descriptor: dict[tuple[str, int], list[str]] = defaultdict(list)
    endpoint_memberships_by_descriptor: dict[
        tuple[str, int], list[dict[str, object]]
    ] = defaultdict(list)
    descriptors: dict[tuple[str, int], dict[str, object]] = {}
    for endpoint in firing_endpoints:
        if endpoint["component_class"] != "turret":
            continue
        component = str(endpoint["component"])
        for descriptor in endpoint["ani_descriptor_memberships"]:
            identity = (component, int(descriptor["descriptor_index"]))
            membership_counts[identity] += 1
            endpoints_by_descriptor[identity].append(str(endpoint["connection"]))
            endpoint_memberships_by_descriptor[identity].append(
                {
                    "connection": str(endpoint["connection"]),
                    "root_to_endpoint_connection_path": list(
                        endpoint.get(
                            "root_to_endpoint_connection_path",
                            [str(endpoint["connection"])],
                        )
                    ),
                    "descriptor_endpoint_path_edge_index": descriptor.get(
                        "endpoint_path_edge_index"
                    ),
                }
            )
            descriptors.setdefault(identity, descriptor)

    inventory = []
    ancestry_covered_turret_active_cohort = []
    relationship_counts: Counter[str] = Counter()
    cross_tab_counts: Counter[tuple[object, ...]] = Counter()
    cross_tab_memberships: Counter[tuple[object, ...]] = Counter()
    covered_descriptors = 0
    for identity in sorted(descriptors):
        component, descriptor_index = identity
        descriptor = descriptors[identity]
        source_connection = str(descriptor["source_connection"])
        source_path = [
            str(connection)
            for connection in descriptor["root_to_source_connection_path"]
        ]
        subname = str(descriptor["subname"])
        component_record = components[component]
        paths_by_connection = {
            str(connection["name"]): [
                str(item) for item in connection["root_to_connection_path"]
            ]
            for connection in component_record["connections"]
        }
        matching_selectors = sorted(
            (
                selector
                for selector in component_record["authored_connection_animations"]
                if str(selector["name"]) == subname
            ),
            key=lambda selector: str(selector["connection"]),
        )
        relationships = []
        for selector in matching_selectors:
            selector_connection = str(selector["connection"])
            selector_path = paths_by_connection[selector_connection]
            if selector_connection == source_connection:
                relation = "same_source_connection"
                distance = 0
            elif (
                len(selector_path) < len(source_path)
                and source_path[: len(selector_path)] == selector_path
            ):
                relation = "strict_ancestor_connection"
                distance = len(source_path) - len(selector_path)
            elif (
                len(source_path) < len(selector_path)
                and selector_path[: len(source_path)] == source_path
            ):
                relation = "descendant_connection"
                distance = len(selector_path) - len(source_path)
            else:
                relation = "unrelated_connection"
                distance = None
            relationship_counts[relation] += 1
            relationships.append(
                {
                    "selector_connection": selector_connection,
                    "root_to_selector_connection_path": selector_path,
                    "relation": relation,
                    "distance": distance,
                }
            )
        if not relationships:
            relationship_counts["none"] += 1

        ancestor_distances = sorted(
            int(relationship["distance"])
            for relationship in relationships
            if relationship["relation"] == "strict_ancestor_connection"
        )
        same_connection = any(
            relationship["relation"] == "same_source_connection"
            for relationship in relationships
        )
        no_selector_on_ancestry = not same_connection and not ancestor_distances
        if not no_selector_on_ancestry:
            covered_descriptors += 1
        has_keys = any(
            int(descriptor["channel_counts"][field]) > 0
            for field in _ANI_CHANNEL_COUNT_FIELDS
        )
        row_key = (
            subname,
            "has_keys" if has_keys else "zero_keys",
            same_connection,
            ancestor_distances[0] if ancestor_distances else None,
            no_selector_on_ancestry,
            len(ancestor_distances) > 1,
        )
        cross_tab_counts[row_key] += 1
        cross_tab_memberships[row_key] += membership_counts[identity]
        inventory_record = {
            "component": component,
            "descriptor_index": descriptor_index,
            "part": str(descriptor["part"]),
            "literal_subname": subname,
            "source_connection": source_connection,
            "root_to_source_connection_path": source_path,
            "descriptor_has_keys": has_keys,
            "endpoint_membership_count": membership_counts[identity],
            "endpoint_connections": sorted(endpoints_by_descriptor[identity]),
            "same_subname_selector_relationships": relationships,
            "same_connection_selector": same_connection,
            "strict_ancestor_selector_distances": ancestor_distances,
            "nearest_ancestor_same_subname_selector_distance": (
                ancestor_distances[0] if ancestor_distances else None
            ),
            "no_same_subname_selector_on_ancestry": no_selector_on_ancestry,
            "multiple_matching_ancestors": len(ancestor_distances) > 1,
        }
        inventory.append(inventory_record)
        if subname == "turret_active" and not no_selector_on_ancestry:
            ancestry_covered_turret_active_cohort.append(
                (
                    identity,
                    descriptor,
                    {
                        **inventory_record,
                        "equipment_macros": list(
                            component_record.get("macros", [])
                        ),
                        "muzzle_endpoint_memberships": sorted(
                            endpoint_memberships_by_descriptor[identity],
                            key=lambda item: str(item["connection"]),
                        ),
                    },
                    membership_counts[identity],
                )
            )

    full_cross_tab = [
        {
            "literal_subname": key[0],
            "descriptor_key_class": key[1],
            "same_connection_selector": key[2],
            "nearest_ancestor_same_subname_selector_distance": key[3],
            "no_same_subname_selector_on_ancestry": key[4],
            "multiple_matching_ancestors": key[5],
            "unique_descriptor_count": cross_tab_counts[key],
            "endpoint_membership_count": cross_tab_memberships[key],
        }
        for key in sorted(
            cross_tab_counts,
            key=lambda item: (
                str(item[0]), str(item[1]), bool(item[2]),
                -1 if item[3] is None else int(item[3]),
                bool(item[4]), bool(item[5]),
            ),
        )
    ]
    unique_descriptor_count = len(inventory)
    if unique_descriptor_count == 0:
        assessment = "ambiguous"
    elif covered_descriptors == unique_descriptor_count:
        assessment = "structurally complete across candidate conventional paths"
    else:
        assessment = "structurally incomplete"
    focused_descriptors = [
        descriptor
        for descriptor in inventory
        if descriptor["literal_subname"] == "turret_active"
    ]
    return {
        "evidence_classification": "inference",
        "relationship_basis_evidence_classification": "shipped-source",
        "literal_name_match_rule": "exact case-sensitive equality",
        "descriptor_identity": ["component", "descriptor_index"],
        "semantic_claim": "none",
        "descriptor_memberships": sum(membership_counts.values()),
        "unique_descriptors": unique_descriptor_count,
        "descriptors": inventory,
        "relationship_occurrence_counts": {
            relation: relationship_counts[relation]
            for relation in (
                "same_source_connection",
                "strict_ancestor_connection",
                "descendant_connection",
                "unrelated_connection",
                "none",
            )
        },
        "full_cross_tab": full_cross_tab,
        "focused_literal_turret_active": {
            "literal_subname": "turret_active",
            "unique_descriptor_count": len(focused_descriptors),
            "endpoint_membership_count": sum(
                int(descriptor["endpoint_membership_count"])
                for descriptor in focused_descriptors
            ),
            "descriptors": focused_descriptors,
            "full_cross_tab": [
                row for row in full_cross_tab
                if row["literal_subname"] == "turret_active"
            ],
        },
        "ancestry_covered_literal_turret_active_candidate_channel_inventory": (
            _build_ancestry_covered_turret_active_candidate_channel_inventory(
                ancestry_covered_turret_active_cohort,
                expected_turret_active_changing_case_baseline,
            )
        ),
        "hypothesis_assessment": {
            "evidence_classification": "inference",
            "assessment": assessment,
            "descriptors_with_same_connection_or_ancestor_selector": (
                covered_descriptors
            ),
            "descriptors_without_same_connection_or_ancestor_selector": (
                unique_descriptor_count - covered_descriptors
            ),
            "boundary": (
                "structural same-subname coverage does not establish that an"
                " engine selector or trigger propagates to descendant"
                " connections"
            ),
        },
    }


_PARANID_L_BEAM_ACCEPTED_PRODUCTION_FORMULA = {
    "production_sha": "0d8780da74e49838d3f14408fe5c8c27ee151871",
    "production_source_file": "md/x4_gunnery_control.xml",
    "production_source_line_range": {"start": 323, "end_inclusive": 335},
    "downstream_vector": [
        -0.36177411330546533,
        0.4829345992763463,
        55.87084740617998,
    ],
    "yaw_origin_expression_terms": [
        [1.877547e-6, 2.018104, -1.043081e-5],
        [0.0, 6.145042419433594, 0.0],
    ],
    "pivot_vector": [-1.730653e-6, 2.926126, -16.11956],
    "runtime_inputs": ["target_bearing_yaw", "target_bearing_pitch"],
    "operation_sequence": [
        "weapon_local_look_at_target_useaimtarget_true",
        "md_create_rotation_pitch_equals_runtime_bearing_pitch",
        "md_transform_downstream_vector_by_pitch_rotation",
        "add_pivot_vector",
        "md_create_rotation_yaw_equals_runtime_bearing_yaw",
        "md_transform_pivoted_vector_by_yaw_rotation",
        "add_yaw_origin",
    ],
    "untraced_constants": [],
}

_PARANID_L_BEAM_TRACE_SPEC = {
    "endpoint_connection": "con_laser_02",
    "root_connection": "Connection01",
    "pivot_connection": "Connection04",
    "barrel_connection": "Connection05",
    "laser_connection": "con_laser_02",
    "rotator_active_descriptor": {
        "descriptor_index": 12,
        "part": "part_rotator",
        "subname": "turret_active",
        "candidate_channel_index": 0,
        "triple_slot_indexes": [0, 1, 2],
    },
    "barrel_active_descriptor": {
        "descriptor_index": 22,
        "part": "anim_barrel",
        "subname": "turret_active",
        "candidate_channel_index": 0,
        "triple_slot_indexes": [0, 1, 2],
    },
}


def _anchor_descriptor_inventory(
    endpoint: dict[str, object],
) -> list[dict[str, object]]:
    selected_identities = {
        int(descriptor["descriptor_index"])
        for descriptor in endpoint["selected_ani_descriptor_memberships"]
    }
    inventory = []
    for descriptor in sorted(
        endpoint["ani_descriptor_memberships"],
        key=lambda item: int(item["descriptor_index"]),
    ):
        channels = []
        for channel_index, field in enumerate(_ANI_CHANNEL_COUNT_FIELDS):
            records = _candidate_channel_records(descriptor, field)
            channels.append(
                {
                    "candidate_channel_id": f"candidate_channel_{channel_index}",
                    "candidate_channel_count_field_index": channel_index,
                    "record_count": len(records),
                    "records": [
                        {
                            "record_index": int(record["record_index"]),
                            "raw_bits": [
                                str(raw_bits) for raw_bits in record["raw_bits"]
                            ],
                            "candidate_values": list(record["raw_values"]),
                            "candidate_value_decode_evidence_classification": (
                                "third-party-technique"
                            ),
                        }
                        for record in records
                    ],
                }
            )
        inventory.append(
            {
                "component": endpoint["component"],
                "descriptor_index": int(descriptor["descriptor_index"]),
                "part": str(descriptor["part"]),
                "subname": str(descriptor["subname"]),
                "source_connection": str(descriptor["source_connection"]),
                "selector_selected": (
                    int(descriptor["descriptor_index"]) in selected_identities
                ),
                "candidate_channel_counts": [
                    int(descriptor["channel_counts"][field])
                    for field in _ANI_CHANNEL_COUNT_FIELDS
                ],
                "candidate_channels": channels,
                "raw_bits_evidence_classification": "shipped-source",
                "candidate_channel_layout_evidence_classification": (
                    "third-party-technique"
                ),
            }
        )
    return inventory


def _anchor_connection_vector(
    source_trace_bundle: dict[str, object],
    connection_name: str,
    field: str,
) -> tuple[list[float], list[dict[str, object]]] | None:
    matches = [
        connection
        for connection in source_trace_bundle["connections"]
        if connection["name"] == connection_name
    ]
    if len(matches) != 1:
        return None
    attributes = matches[0]["authored_offset"].get(field)
    names = ("x", "y", "z") if field == "position" else ("qx", "qy", "qz", "qw")
    if attributes is None or any(
        attributes.get(name, {}).get("candidate_numeric_value") is None
        for name in names
    ):
        return None
    values = [
        float(attributes[name]["candidate_numeric_value"]) for name in names
    ]
    provenance = [
        {
            "component": source_trace_bundle["component"],
            "connection": connection_name,
            "field": f"{field}.{name}",
            "raw_text": attributes[name]["raw_text"],
            "value": values[index],
            "evidence_classification": "shipped-source",
        }
        for index, name in enumerate(names)
    ]
    return values, provenance


def _anchor_ani_vector(
    source_trace_bundle: dict[str, object],
    selector: dict[str, object],
) -> tuple[list[float], list[dict[str, object]]] | None:
    descriptors = [
        descriptor
        for descriptor in source_trace_bundle["endpoint_descriptor_inventory"]
        if int(descriptor["descriptor_index"])
        == int(selector["descriptor_index"])
        and descriptor["part"] == selector["part"]
        and descriptor["subname"] == selector["subname"]
    ]
    if len(descriptors) != 1:
        return None
    channel_index = int(selector["candidate_channel_index"])
    if not 0 <= channel_index < len(_ANI_CHANNEL_COUNT_FIELDS):
        return None
    channel = descriptors[0]["candidate_channels"][channel_index]
    records = channel["records"]
    slot_indexes = [int(index) for index in selector["triple_slot_indexes"]]
    if (
        not records
        or len(slot_indexes) != 3
        or any(not 0 <= index < len(_ANI_KEY_RECORD_CANDIDATE_SLOTS) for index in slot_indexes)
    ):
        return None
    vectors = [
        [float(record["candidate_values"][index]) for index in slot_indexes]
        for record in records
    ]
    if any(vector != vectors[0] for vector in vectors[1:]):
        return None
    provenance = []
    for axis_index, slot_index in enumerate(slot_indexes):
        provenance.append(
            {
                "component": source_trace_bundle["component"],
                "descriptor_index": int(descriptors[0]["descriptor_index"]),
                "part": descriptors[0]["part"],
                "subname": descriptors[0]["subname"],
                "candidate_channel": f"candidate_channel_{channel_index}",
                "slot": str(
                    _ANI_KEY_RECORD_CANDIDATE_SLOTS[slot_index]["slot_id"]
                ),
                "record_indexes": [
                    int(record["record_index"]) for record in records
                ],
                "raw_bits": [
                    str(record["raw_bits"][slot_index]) for record in records
                ],
                "value": vectors[0][axis_index],
                "raw_bits_evidence_classification": "shipped-source",
                "candidate_channel_layout_evidence_classification": (
                    "third-party-technique"
                ),
                "candidate_value_decode_evidence_classification": (
                    "third-party-technique"
                ),
            }
        )
    return vectors[0], provenance


def _anchor_quaternion_multiply(
    left: list[float], right: list[float]
) -> list[float]:
    x, y, z, w = left
    other_x, other_y, other_z, other_w = right
    return [
        w * other_x + x * other_w + y * other_z - z * other_y,
        w * other_y - x * other_z + y * other_w + z * other_x,
        w * other_z + x * other_y - y * other_x + z * other_w,
        w * other_w - x * other_x - y * other_y - z * other_z,
    ]


def _anchor_quaternion_apply(
    quaternion: list[float], vector: list[float]
) -> list[float]:
    x, y, z, w = quaternion
    vector_x, vector_y, vector_z = vector
    tx = 2 * (y * vector_z - z * vector_y)
    ty = 2 * (z * vector_x - x * vector_z)
    tz = 2 * (x * vector_y - y * vector_x)
    return [
        vector_x + w * tx + y * tz - z * ty,
        vector_y + w * ty + z * tx - x * tz,
        vector_z + w * tz + x * ty - y * tx,
    ]


def _anchor_add(*vectors: list[float]) -> list[float]:
    return [sum(vector[index] for vector in vectors) for index in range(3)]


def _anchor_vectors_equal(left: object, right: object) -> bool:
    if not isinstance(left, list) or not isinstance(right, list):
        return False
    return len(left) == len(right) and all(
        math.isclose(float(a), float(b), rel_tol=0.0, abs_tol=1e-12)
        for a, b in zip(left, right)
    )


def _evaluate_paranid_l_beam_trace(
    source_trace_bundle: dict[str, object],
    *,
    production_formula: dict[str, object],
    trace_spec: dict[str, object],
) -> dict[str, object]:
    failures = []
    trace_source = source_trace_bundle.get(
        "source_trace_bundle", source_trace_bundle
    )

    def fail(code: str, finding: str) -> None:
        failures.append({"code": code, "finding": finding})

    connection_traces = {}
    for trace_id, connection_key, field in (
        ("component_root", "root_connection", "position"),
        ("pivot", "pivot_connection", "position"),
        ("pivot_quaternion", "pivot_connection", "quaternion"),
        ("barrel_connection", "barrel_connection", "position"),
        ("barrel_quaternion", "barrel_connection", "quaternion"),
        ("endpoint", "laser_connection", "position"),
    ):
        trace = _anchor_connection_vector(
            trace_source, str(trace_spec[connection_key]), field
        )
        connection_traces[trace_id] = trace
        if trace is None:
            fail(
                "connection_trace_unresolved",
                f"{trace_id} did not resolve to one complete authored {field}",
            )

    ani_traces = {}
    for trace_id, selector_key in (
        ("rotator_active", "rotator_active_descriptor"),
        ("barrel_active", "barrel_active_descriptor"),
    ):
        trace = _anchor_ani_vector(
            trace_source, trace_spec[selector_key]
        )
        ani_traces[trace_id] = trace
        if trace is None:
            fail(
                "ani_trace_unresolved",
                f"{trace_id} did not resolve to one exact constant raw triple",
            )

    formula_constant_provenance = []
    endpoint_resolution = None
    source_constant_provenance = [
        row
        for trace in list(connection_traces.values()) + list(ani_traces.values())
        if trace is not None
        for row in trace[1]
    ]
    derived = None
    if all(trace is not None for trace in connection_traces.values()) and all(
        trace is not None for trace in ani_traces.values()
    ):
        component_root = connection_traces["component_root"][0]
        pivot = connection_traces["pivot"][0]
        pivot_quaternion = connection_traces["pivot_quaternion"][0]
        barrel_connection = connection_traces["barrel_connection"][0]
        barrel_quaternion = connection_traces["barrel_quaternion"][0]
        endpoint = connection_traces["endpoint"][0]
        rotator_active = ani_traces["rotator_active"][0]
        barrel_active = ani_traces["barrel_active"][0]
        combined_quaternion = _anchor_quaternion_multiply(
            pivot_quaternion, barrel_quaternion
        )
        downstream = _anchor_add(
            _anchor_quaternion_apply(
                pivot_quaternion,
                _anchor_add(barrel_connection, barrel_active),
            ),
            _anchor_quaternion_apply(combined_quaternion, endpoint),
        )
        yaw_origin_terms = [component_root, rotator_active]
        yaw_origin = _anchor_add(*yaw_origin_terms)
        endpoint_candidates = []
        for candidate_connection in trace_source.get(
            "firing_endpoint_connections", []
        ):
            candidate_trace = _anchor_connection_vector(
                trace_source, str(candidate_connection), "position"
            )
            if candidate_trace is None:
                continue
            candidate_downstream = _anchor_add(
                _anchor_quaternion_apply(
                    pivot_quaternion,
                    _anchor_add(barrel_connection, barrel_active),
                ),
                _anchor_quaternion_apply(
                    combined_quaternion, candidate_trace[0]
                ),
            )
            endpoint_candidates.append(
                {
                    "connection": candidate_connection,
                    "derived_downstream_vector": candidate_downstream,
                    "matches_production_downstream": _anchor_vectors_equal(
                        candidate_downstream,
                        production_formula.get("downstream_vector"),
                    ),
                }
            )
        matching_endpoint_connections = [
            candidate["connection"]
            for candidate in endpoint_candidates
            if candidate["matches_production_downstream"]
        ]
        selected_endpoint_connection = str(trace_spec["endpoint_connection"])
        endpoint_resolution = {
            "candidate_endpoint_connections": endpoint_candidates,
            "production_matching_endpoint_connections": (
                matching_endpoint_connections
            ),
            "selected_endpoint_connection": selected_endpoint_connection,
            "exact_unique_match": matching_endpoint_connections
            == [selected_endpoint_connection],
            "selection_basis": (
                "unique current authored endpoint offset that reproduces the"
                " accepted production downstream vector"
            ),
            "evidence_classification": "inference",
        }
        if not endpoint_resolution["exact_unique_match"]:
            fail(
                "endpoint_resolution_mismatch",
                "accepted endpoint is not the unique current numeric source match",
            )
        derived = {
            "downstream_vector": downstream,
            "downstream_arithmetic": (
                "apply(Connection04.quaternion, Connection05.position +"
                " anim_barrel/turret_active candidate_channel_0 slots"
                " 000/004/008) + apply(Connection04.quaternion *"
                " Connection05.quaternion, con_laser_02.position)"
            ),
            "yaw_origin_expression_terms": yaw_origin_terms,
            "yaw_origin": yaw_origin,
            "yaw_origin_arithmetic": (
                "Connection01.position + part_rotator/turret_active"
                " candidate_channel_0 slots 000/004/008"
            ),
            "pivot_vector": pivot,
            "pivot_arithmetic": "Connection04.position",
            "evidence_classification": "inference",
        }
        dependency_ids = {
            "downstream_vector": [
                "pivot_quaternion",
                "barrel_connection",
                "barrel_active",
                "barrel_quaternion",
                "endpoint",
            ],
            "yaw_origin": ["component_root", "rotator_active"],
            "pivot_vector": ["pivot"],
        }
        expected_vectors = {
            "downstream_vector": production_formula.get("downstream_vector"),
            "yaw_origin": _anchor_add(
                *production_formula.get("yaw_origin_expression_terms", [])
            )
            if production_formula.get("yaw_origin_expression_terms")
            else None,
            "pivot_vector": production_formula.get("pivot_vector"),
        }
        for formula_id, value in (
            ("downstream_vector", downstream),
            ("yaw_origin", yaw_origin),
            ("pivot_vector", pivot),
        ):
            expected = expected_vectors[formula_id]
            matches = _anchor_vectors_equal(value, expected)
            if not matches:
                fail(
                    "formula_numeric_mismatch",
                    f"{formula_id} differs from the accepted production constant",
                )
            for axis_index, axis in enumerate(("x", "y", "z")):
                formula_constant_provenance.append(
                    {
                        "formula_constant": f"{formula_id}.{axis}",
                        "production_value": (
                            float(expected[axis_index])
                            if isinstance(expected, list)
                            and len(expected) > axis_index
                            else None
                        ),
                        "newly_derived_value": value[axis_index],
                        "source_kind": (
                            "component_connection_offset_field"
                            if formula_id == "pivot_vector"
                            else "explicit_arithmetic_combination"
                        ),
                        "dependencies": dependency_ids[formula_id],
                        "trace_status": "TRACED" if matches else "MISMATCH",
                        "evidence_classification": "inference",
                    }
                )
        if not all(
            _anchor_vectors_equal(actual, expected)
            for actual, expected in zip(
                yaw_origin_terms,
                production_formula.get("yaw_origin_expression_terms", []),
            )
        ) or len(yaw_origin_terms) != len(
            production_formula.get("yaw_origin_expression_terms", [])
        ):
            fail(
                "formula_structure_mismatch",
                "yaw-origin arithmetic terms differ from production",
            )
    else:
        formula_constant_provenance.append(
            {
                "formula_constant": "construction",
                "production_value": None,
                "newly_derived_value": None,
                "source_kind": "UNTRACED",
                "dependencies": [],
                "trace_status": "UNTRACED",
                "evidence_classification": "inference",
            }
        )

    expected_operations = list(
        _PARANID_L_BEAM_ACCEPTED_PRODUCTION_FORMULA["operation_sequence"]
    )
    expected_runtime_inputs = list(
        _PARANID_L_BEAM_ACCEPTED_PRODUCTION_FORMULA["runtime_inputs"]
    )
    if production_formula.get("operation_sequence") != expected_operations:
        fail(
            "formula_structure_mismatch",
            "production operation sequence differs from the accepted construction",
        )
    if production_formula.get("runtime_inputs") != expected_runtime_inputs:
        fail(
            "formula_structure_mismatch",
            "runtime input identities differ from the accepted construction",
        )
    for index, value in enumerate(production_formula.get("untraced_constants", [])):
        fail(
            "untraced_production_constant",
            f"production constant {index} has no authored-source trace",
        )
        formula_constant_provenance.append(
            {
                "formula_constant": f"untraced_constants[{index}]",
                "production_value": value,
                "newly_derived_value": None,
                "source_kind": "UNTRACED",
                "dependencies": [],
                "trace_status": "UNTRACED",
                "evidence_classification": "inference",
            }
        )

    corroboration_matrix = [
        {
            "candidate_semantic": "complete_asset_specific_construction_and_result",
            "assessment": "independently corroborated by aggregate live result",
            "evidence_classification": "live-tested",
        },
        {
            "candidate_semantic": "exact_con_laser_02_endpoint_input",
            "assessment": "independently corroborated by aggregate live result",
            "evidence_classification": "inference",
        },
        {
            "candidate_semantic": "authored_connection_position_and_quaternion_arithmetic_inputs",
            "assessment": "independently corroborated by aggregate live result",
            "evidence_classification": "inference",
        },
        {
            "candidate_semantic": "literal_turret_active_candidate_channel_0_slots_000_004_008_as_used_vectors",
            "assessment": "independently corroborated by aggregate live result",
            "evidence_classification": "inference",
        },
        {
            "candidate_semantic": "x4converter_candidate_channel_0_ownership_name",
            "assessment": "consistent only",
            "evidence_classification": "third-party-technique",
        },
        {
            "candidate_semantic": "asset_specific_operation_sequence",
            "assessment": "independently corroborated by aggregate live result",
            "evidence_classification": "inference",
        },
        {
            "candidate_semantic": "candidate_channels_1_2_3_4",
            "assessment": "not exercised",
            "evidence_classification": "inference",
        },
        {
            "candidate_semantic": "candidate_channel_0_slots_012_through_124",
            "assessment": "not exercised",
            "evidence_classification": "inference",
        },
    ]
    failure_codes = sorted({failure["code"] for failure in failures})
    result = {
        "status": "pass" if not failures else "fail",
        "failures": failures,
        "failure_codes": failure_codes,
        "production_formula": production_formula,
        "runtime_inputs": {
            "identities": production_formula.get("runtime_inputs", []),
            "source_constant_status": "not_source_constants",
        },
        "source_constant_provenance": source_constant_provenance,
        "formula_constant_provenance": formula_constant_provenance,
        "newly_traced_construction": derived,
        "endpoint_resolution": endpoint_resolution,
        "comparison": {
            "structural_match": not any(
                code == "formula_structure_mismatch" for code in failure_codes
            ),
            "numeric_match": not any(
                code == "formula_numeric_mismatch" for code in failure_codes
            ),
            "all_constants_traced": not any(
                code in (
                    "connection_trace_unresolved",
                    "ani_trace_unresolved",
                    "untraced_production_constant",
                )
                for code in failure_codes
            ),
        },
        "corroboration_matrix": corroboration_matrix,
    }
    result.update(source_trace_bundle)
    return result


def _build_paranid_l_beam_live_anchor(
    equipment_macros: list[dict[str, object]],
    component_to_macros: list[dict[str, object]],
    firing_endpoints: list[dict[str, object]],
    *,
    production_formula: dict[str, object],
    trace_spec: dict[str, object],
) -> dict[str, object]:
    macro_name = "turret_par_l_beam_01_mk1_macro"
    macro_matches = [
        record for record in equipment_macros if record["name"] == macro_name
    ]
    if len(macro_matches) != 1:
        return {
            "status": "fail",
            "failure_codes": ["macro_identity_unresolved"],
            "failures": [
                {
                    "code": "macro_identity_unresolved",
                    "finding": "exact accepted macro identity did not resolve once",
                }
            ],
        }
    component_name = str(macro_matches[0]["component"])
    component_matches = [
        record
        for record in component_to_macros
        if record["component"] == component_name
    ]
    endpoint_matches = [
        endpoint
        for endpoint in firing_endpoints
        if endpoint["component"] == component_name
        and endpoint["connection"] == trace_spec["endpoint_connection"]
    ]
    if len(component_matches) != 1 or len(endpoint_matches) != 1:
        return {
            "status": "fail",
            "failure_codes": ["source_identity_unresolved"],
            "failures": [
                {
                    "code": "source_identity_unresolved",
                    "finding": "macro-referenced component or exact endpoint did not resolve once",
                }
            ],
        }
    component = component_matches[0]
    endpoint = endpoint_matches[0]
    inventory = _anchor_descriptor_inventory(endpoint)
    selected_inventory = [
        descriptor for descriptor in inventory if descriptor["selector_selected"]
    ]
    active_inventory = [
        descriptor
        for descriptor in inventory
        if descriptor["subname"] == "turret_active"
    ]
    source_trace_bundle = {
        "source_trace_bundle": {
            "component": component_name,
            "firing_endpoint_connections": [
                candidate["connection"]
                for candidate in firing_endpoints
                if candidate["component"] == component_name
            ],
            "connections": [
                {
                    **{
                        key: value
                        for key, value in connection.items()
                        if key != "_authored_offset"
                    },
                    "authored_offset": connection["_authored_offset"],
                }
                for connection in component["connections"]
            ],
            "endpoint_descriptor_inventory": inventory,
        },
        "identity_chain": {
            "macro": macro_name,
            "macro_source_set": macro_matches[0]["source_set"],
            "macro_source_file": macro_matches[0]["source_file"],
            "component": component_name,
            "component_source_set": component["source_set"],
            "component_source_file": component["source_file"],
            "geometry_source": component["geometry_source"],
            "ani_source_set": component["ani_source_set"],
            "ani_resource": component["ani_resource"],
            "endpoint_connection": endpoint["connection"],
            "root_to_endpoint_connection_path": endpoint[
                "root_to_endpoint_connection_path"
            ],
            "all_component_endpoint_paths": [
                {
                    "endpoint_connection": candidate["connection"],
                    "root_to_endpoint_connection_path": candidate[
                        "root_to_endpoint_connection_path"
                    ],
                }
                for candidate in firing_endpoints
                if candidate["component"] == component_name
            ],
            "resolution_rule": "exact explicit references and identities only",
            "evidence_classification": "shipped-source",
        },
        "endpoint_descriptor_inventory": inventory,
        "selector_selected_descriptor_inventory": selected_inventory,
        "literal_turret_active_descriptors": active_inventory,
        "literal_turret_active_candidate_channel_contributions": {
            "contributing": ["candidate_channel_0"],
            "not_contributing": [
                "candidate_channel_1",
                "candidate_channel_2",
                "candidate_channel_3",
                "candidate_channel_4",
            ],
        },
        "evidence_boundary": {
            "authored_xml_and_ani_bits": "shipped-source",
            "x4converter_field_and_channel_names": "third-party-technique",
            "source_to_formula_provenance_and_arithmetic": "inference",
            "complete_already_tested_construction_and_result": "live-tested",
            "individual_ani_field_live_test_status": "not_live-tested_individually",
        },
        "accepted_live_result": {
            "issue": 69,
            "checkpoint_comment": 5466013484,
            "x4_version": "9.00",
            "build": "611726",
            "accepted_test_lab_sha": (
                "fb8bb7214906f93989b328f32bd7be9187620d25"
            ),
            "settled_muzzle_error_metres": "approximately 0.303",
            "scope": macro_name,
            "evidence_classification": "live-tested",
        },
    }
    return _evaluate_paranid_l_beam_trace(
        source_trace_bundle,
        production_formula=production_formula,
        trace_spec=trace_spec,
    )


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


_X4CONVERTER_COMMIT = "0be4b494089ba7719d4c5d351e63160ef3843ef5"
_X4CONVERTER_KEYFRAME_HEADER = (
    "X4ConverterTools/include/X4ConverterTools/ani/Keyframe.h"
)
_X4CONVERTER_KEYFRAME_SOURCE = "X4ConverterTools/src/ani/Keyframe.cpp"
_X4CONVERTER_ANIMDESC_SOURCE = "X4ConverterTools/src/ani/AnimDesc.cpp"


def _x4converter_site(
    path: str,
    function: str,
    line_start: int,
    line_end: int,
    expression: str,
) -> dict[str, object]:
    return {
        "path": path,
        "function": function,
        "line_range_at_pinned_commit": [line_start, line_end],
        "expression": expression,
    }


def _x4converter_descriptor_offset_148_lead() -> dict[str, object]:
    return {
        "evidence_classification": "third-party-technique",
        "source_revision": {
            "repository": "https://github.com/Cgettys/X4Converter.git",
            "commit": _X4CONVERTER_COMMIT,
            "inspection": "direct pinned checkout",
        },
        "x4converter_member": "Duration",
        "member_declaration_site": _x4converter_site(
            "X4ConverterTools/include/X4ConverterTools/ani/AnimDesc.h",
            "ani::AnimDesc member declaration",
            43,
            43,
            "float Duration = 0",
        ),
        "read_site": _x4converter_site(
            _X4CONVERTER_ANIMDESC_SOURCE,
            "AnimDesc::AnimDesc(StreamReaderLE &reader)",
            21,
            26,
            "NumPostScaleKeys is read before Duration",
        ),
        "write_site": _x4converter_site(
            _X4CONVERTER_ANIMDESC_SOURCE,
            "AnimDesc::WriteToGameFiles",
            79,
            84,
            "NumPostScaleKeys is written before Duration",
        ),
        "validation_report_site": _x4converter_site(
            _X4CONVERTER_ANIMDESC_SOURCE,
            "AnimDesc::validate",
            205,
            207,
            "Duration is included in human-readable validation output",
        ),
        "other_actual_use_sites": [],
        "search_scope": (
            "pinned X4Converter commit C/C++ headers and sources; exact member"
            " search found declaration, read, write, and validation report only"
        ),
        "engine_requiredness": "unresolved",
        "absence_interpretation": (
            "X4Converter use or non-use does not establish X4 engine requiredness"
        ),
        "semantic_promotion": "not_permitted_by_this_inventory",
    }


def _x4converter_candidate_key_record_semantic_lead() -> dict[str, object]:
    field_specs = (
        ("ValueX", "candidate_vector", 45, 27),
        ("ValueY", "candidate_vector", 45, 27),
        ("ValueZ", "candidate_vector", 45, 27),
        ("InterpolationX", "per_axis_mode", 46, 28),
        ("InterpolationY", "per_axis_mode", 47, 28),
        ("InterpolationZ", "per_axis_mode", 48, 28),
        ("Time", "record_order_scalar", 49, 29),
        ("CPX1x", "control_parameters", 53, 31),
        ("CPX1y", "control_parameters", 53, 31),
        ("CPX2x", "control_parameters", 54, 32),
        ("CPX2y", "control_parameters", 54, 32),
        ("CPY1x", "control_parameters", 55, 33),
        ("CPY1y", "control_parameters", 55, 33),
        ("CPY2x", "control_parameters", 56, 34),
        ("CPY2y", "control_parameters", 56, 34),
        ("CPZ1x", "control_parameters", 57, 35),
        ("CPZ1y", "control_parameters", 57, 35),
        ("CPZ2x", "control_parameters", 58, 36),
        ("CPZ2y", "control_parameters", 58, 36),
        ("Tens", "curve_parameters", 60, 38),
        ("Cont", "curve_parameters", 61, 39),
        ("Bias", "curve_parameters", 62, 40),
        ("EaseIn", "curve_parameters", 63, 41),
        ("EaseOut", "curve_parameters", 64, 42),
        ("Deriv", "flags", 65, 43),
        ("DerivInX", "derived_vectors", 66, 44),
        ("DerivInY", "derived_vectors", 66, 44),
        ("DerivInZ", "derived_vectors", 66, 44),
        ("DerivOutX", "derived_vectors", 67, 45),
        ("DerivOutY", "derived_vectors", 67, 45),
        ("DerivOutZ", "derived_vectors", 67, 45),
        ("AngleKey", "flags", 68, 46),
    )
    read_expressions = {
        27: "reader >> ValueX >> ValueY >> ValueZ",
        28: "reader >> InterpolationX >> InterpolationY >> InterpolationZ",
        29: "reader >> Time",
        31: "reader >> CPX1x >> CPX1y",
        32: "reader >> CPX2x >> CPX2y",
        33: "reader >> CPY1x >> CPY1y",
        34: "reader >> CPY2x >> CPY2y",
        35: "reader >> CPZ1x >> CPZ1y",
        36: "reader >> CPZ2x >> CPZ2y",
        38: "reader >> Tens",
        39: "reader >> Cont",
        40: "reader >> Bias",
        41: "reader >> EaseIn",
        42: "reader >> EaseOut",
        43: "reader >> Deriv",
        44: "reader >> DerivInX >> DerivInY >> DerivInZ",
        45: "reader >> DerivOutX >> DerivOutY >> DerivOutZ",
        46: "reader >> AngleKey",
    }

    vector_uses = {
        "ValueX": (184, 185, 'axis == "X" -> ValueX'),
        "ValueY": (186, 187, 'axis == "Y" -> ValueY'),
        "ValueZ": (188, 189, 'axis == "Z" -> ValueZ'),
    }
    mode_uses = {
        "InterpolationX": (197, 198, 'axis == "X" -> InterpolationX'),
        "InterpolationY": (199, 200, 'axis == "Y" -> InterpolationY'),
        "InterpolationZ": (201, 202, 'axis == "Z" -> InterpolationZ'),
    }
    control_uses = {
        "CPX1x": (244, 245, "CPX1x, CPX1y"),
        "CPX1y": (244, 245, "CPX1x, CPX1y"),
        "CPX2x": (254, 255, "CPX2x, CPX2y"),
        "CPX2y": (254, 255, "CPX2x, CPX2y"),
        "CPY1x": (246, 247, "CPY1x, CPY1y"),
        "CPY1y": (246, 247, "CPY1x, CPY1y"),
        "CPY2x": (256, 257, "CPY2x, CPY2y"),
        "CPY2y": (256, 257, "CPY2x, CPY2y"),
        "CPZ1x": (248, 249, "CPZ1x, CPZ1y"),
        "CPZ1y": (248, 249, "CPZ1x, CPZ1y"),
        "CPZ2x": (258, 259, "CPZ2x, CPZ2y"),
        "CPZ2y": (258, 259, "CPZ2x, CPZ2y"),
    }
    curve_validation = {
        "Tens": (126, 129, "Tens != 0 -> unsupported"),
        "Cont": (131, 134, "Cont != 0 -> unsupported"),
        "Bias": (136, 139, "Bias != 0 -> unsupported"),
        "EaseIn": (141, 144, "EaseIn != 0 -> unsupported"),
        "EaseOut": (146, 149, "EaseOut != 0 -> unsupported"),
    }

    field_map = []
    for slot, (member, group, declaration_line, read_line) in zip(
        _ANI_KEY_RECORD_CANDIDATE_SLOTS, field_specs
    ):
        use_sites: list[dict[str, object]] = []
        if member in vector_uses:
            start, end, expression = vector_uses[member]
            use_sites.extend(
                (
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::getValueByAxis",
                        start,
                        end,
                        expression,
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::WriteChannel",
                        220,
                        221,
                        "getValueByAxis(axis) -> frame value attribute",
                    ),
                )
            )
        elif member in mode_uses:
            start, end, expression = mode_uses[member]
            use_sites.extend(
                (
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::getInterpByAxis",
                        start,
                        end,
                        expression,
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::validate",
                        67,
                        81,
                        "checkInterpolationType and getInterpolationTypeName",
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::WriteChannel",
                        210,
                        224,
                        "select, check, name, and emit axis mode",
                    ),
                )
            )
        elif member == "Time":
            use_sites.extend(
                (
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::validate",
                        84,
                        84,
                        "report Time",
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::WriteChannel",
                        216,
                        218,
                        "numeric_cast<int>(30.0 * Time) -> frame id",
                    ),
                )
            )
        elif member in control_uses:
            start, end, expression = control_uses[member]
            use_sites.extend(
                (
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::getControlPoint",
                        start,
                        end,
                        expression,
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::WriteHandle",
                        228,
                        238,
                        "getControlPoint(axis, right) -> handle attributes",
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::validate",
                        104,
                        123,
                        "raw mode 2 checks the corresponding four CP members",
                    ),
                )
            )
        elif member in curve_validation:
            start, end, expression = curve_validation[member]
            use_sites.append(
                _x4converter_site(
                    _X4CONVERTER_KEYFRAME_SOURCE,
                    "Keyframe::validate",
                    start,
                    end,
                    expression,
                )
            )
        elif member == "Deriv":
            use_sites.append(
                _x4converter_site(
                    _X4CONVERTER_KEYFRAME_SOURCE,
                    "Keyframe::validate",
                    98,
                    155,
                    "report Deriv; any nonzero Deriv group member is unsupported",
                )
            )
        elif member.startswith("DerivIn") or member.startswith("DerivOut"):
            use_sites.append(
                _x4converter_site(
                    _X4CONVERTER_KEYFRAME_SOURCE,
                    "Keyframe::validate",
                    100,
                    155,
                    "report vectors; any nonzero Deriv group member is unsupported",
                )
            )
        else:
            use_sites.append(
                _x4converter_site(
                    _X4CONVERTER_KEYFRAME_SOURCE,
                    "Keyframe::validate",
                    103,
                    103,
                    "report AngleKey; no branch or conversion use found",
                )
            )
        field_map.append(
            {
                **slot,
                "x4converter_member": member,
                "x4converter_group": group,
                "x4converter_declaration_site": _x4converter_site(
                    _X4CONVERTER_KEYFRAME_HEADER,
                    "ani::Keyframe member declaration",
                    declaration_line,
                    declaration_line,
                    member,
                ),
                "x4converter_read_site": _x4converter_site(
                    _X4CONVERTER_KEYFRAME_SOURCE,
                    "Keyframe::Keyframe(StreamReaderLE &reader)",
                    read_line,
                    read_line,
                    read_expressions[read_line],
                ),
                "x4converter_use_sites": use_sites,
                "evidence_classification": "third-party-technique",
                "independent_corroboration_required": True,
            }
        )

    group_hypotheses = (
        (
            "candidate_vector",
            "ValueX/ValueY/ValueZ are selected by axis and emitted as a frame value",
        ),
        (
            "per_axis_mode",
            "InterpolationX/Y/Z are selected by axis, checked, named, and emitted",
        ),
        (
            "record_order_scalar",
            "Time is multiplied by 30, integer-cast, and emitted as a frame id",
        ),
        (
            "control_parameters",
            "six axis/side pairs are selected by getControlPoint and emitted by WriteHandle",
        ),
        (
            "curve_parameters",
            "Tens, Cont, Bias, EaseIn, and EaseOut are named but rejected when nonzero",
        ),
        (
            "flags",
            "Deriv is checked as part of an unsupported group; AngleKey is reported only",
        ),
        (
            "derived_vectors",
            "DerivIn and DerivOut triples are reported and rejected when nonzero",
        ),
        (
            "unused_or_reserved",
            "no byte range is declared unused or reserved; AngleKey has no use beyond reporting",
        ),
    )
    record_field_groups = []
    for group_id, hypothesis in group_hypotheses:
        group_fields = [field for field in field_map if field["x4converter_group"] == group_id]
        record_field_groups.append(
            {
                "group_id": group_id,
                "slot_ids": [str(field["slot_id"]) for field in group_fields],
                "x4converter_members": [
                    str(field["x4converter_member"]) for field in group_fields
                ],
                "x4converter_hypothesis": hypothesis,
                "evidence_classification": "third-party-technique",
                "independent_corroboration_required": True,
            }
        )

    common_enum_branches = [
        _x4converter_site(
            _X4CONVERTER_KEYFRAME_SOURCE,
            "Keyframe::checkInterpolationType",
            163,
            170,
            (
                "type == INTERPOLATION_STEP || type == INTERPOLATION_BEZIER"
                " || type == INTERPOLATION_LINEAR"
            ),
        )
    ]
    enum_mapping = []
    for raw_value, identifier, readable_name in (
        (1, "INTERPOLATION_STEP", "STEP"),
        (2, "INTERPOLATION_LINEAR", "LINEAR"),
        (5, "INTERPOLATION_BEZIER", "BEZIER"),
    ):
        branch_sites = list(common_enum_branches)
        if raw_value == 2:
            branch_sites.extend(
                (
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::validate",
                        106,
                        110,
                        "InterpolationX == 2 -> corresponding CP nonzero is invalid",
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::validate",
                        112,
                        116,
                        "InterpolationY == 2 -> corresponding CP nonzero is invalid",
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::validate",
                        118,
                        122,
                        "InterpolationZ == 2 -> corresponding CP nonzero is invalid",
                    ),
                )
            )
        enum_mapping.append(
            {
                "raw_value": raw_value,
                "raw_bits": f"0x{raw_value:08x}",
                "x4converter_identifier": identifier,
                "x4converter_readable_name": readable_name,
                "declaration_site": _x4converter_site(
                    _X4CONVERTER_KEYFRAME_HEADER,
                    "ani::InterpolationType",
                    8,
                    16,
                    identifier,
                ),
                "branch_sites": branch_sites,
                "common_use_sites": [
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::getInterpolationTypeName",
                        173,
                        180,
                        "enumeration value indexes readable-name array",
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::WriteChannel",
                        210,
                        224,
                        "checked mode is emitted by readable name",
                    ),
                ],
                "observed_in_selected_conventional_inventory": True,
                "evidence_classification": "third-party-technique",
                "independent_corroboration_required": True,
            }
        )

    channel_groups = []
    for index, count_member, vector_member, read_lines, output_label in (
        (0, "NumPosKeys", "posKeys", [91, 93], "location"),
        (1, "NumRotKeys", "rotKeys", [94, 96], "rotation_euler"),
        (2, "NumScaleKeys", "scaleKeys", [97, 99], "scale"),
        (3, "NumPreScaleKeys", "preScaleKeys", [100, 102], None),
        (4, "NumPostScaleKeys", "postScaleKeys", [103, 105], None),
    ):
        channel_groups.append(
            {
                "candidate_channel_count_field_index": index,
                "x4converter_count_member": count_member,
                "x4converter_record_vector_member": vector_member,
                "record_read_site": _x4converter_site(
                    _X4CONVERTER_ANIMDESC_SOURCE,
                    "AnimDesc::read_frames",
                    read_lines[0],
                    read_lines[1],
                    f"{count_member} records -> {vector_member}",
                ),
                "intermediate_output_label": output_label,
                "intermediate_output_site": (
                    _x4converter_site(
                        _X4CONVERTER_ANIMDESC_SOURCE,
                        "AnimDesc::WriteIntermediateReprOfChannel",
                        289,
                        298,
                        f'{vector_member} selected for keyType "{output_label}"',
                    )
                    if output_label is not None
                    else None
                ),
                "evidence_classification": "third-party-technique",
                "independent_corroboration_required": True,
            }
        )

    corroboration_rows = (
        (
            "descriptor_channel_group_identity",
            "no_semantic_evidence",
            "raw channel counts and record ranges do not establish the five X4Converter group meanings",
        ),
        (
            "candidate_vector_component_identity",
            "no_semantic_evidence",
            "raw triples establish bits and ordering only",
        ),
        (
            "per_axis_mode_identity",
            "merely_consistent",
            "observed words 1, 2, and 5 match X4Converter enum ordinals but do not establish engine meanings",
        ),
        (
            "mode_specific_behavior",
            "no_semantic_evidence",
            "observed values do not demonstrate the branches or output behavior used by X4Converter",
        ),
        (
            "record_order_scalar_identity",
            "merely_consistent",
            "strictly increasing slot_024 sequences are consistency observations only",
        ),
        (
            "record_order_scalar_unit_and_30_multiplier",
            "no_semantic_evidence",
            "record ordering does not establish a unit or X4Converter's multiplication assumption",
        ),
        (
            "control_parameter_pair_identity_and_side_assignment",
            "merely_consistent",
            "slot_028 through slot_072 patterns do not discriminate X4Converter's pair or side assignments",
        ),
        (
            "curve_parameter_identities",
            "merely_consistent",
            "zero slot_076 through slot_092 values are consistency observations only",
        ),
        (
            "derivative_flag_and_vector_identities",
            "merely_consistent",
            "zero slot_096 through slot_120 values are consistency observations only",
        ),
        (
            "angle_key_flag_identity",
            "merely_consistent",
            "zero slot_124 values are consistency observations only",
        ),
        (
            "zero_tail_member_identities",
            "merely_consistent",
            "zero tail fields do not establish any named member meaning",
        ),
        (
            "intermediate_output_channel_semantics",
            "no_semantic_evidence",
            "X4Converter output labels are not independent evidence of X4 behavior",
        ),
    )
    return {
        "evidence_classification": "third-party-technique",
        "semantic_status": "hypothesis_only",
        "source_revision": {
            "repository": "https://github.com/Cgettys/X4Converter.git",
            "commit": _X4CONVERTER_COMMIT,
            "commit_date": "2019-10-21",
            "inspection": "direct pinned checkout",
        },
        "record_size_bytes": _ANI_KEY_RECORD_SIZE,
        "decision_driving_component_class": "conventional",
        "missileturret_semantic_analysis": "excluded",
        "excluded_evidence": ["archived Issue #69 conclusions"],
        "field_map": field_map,
        "record_field_groups": record_field_groups,
        "candidate_channel_grouping": channel_groups,
        "x4converter_control_parameter_routing": {
            "write_channel_call_site": _x4converter_site(
                _X4CONVERTER_KEYFRAME_SOURCE,
                "Keyframe::WriteChannel",
                222,
                223,
                "WriteHandle(..., false) then WriteHandle(..., true)",
            ),
            "output_node_branch_site": _x4converter_site(
                _X4CONVERTER_KEYFRAME_SOURCE,
                "Keyframe::WriteHandle",
                228,
                238,
                "right true -> handle_left; right false -> handle_right",
            ),
            "member_selection_branch_site": _x4converter_site(
                _X4CONVERTER_KEYFRAME_SOURCE,
                "Keyframe::getControlPoint",
                241,
                263,
                "right false -> CP1 pair; right true -> CP2 pair",
            ),
            "routes": [
                {
                    "right_argument": False,
                    "output_node": "handle_right",
                    "selected_member_suffix": "1",
                },
                {
                    "right_argument": True,
                    "output_node": "handle_left",
                    "selected_member_suffix": "2",
                },
            ],
            "evidence_classification": "third-party-technique",
            "independent_corroboration_required": True,
        },
        "observed_enum_mapping": enum_mapping,
        "independent_corroboration_assessment_scale": [
            "discriminates",
            "merely_consistent",
            "no_semantic_evidence",
        ],
        "independent_corroboration_required": [
            {
                "candidate_semantic": candidate_semantic,
                "current_observation_assessment": assessment,
                "current_observation_boundary": boundary,
                "required": True,
                "evidence_classification": "third-party-technique",
            }
            for candidate_semantic, assessment, boundary in corroboration_rows
        ],
        "discriminated_candidate_semantics": [],
        "semantic_promotion": "not_permitted_by_this_inventory",
    }


def _strip_candidate_raw_key_records(value: object) -> None:
    if isinstance(value, dict):
        value.pop("_candidate_raw_key_records", None)
        value.pop("_authored_offset", None)
        for child in value.values():
            _strip_candidate_raw_key_records(child)
    elif isinstance(value, list):
        for child in value:
            _strip_candidate_raw_key_records(child)


def build_census(
    source_sets: Mapping[str, Path],
    resource_sets: Mapping[str, Path],
    *,
    anchor_production_formula: dict[str, object] | None = None,
    anchor_trace_spec: dict[str, object] | None = None,
    expected_turret_active_changing_case_baseline: (
        tuple[int, int, int] | None
    ) = None,
) -> dict[str, object]:
    """Return a deterministic census or raise CensusError on any unsafe input."""

    roots = _validate_source_sets(source_sets)
    resource_roots = _validate_resource_sets(resource_sets)
    anomalies: list[dict[str, object]] = []
    ani_resources_by_stem, ani_inventory_counts_by_source_set = (
        _build_ani_resource_inventory(resource_roots)
    )
    (
        component_definitions,
        macro_records,
        ware_records,
        identity_collection_anomalies,
    ) = _collect_xml_identities(roots)
    anomalies.extend(identity_collection_anomalies)
    unique_records, macro_identity_anomalies = _resolve_macro_identities(macro_records)
    anomalies.extend(macro_identity_anomalies)

    referenced_components = sorted({record["component"] for record in unique_records})
    for component in referenced_components:
        definitions = component_definitions.get(component, [])
        definition, component_identity_anomalies = _resolve_component_identity(
            component, definitions, unique_records
        )
        anomalies.extend(component_identity_anomalies)
        if definition is not None:
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

            (
                definition["authored_connection_animations"],
                authored_animation_anomalies,
            ) = _validate_authored_animation_selectors(
                definition["authored_connection_animations"],
                component=component,
                source_set=definition["source_set"],
                source_file=definition["source_file"],
            )
            anomalies.extend(authored_animation_anomalies)
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

            match, geometry_identity_anomalies = (
                _resolve_geometry_ani_resource_identity(
                    definition, ani_resources_by_stem, component=component
                )
            )
            anomalies.extend(geometry_identity_anomalies)
            if match is not None:
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
                                "descriptor_offset_148": descriptor[
                                    "descriptor_offset_148"
                                ],
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
    selected_candidate_channel_metadata_by_class = {}
    selected_unique_descriptors_by_class = {}
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
        selected_unique_descriptors_by_class[component_class] = unique_descriptors
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
        selected_candidate_channel_metadata_by_class[component_class] = (
            _inventory_candidate_multi_key_metadata(
                unique_descriptors,
                len(memberships),
                include_patterns=component_class == "turret",
            )
        )

    selected_descriptor_offset_148_by_class = {}
    for component_class in sorted(_INCLUDED_CLASSES):
        unique_descriptors = selected_unique_descriptors_by_class[component_class]
        memberships = [
            descriptor
            for endpoint, descriptor in selected_endpoint_path_descriptor_memberships
            if endpoint["component_class"] == component_class
        ]
        selected_descriptor_offset_148_by_class[component_class] = {
            "selected_descriptor_memberships": len(memberships),
            "unique_selected_descriptors": len(unique_descriptors),
            "offset_148_raw_bits_evidence_classification": "shipped-source",
            "offset_148_candidate_decode_evidence_classification": (
                "third-party-technique"
            ),
            "offset_148_value_inventory": (
                _summarize_descriptor_offset_148_values(unique_descriptors)
            ),
        }
    selected_descriptor_offset_148_by_class["turret"][
        "candidate_channel_slot_024_relationships"
    ] = _summarize_descriptor_slot_024_relationships(
        selected_unique_descriptors_by_class["turret"]
    )
    selected_conventional_membership_counts = Counter(
        (
            str(endpoint["component"]),
            int(descriptor["descriptor_index"]),
        )
        for endpoint, descriptor in selected_endpoint_path_descriptor_memberships
        if endpoint["component_class"] == "turret"
    )
    channel_1_authored_restriction_correlation = (
        _build_channel_1_restriction_correlation(
            selected_unique_descriptors_by_class["turret"],
            selected_conventional_membership_counts,
            component_to_macros,
        )
    )
    subname_candidate_channel_inventory = (
        _build_subname_candidate_channel_inventory(
            selected_unique_descriptors_by_class,
            selected_endpoint_path_descriptor_memberships,
        )
    )
    same_subname_structural_relationship_coverage = (
        _build_same_subname_structural_relationship_coverage(
            component_to_macros,
            firing_endpoints,
            expected_turret_active_changing_case_baseline,
        )
    )
    ancestry_covered_turret_active_candidate_channel_inventory = (
        same_subname_structural_relationship_coverage.pop(
            "ancestry_covered_literal_turret_active_candidate_channel_inventory"
        )
    )
    effective_anchor_trace_spec = (
        anchor_trace_spec
        if anchor_trace_spec is not None
        else _PARANID_L_BEAM_TRACE_SPEC
    )
    paranid_l_beam_live_anchor = _build_paranid_l_beam_live_anchor(
        equipment_macros,
        component_to_macros,
        firing_endpoints,
        production_formula=(
            anchor_production_formula
            if anchor_production_formula is not None
            else _PARANID_L_BEAM_ACCEPTED_PRODUCTION_FORMULA
        ),
        trace_spec=effective_anchor_trace_spec,
    )

    anchor_relationship_descriptor_indexes = {
        int(effective_anchor_trace_spec[name]["descriptor_index"])
        for name in ("rotator_active_descriptor", "barrel_active_descriptor")
    }
    anchor_relationship_descriptors = [
        descriptor
        for descriptor in same_subname_structural_relationship_coverage[
            "focused_literal_turret_active"
        ]["descriptors"]
        if descriptor["component"] == "turret_par_l_beam_01_mk1"
        and descriptor["descriptor_index"] in anchor_relationship_descriptor_indexes
    ]
    paranid_l_beam_live_anchor[
        "same_subname_structural_relationship_coverage"
    ] = {
        "literal_subname": "turret_active",
        "descriptor_relationships": anchor_relationship_descriptors,
        "exact_matching_selector_connections": sorted(
            {
                relationship["selector_connection"]
                for descriptor in anchor_relationship_descriptors
                for relationship in descriptor[
                    "same_subname_selector_relationships"
                ]
            }
        ),
        "evidence_classification": "inference",
        "semantic_claim": "none",
    }

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
    combat_eligibility, combat_eligibility_anomalies = (
        _build_combat_conventional_turret_eligibility(equipment_macros, ware_records)
    )
    if combat_eligibility_anomalies:
        raise CensusError(combat_eligibility_anomalies)

    counts_by_source_set = {}
    for source_set in REQUIRED_SOURCE_SETS:
        records = [record for record in equipment_macros if record["source_set"] == source_set]
        counts_by_source_set[source_set] = {
            "equipment_macros": len(records),
            "turret_macros": sum(record["class"] == "turret" for record in records),
            "missileturret_macros": sum(record["class"] == "missileturret" for record in records),
        }

    return {
        "schema_version": 23,
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
        "combat_conventional_turret_eligibility": combat_eligibility,
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
        "candidate_channel_1_authored_restriction_correlation": (
            channel_1_authored_restriction_correlation
        ),
        "selected_descriptor_subname_candidate_channel_inventory": (
            subname_candidate_channel_inventory
        ),
        "conventional_endpoint_path_descriptor_same_subname_structural_relationship_coverage": (
            same_subname_structural_relationship_coverage
        ),
        "ancestry_covered_literal_turret_active_candidate_channel_inventory": (
            ancestry_covered_turret_active_candidate_channel_inventory
        ),
        "paranid_l_beam_accepted_live_anchor": paranid_l_beam_live_anchor,
        "selected_descriptor_offset_148_inventory_and_slot_024_relationships": {
            "evidence_classification": "inference",
            "descriptor_identity": ["component", "descriptor_index"],
            "descriptor_field_identity": {
                "field_name": "descriptor_offset_148",
                "byte_offset_within_descriptor": _ANI_DESCRIPTOR_OFFSET_148,
                "width_bytes": 4,
                "raw_bits_evidence_classification": "shipped-source",
                "candidate_float32_decode_evidence_classification": (
                    "third-party-technique"
                ),
            },
            "x4converter_lead": _x4converter_descriptor_offset_148_lead(),
            "value_inventory_rules": {
                "finite_nonzero_rule": (
                    "finite candidate float32 decode compares unequal to zero"
                ),
                "non_finite_rule": (
                    "non-finite candidate float32 decodes are separate from"
                    " numeric zero and numeric nonzero counts"
                ),
                "signed_zero_rule": (
                    "+0.0 and -0.0 compare numerically equal but remain distinct"
                    " raw-bit patterns"
                ),
                "raw_bit_distribution_bound": (
                    _DESCRIPTOR_RAW_BIT_DISTRIBUTION_LIMIT
                ),
            },
            "relationship_rules": {
                "evidence_classification": "inference",
                "candidate_channel_ownership_evidence_classification": (
                    "third-party-technique"
                ),
                "slot_024_identity": "slot_024",
                "raw_bit_equality": "exact 32-bit pattern equality",
                "numeric_equality": (
                    "candidate float32 equality; non-finite values are separate"
                ),
                "numeric_extrema": (
                    "minimum and maximum of finite candidate-decoded channel"
                    " slot_024 sequence"
                ),
                "key_count_scope": "zero-key, one-key, and multi-key descriptors",
            },
            "engine_requiredness": "unresolved",
            "semantic_claim": "none",
            "conventional": selected_descriptor_offset_148_by_class["turret"],
            "missileturret": selected_descriptor_offset_148_by_class[
                "missileturret"
            ],
        },
        "x4converter_candidate_key_record_semantic_lead": (
            _x4converter_candidate_key_record_semantic_lead()
        ),
        "selected_conventional_candidate_channel_metadata_patterns": {
            "evidence_classification": "inference",
            "candidate_field_layout": {
                "evidence_classification": "third-party-technique",
                "source": (
                    "X4Converter 0be4b494089ba7719d4c5d351e63160ef3843ef5"
                    " X4ConverterTools/include/X4ConverterTools/ani/Keyframe.h"
                    " and X4ConverterTools/src/ani/Keyframe.cpp"
                ),
                "candidate_enum_slot_ids": [
                    str(_ANI_KEY_RECORD_CANDIDATE_SLOTS[index]["slot_id"])
                    for index in (3, 4, 5)
                ],
                "candidate_numeric_ordering_slot_id": str(
                    _ANI_KEY_RECORD_CANDIDATE_SLOTS[6]["slot_id"]
                ),
                "candidate_middle_slot_ids": [
                    str(_ANI_KEY_RECORD_CANDIDATE_SLOTS[index]["slot_id"])
                    for index in range(7, 19)
                ],
                "candidate_tail_slot_ids": [
                    str(_ANI_KEY_RECORD_CANDIDATE_SLOTS[index]["slot_id"])
                    for index in range(19, 32)
                ],
            },
            "candidate_channel_ownership_order": {
                "evidence_classification": "third-party-technique",
                "source": (
                    "X4Converter 0be4b494089ba7719d4c5d351e63160ef3843ef5"
                    " X4ConverterTools/src/ani/AnimFile.cpp and AnimDesc.cpp"
                ),
                "candidate_channel_count_field_indexes": list(
                    range(len(_ANI_CHANNEL_COUNT_FIELDS))
                ),
            },
            "selection": {
                "component_class": "conventional",
                "minimum_candidate_channel_key_count": 2,
                "descriptor_identity": ["component", "descriptor_index"],
                "main_raw_bit_triple_slot_ids": [
                    str(slot["slot_id"])
                    for slot in _ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOTS
                ],
            },
            "numeric_ordering_rule": (
                "finite candidate decoded values compared in record order;"
                " categories are tested in reported order"
            ),
            "raw_bit_zero_pattern": "0x00000000",
            "semantic_claim": "none",
            "conventional": selected_candidate_channel_metadata_by_class[
                "turret"
            ],
            "missileturret_accounting": (
                selected_candidate_channel_metadata_by_class["missileturret"]
            ),
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
    parser.add_argument(
        "--require-accepted-turret-active-changing-case-baseline",
        action="store_true",
        help=(
            "fail unless the 444-descriptor turret_active cohort has exactly"
            " two changing cases in each of candidate channels 0 and 1"
        ),
    )
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
        report = build_census(
            source_sets,
            resource_sets,
            expected_turret_active_changing_case_baseline=(
                _ACCEPTED_TURRET_ACTIVE_CHANGING_CASE_BASELINE
                if args.require_accepted_turret_active_changing_case_baseline
                else None
            ),
        )
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
