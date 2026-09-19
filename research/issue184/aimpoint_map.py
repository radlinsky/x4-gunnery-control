"""Issue #184 A1 foundation: shared cases, hidden aimed-muzzle truth, class margins, method rules.

Research only. Reuses the accepted #176 pieces unchanged: the 288-turret A4x corpus and its ops
(`issue176-a4x/corpus.py`, `scorer.py`), the #167/#173 native query model and nearest-point
selection, authored target aim points and target boxes (`issue167-p3c/study.py`).

    python3 research/issue184/aimpoint_map.py            # print the class margins
    python3 research/issue184/aimpoint_map.py --selftest

The mapper under test sees only `oracle(case)`, the target box, the ship class and the firing-ship
box. `case["points"]` and `aimed_muzzles(case)` are hidden benchmark truth.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "research/issue176-a4x"), str(ROOT / "research/issue167-p3c")]
import corpus  # noqa: E402
import scorer  # noqa: E402
import sources  # noqa: E402
import study  # noqa: E402

SIZES = ("small", "medium", "large", "extralarge")
# ponytail: inference, not a slot census — each ship class may mount its own turret size and every
# smaller one. Conservative (a superset only widens the margin); replace with a ship-slot census if
# a class margin turns out too wide to be useful.
CLASS_SIZES = {"ship_s": SIZES[:1], "ship_m": SIZES[:2], "ship_l": SIZES[:3], "ship_xl": SIZES}
RADII = (10, 100, 1000, 10000, 100000)  # A2's close-to-stress firing distances (m)
UNKNOWN = None


# ---------------------------------------------------------------- offline class margins

def mount_size(record, components):
    """Authored size token on the turret component's `turret`-tagged mating connection."""
    element = components[record["component"].lower()][0]
    sizes = {z for c in element.iter("connection") for tags in [set((c.get("tags") or "").split())]
             if "turret" in tags for z in SIZES if z in tags}
    if len(sizes) != 1:
        raise corpus.CorpusError(f"{record['macro']}: mount size {sorted(sizes)}")
    return sizes.pop()


STEP = math.radians(0.5)  # joint sweep grid


def _angles(limits):
    lo, hi = (-math.pi, math.pi) if limits is None else map(math.radians, limits)
    n = max(1, math.ceil((hi - lo) / STEP))
    return [lo + (hi - lo) * k / n for k in range(n + 1)]


def reach(record):
    """Conservative max |aimed endpoint - mount| over every legal pose of the authored joints.

    Sweeps each joint over its authored limits on a STEP grid. A joint turned by at most STEP/2
    from a grid angle moves the endpoint at most |lever| * STEP/2, and the lever is bounded by the
    sum of fixed translation lengths, so adding that per joint keeps the result an upper bound."""
    joints = [op for op in record["ops"] if op["kind"] == "joint"]
    bound = sum(math.hypot(*op["transform"]["t"]) for op in record["ops"] if op["kind"] == "fixed")
    grids = [_angles(j["limits"]) for j in joints]
    index = np.stack(np.meshgrid(*(np.arange(len(g)) for g in grids), indexing="ij"), -1).reshape(-1, len(joints))
    p, k = np.zeros((len(index), 3)), 0
    for op in record["ops"]:  # position only: p <- p.R + t (compose's translation rule)
        if op["kind"] == "fixed":
            p = p @ np.asarray(op["transform"]["R"]) + op["transform"]["t"]
        else:
            mats = np.asarray([scorer.JOINT[op["axis"]](a) for a in grids[k]])
            p = np.einsum("ni,nij->nj", p, mats[index[:, k]])
            k += 1
    best = float(np.max(np.linalg.norm(p, axis=1)))
    return best + len(joints) * bound * STEP / 2


def class_margins(records, sizes):
    """{ship class: (margin m, macro that sets it)}. Assumes the mount lies inside the runtime ship box."""
    by_size = {z: (0.0, "") for z in SIZES}
    for key, record in records.items():
        z = sizes[key]
        by_size[z] = max(by_size[z], (reach(record), key))
    return {cls: max(by_size[z] for z in sizes) for cls, sizes in CLASS_SIZES.items()}


# ---------------------------------------------------------------- method rules (production inputs only)

def firing_box(lo, hi, margin):
    """Firing-ship method: runtime ship box expanded by the class margin."""
    return np.asarray(lo, float) - margin, np.asarray(hi, float) + margin


def inside(box, muzzle):
    return bool(np.all(box[0] <= muzzle) and np.all(muzzle <= box[1]))


def target_box(centre, half, scale):
    """Target-box method: search box with the target box's proportions, half-extents x `scale`.

    Authored aim points can sit outside the target box (#169): 68 of 88 in-scope turret surfaces, only
    along Y, needing up to 3.57x or 8.85 m, so `scale` is chosen from the A2 benchmark, not assumed."""
    return np.asarray(centre, float) - scale * np.asarray(half, float), np.asarray(centre, float) + scale * np.asarray(half, float)


def nearest(located, muzzle):
    """Target-box method: label X4's nearest-point rule must select from `muzzle`, or UNKNOWN.

    `located` is [(label, centre, radius)], each true point within `radius` of `centre`. Definite only
    when the farthest the winner can be is strictly nearer than the closest any rival can be. Whether
    `located` is complete enough to answer is the caller's A3 rule, not decided here."""
    d = [(float(np.linalg.norm(np.asarray(c, float) - muzzle)), r, label) for label, c, r in located]
    if not d:
        return UNKNOWN
    best = min(d, key=lambda x: x[0])
    far = best[0] + best[1]
    return best[2] if all(x is best or x[0] - x[1] > far for x in d) else UNKNOWN


# ---------------------------------------------------------------- shared benchmark cases

# #169 host classes: L/XL ships and station modules, the selectable destructible surface population.
HOSTS = {"ship_l", "ship_xl", "defencemodule", "connectionmodule", "production", "storage", "habitation",
         "dockarea", "pier", "buildmodule", "processingmodule", "welfaremodule"}
KIND = {"turret": "turret", "missileturret": "turret", "shieldgenerator": "shield", "engine": "engine"}


def _integrated(macro):
    """Resolved `hull@integrated`, following macro `ref` inheritance (#169)."""
    while macro is not None:
        hull = macro.find("properties/hull")
        if hull is not None and hull.get("integrated") is not None:
            return hull.get("integrated").lower() in ("1", "true")
        macro = sources.macro(macro.get("ref")) if macro.get("ref") else None
    return False


def scope(record, host_tags):
    """(kind, None) for a Gunnery Control target, else (kind, reason). #168/#169 generic rule."""
    cls = sources.component(record["component"]).get("class")
    if cls.startswith("ship_"):
        return "whole", None
    mating = [c for c in sources.connections(sources.component(record["component"])).values()
              if "component" in sources.tags(c)]
    if len(mating) != 1:
        return KIND[cls], "no unique mating connection"
    required = sources.tags(mating[0]) - {"component"}
    if not any(required <= t for t in host_tags):
        return KIND[cls], "no L/XL/station host" + (" (requires unhittable)" if "unhittable" in required else "")
    if _integrated(sources.macro(record["macro"])):
        return KIND[cls], "hull integrated"
    return KIND[cls], None


def targets():
    """Unique target components Gunnery Control can ask ENGAGEABLE about, with authored aim points and
    runtime-box centre/half-extents. An in-scope zero box fails loudly (#168: none in X4 9.00)."""
    study.init()
    referenced = {m.find("component").get("ref") for defs in sources.MACROS.values() for _r, m in defs
                  if m.find("component") is not None}
    host_tags = [sources.tags(c) for name in referenced if name in sources.COMPONENTS
                 for _r, comp in sources.COMPONENTS[name] if comp.get("class") in HOSTS
                 for c in sources.connections(comp).values() if "component" not in sources.tags(c)]
    kept = {}
    for r in study.CORPUS["records"]:
        if scope(r, host_tags)[1] is None:
            if max(r["H"]) == 0:
                raise sources.StudyError(f"in-scope zero box: {r['macro']}")
            kept.setdefault(r["component"], r)
    return list(kept.values())


def cases(records, sizes):
    """Deterministic cases: every target x rotation-cycled bearing x RADII, turrets round-robin.

    ponytail: the firing-ship runtime box is the mount point itself (a lower bound on a real hull);
    real firing-ship hull boxes and mounts are A2 work."""
    turrets = sorted(records)
    dirs = study.fibonacci(24)
    n = 0
    for target in targets():
        for i, direction in enumerate(dirs):
            for radius in RADII:
                key = turrets[n % len(turrets)]
                classes = [c for c, allowed in CLASS_SIZES.items() if sizes[key] in allowed]
                t_rot, f_rot = np.asarray(study.ROT[i % 24]), np.asarray(study.ROT[n % 24])
                mount = radius * np.asarray(direction) + np.asarray(target["C"]) @ t_rot
                yield dict(id=n, target=target["component"], turret=key, ship_class=classes[n % len(classes)],
                           rotation=f_rot, mount=mount, ship_box=(mount, mount),
                           box=(np.asarray(target["C"]), np.asarray(target["H"]), t_rot),
                           points=[np.asarray(p) @ t_rot for p in target["points"]])
                n += 1


def oracle(case):
    """The only view of the target a mapper gets: X4's quantised direction to the selected aim point."""
    pts = [tuple(map(float, p)) for p in case["points"]]
    return lambda u: study.Q(u, pts, [])


def aimed_muzzles(case, records):
    """Hidden truth: {aim point index: world muzzle} after the turret aims at that point.

    ponytail: ordinary_xy only (278 of 288) via the accepted #173 geometry; the 10 others give {}.
    IN_ARC only: an out-of-arc request is CANNOT BEAR territory and its unclamped pose is not real."""
    record = records[case["turret"]]
    if record["mechanical_class"] != "ordinary_xy":
        return {}
    turret, R, O = scorer.accepted_turret(record), case["rotation"], case["mount"]
    out = {}
    for i, p in enumerate(case["points"]):
        g = study.geometry(turret, tuple(tuple(map(float, r)) for r in R), tuple(map(float, O)), tuple(map(float, p)))
        if g["state"] == "IN_ARC":
            out[i] = O + np.asarray(g["muzzle"]) @ R
    return out


def load():
    records = scorer.load()
    components = corpus._index_xml([corpus.SWI_XML, corpus.OFFICIAL_SRC], "component")
    sizes = {k: mount_size(r, components) for k, r in records.items()}
    return records, class_margins(records, sizes), sizes


def selftest():
    a, b = np.zeros(3), np.array([10.0, 0, 0])
    assert nearest([("a", a, .1), ("b", b, .1)], np.array([1.0, 0, 0])) == "a"
    assert nearest([("a", a, 1), ("b", b, 1)], np.array([4.5, 0, 0])) is UNKNOWN  # uncertainty overlaps
    assert nearest([], a) is UNKNOWN
    box = firing_box((0, 0, 0), (1, 1, 1), 2)
    assert np.allclose(target_box((1, 0, 0), (1, 2, 0), 1.2)[1], (2.2, 2.4, 0))
    assert inside(box, np.array([-2.0, 3, 0])) and not inside(box, np.array([3.1, 0, 0]))

    assert _integrated(sources.macro("turret_xen_xl_battleship_01_mk1_macro"))  # #169 integrated turret
    assert not _integrated(sources.macro("turret_kha_l_beam_01_mk1_scenario_macro"))  # ref override kept

    records, margins, sizes = load()
    assert len(records) == 288 and set(sizes.values()) == set(SIZES)
    for case in cases(records, sizes):
        if case["turret"].startswith("official") and len(case["points"]) > 1:
            break
    q = oracle(case)(case["mount"])
    assert q is not None and abs(np.linalg.norm(q) - 1) < 1e-6
    reach_m = margins[case["ship_class"]][0]
    muzzles = aimed_muzzles(case, records)
    assert muzzles and all(np.linalg.norm(m - case["mount"]) <= reach_m for m in muzzles.values())
    print("selftest ok")


def main():
    if "--selftest" in sys.argv:
        return selftest()
    _records, margins, _sizes = load()
    for cls in CLASS_SIZES:
        print(f"{cls}: {margins[cls][0]:.2f} m  ({margins[cls][1]})")


if __name__ == "__main__":
    main()
