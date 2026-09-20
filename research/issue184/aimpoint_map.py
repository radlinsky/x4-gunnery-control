"""Issue #184 A2 benchmark foundation: real firing ships and targets, grouped cases, hidden aimed-muzzle
truth, the two A3 box inputs, and the scorer; plus the A3 minimal mappers for both methods.

A2 reuses the accepted #176 pieces unchanged: the 288-turret A4x corpus and its ops
(`issue176-a4x/corpus.py`, `scorer.py`), the #167/#173 native query model, nearest-point selection,
runtime-box reconstruction, authored aim points and target boxes (`issue167-p3c/`).

    python3 research/issue184/aimpoint_map.py            # A2 summary
    python3 research/issue184/aimpoint_map.py --selftest
    python3 research/issue184/aimpoint_map.py --a3 [--every N] [--jobs 4]   # A3 benchmark, every Nth case
    python3 research/issue184/aimpoint_map.py --a41 [--every N] [--jobs 4]  # A4.1 corner audit (boundary cases)
    python3 research/issue184/aimpoint_map.py --a42 [--jobs 4]              # A4.2 switch-boundary comparison
    python3 research/issue184/aimpoint_map.py --a43 [--jobs 4]              # A4.3 phase 1 (19 cases)
    python3 research/issue184/aimpoint_map.py --a43r [--jobs 4]             # A4.3 phase 2 adaptive rescue
    python3 research/issue184/aimpoint_map.py --a43f [--jobs 4]             # A4.3 phase 3 uncertainty fallback
    python3 research/issue184/aimpoint_map.py --a43h [--jobs 4]             # A4.3 phase 4 hull coverage map
    python3 research/issue184/aimpoint_map.py --a43a [--jobs 4]             # A4.3 phase 5 angular-spread search
    python3 research/issue184/aimpoint_map.py --a6   [--jobs 4]             # A6 gap-only stopping-rule trace

A mapper under test sees only `view(case)`. Aim points, turret, mount and `aimed_muzzles` are hidden truth.
"""
from __future__ import annotations

import itertools
import json
import math
import os
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from multiprocessing import Pool
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "research/issue176-a4x"), str(ROOT / "research/issue167-p3c")]
import corpus  # noqa: E402
import scorer  # noqa: E402
import sources  # noqa: E402
import study  # noqa: E402

CLASSES = ("ship_s", "ship_m", "ship_l", "ship_xl")  # firing-ship classes Gunnery Control supports
UNKNOWN = None


# ---------------------------------------------------------------- offline class margins

STEP = math.radians(0.5)  # joint sweep grid


def _angles(limits):
    lo, hi = (-math.pi, math.pi) if limits is None else map(math.radians, limits)
    n = max(1, math.ceil((hi - lo) / STEP))
    return [lo + (hi - lo) * k / n for k in range(n + 1)]


def sweep(record):
    """(muzzle positions in the turret frame over every legal pose on the STEP grid, between-grid allowance).

    A joint turned by at most STEP/2 from a grid angle moves the endpoint at most |lever| * STEP/2, and the
    lever is bounded by the sum of fixed translation lengths, so any legal muzzle lies within the
    allowance of a sampled one. Rigid mounting preserves that distance."""
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
    return p, len(joints) * bound * STEP / 2


def class_margins(mounts, records):
    """{class: (margin, sampled overflow, (ship, mount, turret))}: the largest distance any legal muzzle of any
    compatible turret on any real mount can lie outside its ship's runtime box (per-axis, as `firing_box`
    grows it), plus that turret's between-grid allowance."""
    by_turret, best = {}, {cls: (0.0, 0.0, None) for cls in CLASSES}
    for m in mounts:
        for k in m["turrets"]:
            by_turret.setdefault(k, []).append(m)
    for k, ms in sorted(by_turret.items()):
        p, allowance = sweep(records[k])
        extent = {}
        for m in ms:
            t, R = m["frames"][k]
            if R.tobytes() not in extent:
                q = p @ R
                extent[R.tobytes()] = q.min(0), q.max(0)
            q_lo, q_hi = extent[R.tobytes()]
            over = max(0.0, float(np.max(np.concatenate([m["box"][0] - (q_lo + t), q_hi + t - m["box"][1]]))))
            if over + allowance > best[m["cls"]][0]:
                best[m["cls"]] = (over + allowance, over, (m["ship"], m["name"], k))
    return best


# ---------------------------------------------------------------- method rules (production inputs only)

def firing_box(lo, hi, margin):
    """Firing-ship method: runtime ship box expanded by the class margin."""
    return np.asarray(lo, float) - margin, np.asarray(hi, float) + margin


def inside(box, muzzle):
    return bool(np.all(box[0] <= muzzle) and np.all(muzzle <= box[1]))


TARGET_PAD_Y = 8.86  # m: the #184 A2 target-box pad, justified by `padding()` over the accepted targets


def target_box(centre, half):
    """Target-box method search box (target frame): the runtime box plus TARGET_PAD_Y on +Y only.

    Authored aim points can sit outside the target box (#169), only ever along +Y; see `padding()`."""
    c, h = np.asarray(centre, float), np.asarray(half, float)
    return c - h, c + h + (0, TARGET_PAD_Y, 0)


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


def _attach(child, mating, parent, conn):
    """Child component frame -> parent component frame, the way `sources.macro_box` attaches a child."""
    return sources.compose(sources._inverse(sources.conn_world(child, mating)), sources.conn_world(parent, conn))


def scope(record, hosts):
    """(kind, reason, R): R is the target's real orientation in its host frame (identity for whole ships),
    reason None for a Gunnery Control target. #168/#169 generic rule; the host is the first compatible one."""
    comp = sources.component(record["component"])
    cls = comp.get("class")
    if cls.startswith("ship_"):
        return "whole", None, np.eye(3)
    mating = [c for c in sources.connections(comp).values() if "component" in sources.tags(c)]
    if len(mating) != 1:
        return KIND[cls], "no unique mating connection", None
    required = sources.tags(mating[0]) - {"component"}
    host = next(((h, c) for t, h, c in hosts if required <= t), None)
    if host is None:
        return KIND[cls], "no L/XL/station host" + (" (requires unhittable)" if "unhittable" in required else ""), None
    if _integrated(sources.macro(record["macro"])):
        return KIND[cls], "hull integrated", None
    return KIND[cls], None, np.asarray(_attach(comp, mating[0], *host)[1])


def targets():
    """Unique official target components Gunnery Control can ask ENGAGEABLE about, with authored aim points,
    runtime-box centre/half-extents, kind and real mounted orientation `R`. An in-scope zero box fails loudly
    (#168: none in X4 9.00)."""
    study.init()
    referenced = {m.find("component").get("ref") for defs in sources.MACROS.values() for _r, m in defs
                  if m.find("component") is not None}
    hosts = [(sources.tags(c), comp, c) for name in sorted(referenced) if name in sources.COMPONENTS
             for rel, comp in sources.COMPONENTS[name] if comp.get("class") in HOSTS and not rel.startswith(SWI)
             for _n, c in sorted(sources.connections(comp).items()) if "component" not in sources.tags(c)]
    kept = {}
    for r in study.CORPUS["records"]:
        kind, reason, R = scope(r, hosts)
        if reason is None:
            if max(r["H"]) == 0:
                raise sources.StudyError(f"in-scope zero box: {r['macro']}")
            kept.setdefault(r["component"], {**r, "kind": kind, "R": R})
    return list(kept.values())


def padding(targets):
    """Smallest search-box growth that contains every authored aim point, per target (target frame):
    proportional scale versus a +Y-only pad. `outside_other` counts points outside the box off +Y."""
    rows = []
    for t in targets:
        C, H, P = np.asarray(t["C"]), np.asarray(t["H"]), np.asarray(t["points"])
        excess = np.abs(P - C) - H
        scale = max(1.0, float(np.max(np.where(H > 0, np.abs(P - C) / np.where(H > 0, H, 1), 1))))
        pad = max(0.0, float(np.max(P[:, 1] - C[1] - H[1])))
        other = int(np.sum(np.delete(excess, 1, axis=1) > 0) + np.sum(C[1] - H[1] - P[:, 1] > 0))
        rows.append(dict(target=t["component"], scale=scale, pad=pad, outside_other=other,
                         pad_volume=(2 * H[1] + TARGET_PAD_Y) / (2 * H[1])))
    return rows


# ---------------------------------------------------------------- real firing ships

SWI_ASSETS = ROOT / ".x4-research-cache/issue184/swi_assets"  # extract_swi_assets.py
SWI = "swi/"


def _index_swi_ships():
    """Index SWI 0.9.1 HF asset XML beside the official sources so SWI ships resolve. Official XML stays
    vanilla: SWI `<diff>` patches and same-name replacements are skipped. -> Counter of skipped files/names."""
    if any(rel.startswith(SWI) for defs in sources.MACROS.values() for rel, _m in defs):
        raise RuntimeError("SWI already indexed")
    official = set(sources.COMPONENTS) | set(sources.MACROS)
    skipped = Counter()
    for p in sorted(SWI_ASSETS.rglob("*.xml")):
        try:
            root = ET.parse(p).getroot()
        except ET.ParseError:
            skipped["SWI asset XML: unparseable file"] += 1
            continue
        skipped["SWI asset XML: <diff> patch of official XML (not applied)"] += root.tag == "diff"
        index = {"components": sources.COMPONENTS, "macros": sources.MACROS}.get(root.tag)
        for e in root if index is not None else ():
            if e.get("name") in official:
                skipped["SWI asset XML: replaces an official definition (kept official)"] += 1
            else:
                index.setdefault(e.get("name"), []).append((SWI + p.relative_to(SWI_ASSETS).as_posix(), e))
    if not skipped:
        raise RuntimeError(f"no SWI asset XML under {SWI_ASSETS}: run extract_swi_assets.py")
    return skipped


def _mating(comp):
    """(connection, inferred): the unique `component`-tagged connection (accepted rule). Inference for the
    SWI turrets that omit that token (swi-091-turret-geometry.md): their unique `turret`-tagged one."""
    conns = sources.connections(comp).values()
    for token, inferred in (("component", False), ("turret", True)):
        found = [c for c in conns if token in sources.tags(c)]
        if found:
            return (found[0], inferred) if len(found) == 1 else (None, None)
    return None, None


def firing_mounts(records, components):
    """Real turret mounts of real firing ships (official 9.00 + SWI 0.9.1 HF, first macro per component), each
    with its ship's runtime box and the ordinary_xy corpus turrets whose mating tags it accepts. Official ships
    take official turrets only. -> (mounts, Counter of exclusion reasons, inferred-mating turret count)."""
    excluded, fit = Counter(), {}
    for key, r in sorted(records.items()):
        conn, inferred = _mating(components[r["component"].lower()][0])
        if r["mechanical_class"] != "ordinary_xy":
            excluded["turret: not ordinary_xy (no accepted aimed-muzzle truth)"] += 1
        elif conn is None:
            excluded["turret: no unique mating connection"] += 1
        else:
            fit[key] = (sources.tags(conn) - {"component"}, components[r["component"].lower()][0], conn, inferred)
    ships = {}
    for name, defs in sorted(sources.MACROS.items()):
        m = defs[0][1]
        if len(defs) == 1 and m.get("class") in CLASSES and m.find("component") is not None:
            ships.setdefault(m.find("component").get("ref"), (name, m.get("class"), defs[0][0].startswith(SWI)))
    mounts, used = [], set()
    for cname, (macro, cls, swi) in sorted(ships.items()):
        source = "swi" if swi else "official"
        try:
            comp, box = sources.component(cname), sources.macro_box(macro)
            found = []
            for conn_name, conn in sorted(sources.connections(comp).items()):
                t = sources.tags(conn)
                if "turret" not in t or "component" in t:
                    continue
                keys = [k for k, f in fit.items() if f[0] <= t]
                foreign = [k for k in keys if not swi and not k.startswith("official:")]
                excluded["pair: SWI turret on an official ship"] += len(foreign)
                keys = [k for k in keys if k not in foreign]
                if keys:
                    found.append(dict(ship=macro, cls=cls, source=source, box=tuple(map(np.asarray, box)),
                                      name=conn_name, turrets=keys,
                                      frames={k: tuple(map(np.asarray, _attach(fit[k][1], fit[k][2], comp, conn)))
                                              for k in keys}))
        except (sources.StudyError, KeyError):
            excluded[f"ship: {source} {cls} runtime box or mount unresolved"] += 1
            continue
        if not found:
            excluded[f"ship: {source} {cls} has no mount a corpus turret fits"] += 1
        mounts += found
        used.update(k for m in found for k in m["turrets"])
    excluded["turret: fits no real ship mount"] += len(set(fit) - used)
    inferred = sum(fit[k][3] for k in used)
    return mounts, excluded, inferred


# ---------------------------------------------------------------- benchmark cases

GAPS = {"close": (10, 100), "ordinary": (1000, 2500, 5000), "stress": (20000, 100000)}  # min clearance (m)
BOUNDARY_GAPS = (100, 1000)
BEARINGS = 8


def cases(targets, mounts):
    """Deterministic A2 cases. Real groups use real targets in real orientations; mount, turret and ship
    rotation cycle with the case id. The firing ship is placed so its whole box clears the target's bounding
    sphere by at least the gap; nothing here looks at a muzzle position.

    close/ordinary/stress: bearing from the target box centre. boundary: bearings in the perpendicular
    bisector plane of the target's nearest pair of authored aim points. artificial: #167 synthetic
    two-point targets (`study.SYN`) with the mount at the synthetic query position."""
    n = 0

    def case(group, name, C, H, t_rot, points, O=None, anchor=None, direction=None, reach=0.0, gap=0.0):
        nonlocal n
        mount = mounts[n % len(mounts)]
        turret = mount["turrets"][(n // len(mounts)) % len(mount["turrets"])]
        f_rot = np.asarray(study.ROT[n % 24])
        t_m, R_m = mount["frames"][turret]
        lo, hi = mount["box"]
        if O is None:
            ship_reach = np.linalg.norm(hi - lo) / 2 + np.linalg.norm(t_m - (lo + hi) / 2)
            O = anchor + np.asarray(direction) * (reach + ship_reach + gap)
        out = dict(id=n, group=group, gap=gap, target=name, ship=mount["ship"], ship_class=mount["cls"],
                   source=mount["source"], mount=mount["name"], turret=turret, ship_box=(lo, hi),
                   rotation=f_rot, position=O - t_m @ f_rot, origin=O, frame=R_m @ f_rot,
                   box=(np.asarray(C, float), np.asarray(H, float), t_rot), points=points)
        n += 1
        return out

    dirs = study.fibonacci(BEARINGS)
    for group, gaps in GAPS.items():
        for t in targets:
            for i, d in enumerate(dirs):
                t_rot = t["R"] @ np.asarray(study.ROT[i % 24])
                pts = [np.asarray(p) @ t_rot for p in t["points"]]
                for gap in gaps:
                    yield case(group, t["component"], t["C"], t["H"], t_rot, pts, anchor=np.asarray(t["C"]) @ t_rot,
                               direction=d, reach=np.linalg.norm(t["H"]), gap=gap)
    for t in targets:
        if len(t["points"]) < 2:
            continue
        pairs = [(a, b) for a in range(len(t["points"])) for b in range(a + 1, len(t["points"]))]
        a, b = min(pairs, key=lambda ab: study.norm(study.sub(t["points"][ab[0]], t["points"][ab[1]])))
        M, _n, u, v = map(np.asarray, study.pair_frame(t, a, b))
        for k in range(BEARINGS):
            t_rot = t["R"] @ np.asarray(study.ROT[k % 24])
            th = 2 * math.pi * k / BEARINGS
            pts = [np.asarray(p) @ t_rot for p in t["points"]]
            for gap in BOUNDARY_GAPS:
                yield case("boundary", t["component"], t["C"], t["H"], t_rot, pts, anchor=M @ t_rot,
                           direction=(u * math.cos(th) + v * math.sin(th)) @ t_rot,
                           reach=np.linalg.norm(t["H"]) + np.linalg.norm(M - t["C"]), gap=gap)
    for k in range(len(study.SYN)):
        _meta, O, C, H, pts = study.trial(study.N_ORD + study.N_OFF + k)
        yield case("artificial", f"synthetic:{k}", C, H, np.eye(3), [np.asarray(p) for p in pts], O=np.asarray(O))


def oracle(case):
    """X4's quantised direction to the selected aim point from a query position."""
    pts = [tuple(map(float, p)) for p in case["points"]]
    return lambda u: study.Q(u, pts, [])


def view(case):
    """Everything a mapper under test may see. No aim points, turret, mount or muzzle."""
    return dict(oracle=oracle(case), target_box=case["box"], ship_class=case["ship_class"],
                ship_box=case["ship_box"], ship_position=case["position"], ship_rotation=case["rotation"])


def aimed_muzzles(case, records):
    """Hidden truth: {aim point index: world muzzle} after the turret aims at that point, via the accepted
    #173 geometry. IN_ARC only: an out-of-arc request is CANNOT BEAR territory and its pose is not real."""
    turret, R, O = scorer.accepted_turret(records[case["turret"]]), case["frame"], case["origin"]
    out = {}
    for i, p in enumerate(case["points"]):
        g = study.geometry(turret, tuple(tuple(map(float, r)) for r in R), tuple(map(float, O)), tuple(map(float, p)))
        if g["state"] == "IN_ARC":
            out[i] = O + np.asarray(g["muzzle"]) @ R
    return out


def ship_local(case, p):
    return (np.asarray(p) - case["position"]) @ case["rotation"].T


# ---------------------------------------------------------------- scoring (A3 method results)

def score(case, result, muzzles):
    """Score one A3 mapper result against hidden truth.

    `result` = {"located": [(label, centre, radius)], "answer": muzzle -> label | UNKNOWN, "queries": int}.
    A located point covers every true aim point within its radius. An answer is correct only when its
    label covers exactly the aim point X4 selects from that muzzle."""
    pts = case["points"]
    cover = {label: [j for j, p in enumerate(pts) if np.linalg.norm(np.asarray(c) - p) <= r]
             for label, c, r in result["located"]}
    hits = Counter(j for js in cover.values() for j in js)
    out = dict(queries=result["queries"], missed=sum(j not in hits for j in range(len(pts))),
               invented=sum(not js for js in cover.values()), merged=sum(len(js) > 1 for js in cover.values()),
               duplicate=sum(v > 1 for v in hits.values()), correct=0, wrong=0, unknown=0, muzzles=len(muzzles),
               radius=[r for label, _c, r in result["located"] if len(cover[label]) == 1],
               error=[float(np.linalg.norm(np.asarray(c) - pts[cover[label][0]]))
                      for label, c, _r in result["located"] if len(cover[label]) == 1])
    for m in muzzles.values():
        truth = study.select(tuple(map(float, m)), [tuple(map(float, p)) for p in pts])
        a = result["answer"](m)
        out["unknown" if a is UNKNOWN else "correct" if cover.get(a) == [truth] else "wrong"] += 1
    return out


# ---------------------------------------------------------------- A3 mappers (production inputs only)

sys.path.insert(0, str(ROOT / "research/issue176-a2"))
from simulate import EPS, REL, basis  # noqa: E402  #176 A2 angular allowance and poor-angle rule

FORWARD = 1e-4  # #176 A4 same-ray tolerance (rad)
SLACK = 2 * (EPS + 1e-6) / FORWARD  # #176 A5 along-ray resolution floor (~7%)
MAX_DEPTH = 2  # octree levels below the outer corners: at most a 5x5x5 corner grid
CAP = 128  # research query cap per mapper run; A6 chooses the production limit


class _Capped(Exception):
    pass


def _rho(*ps):
    return 2 * study.u * max(1.0, *(float(np.max(np.abs(p))) for p in ps))


def crossing(u, d, v, e):
    """(depth along ray (u, d), depth error bound) where ray (v, e) crosses it, or None: the #176 A2 miss
    allowance, forward check and poor-angle rejection (sine below 2 EPS / REL, or error over REL of depth)."""
    c, k = float(d @ e), float(np.linalg.norm(np.cross(d, e)))
    if k < 2 * EPS / REL:
        return None
    w = u - v
    s, t = (c * (e @ w) - d @ w) / k ** 2, ((e @ w) - c * (d @ w)) / k ** 2
    x = u + s * d
    miss = 2 * _rho(u, v, x) + EPS * (abs(s) + abs(t))
    if s <= 0 or t <= 0 or np.linalg.norm(x - v - t * e) > miss or miss / k > REL * max(s, t):
        return None
    return float(s), float(miss / k)


def _on_ray(u, d, centre, r):
    t = float((centre - u) @ d)
    return t > 0 and np.linalg.norm(centre - u - t * d) <= r + EPS * (t + r) + _rho(u, centre)


def _corners(lo, hi):
    return [np.asarray(c) for c in itertools.product(*zip(lo, hi))]


def _search(view, lo, hi, R, O, clear, cube=None, probe=None):
    """Shared A3 search over the box [lo, hi] (world = p @ R + O): query its 8 outer corners, locate the
    points their rays select, then query the corners of each octree leaf `clear` rejects, to MAX_DEPTH. With `cube`,
    finally query a cube of that half-size around each located point (target frame).

    Accepted #176 A5 location rule: two other rays cross an anchor ray at agreeing depths inside the padded
    target box, AND the along-ray bracket on the anchor confirms it (forward just short, non-forward just
    past). The bracket rejects the #176 A2 witness where rays selecting different points meet at a point
    that does not exist; it only resolves ~SLACK of depth, so one crossing alone is not enough (a ray to
    another point can cross just past the anchor's point). Radius = agreed depth span / 2 + angular cone
    + binary32 rounding.
    -> (points [(centre, r)], owner(ray) -> index | None, rays {corner: (world, dir)}, cleared, uncleared, queries).

    `probe`, when given, runs once the box work is finished and may spend further asks. It receives the live
    handles (`ask`, `locate`, `rays`, `points`, `owner`, `count`), so its observations feed this same location
    process instead of a private one."""
    oracle, (C, H, T) = view["oracle"], view["target_box"]
    tlo, thi = target_box(C, H)
    rays, points, hits, tried, n = {}, [], {}, set(), 0

    def ask(p):
        nonlocal n
        if n >= CAP:
            raise _Capped
        n += 1
        d = oracle(p)
        return None if d is None else np.asarray(d)

    def owner(u, d):
        on = [] if d is None else [i for i, (c, r) in enumerate(points) if _on_ray(u, d, c, r)]
        return on[0] if len(on) == 1 else None

    def confirm(u, d, s, err):
        near = s / (1 + 1.5 * SLACK) - 2 * err
        if near <= 0:
            return False
        a, b = ask(u + near * d), ask(u + (s + 2 * err) * d)
        return (a is not None and a @ d > 0 and np.linalg.norm(np.cross(a, d)) <= FORWARD
                and (b is None or b @ d <= 0 or np.linalg.norm(np.cross(b, d)) > FORWARD))

    def locate():
        free = {k: (u, d) for k, (u, d) in rays.items() if d is not None and owner(u, d) is None}
        for ka, kb in itertools.permutations(sorted(free), 2):
            if kb not in hits.setdefault(ka, {}):
                h = crossing(*free[ka], *free[kb])
                hits[ka][kb] = h and (h[0] - h[1], h[0] + h[1])
        found = []
        for ka in free:
            spans = [(h, kb) for kb, h in hits.get(ka, {}).items() if h and kb in free]
            for (h1, kb), (h2, kc) in itertools.combinations(spans, 2):
                lo_, hi_ = max(h1[0], h2[0]), min(h1[1], h2[1])
                if lo_ <= hi_ and (ka, kb, kc) not in tried:
                    found.append((hi_ - lo_, ka, kb, kc, (lo_ + hi_) / 2))
        for width, ka, kb, kc, s in sorted(found):
            (u, d), others = rays[ka], (rays[kb], rays[kc])
            if owner(u, d) is not None or any(owner(*o) is not None for o in others):
                continue
            tried.add((ka, kb, kc))
            x, r = u + s * d, width / 2 + EPS * s + _rho(u, u + s * d)
            if (inside((tlo - r, thi + r), x @ T.T) and all(np.linalg.norm(c - x) > q + r for c, q in points)
                    and confirm(u, d, s, width / 2)):
                points.append((x, r))

    leaves, cleared, uncleared = [(np.asarray(lo, float), np.asarray(hi, float), 0)], [], []
    try:
        while leaves:
            a, b, depth = leaves.pop(0)
            for c in _corners(a, b):
                if tuple(c) not in rays:
                    rays[tuple(c)] = (c @ R + O, ask(c @ R + O))
            locate()
            label = clear(a, b, [owner(*rays[tuple(c)]) for c in _corners(a, b)], points, rays, owner)
            if label is not False:
                cleared.append((a, b, label))
            elif depth < MAX_DEPTH:
                m = (a + b) / 2
                leaves += [(np.minimum(c, m), np.maximum(c, m), depth + 1) for c in _corners(a, b)]
            else:
                uncleared.append((a, b))
            if not leaves and cube is not None:
                leaves, cube = [(c @ R.T - cube, c @ R.T + cube, MAX_DEPTH) for c, _r in points], None
        if probe is not None:
            probe(dict(ask=ask, locate=locate, rays=rays, points=points, owner=owner, count=lambda: n))
    except _Capped:
        uncleared += [(a, b)] + [(x, y) for x, y, _ in leaves]
    return points, owner, rays, cleared, uncleared, n


def _pure(labels):
    """A leaf whose 8 corners all select one located point lies inside that point's Voronoi cell (cells
    are convex), so every position in it selects that point and no other aim point lies in it."""
    return labels[0] if labels[0] is not None and len(set(labels)) == 1 else False


def firing_box_map(view, margin):
    """Firing-ship-box method: map selection over the class-expanded runtime ship box. A later muzzle is
    answered only inside a pure leaf; outside the box or in an unproven leaf it is UNKNOWN."""
    lo, hi = firing_box(*view["ship_box"], margin)
    R, O = view["ship_rotation"], view["ship_position"]
    points, _o, _r, cleared, _u, n = _search(view, lo, hi, R, O, lambda a, b, labels, *_: _pure(labels))

    def answer(m):
        local = (np.asarray(m) - O) @ R.T
        return next((label for a, b, label in cleared if inside((a, b), local)), UNKNOWN)
    return dict(located=[(i, c, r) for i, (c, r) in enumerate(points)], answer=answer, queries=n)


GEO_DEPTH = 4  # query-free splits of an unproven leaf when testing it against the empty balls


def _unproven(a, b, balls, proven, depth=GEO_DEPTH):
    """Sub-boxes of [a, b], split up to `depth` times, each neither inside one empty ball (centre, radius)
    nor inside one proven box."""
    c, r = np.asarray([x for x, _ in balls]).reshape(-1, 3), np.asarray([y for _, y in balls])
    plo, phi = np.asarray([x for x, _ in proven]).reshape(-1, 3), np.asarray([y for _, y in proven]).reshape(-1, 3)
    boxes = np.asarray([(a, b)])
    for level in range(depth + 1):
        far = np.linalg.norm(np.maximum(np.abs(c[None] - boxes[:, None, 0]), np.abs(c[None] - boxes[:, None, 1])), axis=2)
        held = np.all((plo[None] <= boxes[:, None, 0]) & (boxes[:, None, 1] <= phi[None]), axis=2)
        boxes = boxes[~np.any(far < r[None], axis=1) & ~np.any(held, axis=1)]
        if level == depth or not len(boxes):
            return list(boxes)
        m = boxes.mean(axis=1)
        boxes = np.asarray([(np.minimum(x, mid), np.maximum(x, mid)) for (lo, hi), mid in zip(boxes, m)
                            for x in _corners(lo, hi)])


def target_box_map(view):
    """Target-box method: locate the points inside the padded target box, then answer by `nearest` only
    when no unproven region could hold a point nearer to the muzzle than the winner's far bound.

    Proven regions: pure leaves and cubes, and the empty ball of every queried position c whose located point is known
    (radius |c - centre| - r: no aim point is nearer to c than the one it selects)."""
    C, H, T = view["target_box"]
    lo, hi = target_box(C, H)

    def balls(points, rays, owner):
        return [(u @ T.T, np.linalg.norm(points[i][0] - u) - points[i][1])
                for u, d in rays.values() if (i := owner(u, d)) is not None]

    def clear(a, b, labels, points, rays, owner):
        return _pure(labels) is not False or not _unproven(a, b, balls(points, rays, owner), [])

    # Empty balls never cover a located point itself, so each gets a pure cube twice the finest split.
    cube = 2 * (hi - lo) / 2 ** (MAX_DEPTH + GEO_DEPTH)
    points, owner, rays, cleared, leaves, n = _search(view, lo, hi, T, np.zeros(3), clear, cube)
    known, proven = balls(points, rays, owner), [(a, b) for a, b, _label in cleared]
    unproven = [box for a, b in leaves for box in _unproven(a, b, known, proven)]
    located = [(i, c, r) for i, (c, r) in enumerate(points)]

    def answer(m):
        label = nearest(located, m)
        if label is UNKNOWN:
            return UNKNOWN
        far = np.linalg.norm(points[label][0] - m) + points[label][1]
        local = np.asarray(m) @ T.T
        return label if all(np.linalg.norm(np.maximum(0, np.maximum(a - local, local - b))) > far
                            for a, b in unproven) else UNKNOWN
    return dict(located=located, answer=answer, queries=n)


# ---------------------------------------------------------------- A4.1 corner audit (offline)

def _edges(lo, hi):
    """The 12 (corner, corner) pairs of the box that differ in exactly one coordinate."""
    cs = _corners(lo, hi)
    return [(a, b) for a, b in itertools.combinations(cs, 2) if np.count_nonzero(a != b) == 1]


def corner_audit(view, margin, probe=None):
    """A4.1: ask ONLY the 8 outer corners of the class-expanded firing-ship box, reusing the A3 location and
    point-confirmation rules, with no subdivision. Returns what the corners expose, nothing more.

    `probe` (A4.3 phase 2) may then spend further asks on the same location process; without it nothing else
    is asked and `rays` holds the 8 corner asks only."""
    lo, hi = firing_box(*view["ship_box"], margin)
    R, O = view["ship_rotation"], view["ship_position"]
    points, owner, rays, _c, _u, n = _search(view, lo, hi, R, O, lambda *_: True, probe=probe)  # no split
    own = {tuple(c): owner(*rays[tuple(c)]) for c in _corners(lo, hi)}
    mixed = [(a, b) for a, b in _edges(lo, hi)
             if own[tuple(a)] is not None and own[tuple(b)] is not None and own[tuple(a)] != own[tuple(b)]]
    return dict(points=points, own=own, mixed=mixed, queries=n, box=(lo, hi), R=R, O=O, rays=rays, owner=owner)


def _bisector(p, q):
    """(unit normal, point on plane) of the nearest-point switch plane between p and q."""
    d = np.asarray(q, float) - np.asarray(p, float)
    k = float(np.linalg.norm(d))
    return (d / k if k > 0 else np.full(3, math.nan)), (np.asarray(p, float) + q) / 2


def _gap(n1, o1, n2, o2, corners):
    """Worst disagreement (m), over `corners`, between two planes' signed distances."""
    return float(np.max(np.abs((corners - o1) @ n1 - (corners - o2) @ n2)))


def _plane_error(a, b, pa, pb, corners):
    """Worst disagreement (m), over the box corners, between the nearest-point switch plane of the estimated
    pair (a, b) and that of the true pair (pa, pb). Each plane: perpendicular bisector of its two points."""
    return _gap(*_bisector(a, b), *_bisector(pa, pb), corners)


def _audit_case(case):
    records, margins = _LOADED
    a = corner_audit(view(case), margins[case["ship_class"]][0])
    pts, own, mixed = a["points"], a["own"], a["mixed"]
    owners = {i for i in own.values() if i is not None}
    row = dict(group=case["group"], queries=a["queries"], points=len(pts),
               assigned=sum(i is not None for i in own.values()), multi=len(owners) >= 2,
               mixed=len(mixed), plane_ready=False, plane_error=None, measurable=False,
               muzzles=0, muzzles_exposed=0)

    # hidden truth, reporting only: later aimed muzzles whose selected aim point a confirmed point exposes.
    cover = {i: [j for j, p in enumerate(case["points"]) if np.linalg.norm(c - p) <= r] for i, (c, r) in enumerate(pts)}
    exposed = {j for js in cover.values() for j in js}
    for m in aimed_muzzles(case, records).values():
        row["muzzles"] += 1
        row["muzzles_exposed"] += study.select(tuple(map(float, m)), [tuple(map(float, p)) for p in case["points"]]) in exposed

    if len(owners) < 2:
        return row
    # the dominant mixed-edge pair defines the boundary the method would have to place.
    pairs = Counter(tuple(sorted((own[tuple(x)], own[tuple(y)]))) for x, y in mixed)
    if not pairs:
        return row
    (i, j), count = pairs.most_common(1)[0]
    row["plane_ready"] = len(cover[i]) == 1 and len(cover[j]) == 1  # each estimate names one real aim point
    if row["plane_ready"]:
        row["plane_error"] = _plane_error(pts[i][0], pts[j][0], case["points"][cover[i][0]], case["points"][cover[j][0]],
                                          np.asarray(_corners(*a["box"])) @ a["R"] + a["O"])
    # measurable directly: three switch crossings on that pair's edges, not all on one line.
    xs = [(x @ a["R"] + a["O"] + y @ a["R"] + a["O"]) / 2 for x, y in mixed
          if tuple(sorted((own[tuple(x)], own[tuple(y)]))) == (i, j)]
    row["measurable"] = count >= 3 and np.linalg.matrix_rank(np.asarray(xs[1:]) - xs[0], tol=1e-6) >= 2
    return row


def a41(every, jobs):
    """Run the A4.1 corner audit over the boundary cases and report what the 8 corners alone expose."""
    global _LOADED
    records, margins, mounts, _excluded, _inferred = load()
    _LOADED = records, margins
    todo = [c for c in cases(targets(), mounts) if c["group"] == "boundary"][::every]
    os.nice(10)
    with Pool(min(jobs, 4)) as pool:
        rows = list(pool.imap(_audit_case, todo, chunksize=8))
    q = np.asarray([r["queries"] for r in rows])
    multi = [r for r in rows if r["multi"]]
    ready = [r for r in multi if r["plane_error"] is not None]
    err = sorted(r["plane_error"] for r in ready) or [math.nan]
    print(f"A4.1 corner audit: {len(rows)} boundary cases, 8 outer corners only, no subdivision, CAP {CAP}")
    print(f"  confirmed target points:            {sum(r['points'] for r in rows)} total, "
          f"{sum(r['points'] > 0 for r in rows)} cases with >=1, {sum(r['points'] >= 2 for r in rows)} cases with >=2")
    print(f"  corner rays confidently assigned:   {sum(r['assigned'] for r in rows)} of {8 * len(rows)}")
    print(f"  cases with >=2 confirmed owners:    {len(multi)}")
    print(f"  mixed box edges (different owners): {sum(r['mixed'] for r in rows)}, "
          f"cases with >=3 useful mixed edges:  {sum(r['mixed'] >= 3 for r in rows)}")
    print(f"  queries med/p90/max:                {int(np.median(q))} / {int(np.percentile(q, 90))} / {q.max()}")
    print("\n  for the >=2-confirmed-point cases:")
    print(f"    calculated boundary: {len(ready)} of {len(multi)} give a plane from two single-aim-point estimates; "
          f"error vs true plane med/p90/max {np.median(err):.3g} / {np.percentile(err, 90):.3g} / {max(err):.3g} m")
    print(f"    measured boundary:   {sum(r['measurable'] for r in multi)} of {len(multi)} have >=3 non-collinear "
          "switch crossings on one pair's edges")
    print(f"\n  hidden-truth check (reporting only): {sum(r['muzzles_exposed'] for r in rows)} of "
          f"{sum(r['muzzles'] for r in rows)} later aimed muzzles select a point the corner audit already exposed")


# ---------------------------------------------------------------- A4.2 switch-boundary comparison

CACHE = ROOT / ".x4-research-cache/issue184"
SNAPSHOTS = (2, 4, 6)  # halfway asks per chosen edge, recorded as a cost/accuracy curve


def safety_band(a, ra, b, rb, corners):
    """Half-width (m) of a flat conservative band around the estimated switch plane of (a, b).

    A position x provably selects the point near `a` when |x - b| - |x - a| > ra + rb (the estimate balls
    can only move each distance by its radius). With s the signed distance from the estimated plane,
    |x - b|^2 - |x - a|^2 = 2 s |a - b|, so |x - b| - |x - a| >= 2 s |a - b| / (|x - a| + |x - b|).
    Taking the largest |x - a| + |x - b| over the region makes one flat half-width safe everywhere."""
    sep = float(np.linalg.norm(np.asarray(b, float) - a))
    if sep <= 0:
        return math.inf
    reach = float(np.max(np.linalg.norm(corners - a, axis=1) + np.linalg.norm(corners - b, axis=1)))
    return (ra + rb) * reach / (2 * sep)


def _spread(items, key, want=3):
    """`want` of `items` whose `key` positions are spread out: the farthest-apart pair, then greedily the
    item farthest from those already chosen. A flat boundary through near-coincident points is unstable."""
    if len(items) <= want:
        return list(items)
    ps = [np.asarray(key(x), float) for x in items]
    i, j = max(itertools.combinations(range(len(items)), 2), key=lambda ab: np.linalg.norm(ps[ab[0]] - ps[ab[1]]))
    out = [i, j]
    while len(out) < want:
        out.append(max((k for k in range(len(items)) if k not in out),
                       key=lambda k: min(np.linalg.norm(ps[k] - ps[o]) for o in out)))
    return [items[k] for k in out]


def _fit_plane(locs, orient):
    """(unit normal, point) of the plane through three switch locations, oriented like `orient`, plus the
    triangle's shortest altitude as a stability scale; None when the three are effectively collinear."""
    p0, p1, p2 = (np.asarray(x, float) for x in locs)
    n = np.cross(p1 - p0, p2 - p0)
    area2 = float(np.linalg.norm(n))
    longest = max(np.linalg.norm(p1 - p0), np.linalg.norm(p2 - p0), np.linalg.norm(p2 - p1))
    if area2 <= 0 or longest <= 0 or area2 / longest < 1e-6 * longest:
        return None
    n = n / area2
    return (n if n @ orient >= 0 else -n), p0, area2 / longest


def measure_boundary(view, points, edges, pair, R, O):
    """Bisect each chosen mixed edge toward the switch, assigning every new ask the way the method can:
    the observed direction must lie on exactly one confirmed point's ray. Yields (asks so far per edge,
    switch locations, stalls) after each halfway ask, up to max(SNAPSHOTS)."""
    oracle = view["oracle"]
    i, j = pair
    n = 0

    def assign(x):
        nonlocal n
        n += 1
        d = oracle(x)
        if d is None:
            return None
        d = np.asarray(d)
        on = [k for k, (c, r) in enumerate(points) if _on_ray(x, d, c, r)]
        return on[0] if len(on) == 1 else None

    brackets = [[x @ R + O, y @ R + O, True] for x, y in edges]  # [end owned by i, end owned by j, live]
    for _step in range(max(SNAPSHOTS)):
        for br in brackets:
            if not br[2]:
                continue
            w = (br[0] + br[1]) / 2
            a = assign(w)
            if a == i:
                br[0] = w
            elif a == j:
                br[1] = w
            else:  # unassignable, or a third confirmed point: refining further would be a guess
                br[2] = False
        yield n, [(br[0] + br[1]) / 2 for br in brackets], sum(not br[2] for br in brackets)


def _a42_case(case):
    """One A4.2 row: the A4.1 audit, then the calculated and measured boundaries, scored after the fact."""
    records, margins = _LOADED
    v = view(case)
    a = corner_audit(v, margins[case["ship_class"]][0])
    pts, own, mixed = a["points"], a["own"], a["mixed"]
    corners = np.asarray(_corners(*a["box"])) @ a["R"] + a["O"]
    box = firing_box(*case["ship_box"], margins[case["ship_class"]][0])
    muzzles = list(aimed_muzzles(case, records).values())
    truth = [tuple(map(float, p)) for p in case["points"]]
    cover = {k: [q for q, p in enumerate(case["points"]) if np.linalg.norm(c - p) <= r] for k, (c, r) in enumerate(pts)}
    exposed = {q for qs in cover.values() for q in qs}
    row = dict(id=case["id"], target=case["target"], ship=case["ship"], gap=case["gap"], audit=a["queries"],
               points=len(pts), muzzles=len(muzzles),
               muzzles_exposed=sum(study.select(tuple(map(float, m)), truth) in exposed for m in muzzles))

    owners = sorted({k for k in own.values() if k is not None})
    pairs = Counter(tuple(sorted((own[tuple(x)], own[tuple(y)]))) for x, y in mixed)
    if len(owners) < 2 or not pairs:
        row["kind"] = "one_point"
        # C: hidden truth, reporting only. Where do muzzles selecting an unexposed point sit?
        bad = [m for m in muzzles if study.select(tuple(map(float, m)), truth) not in exposed]
        row["unexposed_muzzles"] = len(bad)
        row["unexposed_outside_box"] = sum(not inside(box, ship_local(case, m)) for m in bad)
        if bad and exposed:
            q = min(exposed)
            row["unexposed_to_boundary"] = [  # distance to the true switch plane between the exposed and chosen point
                abs(float((m - o) @ nrm)) for m in bad
                for s in [study.select(tuple(map(float, m)), truth)]
                for nrm, o in [_bisector(case["points"][q], case["points"][s])] if s != q]
        return row

    row["kind"] = "two_point"
    (i, j), _count = pairs.most_common(1)[0]
    (ci, ri), (cj, rj) = pts[i], pts[j]
    n_est, o_est = _bisector(ci, cj)
    w = safety_band(ci, ri, cj, rj, corners)
    row.update(pair_sep=float(np.linalg.norm(cj - ci)), band=2 * w, radii=[ri, rj])

    # A scoring, hidden truth only from here.
    single = len(cover[i]) == 1 and len(cover[j]) == 1
    row["calc_ok"] = single
    if single:
        n_true, o_true = _bisector(case["points"][cover[i][0]], case["points"][cover[j][0]])
        row["calc_error"] = _gap(n_est, o_est, n_true, o_true, corners)
        row["calc_contained"] = row["calc_error"] <= w
        # n_est runs from the point near ci to the one near cj, so s > 0 claims j and s < 0 claims i.
        row.update(calc_outside_band=0, calc_in_band=0, calc_correct=0, calc_unsafe=0)
        for m in muzzles:
            s = float((m - o_est) @ n_est)
            if abs(s) <= w:
                row["calc_in_band"] += 1
                continue
            row["calc_outside_band"] += 1
            claim = cover[j][0] if s > 0 else cover[i][0]
            row["calc_correct" if study.select(tuple(map(float, m)), truth) == claim else "calc_unsafe"] += 1

    # B: the same three spread mixed edges, refined, snapshotted.
    chosen = _spread([(x, y) if own[tuple(x)] == i else (y, x) for x, y in mixed
                      if tuple(sorted((own[tuple(x)], own[tuple(y)]))) == (i, j)],
                     key=lambda e: (e[0] + e[1]) / 2)
    row["edges"] = len(chosen)
    row["meas"] = {}
    if len(chosen) == 3:
        for step, (asks, locs, stalls) in enumerate(measure_boundary(v, pts, chosen, (i, j), a["R"], a["O"]), 1):
            if step not in SNAPSHOTS:
                continue
            fit = _fit_plane(locs, cj - ci)
            e = dict(asks=a["queries"] + asks, stalls=stalls, stable=fit is not None)
            if fit is not None and single:
                e["error"] = _gap(fit[0], fit[1], n_true, o_true, corners)
            row["meas"][str(step)] = e
    return row


def a42(jobs):
    """A4.2: calculated vs directly measured switch boundary over the 240 boundary cases."""
    global _LOADED
    records, margins, mounts, _excluded, _inferred = load()
    _LOADED = records, margins
    todo = [c for c in cases(targets(), mounts) if c["group"] == "boundary"]
    CACHE.mkdir(parents=True, exist_ok=True)
    rows_path, sum_path = CACHE / "a42_rows.jsonl", CACHE / "a42_summary.txt"
    print(f"A4.2: {len(todo)} boundary cases -> {rows_path}", flush=True)
    os.nice(10)
    rows = []
    with open(rows_path, "w") as fh, Pool(min(jobs, 4)) as pool:
        for r in pool.imap(_a42_case, todo, chunksize=4):
            rows.append(r)
            fh.write(json.dumps(r, default=float) + "\n")
            fh.flush()
            if len(rows) % 10 == 0:
                print(f"  {len(rows)}/{len(todo)} -> {rows_path}", flush=True)
    out = _a42_report(rows)
    sum_path.write_text(out)
    print(out + f"\n(rows: {rows_path}, summary: {sum_path})")


def _stats(xs):
    xs = sorted(xs)
    return (f"{np.median(xs):.3g} / {np.percentile(xs, 90):.3g} / {max(xs):.3g}") if xs else "n/a"


def _a42_report(rows):
    two = [r for r in rows if r["kind"] == "two_point"]
    one = [r for r in rows if r["kind"] == "one_point"]
    calc = [r for r in two if r.get("calc_ok")]
    fails = [r for r in calc if not r["calc_contained"]]
    unsafe = [r for r in calc if r.get("calc_unsafe")]
    L = [f"A4.2 switch boundary: {len(rows)} boundary cases, {len(two)} with two confirmed points, "
         f"{len(one)} with one", "",
         "A. calculated boundary (confirmed point estimates + their uncertainty only)",
         f"  usable:              {len(calc)} of {len(two)}",
         f"  error med/p90/max:   {_stats([r['calc_error'] for r in calc])} m",
         f"  band width (2w):     {_stats([r['band'] for r in calc])} m",
         f"  band contains truth: {sum(r['calc_contained'] for r in calc)} of {len(calc)}"
         + (f"   FAILURES: {[r['id'] for r in fails]}" if fails else ""),
         f"  later muzzles:       {sum(r['calc_outside_band'] for r in calc)} resolved outside the band "
         f"({sum(r['calc_correct'] for r in calc)} correct), "
         f"{sum(r['calc_in_band'] for r in calc)} unresolved inside it",
         f"  unsafe answers:      {sum(r.get('calc_unsafe', 0) for r in calc)}"
         + (f"   CASES: {[r['id'] for r in unsafe]}" if unsafe else ""), "",
         "B. measured boundary (bisecting three spread mixed edges)",
         "  asks/edge   cases  stable  total asks med/p90/max   error med/p90/max (m)   stalled edges"]
    for k in SNAPSHOTS:
        got = [r["meas"][str(k)] for r in two if str(k) in r["meas"]]
        rs = got
        err = [g["error"] for g in got if "error" in g]
        L.append(f"  {k:9} {len(rs):6} {sum(g['stable'] for g in got):7}  {_stats([g['asks'] for g in got]):22}  "
                 f"{_stats(err):22}  {sum(g['stalls'] for g in got)}")
    short = [r for r in two if r["edges"] < 3]
    last = str(max(SNAPSHOTS))
    stalled = [r for r in two if r["meas"].get(last, {}).get("stalls")]
    L += [f"  cases without three usable mixed edges: {len(short)}" + (f" {[r['id'] for r in short]}" if short else ""),
          f"  cases where an edge could not be refined safely: {len(stalled)}"
          + (f" {[r['id'] for r in stalled]}" if stalled else ""), "",
          "C. one-confirmed-point cases (hidden truth, reporting only; no asks changed)",
          f"  cases:                                     {len(one)}",
          f"  all later muzzles select the exposed point: {sum(r['unexposed_muzzles'] == 0 for r in one)}",
          f"  at least one selects an unexposed point:    {sum(r['unexposed_muzzles'] > 0 for r in one)}"
          + (f"   CASES: {[r['id'] for r in one if r['unexposed_muzzles']]}"
             if any(r["unexposed_muzzles"] for r in one) else ""),
          f"  affected later muzzles:                     {sum(r['unexposed_muzzles'] for r in one)}"
          f" ({sum(r['unexposed_outside_box'] for r in one)} outside the expanded firing box)",
          f"  their distance to the true switch plane:    "
          f"{_stats([d for r in one for d in r.get('unexposed_to_boundary', [])])} m", "",
          f"total later aimed muzzles: {sum(r['muzzles'] for r in rows)}; "
          f"not covered by a confirmed point: {sum(r['muzzles'] - r['muzzles_exposed'] for r in rows)} "
          f"({sum(r['muzzles'] - r['muzzles_exposed'] for r in two)} in two-point cases, "
          f"{sum(r['muzzles'] - r['muzzles_exposed'] for r in one)} in one-point cases)"]
    return "\n".join(L)


# ---------------------------------------------------------------- A4.3 phase 1: residual uncertainty

# The 19 boundary cases where a later aimed muzzle selects a point the 8 outer corners never exposed
# (A4.2). Hidden truth picked this list and scores the result; the method below never sees it.
A43_CASES = (12155, 12157, 12160, 12163, 12169, 12177, 12196, 12197, 12360, 12362, 12365, 12366,
             12368, 12369, 12388, 12390, 12199, 12234, 12376)


HULL_EPS = 1e-9  # a near-degenerate separating plane counts as separating, so ties fall to UNKNOWN


def spans(vs):
    """True when the vectors `vs` positively span 3-space, i.e. no plane through the origin has all of them
    on one closed side. Checks every candidate supporting normal: a supporting plane of a finite cone can
    always be taken normal to one vector or to the cross product of two, so this is exact up to HULL_EPS."""
    vs = [v / n for v in map(np.asarray, vs) if (n := float(np.linalg.norm(v))) > 0]
    if len(vs) < 4:
        return False
    cands = [c for a, b in itertools.combinations(vs, 2) for c in (np.cross(a, b), -np.cross(a, b))] + \
            [c for v in vs for c in (v, -v)]
    for n in cands:
        k = float(np.linalg.norm(n))
        if k > 0 and min(float(n @ v) / k for v in vs) >= -HULL_EPS:
            return False
    return True


def residual_map(view, margin, probe=None):
    """A4.3 phase 1: answer later positions from the existing corner asks alone, conservatively. No new asks.
    With a `probe` (phase 2) the same rule also uses whatever extra asks the probe spent.

    Every confidently assigned corner ask is an empty ball: no aim point lies nearer to that ask position
    than the point it selected (`target_box_map`'s rule). What those balls leave uncovered is residual
    target space, where an undiscovered aim point may still sit, and a later position may only get a
    definite answer when nothing in that space could beat the winner.

    Where those balls leave nothing, in closed form: let x be an undiscovered point that beats the winner's
    true point t from m. Then |x - u| >= |t - u| at every ask u assigned to the winner, while
    |x - m| <= |t - m|. The set where |x - .| - |t - .| keeps one sign is a half-space, so such an x exists
    only if some plane through m puts every one of those asks on one side. When m is strictly inside the
    hull of the asks assigned to the winner, no such plane exists and no undiscovered point anywhere in the
    residual space can beat it. Otherwise UNKNOWN. The bound needs the asks and their assignment only; it
    never looks at where the residual space actually is, and never at the later muzzles.

    ponytail: this proves the winner beats every *undiscovered* point. Which known point wins is still
    `nearest`, and a second aim point hiding inside a confirmed estimate's own radius still needs a new
    ask, which is A4.3 phase 2."""
    C, H, T = view["target_box"]
    tlo, thi = target_box(C, H)
    a = corner_audit(view, margin, probe)
    points = a["points"]
    asks = [(u, i) for u, d in a["rays"].values() if (i := a["owner"](u, d)) is not None]
    balls = [(u @ T.T, float(np.linalg.norm(points[i][0] - u)) - points[i][1]) for u, i in asks]
    located = [(i, c, r) for i, (c, r) in enumerate(points)]
    residual = _unproven(tlo, thi, balls, []) if balls else [(tlo, thi)]

    def answer(m):
        label = nearest(located, m)
        if label is UNKNOWN:
            return UNKNOWN
        return label if spans([u - m for u, i in asks if i == label]) else UNKNOWN

    return dict(located=located, answer=answer, queries=a["queries"], residual=residual,
                target_volume=float(np.prod(thi - tlo)))


def _a43_row(case, r, muzzles):
    """Score one A4.3 mapper result and add the hidden-truth reporting fields."""
    row = dict(score(case, r, muzzles), id=case["id"], target=case["target"], ship=case["ship"], gap=case["gap"],
               points=len(r["located"]), residual_boxes=len(r["residual"]),
               residual_fraction=float(sum(np.prod(b - a) for a, b in r["residual"])) / r["target_volume"])
    row.pop("radius"); row.pop("error")  # noqa: E702 not meaningful for this row
    # hidden truth, reporting only: which later muzzles select a point no confirmed estimate covers.
    truth = [tuple(map(float, p)) for p in case["points"]]
    cover = {i: [j for j, p in enumerate(case["points"]) if np.linalg.norm(c - p) <= q] for i, c, q in r["located"]}
    exposed = {j for js in cover.values() for j in js}
    row.update(unexposed=0, unexposed_correct=0, unexposed_wrong=0, unexposed_unknown=0, wrong_muzzles=[],
               exposed_points=sorted(exposed))
    for m in muzzles.values():
        sel = study.select(tuple(map(float, m)), truth)
        ans = r["answer"](m)
        verdict = "unknown" if ans is UNKNOWN else "correct" if cover.get(ans) == [sel] else "wrong"
        if verdict == "wrong":
            row["wrong_muzzles"].append(sel)
        if sel not in exposed:
            row["unexposed"] += 1
            row[f"unexposed_{verdict}"] += 1
    return row


def _a43_case(case):
    records, margins = _LOADED
    r = residual_map(view(case), margins[case["ship_class"]][0])
    return _a43_row(case, r, aimed_muzzles(case, records))


def a43(jobs):
    """A4.3 phase 1: the 19 unexposed-point boundary cases, existing corner asks only, no new oracle asks."""
    global _LOADED
    records, margins, mounts, _excluded, _inferred = load()
    _LOADED = records, margins
    todo = [c for c in cases(targets(), mounts) if c["id"] in set(A43_CASES)]
    assert len(todo) == len(A43_CASES), (len(todo), len(A43_CASES))
    CACHE.mkdir(parents=True, exist_ok=True)
    rows_path, sum_path = CACHE / "a43_rows.jsonl", CACHE / "a43_summary.txt"
    print(f"A4.3 phase 1: {len(todo)} cases -> {rows_path}", flush=True)
    os.nice(10)
    rows = []
    with open(rows_path, "w") as fh, Pool(min(jobs, 4)) as pool:
        for r in pool.imap(_a43_case, todo, chunksize=1):
            rows.append(r)
            fh.write(json.dumps(r, default=float) + "\n")
            fh.flush()
            print(f"  {len(rows)}/{len(todo)} case {r['id']}: {r['points']} pts, {r['queries']} asks, "
                  f"{r['correct']}/{r['wrong']}/{r['unknown']} correct/wrong/UNKNOWN", flush=True)
    out = _a43_report(rows)
    sum_path.write_text(out)
    print(out + f"\n(rows: {rows_path}, summary: {sum_path})")


def _a43_report(rows):
    def block(name, rs):
        if not rs:
            return [f"{name}: none"]
        tot = {k: sum(r[k] for r in rs) for k in ("queries", "points", "muzzles", "correct", "wrong", "unknown",
                                                  "unexposed", "unexposed_correct", "unexposed_wrong",
                                                  "unexposed_unknown", "missed", "merged")}
        return [f"{name}: {len(rs)} cases",
                f"  existing asks:                 {tot['queries']} total, med/p90/max "
                f"{_stats([r['queries'] for r in rs])}",
                f"  confirmed points:              {tot['points']} total, "
                f"{sum(r['points'] >= 2 for r in rs)} cases with >=2; {tot['missed']} true points missed, "
                f"{tot['merged']} merged estimates",
                f"  residual target uncertainty:   {_stats([100 * r['residual_fraction'] for r in rs])} "
                "% of the padded target box (med/p90/max)",
                f"  later aimed muzzles:           {tot['muzzles']} -> {tot['correct']} correct, "
                f"{tot['wrong']} wrong, {tot['unknown']} UNKNOWN",
                f"  of those, unexposed-point ones: {tot['unexposed']} -> {tot['unexposed_correct']} correct, "
                f"{tot['unexposed_wrong']} wrong, {tot['unexposed_unknown']} UNKNOWN"]

    one = [r for r in rows if r["points"] < 2]
    two = [r for r in rows if r["points"] >= 2]
    wrong = [r for r in rows if r["wrong"]]
    L = ["A4.3 phase 1: residual-uncertainty answers from the existing corner asks only (no new asks)", ""]
    L += block("one-confirmed-point cases", one) + [""]
    L += block("two-confirmed-point cases", two) + [""]
    L += block("all A4.3 cases", rows) + ["",
          "wrong answers: " + (", ".join(f"case {r['id']} ({r['wrong']})" for r in wrong) if wrong else "none")]
    return "\n".join(L)


# ---------------------------------------------------------------- A4.3 phase 2: adaptive corner rescue

RESCUE_GUARD = 24  # research-loose runaway guard on the extra asks per case; A6 sets any production limit
RESCUE_ALPHA0 = math.radians(2.0)  # #176 A5 first sideways viewing-angle change
RESCUE_ALPHA_MIN = math.radians(1 / 64)  # #176 A5 floor: below this a sideways move buys nothing
FALLBACK_GUARD = 24  # separate research-loose guard for the uncertainty-driven firing-area search


def _box_depth(u, d, tlo, thi, T):
    """Runtime-only depth scale along the ask ray (u, d): the middle of the segment it spends inside the padded
    target box, or its closest approach to the box centre when it misses it. Production target box only."""
    o, e = np.asarray(u, float) @ T.T, np.asarray(d, float) @ T.T
    near, far = 0.0, math.inf
    for k in range(3):
        if abs(e[k]) < 1e-12:
            continue
        a, b = sorted(((tlo[k] - o[k]) / e[k], (thi[k] - o[k]) / e[k]))
        near, far = max(near, a), min(far, b)
    if near <= far < math.inf:
        return 0.5 * (near + far)
    return max(float(((tlo + thi) / 2 - o) @ e), 1.0)


def _cell_resolved(a, b, R, O, T, points, residual):
    """Can an undiscovered aim point still beat every confirmed point somewhere in the firing cell [a, b]?

    `known_far` is a safe upper bound on the distance from any position in the cell to the nearest confirmed
    point: the best (centre distance + radius) at the cell centre, plus the centre-to-corner half-diagonal.
    The cell is resolved when every remaining target-space box is provably farther than that, so no point
    hiding there could win anywhere in the cell. The cell's 8 corners are taken to the target frame and
    enclosed in an axis-aligned box, which contains the cell, so the box-to-box distance can only
    underestimate the true one: conservative in the safe direction."""
    if not points:
        return False
    m = (a + b) / 2 @ R + O
    known_far = min(float(np.linalg.norm(c - m)) + r for c, r in points) + float(np.linalg.norm(b - a)) / 2
    corners = np.asarray([c @ R + O for c in _corners(a, b)]) @ T.T
    lo, hi = corners.min(0), corners.max(0)
    return all(float(np.linalg.norm(np.maximum(0, np.maximum(rlo - hi, lo - rhi)))) > known_far
               for rlo, rhi in residual)


def _pursue(h, tlo, thi, T, anchors, spend, stats, tag, seen):
    """Adaptive moved asks until every anchor ray is assigned or too narrow to observe further (#176 A5).

    An unassigned ask is an observation, not a failure: it names a direction toward *some* aim point. Take
    the anchors one at a time in fixed key order (never hidden truth) and ask again from sideways of that
    ray, offset by the viewing-angle change alpha at the ray's own target-box depth scale. When the moved
    ray does not support its anchor - it misses it, or crosses it outside the padded target box - X4
    selected another point: keep the observation, halve alpha and turn 60 degrees. Every ask feeds the
    shared `locate()`, and a newly confirmed point may explain other stored observations, so the anchor
    list is rebuilt before each spend. `stats` counts under `tag`; `seen` is the shared new-point watch."""
    points = h["points"]
    state = {}
    while anchors:
        h["locate"]()
        anchors = [k for k in anchors if h["owner"](*h["rays"][k]) is None]
        if len(points) > seen[0]:  # a new point may already explain other stored observations
            seen[0] = len(points)
            continue
        if not anchors:
            break
        if not spend(3):  # the spare 2 cover `locate`'s along-ray confirmation
            stats[tag + "guard"] = True
            break
        k = anchors[0]
        u, d = h["rays"][k]
        alpha, turn = state.get(k, (RESCUE_ALPHA0, 0))
        if alpha < RESCUE_ALPHA_MIN:  # nothing narrower left to observe about this direction
            anchors.pop(0)
            continue
        a_ax, b_ax = basis(d)
        side = math.cos(turn * math.pi / 3) * a_ax + math.sin(turn * math.pi / 3) * b_ax
        v = u + _box_depth(u, d, tlo, thi, T) * math.tan(alpha) * side
        h["rays"][tuple(map(float, v))] = (v, dv := h["ask"](v))
        stats[tag + "moved"] += 1
        hit = None if dv is None else crossing(u, d, v, dv)
        supported = hit is not None and inside((tlo, thi), (u + hit[0] * d) @ T.T)
        stats[tag + "switched"] += not supported
        state[k] = (alpha / 2 if not supported else alpha, turn + 1)
    h["locate"]()


def rescue_probe(view, margin, guard=RESCUE_GUARD, fallback_guard=FALLBACK_GUARD, fallback=True):
    """A4.3 phase 2 and 3: adaptive rescue of the corner directions the audit could not assign, then an
    uncertainty-driven fallback search of the firing area for aim points nothing has pointed at yet.

    **Phase 2, the cheap rescue.** An unassigned corner ask is an observation, not a failure: it names a
    direction toward *some* aim point. Taking one at a time in fixed key order (never hidden truth), make a
    sideways moved ask, offset by the viewing-angle change alpha at that ray's own target-box depth scale.
    When the moved ray does not support its anchor - it misses it, or crosses it outside the padded target
    box - X4 selected another point: keep the observation, halve alpha and turn 60 degrees (#176 A5).

    **Phase 3, the fallback.** What the phase-1 empty balls leave uncovered is the target space an unknown
    point could still occupy. Cells of the expanded firing box are asked one question only - could an
    undiscovered point beat every confirmed point anywhere in this cell (`_cell_resolved`) - so ordinary
    competition between points already known is left to the calculated switch boundary and never splits a
    cell. Best-first by cell size: ask at the largest unresolved cell's centre, pursue the answer with the
    same phase-2 moved asks when it is not already assigned, split that cell into 8, rebuild the evidence
    and re-evaluate. Each stage has its own loose research guard.

    Every ask, supporting or switched, enters the shared `locate()`, whose existing conservative
    multi-ray-plus-bracket rule is the only thing that confirms a point; after each new point both stages
    reconsider every stored observation before spending another ask.

    Returns (probe, stats). -> `residual_map(view, margin, probe)`."""
    C, H, T = view["target_box"]
    tlo, thi = target_box(C, H)
    flo, fhi = firing_box(*view["ship_box"], margin)
    R, O = view["ship_rotation"], view["ship_position"]
    stats = dict(before=0, before_points=[], open_before=0, extra=0, moved=0, switched=0, guard=False,
                 fb_used=False, fb_before=0, fb_points=0, fb_extra=0, fb_asks=0, fb_moved=0, fb_switched=0, fb_guard=False,
                 fb_cells=0, fb_unresolved=0, fb_fraction=1.0)

    def probe(h):
        points = h["points"]
        stats.update(before=len(points), before_points=list(points))
        seen = [len(points)]

        start = h["count"]()
        anchors = sorted(k for k, (u, d) in h["rays"].items() if d is not None and h["owner"](u, d) is None)
        stats["open_before"] = len(anchors)
        _pursue(h, tlo, thi, T, anchors, lambda n: h["count"]() - start + n <= guard, stats, "", seen)
        stats["extra"] = h["count"]() - start
        if not fallback:
            return

        start2 = h["count"]()
        spend = lambda n: h["count"]() - start2 + n <= fallback_guard  # noqa: E731
        stats["fb_before"] = len(points)
        cells = [(np.asarray(flo, float), np.asarray(fhi, float))]
        whole = float(np.prod(fhi - flo))
        while True:
            h["locate"]()
            balls = [(u @ T.T, float(np.linalg.norm(points[i][0] - u)) - points[i][1])
                     for u, d in h["rays"].values() if (i := h["owner"](u, d)) is not None]
            residual = _unproven(tlo, thi, balls, []) if balls else [(tlo, thi)]
            open_cells = [c for c in cells if not _cell_resolved(*c, R, O, T, points, residual)]
            if not open_cells or not spend(1):
                stats["fb_guard"] = bool(open_cells)
                stats.update(fb_cells=len(cells), fb_unresolved=len(open_cells),
                             fb_fraction=float(sum(np.prod(b - a) for a, b in open_cells)) / whole)
                break
            stats["fb_used"] = True
            cell = max(open_cells, key=lambda c: float(np.linalg.norm(c[1] - c[0])))
            a, b = cell
            u = (a + b) / 2 @ R + O
            key = tuple(map(float, u))
            h["rays"][key] = (u, dv := h["ask"](u))
            stats["fb_asks"] += 1
            mid = (a + b) / 2
            cells = [c for c in cells if c is not cell]
            cells += [(np.minimum(c, mid), np.maximum(c, mid)) for c in _corners(a, b)]
            h["locate"]()
            if dv is not None and h["owner"](u, dv) is None:
                _pursue(h, tlo, thi, T, [key], spend, stats, "fb_", seen)
        stats["fb_extra"] = h["count"]() - start2
        stats["fb_points"] = len(points) - stats["fb_before"]
    return probe, stats


_FALLBACK = True  # set by `a43r` before the pool forks: whether phase 3 runs after the cheap rescue


def _a43r_case(case):
    records, margins = _LOADED
    v = view(case)
    margin = margins[case["ship_class"]][0]
    probe, stats = rescue_probe(v, margin, fallback=_FALLBACK)
    r = residual_map(v, margin, probe)
    muzzles = aimed_muzzles(case, records)
    row = _a43_row(case, r, muzzles)
    before = {j for i, (c, q) in enumerate(stats["before_points"])
              for j, p in enumerate(case["points"]) if np.linalg.norm(c - p) <= q}
    after = set(row["exposed_points"])
    sel = [study.select(tuple(map(float, m)), [tuple(map(float, p)) for p in case["points"]])
           for m in muzzles.values()]
    row.update(points_before=stats["before"], points_new=len(r["located"]) - stats["before"],
               open_before=stats["open_before"], extra=stats["extra"], moved=stats["moved"],
               switched=stats["switched"], guard=stats["guard"], newly_exposed=len(after - before),
               unexposed_before=sum(s not in before for s in sel),
               rescued_muzzles=sum(s not in before and s in after for s in sel),
               **{k: stats[k] for k in ("fb_used", "fb_points", "fb_extra", "fb_asks", "fb_moved",
                                       "fb_switched", "fb_guard", "fb_cells", "fb_unresolved", "fb_fraction")},
               extra_total=stats["extra"] + stats["fb_extra"],
               still_unexposed=sum(s not in after for s in sel))
    return row


def a43r(jobs, fallback=False):
    """A4.3 phase 2 (and, with `fallback`, phase 3) on the same 19 cases."""
    global _LOADED, _FALLBACK
    _FALLBACK = fallback
    records, margins, mounts, _excluded, _inferred = load()
    _LOADED = records, margins
    todo = [c for c in cases(targets(), mounts) if c["id"] in set(A43_CASES)]
    assert len(todo) == len(A43_CASES), (len(todo), len(A43_CASES))
    CACHE.mkdir(parents=True, exist_ok=True)
    tag = "a43f" if fallback else "a43r"
    rows_path, sum_path = CACHE / f"{tag}_rows.jsonl", CACHE / f"{tag}_summary.txt"
    print(f"A4.3 phase {'2+3' if fallback else '2'}: {len(todo)} cases -> {rows_path}", flush=True)
    os.nice(10)
    rows = []
    with open(rows_path, "w") as fh, Pool(min(jobs, 4)) as pool:
        for r in pool.imap(_a43r_case, todo, chunksize=1):
            rows.append(r)
            fh.write(json.dumps(r, default=float) + "\n")
            fh.flush()
            print(f"  {len(rows)}/{len(todo)} case {r['id']}: {r['points_before']}(+{r['points_new']}) pts, "
                  f"+{r['extra']} rescue asks, +{r['fb_extra']} fallback asks (+{r['fb_points']} pts"
                  f"{', GUARD' if r['fb_guard'] else ''}), {r['switched'] + r['fb_switched']} switched, "
                  f"{r['correct']}/{r['wrong']}/{r['unknown']} correct/wrong/UNKNOWN", flush=True)
    out = _a43r_report(rows)
    sum_path.write_text(out)
    print(out + f"\n(rows: {rows_path}, summary: {sum_path})")


def _a43r_report(rows):
    def block(name, rs):
        if not rs:
            return [f"{name}: none"]
        tot = {k: sum(r[k] for r in rs) for k in ("points_before", "points_new", "open_before", "extra", "moved",
                                                  "switched", "newly_exposed", "unexposed_before",
                                                  "rescued_muzzles", "muzzles", "correct", "wrong", "unknown",
                                                  "unexposed", "unexposed_correct", "unexposed_unknown",
                                                  "unexposed_wrong", "missed", "merged", "invented", "duplicate",
                                                  "fb_extra", "fb_asks", "fb_moved", "fb_switched", "fb_points",
                                                  "fb_unresolved", "fb_cells", "extra_total")}
        return [f"{name}: {len(rs)} cases",
                f"  unassigned corner directions:  {tot['open_before']} in {sum(r['open_before'] > 0 for r in rs)} cases",
                f"  extra asks:                    {tot['extra']} total, med/p90/max {_stats([r['extra'] for r in rs])}"
                f"; {tot['moved']} moved asks, {sum(r['guard'] for r in rs)} cases hit the {RESCUE_GUARD}-ask guard",
                f"  moved asks that switched point: {tot['switched']} in {sum(r['switched'] > 0 for r in rs)} cases",
                f"  confirmed points:              {tot['points_before']} before, +{tot['points_new']} new "
                f"({sum(r['points_new'] > 0 for r in rs)} cases gained one); {tot['missed']} true points still missed",
                f"  bad estimates:                 {tot['invented']} invented, {tot['merged']} merged, "
                f"{tot['duplicate']} duplicate",
                f"  true points newly represented: {tot['newly_exposed']}",
                f"  later muzzles on a before-unexposed point: {tot['unexposed_before']} -> "
                f"{tot['rescued_muzzles']} now select a represented point",
                f"  later aimed muzzles:           {tot['muzzles']} -> {tot['correct']} correct, "
                f"{tot['wrong']} wrong, {tot['unknown']} UNKNOWN",
                f"  of those, still-unexposed ones: {tot['unexposed']} -> {tot['unexposed_correct']} correct, "
                f"{tot['unexposed_wrong']} wrong, {tot['unexposed_unknown']} UNKNOWN",
                f"  fallback search:               used in {sum(r['fb_used'] for r in rs)} cases; "
                f"{tot['fb_extra']} asks ({tot['fb_asks']} cell centres, {tot['fb_moved']} moved, "
                f"{tot['fb_switched']} switched), med/p90/max {_stats([r['fb_extra'] for r in rs])}; "
                f"+{tot['fb_points']} points; {sum(r['fb_guard'] for r in rs)} hit the {FALLBACK_GUARD}-ask guard",
                f"  all additional asks:           {tot['extra_total']} total, med/p90/max "
                f"{_stats([r['extra_total'] for r in rs])}",
                f"  firing area left unresolved:   {_stats([100 * r['fb_fraction'] for r in rs])} % of the "
                f"expanded firing box (med/p90/max), {tot['fb_unresolved']} cells of {tot['fb_cells']}"]

    one = [r for r in rows if r["points_before"] < 2]
    two = [r for r in rows if r["points_before"] >= 2]
    wrong = [r for r in rows if r["wrong"]]
    L = ["A4.3 phase 2/3: adaptive corner rescue, then the uncertainty-driven firing-area fallback", ""]
    L += block("cases the corners gave one point", one) + [""]
    L += block("cases the corners gave two points", two) + [""]
    L += block("all A4.3 cases", rows) + ["",
          "rescue-guard cases: " + (", ".join(str(r["id"]) for r in rows if r["guard"]) or "none"),
          "fallback-guard cases: " + (", ".join(str(r["id"]) for r in rows if r["fb_guard"]) or "none"),
          "cases with an affected muzzle still not represented: "
          + (", ".join(f"{r['id']} ({r['still_unexposed']})" for r in rows if r["still_unexposed"]) or "none"),
          "wrong answers: " + (", ".join(f"case {r['id']} ({r['wrong']})" for r in wrong) if wrong else "none")]
    return "\n".join(L)


# ---------------------------------------------------------------- A4.3 phase 4: observation-hull coverage map

A43H_DEPTH = 4  # fixed measurement resolution, chosen before seeing any result: 16^3 cells per firing box
HULL_TOL = 1e-6  # relative tolerance for "all asks on one side of this candidate facet"


def hull_faces(asks):
    """Outward supporting planes (n, d) of the convex hull of `asks`, as arrays (F, 3) and (F,).

    Brute force over point triples: a plane through three of the points whose remaining points all lie on
    one side supports the hull. With at most a few dozen asks that is a couple of thousand cheap tests, and
    it avoids a scipy dependency this repository does not have. A point is strictly inside the hull exactly
    when `P @ n - d < 0` for every face, which is the same statement `spans()` makes about the directions
    from that point to the asks: no plane through it puts every ask on one closed side."""
    P = np.asarray(asks, float)
    if len(P) < 4:
        return None
    scale = float(np.max(np.abs(P - P.mean(0)))) or 1.0
    faces = {}
    for a, b, c in itertools.combinations(range(len(P)), 3):
        n = np.cross(P[b] - P[a], P[c] - P[a])
        k = float(np.linalg.norm(n))
        if k < HULL_TOL * scale * scale:
            continue
        n = n / k
        s = P @ n - float(n @ P[a])
        if s.max() <= HULL_TOL * scale:
            pass
        elif s.min() >= -HULL_TOL * scale:
            n, s = -n, -s
        else:
            continue
        d = float(n @ P[a])
        faces[tuple(np.round(np.append(n, d / scale), 6))] = (n, d)
    if not faces:
        return None
    n = np.asarray([f[0] for f in faces.values()])
    return n, np.asarray([f[1] for f in faces.values()]), scale


def hull_interior(faces, pts):
    """Boolean mask: which of `pts` lie strictly inside the hull described by `faces`."""
    if faces is None:
        return np.zeros(len(pts), bool)
    n, d, scale = faces
    return (np.asarray(pts, float) @ n.T - d < -HULL_TOL * scale).all(1)


def _components(mask):
    """Sizes of the 6-connected components of a boolean 3-D cell mask, largest first."""
    seen = np.zeros_like(mask)
    sizes = []
    idx = list(zip(*np.nonzero(mask)))
    for start in idx:
        if seen[start]:
            continue
        seen[start] = True
        stack, size = [start], 0
        while stack:
            x, y, z = stack.pop()
            size += 1
            for q in ((x-1, y, z), (x+1, y, z), (x, y-1, z), (x, y+1, z), (x, y, z-1), (x, y, z+1)):
                if all(0 <= q[k] < mask.shape[k] for k in range(3)) and mask[q] and not seen[q]:
                    seen[q] = True
                    stack.append(q)
        sizes.append(size)
    return sorted(sizes, reverse=True)


def hull_cover(view, margin, probe=None, depth=A43H_DEPTH):
    """A4.3 phase 4 diagnostic: how much of the expanded firing-ship area the asks already gathered can
    safely answer, using no new asks at all.

    Every ask position confidently assigned to a confirmed point proves that point beats anything
    undiscovered there. `residual_map` already extends that to a later position inside the convex hull of
    one point's assigned asks: no plane through that position puts all of them on one side, so no hidden
    point can win there either. This measures the volume of that guarantee.

    The measurement is query-free recursive subdivision of the expanded firing box by cell corners: a cell
    is safely covered when all 8 of its corners lie inside one point's ask hull, which by convexity proves
    the whole cell is. A covered cell's children are covered too, so subdividing only the uncovered cells
    to a fixed depth gives the same answer as evaluating the uniform 2^depth grid, which is what this does.
    `depth` is measurement resolution only, never a proposed production search limit.

    Hidden aim points and later aimed muzzles are not used here: the hulls, the grid and the classification
    all come from the asks and their assignment alone."""
    a = corner_audit(view, margin, probe)
    lo, hi = a["box"]
    R, O = a["R"], a["O"]
    asks = {}
    for u, d in a["rays"].values():
        i = a["owner"](u, d)
        if i is not None:
            asks.setdefault(i, []).append(np.asarray(u, float))
    n = 2 ** depth
    axes = [np.linspace(lo[k], hi[k], n + 1) for k in range(3)]
    grid = np.stack(np.meshgrid(*axes, indexing="ij"), -1).reshape(-1, 3) @ R + O
    faces = {i: hull_faces(us) for i, us in asks.items()}
    covered = np.zeros((n, n, n), bool)
    for i, f in faces.items():
        ok = hull_interior(f, grid).reshape(n + 1, n + 1, n + 1)
        cell = np.ones((n, n, n), bool)
        for sx, sy, sz in itertools.product((0, 1), repeat=3):
            cell &= ok[sx:sx + n, sy:sy + n, sz:sz + n]
        covered |= cell
    cell_volume = float(np.prod((hi - lo) / n))
    open_mask = ~covered
    edge = np.zeros((n, n, n), bool)  # cells touching the firing-box surface, where an ask hull can never reach
    edge[0], edge[-1], edge[:, 0], edge[:, -1], edge[:, :, 0], edge[:, :, -1] = (True,) * 6
    return dict(queries=a["queries"], asks={i: len(us) for i, us in asks.items()}, points=len(a["points"]),
                faces=faces, cells=n ** 3, cell_volume=cell_volume,
                covered_cells=int(covered.sum()), open_cells=int(open_mask.sum()),
                regions=_components(open_mask), inner_regions=_components(open_mask & ~edge),
                inside=lambda m: any(hull_interior(f, [m])[0] for f in faces.values()))


def _a43h_case(case):
    records, margins = _LOADED
    v = view(case)
    margin = margins[case["ship_class"]][0]
    probe, stats = rescue_probe(v, margin, fallback=False)  # cheap adaptive corner rescue only, no phase 3
    c = hull_cover(v, margin, probe)
    row = dict(id=case["id"], group=case["group"], points_before=stats["before"], points=c["points"],
               queries=c["queries"], asks=sorted(c["asks"].values(), reverse=True),
               assigned=sum(c["asks"].values()), cells=c["cells"], covered_cells=c["covered_cells"],
               open_cells=c["open_cells"], cell_volume=c["cell_volume"],
               covered_volume=c["covered_cells"] * c["cell_volume"],
               open_volume=c["open_cells"] * c["cell_volume"],
               open_pct=100.0 * c["open_cells"] / c["cells"],
               regions=len(c["regions"]), largest_region=c["regions"][0] if c["regions"] else 0,
               inner_regions=len(c["inner_regions"]),
               largest_inner_region=c["inner_regions"][0] if c["inner_regions"] else 0)
    # hidden truth below this line: scoring the finished coverage map only. It never touched the map.
    before = {j for i, (ctr, q) in enumerate(stats["before_points"])
              for j, p in enumerate(case["points"]) if np.linalg.norm(ctr - p) <= q}
    truth = [tuple(map(float, p)) for p in case["points"]]
    row.update(muzzles=0, muzzles_covered=0, affected=0, affected_covered=0, still_unexposed=0,
               still_unexposed_covered=0)
    a = corner_audit(v, margin, probe)
    after = {j for i, (ctr, q) in enumerate(a["points"]) for j, p in enumerate(case["points"])
             if np.linalg.norm(ctr - p) <= q}
    for m in aimed_muzzles(case, records).values():
        sel = study.select(tuple(map(float, m)), truth)
        covered = bool(c["inside"](np.asarray(m, float)))
        row["muzzles"] += 1
        row["muzzles_covered"] += covered
        if sel not in before:  # one of the 58 originally affected later muzzles
            row["affected"] += 1
            row["affected_covered"] += covered
        if sel not in after:  # one of the 5 the cheap rescue still leaves unrepresented
            row["still_unexposed"] += 1
            row["still_unexposed_covered"] += covered
    return row


def a43h(jobs):
    """A4.3 phase 4: measure the firing-area coverage of the asks the corner audit and cheap rescue already
    spent, on the same 19 cases. Diagnostic only; no new oracle asks, no phase-3 fallback."""
    global _LOADED
    records, margins, mounts, _excluded, _inferred = load()
    _LOADED = records, margins
    todo = [c for c in cases(targets(), mounts) if c["id"] in set(A43_CASES)]
    assert len(todo) == len(A43_CASES), (len(todo), len(A43_CASES))
    CACHE.mkdir(parents=True, exist_ok=True)
    rows_path, sum_path = CACHE / "a43h_rows.jsonl", CACHE / "a43h_summary.txt"
    print(f"A4.3 phase 4: {len(todo)} cases, depth {A43H_DEPTH} -> {rows_path}", flush=True)
    os.nice(10)
    rows = []
    with open(rows_path, "w") as fh, Pool(min(jobs, 4)) as pool:
        for r in pool.imap(_a43h_case, todo, chunksize=1):
            rows.append(r)
            fh.write(json.dumps(r, default=float) + "\n")
            fh.flush()
            print(f"  {len(rows)}/{len(todo)} case {r['id']}: {r['points']} pts, {r['assigned']} assigned asks, "
                  f"{r['open_pct']:.1f}% uncovered, {r['regions']} regions "
                  f"({r['inner_regions']} interior), muzzles {r['muzzles_covered']}/{r['muzzles']} covered",
                  flush=True)
    out = _a43h_report(rows)
    sum_path.write_text(out)
    print(out + f"\n(rows: {rows_path}, summary: {sum_path})")


def _a43h_report(rows):
    def block(name, rs):
        if not rs:
            return [f"{name}: none"]
        tot = {k: sum(r[k] for r in rs) for k in ("assigned", "covered_volume", "open_volume", "muzzles",
                                                  "muzzles_covered", "affected", "affected_covered",
                                                  "still_unexposed", "still_unexposed_covered", "open_cells")}
        per = [n for r in rs for n in r["asks"]]
        return [f"{name}: {len(rs)} cases",
                f"  assigned ask positions:        {tot['assigned']} total over "
                f"{sum(len(r['asks']) for r in rs)} confirmed points; per point med/p90/max {_stats(per)}",
                f"  safely covered firing volume:  {tot['covered_volume']:.4g} m^3",
                f"  uncovered firing volume:       {tot['open_volume']:.4g} m^3",
                f"  uncovered share of the box:    {_stats([r['open_pct'] for r in rs])} % (med/p90/max)",
                f"  uncovered cells at the limit:  {tot['open_cells']} of {sum(r['cells'] for r in rs)}; "
                f"cell size med/p90/max {_stats([r['cell_volume'] for r in rs])} m^3",
                f"  uncovered regions per case:    {_stats([r['regions'] for r in rs])} (med/p90/max), "
                f"largest {_stats([r['largest_region'] for r in rs])} cells",
                f"  of those, not touching the box surface: {_stats([r['inner_regions'] for r in rs])} regions, "
                f"largest {_stats([r['largest_inner_region'] for r in rs])} cells",
                "  --- hidden truth, scoring the finished map only ---",
                f"  later aimed muzzles:           {tot['muzzles']} -> {tot['muzzles_covered']} in safely "
                f"covered space, {tot['muzzles'] - tot['muzzles_covered']} in uncovered space",
                f"  originally affected muzzles:   {tot['affected']} -> {tot['affected_covered']} covered, "
                f"{tot['affected'] - tot['affected_covered']} uncovered",
                f"  still-unexposed muzzles:       {tot['still_unexposed']} -> "
                f"{tot['still_unexposed_covered']} covered, "
                f"{tot['still_unexposed'] - tot['still_unexposed_covered']} uncovered"]

    one = [r for r in rows if r["points_before"] < 2]
    two = [r for r in rows if r["points_before"] >= 2]
    L = [f"A4.3 phase 4: firing-area coverage of the existing corner + cheap-rescue asks, depth {A43H_DEPTH} "
         f"({2 ** A43H_DEPTH}^3 cells), no new asks", ""]
    L += block("cases the corners gave one point", one) + [""]
    L += block("cases the corners gave two points", two) + [""]
    L += block("all A4.3 cases", rows) + ["",
          "per case: " + ", ".join(f"{r['id']} {r['open_pct']:.1f}%/{r['regions']}r" for r in rows)]
    return "\n".join(L)


# ---------------------------------------------------------------- A4.3 phase 5: angular-spread search

A43A_GRID = 9        # samples per axis on each firing-box face, coarse pass; numerical resolution only
A43A_REFINE = 3      # refinement rounds around the coarse winner
A43A_SHRINK = 0.25   # each round searches this fraction of the previous window
A43A_PRIMARY = 12    # experiment: fixed number of primary angular asks per case, no production stopping rule
A43A_GUARD = 24      # loose research guard on the angular stage's total extra asks, moved asks included
A43A_SNAPS = (1, 2, 3, 4, 6, 8, 12)


def _ray_list(rays):
    """The asks collected so far, JSON-ready, for `refine_points`."""
    return [(u.tolist(), None if d is None else d.tolist()) for u, d in rays.values()]


def _definite(cent, rad, W):
    """Vectorised `nearest`: for each world position in W, (index of the nearest confirmed point, whether
    that is definite). Definite means the farthest the winner can be is strictly nearer than the closest
    any rival can be, exactly the accepted rule in `nearest`."""
    D = np.linalg.norm(W[:, None, :] - cent[None], axis=2)
    b = D.argmin(1)
    far = D[np.arange(len(W)), b] + rad[b]
    ok = np.ones(len(W), bool)
    for i in range(len(cent)):
        ok &= (b == i) | (D[:, i] - rad[i] > far)
    return b, ok


def _angle_gaps(W, cent, rad, dirs):
    """(predicted point, definite, angular gap) for each world position: how far, in viewing angle seen
    from its predicted aim point, that position is from the nearest ask already assigned to that point.
    Positions whose nearest known point is not definite get gap -1 and are never chosen."""
    b, ok = _definite(cent, rad, W)
    gap = np.full(len(W), -1.0)
    for i in range(len(cent)):
        m = ok & (b == i)
        if not m.any():
            continue
        V = W[m] - cent[i]
        n = np.linalg.norm(V, axis=1, keepdims=True)
        V = V / np.where(n > 0, n, 1)
        gap[m] = math.pi if not len(dirs[i]) else np.arccos(np.clip(V @ dirs[i].T, -1, 1)).min(1)
    return b, ok, gap


def _face_grid(lo, hi, k, side, win, n):
    """n x n positions on the firing-box face normal to axis `k` at `side`, over the (s, t) window `win`."""
    ax = [a for a in range(3) if a != k]
    ss, ts = (np.linspace(*win[0], n), np.linspace(*win[1], n))
    P = np.zeros((n * n, 3))
    P[:, k] = side
    P[:, ax[0]] = np.repeat(ss, n)
    P[:, ax[1]] = np.tile(ts, n)
    return P


def angular_pick(points, asks, flo, fhi, R, O):
    """The next ask position: the point on the expanded firing box seen from the largest missing viewing
    direction of whichever confirmed aim point would definitely be selected there.

    For every confirmed point, its assigned ask positions become viewing directions from that point. A
    candidate is considered for point A only when the current point estimates say A is definitely the
    nearest known point from it (`_definite`, the accepted `nearest` rule), so no candidate is judged
    across an uncertain switch boundary. Its value is the angle to the nearest existing viewing direction
    for A, and the best candidate over all points and all six faces wins.

    Deterministic coarse-to-fine: a fixed A43A_GRID square on each of the six faces, then A43A_REFINE
    rounds on the winning face over a window shrinking by A43A_SHRINK, clipped to the face. Those are
    numerical resolution constants, fixed before the run, not a search budget.

    -> (angular gap in radians, local position, predicted point index) or None when nothing is definite."""
    cent = np.asarray([c for c, r in points], float)
    rad = np.asarray([r for c, r in points], float)
    dirs = []
    for i in range(len(points)):
        us = np.asarray(asks.get(i, []), float).reshape(-1, 3) - cent[i]
        n = np.linalg.norm(us, axis=1, keepdims=True)
        dirs.append(us[(n > 0).ravel()] / n[n > 0].reshape(-1, 1) if len(us) else us)
    best = None  # (gap, face k, side, s, t, point)
    for k in range(3):
        ax = [a for a in range(3) if a != k]
        win0 = ((flo[ax[0]], fhi[ax[0]]), (flo[ax[1]], fhi[ax[1]]))
        for side in (float(flo[k]), float(fhi[k])):
            P = _face_grid(flo, fhi, k, side, win0, A43A_GRID)
            b, ok, gap = _angle_gaps(P @ R + O, cent, rad, dirs)
            j = int(gap.argmax())
            if gap[j] >= 0 and (best is None or gap[j] > best[0]):
                best = (float(gap[j]), k, side, float(P[j, ax[0]]), float(P[j, ax[1]]), int(b[j]))
    if best is None:
        return None
    k, side = best[1], best[2]
    ax = [a for a in range(3) if a != k]
    half = [(float(fhi[a]) - float(flo[a])) / 2 for a in ax]
    for _ in range(A43A_REFINE):
        half = [w * A43A_SHRINK for w in half]
        win = tuple((max(float(flo[a]), best[3 + q] - half[q]), min(float(fhi[a]), best[3 + q] + half[q]))
                    for q, a in enumerate(ax))
        P = _face_grid(flo, fhi, k, side, win, A43A_GRID)
        b, ok, gap = _angle_gaps(P @ R + O, cent, rad, dirs)
        j = int(gap.argmax())
        if gap[j] >= 0 and gap[j] > best[0]:
            best = (float(gap[j]), k, side, float(P[j, ax[0]]), float(P[j, ax[1]]), int(b[j]))
    pos = np.zeros(3)
    pos[k] = side
    pos[ax[0]], pos[ax[1]] = best[3], best[4]
    return best[0], pos, best[5]


def angular_probe(view, margin, primary=A43A_PRIMARY, guard=A43A_GUARD, rescue_guard=RESCUE_GUARD,
                  near_target=None):
    """A4.3 phase 5: the 8 outer corners and the accepted cheap rescue, then asks chosen purely by the
    largest missing viewing angle (`angular_pick`).

    Each primary ask goes into the same shared `locate()`. If it can be assigned to a known point it is
    simply another observation of that point, which shrinks that point's missing-angle map and moves the
    next ask elsewhere. If it cannot be assigned it is a direction toward something unknown, and the same
    accepted moved-ask rescue pursues it. After any new confirmed point the assignments and the whole
    candidate choice are recomputed from scratch. Hidden aim points and later muzzles are never consulted.

    With `near_target` (A6, metres) the adaptive asks are instead chosen on the six faces of the target's
    runtime box grown by that pad, in the target frame. Nothing else changes: the same candidate rule, the
    same point confirmation and the same guard. The pad is a probe-placement choice only and is not a claim
    that every aim point lies inside that box.

    Returns (probe, stats); `stats["snaps"]` holds the confirmed points after each primary ask."""
    C, H, T = view["target_box"]
    tlo, thi = target_box(C, H)
    flo, fhi = firing_box(*view["ship_box"], margin)
    R, O = view["ship_rotation"], view["ship_position"]
    if near_target is None:
        plo, phi, M, off = flo, fhi, R, O
    else:
        C, H = np.asarray(C, float), np.asarray(H, float)
        plo, phi, M, off = C - H - near_target, C + H + near_target, T, np.zeros(3)
    stats = dict(before=0, before_points=[], after_rescue_points=[], open_before=0,
                 rescue_extra=0, rescue_moved=0, rescue_switched=0, rescue_guard=False,
                 primary=0, extra=0, moved=0, switched=0, guard=False, stalled=False, picks=[], snaps={},
                 trace=[])

    def probe(h):
        points = h["points"]
        stats.update(before=len(points), before_points=list(points))
        seen = [len(points)]

        start = h["count"]()
        anchors = sorted(k for k, (u, d) in h["rays"].items() if d is not None and h["owner"](u, d) is None)
        stats["open_before"] = len(anchors)
        _pursue(h, tlo, thi, T, anchors, lambda n: h["count"]() - start + n <= rescue_guard,
                stats, "rescue_", seen)
        stats["rescue_extra"] = h["count"]() - start
        stats["after_rescue_points"] = list(points)
        stats["pre_rays"] = _ray_list(h["rays"])  # #184 A7: observations available before the angular stage

        start2 = h["count"]()
        spend = lambda n: h["count"]() - start2 + n <= guard  # noqa: E731

        def assigned():
            out = {}
            for u, d in h["rays"].values():
                i = h["owner"](u, d)
                if i is not None:
                    out.setdefault(i, []).append(u)
            return out

        def note(gap):
            """#184 A6: the state a `largest remaining angular gap <= T` rule would test, recorded before
            the ask it precedes. `gap` is None when no candidate is definite (nothing left to choose)."""
            stats["trace"].append(dict(
                gap=None if gap is None else math.degrees(gap), primary=stats["primary"],
                extra=h["count"]() - start2, points=[(c.tolist(), float(r)) for c, r in points]))

        while stats["primary"] < primary:
            h["locate"]()
            if not points:
                stats["stalled"] = True
                break
            if not spend(3):  # the spare 2 cover `locate`'s along-ray confirmation
                stats["guard"] = True
                break
            pick = angular_pick(points, assigned(), plo, phi, M, off)
            if pick is None:  # nothing on the box has a definite nearest known point
                note(None)
                stats["stalled"] = True
                break
            gap, pos, want = pick
            note(gap)
            v = pos @ M + off
            key = tuple(map(float, v))
            if key in h["rays"]:  # the best candidate is an ask already spent: no new viewing angle left
                stats["stalled"] = True
                break
            had = len(points)
            h["rays"][key] = (v, dv := h["ask"](v))
            stats["primary"] += 1
            h["locate"]()
            got = h["owner"](v, dv)
            if got is None and dv is not None:
                _pursue(h, tlo, thi, T, [key], spend, stats, "", seen)
                got = h["owner"](v, dv)
            stats["picks"].append(dict(angle=math.degrees(gap), predicted=want, got=got,
                                       new_points=len(points) - had,
                                       outcome="predicted" if got == want else "other" if got is not None
                                       else "new_point" if len(points) > had else "unassigned"))
            stats["snaps"][stats["primary"]] = dict(
                primary=stats["primary"], extra=h["count"]() - start2, switched=stats["switched"],
                guard=stats["guard"], points=[(c.tolist(), float(r)) for c, r in points],
                rays=_ray_list(h["rays"]))  # #184 A7: prefix refinement input
        final = angular_pick(points, assigned(), plo, phi, M, off) if points else None  # #184 A6 end state
        note(None if final is None else final[0])
        stats["extra"] = h["count"]() - start2
        stats["rays"] = _ray_list(h["rays"])  # #184 A6 post-hoc refinement input
    return probe, stats


def _represented(points, truth):
    """Hidden truth, reporting only: which true aim points some estimate covers."""
    return {j for c, r in points for j, p in enumerate(truth) if np.linalg.norm(np.asarray(c) - p) <= r}


def _a43a_case(case):
    records, margins = _LOADED
    v = view(case)
    margin = margins[case["ship_class"]][0]
    probe, stats = angular_probe(v, margin)
    corner_audit(v, margin, probe)
    muzzles = aimed_muzzles(case, records)
    truth = case["points"]
    sel = [study.select(tuple(map(float, m)), [tuple(map(float, p)) for p in truth]) for m in muzzles.values()]
    before = _represented(stats["before_points"], truth)          # the 8 corners alone
    after_rescue = _represented(stats["after_rescue_points"], truth)  # plus the accepted cheap rescue
    affected = [x for x in sel if x not in before]                # of the original 58
    remaining = [x for x in sel if x not in after_rescue]         # of the 5 the cheap rescue still misses

    rows, last = [], dict(primary=0, extra=0, switched=stats["rescue_switched"], guard=False,
                          points=[(c.tolist(), float(r)) for c, r in stats["after_rescue_points"]])
    for k in A43A_SNAPS:
        snap = stats["snaps"].get(k, last)  # carry the final state forward when the case stopped earlier
        last = snap
        pts = [(np.asarray(c), r) for c, r in snap["points"]]
        got = score(case, dict(located=[(i, c, r) for i, (c, r) in enumerate(pts)],
                               answer=lambda m: UNKNOWN, queries=0), {})
        rep = _represented(pts, truth)
        rows.append(dict(snap=k, primary=snap["primary"], extra=snap["extra"],
                         total_extra=stats["rescue_extra"] + snap["extra"],
                         points=len(pts), new_points=len(pts) - stats["before"],
                         rescue_points=len(stats["after_rescue_points"]),
                         switched=snap["switched"], guard=snap["guard"],
                         **{q: got[q] for q in ("missed", "invented", "merged", "duplicate")},
                         affected_represented=sum(x in rep for x in affected),
                         all_affected=bool(affected) and all(x in rep for x in affected),
                         remaining_represented=sum(x in rep for x in remaining)))
    # #184 A6: the angular-gap trace. `missing` uses hidden truth for reporting only; it never influenced
    # which position was asked or when the search advanced.
    trace = []
    for t in stats["trace"]:
        rep = _represented([(np.asarray(c), r) for c, r in t["points"]], truth)
        trace.append(dict(gap=t["gap"], primary=t["primary"], extra=t["extra"],
                          total_extra=stats["rescue_extra"] + t["extra"], points=len(t["points"]),
                          missing=sorted({x for x in sel if x not in rep}),
                          missing_remaining=sorted({x for x in remaining if x not in rep})))
    return dict(id=case["id"], trace=trace, before=stats["before"], open_before=stats["open_before"],
                rescue_extra=stats["rescue_extra"], rescue_switched=stats["rescue_switched"],
                primary=stats["primary"], extra=stats["extra"], moved=stats["moved"],
                switched=stats["switched"], guard=stats["guard"], stalled=stats["stalled"],
                muzzles=len(sel), affected=len(affected), remaining=len(remaining),
                picks=stats["picks"], snaps=rows)


def a43a(jobs):
    """A4.3 phase 5: the angular-spread experiment on the same 19 cases. No phase-3 fallback."""
    global _LOADED
    records, margins, mounts, _excluded, _inferred = load()
    _LOADED = records, margins
    todo = [c for c in cases(targets(), mounts) if c["id"] in set(A43_CASES)]
    assert len(todo) == len(A43_CASES), (len(todo), len(A43_CASES))
    CACHE.mkdir(parents=True, exist_ok=True)
    rows_path, sum_path = CACHE / "a43a_rows.jsonl", CACHE / "a43a_summary.txt"
    print(f"A4.3 phase 5: {len(todo)} cases, up to {A43A_PRIMARY} primary angular asks -> {rows_path}", flush=True)
    os.nice(10)
    rows = []
    with open(rows_path, "w") as fh, Pool(min(jobs, 4)) as pool:
        for r in pool.imap(_a43a_case, todo, chunksize=1):
            rows.append(r)
            fh.write(json.dumps(r, default=float) + "\n")
            fh.flush()
            end = r["snaps"][-1]
            print(f"  {len(rows)}/{len(todo)} case {r['id']}: {r['primary']} primary, +{r['extra']} extra "
                  f"(rescue {r['rescue_extra']}), {r['before']}->{end['points']} pts, "
                  f"{end['affected_represented']}/{r['affected']} affected represented"
                  f"{', GUARD' if r['guard'] else ''}{', STALLED' if r['stalled'] else ''}", flush=True)
    out = _a43a_report(rows)
    sum_path.write_text(out)
    print(out + f"\n(rows: {rows_path}, summary: {sum_path})")


def _rescue_points(row):
    """Confirmed points a case had before its first angular ask: the 8 corners plus the cheap rescue. The
    snapshot `points` column counts those too, so the angular stage's own gain is the difference."""
    if "rescue_points" in row["snaps"][0]:
        return row["snaps"][0]["rescue_points"]
    return row["snaps"][0]["points"] - (row["picks"][0]["new_points"] if row["picks"] else 0)


def _a43a_report(rows):
    picks = [p for r in rows for p in r["picks"]]
    L = [f"A4.3 phase 5: asks chosen by largest missing viewing angle, {len(rows)} cases, "
         f"up to {A43A_PRIMARY} primary asks, {A43A_GUARD}-ask angular-stage guard", "",
         f"start state: {sum(r['before'] for r in rows)} points from the 8 corners, "
         f"{sum(r['open_before'] for r in rows)} unassigned corner directions, cheap rescue spent "
         f"{sum(r['rescue_extra'] for r in rows)} asks ({sum(r['rescue_switched'] for r in rows)} switched)",
         f"later aimed muzzles: {sum(r['muzzles'] for r in rows)}; originally affected "
         f"{sum(r['affected'] for r in rows)}; still unrecovered after the cheap rescue "
         f"{sum(r['remaining'] for r in rows)}", "",
         f"points after the 8 corners plus the cheap rescue: {sum(_rescue_points(r) for r in rows)}; "
         "the +angular column below is what the angular asks added on top of that", "",
         "snapshot table (all 19 cases; a case that stopped early carries its final state forward)",
         "  primary  asks(angular)  asks(total)  points  +angular  inv/mer/dup  affected repr  cases all  "
         "last5  switch  guard",
         ]
    for k in A43A_SNAPS:
        ss = [s for r in rows for s in r["snaps"] if s["snap"] == k]
        pts = sum(s["points"] for s in ss)
        L.append(f"  {k:>7}  {sum(s['extra'] for s in ss):>12}  {sum(s['total_extra'] for s in ss):>11}  "
                 f"{pts:>6}  {pts - sum(_rescue_points(r) for r in rows):>8}  "
                 f"{sum(s['invented'] for s in ss)}/{sum(s['merged'] for s in ss)}/"
                 f"{sum(s['duplicate'] for s in ss)}".ljust(13)
                 + f"  {sum(s['affected_represented'] for s in ss):>3} of {sum(r['affected'] for r in rows):<7}"
                 f"  {sum(s['all_affected'] for s in ss):>9}  {sum(s['remaining_represented'] for s in ss):>5}  "
                 f"{sum(s['switched'] for s in ss):>6}  {sum(s['guard'] for s in ss):>5}")
    ang = [p["angle"] for p in picks]
    out = Counter(p["outcome"] for p in picks)
    L += ["",
          f"primary asks made: {len(picks)} over {len(rows)} cases; "
          f"{sum(r['primary'] for r in rows)} counted, {sum(r['guard'] for r in rows)} cases hit the guard, "
          f"{sum(r['stalled'] for r in rows)} stalled (no new viewing angle left)",
          f"chosen angular separation from the nearest prior ask of the predicted point: "
          f"med/p90/max {_stats(ang)} degrees" if ang else "no primary asks made",
          f"outcome of each primary ask: {out['predicted']} selected the predicted known point, "
          f"{out['other']} selected another known point, {out['new_point']} were unassigned and led to a "
          f"newly confirmed point, {out['unassigned']} stayed unassigned",
          f"moved asks in the angular stage: {sum(r['moved'] for r in rows)}, "
          f"{sum(r['switched'] for r in rows)} switched point", "",
          "per case: " + ", ".join(
              f"{r['id']} {r['primary']}p/+{r['extra']}a/{r['snaps'][-1]['points']}pts/"
              f"{r['snaps'][-1]['affected_represented']}of{r['affected']}" for r in rows)]
    first = {}
    for r in rows:
        if not r["remaining"]:
            continue
        hit = [s["snap"] for s in r["snaps"] if s["remaining_represented"] == r["remaining"]]
        first[r["id"]] = hit[0] if hit else None
    L += ["", "hidden truth, reporting only - snapshot at which the 5 muzzle selections the cheap rescue "
          "still missed become represented:",
          "  " + (", ".join(f"case {k}: {'never' if v is None else f'after {v} primary asks'}"
                            for k, v in first.items()) or "none")]
    return "\n".join(L)


# ---------------------------------------------------------------- A6: largest-angular-gap stopping rule

A6_EVIDENCE = Path(__file__).with_name("A6_ANGULAR_STOP.md")


def _a6_rule(trace):
    """Gap values the rule `stop when largest remaining angular gap <= T` would test, in order. A state with
    no definite candidate left has nothing to choose and counts as gap 0, which stops at any threshold."""
    return [(0.0 if t["gap"] is None else t["gap"], t) for t in trace]


def _a6_report(rows):
    unsafe = [(g, r["id"], t) for r in rows for g, t in _a6_rule(r["trace"]) if t["missing"]]
    g_miss = min((g for g, _i, _t in unsafe), default=None)
    low, nostop = {}, []
    for r in rows:
        safe = [(g, t) for g, t in _a6_rule(r["trace"]) if not t["missing"]]
        if safe:
            low[r["id"]] = min(safe)[0]
        else:
            nostop.append(r["id"])
    T = max(low.values()) if low else None
    ok = bool(low) and not nostop and g_miss is not None and T < g_miss
    L = ["# Issue #184 A6: is the largest remaining angular gap alone a usable stopping rule?", "",
         f"Rule under test: `stop when largest remaining angular gap <= T`. {len(rows)} A4.3 boundary cases, "
         f"the existing phase-5 angular-spread search, {A43A_PRIMARY} primary asks, {A43A_GUARD}-ask "
         "angular-stage limit. Hidden truth is used for reporting only and never steered the search.", "",
         f"- smallest gap observed while a required point was still missing: "
         f"{'none - no state was ever missing a required point' if g_miss is None else f'{g_miss:.3f} deg'}",
         f"- cases that never reach a state with all required points represented: "
         f"{', '.join(map(str, nostop)) or 'none'}",
         f"- highest per-case lowest safe gap (the smallest T that still stops every case): "
         f"{'n/a' if T is None else f'{T:.3f} deg'}", ""]
    if ok:
        stops = {}
        for r in rows:
            g, t = next((g, t) for g, t in _a6_rule(r["trace"]) if g <= T)
            stops[r["id"]] = t
        L += [f"**Verdict: a safe threshold range exists: {T:.3f} deg <= T < {g_miss:.3f} deg.**",
              f"At T = {T:.3f} deg the worst case spends {max(t['primary'] for t in stops.values())} primary "
              f"asks and {max(t['extra'] for t in stops.values())} actual angular-stage asks "
              f"({max(t['total_extra'] for t in stops.values())} including the cheap rescue).", ""]
    else:
        L += ["**Verdict: the largest angular gap alone is REJECTED as a stopping rule.** "
              + ("Some case never represents its required points at all, so no threshold stops it safely."
                 if nostop else
                 f"A state still missing a required point reaches {g_miss:.3f} deg, at or below the "
                 f"{T:.3f} deg every case needs in order to stop, so every threshold that stops all cases "
                 "also stops at least one case early." if T is not None else ""), ""]
        stops = {}
    L += ["## Per case", "",
          "| case | required | lowest gap while missing | lowest safe gap | lowest-gap safe state (primary / "
          "angular asks / points) | stops at T |", "|---|---|---|---|---|---|"]
    for r in rows:
        miss = [g for g, t in _a6_rule(r["trace"]) if t["missing"]]
        safe = [(g, t) for g, t in _a6_rule(r["trace"]) if not t["missing"]]
        f = min(safe)[1] if safe else None
        s = stops.get(r["id"])
        start = len(r["trace"][0]["missing"]) if r["trace"] else 0
        c_miss = f"{min(miss):.3f}" if miss else "never missing"
        c_low = f"{low[r['id']]:.3f}" if r["id"] in low else "never safe"
        c_first = f"{f['primary']} / {f['extra']} / {f['points']}" if f else "-"
        c_stop = f"{s['primary']} / {s['extra']}" if s else "-"
        L.append(f"| {r['id']} | {start} at start | {c_miss} | {c_low} | {c_first} | {c_stop} |")
    L += ["", "## Full gap trace", "",
          "Each row is a state the rule would have tested: before the first angular ask, before every later "
          "angular ask, and after the final primary ask.", "",
          "| case | primary spent | angular asks spent | points | largest gap (deg) | required still missing |",
          "|---|---|---|---|---|---|"]
    for r in rows:
        for g, t in _a6_rule(r["trace"]):
            L.append(f"| {r['id']} | {t['primary']} | {t['extra']} | {t['points']} | "
                     f"{'none left (0)' if t['gap'] is None else f'{g:.3f}'} | "
                     f"{len(t['missing'])}{' ' + str(t['missing']) if t['missing'] else ''} |")
    L += ["", "## Notes", "",
          "- Cases 12234 and 12376 carry the five muzzle selections the pre-angular cheap rescue still "
          "missed (3 and 2 muzzles). Several muzzles of one case select the same aim point, so the "
          "`required still missing` column counts distinct unrepresented points, not muzzles.",
          "- The gap is not monotone as asks accumulate: confirming a new point re-partitions the box and "
          "can raise the largest gap again (12234 goes 46.8 -> 68.8 deg across its first angular ask). A "
          "threshold rule therefore cannot assume the sequence only descends toward it.", ""]
    return "\n".join(L)


def a6(jobs):
    """#184 A6: run the existing phase-5 angular search and test a gap-only stopping rule on its trace."""
    global _LOADED
    records, margins, mounts, _excluded, _inferred = load()
    _LOADED = records, margins
    todo = [c for c in cases(targets(), mounts) if c["id"] in set(A43_CASES)]
    assert len(todo) == len(A43_CASES), (len(todo), len(A43_CASES))
    CACHE.mkdir(parents=True, exist_ok=True)
    rows_path = CACHE / "a6_rows.jsonl"
    print(f"#184 A6: {len(todo)} cases -> {rows_path}", flush=True)
    os.nice(10)
    rows = []
    with open(rows_path, "w") as fh, Pool(min(jobs, 4)) as pool:
        for r in pool.imap(_a43a_case, todo, chunksize=1):
            rows.append(r)
            fh.write(json.dumps(r, default=float) + "\n")
            fh.flush()
            print(f"  {len(rows)}/{len(todo)} case {r['id']}: {len(r['trace'])} traced states", flush=True)
    rows.sort(key=lambda r: r["id"])
    out = _a6_report(rows)
    A6_EVIDENCE.write_text(out)
    print(out + f"\n(rows: {rows_path}, evidence: {A6_EVIDENCE})")


# ---------------------------------------------------------------- A6: near-target angular probing

A6_NEAR_GAPS = (100, 1000, 8000)  # turret-relevant standoffs; 20/100 km are not meaningful firing ranges here
A6_NEAR_PAD = 50.0                # probe-placement pad on the target runtime box, not a bound on aim points


def _restandoff(case, anchor, gaps):
    """The same geometry at other standoffs: the ship is translated along its own bearing from `anchor`
    by the gap difference, exactly what `cases` does when it builds the members of a multi-gap group.
    Target, bearing, mount, turret and all rotations are untouched; only the distance changes."""
    d = case["origin"] - anchor
    d = d / np.linalg.norm(d)
    for gap in gaps:
        shift = d * (gap - case["gap"])
        yield dict(case, gap=gap, origin=case["origin"] + shift, position=case["position"] + shift)


def a6_near_variants(ts, mounts):
    """The 19 A4.3 boundary cases reproduced at each A6 near-target gap. The bearing is in the bisector
    plane of the target's nearest aim-point pair, so the standoff is measured from that pair's frame."""
    base = {c["id"]: c for c in cases(ts, mounts) if c["id"] in set(A43_CASES)}
    assert len(base) == len(A43_CASES), (len(base), len(A43_CASES))
    tmap = {t["component"]: t for t in ts}
    for cid in A43_CASES:
        c = base[cid]
        t = tmap[c["target"]]
        pairs = [(a, b) for a in range(len(t["points"])) for b in range(a + 1, len(t["points"]))]
        a, b = min(pairs, key=lambda ab: study.norm(study.sub(t["points"][ab[0]], t["points"][ab[1]])))
        yield from _restandoff(c, np.asarray(study.pair_frame(t, a, b)[0]) @ c["box"][2], A6_NEAR_GAPS)


def refine_points(points, rays):
    """#184 A6: tighten the confirmed point estimates from the probe lines already collected, after the
    search has finished. No new asks, and the refined positions never feed back into probe placement, so
    both versions see exactly the same observations.

    A ray is assigned to a point when it passes through exactly one estimate's ball, the ownership rule
    `_search.owner` already uses. For each point with two or more assigned rays the tightest pairwise
    crossing under the unchanged `crossing` rule becomes a candidate, with the same radius formula
    `_search.locate` uses. It is taken only when it is strictly tighter, its whole ball lies inside the
    original ball, and every assigned ray still passes through it. Containment is what keeps the estimate
    about the same aim point: it can neither drift onto a neighbour nor grow to merge two, and no estimate
    is added or removed, so the refined set cannot invent or duplicate a point either.

    -> (refined points, count refined, [reason each unrefined point was left alone])"""
    R = [(np.asarray(u, float), None if d is None else np.asarray(d, float)) for u, d in rays]
    out, refined, skipped = list(points), 0, []
    for i, (c, r) in enumerate(points):
        # ponytail: O(assigned^2) pairwise crossings; assigned rays are tens, not thousands
        own = [(u, d) for u, d in R if d is not None and _on_ray(u, d, c, r)
               and sum(_on_ray(u, d, cc, rr) for cc, rr in points) == 1]
        if len(own) < 2:
            skipped.append("under 2 assigned rays")
            continue
        best = None
        for (ua, da), (ub, db) in itertools.permutations(own, 2):  # either ray of a pair may be the anchor
            h = crossing(ua, da, ub, db)
            if h is None:
                continue
            s, err = h
            x = ua + s * da
            rr = err + EPS * s + _rho(ua, x)
            if best is None or rr < best[1]:
                best = (x, float(rr))
        if best is None:
            skipped.append("no accepted crossing")
        elif not (best[1] < r and float(np.linalg.norm(best[0] - c)) + best[1] <= r):
            skipped.append("not strictly inside the current ball")
        elif not all(_on_ray(u, d, *best) for u, d in own):
            skipped.append("an assigned ray misses the tighter ball")
        else:
            out[i] = best
            refined += 1
    return out, refined, skipped


def _cover(points, truth):
    """Hidden truth, reporting only: which authored aim points each estimate covers."""
    return [sorted(j for j, p in enumerate(truth) if np.linalg.norm(np.asarray(c) - p) <= r) for c, r in points]


def _scored(case, points, rays, muzzles, queries):
    """Score one set of point estimates against hidden truth, before and after `refine_points` on exactly
    the rays given. -> (baseline score, refined score with the refinement-safety fields)."""
    truth = case["points"]
    pts = [(np.asarray(c, float), r) for c, r in points]
    loc = [(i, c, r) for i, (c, r) in enumerate(pts)]
    got = score(case, dict(located=loc, answer=lambda m: nearest(loc, m), queries=queries), muzzles)
    rpts, n_ref, skipped = refine_points(pts, rays)
    rloc = [(i, c, r) for i, (c, r) in enumerate(rpts)]
    rgot = score(case, dict(located=rloc, answer=lambda m: nearest(rloc, m), queries=queries), muzzles)
    keys = ("correct", "wrong", "unknown", "invented", "merged", "duplicate", "missed", "radius", "error")
    return got, dict({q: rgot[q] for q in keys}, count=n_ref, skipped=skipped,
                     identity_changed=sum(x != y for x, y in zip(_cover(pts, truth), _cover(rpts, truth))))


def _a6_near_run(case, v, margin, muzzles, near_target):
    """One angular-search run, near-target or firing-ship-box, with the A6 near-target reporting fields."""
    probe, stats = angular_probe(v, margin, near_target=near_target)
    a = corner_audit(v, margin, probe)
    truth = case["points"]
    needed = sorted({study.select(tuple(map(float, m)), [tuple(map(float, p)) for p in truth])
                     for m in muzzles.values()})
    pre = stats["after_rescue_points"]                       # 8 corners plus the accepted cheap rescue
    corners = a["queries"] - stats["rescue_extra"] - stats["extra"]

    def state(points, extra):
        rep = _represented([(np.asarray(c), r) for c, r in points], truth)
        return dict(points=len(points), exposed=sorted(rep), missing_needed=[x for x in needed if x not in rep],
                    missing_authored=[j for j in range(len(truth)) if j not in rep],
                    angular_extra=extra, asks=corners + stats["rescue_extra"] + extra)

    steps = [state([(np.asarray(c), r) for c, r in pre], 0)]
    for k in sorted(stats["snaps"]):
        sn = stats["snaps"][k]
        steps.append(dict(state([(np.asarray(c), r) for c, r in sn["points"]], sn["extra"]), primary=k))
    expose = next((st for st in steps if not st["missing_needed"]), None)
    all_authored = next((st for st in steps if not st["missing_authored"]), None)

    points = stats["snaps"][max(stats["snaps"])]["points"] if stats["snaps"] else \
        [(c.tolist(), float(r)) for c, r in pre]
    got, refined = _scored(case, points, stats.get("rays", []), muzzles, a["queries"])
    return dict(needed=needed, refined=refined,
                radius=got["radius"], error=got["error"], missed=got["missed"],
                authored=len(truth), corners=corners, rescue_extra=stats["rescue_extra"],
                primary=stats["primary"], angular_extra=stats["extra"], asks=a["queries"],
                guard=stats["guard"], stalled=stats["stalled"],
                gaps=[t["gap"] for t in stats["trace"]], steps=steps,
                expose_asks=expose and expose["asks"], expose_primary=expose and expose.get("primary", 0),
                missing_needed=steps[-1]["missing_needed"], missing_authored=steps[-1]["missing_authored"],
                authored_asks=all_authored and all_authored["asks"],
                final_points=steps[-1]["points"],
                **{q: got[q] for q in ("correct", "wrong", "unknown", "invented", "merged", "duplicate")})


def _a6_near_case(case):
    records, margins = _LOADED
    v, margin = view(case), margins[case["ship_class"]][0]
    muzzles = aimed_muzzles(case, records)
    return dict(id=case["id"], gap=case["gap"], target=case["target"], ship=case["ship"],
                muzzles=len(muzzles),
                near=_a6_near_run(case, v, margin, muzzles, A6_NEAR_PAD),
                firing=_a6_near_run(case, v, margin, muzzles, None))


def a6_near(jobs):
    """A6: does placing the A4.3 angular probes near the target instead of around the firing ship make
    aim-point discovery independent of firing range? Same 19 boundary geometries at 100 m, 1 km and 8 km,
    each run both ways. No stopping rule is chosen here."""
    global _LOADED
    records, margins, mounts, _excluded, _inferred = load()
    _LOADED = records, margins
    todo = list(a6_near_variants(targets(), mounts))
    CACHE.mkdir(parents=True, exist_ok=True)
    rows_path, sum_path = CACHE / "a6_near_rows.jsonl", CACHE / "a6_near_summary.txt"
    print(f"A6 near-target: {len(todo)} cases ({len(A43_CASES)} geometries x {len(A6_NEAR_GAPS)} gaps) -> {rows_path}", flush=True)
    os.nice(10)
    rows = []
    with open(rows_path, "w") as fh, Pool(min(jobs, 4)) as pool:
        for r in pool.imap(_a6_near_case, todo, chunksize=1):
            rows.append(r)
            fh.write(json.dumps(r, default=float) + "\n")
            fh.flush()
            n, f = r["near"], r["firing"]
            print(f"  {len(rows)}/{len(todo)} case {r['id']} @{r['gap']}m: near {n['asks']} asks, "
                  f"{n['final_points']} pts, needed missing {len(n['missing_needed'])}, "
                  f"authored missing {len(n['missing_authored'])}{', GUARD' if n['guard'] else ''} | "
                  f"firing {f['asks']} asks, needed missing {len(f['missing_needed'])}", flush=True)
    out = _a6_near_report(rows)
    sum_path.write_text(out)
    print(out + f"\n(rows: {rows_path}, summary: {sum_path})")


def _stats2(xs):
    xs = sorted(xs)
    return f"{np.median(xs):.3g}/{max(xs):.3g}" if xs else "n/a"


def _a6_near_report(rows):
    L = [f"A6 near-target: angular probes on the target runtime box + {A6_NEAR_PAD:g} m, versus the A4.3 firing-ship box",
         f"{len(rows)} cases: {len(A43_CASES)} boundary geometries at {', '.join(map(str, A6_NEAR_GAPS))} m", "",
         "  method  gap(m)  cases  asks med/p90/max  angular-stage extra med/max  final pts  "
         "cases exposing all needed  all authored  guard  wrong  unknown"]
    for meth in ("near", "firing"):
        for g in A6_NEAR_GAPS:
            rs = [r[meth] for r in rows if r["gap"] == g]
            L.append(f"  {meth:<6}  {g:>6}  {len(rs):>5}  {_stats([r['asks'] for r in rs]):<16}  "
                     f"{_stats([r['angular_extra'] for r in rs]):<27}  "
                     f"{sum(r['final_points'] for r in rs):>9}  "
                     f"{sum(not r['missing_needed'] for r in rs):>25}  "
                     f"{sum(not r['missing_authored'] for r in rs):>12}  "
                     f"{sum(r['guard'] for r in rs):>5}  {sum(r['wrong'] for r in rs):>5}  "
                     f"{sum(r['unknown'] for r in rs):>7}")
    L += ["", "asks needed before the last needed aim point was exposed (cases that exposed them all):"]
    for meth in ("near", "firing"):
        for g in A6_NEAR_GAPS:
            e = [r[meth]["expose_asks"] for r in rows if r["gap"] == g and r[meth]["expose_asks"] is not None]
            L.append(f"  {meth:<6} {g:>6} m: {len(e)} cases, asks med/p90/max {_stats(e) if e else 'n/a'}")
    L += ["", "hidden truth, reporting only - authored aim points never exposed (never steers the search):"]
    for meth in ("near", "firing"):
        for g in A6_NEAR_GAPS:
            rs = [r for r in rows if r["gap"] == g]
            L.append(f"  {meth:<6} {g:>6} m: {sum(len(r[meth]['missing_authored']) for r in rs)} of "
                     f"{sum(r[meth]['authored'] for r in rs)} authored points left undiscovered in "
                     f"{sum(bool(r[meth]['missing_authored']) for r in rs)} cases")
    L += ["", "missing needed points before the angular stage (8 corners + cheap rescue), by gap:"]
    for g in A6_NEAR_GAPS:
        rs = [r for r in rows if r["gap"] == g]
        L.append(f"  {g:>6} m: near {sum(len(r['near']['steps'][0]['missing_needed']) for r in rs)}, "
                 f"firing {sum(len(r['firing']['steps'][0]['missing_needed']) for r in rs)} "
                 "(identical by construction: the same corners and rescue precede both)")
    L += ["", "largest remaining angular gap (deg) recorded before each primary ask:"]
    for meth in ("near", "firing"):
        for g in A6_NEAR_GAPS:
            gs = [x for r in rows if r["gap"] == g for x in r[meth]["gaps"] if x is not None]
            L.append(f"  {meth:<6} {g:>6} m: {len(gs)} recorded, med/p90/max {_stats(gs) if gs else 'n/a'}")
    L += ["", f"post-hoc point refinement from the same observations, near-target runs ({len(rows)} cases, "
          "asks unchanged by construction):",
          "  gap(m)  pts  refined  correct b/a  wrong b/a  UNKNOWN b/a  radius med/max b -> a  "
          "error med/max b -> a  identity changed"]
    for g in A6_NEAR_GAPS:
        rs = [r["near"] for r in rows if r["gap"] == g]
        f = lambda k, base: sum((r if base else r["refined"])[k] for r in rs)  # noqa: E731
        w = lambda k, base: [x for r in rs for x in (r if base else r["refined"])[k]]  # noqa: E731
        L.append(f"  {g:>6}  {sum(r['final_points'] for r in rs):>3}  "
                 f"{sum(r['refined']['count'] for r in rs):>7}  "
                 f"{f('correct', 1):>5} / {f('correct', 0):<3}  {f('wrong', 1):>4} / {f('wrong', 0):<3}  "
                 f"{f('unknown', 1):>6} / {f('unknown', 0):<3}  "
                 f"{_stats2(w('radius', 1))} -> {_stats2(w('radius', 0)):<12}  "
                 f"{_stats2(w('error', 1))} -> {_stats2(w('error', 0)):<12}  "
                 f"{sum(r['refined']['identity_changed'] for r in rs):>6}")
    L += ["  invented/merged/duplicate/missed after refinement: " + ", ".join(
        f"{k} {sum(r['near']['refined'][k] for r in rows)}"
        for k in ("invented", "merged", "duplicate", "missed")),
        "  points left unrefined, by reason: " + ", ".join(
            f"{k} {v}" for k, v in sorted(Counter(
                x for r in rows for x in r["near"]["refined"]["skipped"]).items()))]
    L += ["", "hardest cases by near-target ask count:"]
    for r in sorted(rows, key=lambda r: -r["near"]["asks"])[:8]:
        n = r["near"]
        L.append(f"  case {r['id']} @{r['gap']} m {r['target']}: {n['asks']} asks "
                 f"({n['corners']} corners + {n['rescue_extra']} rescue + {n['angular_extra']} angular), "
                 f"{n['primary']} primary, needed missing {len(n['missing_needed'])}, "
                 f"authored missing {len(n['missing_authored'])}{', GUARD' if n['guard'] else ''}")
    L += ["", "per geometry, needed points still missing at the end (near / firing), by gap:"]
    for cid in A43_CASES:
        rs = {r["gap"]: r for r in rows if r["id"] == cid}
        L.append(f"  {cid}: " + ", ".join(
            f"{g}m {len(rs[g]['near']['missing_needed'])}/{len(rs[g]['firing']['missing_needed'])}"
            for g in A6_NEAR_GAPS if g in rs))
    return "\n".join(L)


# ---------------------------------------------------------------- A7: focused validation and stopping traces

A7_EVIDENCE = Path(__file__).with_name("A7_FOCUSED.md")
A7_PRIMARY = 64          # no primary budget: A43A_GUARD stays the only angular-stage limit while tracing
A7_THRESHOLDS = (90, 60, 45, 30, 20, 15, 10, 5, 2, 1)  # candidate `stop when largest remaining gap <= T` (deg)
A7_QUIET = (2, 4, 6, 8, 10, 12, 14, 16, 18, 20)        # candidate `stop after k angular asks with no new point`


def a7_ordinary(ts, mounts):
    """The ordinary, non-boundary half of the A7 population: every target with more than one authored aim
    point, plus the smallest and largest one-point target of each Gunnery Control target kind under the
    benchmark's own size measure `|H|` - the bounding-sphere reach `cases` already uses for placement.

    One deterministic geometry per target, the first ordinary case `cases` yields for it (bearing 0 at the
    1 km gap), reproduced at each A7 standoff with target, ship, mount, turret, rotations and bearing
    unchanged."""
    want = {t["component"] for t in ts if len(t["points"]) > 1}
    one = [t for t in ts if len(t["points"]) == 1]
    for kind in sorted({t["kind"] for t in one}):
        g = sorted((t for t in one if t["kind"] == kind),
                   key=lambda t: (float(np.linalg.norm(t["H"])), t["component"]))
        want.update((g[0]["component"], g[-1]["component"]))
    seen = set()
    for c in cases(ts, mounts):
        if c["group"] == "ordinary" and c["target"] in want and c["target"] not in seen:
            seen.add(c["target"])
            yield from _restandoff(c, np.asarray(c["box"][0]) @ c["box"][2], A6_NEAR_GAPS)
    assert seen == want, sorted(want - seen)


def a7_variants(ts, mounts):
    """The fixed A7 population: the 19 hard A6 boundary geometries plus the ordinary set, each at every
    A7 standoff. Chosen before the run and never from A7 results."""
    kind = {t["component"]: t["kind"] for t in ts}
    for tag, gen in (("hard", a6_near_variants), ("ordinary", a7_ordinary)):
        for c in gen(ts, mounts):
            yield dict(c, a7=tag, kind=kind[c["target"]])


def _a7_case(case):
    """One A7 case: the accepted near-target search run to the existing 24-ask angular-stage limit, with
    the refined result reconstructed at every state the real implementation could have stopped in, from
    that state's own observations only."""
    records, margins = _LOADED
    v, margin = view(case), margins[case["ship_class"]][0]
    muzzles = aimed_muzzles(case, records)
    truth = case["points"]
    probe, stats = angular_probe(v, margin, primary=A7_PRIMARY, near_target=A6_NEAR_PAD)
    a = corner_audit(v, margin, probe)
    needed = sorted({study.select(tuple(map(float, m)), [tuple(map(float, p)) for p in truth])
                     for m in muzzles.values()})
    corners = a["queries"] - stats["rescue_extra"] - stats["extra"]
    gaps = [t["gap"] for t in stats["trace"]]  # gaps[k] is the largest gap still open after k angular asks

    def state(k, points, rays, extra):
        got, ref = _scored(case, points, rays, muzzles, corners + stats["rescue_extra"] + extra)
        rep = _represented([(np.asarray(c, float), r) for c, r in points], truth)
        return dict(primary=k, angular_extra=extra, asks=corners + stats["rescue_extra"] + extra,
                    gap=gaps[k] if k < len(gaps) else None, points=len(points),
                    missing_needed=[x for x in needed if x not in rep],
                    missing_authored=[j for j in range(len(truth)) if j not in rep],
                    base_correct=got["correct"], base_wrong=got["wrong"], base_unknown=got["unknown"],
                    **{q: ref[q] for q in ("correct", "wrong", "unknown", "invented", "merged", "duplicate",
                                           "missed", "identity_changed", "count", "radius", "error")})

    states = [state(0, stats["after_rescue_points"], stats["pre_rays"], 0)]
    for k in sorted(stats["snaps"]):
        sn = stats["snaps"][k]
        states.append(state(k, sn["points"], sn["rays"], sn["extra"]))
    fin = states[-1]

    def ok(st):
        """As safe and useful as this case's final 24-ask result, judged on the refined result."""
        return (st["wrong"] == 0 and st["identity_changed"] == 0 and st["invented"] == 0
                and st["merged"] == 0 and st["duplicate"] == 0
                and st["correct"] >= fin["correct"] and st["unknown"] <= fin["unknown"]
                and st["missed"] <= fin["missed"]
                and not set(st["missing_needed"]) - set(fin["missing_needed"]))

    for st in states:
        st["ok"] = ok(st)
    early = next((st for st in states if st["ok"]), None)
    return dict(id=case["id"], gap=case["gap"], group=case["a7"], kind=case["kind"], target=case["target"],
                ship=case["ship"], authored=len(truth), muzzles=len(muzzles), needed=needed,
                corners=corners, rescue_extra=stats["rescue_extra"], primary=stats["primary"],
                angular_extra=stats["extra"], asks=a["queries"], guard=stats["guard"],
                stalled=stats["stalled"], states=states,
                earliest=None if early is None else early["primary"],
                earliest_gap=None if early is None else early["gap"],
                earliest_asks=None if early is None else early["asks"],
                earliest_angular=None if early is None else early["angular_extra"])


def _a7_quiet(row, k):
    """The state a `stop after k consecutive angular asks that confirmed no new point` rule would stop
    in - the other obvious observable, since the search already knows when an ask added nothing."""
    q = 0
    for i, st in enumerate(row["states"]):
        q = q + 1 if i and st["points"] == row["states"][i - 1]["points"] else 0
        if q >= k or st["gap"] is None:
            return st
    return row["states"][-1]


def _a7_safe_T(rows):
    """The largest gap threshold that stops every case in a state as safe as its final result. Bisected
    because the safe/unsafe boundary lies between recorded gap values, not on the tested grid."""
    lo, hi = 0.0, 180.0
    for _ in range(60):
        m = (lo + hi) / 2
        lo, hi = (m, hi) if all(_a7_stop(r, m)["ok"] for r in rows) else (lo, m)
    return lo


def _a7_stop(row, T):
    """The state a `stop when the largest remaining viewing-angle gap <= T` rule would stop in. A state
    with no candidate left (gap None) has nothing to ask and stops at any threshold."""
    return next((st for st in row["states"] if st["gap"] is None or st["gap"] <= T), row["states"][-1])


def a7(jobs):
    """A7.1: does the accepted near-target search plus post-hoc refinement stay safe on ordinary
    geometries, and does the full 24-ask trace support a simple earlier stopping rule?"""
    global _LOADED
    records, margins, mounts, _excluded, _inferred = load()
    _LOADED = records, margins
    todo = list(a7_variants(targets(), mounts))
    CACHE.mkdir(parents=True, exist_ok=True)
    rows_path = CACHE / "a7_rows.jsonl"
    print(f"#184 A7: {len(todo)} cases -> {rows_path}", flush=True)
    os.nice(10)
    rows = []
    with open(rows_path, "w") as fh, Pool(min(jobs, 4)) as pool:
        for r in pool.imap(_a7_case, todo, chunksize=1):
            rows.append(r)
            fh.write(json.dumps(r, default=float) + "\n")
            fh.flush()
            f = r["states"][-1]
            print(f"  {len(rows)}/{len(todo)} case {r['id']} {r['group']} @{r['gap']}m: {r['asks']} asks "
                  f"({r['primary']} primary, {r['angular_extra']} angular), {f['points']} pts, "
                  f"correct/wrong/UNKNOWN {f['correct']}/{f['wrong']}/{f['unknown']}, "
                  f"earliest safe stop {r['earliest']}"
                  f"{', GUARD' if r['guard'] else ''}{', STALLED' if r['stalled'] else ''}", flush=True)
    rows.sort(key=lambda r: (r["group"], r["id"], r["gap"]))
    out = _a7_report(rows)
    A7_EVIDENCE.write_text(out)
    print(out + f"\n(rows: {rows_path}, evidence: {A7_EVIDENCE})")


def _a7_report(rows):
    fin = {id(r): r["states"][-1] for r in rows}
    L = ["# Issue #184 A7.1: focused validation of the accepted method, and full stopping traces", "",
         "Offline research, status **inference**. No X4 launch, no production change. The accepted A6",
         "method is unchanged: the same 8 outer firing corners, the same cheap rescue, the same",
         f"near-target probe placement on the target runtime box + {A6_NEAR_PAD:g} m, the same point",
         f"confirmation and the same `refine_points` containment rule. Only the {A43A_PRIMARY}-primary-ask",
         f"experiment budget is lifted, so every case runs to the existing {A43A_GUARD}-ask angular-stage",
         "hard limit and the whole trace exists. No stopping rule is implemented.", "",
         "Run with `python3 research/issue184/aimpoint_map.py --a7`.", "",
         "## Population", "",
         f"{len(rows)} cases, fixed before the run and never chosen from A7 results.", "",
         "| group | geometries | cases | targets |", "|---|---:|---:|---|"]
    for g in ("hard", "ordinary"):
        rs = [r for r in rows if r["group"] == g]
        L.append(f"| {g} | {len(rs) // len(A6_NEAR_GAPS)} | {len(rs)} | "
                 f"{len({r['target'] for r in rs})} distinct |")
    L += ["", "Ordinary targets (one deterministic non-boundary geometry each, reproduced at every gap):", ""]
    for r in sorted({(x["target"], x["kind"], x["authored"], x["id"]) for x in rows if x["group"] == "ordinary"}):
        L.append(f"- `{r[0]}` ({r[1]}, {r[2]} authored point{'s' if r[2] > 1 else ''}, case {r[3]})")
    L += ["", f"Hard geometries: the 19 A4.3/A6 boundary cases {A43_CASES}.", "",
          "## Final result at the 24-ask angular limit", "",
          "b = baseline, a = refined. Correct/wrong/UNKNOWN are over the hidden later aimed muzzles.", "",
          "| group | gap (m) | cases | asks med/p90/max | angular med/max | guard | stalled | pts | "
          "authored missing | needed missing | correct b/a | wrong b/a | UNKNOWN b/a | "
          "radius med/max a (m) | error med/max a (m) |", "|---|---:|---:|---|---|---:|---:|---:|---:|---:|---|---|---|---|---|"]
    for g in ("hard", "ordinary"):
        for gap in A6_NEAR_GAPS:
            rs = [r for r in rows if r["group"] == g and r["gap"] == gap]
            fs = [fin[id(r)] for r in rs]
            L.append(f"| {g} | {gap} | {len(rs)} | {_stats([r['asks'] for r in rs])} | "
                     f"{_stats([r['angular_extra'] for r in rs])} | {sum(r['guard'] for r in rs)} | "
                     f"{sum(r['stalled'] for r in rs)} | {sum(f['points'] for f in fs)} | "
                     f"{sum(len(f['missing_authored']) for f in fs)} of {sum(r['authored'] for r in rs)} | "
                     f"{sum(len(f['missing_needed']) for f in fs)} | "
                     f"{sum(f['base_correct'] for f in fs)} / {sum(f['correct'] for f in fs)} | "
                     f"{sum(f['base_wrong'] for f in fs)} / {sum(f['wrong'] for f in fs)} | "
                     f"{sum(f['base_unknown'] for f in fs)} / {sum(f['unknown'] for f in fs)} | "
                     f"{_stats2([x for f in fs for x in f['radius']])} | "
                     f"{_stats2([x for f in fs for x in f['error']])} |")
    L += ["", "## Refinement safety", "",
          "Every failure class counted over every reconstructed state of every case, not only the final",
          "one, so a prefix refinement would have damaged is caught too. `wrong b/a` is the baseline and",
          "refined wrong count at the same state; `caused by refinement` is the part refinement added,",
          "which is the number this experiment is actually testing.", "",
          "| group | states | wrong b/a | caused by refinement | identity changed | invented | merged | "
          "duplicate | correct -> UNKNOWN | points refined |",
          "|---|---:|---|---:|---:|---:|---:|---:|---:|---:|"]
    for g in ("hard", "ordinary", "all"):
        sts = [st for r in rows if g in (r["group"], "all") for st in r["states"]]
        L.append(f"| {g} | {len(sts)} | {sum(st['base_wrong'] for st in sts)} / "
                 f"{sum(st['wrong'] for st in sts)} | "
                 f"{sum(max(0, st['wrong'] - st['base_wrong']) for st in sts)} | "
                 f"{sum(st['identity_changed'] for st in sts)} | {sum(st['invented'] for st in sts)} | "
                 f"{sum(st['merged'] for st in sts)} | {sum(st['duplicate'] for st in sts)} | "
                 f"{sum(max(0, st['base_correct'] - st['correct']) for st in sts)} | "
                 f"{sum(st['count'] for st in sts)} |")
    bad = sorted({(r["id"], r["gap"]) for r in rows for st in r["states"] if st["wrong"]})
    L += ["", f"The wrong answers are identical before and after refinement and all sit in early prefixes "
          f"of {len(bad)} case instances ({', '.join(f'{i} @{g} m' for i, g in bad)}), where only part of "
          "the target's aim points has been confirmed and `nearest` names a known point confidently "
          "because the point that actually wins is not yet in the set. They are a discovery-completeness "
          "effect, not a refinement effect, and every one of them is gone by the final state. They are "
          "also exactly why a prefix is scored as unsafe below."]
    L += ["", "## Earliest state as safe and useful as the final 24-ask result", "",
          "A state qualifies when its refined result has no wrong answer, no identity change and no",
          "invented, merged or duplicate point, is not below the final result on correct answers, not",
          "above it on UNKNOWN or missed points, and represents every needed aim point the final result",
          "represents. `gap` is the largest viewing-angle gap still open at that state - an observable",
          "quantity the search already computes.", "",
          "| group | gap (m) | cases | earliest angular asks med/max | earliest total asks med/max | "
          "gap at earliest med/max (deg) | never safe |", "|---|---:|---:|---|---|---|---:|"]
    for g in ("hard", "ordinary"):
        for gap in A6_NEAR_GAPS:
            rs = [r for r in rows if r["group"] == g and r["gap"] == gap]
            e = [r for r in rs if r["earliest"] is not None]
            gs = [r["earliest_gap"] for r in e if r["earliest_gap"] is not None]
            L.append(f"| {g} | {gap} | {len(rs)} | {_stats2([r['earliest_angular'] for r in e])} | "
                     f"{_stats2([r['earliest_asks'] for r in e])} | {_stats2(gs)} | {len(rs) - len(e)} |")
    L += ["", "## Candidate observable stopping rules", "",
          "`stop when the largest remaining viewing-angle gap <= T`, evaluated against the completed",
          f"traces. A state with no definite candidate left counts as gap 0. The {A43A_GUARD}-ask limit",
          "remains the backstop in every row.", "",
          "| T (deg) | cases stopped early | unsafe stops | angular asks med/max | worst loss |",
          "|---:|---:|---:|---|---|"]
    for T in A7_THRESHOLDS:
        stops = [(r, _a7_stop(r, T)) for r in rows]
        bad = [(r, st) for r, st in stops if not st["ok"]]
        worst = max(bad, key=lambda x: fin[id(x[0])]["correct"] - x[1]["correct"], default=None)
        L.append(f"| {T} | {sum(st['primary'] < r['primary'] for r, st in stops)} | {len(bad)} | "
                 f"{_stats2([st['angular_extra'] for _r, st in stops])} | "
                 + ("none" if worst is None else
                    f"case {worst[0]['id']} @{worst[0]['gap']} m: correct "
                    f"{worst[1]['correct']} vs {fin[id(worst[0])]['correct']}, "
                    f"needed missing {len(worst[1]['missing_needed'])} vs "
                    f"{len(fin[id(worst[0])]['missing_needed'])}") + " |")
    L += ["", "`stop after k consecutive angular asks that confirmed no new point`, the other observable",
          "the search already has:", "",
          "| k | cases stopped early | unsafe stops | angular asks med/max |", "|---:|---:|---:|---|"]
    for k in A7_QUIET:
        stops = [(r, _a7_quiet(r, k)) for r in rows]
        L.append(f"| {k} | {sum(st['primary'] < r['primary'] for r, st in stops)} | "
                 f"{sum(not st['ok'] for _r, st in stops)} | "
                 f"{_stats2([st['angular_extra'] for _r, st in stops])} |")
    T = _a7_safe_T(rows)
    stops = [_a7_stop(r, T) for r in rows]
    quiet = [k for k in A7_QUIET if all(_a7_quiet(r, k)["ok"] for r in rows)]
    qs = [_a7_quiet(r, min(quiet)) for r in rows] if quiet else []
    run = [r["angular_extra"] for r in rows]
    unsafe = [st["gap"] for r in rows for st in r["states"] if not st["ok"] and st["gap"] is not None]
    early = [r["earliest_gap"] for r in rows if r["earliest_gap"] is not None]
    oracle = [r["earliest_angular"] for r in rows if r["earliest_angular"] is not None]
    L += ["", "## Verdict", "",
          f"**No simple observable rule buys anything here.** The largest gap threshold that is safe on "
          f"every one of the {len(rows)} cases is T = {T:.3g} deg, and it spends "
          f"{_stats2([st['angular_extra'] for st in stops])} angular-stage asks (med/max) against "
          f"{_stats2(run)} for the unrestricted run - no saving. The quiet-ask rule is the same story: "
          + (f"the smallest safe k is {min(quiet)}, at {_stats2([st['angular_extra'] for st in qs])} asks."
             if quiet else "no tested k is safe on every case."), "",
          f"The reason is visible in the gap distributions: states that are **not** yet as good as the "
          f"final result span {min(unsafe):.3g} to {max(unsafe):.3g} deg, "
          f"while the earliest safe state of each case sits between {min(early):.3g} and "
          f"{max(early):.3g} deg. The two ranges overlap almost completely, so the largest remaining "
          "viewing angle does not separate a state that is already good enough from one that is not.", "",
          f"The headroom is real and unclaimed: with hindsight the earliest safe state needs only "
          f"{_stats2(oracle)} angular-stage asks (med/max) against {_stats2(run)} actually spent. No "
          "observable tested here finds it. **The existing "
          f"{A43A_GUARD}-ask angular-stage limit remains the fallback stopping condition**, and A7 "
          "implements no rule.", "",
          "## Limitations", "",
          f"- {len(rows)} cases, not the full #184 benchmark. The ordinary half is one deterministic "
          "geometry per target and one bearing, so it measures target variety, not bearing variety.",
          "- The 'as safe and useful as the final result' test compares each case against its own 24-ask "
          "result. It cannot see a point no state of that case ever discovered.",
          f"- {sum(r['muzzles'] == 0 for r in rows)} of {len(rows)} cases have no IN_ARC aimed muzzle, so "
          "they contribute discovery, identity and uncertainty evidence but no correct/wrong/UNKNOWN "
          "answer.",
          "- Every case here ran to the 24-ask limit by construction, so the ask counts in this note are "
          "the cost of collecting the trace, not the cost of the accepted method under its own "
          f"{A43A_PRIMARY}-primary-ask budget.",
          "- The containment rule in `refine_points` was not weakened, so the points it skips are still "
          "skipped; whether a weaker condition stays sound is untested."]
    L += ["", "## Per case", "",
          "| case | group | target | gap (m) | asks | angular | primary | guard | stalled | pts | "
          "authored missing | correct | wrong | UNKNOWN | earliest safe primary / angular / gap (deg) |",
          "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|"]
    for r in rows:
        f = fin[id(r)]
        e = "never" if r["earliest"] is None else (
            f"{r['earliest']} / {r['earliest_angular']} / "
            + ("none left" if r["earliest_gap"] is None else f"{r['earliest_gap']:.3g}"))
        L.append(f"| {r['id']} | {r['group']} | `{r['target']}` | {r['gap']} | {r['asks']} | "
                 f"{r['angular_extra']} | {r['primary']} | {int(r['guard'])} | {int(r['stalled'])} | "
                 f"{f['points']} | {len(f['missing_authored'])} | {f['correct']} | {f['wrong']} | "
                 f"{f['unknown']} | {e} |")
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------- run

def load():
    skipped = _index_swi_ships()
    records = scorer.load()
    components = corpus._index_xml([corpus.SWI_XML, corpus.OFFICIAL_SRC], "component")
    mounts, excluded, inferred = firing_mounts(records, components)
    excluded.update(skipped)
    return records, class_margins(mounts, records), mounts, excluded, inferred


def summary():
    records, margins, mounts, excluded, inferred = load()
    tgts = targets()
    print("class margins (full mounted-muzzle sweep):")
    for cls, (margin, sampled, (ship, mount, turret)) in margins.items():
        print(f"  {cls:7} {margin:8.2f} m  (sampled {sampled:.2f} m)  {ship} {mount} {turret}")
    groups, used, muzzle = Counter(), {}, Counter()
    for c in cases(tgts, mounts):
        g = c["group"]
        groups[g] += 1
        used.setdefault((c["source"], c["ship_class"]), set()).add((c["ship"], c["mount"], c["turret"]))
        m = aimed_muzzles(c, records)
        muzzle[g, "no IN_ARC muzzle"] += not m
        lo, hi = firing_box(*c["ship_box"], margins[c["ship_class"]][0])
        for p in m.values():
            muzzle[g, "inside" if inside((lo, hi), ship_local(c, p)) else "OUTSIDE"] += 1
    print("\nfiring ships / mounts / turrets used, by source and class:")
    for (src, cls), s in sorted(used.items()):
        print(f"  {src:8} {cls:7} {len({x[0] for x in s}):3} ships  {len({x[:2] for x in s}):4} mounts  "
              f"{len({x[2] for x in s}):3} turrets")
    print(f"  SWI turrets paired through the inferred `turret` mating connection: {inferred}")
    turrets = {x[2] for s in used.values() for x in s}
    print("  distinct turrets used:", dict(Counter(k.split(":")[0] for k in turrets)))
    out = [(float(np.max(np.maximum(m["box"][0] - t, 0) + np.maximum(t - m["box"][1], 0))), m)
           for m in mounts for t in [m["frames"][m["turrets"][0]][0]] if not inside(m["box"], t)]
    worst = max(out, key=lambda o: o[0])
    print(f"  mounts outside their own runtime ship box: {len(out)} of {len(mounts)}, worst {worst[0]:.2f} m "
          f"({worst[1]['ship']} {worst[1]['name']}), beyond the class margin: "
          f"{sum(d > margins[m['cls']][0] for d, m in out)}")
    print("\ntargets:", len(tgts), dict(Counter(t["kind"] for t in tgts)),
          "aim points:", sum(len(t["points"]) for t in tgts))
    print("\ngroup        cases  no-IN_ARC  aimed muzzles inside / OUTSIDE class-expanded ship box")
    for g in ("close", "ordinary", "boundary", "stress", "artificial"):
        print(f"  {g:10} {groups[g]:6} {muzzle[g, 'no IN_ARC muzzle']:9}  {muzzle[g, 'inside']:6} / {muzzle[g, 'OUTSIDE']}")
    rows = padding(tgts)
    need = [r for r in rows if r["pad"] > 0]
    worst = max(rows, key=lambda r: r["scale"])
    print(f"\ntarget-box padding: {len(need)} of {len(rows)} targets have an aim point above the box, "
          f"{sum(r['outside_other'] for r in rows)} outside it in any other direction")
    print(f"  proportional: needs {worst['scale']:.2f}x ({worst['target']}), search volume x{worst['scale'] ** 3:.1f} for every target")
    by_pad = max(rows, key=lambda r: r["pad"])
    vol = sorted(r["pad_volume"] for r in rows)
    print(f"  +Y pad: needs {by_pad['pad']:.2f} m ({by_pad['target']}); TARGET_PAD_Y {TARGET_PAD_Y} m grows volume "
          f"median x{vol[len(vol) // 2]:.2f}, max x{vol[-1]:.2f}  -> chosen")
    print("\nexcluded:")
    for reason, k in sorted(excluded.items()):
        print(f"  {k:4}  {reason}")


GROUPS = ("close", "ordinary", "boundary", "stress", "artificial")
_LOADED = None


def _evaluate(case):
    records, margins = _LOADED
    muzzles, v, margin = aimed_muzzles(case, records), view(case), margins[case["ship_class"]][0]
    rows = []
    for method, result in (("firing", firing_box_map(v, margin)), ("target", target_box_map(v))):
        row = dict(score(case, result, muzzles), group=case["group"], method=method, capped=result["queries"] >= CAP)
        if method == "firing":
            box = firing_box(*case["ship_box"], margin)
            row["outside"] = sum(not inside(box, ship_local(case, m)) for m in muzzles.values())
        else:  # UNKNOWN only because an unproven region could hold a nearer point
            row["incomplete"] = sum(result["answer"](m) is UNKNOWN and nearest(result["located"], m) is not UNKNOWN
                                    for m in muzzles.values())
            C, H, T = case["box"]
            lo, hi = target_box(C, H)
            row["premise"] = not all(inside((lo - 1e-6, hi + 1e-6), p @ T.T) for p in case["points"])
        rows.append(row)
    return rows


def a3(every, jobs):
    """Run both A3 mappers on every `every`-th case of each group; print per-group, per-method results."""
    global _LOADED
    records, margins, mounts, _excluded, _inferred = load()
    _LOADED = records, margins
    seen = Counter()
    todo = []
    for c in cases(targets(), mounts):
        seen[c["group"]] += 1
        if (seen[c["group"]] - 1) % every == 0:
            todo.append(c)
    os.nice(10)
    with Pool(min(jobs, 4)) as pool:  # forked workers share the loaded corpus
        rows = [r for rs in pool.imap(_evaluate, todo, chunksize=8) for r in rs]
    print(f"A3: every {every} case(s) per group, CAP {CAP} queries, MAX_DEPTH {MAX_DEPTH}, GEO_DEPTH {GEO_DEPTH}")
    for method in ("firing", "target"):
        print(f"\n{method}-box method")
        print("  group       cases  queries  q med/p90/max  capped  muzzles correct wrong unknown  "
              "missed invented merged dup  error med/max (m)   radius med/max (m)  " +
              ("outside-box" if method == "firing" else "incomplete muzzles/cases  premise-failed cases (wrong)"))
        for g in GROUPS:
            rs = [r for r in rows if r["method"] == method and r["group"] == g]
            if not rs:
                continue
            q = np.asarray([r["queries"] for r in rs])
            tot = {k: sum(r[k] for r in rs) for k in ("muzzles", "correct", "wrong", "unknown", "missed", "invented",
                                                       "merged", "duplicate", "capped")}
            err, rad = [e for r in rs for e in r["error"]] or [math.nan], [x for r in rs for x in r["radius"]] or [math.nan]
            extra = (f"{sum(r['outside'] for r in rs)}" if method == "firing" else
                     f"{sum(r['incomplete'] for r in rs)} / {sum(r['incomplete'] > 0 for r in rs)}  "
                     f"{sum(r['premise'] for r in rs)} ({sum(r['wrong'] for r in rs if r['premise'])})")
            print(f"  {g:10} {len(rs):6} {q.sum():8} {int(np.median(q)):4}/{int(np.percentile(q, 90)):3}/{q.max():3}"
                  f"  {tot['capped']:6} {tot['muzzles']:8} {tot['correct']:7} {tot['wrong']:5} {tot['unknown']:7}  "
                  f"{tot['missed']:6} {tot['invented']:8} {tot['merged']:6} {tot['duplicate']:3}  "
                  f"{np.median(err):8.2g} / {max(err):8.2g}  {np.median(rad):8.2g} / {max(rad):8.2g}  {extra}")


def selftest():
    a, b = np.zeros(3), np.array([10.0, 0, 0])
    assert nearest([("a", a, .1), ("b", b, .1)], np.array([1.0, 0, 0])) == "a"
    assert nearest([("a", a, 1), ("b", b, 1)], np.array([4.5, 0, 0])) is UNKNOWN  # uncertainty overlaps
    assert nearest([], a) is UNKNOWN
    box = firing_box((0, 0, 0), (1, 1, 1), 2)
    assert inside(box, np.array([-2.0, 3, 0])) and not inside(box, np.array([3.1, 0, 0]))
    assert np.allclose(target_box((1, 0, 0), (1, 2, 1))[1], (2, 2 + TARGET_PAD_Y, 1))

    fake = dict(points=[a, b, np.array([0.0, 50, 0])])  # score(): missed, invented, merged, duplicate, wrong
    got = score(fake, dict(located=[("A", a, 1), ("A2", a + .5, 1), ("B", (5, 0, 0), 6), ("X", (0, -99, 0), 1)],
                           answer=lambda m: "A" if m[0] < 3 else "B" if m[0] < 7 else UNKNOWN, queries=8),
                {0: a + .1, 1: b - 4.5, 2: b + 1})
    assert {k: got[k] for k in ("missed", "invented", "merged", "duplicate", "correct", "wrong", "unknown")} == \
        dict(missed=1, invented=1, merged=1, duplicate=1, correct=1, wrong=1, unknown=1)

    def synthetic(pts, C, H, ship=((-10, -10, -10), (10, 10, 10)), at=(0, 0, -2000)):
        pts = [tuple(map(float, p)) for p in pts]
        return dict(points=[np.asarray(p) for p in pts]), dict(
            oracle=lambda u: study.Q(u, pts, []), target_box=(np.asarray(C, float), np.asarray(H, float), np.eye(3)),
            ship_box=tuple(np.asarray(x, float) for x in ship), ship_position=np.asarray(at, float), ship_rotation=np.eye(3))

    def check(case, result, muzzles, **want):
        got = score(case, result, {i: np.asarray(m, float) for i, m in enumerate(muzzles)})
        assert got["wrong"] == got["invented"] == 0 and all(got[k] == v for k, v in want.items()), got

    z = np.array([0, 0, 1.0])
    assert math.isclose(crossing(np.zeros(3), z, np.array([10.0, 0, 0]), np.array([-.6, 0, .8]))[0], 40 / 3, rel_tol=1e-6)
    assert crossing(np.zeros(3), z, np.ones(3), z) is None  # parallel
    far = [(0, 0, -2000), (3, 0, -2000), (0, 0, 2000)]
    case, v = synthetic([(1, 2, 3)], (0, 0, 0), (20, 20, 20))
    check(case, target_box_map(v), far, correct=3)
    check(case, firing_box_map(v, 5), far, correct=2, unknown=1)  # (0, 0, 2000) is outside the firing box
    # #176 A2 witness: every corner selects its own point halfway to the box centre, so all corner rays meet
    # at the centre, which is no aim point. The along-ray bracket must reject it.
    lo, hi = target_box((0, 0, 0), (20, 20, 20))
    case, v = synthetic([(c + (lo + hi) / 2) / 2 for c in _corners(lo, hi)], (0, 0, 0), (20, 20, 20))
    assert all(study.select(tuple(c), [tuple(p) for p in case["points"]]) == i for i, c in enumerate(_corners(lo, hi)))
    check(case, target_box_map(v), far)
    # #184 case 12352: a ray to the other point crosses the anchor ray just past its point, inside the
    # bracket's ~SLACK resolution; one crossing plus the bracket invented two points 180 m from any real one.
    case, v = synthetic([(0, 0, 59.2), (0, 0, -201.495)], (0, 0, -71), (150, 150, 150),
                        ship=((-1093.02, 2304.84, -2871.78), (1149.38, 7698.96, 2522.34)), at=(0, 0, 0))
    check(case, firing_box_map(v, 0), [])

    # A4.1: two well-separated points either side of a big ship box -> corners split between them.
    case, v = synthetic([(0, 0, -300), (0, 0, 300)], (0, 0, 0), (400, 400, 400),
                        ship=((-200, -200, -200), (200, 200, 200)), at=(0, 1500, 0))
    a = corner_audit(v, 0)
    assert len(a["points"]) == 2 and len(a["mixed"]) == 4, (len(a["points"]), len(a["mixed"]))
    assert len(_edges(np.zeros(3), np.ones(3))) == 12
    assert _plane_error(np.array([0., 0, -1]), np.array([0., 0, 1]), np.array([0., 0, -1]), np.array([0., 0, 1]),
                        np.asarray(_corners(np.zeros(3), np.ones(3)))) == 0.0

    # A4.2: the conservative band must cover the estimate error, and bisecting the mixed edges must
    # converge on the true switch plane (here z = 0) without ever seeing the true points.
    corners = np.asarray(_corners(*firing_box((-200, -200, -200), (200, 200, 200), 0))) + (0, 1500, 0)
    w = safety_band(np.array([0., 0, -302]), 3.0, np.array([0., 0, 301]), 2.0, corners)
    assert w >= _plane_error(np.array([0., 0, -302]), np.array([0., 0, 301]),
                             np.array([0., 0, -300]), np.array([0., 0, 300]), corners), w
    # the band's promise: every position it calls resolved really does select the point on that side.
    ca, cb = np.array([0., 0, -302]), np.array([0., 0, 301])
    n_est, o_est = _bisector(ca, cb)
    rng = np.random.default_rng(0)
    probe = rng.uniform((-200, 1300, -200), (200, 1700, 200), (2000, 3))
    for x in probe:
        d = float((x - o_est) @ n_est)
        if abs(d) > w:
            assert study.select(tuple(x), [(0, 0, -300), (0, 0, 300)]) == (1 if d > 0 else 0), (x, d)
    assert _fit_plane([(0, 0, 0), (1, 0, 0), (2, 0, 0)], np.array([0., 0, 1])) is None  # collinear
    n_fit, o_fit, _scale = _fit_plane([(0, 0, 0), (100, 0, 0), (0, 100, 0)], np.array([0., 0, 1]))
    assert np.allclose(n_fit, (0, 0, 1)) and np.allclose(o_fit, 0)
    own = {tuple(c): a["own"][tuple(c)] for c in _corners(*a["box"])}
    i, j = sorted({k for k in own.values() if k is not None})
    edges = _spread([(x, y) if own[tuple(x)] == i else (y, x) for x, y in a["mixed"]], key=lambda e: (e[0] + e[1]) / 2)
    assert len(edges) == 3 and len({tuple((x + y) / 2) for x, y in edges}) == 3
    errs = []
    for step, (asks, locs, stalls) in enumerate(measure_boundary(v, a["points"], edges, (i, j), a["R"], a["O"]), 1):
        assert asks == 3 * step and not stalls
        fit = _fit_plane(locs, a["points"][j][0] - a["points"][i][0])
        assert fit is not None
        errs.append(_gap(fit[0], fit[1], *_bisector((0, 0, -300), (0, 0, 300)), corners))
    # each halfway ask halves the bracket, so the measured plane closes on the true one (z = 0 here)
    assert errs[-1] < errs[0] / 8 and errs[-1] < 5.0, errs

    # A4.3: the residual model's promise is that every definite answer is right even when a third point
    # it never saw exists. Hide one: build the map from two points, then score against three.
    cube = _corners(-np.ones(3), np.ones(3))
    assert spans(cube) and not spans(cube[:3])
    assert not spans([c for c in cube if c[2] > 0])  # one side only: a separating plane exists
    assert not spans([c - (0, 0, 1.001) for c in cube])  # viewpoint just outside a face
    two = [(0, 0, -300), (0, 0, 300)]
    hidden = two + [(0, 380, 0)]
    _c, v = synthetic(two, (0, 0, 0), (400, 400, 400), ship=((-200, -200, -200), (200, 200, 200)), at=(0, 1500, 0))
    r = residual_map(v, 0)
    assert len(r["located"]) == 2 and r["queries"] >= 8  # the 8 outer corners plus confirmation brackets
    assert 0 < sum(float(np.prod(b - a)) for a, b in r["residual"]) < r["target_volume"]
    rng = np.random.default_rng(1)
    probe = np.concatenate([rng.uniform((-200, 1300, -200), (200, 1700, 200), (200, 3)),
                            rng.uniform((-3000, -3000, -3000), (3000, 3000, 3000), (200, 3))])
    for x in probe:  # a definite answer must name the point X4 really picks, hidden third point and all
        ans = r["answer"](x)
        assert ans is UNKNOWN or np.linalg.norm(r["located"][ans][1] - hidden[study.select(tuple(x), hidden)]) \
            <= r["located"][ans][2], x
    # each confirmed point owns only its own four corners here, so no muzzle is inside either hull
    assert all(r["answer"](x) is UNKNOWN for x in probe)
    # one point owning all eight corners does resolve every position inside the firing box
    _c, v = synthetic([(1, 2, 3)], (0, 0, 0), (20, 20, 20), ship=((-10, -10, -10), (10, 10, 10)), at=(0, 0, -2000))
    r = residual_map(v, 5)
    assert len(r["located"]) == 1 and all(r["answer"](x) == 0 for x in rng.uniform(-10, 10, (50, 3)) + (0, 0, -2000))
    assert r["answer"](np.array([0.0, 0, 2000])) is UNKNOWN  # the far side is outside that hull

    # A4.3 phase 2: four points, one per firing-box quadrant, so every corner ask selects a point only one
    # other corner shares. Three rays are needed to confirm one, so the corners alone confirm nothing and all
    # eight directions are left unassigned. The rescue must turn those observations into all four points, and
    # must spend fewer moved asks than there are unassigned directions, because one new point explains others.
    quad = [(x, 0, z) for x in (-350, 350) for z in (-350, 350)]
    case, v = synthetic(quad, (0, 0, 0), (400, 400, 400), ship=((-200, -200, -200), (200, 200, 200)), at=(0, 1500, 0))
    assert not corner_audit(v, 0)["points"]
    rescue, stats = rescue_probe(v, 0, fallback=False)
    r = residual_map(v, 0, rescue)
    assert stats["open_before"] == 8 and not stats["guard"] and stats["extra"] <= RESCUE_GUARD, stats
    assert 0 < stats["moved"] < stats["open_before"], stats
    check(case, r, [], missed=0, merged=0, duplicate=0)  # four estimates, one true point each, none invented

    # A4.3 phase 3: two points split the eight corners four/four, so the corners confirm both and the cheap
    # rescue has no unassigned direction to follow - yet a third point wins inside the firing area, and the
    # only evidence of it is that the empty balls cannot rule out the target space it sits in. The
    # uncertainty-driven cell search must find it without being told where it is.
    hidden3 = [(-350, 0, 0), (350, 0, 0), (0, -20, 0)]
    case, v = synthetic(hidden3, (0, 0, 0), (400, 400, 400), ship=((-200, -200, -200), (200, 200, 200)),
                        at=(0, 1500, 0))
    assert len(corner_audit(v, 0)["points"]) == 2
    rescue, stats = rescue_probe(v, 0)
    r = residual_map(v, 0, rescue)
    assert stats["open_before"] == 0 and stats["extra"] == 0, stats  # nothing for the cheap rescue to pursue
    assert stats["fb_used"] and stats["fb_asks"] > 0 and stats["fb_points"] == 1, stats
    check(case, r, [], missed=0, merged=0, duplicate=0)  # the third point is now represented, nothing invented

    # A4.3 phase 4: the coverage map must mean exactly what `spans()` means, cell by cell.
    rng2 = np.random.default_rng(7)
    P = rng2.normal(size=(12, 3))
    fs = hull_faces(P)
    assert all(hull_interior(fs, [x])[0] == spans([u - x for u in P]) for x in rng2.normal(size=(300, 3)) * 0.6)
    assert hull_faces(np.zeros((4, 3))) is None and not hull_interior(None, [np.zeros(3)])[0]  # degenerate
    m = np.zeros((4, 4, 4), bool)
    m[0, 0, 0] = m[0, 0, 1] = m[3, 3, 3] = True
    assert _components(m) == [2, 1]

    # one point owning all 8 corners: its ask hull is the whole firing box, so every cell that does not
    # touch the box surface is safely covered and no interior hole is left. The surface shell can never be
    # covered - the asks lie on it - so that shell is the measurement floor, not a hole.
    _c, v = synthetic([(1, 2, 3)], (0, 0, 0), (20, 20, 20), ship=((-10, -10, -10), (10, 10, 10)), at=(0, 0, -2000))
    cov = hull_cover(v, 5)
    n = 2 ** A43H_DEPTH
    assert cov["open_cells"] == n ** 3 - (n - 2) ** 3 and not cov["inner_regions"], cov["open_cells"]
    assert cov["inside"](np.array([0.0, 0, -2000])) and not cov["inside"](np.array([0.0, 0, 2000]))

    # all 8 corners assigned to confirmed points, nothing for the cheap rescue to pursue - and yet a third
    # point hides inside the firing area. Each confirmed point owns one flat face of corners, whose hull has
    # no interior, so the observations prove nothing anywhere: a genuine uncovered hole covering the whole
    # firing box, deep interior cells included.
    hidden3 = [(-350, 0, 0), (350, 0, 0), (0, -20, 0)]
    _c, v = synthetic(hidden3, (0, 0, 0), (400, 400, 400), ship=((-200, -200, -200), (200, 200, 200)),
                      at=(0, 1500, 0))
    rescue, stats = rescue_probe(v, 0, fallback=False)
    assert stats["open_before"] == 0 and stats["extra"] == 0, stats
    cov = hull_cover(v, 0, rescue)
    assert sum(cov["asks"].values()) == 8 and cov["points"] == 2, cov["asks"]  # every corner assigned
    assert cov["covered_cells"] == 0 and cov["inner_regions"] == [(n - 2) ** 3], cov["inner_regions"]

    # A4.3 phase 5: the next ask must go where the aim point has never been seen from. One point, with
    # every assigned ask on the -x face of the firing box: the largest missing viewing direction is the
    # opposite face, and the chosen candidate must land on it.
    flo_, fhi_ = np.array([-200.0, -200, -200]), np.array([200.0, 200, 200])
    Rz, Oz = np.eye(3), np.array([0.0, 1500, 0])
    one = [(np.zeros(3), 1.0)]
    seen_asks = {0: [np.asarray(q, float) @ Rz + Oz for q in itertools.product([-200.0], [-200, 200], [-200, 200])]}
    gap, pos, want = angular_pick(one, seen_asks, flo_, fhi_, Rz, Oz)
    assert want == 0 and pos[0] == fhi_[0] and gap > 0, (pos, gap)

    # Candidates are only ever judged where the confirmed estimates make the nearest point definite, which
    # must be the accepted `nearest` rule and nothing looser - including between two points.
    two_pts = [(np.array([-350.0, 0, 0]), 2.0), (np.array([350.0, 0, 0]), 2.0)]
    loc = [(i, c, r) for i, (c, r) in enumerate(two_pts)]
    W = rng.uniform(flo_, fhi_, (500, 3)) @ Rz + Oz
    bi, okm = _definite(np.asarray([c for c, _r in two_pts]), np.asarray([r for _c, r in two_pts]), W)
    assert all((int(b) if o else UNKNOWN) == nearest(loc, w) for w, b, o in zip(W, bi, okm))
    gap, pos, want = angular_pick(two_pts, {0: [np.array([-200.0, -200, -200]) @ Rz + Oz],
                                            1: [np.array([200.0, 200, 200]) @ Rz + Oz]}, flo_, fhi_, Rz, Oz)
    assert nearest(loc, pos @ Rz + Oz) == want, (pos, want)  # never chosen across an uncertain boundary

    # The phase-3 witness again: the corners confirm two points, the cheap rescue has nothing to pursue,
    # and a third point hides inside the firing area. Spreading asks by viewing angle must reach it.
    _c, v = synthetic(hidden3, (0, 0, 0), (400, 400, 400), ship=((-200, -200, -200), (200, 200, 200)),
                      at=(0, 1500, 0))
    ang, astats = angular_probe(v, 0)
    a = corner_audit(v, 0, ang)
    assert astats["before"] == 2 and astats["open_before"] == 0, astats
    assert len(a["points"]) == 3, len(a["points"])  # the hidden point, found without being told where
    assert all(p["angle"] > 0 for p in astats["picks"]) and astats["extra"] <= A43A_GUARD, astats
    check(_c, dict(located=[(i, c, r) for i, (c, r) in enumerate(a["points"])],
                   answer=lambda m: UNKNOWN, queries=0), [], missed=0, merged=0, duplicate=0)

    assert _integrated(sources.macro("turret_xen_xl_battleship_01_mk1_macro"))  # #169 integrated turret
    assert not _integrated(sources.macro("turret_kha_l_beam_01_mk1_scenario_macro"))  # ref override kept

    records, margins, mounts, _excluded, _inferred = load()
    tgts = targets()
    assert max(r["pad"] for r in padding(tgts)) <= TARGET_PAD_Y and not any(r["outside_other"] for r in padding(tgts))
    assert {m["source"] for m in mounts} == {"official", "swi"}
    seen = set()
    for case in cases(tgts, mounts):
        if case["group"] in seen:
            continue
        seen.add(case["group"])
        assert not {"points", "turret", "mount", "origin", "frame"} & set(view(case))
        lo, hi = map(np.asarray, case["ship_box"])
        ship = [c @ case["rotation"] + case["position"] for c in itertools.product(*zip(lo, hi))]
        C, H, R = case["box"]
        if case["group"] != "artificial":  # real groups keep the whole firing ship clear of the target
            assert min(np.linalg.norm(p - C @ R) for p in ship) >= np.linalg.norm(H) + case["gap"] - 1e-6
        for m in aimed_muzzles(case, records).values():
            assert inside(firing_box(lo, hi, margins[case["ship_class"]][0]), ship_local(case, m))
    assert seen == {"close", "ordinary", "stress", "boundary", "artificial"}
    print("selftest ok")


def main():
    if "--selftest" in sys.argv:
        return selftest()
    arg = lambda k, d: int(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d  # noqa: E731
    if "--a3" in sys.argv:
        return a3(arg("--every", 1), arg("--jobs", 4))
    if "--a41" in sys.argv:
        return a41(arg("--every", 1), arg("--jobs", 4))
    if "--a42" in sys.argv:
        return a42(arg("--jobs", 4))
    if "--a7" in sys.argv:
        return a7(arg("--jobs", 4))
    if "--a6-near" in sys.argv:
        return a6_near(arg("--jobs", 4))
    if "--a6" in sys.argv:
        return a6(arg("--jobs", 4))
    if "--a43a" in sys.argv:
        return a43a(arg("--jobs", 4))
    if "--a43h" in sys.argv:
        return a43h(arg("--jobs", 4))
    if "--a43f" in sys.argv:
        return a43r(arg("--jobs", 4), fallback=True)
    if "--a43r" in sys.argv:
        return a43r(arg("--jobs", 4))
    if "--a43" in sys.argv:
        return a43(arg("--jobs", 4))
    summary()


if __name__ == "__main__":
    main()
