"""Connection hierarchy, firing-endpoint classification, and endpoint source-path derivation for the Issue #78 census tools."""
from __future__ import annotations

from collections import defaultdict

from census_common import _anomaly


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
                "authored_restrictions": record["authored_restrictions"],
                "_authored_offset": record["authored_offset"],
                "_direct_owned_part_transforms": record.get(
                    "_direct_owned_part_transforms", []
                ),
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
                        "descriptor_offset_148": descriptor[
                            "descriptor_offset_148"
                        ],
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
