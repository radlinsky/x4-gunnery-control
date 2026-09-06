#!/usr/bin/env python3
"""Generate the source-resolved turret muzzle geometry consumed by UI Lua."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import NotRequired, Sequence, TypedDict, cast

from census_common import CensusError
from census_pipeline import build_census


# Only the census-report shape this generator reads; the real report carries more.
class _Number(TypedDict):
    candidate_numeric_value: float


# offset -> "position"/"quaternion" -> component name -> numeric record
_Offset = dict[str, dict[str, _Number]]


class _Restriction(TypedDict):
    type_token: str
    authored_min: NotRequired[_Number]
    authored_max: NotRequired[_Number]


class _Layer(TypedDict):
    source_part: str
    owning_connection: str
    connection_authored_offset: _Offset
    part_authored_offset: _Offset
    authored_restrictions: list[_Restriction]
    settled_local_position_delta: NotRequired[list[float]]
    settled_local_euler_xyz_delta_radians: NotRequired[list[float]]


class _Geometry(TypedDict):
    source_geometry_layers: list[_Layer]
    endpoint_connection: str
    endpoint_authored_offset: _Offset


class _Resolution(TypedDict):
    classification: str
    semantic_case: str
    applied_authored_geometry: _Geometry


class _Component(TypedDict):
    macros: list[str]
    source_semantic_resolutions: list[_Resolution]


class _Report(TypedDict):
    x4_version: str
    component_to_macros: list[_Component]


# macro -> (accepted semantic case, expected source-part layer count)
MACROS = {
    "turret_par_l_beam_01_mk1_macro": ("depth4_dual_translation", 4),
    "turret_par_m_laser_01_mk1_macro": ("depth5_additive_x_rotation", 5),
    "turret_par_l_laser_01_mk1_macro": ("depth4_dual_translation", 4),
    "turret_par_l_plasma_01_mk1_macro": ("depth4_dual_translation", 4),
    "turret_par_m_beam_01_mk1_macro": ("depth5_additive_x_rotation", 5),
    "turret_par_m_plasma_01_mk1_macro": ("depth5_additive_x_rotation", 5),
    "turret_tel_m_beam_01_mk1_macro": ("depth5_additive_x_rotation", 5),
    "turret_tel_m_laser_01_mk1_macro": ("depth5_additive_x_rotation", 5),
    "turret_tel_m_plasma_01_mk1_macro": ("depth5_additive_x_rotation", 5),
    "turret_ter_m_laser_01_mk1_macro": ("depth5_additive_x_rotation", 5),
    "turret_spl_l_beam_01_mk1_macro": ("depth4_zero_translation", 4),
    "turret_spl_l_laser_01_mk1_macro": ("depth4_zero_translation", 4),
    "turret_spl_l_plasma_01_mk1_macro": ("depth4_zero_translation", 4),
}


def _source_set(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected NAME=PATH")
    name, raw_path = value.split("=", 1)
    if not name or not raw_path:
        raise argparse.ArgumentTypeError("expected non-empty NAME=PATH")
    return name, Path(raw_path)


def _mapping(values: list[tuple[str, Path]], option: str) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for name, path in values:
        if name in result:
            raise SystemExit(f"duplicate {option} name: {name}")
        result[name] = path
    return result


def _number(value: float) -> str:
    number = float(value)
    if number == 0:
        return "0"
    return repr(number)


def _vector(offset: _Offset, key: str, names: tuple[str, ...]) -> str:
    record = offset.get(key)
    if record is None:
        defaults = (0.0, 0.0, 0.0, 1.0) if key == "quaternion" else (0.0, 0.0, 0.0)
        values = defaults
    else:
        values = tuple(float(record[name]["candidate_numeric_value"]) for name in names)
    return "{ " + ", ".join(_number(value) for value in values) + " }"


def _transform(offset: _Offset) -> str:
    return "{ position = %s, quaternion = %s }" % (
        _vector(offset, "position", ("x", "y", "z")),
        _vector(offset, "quaternion", ("qx", "qy", "qz", "qw")),
    )


def _rotation(restrictions: list[_Restriction]) -> str | None:
    if not restrictions:
        return None
    if len(restrictions) != 1:
        raise SystemExit("unsupported multiple runtime rotation roles on one layer")
    restriction = restrictions[0]
    token = str(restriction["type_token"])
    if token not in ("rotation_x", "rotation_y"):
        raise SystemExit(f"unsupported runtime rotation role: {token}")
    fields = [f'axis = "{token[-1]}"']
    for bound, target in (
        (restriction.get("authored_min"), "minimum_degrees"),
        (restriction.get("authored_max"), "maximum_degrees"),
    ):
        if bound is not None:
            fields.append(f'{target} = {_number(bound["candidate_numeric_value"])}')
    return "{ " + ", ".join(fields) + " }"


def _settled_rotation_x(layer: _Layer) -> str | None:
    values = layer.get("settled_local_euler_xyz_delta_radians")
    if values is None:
        return None
    # Only the proven local-X case is representable; anything else
    # would need a full Euler representation nothing consumes yet.
    if float(values[1]) != 0 or float(values[2]) != 0:
        raise SystemExit("unsupported non-local-X settled rotation")
    return _number(values[0])


def _record(report: _Report, macro: str) -> list[str]:
    semantic_case, layer_count = MACROS[macro]
    matches = [
        record
        for record in report["component_to_macros"]
        if macro in record["macros"]
    ]
    if len(matches) != 1 or matches[0]["macros"].count(macro) != 1:
        raise SystemExit(f"expected exactly one census identity for {macro}")
    component = matches[0]
    if component["macros"] != [macro]:
        raise SystemExit(f"unsupported shared component for {macro}")
    resolutions = component["source_semantic_resolutions"]
    if len(resolutions) != 2 or any(
        item.get("classification") != "SOURCE_RESOLVED"
        or item.get("semantic_case") != semantic_case
        for item in resolutions
    ):
        raise SystemExit(f"unsupported source geometry for {macro}")

    geometries = [item["applied_authored_geometry"] for item in resolutions]
    layers = geometries[0]["source_geometry_layers"]
    if len(layers) != layer_count or any(
        geometry["source_geometry_layers"] != layers for geometry in geometries[1:]
    ):
        raise SystemExit(f"unsupported endpoint topology for {macro}")

    lines = [
        f'    ["{macro}"] = {{',
        f'        semantic_case = "{semantic_case}",',
        "        layers = {",
    ]
    for layer in layers:
        lines.extend([
            "            {",
            f'                source_part = "{layer["source_part"]}",',
            f'                owning_connection = "{layer["owning_connection"]}",',
            f'                connection_transform = {_transform(layer["connection_authored_offset"])},',
            f'                part_transform = {_transform(layer["part_authored_offset"])},',
        ])
        if "settled_local_position_delta" in layer:
            values = layer["settled_local_position_delta"]
            lines.append(
                "                settled_position = { "
                + ", ".join(_number(value) for value in values)
                + " },"
            )
        settled_rotation = _settled_rotation_x(layer)
        if settled_rotation is not None:
            lines.append(f"                settled_rotation_x_radians = {settled_rotation},")
        rotation = _rotation(layer["authored_restrictions"])
        if rotation is not None:
            lines.append(f"                runtime_rotation = {rotation},")
        lines.append("            },")
    lines.extend(["        },", "        endpoints = {"])
    for geometry in sorted(geometries, key=lambda item: item["endpoint_connection"]):
        lines.append(
            f'            {{ connection = "{geometry["endpoint_connection"]}", '
            f'transform = {_transform(geometry["endpoint_authored_offset"])} }},'
        )
    lines.extend(["        },", "    },"])
    return lines


def _render(report: _Report, x4_version: str) -> str:
    if str(report["x4_version"]) != x4_version:
        raise SystemExit(
            f"census X4 version {report['x4_version']} does not match {x4_version}"
        )
    lines = [
        "-- Generated by scripts/generate-turret-muzzle-geometry.py from the",
        f"-- X4 {x4_version} census source-semantic pipeline; do not hand-edit.",
        "X4GunneryTurretMuzzleGeometry = {",
    ]
    for macro in MACROS:
        lines.extend(_record(report, macro))
    lines.extend(["}", ""])
    return "\n".join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="generate source-resolved muzzle geometry for "
        + ", ".join(MACROS)
    )
    parser.add_argument("--source-set", action="append", default=[], type=_source_set)
    parser.add_argument("--resource-set", action="append", default=[], type=_source_set)
    parser.add_argument("--x4-version", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        report = cast(
            _Report,
            build_census(
                _mapping(args.source_set, "source-set"),
                _mapping(args.resource_set, "resource-set"),
                include_source_semantic_resolutions=True,
            ),
        )
    except CensusError as error:
        print(error, file=sys.stderr)
        return 1
    args.output.write_text(_render(report, args.x4_version), encoding="utf-8")
    print(f"wrote {len(MACROS)} turret macro geometry records to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
