#!/usr/bin/env python3
"""Validate Test Lab turret assignments against official X4 source."""
from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Mapping, Sequence

from census_common import REQUIRED_SOURCE_SETS
from turret_ship_compatibility import query_compatibility


class PreflightError(Exception):
    pass


def _attributes(element: ET.Element, expected: set[str], context: str) -> None:
    if set(element.attrib) != expected or any(not element.get(name, "").strip() for name in expected):
        raise PreflightError(f"{context}: expected exactly {sorted(expected)} attributes")


def validate_loadouts(source_sets: Mapping[str, Path], loadouts_path: Path) -> None:
    try:
        root = ET.parse(loadouts_path).getroot()
    except (OSError, ET.ParseError) as exc:
        raise PreflightError(f"cannot read loadouts XML: {exc}") from exc
    if root.tag != "loadouts":
        raise PreflightError("unsupported loadout document root")

    cache: dict[tuple[str, str], dict[str, object]] = {}
    for loadout in root:
        if loadout.tag != "loadout":
            raise PreflightError(f"unsupported element <{loadout.tag}> under <loadouts>")
        loadout_id = loadout.get("id", "").strip()
        ship_macro = loadout.get("macro", "").strip()
        if not loadout_id or not ship_macro:
            raise PreflightError("loadout requires non-empty id and macro attributes")
        context = f"loadout {loadout_id!r}"

        singular = list(loadout.findall("./macros/turret"))
        plural = list(loadout.findall("./groups/turrets"))
        if list(loadout.iter("turret")) != singular or list(loadout.iter("turrets")) != plural:
            raise PreflightError(f"{context}: unsupported turret assignment structure")

        for assignment in singular + plural:
            turret_macro = assignment.get("macro", "").strip()
            pair = (turret_macro, ship_macro)
            if pair not in cache:
                cache[pair] = query_compatibility(source_sets, turret_macro, ship_macro)
            result = cache[pair]
            assignment_context = f"{context}, turret {turret_macro!r}"
            if result["status"] == "unresolved":
                if result["reason"] == "source_sets":
                    raise PreflightError(
                        "required official X4 source sets are unavailable; provide the complete "
                        "base and DLC XML source-set root"
                    )
                raise PreflightError(
                    f"{assignment_context}: source identity unresolved ({result['reason']})"
                )

            connections = {
                str(item["connection"]): item for item in result["ship_connections"]  # type: ignore[index]
            }
            compatible = {
                str(item["connection"]): item for item in result["compatible_connections"]  # type: ignore[index]
            }
            if assignment.tag == "turret":
                _attributes(assignment, {"macro", "path"}, assignment_context)
                path = assignment.get("path", "")
                if not path.startswith("../") or "/" in path[3:] or len(path) == 3:
                    raise PreflightError(f"{assignment_context}: unsupported path ownership {path!r}")
                connection_name = path[3:]
                if connection_name not in connections:
                    raise PreflightError(
                        f"{assignment_context}: ship connection {connection_name!r} does not exist"
                    )
                group = connections[connection_name]["group"]
                if group:
                    raise PreflightError(
                        f"{assignment_context}: connection {connection_name!r} belongs to named turret group "
                        f"{group!r}; use group-targeted <turrets macro=\"...\" group=\"{group}\" exact=\"N\"/> syntax"
                    )
                if connection_name not in compatible:
                    raise PreflightError(
                        f"{assignment_context}: turret is incompatible with ship connection {connection_name!r}"
                    )
            else:
                _attributes(assignment, {"macro", "group", "exact"}, assignment_context)
                group = assignment.get("group", "").strip()
                raw_exact = assignment.get("exact", "")
                try:
                    exact = int(raw_exact)
                except ValueError as exc:
                    raise PreflightError(f"{assignment_context}: exact must be a positive integer") from exc
                if exact < 1 or str(exact) != raw_exact:
                    raise PreflightError(f"{assignment_context}: exact must be a positive integer")
                group_connections = [item for item in connections.values() if item["group"] == group]
                if not group_connections:
                    raise PreflightError(f"{assignment_context}: named turret group {group!r} does not exist")
                compatible_count = sum(item["group"] == group for item in compatible.values())
                if compatible_count < exact:
                    raise PreflightError(
                        f"{assignment_context}: named turret group {group!r} has {compatible_count} "
                        f"source-compatible connections, fewer than exact={exact}"
                    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument(
        "--loadouts",
        type=Path,
        default=Path("testlab/x4_gunnery_control_testlab/libraries/loadouts.xml"),
    )
    args = parser.parse_args(argv)
    source_sets = {name: args.source_root / name for name in REQUIRED_SOURCE_SETS}
    try:
        validate_loadouts(source_sets, args.loadouts)
    except PreflightError as exc:
        print(f"Test Lab turret preflight failed: {exc}", file=sys.stderr)
        return 1
    print(f"Test Lab turret preflight passed: {args.loadouts}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
