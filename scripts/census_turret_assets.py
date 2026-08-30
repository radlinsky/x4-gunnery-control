#!/usr/bin/env python3
"""Build the Issue #72 A2.1 macro-driven X4 9.00 turret asset census.

This tool intentionally stops at equipment macro -> referenced component asset.
It does not inspect geometry, ANI data, parts, connections, or muzzle endpoints.
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
    component_definitions: dict[str, list[tuple[str, str]]] = defaultdict(list)
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
                    component_definitions[name].append((source_set, relative))

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

    for record in unique_records:
        component = record["component"]
        if component not in component_definitions:
            anomalies.append(
                _anomaly(
                    "unresolved_component_reference",
                    "equipment macro references no component definition in the official source set",
                    source_set=record["source_set"],
                    source_file=record["source_file"],
                    macro=record["name"],
                    component=component,
                )
            )

    if anomalies:
        raise CensusError(anomalies)

    equipment_macros = sorted(unique_records, key=lambda record: record["name"])
    inverted: dict[str, list[str]] = defaultdict(list)
    for record in equipment_macros:
        inverted[record["component"]].append(record["name"])

    component_to_macros = [
        {"component": component, "macro_count": len(macros), "macros": sorted(macros)}
        for component, macros in sorted(inverted.items())
    ]
    cardinalities = Counter(entry["macro_count"] for entry in component_to_macros)
    counts_by_source_set = {}
    for source_set in REQUIRED_SOURCE_SETS:
        records = [record for record in equipment_macros if record["source_set"] == source_set]
        counts_by_source_set[source_set] = {
            "equipment_macros": len(records),
            "turret_macros": sum(record["class"] == "turret" for record in records),
            "missileturret_macros": sum(record["class"] == "missileturret" for record in records),
        }

    return {
        "schema_version": 1,
        "x4_version": "9.00",
        "official_source_sets": list(REQUIRED_SOURCE_SETS),
        "counts": {
            "equipment_macros": len(equipment_macros),
            "turret_macros": sum(record["class"] == "turret" for record in equipment_macros),
            "missileturret_macros": sum(record["class"] == "missileturret" for record in equipment_macros),
            "unique_components": len(component_to_macros),
        },
        "counts_by_source_set": counts_by_source_set,
        "equipment_macros": equipment_macros,
        "component_to_macros": component_to_macros,
        "component_macro_cardinality": {str(key): cardinalities[key] for key in sorted(cardinalities)},
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
    parser.add_argument("--output", type=Path, help="write JSON here instead of stdout")
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
        report = build_census(source_sets)
    except CensusError as exc:
        sys.stderr.write(str(exc) + "\n")
        return 2

    output = render_json(report)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
