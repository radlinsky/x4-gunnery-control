#!/usr/bin/env python3
"""Build the Issue #72 macro-driven X4 9.00 turret asset census.

This tool stops at exact authored connection paths, firing-endpoint connection
identities, and ANI descriptor/source-part identity. It does not parse ANI
keyframes/channels or interpret transforms, pivots, axes, joints, descriptor
relevance, active pose, or prospective muzzle position.
"""
from __future__ import annotations

import argparse
import json
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


def _parse_ani_descriptors(path: Path) -> list[dict[str, str]]:
    """Parse only the current ANI v1 header and fixed descriptor table."""

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

    descriptors: list[dict[str, str]] = []
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
        descriptors.append({"part": part, "subname": subname})
    return sorted(descriptors, key=lambda item: (item["part"], item["subname"]))


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
                                    "part": part,
                                    "subname": descriptor["subname"],
                                    "source_connection": owner,
                                    "root_to_source_connection_path": connection_paths[owner],
                                }
                            )
                        definition["ani_descriptors"] = joined_descriptors
                        definition["descriptor_parts_absent_from_source_parts"] = sorted(
                            absent_parts
                        )

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
        "schema_version": 7,
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
            "authored_connection_animations": sum(
                len(record["authored_connection_animations"])
                for record in component_to_macros
            ),
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
