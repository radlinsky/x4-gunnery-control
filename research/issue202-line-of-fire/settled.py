"""Issue #202: settled CLEAR LINE OF FIRE benchmark on real X4 9.00 collision geometry.

Truth is the straight path from the turret's SETTLED `barrelposition` to the point X4's shoot controller
bears on, never the line a candidate tests. Per test (scene, turret, target, starting yaw):

1. The bearing point (native trace, selected-target-line-of-fire.md):
   - an element or a whole ship with authored aim points: the nearest one from the TURRET COMPONENT ORIGIN
     (the shoot controller passes the weapon component to `0x00520FC0`; the muzzle never selects);
   - an element or ship without one: its box centre; a ship whose box radius exceeds 500 m adds the
     LargeTarget offset, kept only when the offset point lies inside the target's own layer-0/1 body,
     which is the HULL model (see `bearing_point`);
   - a station root: its live union-box centre (station components own no geometry, so the offset is
     always rejected).
2. CAN BEAR by the accepted #176 scorer on that point, else excluded.
3. Settling from the starting yaw by the #166 yaw gate; a trap, a repeller start or an out-of-arc rest
   is UNKNOWN.
4. The segment from the settled `barrelposition` (endpoint element 0) to the bearing point, ignoring
   only the firing turret's own meshes as X4's pre-fire gate does. Its first hit is classified with the
   #202 membership rules. UNKNOWN when the shape models disagree, the segment hits nothing, or the two
   closest hits on different instances lie within TIE metres and differ in membership.

Candidates are the `benchmark.py` decision code fed the physical first hit of each tested segment, from the
pre-turn ("parked") and the settled muzzle, plus the first `useaimtarget=true` probe alone. Guided missile
turrets bypass the obstruction check and are only counted (GUIDED).

    python3 research/issue202-line-of-fire/settled.py [--report]   # ~12 min, one niced process; needs the #176 corpus
"""
from __future__ import annotations

import gzip
import json
import math
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path[:0] = [str(HERE), str(ROOT / "research/issue176-a4x"), str(ROOT / "research/issue184")]
import benchmark as B  # noqa: E402
import geometry as Gm  # noqa: E402
import scenes as Sc  # noqa: E402
import scorer  # noqa: E402
from barrelposition_evaluator import (  # noqa: E402
    ZERO, _native_connection_name_hash, compose, evaluate, joint_matrix, load_turrets, vec_mul)
from census_common import REQUIRED_SOURCE_SETS  # noqa: E402
from yaw_rest_gate import SNAP, ZENITH, ZEROING, classify  # noqa: E402

S = Gm.S
_GATE = {}


def _classify(geometry, target):
    """Memoized #166 yaw gate: the scorer and the settling step ask the same question per start."""
    key = (geometry["beta"], geometry["t_G"], geometry["t_H"], geometry["R_H"], target)
    if key not in _GATE:
        _GATE[key] = classify(geometry, target)
    return _GATE[key]


scorer.study.classify = _classify
OUT = ROOT / ".x4-research-cache/issue202-settled/rows.jsonl.gz"

# The #202 LIVE anchor: the owner's Boron Ray with 12 M railguns and 2 L disruptors, two Osakas.
FIRING = ("ship_bor_l_destroyer_01_a_macro", {"turret medium": "turret_bor_m_railgun_02_mk1_macro",
                                              "turret large": "turret_bor_l_disruptor_01_mk1_macro"})
TARGET = "ship_ter_l_destroyer_01_a_macro"
# Stated Osaka loadout (the LIVE one was a random level-1.0 loadout that was not logged).
TARGET_LOADOUT = {"turret medium": "turret_ter_m_laser_02_mk1_macro", "turret large": "turret_ter_l_laser_01_mk1_macro",
                  "shield medium": "shield_ter_m_standard_02_mk1_macro", "shield large": "shield_ter_l_standard_01_mk1_macro",
                  "engine large": "engine_ter_l_allround_01_mk1_macro"}
# Osaka positions in the Ray frame (+Z nose, +Y up): the selected one, then the other.
ARRANGEMENTS = {
    "fixture": ((900, 0, 3500), (-900, 0, 3500)),       # the LIVE issue-197-ray-two-osaka fixture
    "screened": ((300, 150, 4000), (-50, 0, 2200)),     # the other Osaka partly screens the target
    "abeam": ((3000, 600, -400), (3000, -900, -2600)),  # high on the starboard beam
}
TARGET_YAWS = (0, 90, 180, 270)
START_YAWS = (0.0, math.pi)          # parked at yaw 0, and at rest after a target astern
SHOT_RANGE = 30000.0
TIE = 0.01                           # m: two closest hits this close on different instances are a tie
LT_SCALE = np.array([0.25, 0.25, 0.75])   # LargeTarget offset scale (0x02CC11C0)
LT_UNRESOLVED = "large-target offset: layer-0/1 body not reconstructed (nocollision_jolt part)"
MODELS = ("mesh", "hull")
METHODS = ("current", "seven", "lazy", "eight")
PHASES = ("parked", "settled")
BLOCKER_HOST = "ship_bor_l_miner_solid_01"   # the external-blocker scenes: one host, one view, one firing ship


# ---------------------------------------------------------------- scene assembly

def _choose(loadout=None, host=None):
    """Slot chooser: a stated (kind size) loadout, else the stated compatible macro for the host faction."""
    def choose(_name, kind, tags):
        if loadout is not None:
            return loadout.get(f"{kind} {'large' if 'large' in tags else 'medium'}")
        return Sc.stated_macro(kind, tags, Sc.faction(host))
    return choose


def _add_ship(scene, prefix, macro, pose, choose, group, **extra):
    els = scene.add_ship(prefix, macro, pose, choose, group, **extra)
    for e in els:
        e["ship_origin"] = Sc.to_local(e["frame"][0], pose)
    return els


def _whole(macro, pose):
    C, H = Sc.box(macro)
    return dict(label="H:hull", cls="whole ship", kind="hull", macro=macro, frame=pose, C=C, H=H,
                points=Sc.aim_points(macro))


def _element(e, cls):
    C, H = Sc.box(e["macro"])
    return dict(label=e["label"], cls=cls, kind=e["kind"], macro=e["macro"], frame=e["frame"], C=C, H=H,
                points=Sc.aim_points(e["macro"]), module=e.get("module"))


def _station(scene, plan, pose):
    """Modules of a shipped construction plan with stated equipment in each module's faction."""
    modules, elements = [], []
    for i, (m, pos, yaw) in enumerate(Sc.plan_entries(plan)):
        local = Sc.frame(pos, Sc.ry(yaw))
        f = Sc.compose(local, pose)
        label = f"H:module:{i}"
        scene.add(label, Sc.body(m), f, group="H", role="module", macro=m, module=label)
        modules.append(dict(label=label, macro=m, frame=f, local=local))
        comp = S.component(Sc.comp_of(m))
        for name, conn in sorted(S.connections(comp).items()):
            t = S.tags(conn)
            kind = Sc.slot_kind(t)
            em = None if kind is None or "component" in t else Sc.stated_macro(kind, t, Sc.faction(m))
            if em is None:
                continue
            ef = Sc.compose(Sc.attach(em, comp, conn), f)
            el = f"H:{kind}:{i}:{name}"
            scene.add(el, Sc.body(em), ef, group="H", role=kind, macro=em, conn=name, module=label)
            elements.append(dict(label=el, kind=kind, macro=em, conn=name, frame=ef, tags=t, module=label))
    C, H = Sc.station_box([dict(m, frame=m["local"]) for m in modules])   # station frame
    root = dict(label="H:station", cls="station root", kind="station", macro=plan, frame=pose, C=C, H=H,
                points=[], modules=modules)
    return [root] + [_element(e, "station surface") for e in Sc.element_targets(elements)]


def _add_firing(scene, fship, variant, pose, records):
    """The firing ship with one loadout variant. Turret sockets of non-firing mounts are siblings."""
    name, keys, fire = variant
    comp_macros = {m: records[k]["macro"] for m, k in keys.items()}

    def choose(conn, kind, tags):
        if kind == "turret" and conn in comp_macros:
            return comp_macros[conn]
        return Sc.stated_macro(kind, tags, Sc.faction(fship["ship"]))
    for e in _add_ship(scene, "F", fship["ship"], pose, choose, "F"):
        if e["kind"] == "turret" and e["conn"] in fire:
            scene.turrets.append(dict(label=e["label"], mount=e["conn"], key=keys[e["conn"]],
                                      macro=comp_macros[e["conn"]], frame=e["frame"], origin_ship=e["ship_origin"]))
    scene.firing = dict(tag=fship["tag"], ship=fship["ship"], variant=name, pose=pose)


def anchor_scenes(records):
    """The #202 LIVE Ray/two-Osaka scene: three arrangements x four Osaka yaws (turret sockets only on the
    Ray, as before, so the anchor stays comparable)."""
    ray = Sc.frame(np.zeros(3), np.eye(3))
    for arrangement, (pos_r, pos_l) in ARRANGEMENTS.items():
        for yaw in TARGET_YAWS:
            sc = Sc.Scene(f"anchor:{arrangement}:{yaw}")
            els = _add_ship(sc, "F", FIRING[0], ray, _choose(FIRING[1]), "F")
            for e in els:
                if e["kind"] == "turret":
                    sc.turrets.append(dict(label=e["label"], mount=e["conn"], key="official:" + e["macro"],
                                           macro=e["macro"], frame=e["frame"], origin_ship=e["ship_origin"]))
            sc.firing = dict(tag="Ray", ship=FIRING[0], variant="LIVE", pose=ray)
            pose = Sc.frame(pos_r, Sc.ry(yaw))
            host = _add_ship(sc, "H", TARGET, pose, _choose(TARGET_LOADOUT), "H")
            _add_ship(sc, "X", TARGET, Sc.frame(pos_l, Sc.ry(yaw)), _choose(TARGET_LOADOUT), "X", cls="ship")
            sc.targets = [_whole(TARGET, pose)] + [_element(e, "ship surface") for e in host
                                                   if Sc.body(e["macro"]) is not None]
            sc.info = dict(population="anchor", view=f"{arrangement} yaw {yaw}", blocker=None, host=TARGET)
            yield sc


def _placement(anchor, direction, reach, fship, k, gap):
    """Firing-ship pose: its box centre on the view bearing, its whole box clear of the target by `gap`."""
    import study
    C, H = Sc.box(fship["ship"])
    rot = np.asarray(study.ROT[k % 24])
    return Sc.frame(anchor + direction * (reach + float(np.linalg.norm(H)) + gap) - C @ rot, rot)


def _hosts():
    """(host macro, kind, whole-ship target?, why) for the broad population."""
    out = [(r["macro"], "ship", True, r["why"]) for r in Sc.whole_ship_targets()]
    # the only element authoring several aim points has one host: the Xenon mothership
    out.append(("ship_xen_xl_mothership_01_a_macro", "ship", False, "host of the only multi-point element"))
    out += [(plan, "station", False, why) for plan, why in Sc.STATION_PLANS.items()]
    return out


def _posed(name, kind, rot, whole):
    """(scene, targets, host box centre, host half-extents) with the host at the origin in rotation `rot`.
    Targets: the whole ship (if chosen) and its `element_targets`; on a host kept only for its multi-point
    element, that element; on a station, the root and its `element_targets`."""
    sc = Sc.Scene(name)
    pose = Sc.frame(np.zeros(3), rot)
    if kind == "station":
        targets = _station(sc, name, pose)
        return sc, targets, targets[0]["C"], targets[0]["H"]
    host = [e for e in _add_ship(sc, "H", name, pose, _choose(host=name), "H") if Sc.body(e["macro"]) is not None]
    if whole:
        els = Sc.element_targets(host) if S.macro(name).get("class") in ("ship_l", "ship_xl") else []
        targets = [_whole(name, pose)] + [_element(e, "ship surface") for e in els]
    else:
        targets = [_element(e, "ship surface") for e in host if len(Sc.aim_points(e["macro"])) > 1]
    C, H = Sc.box(name)
    return sc, targets, C, H


def broad_scenes(ships, ctx):
    """Every host x view x (two firing ships x their loadout variants), plus the external-blocker scenes."""
    for h, (name, kind, whole, why) in enumerate(_hosts()):
        _sc, targets, _C, _H = _posed(name, kind, np.eye(3), whole)
        multi = next((t for t in targets if len(t["points"]) > 1), None)
        pair = None
        if multi is not None:                         # nearest authored pair, in the host frame
            M, u, v = Sc.nearest_pair(multi["points"])
            pair = (Sc.to_world(M, multi["frame"]), u @ multi["frame"][1], v @ multi["frame"][1])
        for v, view in enumerate(Sc.views(pair)):
            yield from _view_scenes(name, kind, whole, h, v, view, pair, ships, ctx, why)
    yield from blocker_scenes(ships, ctx)


def _view_scenes(name, kind, whole, h, v, view, pair, ships, ctx, why, blocker=None):
    group, bearing, direction, rot = view
    host, targets, C, H = _posed(name, kind, rot, whole)
    centre = C @ rot
    anchor = centre if group == "ordinary" else pair[0] @ rot
    reach = float(np.linalg.norm(H)) + float(np.linalg.norm(anchor - centre))
    for fship in (ships if blocker is None else [ships[2]]):
        pose = _placement(anchor, np.asarray(direction, float), reach, fship, 6 * ships.index(fship) + v,
                          Sc.GAPS[group])
        for variant in fship["variants"]:
            sc = Sc.Scene(f"{name}:{group}/b{bearing}:{fship['tag']}:{variant[0]}" + (f":{blocker}" if blocker else ""))
            sc.instances, sc.meta = list(host.instances), dict(host.meta)
            _add_firing(sc, fship, variant, pose, ctx["records"])
            if blocker is not None:
                _add_blocker(sc, blocker, pose, anchor, targets[0], ctx)
            sc.targets = targets
            sc.info = dict(population="broad", view=f"{group}/b{bearing}", blocker=blocker, host=name, why=why)
            yield sc


def _add_blocker(sc, cls, firing_pose, anchor, whole, ctx):
    """One external body between the firing ship and the target: at mid-distance, shifted sideways by a
    quarter of its own size so it screens part of the firing ship. The small object is metres across, so it
    sits on one firing turret's own settled bearing path to the whole ship, 60% of the way along."""
    macro = Sc.BLOCKERS[cls]
    C, H = Sc.box(macro)
    start = firing_pose[0]
    d = anchor - start
    side = np.cross(d, [0.0, 1.0, 0.0])
    side /= np.linalg.norm(side)
    if cls == "small":
        centre = None
        for tur in sc.turrets:
            record = ctx["records"][tur["key"]]
            aim = bearing_point(sc, tur, whole)[0]
            if record["weapon_behavior"] == "guided_missile" or aim is None:
                continue
            state, y, x = settle(record, ctx["turs"][tur["macro"]], tuple(map(float, Sc.to_local(aim, tur["frame"]))), 0.0)
            if state == "SETTLED":
                o = _muzzles(ctx["evs"][tur["macro"]], record["endpoint"]["tag"], x, y, tur["frame"])[0][0]
                centre = o + 0.6 * (aim - o)
                break
        if centre is None:
            return
    else:
        centre = start + 0.5 * d + side * 0.25 * float(np.linalg.norm(H))
    f = Sc.frame(centre - C, np.eye(3))
    if cls == "ship":
        _add_ship(sc, "X", macro, f, _choose(host=macro), "X", cls="ship")
    else:
        sc.add(f"X:{cls}", Sc.body(macro), f, group="X", role=cls, cls=cls)


def blocker_scenes(ships, ctx):
    """Each external blocker class once: host BLOCKER_HOST, its first ordinary view, firing ship L2."""
    name, kind, whole, _why = next(x for x in _hosts() if Sc.comp_of(x[0]) == BLOCKER_HOST)
    for cls in Sc.BLOCKERS:
        yield from _view_scenes(name, kind, whole, 0, 0, Sc.views(None)[0], None, ships, ctx,
                                f"external blocker: {cls}", blocker=cls)


# ---------------------------------------------------------------- symbols (the benchmark.py world)

def module_rank(scene, target):
    """Station modules ranked by distance from the firing ship (production `sortbydistanceto`)."""
    if target["cls"] not in ("station root",):
        return {}
    o = scene.firing["pose"][0]
    mods = sorted(target["modules"], key=lambda m: (float(np.linalg.norm(m["frame"][0] - o)), m["label"]))
    return {m["label"]: ("M1", "M2")[i] if i < 2 else "M3" for i, m in enumerate(mods)}


def symbol(scene, label, turret, target, rank):
    if label is None:
        return None
    m = scene.meta[label]
    group, role = m["group"], m["role"]
    if group == "F":
        if role == "hull":
            return "S"
        if role == "turret":
            return "W" if label == turret["label"] else "W2"
        return {"shield": "SSH", "engine": "SEN"}[role]
    if group == "X":
        return {"ship": "X", "module": "KM", "asteroid": "A", "small": "O"}[m["cls"]]
    cls = target["cls"]
    if cls in ("whole ship", "ship surface"):
        if label == target["label"] and cls == "ship surface":
            return "T"
        return "P" if role == "hull" else {"turret": "T2", "shield": "PSH", "engine": "PEN"}[role]
    if cls == "station root":
        mod = rank[m["module"]]
        return mod if role == "module" else {"M1": "MT", "M2": "MS", "M3": "MT3"}[mod]
    if label == target["label"]:
        return "MT"
    same = m["module"] == target["module"]
    if role == "module":
        return "M1" if same else "M2"
    return "MT2" if same else "MS"


TARGET_SYMBOL = {"whole ship": "P", "ship surface": "T", "station root": "ST", "station surface": "MT"}


# ---------------------------------------------------------------- turret settling

def _yaw_gap(tur, pt, y):
    """g(y) = wrap(F(y) - y) of the decoded #166 yaw map (turret-yaw-resting-point-gate.md)."""
    G, H = tur["seg"]["G"], tur["seg"]["H"]
    pivot = compose(G, compose((ZERO, joint_matrix(0.0, y)), H))[0]
    d = [p - q for p, q in zip(pt, pivot)]
    n = math.sqrt(sum(v * v for v in d))
    d = [0.0 if abs(v) < ZEROING * n else v for v in d]
    dh = vec_mul(tuple(d), tuple(zip(*H[1])))
    n = math.sqrt(sum(v * v for v in d))
    f = 0.0 if abs(dh[0]) < ZENITH * n and abs(dh[2]) < ZENITH * n else math.atan2(dh[0], dh[2]) - tur["yaw"]["beta"]
    return math.remainder(f - y, 2 * math.pi)


def _pitch(tur, pt, y):
    """Leaf pitch at yaw y, exactly as study.geometry scores each resting yaw."""
    L, G, H = tur["seg"]["L"], tur["seg"]["G"], tur["seg"]["H"]
    frame = compose(G, compose((ZERO, joint_matrix(0.0, y)), H))
    d = [p - q for p, q in zip(pt, frame[0])]
    n = math.sqrt(sum(v * v for v in d))
    d = tuple(0.0 if abs(v) < ZEROING * n else v for v in d)
    q = vec_mul(d, tuple(zip(*frame[1])))
    aim = L[1][2]
    x = math.remainder(math.atan2(q[1], q[2]) - math.atan2(aim[1], aim[2]), 2 * math.pi)
    lo, hi = tur["arc"]
    return x, round(lo, 4) <= round(math.degrees(x), 4) <= round(hi, 4)


def settled_yaw(tur, pt, y0):
    """(kind, yaw) the yaw mover reaches from rest at y0: it moves toward sign(g) and stops at the first
    attractor that way. kind is 'rest', 'trap' or 'start on a repeller'."""
    gate = _classify(tur["yaw"], pt)
    attractors = [(y, "rest") for y in gate["resting"]] + [(y, "trap") for y in gate["traps"]]
    g0 = _yaw_gap(tur, pt, y0)
    if abs(g0) < SNAP:
        y, kind = min(attractors, key=lambda a: abs(math.remainder(a[0] - y0, 2 * math.pi)))
        return (kind, y) if abs(math.remainder(y - y0, 2 * math.pi)) <= 1e-3 else ("start on a repeller", None)
    sign = 1 if g0 > 0 else -1
    y, kind = min(attractors, key=lambda a: (sign * (a[0] - y0)) % (2 * math.pi))
    return kind, y


def check_settling():
    """#166 KB two-rest geometry: pivot (0, 1, -5), target at rho = 3, bearing 0 rests at 0 and -pi.
    The rest reached must follow the starting yaw, never the favorable one."""
    I = ((1.0, 0, 0), (0, 1.0, 0), (0, 0, 1.0))
    tur = dict(yaw=dict(t_G=(0.0, 1.0, -5.0), t_H=ZERO, R_H=I, beta=0.0),
               seg=dict(G=((0.0, 1.0, -5.0), I), H=(ZERO, I)))
    pt = (0.0, 1.0, 3.0)
    rests = sorted(_classify(tur["yaw"], pt)["resting"])
    assert len(rests) == 2, rests
    for y0 in (0.0, 0.5, -0.5, 3.0, -3.0, math.pi):
        kind, y = settled_yaw(tur, pt, y0)
        want = math.pi if y0 == math.pi else 0.0
        assert kind == "rest" and abs(math.remainder(y - want, 2 * math.pi)) < 1e-6, (y0, kind, y)


def settle(record, tur, pt, y0):
    """-> (state, yaw, pitch). state CAN BEAR+settled 'SETTLED', else the UNKNOWN reason."""
    bear = scorer.score(record, pt)
    if bear["decision"] is None:
        return "scorer UNKNOWN", None, None
    if not bear["decision"]:
        return "CANNOT BEAR", None, None
    kind, y = settled_yaw(tur, pt, y0)
    if kind != "rest":
        return kind, None, None
    x, ok = _pitch(tur, pt, y)
    if not ok:
        return "settled rest out of arc", None, None
    return "SETTLED", y, x


# ---------------------------------------------------------------- aim points

def _select(o_local, points):
    """Native nearest authored aim point (binary32 distance, earlier wins ties); origin in target frame."""
    import study
    return study.select(tuple(map(float, o_local)), [tuple(map(float, p)) for p in points])


def bearing_point(scene, turret, target):
    """(world point or None, source, selected index or None) of the point X4's shoot controller bears on.

    The LargeTarget point-inside test (`0x0051BEB0`) runs Jolt CollidePoint on the target's layer-0/1 body
    (`+0x260`). That body is built by the same member walk as the layer-3 body, but from each part's `-hull`
    convex shape (geometry `+0x28`, getter `0x000B1D40`), and it also drops `nocollision_jolt` parts
    (`0x00747AA2`). So the test is the HULL model on the same parts; a target with a `nocollision_jolt`
    part is not reconstructed and its row stays UNKNOWN."""
    o = Sc.to_local(turret["frame"][0], target["frame"])
    if target["points"]:
        i = _select(o, target["points"])
        return Sc.to_world(target["points"][i], target["frame"]), "authored", i
    C = target["C"]
    if target["cls"] != "whole ship" or float(np.linalg.norm(target["H"])) <= Sc.LARGE_TARGET_RADIUS:
        return Sc.to_world(C, target["frame"]), "centre", None
    Cf, Hf = Sc.box(scene.firing["ship"])
    offset = (turret["origin_ship"] - Cf) / Hf * target["H"] * LT_SCALE
    p = Sc.to_world(C + offset, target["frame"])
    body = [(b, f) for label, b, f in scene.instances if scene.meta[label]["group"] == "H"]
    if any(b.jolt for b, _f in body):
        return None, LT_UNRESOLVED, None
    if any(Gm.inside(b, Sc.to_local(p, f), "hull") for b, f in body):
        return p, "centre + large-target offset", None
    return Sc.to_world(C, target["frame"]), "centre (large-target offset outside the body)", None


def endpoints(scene, turret, target, origin, rank):
    """World endpoints of every tested line from `origin`: the benchmark.py keys."""
    f, C, H = target["frame"], target["C"], target["H"]
    if target["cls"] == "station root":
        by = {v: m for m, v in rank.items() if v in ("M1", "M2")}
        mods = {m["label"]: m for m in target["modules"]}
        out = {k: Sc.to_world(Sc.box(mods[m]["macro"])[0], mods[m]["frame"]) for k, m in by.items()}
        out["aim"] = Sc.to_world(C, f)
        return out
    o = Sc.to_local(origin, f)
    if target["cls"] == "whole ship":
        gap, push = np.linalg.norm(C - o), 0.9 * H.min()
        t = Sc.to_local(turret["frame"][0], f)
        return {"c": Sc.to_world(C + (C - o) * push / gap if gap > 0 and push > 0 else C, f),
                # MD useaimtarget: the same selector, but never the LargeTarget offset
                "aim": Sc.to_world(target["points"][_select(t, target["points"])] if target["points"] else C, f)}
    t = Sc.to_local(turret["frame"][0], f)
    out = {"c": Sc.to_world(C, f),
           "aim": Sc.to_world(target["points"][_select(t, target["points"])] if target["points"] else C, f)}
    for axis, name in enumerate("xyz"):
        for pct, sign in (("25", -0.5), ("75", 0.5)):
            p = C.copy()
            p[axis] += sign * H[axis]
            out[name + pct] = Sc.to_world(p, f)
    return out


# ---------------------------------------------------------------- one test

def _endpoint_names(ev, tag):
    lasers = [n for n, c in ev["connections"].items() if tag in c["tag_tokens"]]
    return sorted(lasers, key=_native_connection_name_hash)


def _muzzles(ev, tag, x, y, f):
    """World (position, +Z direction) of every firing endpoint at joint angles (x, y)."""
    out = []
    for conn in _endpoint_names(ev, tag):
        tr = evaluate(dict(ev, selected_connection=conn), x, y)["transform"]
        out.append((np.asarray(tr["translation"]) @ f[1] + f[0], np.asarray(tr["z"]) @ f[1]))
    return out


def _lines(scene, origin, turret, target, rank, models):
    """First hit of every tested line; 'aim_ex' is the probe line under MD excludeself=true, which also drops
    the firing ship's own hull (its ancestor) but keeps its siblings."""
    out = {}
    ends = endpoints(scene, turret, target, origin, rank)
    exself = {turret["label"]} | {label for label in scene.meta if label.startswith("F:hull")}
    for model in models:
        out[model] = {}
        for e, p in list(ends.items()) + [("aim_ex", ends["aim"])]:
            label, _t = Gm.first_hit(scene.instances, origin, e=p, model=model, skip=exself if e == "aim_ex" else ())
            sym = symbol(scene, label, turret, target, rank)
            out[model][e] = [sym] if sym else []
    return out


def run_test(scene, turret, target, start, ctx, models=MODELS):
    record = ctx["records"][turret["key"]]
    rank = module_rank(scene, target)
    row = dict(scene=scene.name, **scene.info, firing=scene.firing["tag"], variant=scene.firing["variant"],
               turret=turret["label"], macro=turret["macro"], category=Sc.turret_category(turret["key"], ctx["records"]),
               target=target["label"], target_cls=target["cls"], target_kind=target["kind"],
               target_macro=target["macro"], aim_points=len(target["points"]), start=start)
    if record["weapon_behavior"] == "guided_missile":
        row["state"] = "GUIDED"
        return row
    aim, source, index = bearing_point(scene, turret, target)
    row.update(aim_source=source, aim_index=index)
    if aim is None:
        row["state"] = source
        return row
    pt = tuple(float(v) for v in Sc.to_local(aim, turret["frame"]))
    state, y, x = settle(record, ctx["turs"][turret["macro"]], pt, start)
    row["state"] = state
    ev, tag = ctx["evs"][turret["macro"]], record["endpoint"]["tag"]
    parked = _muzzles(ev, tag, 0.0, start, turret["frame"])
    row["phases"] = {"parked": _lines(scene, parked[0][0], turret, target, rank, models)}
    if len(target["points"]) > 1:        # diagnostic: which point a muzzle-origin selector would choose
        row["select_from"] = {"turret origin": index,
                              "parked muzzle": _select(Sc.to_local(parked[0][0], target["frame"]), target["points"])}
    if state != "SETTLED":
        return row
    settled = _muzzles(ev, tag, x, y, turret["frame"])
    row["phases"]["settled"] = _lines(scene, settled[0][0], turret, target, rank, models)
    if len(target["points"]) > 1:
        row["select_from"]["settled muzzle"] = _select(Sc.to_local(settled[0][0], target["frame"]), target["points"])
    row["yaw"], row["pitch"] = y, x
    own = {turret["label"]}
    row["truth_hits"] = {}
    for m in models:
        a, ta, b, tb = Gm.first_hit(scene.instances, settled[0][0], e=aim, model=m, skip=own, runner_up=True)
        row["truth_hits"][m] = [symbol(scene, a, turret, target, rank), ta,
                                symbol(scene, b, turret, target, rank) if tb - ta < TIE else None]
    if all(h[0] is None for h in row["truth_hits"].values()):   # diagnostic only: what lies past the aim point
        o = settled[0][0]
        d = (aim - o) / np.linalg.norm(aim - o)
        row["beyond"] = {m: symbol(scene, Gm.first_hit(scene.instances, o, d=d, tmax=SHOT_RANGE, model=m, skip=own)[0],
                                   turret, target, rank) for m in models}
    # diagnostic only: barrel 0's settled +Z projectile path
    p, d = settled[0]
    row["shots"] = {m: symbol(scene, Gm.first_hit(scene.instances, p, d=d, tmax=SHOT_RANGE, model=m, skip=own)[0],
                              turret, target, rank) for m in models}
    row["barrels"] = len(settled)
    return row


# ---------------------------------------------------------------- truth and candidates

def _cls(tsym, hit):
    return None if hit is None else B.qualifies(tsym, hit)


def tsym(row):
    return TARGET_SYMBOL[row["target_cls"]]


def truth(row):
    """CLEAR / NOT, or the UNKNOWN reason, for the settled barrelposition -> bearing point path."""
    if row["state"] != "SETTLED":
        return row["state"]
    t = tsym(row)
    classes = set()
    for sym, _d, tie in row["truth_hits"].values():
        if tie is not None and _cls(t, tie) != _cls(t, sym):
            return "first-hit tie"
        classes.add(_cls(t, sym))
    if len(classes) > 1:
        return "shape models disagree"
    cls = classes.pop()
    if cls is None:
        return "aim path reaches no geometry"
    return "CLEAR" if cls else "NOT"


def aim_probe(row, phase, model):
    """The first `useaimtarget=true` probe by itself: True iff its first hit is a target member."""
    line = row["phases"][phase][model].get("aim", [])
    return bool(line) and B.qualifies(tsym(row), line[0])


def candidates(row, model):
    """{(method, phase): (status, reason, calls)} through the benchmark.py decision code."""
    out = {}
    for phase, lines in row["phases"].items():
        sc = dict(id="physical", target=tsym(row), lines=lines[model])
        for method in METHODS:
            out[method, phase] = B.candidate(sc, method)
    return out


def outcome(said, t):
    return "TP" if said and t == "CLEAR" else "FP" if said else "FN" if t == "CLEAR" else "TN"


# ---------------------------------------------------------------- population

def context():
    """Firing ships, #176 records, accepted turret geometry and barrelposition evaluators."""
    ships, records = Sc.firing_population()
    macros = sorted({records[k]["macro"] for s in ships for _n, keys, fire in s["variants"] for k in keys.values()}
                    | set(FIRING[1].values()))
    src = ROOT / ".x4-research-cache/official-source-sets"
    ani = ROOT / ".x4-research-cache/issue72-a2-ani-resources"
    evs = load_turrets({n: src / n for n in REQUIRED_SOURCE_SETS}, {n: ani / n for n in REQUIRED_SOURCE_SETS}, macros)
    turs = {m: scorer.accepted_turret(records["official:" + m]) for m in macros}
    return ships, dict(records=records, evs=evs, turs=turs)


def population(ships, ctx, out):
    """Run every scene, streaming rows to `out`; -> count."""
    n, t0 = 0, time.time()
    scenes = list(anchor_scenes(ctx["records"])) + list(broad_scenes(ships, ctx))
    for i, scene in enumerate(scenes):
        for turret in scene.turrets:
            for target in scene.targets:
                for start in START_YAWS:
                    out.write(json.dumps(run_test(scene, turret, target, start, ctx), separators=(",", ":"),
                                         default=float) + "\n")
                    n += 1
        print(f"[{i + 1}/{len(scenes)}] {scene.name}: {n} tests, {time.time() - t0:.0f} s", flush=True)
    return n


def check_kinematics(ctx):
    """The evaluator's element-0 endpoint must be the scorer's muzzle (same accepted transform chain)."""
    import study
    for m, ev in ctx["evs"].items():
        tag = ctx["records"]["official:" + m]["endpoint"]["tag"]
        assert _endpoint_names(ev, tag)[0] == ev["selected_connection"], m
        for pt in ((30.0, 40.0, 900.0), (-400.0, 150.0, -60.0)):
            g = study.geometry(ctx["turs"][m], ((1.0, 0, 0), (0, 1.0, 0), (0, 0, 1.0)), ZERO, pt)
            if g["decision"]:
                mine = evaluate(ev, g["pitch"], g["yaw"])["transform"]["translation"]
                assert np.allclose(mine, g["muzzle"], atol=1e-6), (m, mine, g["muzzle"])


# ---------------------------------------------------------------- #60 station geometry

def station60(plan="xen_defence", distance=4000.0, samples=200):
    """Where the station root's bearing point (the live union-box centre) lies, and what a straight line from
    outside toward it hits first."""
    sc = Sc.Scene(plan)
    root = _station(sc, plan, Sc.frame(np.zeros(3), np.eye(3)))[0]
    centre = root["C"]
    modules = [(label, b, f) for label, b, f in sc.instances if sc.meta[label]["role"] == "module"]
    out = dict(centre=centre.round(1).tolist(), modules=len(root["modules"]), inside={}, lines={})
    for model in MODELS:
        out["inside"][model] = next((label for label, b, f in modules if Gm.inside(b, Sc.to_local(centre, f), model)),
                                    None)
    golden = math.pi * (3 - math.sqrt(5))
    for model in MODELS:
        firsts = Counter()
        for k in range(samples):
            z = 1 - 2 * (k + 0.5) / samples
            r = math.sqrt(1 - z * z)
            direction = np.array([r * math.cos(golden * k), z, r * math.sin(golden * k)])
            hit = Gm.first_hit(sc.instances, centre + (distance + float(np.linalg.norm(root["H"]))) * direction,
                               e=centre, model=model)[0]
            firsts["no module" if hit is None else "module" if sc.meta[hit]["role"] == "module" else "element"] += 1
        out["lines"][model] = dict(sorted(firsts.items()))
    return out


# ---------------------------------------------------------------- scoring

MECH = {"S": "own hull", "W": "own turret socket", "W2": "sibling turret (firing ship)",
        "SSH": "sibling shield (firing ship)", "SEN": "sibling engine (firing ship)", "X": "other ship",
        "WR": "ship wreck", "KM": "external station module", "A": "asteroid", "O": "small object (satellite)",
        None: "no hit"}
TARGET_MECH = {
    "T": {"T": "selected element", "P": "parent hull", "T2": "sibling turret on target",
          "PSH": "sibling shield on target", "PEN": "sibling engine on target"},
    "P": {"P": "target hull", "T2": "target's own element", "PSH": "target's own element", "PEN": "target's own element"},
    "ST": {k: "station module" for k in ("M1", "M2", "M3")} | {k: "module element" for k in ("MT", "MS", "MT3")},
    "MT": {"MT": "selected element", "M1": "parent module", "M2": "other module", "MT2": "sibling element, same module",
           "MS": "element on another module"},
}


def mech(row, sym):
    return TARGET_MECH[tsym(row)].get(sym) or MECH[sym]


def probe_status(row, phase, model):
    return ("C" if aim_probe(row, phase, model) else "N"), "", 1


def probe_ex_status(row, phase, model):
    """Probe, then only when its first hit is the firing turret itself (a Q(W) call identifies it) the same
    line with excludeself=true: 1 or 3 calls."""
    lines = row["phases"][phase][model]
    if aim_probe(row, phase, model):
        return "C", "", 1
    if lines.get("aim") != ["W"]:
        return "N", "", 2
    ex = lines.get("aim_ex", [])
    return ("C" if ex and B.qualifies(tsym(row), ex[0]) else "N"), "self", 3


def statuses(row, model):
    """{(method, phase): (status, reason, calls)} with the probe as method 'probe'."""
    out = candidates(row, model)
    for phase in row["phases"]:
        out["probe", phase] = probe_status(row, phase, model)
        out["probe+ex", phase] = probe_ex_status(row, phase, model)
    return out


def scored(rows, model="mesh"):
    """[(row, truth, statuses)] for rows with defensible truth."""
    out = []
    for r in rows:
        t = truth(r)
        if t in ("CLEAR", "NOT") and "settled" in r["phases"]:
            out.append((r, t, statuses(r, model)))
    return out


def matrix(items, method, phase):
    c = Counter()
    for _r, t, st in items:
        status, _reason, calls = st[method, phase]
        c[outcome(status == "C", t)] += 1
        c["UNKNOWN"] += status == "U"
        c["UNKNOWN on CLEAR truth"] += status == "U" and t == "CLEAR"
        c["n"] += 1
        c["calls"] += calls
    return c


REPORTED = ("probe", "probe+ex", "current", "seven", "lazy", "eight")


def accuracy_table(items, say, methods=REPORTED):
    say("| method | phase | n | TP | FP | TN | FN | UNKNOWN | UNKNOWN on CLEAR | mean calls |")
    say("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for method in methods:
        for phase in PHASES:
            c = matrix(items, method, phase)
            u = "-" if method.startswith("probe") else c["UNKNOWN"]
            uc = "-" if method.startswith("probe") else c["UNKNOWN on CLEAR truth"]
            say(f"| {method} | {phase} | {c['n']} | {c['TP']} | {c['FP']} | {c['TN']} | {c['FN']} | {u} | {uc} | "
                f"{c['calls'] / max(1, c['n']):.2f} |")


def breakdown(items, key, say, title):
    groups = defaultdict(list)
    for it in items:
        groups[key(it)].append(it)
    cols = [(m, p) for m in ("probe", "current", "seven") for p in PHASES] + [("probe+ex", "settled")]
    say(f"\n### By {title} (MESH; each cell FP / FN)\n")
    say(f"| {title} | n | truth CLEAR | " + " | ".join(f"{m} {p}" for m, p in cols) + " |")
    say("|---|---:|---:|" + "---:|" * len(cols))
    for k in sorted(groups, key=str):
        g = groups[k]
        cells = []
        for m, p in cols:
            c = matrix(g, m, p)
            cells.append(f"{c['FP']} / {c['FN']}")
        say(f"| {k} | {len(g)} | {sum(t == 'CLEAR' for _r, t, _s in g)} | " + " | ".join(cells) + " |")


def selector_key(row):
    if row["aim_points"] < 2:
        return f"{min(row['aim_points'], 2)} aim points"
    sel = row.get("select_from", {})
    return "2+ aim points, selector-origin sensitive" if len(set(sel.values())) > 1 else \
        "2+ aim points, every origin selects the same point"


def blocker_key(row):
    return mech(row, row["truth_hits"]["mesh"][0])


def turret_key(row):
    c = row["category"]
    return f"{c['size']} {c['behavior']}, {c['endpoints']} endpoint"


def first_clear(row, phase, model, order):
    lines = row["phases"][phase][model]
    return next((e for e in order if lines.get(e) and B.qualifies(tsym(row), lines[e][0])), None)


def cause(row, t, method, phase, model="mesh"):
    """A physical explanation of one wrong answer."""
    lines = row["phases"][phase][model]
    truth_mech = mech(row, row["truth_hits"][model][0])
    where = "parked origin" if phase == "parked" else "settled origin"
    if method == "probe+ex":
        return f"{'FP' if t == 'NOT' else 'FN'}: excludeself=true line from {where}; bearing path first hit {truth_mech}"
    if method == "probe":
        first = lines["aim"][0] if lines.get("aim") else None
        endpoint = "" if row.get("aim_source") in ("authored", "centre", "centre (large-target offset outside the body)") \
            else f"; probe endpoint is the box centre, the turret bears on the {row['aim_source']}"
        if t == "CLEAR":
            return f"FN: probe from {where} first hits {mech(row, first)}{endpoint}"
        return f"FP: probe from {where} reaches the target; the bearing path is blocked by {truth_mech}{endpoint}"
    order = ["M1", "M2"] if tsym(row) == "ST" else ["aim", "x25", "x75", "y25", "y75", "z25", "z75"] \
        if method != "current" and tsym(row) in ("T", "MT") else ["c"]
    if t == "NOT":
        e = first_clear(row, phase, model, order)
        return f"FP: '{e}' line from {where} reaches the target; the bearing path is blocked by {truth_mech}"
    e = order[0]
    first = lines[e][0] if lines.get(e) else None
    return f"FN: '{e}' line from {where} first hits {mech(row, first)} (no tested line reaches the target)"


# ---------------------------------------------------------------- integrity

def _synthetic(target_cls, truth_sym, lines, points=1):
    hits = {m: [truth_sym, 100.0, None] for m in MODELS}
    return dict(state="SETTLED", target_cls=target_cls, truth_hits=hits, aim_points=points,
                phases={p: {m: lines for m in MODELS} for p in PHASES})


def integrity(rows, items):
    """Checks that would catch the known ways this benchmark could silently lie. -> list of failures."""
    bad = []
    # 1 candidate lines never define truth
    for r in [r for r in rows if r.get("phases") and r["state"] == "SETTLED"][::97]:
        blank = dict(r, phases={p: {m: {e: ["P"] for e in ls[m]} for m in ls} for p, ls in r["phases"].items()})
        if truth(blank) != truth(r):
            bad.append(f"truth depends on candidate lines: {r['scene']} {r['turret']} {r['target']}")
    # 2 an UNKNOWN candidate never counts as a correct CLEAR
    r = _synthetic("ship surface", "T", {})
    st = statuses(r, "mesh")
    if st["seven", "settled"][0] != "U" or matrix([(r, "CLEAR", st)], "seven", "settled")["FN"] != 1:
        bad.append("UNKNOWN candidate on CLEAR truth is not an FN")
    # 3 an UNKNOWN truth never enters the matrix (a CLEAR changed to UNKNOWN cannot become an FN)
    r = _synthetic("ship surface", "T", {})
    r["truth_hits"]["hull"] = ["P", 100.0, None]
    if truth(r) != "shape models disagree" or scored([r]):
        bad.append("an UNKNOWN truth row is scored")
    n = sum(truth(r) in ("CLEAR", "NOT") and "settled" in r.get("phases", {}) for r in rows)
    if n != len(items):
        bad.append(f"scored rows {len(items)} != defensible truth rows {n}")
    # 4 a station element's parent module, sibling or another module is never CLEAR
    for sym in ("M1", "M2", "MT2", "MS"):
        if truth(_synthetic("station surface", sym, {})) != "NOT":
            bad.append(f"station-surface first hit {sym} is CLEAR")
    for r, t, _s in items:
        if r["target_cls"] == "station surface" and r["truth_hits"]["mesh"][0] != "MT" and t == "CLEAR":
            bad.append(f"station-surface row CLEAR on {r['truth_hits']['mesh'][0]}: {r['scene']}")
    # 5 multi-point rows carry the selection from every plausible origin and use the native one
    for r, _t, _s in items:
        if r["aim_points"] > 1:
            sel = r.get("select_from", {})
            if set(sel) != {"turret origin", "parked muzzle", "settled muzzle"} or sel["turret origin"] != r["aim_index"]:
                bad.append(f"multi-point row without its selector record: {r['scene']} {r['turret']}")
    # 6 a box point that reaches the element never turns a blocked bearing path into a correct answer
    r = _synthetic("ship surface", "P", {"aim": ["P"], "c": ["P"], "x25": ["T"], "*": ["P"]})
    r["phases"] = {p: {m: {e: ["T"] if e == "x25" else ["P"] for e in ("aim", "c", "x25", "x75", "y25", "y75", "z25", "z75")}
                       for m in MODELS} for p in PHASES}
    if matrix([(r, truth(r), statuses(r, "mesh"))], "seven", "settled")["FP"] != 1:
        bad.append("an alternate box point clearing a blocked bearing path is not an FP")
    # lazy classification never changes a status
    for r, _t, st in items:
        for p in PHASES:
            if st["lazy", p][0] != st["seven", p][0]:
                bad.append(f"lazy != seven: {r['scene']} {r['turret']} {r['target']} {p}")
    return bad


# ---------------------------------------------------------------- report

def _q(values, p):
    values = sorted(values)
    return values[min(len(values) - 1, int(p * len(values)))] if values else 0


ORDER = ["CLEAR", "NOT", "GUIDED", "CANNOT BEAR", "scorer UNKNOWN", "trap", "start on a repeller",
         "settled rest out of arc", LT_UNRESOLVED,
         "shape models disagree", "first-hit tie", "aim path reaches no geometry"]
CLASSES = ("whole ship", "ship surface", "station surface", "station root")


def report(rows):
    out = []
    say = out.append
    items_all = scored(rows)
    items_hull = scored(rows, "hull")
    say(f"# Settled line-of-fire benchmark ({len(rows)} tests)\n")
    say("## Population\n")
    for pop in ("anchor", "broad"):
        rs = [r for r in rows if r["population"] == pop]
        say(f"- {pop}: {len({r['scene'] for r in rs})} scenes, {len({(r['scene'], r['turret']) for r in rs})} "
            f"turret placements, {len(rs)} tests")
    say("\n| firing ship | variant | firing turrets |")
    say("|---|---|---|")
    fire = defaultdict(set)
    for r in rows:
        fire[r["firing"], r["variant"]].add((r["turret"].split(":")[-1], r["macro"], turret_key(r)))
    for (f, v), ts in sorted(fire.items()):
        macros = Counter(f"{m} ({k})" for _mt, m, k in ts)
        say(f"| {f} | {v} | " + "; ".join(f"{n}x {m}" for m, n in sorted(macros.items())) + " |")
    say("\n| target class | distinct targets | hosts | tests |")
    say("|---|---:|---:|---:|")
    for cls in CLASSES:
        rs = [r for r in rows if r["target_cls"] == cls]
        say(f"| {cls} | {len({(r['host'], r['target_macro'], r['target']) for r in rs})} | "
            f"{len({r['host'] for r in rs})} | {len(rs)} |")
    say("\n## Truth and exclusions\n")
    states = Counter((truth(r), r["target_cls"]) for r in rows)
    say("| truth | " + " | ".join(CLASSES) + " | total |")
    say("|---|" + "---:|" * (len(CLASSES) + 1))
    for t in ORDER + sorted({s for s, _c in states} - set(ORDER)):
        say(f"| {t} | " + " | ".join(str(states[t, c]) for c in CLASSES) + f" | {sum(states[t, c] for c in CLASSES)} |")
    disagree = Counter((r["target_cls"], r["truth_hits"]["mesh"][0], r["truth_hits"]["hull"][0]) for r in rows
                       if truth(r) == "shape models disagree")
    say("\nShape-model disagreements (target class, MESH first hit, HULL first hit):\n")
    say("\n".join(f"- {c}: {mech_sym(a)} vs {mech_sym(b)}: {n}" for (c, a, b), n in disagree.most_common(12)))
    for pop in ("all", "anchor", "broad"):
        items = [it for it in items_all if pop == "all" or it[0]["population"] == pop]
        say(f"\n## Accuracy, MESH, {pop} ({len(items)} scored rows)\n")
        accuracy_table(items, say)
    say("\n## Accuracy, HULL shape model, all\n")
    accuracy_table(items_hull, say, ("probe", "probe+ex", "current", "seven"))
    for cls in CLASSES:
        items = [it for it in items_all if it[0]["target_cls"] == cls]
        say(f"\n## {cls} ({len(items)} scored rows, MESH)\n")
        accuracy_table(items, say, ("probe", "probe+ex", "current", "seven", "lazy"))
    say("\n## Breakdowns")
    broad = [it for it in items_all if it[0]["population"] == "broad"]
    breakdown(items_all, lambda it: it[0]["target_cls"], say, "target class")
    breakdown([it for it in items_all if it[0]["target_kind"] != "hull"], lambda it: f"{it[0]['target_cls']}: "
              f"{it[0]['target_kind']}", say, "surface type")
    breakdown(items_all, lambda it: selector_key(it[0]), say, "aim-point count and selector")
    breakdown(items_all, lambda it: f"{tsym(it[0])}: {blocker_key(it[0])}", say, "first hit on the bearing path")
    breakdown(broad, lambda it: turret_key(it[0]), say, "firing turret (broad)")
    breakdown(broad, lambda it: it[0]["firing"], say, "firing ship (broad)")
    breakdown(broad, lambda it: it[0]["blocker"] or "none", say, "external blocker scene (broad)")
    breakdown([it for it in items_all if it[0]["target_cls"] == "whole ship"],
              lambda it: it[0]["aim_source"], say, "whole-ship bearing point")
    covered = Counter(blocker_key(r) for r, _t, _s in items_all)
    say("\nBlocker mechanisms never the first hit on a scored bearing path: " +
        (", ".join(sorted(set(MECH.values()) - set(covered) - {"no hit", "own turret socket"})) or "none"))
    say("\n## What each wrong answer is (MESH)\n")
    for method in ("probe", "probe+ex", "current", "seven"):
        for phase in PHASES:
            causes = Counter()
            for r, t, st in items_all:
                if (st[method, phase][0] == "C") != (t == "CLEAR"):
                    causes[f"{r['target_cls']}: {cause(r, t, method, phase)}"] += 1
            say(f"\n### {method}, {phase} ({sum(causes.values())} wrong)\n")
            say("\n".join(f"- {n}: {k}" for k, n in causes.most_common(14)) or "- none")
    say("\n## Do the six box points ever help? (MESH, rows where seven and the probe disagree)\n")
    say("| phase | truth | seven CLEAR, probe not | count |")
    say("|---|---|---|---:|")
    for phase in PHASES:
        diff = Counter((t, r["target_cls"]) for r, t, st in items_all
                       if st["seven", phase][0] == "C" and st["probe", phase][0] != "C")
        for (t, c), n in sorted(diff.items()):
            say(f"| {phase} | {t} | {c}: {'recovered FN' if t == 'CLEAR' else 'added FP'} | {n} |")
    say("\n## The firing turret's own collision on the probe line (settled, truth CLEAR)\n")
    own = Counter(r["macro"] for r, t, _s in items_all if t == "CLEAR" and r["phases"]["settled"]["mesh"]["aim"] == ["W"])
    tot = Counter(r["macro"] for r, t, _s in items_all if t == "CLEAR")
    say("| firing turret | probe first hits its own turret | truth CLEAR rows |")
    say("|---|---:|---:|")
    for m, n in own.most_common():
        say(f"| {m} | {n} | {tot[m]} |")
    say("\n## Truth UNKNOWN because the bearing path reaches no geometry\n")
    say("| target class | target | rows | probe CLEAR | seven CLEAR | first hit past the aim point (MESH) |")
    say("|---|---|---:|---:|---:|---|")
    nog = defaultdict(list)
    for r in rows:
        if truth(r) == "aim path reaches no geometry":
            nog[r["target_cls"], r["target_macro"]].append(r)
    for (c, m), rs in sorted(nog.items()):
        st = [statuses(r, "mesh") for r in rs]
        past = Counter(mech(r, r.get("beyond", {}).get("mesh")) for r in rs)
        say(f"| {c} | {m} | {len(rs)} | {sum(s['probe', 'settled'][0] == 'C' for s in st)} | "
            f"{sum(s['seven', 'settled'][0] == 'C' for s in st)} | {dict(past)} |")
    say("\n## Multi-aim-point targets\n")
    multi = [r for r in rows if r["aim_points"] > 1 and "select_from" in r]
    settled_multi = [r for r in multi if "settled muzzle" in r["select_from"]]
    sens = [r for r in settled_multi if len(set(r["select_from"].values())) > 1]
    say(f"- multi-point tests: {len(multi)} ({len(settled_multi)} settled)")
    say(f"- settled rows where turret origin, parked muzzle and settled muzzle all select the same point: "
        f"{len(settled_multi) - len(sens)}; where the origin matters: {len(sens)}")
    for pair in (("turret origin", "parked muzzle"), ("turret origin", "settled muzzle")):
        say(f"- {pair[0]} vs {pair[1]} differ: {sum(r['select_from'][pair[0]] != r['select_from'][pair[1]] for r in settled_multi)}")
    say("- truth uses the turret origin (native, resolved), so every multi-point row is scored")
    say("\n## Starting state\n")
    starts = defaultdict(dict)
    for r in rows:
        if r["state"] == "SETTLED":
            starts[r["scene"], r["turret"], r["target"]][r["start"]] = (r["yaw"], truth(r))
    split = [v for v in starts.values() if len(v) == 2 and abs(math.remainder(v[0.0][0] - v[math.pi][0], 2 * math.pi)) > 1e-3]
    say(f"- same turret and target, parked vs astern start settle at different yaws: {len(split)} pairs; "
        f"truth differs in {sum(v[0.0][1] != v[math.pi][1] for v in split)}")
    say("- " + ", ".join(f"{k}: {n}" for k, n in Counter(r["state"] for r in rows).most_common()))
    b0 = Counter()
    for r, t, _s in items_all:
        b0["scored rows"] += 1
        b0["barrel 0 +Z path differs from truth"] += bool(_cls(tsym(r), r["shots"]["mesh"])) != (t == "CLEAR")
    say("\n## Diagnostic only: settled barrel-0 +Z projectile path (MESH)\n")
    say("\n".join(f"- {k}: {v}" for k, v in b0.items()))
    say("\n## Simulated check_line_of_sight calls per turret (MESH)\n")
    say("| method | phase | median | p90 | max |")
    say("|---|---|---:|---:|---:|")
    for method in ("current", "seven", "lazy", "eight"):
        for phase in PHASES:
            v = [st[method, phase][2] for _r, _t, st in items_all]
            say(f"| {method} | {phase} | {_q(v, .5)} | {_q(v, .9)} | {max(v, default=0)} |")
    say("\n## #202 anchor, fixture arrangement, parked start: elements where current reads <= 2/14 but >= 7 "
        "turrets are truly CLEAR\n")
    say("| Osaka yaw | element | truth CLEAR / scored | current | seven | probe | current centre-line first hit |")
    say("|---:|---|---:|---:|---:|---:|---|")
    live_like = 0
    for w in witness202(rows):
        n = w["truth"].get("CLEAR", 0) + w["truth"].get("NOT", 0)
        if w["current"] <= 2 and w["truth"].get("CLEAR", 0) >= 7:
            live_like += 1
            say(f"| {w['yaw']} | {w['target'].split(':')[-1]} | {w['truth'].get('CLEAR', 0)} / {n} | "
                f"{w['current']}/14 | {w['seven']}/14 | {w['probe']}/14 | {w['centre_first_hit']} |")
    say(f"\n{live_like} element/orientation pairs show the LIVE #202 pattern.")
    say("\n## Station roots: where the union-box centre is\n")
    for plan in Sc.STATION_PLANS:
        st = station60(plan)
        say(f"- {plan} ({st['modules']} modules): centre {st['centre']}, inside a module: MESH {st['inside']['mesh']}, "
            f"HULL {st['inside']['hull']}; first hit on 200 lines toward it from outside: {st['lines']}")
    bad = integrity(rows, items_all)
    say("\n## Integrity\n")
    say("PASS" if not bad else "FAIL\n" + "\n".join(f"- {b}" for b in bad[:30]))
    return "\n".join(out), bad


def mech_sym(sym):
    return sym or "no hit"


def witness202(rows):
    """Anchor fixture arrangement, parked start: per element and Osaka yaw, CLEAR counts out of 14."""
    groups = defaultdict(list)
    for r in rows:
        if r["population"] == "anchor" and r["view"].startswith("fixture") and r["start"] == 0.0 \
                and r["target_cls"] == "ship surface":
            groups[r["view"].split()[-1], r["target"]].append(r)
    out = []
    for (yaw, target), rs in sorted(groups.items()):
        t = Counter(truth(r) for r in rs)
        ok = [r for r in rs if r["state"] == "SETTLED"]
        c = {m: sum(candidates(r, "mesh")[m, "settled"][0] == "C" for r in ok) for m in ("current", "seven")}
        c["probe"] = sum(aim_probe(r, "settled", "mesh") for r in ok)
        blockers = Counter(mech_sym((r["phases"]["settled"]["mesh"]["c"] or [None])[0]) for r in ok)
        out.append(dict(yaw=yaw, target=target, truth=dict(t), **c, centre_first_hit=dict(blockers)))
    return out


def load_rows():
    with gzip.open(OUT, "rt") as stream:
        return [json.loads(line) for line in stream]


def main():
    if "--report" not in sys.argv:
        check_settling()
        ships, ctx = context()
        check_kinematics(ctx)
        OUT.parent.mkdir(parents=True, exist_ok=True)
        with gzip.open(OUT, "wt") as stream:
            population(ships, ctx, stream)
    text, bad = report(load_rows())
    print(text)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
