"""Issue #202: the stratified physical population for the settled line-of-fire benchmark.

Every selection rule below is fixed before anything is scored and reads only source metadata (aim-point
counts, box sizes, mount positions, turret geometry), never a benchmark result. The #184 machinery is
reused: `aimpoint_map.firing_mounts` for real firing mounts and their corpus turrets, the A7.3 official
firing-ship rows and `a73_loadout` (shortest barrel/broadest arc and longest barrel/narrowest arc per
mount), `targets()` for authored aim points, and the `cases` bearing construction for ordinary and
aim-point-switch (boundary) views. SWI ships are left out: their collision geometry is not installed.

A scene is one firing ship (one loadout variant) and one target host (ship or station), optionally with
one external blocker, all as real collision bodies in one zone. Labels:

    F:hull, F:turret:<mount>, F:shield:<conn>, F:engine:<conn>     firing ship
    H:hull, H:<kind>:<conn>                                         target ship and its elements
    H:module:<i>, H:<kind>:<i>:<conn>                               station modules and their elements (settled._station)
    X:<cls>                                                         external blocker (cls: ship/module/asteroid/small)
"""
from __future__ import annotations

import math
import xml.etree.ElementTree as ET
from collections import defaultdict
from functools import lru_cache
from pathlib import Path

import numpy as np

import geometry as Gm

S = Gm.S
ROOT = Path(__file__).resolve().parents[2]
PLANS = ROOT / ".x4-research-cache/constructionplans/libraries/constructionplans.xml"
KIND = {"turret": "turret", "missileturret": "turret", "shieldgenerator": "shield", "engine": "engine"}
LARGE_TARGET_RADIUS = 500.0   # Ship slot +0x1BF0: runtime box radius > global +0x502C, initialised to 500.0
FIRING_ROWS = ("M1", "L1", "L2", "X1")          # the official A7.3 firing ships
MAX_MOUNTS = 6                 # extreme mounts per axis direction on turret-heavy ships
STATION_PLANS = {"xen_defence": "compact Xenon defence platform (#60 witness)",
                 "arg_tradestation": "sparse trading station: docks and piers on long struts",
                 "arg_shipyard": "large shipyard: build, storage and habitation modules"}
BLOCKERS = {"ship": "ship_arg_l_destroyer_01_a_macro", "module": "struct_arg_base_01_macro",
            "asteroid": "env_ast_ice_l_01_macro", "small": "eq_arg_satellite_01_macro"}
ORDINARY, BOUNDARY = (0, 3), (0, 4)             # A7.3 bearing indices of the `cases` construction
GAPS = {"ordinary": 1500.0, "boundary": 300.0}  # clearance between the two ships' boxes (m)


def frame(t, R):
    return np.asarray(t, float), np.asarray(R, float)


def compose(a, b):
    """Row-vector (t, R): first a, then b."""
    return a[0] @ b[1] + b[0], a[1] @ b[1]


def inverse(a):
    return -a[0] @ a[1].T, a[1].T


def to_world(p, f):
    return np.asarray(p, float) @ f[1] + f[0]


def to_local(p, f):
    return (np.asarray(p, float) - f[0]) @ f[1].T


def ry(deg):
    a = math.radians(deg)
    return np.array([[math.cos(a), 0, -math.sin(a)], [0, 1, 0], [math.sin(a), 0, math.cos(a)]])


# ---------------------------------------------------------------- source helpers

def comp_of(macro):
    return S.macro(macro).find("component").get("ref")


def mating(comp):
    found = [c for c in S.connections(comp).values() if "component" in S.tags(c)]
    return found[0] if len(found) == 1 else None


def attach(child_macro, host_comp, conn):
    """Child component frame -> host component frame at connection `conn` (the #184 `_attach`)."""
    child = S.component(comp_of(child_macro))
    return frame(*S.compose(S._inverse(S.conn_world(child, mating(child))), S.conn_world(host_comp, conn)))


@lru_cache(None)
def body(macro):
    return Gm.body(comp_of(macro))


def integrated(macro):
    m = S.macro(macro)
    while m is not None:
        hull = m.find("properties/hull")
        if hull is not None and hull.get("integrated") is not None:
            return hull.get("integrated").lower() in ("1", "true")
        m = S.macro(m.get("ref")) if m.get("ref") else None
    return False


@lru_cache(None)
def element_macros():
    """{kind: [(macro, required mating tags)]} of official surface-element macros, sorted by name."""
    out = defaultdict(list)
    for name, defs in sorted(S.MACROS.items()):
        m = defs[0][1]
        kind = KIND.get(m.get("class"))
        if kind is None or len(defs) != 1 or m.find("component") is None:
            continue
        try:
            conn = mating(S.component(comp_of(name)))
        except S.StudyError:
            continue
        if conn is not None:
            out[kind].append((name, frozenset(S.tags(conn) - {"component"})))
    return out


def slot_kind(tags):
    return next((k for k in ("turret", "shield", "engine") if k in tags), None)


def compatible(kind, tags):
    return [m for m, need in element_macros()[kind] if need <= tags]


def stated_macro(kind, tags, faction):
    """Stated equipment for one slot (never an observed loadout): a compatible official macro with collision
    geometry, the host's faction first, then by name. Guided and dumb-fire launchers are left to the firing
    loadout, so target siblings are conventional turrets."""
    pool = [m for m in compatible(kind, tags) if body(m) is not None
            and not (kind == "turret" and ("guided" in m or "missile" in m or "torpedo" in m))]
    return min(pool, key=lambda m: (f"_{faction}_" not in m, m), default=None)


FACTIONS = {"arg", "par", "tel", "spl", "ter", "bor", "xen", "kha", "pir", "yak", "atf", "tfm", "gen"}


def faction(name):
    """Faction code in an asset name ('xenon' counts as 'xen'), else ''."""
    return next(({"xenon": "xen"}.get(t, t) for t in name.split("_") if t in FACTIONS or t == "xenon"), "")


def aim_points(macro):
    """Authored aim points in the component frame, in native connection-name hash order (#167/#184)."""
    from barrelposition_evaluator import _native_connection_name_hash
    comp = S.component(comp_of(macro))
    aims = sorted((c for c in S.connections(comp).values() if "aimtarget" in S.tags(c)),
                  key=lambda c: _native_connection_name_hash(c.get("name").lower()))
    return [np.array([float(c.find("offset/position").get(a, 0)) for a in "xyz"]) for c in aims]


def box(macro):
    C, H = S.center_half(macro)
    return np.array(C), np.array(H)


def hull_parts(macro):
    """[(component body, frame in the ship frame)] of a ship: its own component, then every macro child
    with collision geometry (launch tubes, the Xenon mothership's structure, ...), attached as `macro_box`."""
    comp = S.component(comp_of(macro))
    out = [(Gm.body(comp_of(macro)), frame(np.zeros(3), np.eye(3)))]
    for mc in S.macro(macro).findall("connections/connection"):
        child = mc.find("macro")
        if child is None or not child.get("ref"):
            continue
        cm = child.get("ref")
        ccomp = S.component(comp_of(cm))
        at, pc = S.connections(ccomp).get(child.get("connection")), S.connections(comp).get(mc.get("ref"))
        b = body(cm)
        if b is None or at is None or pc is None:
            continue
        f = frame(*S.compose(S._inverse(S.conn_world(ccomp, at)), S.conn_world(comp, pc)))
        out += [(pb, compose(pf, f)) for pb, pf in hull_parts(cm)]
    return [(b, f) for b, f in out if b is not None]


# ---------------------------------------------------------------- scene

class Scene:
    """Real collision bodies of one arrangement. `meta[label]` is the role of every instance."""

    def __init__(self, name):
        self.name, self.instances, self.meta = name, [], {}
        self.turrets, self.targets = [], []

    def add(self, label, b, f, **meta):
        if b is not None:
            self.instances.append((label, b, f))
        self.meta[label] = meta

    def add_ship(self, prefix, macro, pose, choose, role, **extra):
        """Hull parts plus stated equipment. choose(conn, kind, tags) -> macro or None."""
        comp = S.component(comp_of(macro))
        for i, (b, f) in enumerate(hull_parts(macro)):
            self.add(f"{prefix}:hull" + (f":{i}" if i else ""), b, compose(f, pose), group=role, role="hull", **extra)
        elements = []
        for name, conn in sorted(S.connections(comp).items()):
            t = S.tags(conn)
            kind = slot_kind(t)
            if kind is None or "component" in t:
                continue
            m = choose(name, kind, t)
            if m is None:
                continue
            f = compose(attach(m, comp, conn), pose)
            label = f"{prefix}:{kind}:{name}"
            self.add(label, body(m), f, group=role, role=kind, macro=m, conn=name, **extra)
            elements.append(dict(label=label, kind=kind, macro=m, conn=name, frame=f, tags=t))
        return elements


@lru_cache(None)
def plan_entries(plan):
    root = ET.parse(PLANS).getroot()
    p = next(x for x in root.findall("plan") if x.get("id") == plan)
    out = []
    for e in p.findall("entry"):
        pos, rot = e.find("offset/position"), e.find("offset/rotation")
        assert rot is None or not (float(rot.get("pitch", 0)) or float(rot.get("roll", 0))), plan
        out.append((e.get("macro"), np.array([float(pos.get(a, 0)) if pos is not None else 0.0 for a in "xyz"]),
                    float(rot.get("yaw", 0)) if rot is not None else 0.0))
    return tuple(out)


def station_box(modules):
    """The station's live union box (station instance box `+0xC90`): union of module boxes, world frame."""
    lo, hi = [], []
    for m in modules:
        C, H = box(m["macro"])
        corners = np.array([[C[j] + (H[j] if k >> j & 1 else -H[j]) for j in range(3)] for k in range(8)])
        w = to_world(corners, m["frame"])
        lo.append(w.min(0))
        hi.append(w.max(0))
    lo, hi = np.min(lo, 0), np.max(hi, 0)
    return (lo + hi) / 2, (hi - lo) / 2


# ---------------------------------------------------------------- firing population

def turret_category(key, records):
    r = records[key]
    m = r["macro"]
    size = "L" if "_l_" in m else "M"
    ends = sum(1 for _ in _endpoint_names(r))
    beh = {"conventional_gun": "beam" if "beam" in m else "projectile", "dumbfire_missile": "unguided missile",
           "guided_missile": "guided missile"}[r["weapon_behavior"]]
    return dict(size=size, endpoints="multi" if ends > 1 else "single", behavior=beh)


def _endpoint_names(record):
    tag = record["endpoint"]["tag"]
    comp = S.component(record["component"])
    return [n for n, c in S.connections(comp).items() if tag in S.tags(c)]


def physical_loadout(ship_mounts, records):
    """A7.3 `a73_loadout` over the turrets that run the obstruction check: guided missile turrets never do
    (weapon-path-obstruction-groups.md), so they are ranked out and kept only as a GUIDED count."""
    import aimpoint_map as am
    out = []
    for m in ship_mounts:
        keys = [k for k in m["turrets"] if records[k]["weapon_behavior"] != "guided_missile"]
        keys = sorted(keys, key=lambda k: (am.a73_turret_geometry(k, records)[0],
                                           -am.a73_turret_geometry(k, records)[1], k))
        if keys:
            out.append(dict(m, turrets=sorted({keys[0], keys[-1]}, key=keys.index)))
    return out


def _extreme_mounts(ms):
    """Up to MAX_MOUNTS mounts: the extremes of the mount positions along +-x, +-y, +-z, ties by name."""
    if len(ms) <= MAX_MOUNTS:
        return ms
    pos = {m["name"]: m["frames"][m["turrets"][0]][0] for m in ms}
    keep = []
    for axis in range(3):
        for sign in (1, -1):
            best = min(ms, key=lambda m: (-sign * pos[m["name"]][axis], m["name"]))
            if best["name"] not in [k["name"] for k in keep]:
                keep.append(best)
    return keep[:MAX_MOUNTS]


def firing_population():
    """The official A7.3 firing ships, their chosen mounts and loadout variants.
    -> (ships, records): ships = [dict(tag, ship, cls, mounts, variants=[(name, {mount: key})])]."""
    import aimpoint_map as am
    import corpus
    import scorer
    records = scorer.load()
    components = corpus._index_xml([corpus.SWI_XML, corpus.OFFICIAL_SRC], "component")
    mounts, _excluded, _inferred = am.firing_mounts(records, components)
    by = defaultdict(list)
    for m in mounts:
        by[m["ship"]].append(m)
    meta = {s: dict(am.a73_ship_stats(ms), cls=ms[0]["cls"], source=ms[0]["source"]) for s, ms in by.items()}
    ships = []
    for tag, cls, src, metric, direction, why in am.A73_SHIP_RULE:
        if tag not in FIRING_ROWS:
            continue
        pool = sorted(s for s, d in meta.items() if d["cls"] == cls and d["source"] == src)
        sign = -1 if direction == "max" else 1
        ship = min(pool, key=lambda s: (sign * meta[s][metric], s))
        loadout = physical_loadout(by[ship], records)
        chosen = {m["name"] for m in _extreme_mounts(loadout)}
        base = {m["name"]: m["turrets"][0] for m in loadout}
        variants = [("A", base, {n for n in chosen}),
                    ("B", {**base, **{m["name"]: m["turrets"][-1] for m in loadout if m["name"] in chosen}},
                     {m["name"] for m in loadout if m["name"] in chosen and len(m["turrets"]) > 1})]
        ships.append(dict(tag=tag, ship=ship, cls=cls, why=why, mounts={m["name"]: m for m in loadout},
                          all_mounts={m["name"]: m for m in by[ship]}, variants=variants,
                          mount_count=len(loadout), chosen=sorted(chosen)))
    # category completion: every firing behaviour, size and endpoint layout the corpus offers, once
    have = {(k, v) for s in ships for _n, lo, fire in s["variants"] for mt in fire
            for k, v in turret_category(lo[mt], records).items()}
    for key in sorted(k for k in records if k.startswith("official:")):
        cat = turret_category(key, records)
        missing = [(k, v) for k, v in cat.items() if (k, v) not in have]
        if not missing:
            continue
        for s in ships:
            mt = next((n for n in sorted(s["all_mounts"]) if key in s["all_mounts"][n]["turrets"]), None)
            if mt is not None:
                base = s["variants"][0][1]
                s["variants"].append((f"C:{key.split(':')[1]}", {**base, mt: key}, {mt}))
                s["mounts"].setdefault(mt, s["all_mounts"][mt])
                have.update(cat.items())
                break
    return ships, records


# ---------------------------------------------------------------- target population

CENSUS_SKIPPED = {}


def _census():
    """Official ship_s..ship_xl components with a collision body: (component, macro, class, |H|, points)."""
    rows = {}
    for name, defs in sorted(S.MACROS.items()):
        m = defs[0][1]
        if len(defs) != 1 or m.get("class") not in ("ship_s", "ship_m", "ship_l", "ship_xl") or m.find("component") is None:
            continue
        cn = m.find("component").get("ref")
        if cn in rows:
            continue
        try:
            _C, H = box(name)
            parts = hull_parts(name)
        except (S.StudyError, FileNotFoundError, KeyError, AssertionError) as e:
            CENSUS_SKIPPED[cn] = f"{type(e).__name__}: {e}"
            continue
        if parts and parts[0][0] is not None:
            rows[cn] = dict(component=cn, macro=name, cls=m.get("class"), reach=float(np.linalg.norm(H)),
                            points=len(aim_points(name)))
    return list(rows.values())


def whole_ship_targets():
    """Rule: for each authored aim-point count, the smallest and largest ship by |H| whose own hull has a
    collision body; for no aim point also the median and the smallest above the large-target radius."""
    by = defaultdict(list)
    for r in _census():
        by[r["points"]].append(r)
    out = []
    for k in sorted(by):
        g = sorted(by[k], key=lambda r: (r["reach"], r["component"]))
        idx = [0, len(g) - 1]
        if k == 0:
            big = next(i for i, r in enumerate(g) if r["reach"] > LARGE_TARGET_RADIUS)
            idx = [0, len(g) // 2, big, len(g) - 1]
        for i in dict.fromkeys(idx):
            out.append(dict(g[i], why=f"{k} aim points: " + {0: "smallest", len(g) - 1: "largest",
                                                              len(g) // 2: "median"}.get(i, "smallest above 500 m")))
    return out


def element_targets(elements):
    """Rule: per kind present, the smallest and largest selectable element by |H| (ties by connection name).
    Selectable: collision body, not hull-integrated."""
    out = []
    by = defaultdict(list)
    for e in elements:
        if body(e["macro"]) is not None and not integrated(e["macro"]) and "unhittable" not in e["tags"]:
            by[e["kind"]].append(e)
    for kind in ("turret", "shield", "engine"):
        g = sorted(by[kind], key=lambda e: (float(np.linalg.norm(box(e["macro"])[1])), e["conn"]))
        for i in dict.fromkeys([0, len(g) - 1] if g else []):
            out.append(g[i])
    return out


def views(multi_pair=None):
    """[(group, bearing index, direction, target rotation)] for a target: two ordinary bearings of the #184
    `cases` construction and, for a multi-aim-point target, two bearings in the perpendicular bisector
    plane of its nearest authored pair (pair given as (midpoint, u, v) in the target frame)."""
    import study
    dirs = study.fibonacci(8)
    out = [("ordinary", i, np.asarray(dirs[i]), np.asarray(study.ROT[i % 24])) for i in ORDINARY]
    if multi_pair is not None:
        _M, u, v = multi_pair
        for k in BOUNDARY:
            rot = np.asarray(study.ROT[k % 24])
            th = 2 * math.pi * k / 8
            out.append(("boundary", k, (u * math.cos(th) + v * math.sin(th)) @ rot, rot))
    return out


def nearest_pair(points):
    """(midpoint, u, v) of the nearest authored pair, as `study.pair_frame`."""
    import study
    pairs = [(a, b) for a in range(len(points)) for b in range(a + 1, len(points))]
    a, b = min(pairs, key=lambda ab: float(np.linalg.norm(points[ab[0]] - points[ab[1]])))
    M, _n, u, v = study.pair_frame(dict(points=[tuple(map(float, p)) for p in points]), a, b)
    return np.asarray(M), np.asarray(u), np.asarray(v)
