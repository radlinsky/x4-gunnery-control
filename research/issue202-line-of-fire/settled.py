"""Issue #202: settled CLEAR LINE OF FIRE benchmark on real X4 9.00 collision geometry.

Truth is the straight path from the turret's SETTLED `barrelposition` to the X4 aim point it is
bearing toward, not the line any method tests. For each test (turret, starting yaw, target,
arrangement):

1. CAN BEAR by the accepted #176 scorer on X4's selected aim point; otherwise UNKNOWN, excluded.
2. Settling from the starting yaw (zero velocity) by the #166 yaw gate: the turret moves toward
   sign(g) to the nearest attractor that way. A trap there, or a settled yaw whose pitch is out of
   arc, is UNKNOWN (cannot be shown to settle), excluded. The favorable rest is never picked.
3. The segment from the settled `barrelposition` (endpoint element 0) to that same aim point is cast,
   ignoring only the firing turret's own meshes as X4's pre-fire gate does. Its first hit is scored
   with the #202 membership rules: a member is CLEAR, anything else NOT CLEAR. A segment that
   reaches the aim point without any hit has no first hit to classify (UNKNOWN), and the MESH and
   HULL shape models must agree; otherwise UNKNOWN.

Each barrel's settled +Z projectile path is kept as a diagnostic only; it never defines or excludes
a row.

Candidates are the `benchmark.py` decision code (current, seven, lazy, eight = seven + old centre),
fed with the physical first hit of each tested segment from the pre-turn muzzle and from the
settled muzzle. Query counts are simulated `check_line_of_sight` calls.

    python3 research/issue202-line-of-fire/settled.py [--report]   # ~6 min, one process; needs the #176 corpus
"""
from __future__ import annotations

import gzip
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path[:0] = [str(HERE), str(ROOT / "research/issue176-a4x")]
import benchmark as B  # noqa: E402
import geometry as Gm  # noqa: E402
import scorer  # noqa: E402
from barrelposition_evaluator import (  # noqa: E402
    ZERO, _native_connection_name_hash, compose, evaluate, joint_matrix, load_turrets, ry, vec_mul)
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

# The #202 LIVE scene: the owner's Boron Ray with 12 M railguns and 2 L disruptors, two Osakas.
FIRING = ("ship_bor_l_destroyer_01", {"medium": "turret_bor_m_railgun_02_mk1_macro",
                                      "large": "turret_bor_l_disruptor_01_mk1_macro"})
TARGET = "ship_ter_l_destroyer_01"
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
MODELS = ("mesh", "hull")
METHODS = ("current", "seven", "lazy", "eight")
PHASES = ("parked", "settled")


# ---------------------------------------------------------------- scene assembly

def _frame(tr):
    return np.asarray(tr[0], float), np.asarray(tr[1], float)


def _mating(comp):
    found = [c for c in S.connections(comp).values() if "component" in S.tags(c)]
    assert len(found) == 1, comp.get("name")
    return found[0]


def _mounts(ship, loadout):
    """[(connection, macro, component-frame -> ship-frame transform)] for a stated loadout."""
    comp, out = S.component(ship), []
    for name, conn in sorted(S.connections(comp).items()):
        t = S.tags(conn)
        kind = next((k for k in ("turret", "shield", "engine") if k in t), None)
        if kind is None or "component" in t:
            continue
        size = "large" if "large" in t else "medium"
        macro = loadout.get(f"{kind} {size}", loadout.get(size) if kind == "turret" else None)
        if macro is None:
            continue
        child = S.component(S.macro(macro).find("component").get("ref"))
        assert S.tags(_mating(child)) - {"component"} <= t, (name, macro)
        out.append((name, macro, S.compose(S._inverse(S.conn_world(child, _mating(child))), S.conn_world(comp, conn))))
    return out


def _pose(position, yaw_deg):
    return (tuple(map(float, position)), ry(math.radians(yaw_deg)))


def _body(macro):
    return Gm.body(S.macro(macro).find("component").get("ref"))


def element_info(macro):
    """Element-frame box centre, half-extents and authored aim points (hash order), as #167/#184."""
    comp = S.component(S.macro(macro).find("component").get("ref"))
    aims = sorted((c for c in S.connections(comp).values() if "aimtarget" in S.tags(c)),
                  key=lambda c: _native_connection_name_hash(c.get("name").lower()))
    points = [tuple(float(c.find("offset/position").get(a, 0)) for a in "xyz") for c in aims]
    C, H = S.center_half(macro)
    return np.array(C), np.array(H), [np.array(p) for p in points]


class Scene:
    def __init__(self, arrangement, target_yaw):
        ray = (ZERO, ((1.0, 0, 0), (0, 1.0, 0), (0, 0, 1.0)))
        self.instances = [("ray", Gm.body(FIRING[0]), _frame(ray))]
        self.turrets = []
        for i, (conn, macro, tr) in enumerate(_mounts(FIRING[0], FIRING[1])):
            world = compose(tr, ray)
            self.turrets.append(dict(index=i, mount=conn, macro=macro, frame=world))
            self.instances.append((f"sock:{i}", _body(macro), _frame(world)))
        self.elements = []
        for side, position in zip("RL", ARRANGEMENTS[arrangement]):
            pose = _pose(position, target_yaw)
            self.instances.append((f"osaka:{side}", Gm.body(TARGET), _frame(pose)))
            if side == "R":
                self.hull_pose = pose
            for conn, macro, tr in _mounts(TARGET, TARGET_LOADOUT):
                world = compose(tr, pose)
                label = f"el:{side}:{conn}"
                b = _body(macro)
                if b is not None:
                    self.instances.append((label, b, _frame(world)))
                if side == "R":
                    self.elements.append(dict(label=label, conn=conn, macro=macro, frame=world, body=b is not None))

    def symbol(self, label, turret, target):
        """Map an instance to the benchmark.py world (W own turret, S firing hull, P target hull, T/T2)."""
        if label is None:
            return None
        if label == "ray":
            return "S"
        if label.startswith("sock:"):
            return "W" if label == f"sock:{turret}" else "W2"
        if label == "osaka:R":
            return "P"
        if label.startswith("el:R:"):
            return "T" if label == target else "T2"
        return "X"                                    # the other Osaka and its elements


def _to_local(p, frame):
    t, R = _frame(frame)
    return (np.asarray(p) - t) @ R.T


def _to_world(p, frame):
    t, R = _frame(frame)
    return np.asarray(p) @ R + t


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
    # KB emulation: settled on a target astern it stays at -pi; from anywhere else it reaches yaw 0.
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


# ---------------------------------------------------------------- one test

def _lines(scene, origin, turret, target_label, element, hull_target, models):
    """First-hit symbol per tested segment from `origin`, for each shape model."""
    if hull_target:
        C, H = (np.array(v) for v in S.center_half(f"{TARGET}_a_macro"))
        frame = scene.hull_pose
        o = _to_local(origin, frame)
        gap = np.linalg.norm(C - o)
        push = 0.9 * H.min()
        ends = {"c": C + (C - o) * push / gap if gap > 0 and push > 0 else C,
                "aim": C}                                  # no authored aim point: box centre
    else:
        C, H, aims = element_info(element["macro"])
        frame = element["frame"]
        o = _to_local(origin, frame)
        aim = aims[_select(o, aims)] if aims else C       # the useaimtarget endpoint from this origin
        ends = {"c": C, "aim": aim}
        for axis, name in enumerate("xyz"):
            for pct, sign in (("25", -0.5), ("75", 0.5)):
                p = C.copy()
                p[axis] += sign * H[axis]
                ends[name + pct] = p
    out = {}
    for model in models:
        out[model] = {}
        for e, p in ends.items():
            label, _t = Gm.first_hit(scene.instances, origin, e=_to_world(p, frame), model=model)
            sym = scene.symbol(label, turret, target_label)
            out[model][e] = [sym] if sym else []
    return out


def _select(o, points):
    """Native nearest authored aim point (binary32 distance, earlier wins ties); origin in target frame."""
    import study
    return study.select(tuple(o), [tuple(p) for p in points])


def _endpoints(evaluator_turret):
    lasers = [n for n, c in evaluator_turret["connections"].items() if "laser" in c["tag_tokens"]]
    return sorted(lasers, key=_native_connection_name_hash)


def _muzzles(ev, x, y, frame):
    """World (position, +Z direction) of every firing endpoint at joint angles (x, y)."""
    out = []
    for conn in _endpoints(ev):
        tr = evaluate(dict(ev, selected_connection=conn), x, y)["transform"]
        t, R = _frame(frame)
        out.append((np.asarray(tr["translation"]) @ R + t, np.asarray(tr["z"]) @ R))
    return out


def run_test(scene, turret, record, tur, ev, target, start, models=MODELS):
    hull_target = target is None
    target_label = "osaka:R" if hull_target else target["label"]
    # aim point in world: the element's nearest authored point from the turret origin, else box centre
    if hull_target:
        C, _H = S.center_half(f"{TARGET}_a_macro")
        aim_world = _to_world(np.array(C), scene.hull_pose)
    else:
        C, _H, aims = element_info(target["macro"])
        turret_origin = _to_local(_frame(turret["frame"])[0], target["frame"])
        aim_world = _to_world(aims[_select(turret_origin, aims)] if aims else C, target["frame"])
    pt = tuple(float(v) for v in _to_local(aim_world, turret["frame"]))
    row = dict(turret=turret["index"], macro=turret["macro"], target=target_label, start=start,
               aim_points=0 if hull_target else len(aims))
    state, y, x = settle(record, tur, pt, start)
    row["state"] = state
    # pre-turn muzzle: the starting yaw at rest pitch 0
    parked = _muzzles(ev, 0.0, start, turret["frame"])
    row["phases"] = {"parked": _lines(scene, parked[0][0], turret["index"], target_label, target, hull_target, models)}
    if state != "SETTLED":
        return row
    settled = _muzzles(ev, x, y, turret["frame"])
    row["phases"]["settled"] = _lines(scene, settled[0][0], turret["index"], target_label, target, hull_target, models)
    row["yaw"], row["pitch"] = y, x
    own = {f"sock:{turret['index']}"}
    # truth: settled barrelposition -> the aim point the turret bears toward
    row["truth_hits"] = {m: scene.symbol(Gm.first_hit(scene.instances, settled[0][0], e=aim_world, model=m,
                                                      skip=own)[0], turret["index"], target_label)
                         for m in models}
    # diagnostic only: each barrel's settled +Z projectile path
    row["shots"] = {m: [scene.symbol(Gm.first_hit(scene.instances, p, d=d, tmax=SHOT_RANGE, model=m, skip=own)[0],
                                     turret["index"], target_label) for p, d in settled] for m in models}
    row["barrels"] = len(settled)
    return row


def _tsym(row):
    return "P" if row["target"] == "osaka:R" else "T"


def _cls(tsym, hit):
    return None if hit is None else B.qualifies(tsym, hit)


def truth(row):
    """CLEAR / NOT, or the UNKNOWN reason, for the settled barrelposition -> aim point path."""
    if row["state"] != "SETTLED":
        return row["state"]
    classes = {_cls(_tsym(row), h) for h in row["truth_hits"].values()}
    if len(classes) > 1:
        return "shape models disagree"
    cls = classes.pop()
    if cls is None:
        return "aim path reaches no geometry"
    return "CLEAR" if cls else "NOT"


def aim_probe(row, phase, model):
    """The first `useaimtarget=true` probe by itself: True iff its first hit is a target member."""
    line = row["phases"][phase][model]["aim"]
    return bool(line) and B.qualifies(_tsym(row), line[0])


def candidates(row, model):
    """{(method, phase): (status, reason, calls)} through the benchmark.py decision code."""
    out = {}
    target = "P" if row["target"] == "osaka:R" else "T"
    for phase, lines in row["phases"].items():
        sc = dict(id="physical", target=target, lines=lines[model])
        for method in METHODS:
            out[method, phase] = B.candidate(sc, method)
    return out


# ---------------------------------------------------------------- population

def population():
    records = scorer.load()
    src = ROOT / ".x4-research-cache/official-source-sets"
    ani = ROOT / ".x4-research-cache/issue72-a2-ani-resources"
    macros = sorted(set(FIRING[1].values()))
    evs = load_turrets({n: src / n for n in REQUIRED_SOURCE_SETS}, {n: ani / n for n in REQUIRED_SOURCE_SETS}, macros)
    turs = {m: scorer.accepted_turret(records["official:" + m]) for m in macros}
    rows = []
    for arrangement in ARRANGEMENTS:
        for yaw in TARGET_YAWS:
            scene = Scene(arrangement, yaw)
            targets = [None] + [e for e in scene.elements if e["body"]]
            for turret in scene.turrets:
                m = turret["macro"]
                for target in targets:
                    for start in START_YAWS:
                        row = run_test(scene, turret, records["official:" + m], turs[m], evs[m], target, start)
                        row.update(arrangement=arrangement, target_yaw=yaw,
                                   target_macro=None if target is None else target["macro"])
                        rows.append(row)
            print(f"{arrangement} yaw {yaw}: {len(rows)} tests", flush=True)
    return rows, evs, turs, records


def check_kinematics(evs, turs):
    """The evaluator's element-0 endpoint must be the scorer's muzzle (same accepted transform chain)."""
    import study
    for m, ev in evs.items():
        assert _endpoints(ev)[0] == ev["selected_connection"], m
        for pt in ((30.0, 40.0, 900.0), (-400.0, 150.0, -60.0)):
            g = study.geometry(turs[m], ((1.0, 0, 0), (0, 1.0, 0), (0, 0, 1.0)), ZERO, pt)
            if g["decision"]:
                mine = evaluate(ev, g["pitch"], g["yaw"])["transform"]["translation"]
                assert np.allclose(mine, g["muzzle"], atol=1e-6), (m, mine, g["muzzle"])


# ---------------------------------------------------------------- #60 station geometry

# Shipped `xen_defence` construction plan (libraries/constructionplans.xml): module macro, position, yaw.
XEN_DEFENCE = (("dockarea_xen_m_station_01_macro", (0, 0, 0), 0),
               ("xenon_small_station_01_base_macro", (-335.085, -94.811, -1581.06), 0),
               ("xenon_small_station_01_base_macro", (-1596.242, -277.647, -1040.873), 139.99998),
               ("xenon_small_station_01_base_macro", (335.085, -94.81, 1581.06), -179.99991),
               ("xenon_small_station_01_base_macro", (1596.242, -277.647, 1040.873), -40.00001))


def station60(distance=4000.0, samples=200):
    """Where the station root's `useaimtarget` endpoint (the live union-box centre; stations author no
    aim point) lies, and what a straight line from outside toward it hits first."""
    instances, lo, hi = [], [], []
    for i, (macro, position, yaw) in enumerate(XEN_DEFENCE):
        pose = _frame(_pose(position, yaw))
        instances.append((f"M{i + 1}", _body(macro), pose))
        C, H = (np.array(v) for v in S.center_half(macro))
        corners = np.array([[C[j] + (H[j] if k >> j & 1 else -H[j]) for j in range(3)] for k in range(8)])
        world = corners @ pose[1] + pose[0]
        lo.append(world.min(0))
        hi.append(world.max(0))
    centre = (np.min(lo, 0) + np.max(hi, 0)) / 2
    out = dict(centre=centre.round(1).tolist(), inside={}, lines={})
    for model in MODELS:
        # a point is inside solid geometry if a ray from it leaves through an odd number of MESH faces;
        # for HULL it is inside iff a zero-length cast from it hits (solid convex)
        hit = Gm.first_hit(instances, centre, d=np.array([0.0, 1.0, 0.0]), tmax=1e-9, model="hull")[0]
        out["inside"][model] = hit if model == "hull" else _parity_inside(instances, centre)
    golden = math.pi * (3 - math.sqrt(5))
    for model in MODELS:
        firsts = Counter()
        for k in range(samples):
            z = 1 - 2 * (k + 0.5) / samples
            r = math.sqrt(1 - z * z)
            direction = np.array([r * math.cos(golden * k), z, r * math.sin(golden * k)])
            firsts[Gm.first_hit(instances, centre + distance * direction, e=centre, model=model)[0] or "none"] += 1
        out["lines"][model] = dict(sorted(firsts.items()))
    return out


def _parity_inside(instances, point):
    """Odd crossings of two-sided MESH faces along +Y (instance-wise) -> the containing module, else None."""
    for label, b, (t, R) in instances:
        o, d = (point - t) @ R.T, np.array([0.0, 1.0, 0.0]) @ R.T
        e1, e2 = b.tris[:, 1] - b.tris[:, 0], b.tris[:, 2] - b.tris[:, 0]
        p = np.cross(d, e2)
        det = (e1 * p).sum(1)
        ok = np.abs(det) > 1e-12
        inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
        s = o - b.tris[:, 0]
        u = (s * p).sum(1) * inv
        q = np.cross(s, e1)
        v = (q @ d) * inv
        tt = (e2 * q).sum(1) * inv
        if (ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (tt > 0)).sum() % 2:
            return label
    return None


# ---------------------------------------------------------------- scoring and report

def score_rows(rows, model):
    """Binary accuracy per (method, phase) on rows with defensible truth. BLOCKED and UNKNOWN are
    'not clear'; UNKNOWN is also counted on its own. -> {(method, phase): Counter}."""
    table = defaultdict(Counter)
    for row in rows:
        t = truth(row)
        if t not in ("CLEAR", "NOT"):
            continue
        for key, (status, _reason, calls) in candidates(row, model).items():
            said = status == "C"
            c = table[key]
            c["TP" if said and t == "CLEAR" else "FP" if said else "FN" if t == "CLEAR" else "TN"] += 1
            c["UNKNOWN"] += status == "U"
            c["UNKNOWN on CLEAR truth"] += status == "U" and t == "CLEAR"
            c["n"] += 1
            c["calls"] += calls
    return table


def _kind(row):
    m = row.get("target_macro") or "hull"
    return "hull" if m == "hull" else m.split("_")[0]


def _q(values, p):
    values = sorted(values)
    return values[min(len(values) - 1, int(p * len(values)))]


def report(rows):
    out = []
    say = out.append
    say(f"# Settled-shot benchmark ({len(rows)} tests)\n")
    kinds = sorted({_kind(r) for r in rows})
    states = Counter((truth(r), _kind(r)) for r in rows)
    order = ["CLEAR", "NOT", "CANNOT BEAR", "scorer UNKNOWN", "trap", "start on a repeller",
             "settled rest out of arc", "shape models disagree", "aim path reaches no geometry"]
    say("## Truth and exclusions\n")
    say("| truth | " + " | ".join(kinds) + " | total |")
    say("|---|" + "---:|" * (len(kinds) + 1))
    for t in order:
        say(f"| {t} | " + " | ".join(str(states[t, k]) for k in kinds) + f" | {sum(states[t, k] for k in kinds)} |")
    for model in MODELS:
        say(f"\n## Accuracy, {model.upper()} shape model (scored rows only)\n")
        say("| method | phase | n | TP | FP | TN | FN | UNKNOWN | UNKNOWN on CLEAR | mean calls |")
        say("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        table = score_rows(rows, model)
        for method in METHODS:
            for phase in PHASES:
                c = table[method, phase]
                say(f"| {method} | {phase} | {c['n']} | {c['TP']} | {c['FP']} | {c['TN']} | {c['FN']} | "
                    f"{c['UNKNOWN']} | {c['UNKNOWN on CLEAR truth']} | {c['calls'] / max(1, c['n']):.2f} |")
        for phase in PHASES:
            c = Counter()
            for r in rows:
                t = truth(r)
                if t in ("CLEAR", "NOT"):
                    said = aim_probe(r, phase, model)
                    c["TP" if said and t == "CLEAR" else "FP" if said else "FN" if t == "CLEAR" else "TN"] += 1
            say(f"| useaimtarget probe alone | {phase} | {sum(c.values())} | {c['TP']} | {c['FP']} | {c['TN']} | "
                f"{c['FN']} | - | - | 1.00 |")
    say("\n## useaimtarget probe versus truth, MESH: what explains each mismatch\n")
    why = Counter()
    for r in rows:
        t = truth(r)
        if t not in ("CLEAR", "NOT"):
            continue
        for phase in PHASES:
            said = aim_probe(r, phase, "mesh")
            if said == (t == "CLEAR"):
                continue
            line = r["phases"][phase]["mesh"]["aim"]
            first = line[0] if line else "no hit before the endpoint"
            origin = "same origin" if phase == "settled" else "parked origin"
            multi = "; several aim points" if r["aim_points"] > 1 else ""
            why[phase, t, f"probe first hit {first} ({origin}{multi})"] += 1
    say("\n".join(f"- {p}: truth {t}, {w}: {n}" for (p, t, w), n in sorted(why.items())) or "- none")
    say("\n## Parked to settled, MESH (same rows, same truth)\n")
    say("| method | FN fixed | FN introduced | FP fixed | FP introduced |")
    say("|---|---:|---:|---:|---:|")
    scored = [(r, truth(r), candidates(r, "mesh")) for r in rows if truth(r) in ("CLEAR", "NOT")]
    for method in METHODS:
        c = Counter()
        for _r, t, cand in scored:
            a, b = cand[method, "parked"][0] == "C", cand[method, "settled"][0] == "C"
            if t == "CLEAR":
                c["FN fixed"] += not a and b
                c["FN introduced"] += a and not b
            else:
                c["FP fixed"] += a and not b
                c["FP introduced"] += not a and b
        say(f"| {method} | {c['FN fixed']} | {c['FN introduced']} | {c['FP fixed']} | {c['FP introduced']} |")
    say("\n## Element targets only, MESH, settled phase\n")
    say("| method | n | TP | FP | TN | FN | UNKNOWN |")
    say("|---|---:|---:|---:|---:|---:|---:|")
    el = [r for r in rows if r["target"] != "osaka:R"]
    table = score_rows(el, "mesh")
    for method in METHODS:
        c = table[method, "settled"]
        say(f"| {method} | {c['n']} | {c['TP']} | {c['FP']} | {c['TN']} | {c['FN']} | {c['UNKNOWN']} |")
    diff = Counter()
    for r, t, cand in scored:
        for phase in PHASES:
            s7, s8 = cand["seven", phase][0], cand["eight", phase][0]
            if s7 != s8:
                diff[phase, t, s7, s8] += 1
    say("\n## Eighth point (old centre after the seven), rows where it changes the status\n")
    say("\n".join(f"- {p}: truth {t}, seven {a} -> eight {b}: {n}" for (p, t, a, b), n in sorted(diff.items()))
        or "- none")
    lazy = sum(cand["lazy", p][0] != cand["seven", p][0] for _r, _t, cand in scored for p in PHASES)
    say(f"- lazy classification changed a status in {lazy} scored rows")
    # diagnostic only: settled +Z projectile paths against the line-of-fire truth
    b0 = Counter()
    for r in rows:
        t = truth(r)
        if t not in ("CLEAR", "NOT"):
            continue
        hits = [_cls(_tsym(r), h) for h in r["shots"]["mesh"]]
        b0["scored rows"] += 1
        b0["barrel 0 +Z path differs from truth"] += bool(hits[0]) != (t == "CLEAR")
        if r["barrels"] > 1:
            b0["multi-barrel rows"] += 1
            b0["another barrel's +Z path differs from barrel 0"] += any(bool(h) != bool(hits[0]) for h in hits[1:])
    starts = defaultdict(dict)
    for r in rows:
        if r["state"] == "SETTLED":
            starts[r["arrangement"], r["target_yaw"], r["turret"], r["target"]][r["start"]] = (r["yaw"], truth(r))
    split = [v for v in starts.values() if len(v) == 2 and
             abs(math.remainder(v[0.0][0] - v[math.pi][0], 2 * math.pi)) > 1e-3]
    say(f"\n## Starting state\n\n- same turret and target, parked vs astern start settle at different yaws: "
        f"{len(split)} pairs; truth differs in {sum(v[0.0][1] != v[math.pi][1] for v in split)}")
    say("\n## Diagnostic only: settled +Z projectile paths (MESH; never defines or excludes a row)\n")
    say("\n".join(f"- {k}: {v}" for k, v in b0.items()))
    # query cost per 14-turret pass
    say("\n## Simulated check_line_of_sight calls (MESH), per turret and per 14-turret pass\n")
    say("| method | phase | median | p90 | max | pass median | pass max |")
    say("|---|---|---:|---:|---:|---:|---:|")
    passes = defaultdict(lambda: defaultdict(int))
    per = defaultdict(list)
    for r in rows:
        if r["state"] != "SETTLED":
            continue
        cand = candidates(r, "mesh")
        key = (r["arrangement"], r["target_yaw"], r["target"], r["start"])
        for (method, phase), (_s, _why, calls) in cand.items():
            per[method, phase].append(calls)
            passes[method, phase][key] += calls
    for method in METHODS:
        for phase in PHASES:
            v, pv = per[method, phase], list(passes[method, phase].values())
            say(f"| {method} | {phase} | {_q(v, .5)} | {_q(v, .9)} | {max(v)} | {_q(pv, .5)} | {max(pv)} |")
    say("\n(passes count only turrets that settle; a full pass also checks the excluded ones)")
    say("\n## #202 fixture, parked start: elements where current reads <= 2/14 but >= 7 turrets truly CLEAR\n")
    say("| Osaka yaw | element | truth CLEAR / scored | current | seven | eight | current centre-line first hit |")
    say("|---:|---|---:|---:|---:|---:|---|")
    live_like = 0
    for w in witness202(rows):
        scored = w["truth"].get("CLEAR", 0) + w["truth"].get("NOT", 0)
        if w["current"] <= 2 and w["truth"].get("CLEAR", 0) >= 7:
            live_like += 1
            say(f"| {w['yaw']} | {w['target'].split(':')[-1]} | {w['truth'].get('CLEAR', 0)} / {scored} | "
                f"{w['current']}/14 | {w['seven']}/14 | {w['eight']}/14 | {w['centre_first_hit']} |")
    say(f"\n{live_like} element/orientation pairs show the LIVE #202 pattern.")
    st = station60()
    say("\n## #60 Xenon Defence Platform (shipped `xen_defence` plan, real module meshes)\n")
    say(f"- live union-box centre {st['centre']}: inside MESH module {st['inside']['mesh']}, "
        f"inside HULL piece {st['inside']['hull']}")
    for model in MODELS:
        say(f"- {model.upper()}: first hit on 200 lines from 4 km toward that centre: {st['lines'][model]}")
    return "\n".join(out)


def witness202(rows):
    """Fixture arrangement, parked start: per element and target yaw, CLEAR counts out of 14."""
    groups = defaultdict(list)
    for r in rows:
        if r["arrangement"] == "fixture" and r["start"] == 0.0 and r["target"] != "osaka:R":
            groups[r["target_yaw"], r["target"]].append(r)
    out = []
    for (yaw, target), rs in sorted(groups.items()):
        t = Counter(truth(r) for r in rs)
        c = {m: sum(r["state"] == "SETTLED" and candidates(r, "mesh")[m, "settled"][0] == "C" for r in rs)
             for m in ("current", "seven", "eight")}
        blockers = Counter(r["phases"]["settled"]["mesh"]["c"][0] if r["phases"]["settled"]["mesh"]["c"] else "miss"
                           for r in rs if r["state"] == "SETTLED")
        out.append(dict(yaw=yaw, target=target, truth=dict(t), **c, centre_first_hit=dict(blockers)))
    return out


def load_rows():
    with gzip.open(OUT, "rt") as stream:
        return [json.loads(line) for line in stream]


def main():
    if "--report" not in sys.argv:
        rows, evs, turs, _records = population()
        check_kinematics(evs, turs)
        check_settling()
        OUT.parent.mkdir(parents=True, exist_ok=True)
        with gzip.open(OUT, "wt") as stream:
            for row in rows:
                stream.write(json.dumps(row, separators=(",", ":"), default=float) + "\n")
    print(report(load_rows()))


if __name__ == "__main__":
    main()
