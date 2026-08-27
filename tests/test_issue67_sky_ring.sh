#!/usr/bin/env bash
set -euo pipefail

# Issue #67 goal-1 redesign (handoff docs/issue-67-arc-redesign-handoff.md §5-§6):
# the r15 Colossus ring could not answer goal 1 because its {-10,+90} lower
# limit coincides with deck-plane own-hull occlusion: every origin-outside /
# aim-inside pair was also line-of-fire blocked, and the ~0.04 deg split was
# inside measurement noise.
#
# r31 keeps the r16 shooter - Paranid L destroyer (ship_par_l_destroyer_01_a)
# con_turret_laser_l_01: turret_par_l_plasma_01_mk1_macro, authored band
# {-5,+80}. Beyond +80 degrees faces open sky from the top-deck mount
# (y=+98.2), so out-of-arc directions are NOT own-hull blocked: a refusal is
# attributable to the origin-based arc check, and a fire proves X4 engages via
# hittable aim points that cross an authored limit.
#
# The targets are the r16 fixture's A/B half: base-game Argon L destroyer 02
# (ship_arg_l_destroyer_02, con_turret_l_01, group_rear_up_mid) carrying the
# SAME sky parameters as the r16 K run, so the same two sky points ride a
# different hull. The mount has no quaternion (identity) and its 13.28383 m
# lever points straight up. Spawned under the xenon owner (naturally hostile;
# the r16 hostility mechanism, fail-closed on the mayattack census).
#
# The origin/aim split comes solely from the element's 13.28 m useaimtarget
# offset, so whole-degree margins force close placements (~270-300 m slant,
# near zenith, where the offset can be perpendicular to the line of fire).

python3 - <<'PY'
import math
import re
from pathlib import Path

# ---------------------------------------------------------------- helpers ----
def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def qnorm(q):
    length = math.sqrt(sum(value * value for value in q))
    return tuple(value / length for value in q)


def qconj(q):
    return (-q[0], -q[1], -q[2], q[3])


def qrot(q, vector):
    q = qnorm(q)
    result = qmul(qmul(q, (*vector, 0.0)), qconj(q))
    return result[:3]


def qaxis(axis, degrees):
    half = math.radians(degrees) / 2.0
    sine, cosine = math.sin(half), math.cos(half)
    return {
        "x": (sine, 0.0, 0.0, cosine),
        "y": (0.0, sine, 0.0, cosine),
        "z": (0.0, 0.0, sine, cosine),
    }[axis]


def qyaw(degrees):
    return qaxis("y", degrees)


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def scale(a, factor):
    return tuple(x * factor for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def length(v):
    return math.sqrt(dot(v, v))


def pitch(vector):
    return math.atan2(vector[1], math.hypot(vector[0], vector[2]))


def math_yxz(q):
    # Mathematical decomposition q = Ry(yaw) * Rx(pitch) * Rz(roll).
    x, y, z, w = qnorm(q)
    matrix = (
        (1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
        (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
        (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)),
    )
    mathematical_pitch = math.asin(max(-1.0, min(1.0, -matrix[1][2])))
    yaw = math.atan2(matrix[0][2], matrix[2][2])
    roll = math.atan2(matrix[1][0], matrix[1][1])
    return tuple(math.degrees(value) for value in (yaw, mathematical_pitch, roll))


def x4_spawn_quaternion(yaw, authored_pitch, authored_roll):
    # Correlated r13 live geometry proves that MD <rotation> retains yaw's sign
    # but applies pitch and roll opposite to this right-handed decomposition.
    return qmul(
        qmul(qyaw(yaw), qaxis("x", -authored_pitch)),
        qaxis("z", -authored_roll),
    )


# ------------------------------------------------- r13 regression anchor -----
surface_pos = (-263.2988, 21.30472, 320.1086)
surface_q = (0.6687521, -0.7221637, -0.1221243, 0.1278122)
aim_offset = (0.0, 13.28383, 0.0)
aim_local = add(surface_pos, qrot(surface_q, aim_offset))
arc_lower_limit = -math.radians(5.0)  # Paranid L plasma band {-5,+80}
lower_limit = arc_lower_limit

r13_weapon_pos = (295.7003, 118.8856, 808.6356)
r13_weapon_q = (-3.719e-7, 2.326e-7, 0.08715667, -0.9961947)
r13_cases = {
    0:   (4601.000,   698.629, -657.773, 180.0000,  -0.0000,   0.0000, -0.174922, -0.174161),
    30:  (3827.216,  2495.363, -974.588, 209.6216,  -4.9810,  -1.3178, -0.192773, -0.192415),
    60:  (2244.874,  3670.366,-1181.774, 239.6187,  -8.6492,  -4.9617, -0.211540, -0.211751),
    90:  ( 277.961,  3908.798,-1223.815, 270.0000, -10.0001, -10.0002, -0.226621, -0.227405),
    120: (-1546.491, 3146.770,-1089.446, 300.3813,  -8.6492, -15.0386, -0.234654, -0.235911),
    150: (-2739.620, 1588.468, -814.671, 330.3783,  -4.9809, -18.6824, -0.233614, -0.235232),
    180: (-2981.730, -348.563, -473.116,   0.0000,   0.0001, -20.0002, -0.223173, -0.224756),
    210: (-2207.946,-2145.297, -156.301,  29.6216,   4.9811, -18.6824, -0.205508, -0.206734),
    240: ( -625.604,-3320.300,   50.885,  59.6187,   8.6493, -15.0385, -0.185419, -0.186040),
    270: ( 1341.309,-3558.731,   92.925,  90.0000,  10.0002, -10.0001, -0.168843, -0.168828),
    300: ( 3165.761,-2796.704,  -41.443, 120.3813,   8.6493,  -4.9616, -0.160626, -0.160085),
    330: ( 4358.891,-1238.401, -316.218, 150.3784,   4.9810,  -1.3178, -0.162974, -0.162129),
}
correct_errors = []
wrong_errors = []
for distance, x, y, yaw, authored_pitch, authored_roll, live_origin, live_aim in r13_cases.values():
    root = (x, y, distance - 1.0)
    for sign_correct, errors in ((True, correct_errors), (False, wrong_errors)):
        if sign_correct:
            target_q = x4_spawn_quaternion(yaw, authored_pitch, authored_roll)
        else:
            target_q = qmul(qmul(qyaw(yaw), qaxis("x", authored_pitch)), qaxis("z", authored_roll))
        origin = add(root, qrot(target_q, surface_pos))
        aim = add(root, qrot(target_q, aim_local))
        predicted = (
            pitch(qrot(qconj(r13_weapon_q), sub(origin, r13_weapon_pos))),
            pitch(qrot(qconj(r13_weapon_q), sub(aim, r13_weapon_pos))),
        )
        errors.extend((predicted[0] - live_origin, predicted[1] - live_aim))
correct_rmse = math.sqrt(sum(value * value for value in correct_errors) / len(correct_errors))
wrong_rmse = math.sqrt(sum(value * value for value in wrong_errors) / len(wrong_errors))
assert correct_rmse < 0.00025, f"X4-sign model lost r13 live fit: {correct_rmse:.9f} rad"
assert wrong_rmse > 0.03, f"old positive-sign model unexpectedly fits r13: {wrong_rmse:.9f} rad"

# ----------------------------------------------------- r16 weapon frame ------
# Shipped source: assets/units/size_l/ship_par_l_destroyer_01.xml connection
# con_turret_laser_l_01, single-slot group group_front_up_mid2 on the top deck.
# CRITICAL: X4 stores connection-offset quaternions INVERTED (child->parent).
# Reported r16 rotation is the raw XML's conjugate; that sector->weapon transform
# matches the logged WEAPONPOSE rot_pitch=-0.25568 rad (= -14.648 deg) and
# empirically maps sector vectors to weapon-local under Python qrot.
weapon_pos = (0.0, 98.20842, 237.1827)
sector_to_weapon_q = qconj((-0.1274921, 0.0, 0.0, -0.9918396))
weapon_to_sector_q = qconj(sector_to_weapon_q)

# q4 regression: the reported rotation triple below is a spawn authoring input;
# sector_to_weapon_q is the separate frame transform used for pitch extraction.
q4_pstar = (500806.093750, 98.208412, -151.050034)
q4_root = (500709.719, 666.319, -474.757)
q4_q = x4_spawn_quaternion(29.1400, -80.8038, 75.8055)
q4_surface = add(q4_root, qrot(q4_q, surface_pos))
q4_aim = add(q4_root, qrot(q4_q, aim_local))
assert length(sub(q4_surface, (500821.500000, 391.954742, -184.100586))) < 0.02, (
    f"q4 source surface drifted by {length(sub(q4_surface, (500821.500000, 391.954742, -184.100586))):.6f} m"
)
origin_p = pitch(qrot(sector_to_weapon_q, sub(q4_surface, q4_pstar)))
aim_p = pitch(qrot(sector_to_weapon_q, sub(q4_aim, q4_pstar)))
assert abs(origin_p - 1.19958) < 1e-4, f"q4 live origin pitch drifted: {origin_p:.6f}"
assert abs(aim_p - 1.23709) < 1e-4, f"q4 live aim pitch drifted: {aim_p:.6f}"
old_origin_p = pitch(qrot(weapon_to_sector_q, sub(q4_surface, q4_pstar)))
assert abs(old_origin_p - 1.19958) > 0.15, f"q4 reversed origin unexpectedly fits: {old_origin_p:.6f}"

# --------------------------------------- r31 target geometry (Argon L) ------
# The r13 and q4 anchors above already consumed the K mount constants, so the
# swap to the Argon target happens here: from this point on surface_pos,
# surface_q, aim_local, d_vec, lever, the solver, and the spec cross-
# validation below all run on the Argon geometry. The K values remain the
# r13/q4 regression anchors.
surface_pos = (0.0, 43.25907, -308.1357)
surface_q = (0.0, 0.0, 0.0, 1.0)
aim_local = add(surface_pos, qrot(surface_q, aim_offset))

upper_limit = math.radians(80.0)
plasma_max_range = 600.0 * 13.2  # bullet_par_turret_l_plasma_01_mk1_macro

# Shooter hull AABB from the component <size> block.
shooter_center = (0.0, -0.4211273, 69.43697)
shooter_half = (181.9283, 146.8238, 272.7145)


def point_shooter_distance(point):
    delta = sub(point, shooter_center)
    outside = tuple(max(abs(d) - h, 0.0) for d, h in zip(delta, shooter_half))
    return length(outside)


d_vec = sub(aim_local, surface_pos)
lever = length(d_vec)
assert abs(lever - 13.28383) < 1e-4, f"unexpected aim lever {lever}"


def frame_direction(pitch_deg, azimuth_deg):
    p, a = math.radians(pitch_deg), math.radians(azimuth_deg)
    return (math.cos(p) * math.sin(a), math.sin(p), math.cos(p) * math.cos(a))


def rotation_between(source, target):
    s, t = qnorm((*source, 0.0))[:3], qnorm((*target, 0.0))[:3]
    c = max(-1.0, min(1.0, dot(s, t)))
    axis = cross(s, t)
    axis_len = length(axis)
    if axis_len < 1e-9:
        return (0.0, 0.0, 0.0, 1.0) if c > 0 else (1.0, 0.0, 0.0, 0.0)
    axis = tuple(value / axis_len for value in axis)
    half = math.acos(c) / 2.0
    sine = math.sin(half)
    return (axis[0] * sine, axis[1] * sine, axis[2] * sine, math.cos(half))


def solve_placement(label, origin_pitch_deg, aim_pitch_deg, azimuth_deg, origin_range):
    """Place a target whose element origin sits on one weapon-frame ray and
    whose useaimtarget lands exactly on a neighbouring ray."""
    u_o = frame_direction(origin_pitch_deg, azimuth_deg)
    u_a = frame_direction(aim_pitch_deg, azimuth_deg)
    # Ray construction happens in the weapon frame; positions become world
    # offsets through the weapon mount transform (shooter spawns at identity).
    origin_local = scale(u_o, origin_range)
    rho = dot(origin_local, u_a)
    assert rho > 0.0, f"{label}: aim ray behind weapon"
    closest = scale(u_a, rho)
    needed = sub(closest, origin_local)
    needed_len = length(needed)
    assert needed_len <= lever - 0.05, (
        f"{label}: needs {needed_len:.3f} m lever, element offers {lever:.3f} m"
    )
    base_q = rotation_between(d_vec, needed)
    if needed_len < 1e-6:
        base_q = (0.0, 0.0, 0.0, 1.0)
    best = None
    for step in range(96):
        half = math.radians(360.0 / 96 * step) / 2.0
        axis = qnorm((*needed, 0.0))[:3] if needed_len >= 1e-6 else (0.0, 0.0, 1.0)
        sine = math.sin(half)
        spin = (axis[0] * sine, axis[1] * sine, axis[2] * sine, math.cos(half))
        target_q = qmul(spin, base_q)
        # P*-relative element-origin offset = qrot(weapon_to_sector_q, origin_local);
        # full target-root offset from P* = that origin offset - qrot(target_q, surface_pos).
        origin_world = add(weapon_pos, qrot(weapon_to_sector_q, origin_local))
        root = sub(origin_world, qrot(target_q, surface_pos))
        separation = point_shooter_distance(root)
        for _, placed_root, _q in solved:
            separation = min(separation, length(sub(root, placed_root)))
        if best is None or separation > best[0]:
            best = (separation, root, target_q)
    separation, root, target_q = best
    origin = add(root, qrot(target_q, surface_pos))
    aim = add(root, qrot(target_q, aim_local))
    solved.append((label, root, target_q))
    return {
        "label": label,
        "kind": label.split("-")[0],
        "origin": origin,
        "aim": aim,
        "root": root,
        "q": target_q,
        "separation": separation,
    }


solved = []
targets = []
# Single straddle: origin >= 80 + 1.25 deg, aim <= 80 - 1.25 deg. Slant range
# stays under the ~303 m ceiling implied by the 13.28 m lever at a 2.5 deg gap.
# Near-zenith geometry forces every possible straddle element into a small sky
# basket, and 843 m Argon hulls there would occlude each other's lines of
# fire, so replication comes from re-runs (r11->r12 reproduced identically
# across processes), not from intra-run clustering.
# Azimuth 227 (not the r16 K azimuth 20): at 20 the Argon aim point's line of
# fire crosses the target's own part_main OBB (verified below); at 227 the aim
# LOS clears the hull.
targets.append(solve_placement("straddle-0", 81.25, 78.75, 227.0, 296.0))
# Positive control: fully inside the arc, mid elevation, far away -> MUST
# fire; proves the rig engages at all. No separate out-of-arc negative control:
# r11/r12/r15 already showed the ENGINE itself reporting non-engageable on
# out-of-arc origins, so "X4 ignores arcs" is excluded by prior live evidence.
targets.append(solve_placement("positive", 70.0, 69.5, 200.0, 1500.0))

# ------------------------------------------------------------- gate checks ---
min_margin_out = math.radians(1.0)
min_margin_in = math.radians(1.0)
labels_by_kind = {}

for entry in targets:
    label = entry["label"]
    kind = label.split("-")[0]
    origin_w = qrot(sector_to_weapon_q, sub(entry["origin"], weapon_pos))
    aim_w = qrot(sector_to_weapon_q, sub(entry["aim"], weapon_pos))
    origin_p, aim_p = pitch(origin_w), pitch(aim_w)
    if kind == "straddle":
        assert origin_p - upper_limit >= min_margin_out, (
            f"{label}: origin margin {math.degrees(origin_p - upper_limit):.3f} deg"
        )
        assert upper_limit - aim_p >= min_margin_in, (
            f"{label}: aim margin {math.degrees(upper_limit - aim_p):.3f} deg"
        )
    elif kind == "positive":
        assert lower_limit + math.radians(10.0) <= aim_p <= upper_limit - math.radians(10.0)
        assert lower_limit + math.radians(10.0) <= origin_p <= upper_limit - math.radians(10.0)
    elif kind == "negative":
        assert origin_p >= upper_limit + math.radians(3.0)
        assert aim_p >= upper_limit + math.radians(3.0)
    else:
        raise AssertionError(f"unknown kind {kind}")
    # Whole-degree design intent: report the realised margins.
    entry["origin_pitch"] = math.degrees(origin_p)
    entry["aim_pitch"] = math.degrees(aim_p)
    range_to_aim = length(sub(entry["aim"], weapon_pos))
    assert range_to_aim < plasma_max_range * 0.95, f"{label}: aim beyond range gate"
    # Sky-clearance bound (inference, not mesh-proven): both designated points
    # must sit well above the horizon from the top-deck mount.
    world_o_elev = math.degrees(pitch(sub(entry["origin"], weapon_pos)))
    world_a_elev = math.degrees(pitch(sub(entry["aim"], weapon_pos)))
    assert world_a_elev >= 45.0, f"{label}: aim only {world_a_elev:.1f} deg above horizon"
    assert world_o_elev >= 45.0, f"{label}: origin only {world_o_elev:.1f} deg above horizon"
    # Element points must clear the shooter hull AABB by a wide margin.
    assert point_shooter_distance(entry["origin"]) >= 200.0, f"{label}: origin hugs shooter hull"
    assert point_shooter_distance(entry["aim"]) >= 200.0, f"{label}: aim hugs shooter hull"

roots = [entry["root"] for entry in targets]
min_pair = min(
    length(sub(first, second))
    for index, first in enumerate(roots)
    for second in roots[index + 1:]
)
assert min_pair >= 1000.0, f"target roots crowd to {min_pair:.1f} m"

# ------------------------------------------- target-hull clearance (r31) ----
# The r16 gates never modelled the target hull; r31 adds the one physical
# guarantee this fixture needs: the designated AIM point sits outside the
# target's collidable part_main OBB and the line of fire to it is clear of
# that hull. part_main is the ONLY collidable part of ship_arg_l_destroyer_02
# (every other part is nocollision). Ship-frame OBB: part <size> block
# (half-extents 211.9066, 95.03001, 421.7478; centre shifted through the
# ConnectionForpart_main offset (0,-13.83512,-129.9827)) ->
# centre (-0.0002098083, -41.89881, -15.8806).
tgt_obb_c = (-0.0002098083, -41.89881, -15.8806)
tgt_obb_h = (211.9066, 95.03001, 421.7478)

def point_obb_exterior(p, c, h, q):
    local = qrot(qconj(q), sub(p, c))
    return tuple(max(abs(local[i]) - h[i], 0.0) for i in range(3))

def segment_hits_obb(p0, p1, c, h, q):
    a = qrot(qconj(q), sub(p0, c))
    b = qrot(qconj(q), sub(p1, c))
    d = sub(b, a)
    lo, hi = 0.0, 1.0
    for i in range(3):
        if abs(d[i]) < 1e-9:
            if abs(a[i]) > h[i]:
                return True
        else:
            t1 = (-h[i] - a[i]) / d[i]
            t2 = (h[i] - a[i]) / d[i]
            if t1 > t2:
                t1, t2 = t2, t1
            lo, hi = max(lo, t1), min(hi, t2)
            if lo > hi:
                return False
    return True

for entry in targets:
    world_c = add(entry["root"], qrot(entry["q"], tgt_obb_c))
    aim_clear = length(point_obb_exterior(entry["aim"], world_c, tgt_obb_h, entry["q"]))
    assert aim_clear >= 2.0, (
        f"{entry['label']}: aim point only {aim_clear:.2f} m beyond the target hull OBB"
    )
    assert not segment_hits_obb(weapon_pos, entry["aim"], world_c, tgt_obb_h, entry["q"]), (
        f"{entry['label']}: line of fire to the aim point crosses the target hull OBB"
    )

# ------------------------------------------- authoring transform conversion --
derived = {}
for index, entry in enumerate(targets):
    yaw, mathematical_pitch, mathematical_roll = math_yxz(entry["q"])
    key = {"straddle-0": 0, "straddle-1": 1, "straddle-2": 2,
           "positive": 100, "negative": 200}[entry["label"]]
    root_offset_pstar = sub(entry["root"], weapon_pos)  # P*-relative placement offset
    expected = (
        entry["root"][2] + 1.0,
        entry["root"][0],
        entry["root"][1],
        yaw % 360.0,
        -mathematical_pitch,
        -mathematical_roll,
        root_offset_pstar[0],
        root_offset_pstar[1],
        root_offset_pstar[2],
    )
    derived[key] = expected
    print(
        f"SKY SURVEY A {key:03d}: distance={expected[0]:.3f} x={expected[1]:.3f} "
        f"y={expected[2]:.3f} yaw={expected[3]:.4f} pitch={expected[4]:.4f} "
        f"roll={expected[5]:.4f} | origin_pitch={entry['origin_pitch']:.3f} "
        f"aim_pitch={entry['aim_pitch']:.3f} sep={entry['separation']:.0f} "
        f"| p*-offset ox={expected[6]:.3f} oy={expected[7]:.3f} oz={expected[8]:.3f}"
    )
print(f"min pairwise root distance: {min_pair:.1f} m")

# ------------------------------------------------- spec cross-validation -----
spec_path = Path("testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua")
text = spec_path.read_text(encoding="utf-8")
number = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)"
pattern = re.compile(
    rf'{{ label = "SKY SURVEY A (\d{{3}})",.*?'
    rf'count = 1, distance = ({number}), x = ({number}), y = ({number}), spread = 0,\s*'
    rf'ox = ({number}), oy = ({number}), oz = ({number}),\s*'
    rf'yaw = ({number}), pitch = ({number}), roll = ({number}),\s*'
    rf'preserveOrientation = true,',
    re.S,
)
actual = {
    int(angle): tuple(float(value) for value in values)
    for angle, *values in pattern.findall(text)
}
assert sorted(actual) == sorted(derived), (
    f"expected source-derived survey keys {sorted(derived)}, found {sorted(actual)}"
)

assert 'id      = "issue-67-argon-sky-survey-r32"' in text
assert text.count('geometryCase = "arc_split"') == 1
assert text.count('geometryCase = "positive_control"') == 1
assert "positiveControl" not in text
assert "enabled = false" in text, "repository survey fixture must remain disabled"
assert 'shipMacro       = "ship_par_l_destroyer_01_a_macro"' in text
assert 'turretGroup     = "group_front_up_mid2"' in text
assert 'expectedTurrets = 1' in text
assert '"turret_par_l_plasma_01_mk1_macro"' in text

for key, expected in derived.items():
    distance, x, y, ox, oy, oz, authored_yaw, authored_pitch, authored_roll = actual[key]
    error = abs((authored_yaw - expected[3] + 180.0) % 360.0 - 180.0)
    assert error <= 0.001, (
        f"survey {key:03d} yaw is guessed/drifted: spec={authored_yaw:.6f}, "
        f"derived={expected[3]:.6f}, error={error:.6f}"
    )
    for observed, want, name in zip(
        (distance, x, y, authored_pitch, authored_roll), expected[:3] + expected[4:],
        ("distance", "x", "y", "pitch", "roll"),
    ):
        tolerance = 0.001 if name in ("pitch", "roll") else 0.002
        assert abs(observed - want) <= tolerance, (
            f"survey {key:03d} {name} is guessed/drifted: spec={observed:.6f}, "
            f"derived={want:.6f}"
        )
    # P*-relative surface_mask offsets: independently locked coordinate frame.
    for observed, want, name in zip(
        (ox, oy, oz), expected[6:], ("ox", "oy", "oz")
    ):
        assert abs(observed - want) <= 0.002, (
            f"survey {key:03d} {name} is guessed/drifted: spec={observed:.6f}, "
            f"derived={want:.6f}"
        )

    # Re-evaluate rounded authored values through every fixture gate.
    authored_q = x4_spawn_quaternion(authored_yaw, authored_pitch, authored_roll)
    authored_root = (x, y, distance - 1.0)
    origin = add(authored_root, qrot(authored_q, surface_pos))
    aim = add(authored_root, qrot(authored_q, aim_local))
    kind = "straddle" if key < 100 else ("positive" if key == 100 else "negative")
    origin_p = pitch(qrot(sector_to_weapon_q, sub(origin, weapon_pos)))
    aim_p = pitch(qrot(sector_to_weapon_q, sub(aim, weapon_pos)))
    if kind == "straddle":
        assert origin_p - upper_limit >= min_margin_out
        assert upper_limit - aim_p >= min_margin_in
    elif kind == "positive":
        assert lower_limit + math.radians(10.0) <= aim_p <= upper_limit - math.radians(10.0)
    else:
        assert origin_p >= upper_limit + math.radians(3.0)
        assert aim_p >= upper_limit + math.radians(3.0)
    assert length(sub(aim, weapon_pos)) < plasma_max_range * 0.95

print(
    "issue 67 Paranid sky-survey math passed "
    f"(r13 live-fit RMSE={correct_rmse:.9f} rad; rejected model={wrong_rmse:.9f} rad)"
)
PY
