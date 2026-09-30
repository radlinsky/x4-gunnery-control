#!/usr/bin/env python3
"""#166 A9 offline barrelposition evaluator: behavior on a tiny synthetic turret.

Guards the engine rules that earlier hand-built geometry got wrong: native-hash
endpoint selection, joint signs/pivot, ANI local translation rotating with the
joint, unchanged ANI X sign, active-hold time, and fail-closed restrictions.
"""
from __future__ import annotations

import math
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "support"))

from census_fixture import _ani_bytes, _candidate_key_record, _source_roots, _write  # noqa: E402

from barrelposition_evaluator import EvaluatorError, evaluate, load_turrets  # noqa: E402

MACRO = "turret_t_macro"


def _key(value: tuple[float, float, float], time: float) -> bytes:
    # linear (enum 2) key: value, enums, time, then zeroed handles/tail
    return _candidate_key_record((*value, 2, 2, 2, time, *([0.0] * 17), 0, *([0.0] * 6), 0))


def _component(pitch_restriction: str = "rotation_x") -> str:
    return f"""<components><component name="turret_t" class="turret">
<source geometry="geometry/turret_t"/><connections>
 <connection name="base"><parts><part name="socket"/></parts>
  <animations><animation name="turret_active" start="1" end="1"/></animations></connection>
 <connection name="yaw" parent="socket"><restrictions><restriction type="rotation_y"/></restrictions>
  <parts><part name="rotator"/></parts></connection>
 <connection name="pitch" parent="rotator"><offset><position x="0" y="0" z="1"/></offset>
  <restrictions><restriction type="{pitch_restriction}"><limits><min value="-10"/><max value="90"/></limits></restriction></restrictions>
  <parts><part name="gun"/></parts></connection>
 <connection name="con_a" parent="gun" tags="laser"><offset><position x="0" y="0" z="3"/></offset></connection>
 <connection name="con_b" parent="gun" tags="laser"><offset><position x="0" y="0" z="3"/></offset></connection>
</connections></component></components>"""


class BarrelpositionEvaluatorTests(unittest.TestCase):
    def _load(self, root: Path, pitch_restriction: str = "rotation_x") -> dict[str, object]:
        roots = _source_roots(root)
        _write(roots["base"], "turret_t.xml", _component(pitch_restriction))
        _write(roots["base"], "macros.xml",
               f'<macros><macro name="{MACRO}" class="turret"><component ref="turret_t"/></macro></macros>')
        # Active track runs (0,0,0) -> (-1,0,0); duration 1.0 s, so the hold is the last key.
        (roots["base"] / "geometry").mkdir(exist_ok=True)
        (roots["base"] / "geometry/turret_t.ANI").write_bytes(_ani_bytes(
            ("rotator", "turret_active", 2, 0, 0, 0, 0, 0x3F800000),
            key_data=_key((0.0, 0.0, 0.0), 0.0) + _key((-1.0, 0.0, 0.0), 1.0),
        ))
        return load_turrets(roots, roots, [MACRO])[MACRO]

    def _translation(self, turret: dict[str, object], rx: float, ry: float) -> list[float]:
        return evaluate(turret, rx, ry)["transform"]["translation"]

    def test_selection_joints_and_active_hold_compose_in_engine_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            turret = self._load(Path(tmp))
            # Smallest native hash, not lexical order.
            self.assertEqual(turret["selected_connection"], "con_b")
            # Rest pose: endpoint z3 + pitch z1 + held ANI (-1,0,0), no X negation.
            for got, want in zip(self._translation(turret, 0.0, 0.0), (-1.0, 0.0, 4.0)):
                self.assertAlmostEqual(got, want)
            # rotation_y +90deg: whole (-1,0,4) subtree, incl. the rotator's ANI
            # translation, turns about the yaw origin; +Z goes toward +X.
            for got, want in zip(self._translation(turret, 0.0, math.pi / 2), (4.0, 0.0, 1.0)):
                self.assertAlmostEqual(got, want)
            # rotation_x +90deg pivots at the pitch origin; +Z goes toward +Y.
            result = evaluate(turret, math.pi / 2, 0.0)
            for got, want in zip(result["transform"]["translation"], (-1.0, 3.0, 1.0)):
                self.assertAlmostEqual(got, want)
            for got, want in zip(result["transform"]["z"], (0.0, 1.0, 0.0)):
                self.assertAlmostEqual(got, want)

    def test_joint_segments_recompose_and_expose_yaw_geometry(self) -> None:
        from barrelposition_evaluator import ZERO, compose, joint_segments, rx, ry
        from yaw_rest_gate import yaw_geometry

        with tempfile.TemporaryDirectory() as tmp:
            turret = self._load(Path(tmp))
            seg = joint_segments(turret)
            x, y = 0.3, -1.2
            chain = seg["L"]
            for op in ((ZERO, rx(-x)), seg["G"], (ZERO, ry(y)), seg["H"]):
                chain = compose(chain, op)
            for got, want in zip(chain[0], self._translation(turret, x, y)):
                self.assertAlmostEqual(got, want)
            geometry = yaw_geometry(turret)
            # Pitch pivot = pitch offset z1 + rotator ANI (-1,0,0); rest aim is +Z.
            for got, want in zip(geometry["t_G"], (-1.0, 0.0, 1.0)):
                self.assertAlmostEqual(got, want)
            self.assertAlmostEqual(geometry["beta"], 0.0)

    def test_loop_with_moving_cubic_handles_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "turret_t.xml",
                   _component().replace("turret_active", "turretloop_active"))
            _write(roots["base"], "macros.xml",
                   f'<macros><macro name="{MACRO}" class="turret"><component ref="turret_t"/></macro></macros>')
            # Enum-5 keys equal at both ends, but key 0's out-handle x (raw slot 8) is 1.0.
            def cubic(time: float, out_x: float) -> bytes:
                return _candidate_key_record(
                    (0.0, 0.0, 0.0, 5, 5, 5, time, 0.0, out_x, *([0.0] * 15), 0, *([0.0] * 6), 0))
            (roots["base"] / "geometry").mkdir(exist_ok=True)
            (roots["base"] / "geometry/turret_t.ANI").write_bytes(_ani_bytes(
                ("rotator", "turretloop_active", 2, 0, 0, 0, 0, 0x3F800000),
                key_data=cubic(0.0, 1.0) + cubic(1.0, 0.0),
            ))
            turret = load_turrets(roots, roots, [MACRO])[MACRO]
            with self.assertRaises(EvaluatorError):
                evaluate(turret, 0.0, 0.0)

    def test_unsupported_restriction_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            turret = self._load(Path(tmp), pitch_restriction="translation_x")
            with self.assertRaises(EvaluatorError):
                evaluate(turret, 0.0, 0.0)


if __name__ == "__main__":
    unittest.main()
