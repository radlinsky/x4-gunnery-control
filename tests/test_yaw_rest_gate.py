#!/usr/bin/env python3
"""#166 A11 target-only yaw resting-point gate: closed-form contracts on synthetic geometry.

Pivot offset in the yaw frame is (κ lateral, f forward); ρ is the target's
horizontal distance from the yaw axis and s = sqrt(ρ² - κ²). Without zeroing the
fixed point has slope F' = -f/(s - f): it rests when s > 2f (|F'| < 1), oscillates
without settling when f < s < 2f, is held astern when 0 < s < f, and neither
exists when ρ < |κ|. The 1e-3 component zeroing and the zenith rule can add
resting points; the gate finds them as polynomial roots, not by scanning.
"""
from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from yaw_rest_gate import classify  # noqa: E402

IDENTITY = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))


def geometry(t_g, beta=0.0):
    return {"t_G": t_g, "t_H": (0.0, 0.0, 0.0), "R_H": IDENTITY, "beta": beta}


def target(rho, phi, height):
    return (rho * math.sin(phi), height, rho * math.cos(phi))


class YawRestGateTests(unittest.TestCase):
    def assert_yaws(self, got, want):
        self.assertEqual(len(got), len(want))
        for g, w in zip(sorted(got), sorted(want)):
            self.assertAlmostEqual(math.remainder(g - w, 2 * math.pi), 0.0, places=9)

    def test_two_geometric_solutions_leave_one_resting_point(self):
        # f < 0 and s < -f: the second fixed point exists but repels.
        result = classify(geometry((0.0, 1.0, -5.0)), target(3.0, 0.7, 20.0))
        self.assertEqual(result["class"], "one")
        self.assert_yaws(result["resting"], [0.7])
        self.assertEqual(result["traps"], [])
        self.assertTrue(result["state_independent"])

    def test_one_rest_with_a_trap_is_not_state_independent(self):
        # Target straight above the pivot at yaw 0: the zenith window rests there,
        # while just outside it the atan2 target jumps and holds a trap.
        result = classify(geometry((1.0, 1.0, 2.0), beta=math.pi / 2), (1.0, 20.0, 2.0))
        self.assertEqual(result["class"], "one")
        self.assert_yaws(result["resting"], [0.0])
        self.assertEqual(len(result["traps"]), 1)
        self.assertFalse(result["state_independent"])

    def test_target_on_the_pivot_does_not_divide_by_zero(self):
        result = classify(geometry((0.0, 1.0, 2.0)), (0.0, 1.0, 2.0))
        self.assertIn(result["class"], ("one", "several", "none"))

    def test_target_inside_forward_pivot_offset_is_a_trap_not_a_rest(self):
        result = classify(geometry((0.0, 1.0, 2.0)), target(1.0, 0.7, 20.0))
        self.assertEqual(result["class"], "none")
        self.assert_yaws(result["traps"], [0.7])

    def test_frame_by_frame_iteration_bounds_rest_at_s_equals_two_f(self):
        # f = 2: s = 5 gives F' = -2/3 (rests); s = 3 gives F' = -2 (oscillates).
        for s, want in ((5.0, "one"), (3.0, "none")):
            result = classify(geometry((0.0, 1.0, 2.0)), target(s, 0.7, 20.0))
            self.assertEqual(result["class"], want, s)
            self.assert_yaws(result["resting"] or result["traps"], [0.7])

    def test_target_inside_lateral_pivot_offset_spins(self):
        result = classify(geometry((1.5, 1.0, 0.0)), target(0.5, 0.7, 20.0))
        self.assertEqual((result["class"], result["resting"], result["traps"]), ("none", [], []))

    def test_zenith_rule_rests_at_zero_yaw(self):
        result = classify(geometry((0.0, 1.0, 0.0), beta=0.4), (0.0, 30.0, 0.0))
        self.assertEqual(result["class"], "one")
        self.assert_yaws(result["resting"], [0.0])

    def test_zeroing_window_holds_the_axis_aligned_repeller(self):
        # Target on the +Z axis inside the pivot circle: near yaw π the direction's
        # X component is below 1e-3, so the unstable solution becomes a second rest.
        result = classify(geometry((0.0, 1.0, -5.0)), target(3.0, 0.0, 20.0))
        self.assertEqual(result["class"], "several")
        self.assert_yaws(result["resting"], [0.0, -math.pi])

    def test_zeroing_boundary_is_exact(self):
        # Direction X component at yaw π just above / below 1e-3f of the unit vector.
        pivot = (0.0, 1.0, 5.0)
        for scale, want in ((1.0001, "one"), (0.9999, "several")):
            direction = (1e-3 * scale, 0.6, -0.8)
            n = math.sqrt(sum(v * v for v in direction))
            point = tuple(p + 10.0 * v / n for p, v in zip(pivot, direction))
            self.assertEqual(classify(geometry((0.0, 1.0, -5.0)), point)["class"], want, scale)


if __name__ == "__main__":
    unittest.main()
