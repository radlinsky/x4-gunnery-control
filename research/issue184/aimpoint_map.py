"""Issue #184 A2 benchmark foundation: real firing ships and targets, grouped cases, hidden aimed-muzzle
truth, the two A3 box inputs, and the scorer for A3 method results. No search method yet (A3).

Reuses the accepted #176 pieces unchanged: the 288-turret A4x corpus and its ops
(`issue176-a4x/corpus.py`, `scorer.py`), the #167/#173 native query model, nearest-point selection,
runtime-box reconstruction, authored aim points and target boxes (`issue167-p3c/`).

    python3 research/issue184/aimpoint_map.py            # A2 summary
    python3 research/issue184/aimpoint_map.py --selftest

A mapper under test sees only `view(case)`. Aim points, turret, mount and `aimed_muzzles` are hidden truth.
"""
from __future__ import annotations

import itertools
import math
import sys
import xml.etree.ElementTree as ET
from collections import Counter
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
    summary()


if __name__ == "__main__":
    main()
