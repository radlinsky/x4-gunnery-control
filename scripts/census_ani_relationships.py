"""Turret-active subname and ancestry structural relationship inventory for the Issue #78 census tools."""
from __future__ import annotations

from collections import Counter, defaultdict

from census_ani_analysis import (
    _ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOT_INDEXES,
    _CANDIDATE_CHANNEL_DYNAMICS_CLASSIFICATIONS,
    _CANDIDATE_NUMERIC_ORDERING_SHAPES,
    _candidate_channel_records,
    _candidate_main_triple_changing_mask,
    _classify_candidate_multi_key_triples,
    _summarize_candidate_channel_metadata,
)
from census_ani_parser import (
    _ANI_CHANNEL_COUNT_FIELDS,
    _ANI_KEY_RECORD_CANDIDATE_SLOTS,
)
from census_common import (
    CensusError,
    _anomaly,
)
from census_identity import _INCLUDED_CLASSES


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
