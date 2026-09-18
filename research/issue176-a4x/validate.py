"""Focused checks for scorer.py (#176 A4x). ~4 min single process; run corpus.py first."""
import math
import os
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parents[1] / "research/issue173-scorer-audit")]
import scorer as s  # noqa: E402
import audit  # noqa: E402  (loads the accepted #167 turret pickle; memoizes the shared yaw gate)
from barrelposition_evaluator import joint_segments, load_turrets  # noqa: E402
from corpus import OFFICIAL_ANI, OFFICIAL_SRC, REQUIRED_SOURCE_SETS  # noqa: E402

I3, O = s.IDENTITY, s.ZERO
R = s.load()
angle = lambda a, b: math.degrees(math.acos(max(-1.0, min(1.0, sum(x * y for x, y in zip(a, b))))))  # noqa: E731


def at(az, el, r=1000.0):
    """Point at azimuth (about +Y, from +Z toward +X) and elevation, degrees."""
    a, e = math.radians(az), math.radians(el)
    return (r * math.cos(e) * math.sin(a), r * math.sin(e), r * math.cos(e) * math.cos(a))


def record(seg, arc):
    """Wrap an accepted (#173 synthetic) turret as corpus ops: L, leaf X, G, root Y, H."""
    fixed = lambda T: {"kind": "fixed", "transform": {"t": list(T[0]), "R": [list(r) for r in T[1]]}}  # noqa: E731
    return {"macro": "synthetic", "source": "synthetic" + str(id(seg)), "mechanical_class": "ordinary_xy",
            "ops": [fixed(seg["L"]), {"kind": "joint", "axis": "x", "limits": list(arc), "connection": "x"},
                    fixed(seg["G"]), {"kind": "joint", "axis": "y", "limits": None, "connection": "y"}, fixed(seg["H"])]}


def same(ref, new):
    return ref["state"] == new["state"] and (new["decision"] is None) == ref["state"].startswith("UNKNOWN")


def check_ops_consumption():
    accepted = {t["macro"]: t for t in audit.TURRETS}
    for t in accepted.values():
        a = s.accepted_turret(R["official:" + t["macro"]])
        assert (a["seg"], a["yaw"], a["arc"]) == (t["seg"], t["yaw"], tuple(t["arc"])), t["macro"]
    official = [r["macro"] for r in R.values() if r["source"] == "official"]
    loaded = load_turrets({n: OFFICIAL_SRC / n for n in REQUIRED_SOURCE_SETS},
                          {n: OFFICIAL_ANI / n for n in REQUIRED_SOURCE_SETS}, official)
    for m in official:
        assert s.segments(R["official:" + m])[2] == joint_segments(loaded[m]), m
    classes = {"ordinary_xy": ("y", False), "bounded_traverse": ("y", True), "reversed_xy": ("x", True), "rotation_z": ("z", False)}
    for r in R.values():
        leaf, root, _ = s.segments(r)
        assert (root["axis"], root["limits"] is not None) == classes[r["mechanical_class"]], r["macro"]
        assert leaf["axis"] == ("y" if root["axis"] == "x" else "x"), r["macro"]
    print(f"ops: 92 accepted turrets bit-identical, {len(official)} official segments == joint_segments, 288 axis/order ok")


def check_ordinary_agreement(stride=37):
    counts, n = Counter(), 0
    for i, (pop, name, t, pt) in enumerate(c for c in audit.cases() if c[0] != "stress"):
        if i % stride:
            continue
        ref = s.study.geometry(t, I3, O, pt)
        new = s.score(R["official:" + t["macro"]], pt)
        assert same(ref, new), (pop, name, t["macro"], ref["state"], new["state"])
        counts[pop, ref["state"], ref["yaws"]] += 1
        n += 1
    # #173 reference geometries: several rests (mixed/all in/all out), one+trap, no rest
    several = audit.synthetic("several", (-10.0, 60.0), t_g=(0.0, 1.0, -5.0))
    trap = audit.synthetic("trap", (-10.0, 90.0), t_g=(1.0, 1.0, 2.0), rg=audit.ry(math.pi / 2))
    none = audit.synthetic("none", (-10.0, 90.0), t_g=(0.0, 1.0, 2.0))
    want = [(several, (0.0, 9.0, 3.0), "IN_ARC"), (several, (0.0, 1.5, 3.0), "IN_ARC"),
            (several, (0.0, -2.0, 3.0), "OUT_OF_ARC"), (trap, (1.0, 20.0, 2.0), "UNKNOWN_one_trap"),
            (none, (math.sin(0.7), 1.0, math.cos(0.7)), "UNKNOWN_none_trap")]
    for t, pt, state in want:
        new = s.score(record(t["seg"], t["arc"]), pt)
        assert new["state"] == state and same(s.study.geometry(t, I3, O, pt), new), (t["macro"], pt, new["state"])
    print(f"ordinary: {n} audit cases + {len(want)} #173 yaw references agree with the accepted scorer")
    for k, v in sorted(counts.items()):
        print("  ", k, v)


def check_bounded():
    counts = Counter()
    for r in (r for r in R.values() if r["mechanical_class"] == "bounded_traverse"):
        leaf, root, _ = s.segments(r)
        unlimited = s.accepted_turret(r)  # same ops, root Y treated as unlimited by the accepted scorer
        for i, d in enumerate(s.study.DIRS):
            pt = tuple(300.0 * c for c in d)
            new = s.score(r, pt)
            counts[r["macro"], new["state"]] += 1
            if new["state"].startswith("UNKNOWN"):
                assert new["state"] == "UNKNOWN_root_limit_unwrap" and abs(abs(math.degrees(new["root"])) - 90) < 1e-3
                continue
            if new["decision"]:
                assert angle(new["aim"], new["d"]) < 1e-5
            request = math.atan2(new["d"][0], new["d"][2])  # root Y request; bounded records have beta = 0
            edge = min(abs(abs(math.degrees(request)) - b) for b in map(abs, root["limits"]))
            if s._in_arc(request, root["limits"]):
                if i % 3 == 0 and edge > 1e-3:
                    assert same(s.study.geometry(unlimited, I3, O, pt), new), (r["macro"], i)
            else:
                # clamped root: parks on the nearer limit, the leaf solves in that frame, the barrel cannot bear
                assert new["root"] in map(math.radians, root["limits"]), (r["macro"], i)
                assert not new["decision"] and angle(new["aim"], new["d"]) > 1e-4, (r["macro"], i)
    nk7 = R["swi:turret_m_ion_nk7_ball_macro"]
    for az, el, root_deg, state in ((60, 30, 60, "IN_ARC"), (80, 10, 70, "OUT_OF_ARC"), (175, 0, 70, "OUT_OF_ARC"),
                                    (-175, 0, -70, "OUT_OF_ARC"), (0, 75, 0, "OUT_OF_ARC")):
        out = s.score(nk7, at(az, el))
        assert out["state"] == state and abs(math.degrees(out["root"]) - root_deg) < 1e-4, (az, el, out)
    assert s.score(nk7, at(90, 0))["state"] == "OUT_OF_ARC"  # 140 deg span: clamped, no unwrap ambiguity
    ball = R["swi:turret_s_gauntlet_macro"]
    assert s.score(ball, at(90, 0))["state"] == "UNKNOWN_root_limit_unwrap"  # 180 deg span, request on a limit
    assert s.score(ball, at(89, 0))["state"] == "IN_ARC" and s.score(ball, at(91, 0))["state"] == "OUT_OF_ARC"
    assert s.score(ball, at(0, 90))["state"] == "IN_ARC"  # zenith: traced request 0, pitch 90 inside +/-90
    print("bounded:", dict(Counter(k[1] for k in counts.elements())))


def check_reversed():
    wall = R["swi:turret_m_wall_sith_macro"]
    leaf, root, _ = s.segments(wall)
    assert (root["axis"], root["limits"], leaf["axis"], leaf["limits"]) == ("x", [-50.0, 50.0], "y", [-20.0, 20.0])
    # u = (sin 19.5, cos 19.5 sin 45, cos 19.5 cos 45) from the fixed pivot: root X 45, leaf Y 19.5 -> reachable.
    # Read as Y-then-X (renamed by position) the yaw would be atan2(u_x, u_z) = 26.6 > 20: OUT.
    u = (math.sin(math.radians(19.5)), math.cos(math.radians(19.5)) * math.sqrt(0.5), math.cos(math.radians(19.5)) * math.sqrt(0.5))
    out = s.score(wall, tuple(1000.0 * c for c in u))
    assert out["state"] == "IN_ARC" and angle(out["aim"], out["d"]) < 1e-6, out
    assert abs(abs(math.degrees(out["root"])) - 45) < 1e-4 and abs(abs(math.degrees(out["leaf"])) - 19.5) < 1e-4
    assert math.degrees(math.atan2(u[0], u[2])) > 26
    for pt, state in ((at(0, 0), "IN_ARC"), (at(21, 0), "OUT_OF_ARC"), (at(0, 49), "IN_ARC"), (at(0, 51), "OUT_OF_ARC"),
                      (at(0, -49), "IN_ARC"), (at(180, 0), "OUT_OF_ARC")):
        assert s.score(wall, pt)["state"] == state, (pt, state)
    counts = Counter(s.score(wall, tuple(300.0 * c for c in d))["state"] for d in s.study.DIRS)
    print("reversed:", dict(counts))


def check_rotation_z():
    dish = R["swi:turret_arrestor_dish_macro"]
    leaf, root, seg = s.segments(dish)
    assert (root["axis"], root["limits"], leaf["axis"], leaf["limits"]) == ("z", None, "x", [-25.0, 25.0])

    def off(theta, clock, r):  # clock from +Y toward +X, the traced atan2(u.x, u.y) convention
        t, c = math.radians(theta), math.radians(clock)
        return (r * math.sin(t) * math.sin(c), r * math.sin(t) * math.cos(c), r * math.cos(t))

    # stable rest: one resting clock at the target clock, leaf request ~ off-axis angle
    for theta, r, state in ((10, 1e4, "IN_ARC"), (24, 1e4, "IN_ARC"), (26, 1e4, "OUT_OF_ARC"), (60, 1e4, "OUT_OF_ARC"),
                            (22, 20.0, "IN_ARC"), (80, 8.0, "OUT_OF_ARC")):
        for clock in range(0, 360, 15):
            out = s.score(dish, off(theta, clock, r))
            assert out["state"] == state and out["clocks"] == "one", (theta, r, clock, out)
            assert abs(math.remainder(out["root"] - math.radians(clock), 2 * math.pi)) < 1e-6, (theta, r, clock, out)
            if r == 1e4:
                assert abs(math.degrees(out["leaf"]) - theta) < 0.05, (theta, clock, out)
    # on-axis far targets: 1e-3f zeroing makes the projection degenerate, request 0 rests at clock 0
    assert s.score(dish, (0.0, 0.0, 1e4))["state"] == "IN_ARC" and s.score(dish, (0.0, 0.0, -1e4))["state"] == "OUT_OF_ARC"
    # hidden state / no rest: pivot f = 2.748 m along the clock; rho < 2f oscillates or holds astern -> UNKNOWN
    for rho in (1.0, 2.0, 4.0, 5.0):
        for clock in range(15, 360, 30):  # off-axis: an axis-aligned clock can rest inside the 1e-3f zeroing band
            out = s.score(dish, (rho * math.sin(math.radians(clock)), rho * math.cos(math.radians(clock)), 50.0))
            assert out["state"].startswith("UNKNOWN") and out["decision"] is None, (rho, clock, out)
    assert s.score(dish, (0.0, 0.0, 50.0))["state"].startswith("UNKNOWN")  # on axis, close: pivot holds the target astern
    # handedness-free: mirroring the target across either clock plane never changes the answer
    counts = Counter()
    for d in s.study.DIRS:
        for r in (30.0, 300.0, 3000.0):
            pt = tuple(r * c for c in d)
            out = s.score(dish, pt)
            assert out["state"] == s.score(dish, (-pt[0], pt[1], pt[2]))["state"] == s.score(dish, (pt[0], -pt[1], pt[2]))["state"]
            counts[r, out["state"]] += 1
    print("rotation_z:", dict(sorted(counts.items())))


if __name__ == "__main__":
    os.nice(10)
    check_ops_consumption()
    check_reversed()
    check_rotation_z()
    check_bounded()
    check_ordinary_agreement()
    print("PASS")
