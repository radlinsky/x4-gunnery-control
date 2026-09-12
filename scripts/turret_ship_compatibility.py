#!/usr/bin/env python3
"""Answer exact turret-to-ship compatibility from current X4 source."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Mapping, Sequence

from census_common import REQUIRED_SOURCE_SETS, CensusError, render_json
from census_identity import (
    _INCLUDED_CLASSES,
    _collect_xml_identities,
    _resolve_component_identity,
    _resolve_macro_identities,
)
from census_sources import _validate_source_sets


def _unresolved(
    turret_macro: str,
    ship_macro: str,
    reason: str,
    anomalies: list[dict[str, object]] | None = None,
) -> dict[str, object]:
    result: dict[str, object] = {
        "status": "unresolved",
        "turret_macro": turret_macro,
        "ship_macro": ship_macro,
        "reason": reason,
    }
    if anomalies:
        result["anomalies"] = anomalies
    return result


def query_compatibility(
    source_sets: Mapping[str, Path], turret_macro: str, ship_macro: str
) -> dict[str, object]:
    try:
        roots = _validate_source_sets(source_sets)
    except CensusError as exc:
        return _unresolved(turret_macro, ship_macro, "source_sets", exc.anomalies)

    components, macro_records, _wares, anomalies = _collect_xml_identities(
        roots, macro_names=frozenset((turret_macro, ship_macro))
    )
    if anomalies:
        return _unresolved(turret_macro, ship_macro, "source_identity", anomalies)

    records, anomalies = _resolve_macro_identities(macro_records)
    if anomalies:
        return _unresolved(turret_macro, ship_macro, "macro_identity", anomalies)
    by_name = {record["name"]: record for record in records}
    missing = [name for name in (turret_macro, ship_macro) if name not in by_name]
    if missing:
        return _unresolved(
            turret_macro,
            ship_macro,
            "missing_macro",
            [{"code": "missing_macro", "macro": name} for name in missing],
        )

    turret = by_name[turret_macro]
    ship = by_name[ship_macro]
    if turret["class"] not in _INCLUDED_CLASSES or not ship["class"].startswith("ship_"):
        return _unresolved(turret_macro, ship_macro, "unsupported_macro_class")

    turret_component, turret_anomalies = _resolve_component_identity(
        turret["component"], components.get(turret["component"], []), records
    )
    ship_component, ship_anomalies = _resolve_component_identity(
        ship["component"], components.get(ship["component"], []), records
    )
    identity_anomalies = turret_anomalies + ship_anomalies
    if identity_anomalies or turret_component is None or ship_component is None:
        return _unresolved(
            turret_macro, ship_macro, "component_identity", identity_anomalies
        )
    if (
        turret_component["component_class"] != turret["class"]
        or ship_component["component_class"] != ship["class"]
    ):
        return _unresolved(turret_macro, ship_macro, "component_class_mismatch")

    mating = [
        connection
        for connection in turret_component["connection_records"]
        if "component" in connection["tag_tokens"]
    ]
    if len(mating) != 1:
        return _unresolved(turret_macro, ship_macro, "mating_connection_identity")
    required_tags = set(mating[0]["tag_tokens"]) - {"component"}
    if not required_tags:
        return _unresolved(turret_macro, ship_macro, "empty_compatibility_tags")

    compatible = []
    ship_connections = []
    for connection in ship_component["connection_records"]:
        name = str(connection["name"]).strip()
        if not name:
            return _unresolved(turret_macro, ship_macro, "malformed_ship_connection")
        raw_group = connection["authored_attributes"].get("group")
        group = str(raw_group).strip() if raw_group is not None else None
        entry = {"connection": name, "group": group or None}
        ship_connections.append(entry)
        if required_tags.issubset(connection["tag_tokens"]):
            compatible.append(entry)

    connection_names = [entry["connection"] for entry in ship_connections]
    if len(set(connection_names)) != len(connection_names):
        return _unresolved(turret_macro, ship_macro, "duplicate_ship_connection")
    ship_connections.sort(key=lambda entry: (str(entry["connection"]), str(entry["group"] or "")))
    compatible.sort(key=lambda entry: (str(entry["connection"]), str(entry["group"] or "")))
    return {
        "status": "compatible" if compatible else "incompatible",
        "turret_macro": turret_macro,
        "ship_macro": ship_macro,
        "ship_connections": ship_connections,
        "compatible_connections": compatible,
        "compatible_mount_count": len(compatible),
    }


def _source_set(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected NAME=PATH")
    name, raw_path = value.split("=", 1)
    if not name or not raw_path:
        raise argparse.ArgumentTypeError("expected non-empty NAME=PATH")
    return name, Path(raw_path)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Check one exact X4 turret macro against one exact ship macro."
    )
    parser.add_argument(
        "--source-set",
        action="append",
        default=[],
        metavar="NAME=PATH",
        type=_source_set,
        help="repeat for each required official X4 source set",
    )
    parser.add_argument("--turret-macro", required=True)
    parser.add_argument("--ship-macro", required=True)
    args = parser.parse_args(argv)

    source_sets: dict[str, Path] = {}
    for name, path in args.source_set:
        if name in source_sets:
            parser.error(f"source set {name!r} was supplied more than once")
        source_sets[name] = path
    missing = sorted(set(REQUIRED_SOURCE_SETS) - set(source_sets))
    extra = sorted(set(source_sets) - set(REQUIRED_SOURCE_SETS))
    if missing or extra:
        parser.error(f"source sets must be exactly {list(REQUIRED_SOURCE_SETS)}")

    sys.stdout.write(
        render_json(query_compatibility(source_sets, args.turret_macro, args.ship_macro))
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
