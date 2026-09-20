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
from simulate import EPS, REL  # noqa: E402  #176 A2 angular allowance and poor-angle rule

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


def _search(view, lo, hi, R, O, clear, cube=None):
    """Shared A3 search over the box [lo, hi] (world = p @ R + O): query its 8 outer corners, locate the
    points their rays select, then query the corners of each octree leaf `clear` rejects, to MAX_DEPTH. With `cube`,
    finally query a cube of that half-size around each located point (target frame).

    Accepted #176 A5 location rule: two other rays cross an anchor ray at agreeing depths inside the padded
    target box, AND the along-ray bracket on the anchor confirms it (forward just short, non-forward just
    past). The bracket rejects the #176 A2 witness where rays selecting different points meet at a point
    that does not exist; it only resolves ~SLACK of depth, so one crossing alone is not enough (a ray to
    another point can cross just past the anchor's point). Radius = agreed depth span / 2 + angular cone
    + binary32 rounding.
    -> (points [(centre, r)], owner(ray) -> index | None, rays {corner: (world, dir)}, cleared, uncleared, queries)."""
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


def _unproven(a, b, balls, proven):
    """Sub-boxes of [a, b], split up to GEO_DEPTH times, each neither inside one empty ball (centre, radius)
    nor inside one proven box."""
    c, r = np.asarray([x for x, _ in balls]).reshape(-1, 3), np.asarray([y for _, y in balls])
    plo, phi = np.asarray([x for x, _ in proven]).reshape(-1, 3), np.asarray([y for _, y in proven]).reshape(-1, 3)
    boxes = np.asarray([(a, b)])
    for level in range(GEO_DEPTH + 1):
        far = np.linalg.norm(np.maximum(np.abs(c[None] - boxes[:, None, 0]), np.abs(c[None] - boxes[:, None, 1])), axis=2)
        held = np.all((plo[None] <= boxes[:, None, 0]) & (boxes[:, None, 1] <= phi[None]), axis=2)
        boxes = boxes[~np.any(far < r[None], axis=1) & ~np.any(held, axis=1)]
        if level == GEO_DEPTH or not len(boxes):
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


def corner_audit(view, margin):
    """A4.1: ask ONLY the 8 outer corners of the class-expanded firing-ship box, reusing the A3 location and
    point-confirmation rules, with no subdivision. Returns what the corners expose, nothing more."""
    lo, hi = firing_box(*view["ship_box"], margin)
    R, O = view["ship_rotation"], view["ship_position"]
    points, owner, rays, _c, _u, n = _search(view, lo, hi, R, O, lambda *_: True)  # every leaf cleared: no split
    own = {tuple(c): owner(*rays[tuple(c)]) for c in _corners(lo, hi)}
    mixed = [(a, b) for a, b in _edges(lo, hi)
             if own[tuple(a)] is not None and own[tuple(b)] is not None and own[tuple(a)] != own[tuple(b)]]
    return dict(points=points, own=own, mixed=mixed, queries=n, box=(lo, hi), R=R, O=O)


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
    summary()


if __name__ == "__main__":
    main()
