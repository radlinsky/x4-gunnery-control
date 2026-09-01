"""Census source validation and identity-resolution orchestration for the Issue #78 census tools."""
from __future__ import annotations

from pathlib import Path
from typing import Mapping

from census_ani_parser import AniDescriptorError, _parse_ani_descriptors
from census_common import CensusError, _anomaly
from census_endpoint_paths import (
    _classify_firing_endpoints,
    _derive_endpoint_source_paths,
    _join_authored_animation_selectors,
    _resolve_connection_hierarchy,
)
from census_identity import (
    _build_ani_resource_inventory,
    _collect_xml_identities,
    _resolve_component_identity,
    _resolve_geometry_ani_resource_identity,
    _resolve_macro_identities,
    _validate_authored_animation_selectors,
)
from census_report import _assemble_census_report
from census_sources import _validate_resource_sets, _validate_source_sets


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
    return _assemble_census_report(
        component_definitions,
        unique_records,
        ware_records,
        ani_inventory_counts_by_source_set,
        anchor_production_formula=anchor_production_formula,
        anchor_trace_spec=anchor_trace_spec,
        expected_turret_active_changing_case_baseline=(
            expected_turret_active_changing_case_baseline
        ),
    )
