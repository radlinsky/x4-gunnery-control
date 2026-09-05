#!/usr/bin/env python3
"""Deterministic-generation proof for the muzzle-geometry renderer.

Feeds the generator a small synthetic source-resolved census report and asserts
byte-identical output across repeat renders and across reversed endpoint input
ordering. This is a determinism test, not a geometry-parity test -- the numeric
transforms are minimal placeholders; real Beam parity lives in
tests/test_turret_muzzle_geometry.lua.
"""
import importlib.util
import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_SCRIPTS))
_SCRIPT = _SCRIPTS / "generate-turret-muzzle-geometry.py"
_spec = importlib.util.spec_from_file_location("generate_turret_muzzle_geometry", _SCRIPT)
assert _spec and _spec.loader
_gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_gen)

X4_VERSION = "test"


def _offset(pos, quat):
    return {
        "position": {axis: {"candidate_numeric_value": value} for axis, value in zip("xyz", pos)},
        "quaternion": {
            axis: {"candidate_numeric_value": value}
            for axis, value in zip(("qx", "qy", "qz", "qw"), quat)
        },
    }


def _layers(count):
    return [
        {
            "source_part": f"part_{index}",
            "owning_connection": f"con_{index}",
            "connection_authored_offset": _offset((index, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0)),
            "part_authored_offset": _offset((0.0, index, 0.0), (0.0, 0.0, 0.0, 1.0)),
            "authored_restrictions": [],
        }
        for index in range(count)
    ]


def _endpoint_geometry(layers, connection, semantic_case):
    return {
        "classification": "SOURCE_RESOLVED",
        "semantic_case": semantic_case,
        "applied_authored_geometry": {
            "source_geometry_layers": layers,
            "endpoint_connection": connection,
            "endpoint_authored_offset": _offset((0.0, 0.0, 1.0), (0.0, 0.0, 0.0, 1.0)),
        },
    }


def _report(endpoint_connections):
    components = []
    for macro, (semantic_case, layer_count) in _gen.MACROS.items():
        layers = _layers(layer_count)
        components.append(
            {
                "macros": [macro],
                "source_semantic_resolutions": [
                    _endpoint_geometry(layers, connection, semantic_case)
                    for connection in endpoint_connections
                ],
            }
        )
    return {"x4_version": X4_VERSION, "component_to_macros": components}


def _check_settled_rotation_x():
    assert _gen._settled_rotation_x({}) is None
    assert _gen._settled_rotation_x(
        {"settled_local_euler_xyz_delta_radians": [0.6108652353286743, 0.0, -0.0]}
    ) == "0.6108652353286743"
    for bad in ([0.0, 1e-9, 0.0], [0.0, 0.0, 1e-9]):
        try:
            _gen._settled_rotation_x({"settled_local_euler_xyz_delta_radians": bad})
        except SystemExit:
            continue
        raise AssertionError(f"nonzero Euler Y/Z must fail closed: {bad}")


def main():
    _check_settled_rotation_x()
    order = ("con_laser_01", "con_laser_02")

    first = _gen._render(_report(order), X4_VERSION)
    second = _gen._render(_report(order), X4_VERSION)
    assert first == second, "repeat renders diverged"

    reversed_render = _gen._render(_report(tuple(reversed(order))), X4_VERSION)
    assert first == reversed_render, "endpoint input ordering changed generated text"

    print("turret muzzle geometry generation determinism tests passed")


if __name__ == "__main__":
    main()
