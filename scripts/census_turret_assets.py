#!/usr/bin/env python3
"""Build the Issue #72 macro-driven X4 9.00 turret asset census.

This tool stops at component -> exact authored geometry-source identity. It does
not discover ANI files or inspect descriptors, parts, connections, or endpoints.
"""
from __future__ import annotations

import argparse
import json
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


def _xml_files(root: Path) -> list[Path]:
    return sorted(
        (path for path in root.rglob("*") if path.is_file() and path.suffix.lower() == ".xml"),
        key=lambda path: path.relative_to(root).as_posix(),
    )


def _direct_children(element: ET.Element, tag: str) -> list[ET.Element]:
    return [child for child in element if child.tag == tag]


def build_census(source_sets: Mapping[str, Path]) -> dict[str, object]:
    """Return a deterministic census or raise CensusError on any unsafe input."""

    roots = _validate_source_sets(source_sets)
    anomalies: list[dict[str, object]] = []
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
        "schema_version": 3,
        "x4_version": "9.00",
        "official_source_sets": list(REQUIRED_SOURCE_SETS),
        "counts": {
            "equipment_macros": len(equipment_macros),
            "turret_macros": sum(record["class"] == "turret" for record in equipment_macros),
            "missileturret_macros": sum(record["class"] == "missileturret" for record in equipment_macros),
            "unique_components": len(component_to_macros),
            "unique_geometry_sources": len(geometry_source_to_components),
        },
        "counts_by_source_set": counts_by_source_set,
        "equipment_macros": equipment_macros,
        "component_to_macros": component_to_macros,
        "component_macro_cardinality": {str(key): cardinalities[key] for key in sorted(cardinalities)},
        "geometry_source_to_components": geometry_source_to_components,
        "geometry_source_component_cardinality": {
            str(key): geometry_cardinalities[key] for key in sorted(geometry_cardinalities)
        },
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
        help="repeat exactly once for base and each required official extension",
    )
    parser.add_argument("--output", type=Path, help="write census JSON here instead of stdout")
    parser.add_argument("--old79-components", type=Path, help="preserved old 79-component cache")
    parser.add_argument("--platform-sweep", type=Path, help="preserved platform-sweep cache")
    parser.add_argument("--reconciliation-output", type=Path, help="write historical reconciliation JSON here")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _arguments(argv)
    source_sets: dict[str, Path] = {}
    duplicate_arguments: list[dict[str, object]] = []
    for name, path in args.source_set:
        if name in source_sets:
            duplicate_arguments.append(
                _anomaly("duplicate_source_set_argument", "source set was supplied more than once", source_set=name)
            )
        source_sets[name] = path

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
        report = build_census(source_sets)
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
