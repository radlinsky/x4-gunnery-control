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


def _shared_report(aliases):
    """One census component backing several macro aliases."""
    macro = aliases[0]
    semantic_case, layer_count = _gen.MACROS[macro]
    layers = _layers(layer_count)
    return {
        "x4_version": X4_VERSION,
        "component_to_macros": [
            {
                "macros": list(aliases),
                "source_semantic_resolutions": [
                    _endpoint_geometry(layers, connection, semantic_case)
                    for connection in ("con_a", "con_b")
                ],
            }
        ],
    }


def _check_shared_component():
    # Both Xenon aliases are backed by one component under one contract.
    shared = ("turret_xen_m_beam_02_mk1_macro", "turret_xen_m_laser_02_mk1_macro")
    report = _shared_report(shared)
    first, second = (_gen._record(report, macro) for macro in shared)
    assert first[0] != second[0], "each alias must key its own record"
    assert first[1:] == second[1:], "aliases on one component must share geometry"

    near_misses = {
        "unsupported alias": shared + ("turret_xen_m_unknown_mk1_macro",),
        # depth5_additive_x_rotation / 5 layers: a different contract.
        "contract mismatch": shared + ("turret_par_m_laser_01_mk1_macro",),
        "duplicate alias": shared + (shared[1],),
    }
    for label, aliases in near_misses.items():
        bad = _shared_report(aliases)
        try:
            _gen._record(bad, shared[0])
        except SystemExit:
            continue
        raise AssertionError(f"{label} must fail closed")

    # The accepted Terran production macro shares a component with one
    # story-only alias outside the production boundary.
    terran = "turret_ter_m_laser_02_mk1_macro"
    story = "turret_ter_m_laser_story_mk1_macro"
    report = _shared_report((terran, story))
    assert _gen._record(report, terran)
    assert story not in _gen.MACROS


def _check_resolution_cardinality():
    connections = tuple(f"con_{index}" for index in range(5))
    cases = (
        ("turret_par_m_laser_01_mk1_macro", (1, 2, 5)),
        ("turret_par_l_beam_01_mk1_macro", (2,)),
    )
    for macro, accepted in cases:
        semantic_case, layer_count = _gen.MACROS[macro]
        layers = _layers(layer_count)
        for count in (1, 2, 3, 5):
            report = {
                "x4_version": X4_VERSION,
                "component_to_macros": [
                    {
                        "macros": [macro],
                        "source_semantic_resolutions": [
                            _endpoint_geometry(layers, connection, semantic_case)
                            for connection in connections[:count]
                        ],
                    }
                ],
            }
            try:
                _gen._record(report, macro)
            except SystemExit:
                assert count not in accepted, f"{macro} must accept {count}"
            else:
                assert count in accepted, f"{macro} must reject {count}"


def _check_barrelposition_hash():
    """The recovered #164 native connection-name hash, not ordinary FNV-1a."""
    # Census corpus.csv values for the analyzed X4 9.00 binary.
    for name, expected in (
        ("con_laser_02", 0x0C9442E72BBE5380),
        ("con_heavy_004", 0xD036B5AC8B234172),
    ):
        actual = _gen._native_connection_name_hash(name)
        assert actual == expected, f"{name}: {actual:#x} != {expected:#x}"
    try:
        _gen._native_connection_name_hash("con_l\u00e4ser_02")
    except SystemExit:
        pass
    else:
        raise AssertionError("non-ASCII connection name must fail closed")


def _check_barrelposition_selection():
    """Prove the selector is the unsigned-hash minimum, not an index rule."""
    macro = "turret_spl_m_plasma_02_mk1_macro"
    cases = {
        # one eligible endpoint
        ("con_laser_01",): "con_laser_01",
        # lexical endpoint 2 wins (Beam/Laser pattern)
        ("con_beam_01", "con_beam_02"): "con_beam_02",
        ("con_laser_01", "con_laser_02"): "con_laser_02",
        # lexical endpoint 1 wins (the Split Plasma counterexample)
        ("con_standard_01", "con_standard_02"): "con_standard_01",
        # five-endpoint Gatling family: neither index 1 nor 2
        (
            "con_heavy_001",
            "con_heavy_002",
            "con_heavy_003",
            "con_heavy_004",
            "con_heavy_005",
        ): "con_heavy_004",
    }
    for connections, expected in cases.items():
        assert _gen._barrelposition_connection(connections, macro) == expected
        # Input order must not matter.
        assert (
            _gen._barrelposition_connection(tuple(reversed(connections)), macro)
            == expected
        )

    for label, connections in (
        ("no eligible endpoint", ()),
        ("hash collision", ("con_a", "con_a")),
    ):
        try:
            _gen._barrelposition_connection(connections, macro)
        except SystemExit:
            continue
        raise AssertionError(f"{label} must fail closed")


def _check_barrelposition_emission():
    """Only the bounded #155 case gains the explicit identity field."""
    order = ("con_standard_01", "con_standard_02")
    report = _report(order)
    for macro, (semantic_case, _) in _gen.MACROS.items():
        text = "\n".join(_gen._record(report, macro))
        explicit = 'barrelposition_connection = "con_standard_01",' in text
        expected = semantic_case in _gen.EXPLICIT_BARRELPOSITION_SEMANTIC_CASES
        assert explicit == expected, f"{macro} explicit identity {explicit}"
        assert "barrelposition_connection" in text or not expected


def main():
    _check_settled_rotation_x()
    _check_shared_component()
    _check_resolution_cardinality()
    _check_barrelposition_hash()
    _check_barrelposition_selection()
    _check_barrelposition_emission()
    order = ("con_laser_01", "con_laser_02")

    first = _gen._render(_report(order), X4_VERSION)
    second = _gen._render(_report(order), X4_VERSION)
    assert first == second, "repeat renders diverged"

    reversed_render = _gen._render(_report(tuple(reversed(order))), X4_VERSION)
    assert first == reversed_render, "endpoint input ordering changed generated text"

    print("turret muzzle geometry generation determinism tests passed")


if __name__ == "__main__":
    main()
