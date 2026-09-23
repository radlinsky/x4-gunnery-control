"""Issue #186 L6: research-only LINE OF FIRE benchmark over small constructed scenes.

Offline decision-logic evidence only. Each scene holds explicit bodies (oriented boxes and spheres), a component
hierarchy, ownership, zones and known presence states. Real #184 targets supply runtime boxes, authored aim points and
host attachment; the frozen #184 A7.3 search recovers the aim point once per target view; #185's C2 row builder
supplies the firing origins. Truth comes from the accepted native L3/L4 rules applied to the scene's own
closest hits; the candidate is the accepted MD method (three same-segment `check_line_of_sight` queries and
X4's conditional second ray), simulated as boolean-only calls. Simplified shapes do not reproduce X4 collision
meshes or establish that a constructed hit arrangement is physically attainable in X4.

    python3 research/issue186-line-of-fire/benchmark.py
"""
from __future__ import annotations

import gzip
import importlib.util
import json
import sys
import time
from collections import Counter
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / ".x4-research-cache/issue186-line-of-fire/cases.jsonl.gz"
sys.path.insert(0, str(ROOT / "research/issue184"))
import aimpoint_map as am  # noqa: E402  (also puts #176 scorer and #167 sources/study on the path)

_spec = importlib.util.spec_from_file_location("c2", ROOT / "research/issue185-c2/benchmark.py")
c2 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(c2)
scorer, sources, study = am.scorer, am.sources, am.study

EPS = 1e-6               # m: numerical tolerance for synthetic intersection checks
D = 1000.0               # m: standard firing-origin-to-target setup distance
LARGE = 500.0            # m: X4's target-size controller split (runtime box radius)
CONV, GUIDED, UNGUIDED, CLUSTER = ("CONVENTIONAL_STRAIGHT_PATH", "GUIDED_MISSILE",
                                   "UNGUIDED_DIRECT_MISSILE", "DISTRIBUTING_CLUSTER_MISSILE")
CLEAR, BLOCKED, UNKNOWN = "clear", "LINE OF FIRE BLOCKED", "UNKNOWN"
L2_OFFICIAL_AMMO = {GUIDED: 15, UNGUIDED: 8, CLUSTER: 2}
FALLBACK = "current weapon.barrelposition fallback"
PREDICTED = "geometry-predicted aimed muzzle"


# ---------------------------------------------------------------- L2 weapon behavior (source, not names)

def _missile_turret_tags():
    return [set(sources.macro(n).find("properties/ammunition").get("tags").split())
            for n, defs in sources.MACROS.items() if defs[0][1].get("class") == "missileturret"]


def ammo_group(turret, ammo, records):
    """(group, UNKNOWN reason). Conventional turrets come from the audited #176 corpus; missiles from the loaded
    ammunition macro's own authored guidance/distribution."""
    record = records.get(turret)
    if record is not None and record["weapon_behavior"] == "conventional_gun":
        return CONV, None
    if ammo is None:
        return None, "no loaded ammunition"
    try:
        props = sources.macro(ammo).find("properties/missile")
    except sources.StudyError:
        return None, "unaudited modded ammunition"
    if props is None or props.get("guided") not in ("0", "1"):
        return None, "missing guidance"
    if props.get("guided") == "1":
        return GUIDED, None
    return (CLUSTER if props.get("distribute") == "1" else UNGUIDED), None


def official_ammo_census():
    """Compatible official turret ammunition by group; must match the accepted L2 counts."""
    turret_tags = _missile_turret_tags()
    out, unknown = Counter(), []
    for name, defs in sorted(sources.MACROS.items()):
        m = defs[0][1]
        missile = m.find("properties/missile")
        if m.get("class") != "missile" or missile is None:
            continue
        tags = set((missile.get("tags") or "").split())
        if tags and any(tags <= t for t in turret_tags):
            group, reason = ammo_group(None, name, {})
            if group is None:
                unknown.append((name, reason))
            else:
                out[group] += 1
    spans = [t for t in turret_tags if {"guided", "dumbfire"} <= t]
    return out, unknown, spans


# ---------------------------------------------------------------- scene geometry

def _basis(v):
    v = np.asarray(v, float) / np.linalg.norm(v)
    a = np.cross(v, (0.0, 0.0, 1.0) if abs(v[2]) < 0.9 else (1.0, 0.0, 0.0))
    a /= np.linalg.norm(a)
    return np.array([v, a, np.cross(v, a)])


def _turn(local, world):
    """Rotation R (row convention, world = local @ R) sending unit `local` to unit `world`."""
    return _basis(local).T @ _basis(world)


def _enter(body, a, b, m):
    """Entry fraction of segment a->b into `body` grown by margin m (negative shrinks), or None."""
    d = b - a
    if body["shape"] == "sphere":
        rad = body["size"] + m
        if rad <= 0:
            return None
        f = a - body["c"]
        qa, qb, qc = d @ d, 2 * f @ d, f @ f - rad * rad
        if qc <= 0:
            return 0.0
        disc = qb * qb - 4 * qa * qc
        t = None if disc < 0 else (-qb - np.sqrt(disc)) / (2 * qa)
        return t if t is not None and 0 <= t <= 1 else None
    h = np.asarray(body["size"]) + m
    if np.any(h <= 0):
        return None
    o, dl = (a - body["c"]) @ body["R"].T, d @ body["R"].T
    lo, hi = 0.0, 1.0
    for k in range(3):
        if abs(dl[k]) < 1e-15:
            if abs(o[k]) > h[k]:
                return None
            continue
        t1, t2 = sorted(((-h[k] - o[k]) / dl[k], (h[k] - o[k]) / dl[k]))
        lo, hi = max(lo, t1), min(hi, t2)
        if lo > hi:
            return None
    return lo


def first_hits(scene, a, b, r):
    """(possible closest-hit components, whether a miss is possible) with every body boundary uncertain by r.
    Only present/unknown-presence layer-3 bodies in the querying zone's physics world are candidates."""
    cand = []
    for body in scene["bodies"]:
        if body["presence"] == "absent" or scene["comp"][body["comp"]]["zone"] != scene["weapon_zone"]:
            continue
        lo = _enter(body, a, b, r)
        if lo is not None:
            hi = _enter(body, a, b, -r) if body["presence"] == "present" else None
            cand.append((lo, hi, body))
    sure = min((hi for _lo, hi, _b in cand if hi is not None), default=None)
    return [bd for lo, _hi, bd in cand if sure is None or lo <= sure], sure is None


def chain(scene, c):
    while c is not None:
        yield c
        c = scene["comp"][c]["parent"]


def containing(scene, c):
    """Native class-`object` containing object: the nearest inclusive ancestor of class object."""
    return next(x for x in chain(scene, c) if scene["comp"][x]["object_class"])


# ---------------------------------------------------------------- truth: accepted native rules on the scene

def truth(scene, origin, P, T, group, reason, r):
    """(result, first-hit class, UNKNOWN reason). Uses closest hits and the native containment walk only."""
    if group is None:
        return UNKNOWN, "weapon", reason
    if group == GUIDED:
        return CLEAR, "guided bypass", None
    if scene["comp"][T]["zone"] != scene["weapon_zone"]:
        return UNKNOWN, "cross-zone", "cross-zone target physics world"

    def classify(radius):
        out = set()
        hits, miss = first_hits(scene, origin, P, radius)
        if miss:
            out.add((CLEAR, "genuine miss"))
        for body in hits:
            h = body["comp"]
            if T in chain(scene, h):
                out.add((CLEAR, "selected target"))
            elif containing(scene, h) == containing(scene, T):
                hits2, miss2 = first_hits(scene, origin, scene["comp"][T]["pos"], EPS)
                ok = {bd["comp"] == T for bd in hits2} | ({False} if miss2 else set())
                out |= {(CLEAR if k else BLOCKED, "same object, second ray " + ("clears" if k else "blocks"))
                        for k in ok}
            else:
                out.add((BLOCKED, "unrelated"))
        return out

    outcomes = classify(max(r, EPS))
    if len({o[0] for o in outcomes}) == 1:
        result = next(iter(outcomes))[0]
        cls = {o[1] for o in outcomes}
        return result, cls.pop() if len(cls) == 1 else "ambiguous class, same result", None
    if len({o[0] for o in classify(EPS)}) == 1:
        why = "aim-point uncertainty"
    elif any(b["presence"] == "unknown" for b in first_hits(scene, origin, P, EPS)[0]):
        why = "unestablished wreck/presence state"
    else:
        why = "near-coincident hits"
    return UNKNOWN, "ambiguous", why


# ---------------------------------------------------------------- candidate: accepted L4 MD method

def los(scene, log, origin, P, declared, second=False):
    """Simulated `check_line_of_sight` (useaimtarget=false, excludeself=false): the world endpoint is expressed
    in the declared target's frame and transformed back, then True iff the closest hit is `declared` or a
    descendant. The constructed scene has one known body-presence state and a deterministic hit order."""
    c = scene["comp"][declared]
    offset = (P - c["pos"]) @ c["R"].T
    end = c["pos"] + offset @ c["R"]
    log.append(dict(declared=declared, start=origin.tolist(), end=end.tolist(), second=second))
    hits = [(t, i, b) for i, b in enumerate(scene["bodies"])
            if b["presence"] == "present"
            if scene["comp"][b["comp"]]["zone"] == scene["weapon_zone"]
            if (t := _enter(b, origin, end, 0.0)) is not None]
    if not hits:
        return False
    first = min(t for t, _i, _b in hits)
    tied = sorted((i, b) for t, i, b in hits if t - first <= EPS)
    return declared in chain(scene, tied[0][1]["comp"])


def candidate(scene, origin, P, T, group, reason):
    """(result, implied first-hit class, UNKNOWN reason, query log). Needs no current/soft/engaged target."""
    log = []
    if group is None:
        return UNKNOWN, "weapon", reason, log
    if group == GUIDED:
        return CLEAR, "guided bypass", None, log
    if scene["comp"][T]["zone"] != scene["weapon_zone"]:
        return UNKNOWN, "cross-zone", "cross-zone target physics world", log
    if los(scene, log, origin, P, T):
        return CLEAR, "selected target", None, log
    if los(scene, log, origin, P, scene["comp"][T]["object"]):
        if los(scene, log, origin, scene["comp"][T]["pos"], T, second=True):
            return CLEAR, "same object, second ray clears", None, log
        return BLOCKED, "same object, second ray blocks", None, log
    if los(scene, log, origin, P, scene["weapon_zone"]):
        return BLOCKED, "unrelated", None, log
    return CLEAR, "genuine miss", None, log


# ---------------------------------------------------------------- real targets, #184 recovery, #185 origins

class Data:
    def __init__(self):
        self.records = scorer.load()
        ts = am.targets()
        self.targets = {t["component"]: t for t in ts}
        self.hosts = am.official_hosts()
        self.census = {}
        for game in ("vanilla", "swi"):
            for line in open(ROOT / f".x4-research-cache/issue184/a44_census_{game}.jsonl"):
                row = json.loads(line)
                self.census[game, row["component"]] = row
        self.views = {}

    def whole(self, game, name):
        """Whole-ship target from the #184 targets() population, else from the A4.4 census of that game."""
        t = self.targets.get(name) if game == "official" else None
        if t is None:
            row = self.census["vanilla" if game == "official" else "swi", name]
            t = dict(component=name, points=row["points"], C=row["C"], H=row["H"], kind="whole", R=np.eye(3),
                     cls=row["ship_class"][0], population="A4.4 census " + game)
        else:
            t = dict(t, cls=sources.component(name).get("class"), population="#184 targets()")
        return t

    def mount(self, name, host_prefix):
        """(host component name, host class, (t, R) surface frame in host frame) for a real compatible host."""
        comp = sources.component(name)
        mating = [c for c in sources.connections(comp).values() if "component" in sources.tags(c)][0]
        need = sources.tags(mating) - {"component"}
        tags, host, conn = next(h for h in self.hosts if need <= h[0] and h[1].get("class").startswith(host_prefix))
        t, R = am._attach(comp, mating, host, conn)
        return host.get("name"), host.get("class"), (np.asarray(t, float), np.asarray(R, float))

    def recover(self, key, t, T, query):
        """One frozen #184 A7.3 search per target view (target frame, origin at target origin, rotation T),
        then the accepted `nearest` answer from `query`. The complete record is kept unchanged."""
        if key not in self.views:
            case = dict(points=[np.asarray(p, float) @ T for p in t["points"]], box=(t["C"], t["H"], T),
                        ship_class=None, ship_box=None, position=None, rotation=None)
            st = am.near_only_run(am.view(case), total=am.A73_TOTAL, pad=am.A6_NEAR_PAD, geom=am.A73_GEOM)
            pts = [(np.asarray(x, float), r) for x, r in st["points"]]
            rpts, _n, _skipped = am.refine_points(pts, st["rays"])
            self.views[key] = (case, st, rpts)
        case, st, rpts = self.views[key]
        label = am.nearest([(i, c, r) for i, (c, r) in enumerate(rpts)], query)
        if label is am.UNKNOWN:
            raise AssertionError(f"#184 answer UNKNOWN for {key}")
        truth_pts = case["points"] or [np.asarray(t["C"], float) @ T]
        j = study.select(tuple(map(float, query)), [tuple(map(float, p)) for p in truth_pts])
        centre, radius = rpts[label]
        if np.linalg.norm(centre - truth_pts[j]) > radius:
            raise AssertionError(f"#184 recovered point misses its hidden truth for {key}")
        return dict(view=key, label=int(label), centre=[float(x) for x in centre], radius=float(radius),
                    samples=st["asks"], end=st["end"], points=[[list(map(float, c)), float(r)] for c, r in rpts],
                    authored=len(t["points"]), hidden_truth=[float(x) for x in truth_pts[j]])


def handoff(turret, record, O, R, P, case_id):
    """#185 C2 row for the recovered centre (turret-local), with origins mapped back to world."""
    row = c2._score(turret, record, case_id, "normal supported", tuple(map(float, (P - O) @ R.T)))
    return row, [dict(index=i, source=PREDICTED, position=(O + np.asarray(m) @ R).tolist())
                 for i, m in enumerate(row["predicted_muzzle_positions"])]


# ---------------------------------------------------------------- scene construction

UP = (0.0, 1.0, 0.5)     # target-frame approach from the surface's outward (+Y) side
LOOKS = ((0, 1, 1), (0, 1, 0.4), (0.5, 1, 1), (-0.5, 1, 1), (0, 1, 2))   # turret-local directions to try


class Scene:
    """One constructed scene: zone, firing ship + turret, one selected target, #184 point, #185 origins."""

    def __init__(self, data, cid, target, turret="official:turret_arg_l_laser_01_mk1_macro", ammo=None,
                 view=0, dist=D, host=None, station=None, look=None, source="official", approach=None):
        self.data, self.id, self.source = data, cid, source
        zR = np.asarray(study.ROT[(view * 7 + 5) % 24], float)
        self.s = dict(comp={}, bodies=[], weapon_zone="zone")
        self.add("zone", None, True, np.array([3.0e4, -2.0e3, 5.0e3]), zR, owner=None, zone="zone")
        tR = np.asarray(study.ROT[view % 24], float)
        X = np.array([1.2e4, 800.0, -4.5e3]) + 50.0 * view
        name = target["component"]
        if station is not None:                  # synthetic module offsets and union box, box-centre aim point
            self.add("station", "zone", True, X, tR, owner="player")
            lo = hi = None
            for i, (mname, off) in enumerate(station):
                c, h = map(np.asarray, sources.center_half(mname))
                mid = f"module{i + 1}:{mname}"
                self.add(mid, "station", True, X + np.asarray(off) @ tR, tR, owner="player")
                self.box(mid, X + (np.asarray(off) + c) @ tR, tR, h)
                lo = c - h + off if lo is None else np.minimum(lo, c - h + off)
                hi = c + h + off if hi is None else np.maximum(hi, c + h + off)
            target = dict(target, C=((lo + hi) / 2).tolist(), H=((hi - lo) / 2).tolist(), points=[])
            self.T, TR = "station", tR
        elif host is not None:                   # surface element on a real host (ship or station module)
            hname, hcls, (ht, hR) = host
            if hcls.startswith("ship"):
                self.add(hname, "zone", True, X, tR, owner="enemy")
            else:
                self.add("station", "zone", True, X - np.array([0, 0, 400.0]) @ tR, tR, owner="enemy")
                self.add(hname, "station", True, X, tR, owner="enemy")
            TR = hR @ tR
            self.add(name, hname, False, X + ht @ tR, TR, owner="enemy", public=hname)
            self.box(name, X + ht @ tR + np.asarray(target["C"]) @ TR, TR, target["H"])
            self.T = name
        else:                                    # whole ship: runtime box used as an abstract hit shape
            self.add(name, "zone", True, X, tR, owner="enemy")
            self.box(name, X + np.asarray(target["C"]) @ tR, tR, target["H"])
            self.T, TR = name, tR
        self.target, self.TR = target, TR
        pos = self.s["comp"][self.T]["pos"]
        centre = pos + np.asarray(target["C"]) @ TR
        w = np.asarray(study.fibonacci(8)[view % 8], float) if approach is None else \
            -_basis(np.asarray(approach, float) @ TR)[0]      # O on the target-frame `approach` side
        radius = float(np.linalg.norm(target["H"]))
        dist = max(dist, radius + 100.0)          # origin stays outside the synthetic target box
        O = centre - dist * w
        rec = data.recover((name, view, host and host[0], station is not None), target, TR, O - pos)
        self.record = rec
        self.P = pos + np.asarray(rec["centre"])
        self.large = radius >= LARGE
        self.turret, self.ammo = turret, ammo
        record = data.records.get(turret)
        self.add("firing_ship", "zone", True, O - 30.0 * w, np.eye(3), owner="player")
        self.add("turret", "firing_ship", False, O, np.eye(3), owner="player")
        self.no_origin = None
        if record is None:                        # unknown/future turret: #185 fallback origin, no geometry
            self.row = dict(result="CAN AIM", predicted_muzzle_positions=[])
            self.origins = [dict(index=0, source=FALLBACK, position=(O + np.array([0.0, 2.5, 0.0])).tolist())]
            return
        for local in ((look,) if look is not None else LOOKS):
            R = _turn(local, self.P - O)
            self.row, self.origins = handoff(turret, record, O, R, self.P, self.id)
            if self.origins or look is not None:
                break
        assert self.origins or look is not None, f"{cid}: no CAN AIM turret orientation"

    def add(self, cid, parent, obj, pos, R, owner, zone="zone", public=None):
        self.s["comp"][cid] = dict(parent=parent, object_class=obj, zone=zone, pos=np.asarray(pos, float),
                                   R=np.asarray(R, float), owner=owner, object=public or cid)

    def box(self, comp, c, R, h, presence="present", label=None):
        self.s["bodies"].append(dict(comp=comp, shape="box", c=np.asarray(c, float), R=np.asarray(R, float),
                                     size=np.asarray(h, float), presence=presence, label=label))

    def ball(self, comp, c, rad, presence="present", label=None):
        self.s["bodies"].append(dict(comp=comp, shape="sphere", c=np.asarray(c, float), size=float(rad),
                                     presence=presence, label=label))

    def along(self, s, lateral=(0.0, 0.0, 0.0), origin=0):
        """World point at fraction s of the segment from supplied origin `origin` to the aim point."""
        o = np.asarray(self.origins[origin]["position"])
        return o + s * (self.P - o) + np.asarray(lateral)

    def both(self, s):
        """Midpoint, at fraction s, between the first ray and X4's second ray to the component origin."""
        o = np.asarray(self.origins[0]["position"])
        return (self.along(s) + o + s * (self.s["comp"][self.T]["pos"] - o)) / 2

    def blocker(self, kind, s, rad=5.0, owner="enemy", parent="zone", presence="present", box=None, **kw):
        cid = f"{kind}@{s:g}" + ("" if presence == "present" else f":{presence}")
        if cid not in self.s["comp"]:
            self.add(cid, parent, parent == "zone" or kind.startswith("station"), self.along(s, **kw),
                     np.eye(3), owner=owner)
        if box is None:
            self.ball(cid, self.along(s, **kw), rad, presence, kind)
        else:
            self.box(cid, self.along(s, **kw), np.eye(3), box, presence, kind)
        return cid


# ---------------------------------------------------------------- cases

def cases(data):
    """Yield (scene, labels). Labels name what the case covers; truth never reads them."""
    X = lambda n: data.whole("official", n)  # noqa: E731
    tur = data.targets
    ship_l = data.mount("turret_par_m_plasma_02_mk1", "ship")
    mod = data.mount("turret_par_m_plasma_02_mk1", "defence")
    shield = data.mount("shield_arg_l_standard_01_mk1", "ship")
    engine = data.mount("engine_arg_l_allround_01_mk1", "ship")
    st_mod = "defence_arg_disc_01_macro"
    station = ((st_mod, (-420.0, 0.0, 0.0)), ("storage_arg_l_container_01_macro", (700.0, 0.0, 0.0)))
    dumb, guided = "official:turret_arg_m_dumbfire_01_mk1_macro", "official:turret_arg_m_guided_01_mk1_macro"

    def S(cid, target, **kw):
        return Scene(data, cid, target, **kw)

    # whole ships XS/S/M/L/XL, small and large, clear via the selected target
    for i, (n, game) in enumerate((("ship_ter_xs_pv_01_a", "official"), ("ship_pir_s_fighter_01", "official"),
                                   ("ship_xen_m_fighter_01", "official"), ("ship_arg_l_destroyer_01", "official"),
                                   ("ship_ter_xl_carrier_01", "official"), ("arrestor_cruiser", "swi"))):
        t = data.whole(game, n)
        turret = "swi:turret_cis_dual_heavyturbo_macro" if game == "swi" else \
            "official:turret_arg_l_laser_01_mk1_macro"
        yield S(f"whole-{n}", t, view=i, turret=turret, source=game), dict(order="target only")
    # translated/rotated whole ship with every blocker class in front of it
    blockers = (("own hull", dict(parent="firing_ship", owner="player", s=0.01, rad=8.0)),
                ("player ship", dict(owner="player", s=0.4, box=(20.0, 8.0, 30.0))),
                ("enemy ship", dict(s=0.4, box=(20.0, 8.0, 30.0))),
                ("asteroid", dict(owner=None, s=0.5, rad=60.0)),
                ("player station", dict(owner="player", s=0.5, box=(150.0, 150.0, 150.0))),
                ("enemy station", dict(s=0.5, box=(150.0, 150.0, 150.0))),
                ("missile/explosive", dict(s=0.2, rad=1.0)),
                ("gate", dict(owner=None, s=0.6, box=(300.0, 300.0, 20.0))),
                ("mine (representative small object)", dict(s=0.3, rad=2.0)),
                ("fresh ship wreck", dict(s=0.4, box=(20.0, 8.0, 30.0))),
                ("persistent wreck", dict(s=0.4, box=(20.0, 8.0, 30.0))),
                ("restored wreck", dict(s=0.4, box=(20.0, 8.0, 30.0))),
                ("wrecked station", dict(s=0.5, box=(150.0, 150.0, 150.0))),
                ("destroyed without wreck", dict(s=0.4, box=(20.0, 8.0, 30.0), presence="absent")),
                ("wreck killed again", dict(s=0.4, box=(20.0, 8.0, 30.0), presence="absent")),
                ("wreck timed out", dict(s=0.4, box=(20.0, 8.0, 30.0), presence="absent")))
    for kind, kw in blockers:
        sc = S(f"blocker-{kind}#M", X("ship_xen_m_fighter_01"), view=9)
        sc.blocker(kind, **kw)
        yield sc, dict(blocker=kind, order="blocker before target")
    for kind, s in (("station module", 0.5), ("station-module wreck", 0.5)):
        sc = S(f"blocker-{kind}#M", X("ship_xen_m_fighter_01"), view=9)
        sc.add("other station", "zone", True, sc.along(s), np.eye(3), owner="enemy")
        sc.blocker(kind, s, parent="other station", box=(120.0, 120.0, 120.0))
        yield sc, dict(blocker=kind, order="blocker before target")
    # every supported weapon group on one blocked scene; guided uses zero queries
    for turret, ammo, label in ((dumb, "missile_dumbfire_light_mk1_macro", "unguided"),
                                (dumb, "missile_cluster_light_mk1_macro", "cluster (same turret, ammo switch)"),
                                (guided, "missile_guided_light_mk1_macro", "guided"),
                                (dumb, "missile_story_dumbfire_light_mk2_macro", "missing guidance"),
                                (dumb, None, "no loaded ammunition"),
                                ("mod:turret_future_mk1_macro", "mod_unaudited_bullet_macro", "unaudited mod")):
        sc = S(f"group-{label}#M", X("ship_xen_m_fighter_01"), view=9, turret=turret, ammo=ammo)
        sc.blocker("enemy ship", 0.4, box=(20.0, 8.0, 30.0))
        yield sc, dict(blocker="enemy ship", order="blocker before target", weapon=label)
    for turret, ammo, label in ((dumb, "missile_dumbfire_light_mk1_macro", "unguided"),
                                (dumb, "missile_cluster_light_mk1_macro", "cluster"),
                                (guided, "missile_guided_light_mk1_macro", "guided")):
        sc = S(f"group-own-hull-{label}#M", X("ship_xen_m_fighter_01"), view=9, turret=turret, ammo=ammo)
        sc.blocker("own hull", 0.01, rad=8.0, parent="firing_ship", owner="player")
        yield sc, dict(blocker="own hull", order="blocker before target", weapon=label)
    # first-hit ordering
    sc = S("order-behind-target#XL", X("ship_ter_xl_carrier_01"), view=4)
    sc.blocker("enemy ship", 0.999, rad=0.5)
    yield sc, dict(blocker="enemy ship", order="unrelated behind selected target")
    sc = S("order-two-unrelated#M", X("ship_xen_m_fighter_01"), view=9)
    sc.blocker("asteroid", 0.3, rad=40.0, owner=None)
    sc.blocker("enemy ship", 0.6, box=(20.0, 8.0, 30.0))
    yield sc, dict(blocker="asteroid+enemy ship", order="two unrelated, closest decides")
    sc = S("order-absent-then-ship#M", X("ship_xen_m_fighter_01"), view=9)
    sc.blocker("wreck timed out", 0.3, box=(20.0, 8.0, 30.0), presence="absent")
    sc.blocker("enemy ship", 0.6, box=(20.0, 8.0, 30.0))
    yield sc, dict(blocker="absent wreck+enemy ship", order="removed body, later body blocks")
    sc = S("order-own-hull-first#M", X("ship_xen_m_fighter_01"), view=9)
    sc.blocker("own hull", 0.01, rad=8.0, parent="firing_ship", owner="player")
    sc.blocker("enemy ship", 0.5, box=(20.0, 8.0, 30.0))
    yield sc, dict(blocker="own hull+enemy ship", order="own hull before external")
    sc = S("order-external-first#M", X("ship_xen_m_fighter_01"), view=9)
    sc.blocker("missile/explosive", 0.002, rad=0.5)
    sc.blocker("own hull", 0.02, rad=8.0, parent="firing_ship", owner="player")
    yield sc, dict(blocker="missile+own hull", order="external before own hull")
    sc = S("order-target-first#XL", X("ship_ter_xl_carrier_01"), view=4)
    sc.blocker("enemy ship", 0.9995, rad=0.3)
    yield sc, dict(blocker="enemy ship", order="selected target before unrelated")
    # same-containing-object: ship and station surfaces, second ray clears/blocks
    for label, host, t, up in (("ship turret", ship_l, tur["turret_par_m_plasma_02_mk1"], UP),
                               ("ship shield", shield, tur["shield_arg_l_standard_01_mk1"], UP),
                               ("ship engine", engine, tur["engine_arg_l_allround_01_mk1"], (0, 1, -0.5)),
                               ("station-module turret", mod, tur["turret_par_m_plasma_02_mk1"], UP)):
        for want in ("clears", "blocks"):   # engine origin sits on its box's +Z face: approach from -Z
            sc = S(f"same-{label}-{want}#{label}", t, view=11, host=host, approach=up)
            s = 1 - 60.0 / np.linalg.norm(sc.P - sc.origins[0]["position"])
            if want == "clears":
                sc.ball(host[0], sc.along(s), 0.05, label="host part")
            else:
                sc.ball(host[0], sc.both(s), np.linalg.norm(sc.both(s) - sc.along(s)) + 1.0, label="host part")
            yield sc, dict(order=f"same object, second ray {want}", surface=label, blocker="host part")
        sc = S(f"surface-{label}-clear#{label}", t, view=11, host=host, approach=up)
        yield sc, dict(order="target only", surface=label)
    sc = S("order-same-before-external#ship turret", tur["turret_par_m_plasma_02_mk1"], view=11, host=ship_l,
           approach=UP)
    sc.ball(ship_l[0], sc.along(1 - 60.0 / D), 0.05, label="host part")
    sc.blocker("enemy ship", 1 - 30.0 / D, rad=0.05)
    yield sc, dict(order="same object before external", blocker="host part+enemy ship", surface="ship turret")
    sc = S("order-target-before-same#station-module shield", tur["shield_arg_l_standard_01_mk1"], view=11,
           host=data.mount("shield_arg_l_standard_01_mk1", "defence"), approach=UP)
    sc.ball(sc.s["comp"][sc.T]["parent"], sc.along(1.0 - 1.0 / D), 0.3, label="host part")
    yield sc, dict(order="selected target before same object", blocker="host part", surface="station-module shield")
    sc = S("sibling-module#station-module turret", tur["turret_par_m_plasma_02_mk1"], view=11, host=mod,
           approach=UP)
    sc.add("module2", "station", True, sc.along(0.98), np.eye(3), owner="enemy")
    sc.ball("module2", sc.along(0.98), 0.05, label="station module")
    yield sc, dict(order="sibling module (unrelated to surface module)", blocker="station module",
                   surface="station-module turret")
    # whole station, large genuine miss through the module gap; small genuine miss off-box aim point
    sc = S("station-whole-miss#station", dict(component="station"), view=2, station=station, approach=(0, 0, 1))
    yield sc, dict(order="genuine miss")
    sc = S("station-whole-hit#station", dict(component="station"), view=2, station=station, approach=(0, 0, 1))
    sc.ball("module1:" + st_mod, sc.along(0.95), 5.0, label="own module")
    yield sc, dict(order="descendant module hit")
    t = tur["turret_par_m_plasma_02_mk1"]
    for label, extra in (("miss", None), ("beyond-endpoint", 1.02), ("uncertainty", "ball")):
        sc = S(f"off-box-{label}#offbox", t, view=5, host=ship_l, approach=UP)
        if extra == 1.02:
            sc.blocker("mine (representative small object)", 1.0 + 0.3 / D, rad=0.1)
        elif extra == "ball":
            r = sc.record["radius"]
            sc.blocker("mine (representative small object)", 0.999, rad=0.2, lateral=_side(sc) * (0.2 + r / 2))
        yield sc, dict(order="genuine miss" if extra is None else f"off-box {label}", surface="ship turret",
                       blocker=None if extra is None else "mine (representative small object)")
    # cross-zone target stays UNKNOWN
    sc = S("cross-zone#M", X("ship_xen_m_fighter_01"), view=9)
    sc.s["comp"][sc.T]["zone"] = "zone2"
    yield sc, dict(order="cross-zone")
    # #185 handoff: multi-origin (100 m: the only distance with a known multi-stable case), fallback, none
    rec = data.records["official:turret_bor_l_disruptor_01_mk1_macro"]
    leaf, _root, _seg = scorer.segments(rec)
    local = np.asarray(c2._limit_point(rec, "leaf", leaf["limits"][1] - c2.LIMIT_OFFSET_DEGREES, 100.0))
    sc = S("multi-origin#M", X("ship_xen_m_fighter_01"), view=9, turret="official:turret_bor_l_disruptor_01_mk1_macro",
           dist=100.0, look=tuple(local))
    O = sc.s["comp"]["turret"]["pos"]
    R = _turn(tuple(local), sc.P - O)
    O2 = sc.P - np.asarray(local) @ R        # the same recovered point, reached along the multi-stable bearing
    sc.s["comp"]["turret"]["pos"] = O2
    sc.row, sc.origins = handoff(sc.turret, rec, O2, R, sc.P, sc.id)
    sc.blocker("mine (representative small object)", 0.02, rad=0.3, origin=0)
    yield sc, dict(order="multi-origin", blocker="mine (representative small object)")
    sc = S("fallback-origin#M", X("ship_xen_m_fighter_01"), view=9, turret="mod:turret_future_mk1_macro",
           ammo="missile_dumbfire_light_mk1_macro")
    sc.blocker("enemy ship", 0.4, box=(20.0, 8.0, 30.0))
    yield sc, dict(order="blocker before target", blocker="enemy ship", weapon="unknown turret fallback origin")
    sc = S("cannot-bear#M", X("ship_xen_m_fighter_01"), view=9, look=(0, -1, 0))
    assert sc.row["result"] == "CANNOT BEAR" and not sc.origins
    yield sc, dict(order="no origin (CANNOT BEAR)")
    sc = S("c185-unknown#M", X("ship_xen_m_fighter_01"), view=9)
    sc.row, sc.origins = dict(sc.row, result="UNKNOWN", predicted_muzzle_positions=[]), []
    yield sc, dict(order="no origin (#185 UNKNOWN)")


def _side(sc):
    d = sc.P - np.asarray(sc.origins[0]["position"])
    return _basis(d)[1]


# ---------------------------------------------------------------- run, check, report

def evaluate(sc, labels):
    group, reason = ammo_group(sc.turret, sc.ammo, sc.data.records)
    r = sc.record["radius"]
    rows = []
    before = json.dumps(sc.record, sort_keys=True)
    origins_in = json.dumps(sc.origins)
    for o in sc.origins:
        origin = np.asarray(o["position"])
        exp, exp_cls, exp_why = truth(sc.s, origin, sc.P, sc.T, group, reason, r)
        got, got_cls, got_why, log = candidate(sc.s, origin, sc.P, sc.T, group, reason)
        hidden = truth(sc.s, origin, sc.s["comp"][sc.T]["pos"] + np.asarray(sc.record["hidden_truth"]), sc.T,
                       group, reason, 0.0)[0]      # X4's own authored point: diagnostic only, not the standard
        rows.append(dict(case=sc.id, source=sc.source, target=sc.target["component"], target_type=_ttype(sc, labels),
                         target_size="large" if sc.large else "small", turret=sc.turret, ammo=sc.ammo,
                         group=group or "UNKNOWN", origin_index=o["index"], origin_source=o["source"],
                         origin=o["position"], aim_point=sc.P.tolist(), aim_record=sc.record, c185=sc.row["result"],
                         expected=exp, expected_class=exp_cls, expected_reason=exp_why, result=got,
                         result_class=got_cls, result_reason=got_why, hidden_point_result=hidden,
                         queries=len(log), query_log=log, **labels))
    assert json.dumps(sc.record, sort_keys=True) == before and json.dumps(sc.origins) == origins_in
    if not sc.origins:
        rows.append(dict(case=sc.id, source=sc.source, target=sc.target["component"], target_type=_ttype(sc, labels),
                         target_size="large" if sc.large else "small", turret=sc.turret, ammo=sc.ammo,
                         group=group or "UNKNOWN", origin_index=None, origin_source=None, origin=None,
                         aim_point=sc.P.tolist(), aim_record=sc.record, c185=sc.row["result"], expected="no pair",
                         expected_class="no origin", expected_reason=None, result="no pair",
                         result_class="no origin", result_reason=None, queries=0, query_log=[], **labels))
    return rows


def _ttype(sc, labels):
    if "surface" in labels:
        return labels["surface"]
    if sc.T == "station":
        return "whole station"
    if sc.T != sc.target["component"] or "kind" in sc.target and sc.target["kind"] != "whole":
        return "surface"
    return f"whole ship {sc.target.get('cls', '?')}"


REQUIRED = dict(
    group={CONV, GUIDED, UNGUIDED, CLUSTER, "UNKNOWN"},
    expected_class={"selected target", "same object, second ray clears", "same object, second ray blocks",
                    "unrelated", "genuine miss", "guided bypass", "weapon", "cross-zone", "no origin"},
    expected_reason={"cross-zone target physics world", "missing guidance", "no loaded ammunition",
                     "unaudited modded ammunition"},
    target_type={"whole ship ship_xs", "whole ship ship_s", "whole ship ship_m", "whole ship ship_l",
                 "whole ship ship_xl", "whole station", "ship turret", "ship shield", "ship engine",
                 "station-module turret"},
    target_size={"small", "large"},
    origin_source={PREDICTED, FALLBACK},
    source={"official", "swi"},
)


def check(rows, scenes):
    fails = []
    for r in rows:
        if r["expected"] != r["result"]:
            fails.append(f"{r['case']} origin {r['origin_index']}: expected {r['expected']}"
                         f" ({r['expected_class']}/{r['expected_reason']}), got {r['result']} ({r['result_class']})")
        elif r["expected"] in (CLEAR, BLOCKED) and r["expected_class"] != r["result_class"] and \
                r["expected_class"] != "ambiguous class, same result":
            fails.append(f"{r['case']}: first-hit class {r['result_class']} != {r['expected_class']}")
        limit = 4 if r["group"] in (CONV, UNGUIDED, CLUSTER) else 0
        if r["queries"] > limit:
            fails.append(f"{r['case']}: {r['queries']} queries > {limit}")
    for sc, labels in scenes:
        mine = [r for r in rows if r["case"] == sc.id and r["origin_index"] is not None]
        if [r["origin_index"] for r in mine] != [o["index"] for o in sc.origins] or \
                [r["origin"] for r in mine] != [o["position"] for o in sc.origins]:
            fails.append(f"{sc.id}: origins dropped, reordered or changed")
        if sc.row["result"] != "CAN AIM" and mine:
            fails.append(f"{sc.id}: invented an origin for {sc.row['result']}")
        if any(r["aim_point"] != (np.asarray(sc.record["centre"]) + sc.s["comp"][sc.T]["pos"]).tolist() for r in mine):
            fails.append(f"{sc.id}: aim point moved")
        for r in mine:        # same world segment in every declared frame; second ray only to the component origin
            for q in r["query_log"]:
                want = sc.s["comp"][sc.T]["pos"] if q["second"] else sc.P
                if np.max(np.abs(np.asarray(q["start"]) - np.asarray(r["origin"]))) > 1e-9 or \
                        np.max(np.abs(np.asarray(q["end"]) - want)) > 1e-6:
                    fails.append(f"{sc.id}: query {q['declared']} moved the origin or endpoint")
            if r["result"] != UNKNOWN and sum(q["second"] for q in r["query_log"]) != \
                    r["result_class"].startswith("same"):
                fails.append(f"{sc.id}: second ray without a same-containing-object first hit")
            inside = [b for b in sc.s["bodies"] if sc.T in chain(sc.s, b["comp"])
                      and _enter(b, np.asarray(r["origin"]), np.asarray(r["origin"]) + 1e-3, 0.0) == 0.0]
            if inside:
                fails.append(f"{sc.id}: firing origin inside the target")
    multi = [sc for sc, _l in scenes if len(sc.origins) > 1]
    if not any({r["result"] for r in rows if r["case"] == sc.id} == {CLEAR, BLOCKED} for sc in multi):
        fails.append("no multi-origin case with one clear and one blocked origin")
    for field, want in REQUIRED.items():
        missing = want - {r[field] for r in rows}
        if missing:
            fails.append(f"coverage: {field} lacks {sorted(missing)}")
    for need in ("own hull", "player ship", "enemy ship", "asteroid", "player station", "enemy station",
                 "station module", "missile/explosive", "gate", "mine (representative small object)",
                 "fresh ship wreck", "persistent wreck", "restored wreck", "wrecked station", "station-module wreck",
                 "destroyed without wreck", "wreck killed again", "wreck timed out"):
        if need not in {r.get("blocker") for r in rows}:
            fails.append(f"coverage: blocker {need}")
    return fails


def _table(rows, field, cols=(CLEAR, BLOCKED, UNKNOWN, "no pair")):
    keys = sorted({str(r.get(field)) for r in rows})
    out = [f"| {field} | " + " | ".join(cols) + " |", "|---|" + "---:|" * len(cols)]
    for k in keys:
        c = Counter(r["result"] for r in rows if str(r.get(field)) == k)
        out.append(f"| {k} | " + " | ".join(str(c[x]) for x in cols) + " |")
    return out


def report(rows, fails, census, seconds, scenes, searches, research_rows):
    wrong_clear = sum(r["result"] == CLEAR and r["expected"] == BLOCKED for r in rows)
    wrong_block = sum(r["result"] == BLOCKED and r["expected"] == CLEAR for r in rows)
    missing_unknown = sum(r["expected"] == UNKNOWN and r["result"] != UNKNOWN for r in rows)
    excess_unknown = sum(r["result"] == UNKNOWN and r["expected"] in (CLEAR, BLOCKED) for r in rows)
    pairs = [r for r in rows if r["origin_index"] is not None]
    nonguided = [r["queries"] for r in pairs if r["group"] in (CONV, UNGUIDED, CLUSTER)]
    census_counts, unknown_ammo, spans = census
    L = ["# LINE OF FIRE benchmark findings (#186 L6)", "",
         "Status: **inference** — offline decision-logic evidence over constructed scenes. Simplified box/sphere "
         "bodies do not reproduce X4 collision meshes; no LIVE evidence is added.", "",
         f"**{len(scenes)} scenes, {len(pairs)} firing-origin + aim-point pairs, {len(rows) - len(pairs)} "
         f"no-origin inputs.** Result: **{'PASS' if not fails else 'FAIL'}**.", "",
         "| measure | value |", "|---|---:|",
         f"| correct scored pairs/inputs (constructed scenes) | "
         f"{sum(r['expected'] == r['result'] for r in rows)} of {len(rows)} |",
         f"| failing pairs | {len({(r['case'], r['origin_index']) for r in rows if r['expected'] != r['result']})} |",
         f"| wrong clear | {wrong_clear} |", f"| wrong LINE OF FIRE BLOCKED | {wrong_block} |",
         f"| correct UNKNOWN | {sum(r['expected'] == r['result'] == UNKNOWN for r in rows)} |",
         f"| missing UNKNOWN (definite where truth is UNKNOWN) | {missing_unknown} |",
         f"| excessive UNKNOWN | {excess_unknown} |",
         f"| max LOS queries, non-guided pair (limit 4) | {max(nonguided)} |",
         f"| max LOS queries, guided / UNKNOWN-weapon pair (limit 0) | "
         f"{max([r['queries'] for r in pairs if r['group'] not in (CONV, UNGUIDED, CLUSTER)] or [0])} |",
         f"| total simulated LOS queries | {sum(r['queries'] for r in rows)} |",
         f"| centre result differing from the hidden authored-point result | "
         f"{sum(r['result'] != r.get('hidden_point_result', r['result']) for r in pairs)} |",
         f"| #184 frozen searches (one per target view) / max samples | {searches[0]} / {searches[1]} |",
         f"| offline Python run time (not X4 cost) | {seconds:.1f} s |", ""]
    if fails:
        L += ["## Failures", ""] + [f"- {f}" for f in fails] + [""]
    L += ["## Accepted design-risk example (excluded from correctness scoring)", "",
          f"- `off-box-uncertainty`: the synthetic blocker edge gives expected "
          f"{research_rows[0]['expected']} and candidate {research_rows[0]['result']}. This does not establish "
          "that such an edge occurs for the real X4 collision geometry. The retained design deliberately uses "
          "#184's supplied centre point for obstruction and accepts this residual edge risk rather than expanding "
          "the recovery uncertainty area or returning UNKNOWN.", "",
          "## Notes", "",
          "- Simulated `check_line_of_sight` returns a boolean for one known constructed body-presence state. "
          "Actual wreck bodies are present or absent; both established rules have scored cases.",
          "- Observed maximum is 3 queries: the tree issues either the zone query or the second ray, never both. "
          "The accepted L4 bound of 4 is still enforced.",
          "- XS comes from #184 `targets()` (the A4.4 census omits XS); `ship_arg_l_destroyer_01` is a real "
          "no-aim-point L ship from the vanilla A4.4 census (box-centre fallback); `arrestor_cruiser` comes from "
          "the SWI-applied census with a SWI turret. Rows keep `source` official/swi separate.",
          "- Ammunition switch: `turret_arg_m_dumbfire_01_mk1` loads both ordinary unguided and cluster "
          "ammunition. No official missile turret's ammunition tags accept both guided and dumbfire macros, so a "
          "guided/unguided switch on one turret does not exist in source.",
          "- The multi-origin scene uses 100 m: #185's only known multi-stable case (bor disruptor, leaf limit) "
          "is at that distance; the recovered #184 point is reached along that exact turret-local bearing.",
          "- The whole-station scene places two real module macros at invented offsets and uses their synthetic "
          "union box for a box-centre fallback. It is not a real station layout. Surface hosts use real "
          "attachment frames, but their host-part spheres are artificial branch fixtures, not hull meshes. "
          "Whole-ship runtime boxes are also abstract hit shapes, not ship bodies. No modeled hit or miss "
          "establishes physical attainability in X4.",
          "- Pair-specific collision filters have no runtime-visible input, so no scene models them; they stay "
          "an L8 condition.", ""]
    for field in ("group", "target_type", "target_size", "blocker", "order", "expected_class", "result_reason",
                  "origin_source", "source"):
        L += _table(rows, field) + [""]
    L += ["## Per-origin results", ""]
    for sc, _l in scenes:
        if len(sc.origins) > 1 or (sc.origins and sc.origins[0]["source"] == FALLBACK) or not sc.origins:
            got = [(r["origin_index"], r["origin_source"], r["result"]) for r in rows if r["case"] == sc.id]
            L.append(f"- `{sc.id}` (#185 {sc.row['result']}): {got}")
    L += ["", "## Weapon behavior source check", "",
          f"Compatible official turret ammunition by group: {dict(census_counts)} (accepted L2: "
          f"{L2_OFFICIAL_AMMO}). Compatible macros without a usable guidance value: {unknown_ammo}. "
          f"Missile-turret ammunition tag sets spanning guided and dumbfire: {len(spans)}.", ""]
    return "\n".join(L)


def main():
    t0 = time.perf_counter()
    census = official_ammo_census()
    if {k: census[0][k] for k in L2_OFFICIAL_AMMO} != L2_OFFICIAL_AMMO:
        raise SystemExit(f"official ammunition census drift: {dict(census[0])}")
    data = Data()
    all_scenes = list(cases(data))
    research_scenes = [(sc, labels) for sc, labels in all_scenes if sc.id.startswith("off-box-uncertainty#")]
    scenes = [(sc, labels) for sc, labels in all_scenes if not sc.id.startswith("off-box-uncertainty#")]
    research_rows = [row for sc, labels in research_scenes for row in evaluate(sc, labels)]
    rows = [row for sc, labels in scenes for row in evaluate(sc, labels)]
    seconds = time.perf_counter() - t0
    fails = check(rows, scenes)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(OUT, "wt") as fh:
        for r in rows:
            fh.write(json.dumps(r, default=float, sort_keys=True) + "\n")
    searches = (len(data.views), max(st["asks"] for _c, st, _r in data.views.values()))
    text = report(rows, fails, census, seconds, scenes, searches, research_rows)
    (HERE / "findings.md").write_text(text)
    print(text)
    print(f"rows: {OUT}")
    if fails:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
