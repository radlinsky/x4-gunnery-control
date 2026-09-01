"""Source XML and ANI-resource identity collection for the Issue #78 census tools."""
from __future__ import annotations

import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path
from typing import Mapping

from census_common import REQUIRED_SOURCE_SETS, _anomaly
from census_sources import _ani_files, _xml_files

_INCLUDED_CLASSES = frozenset(("turret", "missileturret"))


def _direct_children(element: ET.Element, tag: str) -> list[ET.Element]:
    return [child for child in element if child.tag == tag]


def _authored_restriction_limit(
    restriction: ET.Element, tag: str
) -> dict[str, object] | None:
    limits = _direct_children(restriction, "limits")
    bound_elements = [
        bound
        for limits_element in limits
        for bound in _direct_children(limits_element, tag)
    ]
    if not bound_elements:
        return None
    raw_text = bound_elements[0].get("value")
    candidate_numeric_value = None
    if raw_text is not None:
        try:
            candidate_numeric_value = float(raw_text)
        except ValueError:
            pass
    return {
        "raw_text": raw_text,
        "candidate_numeric_value": candidate_numeric_value,
    }


def _authored_numeric_attributes(
    element: ET.Element | None, names: tuple[str, ...]
) -> dict[str, dict[str, object]] | None:
    if element is None:
        return None
    attributes = {}
    for name in names:
        raw_text = element.get(name)
        candidate_numeric_value = None
        if raw_text is not None:
            try:
                candidate_numeric_value = float(raw_text)
            except ValueError:
                pass
        attributes[name] = {
            "raw_text": raw_text,
            "candidate_numeric_value": candidate_numeric_value,
            "evidence_classification": "shipped-source",
        }
    return attributes


def _parse_authored_connection_offset(
    connection: ET.Element,
) -> dict[str, object]:
    offsets = _direct_children(connection, "offset")
    offset = offsets[0] if offsets else None
    positions = _direct_children(offset, "position") if offset is not None else []
    quaternions = (
        _direct_children(offset, "quaternion") if offset is not None else []
    )
    return {
        "position": _authored_numeric_attributes(
            positions[0] if positions else None, ("x", "y", "z")
        ),
        "quaternion": _authored_numeric_attributes(
            quaternions[0] if quaternions else None,
            ("qx", "qy", "qz", "qw"),
        ),
    }


def _parse_authored_connection_restrictions(
    connection: ET.Element,
) -> list[dict[str, object]]:
    source_connection = connection.get("name", "")
    restriction_elements = [
        restriction
        for restrictions in _direct_children(connection, "restrictions")
        for restriction in _direct_children(restrictions, "restriction")
    ]
    return [
        {
            "source_connection": source_connection,
            "restriction_index": restriction_index,
            "type_token": restriction.get("type"),
            "type_token_raw_text": restriction.get("type"),
            "authored_min": _authored_restriction_limit(restriction, "min"),
            "authored_max": _authored_restriction_limit(restriction, "max"),
            "evidence_classification": "shipped-source",
        }
        for restriction_index, restriction in enumerate(restriction_elements)
    ]


def _normalized_resource_identity(value: str) -> str:
    """Normalize only separators and case for resource identity comparison."""

    return value.replace("\\", "/").casefold()


def _build_ani_resource_inventory(
    resource_roots: Mapping[str, Path],
) -> tuple[dict[str, list[dict[str, object]]], dict[str, int]]:
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
            ani_resources_by_stem[
                _normalized_resource_identity(ani_resource[:-4])
            ].append(
                {
                    "ani_source_set": source_set,
                    "ani_resource": ani_resource,
                    "_ani_path": path,
                }
            )
    return ani_resources_by_stem, ani_inventory_counts_by_source_set


def _collect_xml_identities(
    roots: Mapping[str, Path],
) -> tuple[
    dict[str, list[dict[str, object]]],
    list[dict[str, str]],
    list[dict[str, object]],
    list[dict[str, object]],
]:
    component_definitions: dict[str, list[dict[str, object]]] = defaultdict(list)
    macro_records: list[dict[str, str]] = []
    ware_records: list[dict[str, object]] = []
    anomalies: list[dict[str, object]] = []

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
                                    "authored_restrictions": (
                                        _parse_authored_connection_restrictions(
                                            connection
                                        )
                                    ),
                                    "authored_offset": (
                                        _parse_authored_connection_offset(connection)
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

            for ware in xml_root.iter("ware"):
                component_children = _direct_children(ware, "component")
                use_children = _direct_children(ware, "use")
                component_refs = [
                    child.get("ref", "").strip()
                    for child in component_children
                    if child.get("ref", "").strip()
                ]
                if len(component_children) == 1:
                    mapped_refs = component_refs
                else:
                    mapped_refs = sorted(set(component_refs))
                for component_ref in mapped_refs:
                    ware_records.append(
                        {
                            "ware": ware.get("id", "").strip(),
                            "component": component_ref,
                            "source_set": source_set,
                            "source_file": relative,
                            "component_reference_count": len(component_children),
                            "use_count": len(use_children),
                            "purpose_attributes": [
                                use.get("purposes") for use in use_children
                            ],
                            "use_records": [
                                {
                                    "purposes": use.get("purposes"),
                                    "attributes": dict(use.attrib),
                                }
                                for use in use_children
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

    return component_definitions, macro_records, ware_records, anomalies


def _resolve_macro_identities(
    macro_records: list[dict[str, str]],
) -> tuple[list[dict[str, str]], list[dict[str, object]]]:
    records_by_name: dict[str, list[dict[str, str]]] = defaultdict(list)
    for record in macro_records:
        records_by_name[record["name"]].append(record)

    unique_records: list[dict[str, str]] = []
    anomalies: list[dict[str, object]] = []
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
    return unique_records, anomalies


def _resolve_component_identity(
    component: str,
    definitions: list[dict[str, object]],
    unique_records: list[dict[str, str]],
) -> tuple[dict[str, object] | None, list[dict[str, object]]]:
    anomalies: list[dict[str, object]] = []
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
        return None, anomalies
    if len(definitions) > 1:
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
        return None, anomalies

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
    return definition, anomalies


def _validate_authored_animation_selectors(
    animations: list[dict[str, str]],
    *,
    component: str,
    source_set: object,
    source_file: object,
) -> tuple[list[dict[str, str]], list[dict[str, object]]]:
    authored_animations = []
    anomalies: list[dict[str, object]] = []
    for animation in animations:
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
                    source_set=source_set,
                    source_file=source_file,
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
                    source_set=source_set,
                    source_file=source_file,
                )
            )
    return sorted(
        authored_animations, key=lambda item: (item["connection"], item["name"])
    ), anomalies


def _resolve_geometry_ani_resource_identity(
    definition: dict[str, object],
    ani_resources_by_stem: Mapping[str, list[dict[str, object]]],
    *,
    component: str,
) -> tuple[dict[str, object] | None, list[dict[str, object]]]:
    anomalies: list[dict[str, object]] = []
    match: dict[str, object] | None = None
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
    return match, anomalies
