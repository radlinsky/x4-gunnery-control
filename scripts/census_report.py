"""Successful-corpus census report assembly for the Issue #78 census tools."""
from __future__ import annotations

from collections import Counter, defaultdict

from census_ani_analysis import (
    _ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOTS,
    _DESCRIPTOR_RAW_BIT_DISTRIBUTION_LIMIT,
    _build_channel_1_restriction_correlation,
    _inventory_candidate_multi_key_metadata,
    _summarize_candidate_channel_dynamics,
    _summarize_candidate_raw_key_records,
    _summarize_descriptor_offset_148_values,
    _summarize_descriptor_slot_024_relationships,
)
from census_ani_parser import (
    _ANI_CHANNEL_COUNT_FIELDS,
    _ANI_DESCRIPTOR_OFFSET_148,
    _ANI_KEY_RECORD_CANDIDATE_OVERLAPPING_BYTES,
    _ANI_KEY_RECORD_CANDIDATE_SLOTS,
    _ANI_KEY_RECORD_CANDIDATE_UNACCOUNTED_BYTES,
    _ANI_KEY_RECORD_SIZE,
)
from census_ani_relationships import (
    _build_same_subname_structural_relationship_coverage,
    _build_subname_candidate_channel_inventory,
)
from census_anchor_evidence import (
    _PARANID_L_BEAM_ACCEPTED_PRODUCTION_FORMULA,
    _PARANID_L_BEAM_TRACE_SPEC,
    _build_paranid_l_beam_live_anchor,
)
from census_common import REQUIRED_SOURCE_SETS, CensusError
from census_eligibility import _build_combat_conventional_turret_eligibility
from census_endpoint_paths import _FIRING_ENDPOINT_TAG_BY_COMPONENT_CLASS
from census_identity import _INCLUDED_CLASSES
from census_topology import _build_combat_conventional_topology_inventory
from census_x4converter_evidence import (
    _x4converter_candidate_key_record_semantic_lead,
    _x4converter_descriptor_offset_148_lead,
)


def _strip_candidate_raw_key_records(value: object) -> None:
    if isinstance(value, dict):
        value.pop("_candidate_raw_key_records", None)
        value.pop("_authored_offset", None)
        value.pop("_direct_owned_part_transforms", None)
        for child in value.values():
            _strip_candidate_raw_key_records(child)
    elif isinstance(value, list):
        for child in value:
            _strip_candidate_raw_key_records(child)


def _assemble_census_report(
    component_definitions: dict[str, list[dict[str, object]]],
    unique_records: list[dict[str, str]],
    ware_records: list[dict[str, object]],
    ani_inventory_counts_by_source_set: dict[str, int],
    *,
    anchor_production_formula: dict[str, object] | None = None,
    anchor_trace_spec: dict[str, object] | None = None,
    expected_turret_active_changing_case_baseline: (
        tuple[int, int, int] | None
    ) = None,
) -> dict[str, object]:
    """Assemble the successful-corpus census report in the original stage order."""

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
    combat_conventional_topology_inventory = (
        _build_combat_conventional_topology_inventory(
            combat_eligibility, component_to_macros
        )
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
        "schema_version": 25,
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
        "combat_conventional_topology_inventory": (
            combat_conventional_topology_inventory
        ),
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
