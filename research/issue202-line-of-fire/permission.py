"""Issue #202: selected-target CLEAR LINE OF FIRE scored against X4's own pre-fire permission.

Truth is X4's pre-fire obstruction decision (native trace, weapon-path-obstruction-groups.md), for the turret
settled on its bearing point and every other firing requirement assumed met. It is permission, not a launch
or a hit. The firing turret's own meshes are ignored, as native does.

- Beam ammunition (`isbeam`, no `lenientfireallowance`, target not a missile) casts from the muzzle along the
  barrel for max fire range R. It fires only if the first hit is the target or a descendant; a miss or any
  other hit withholds fire.
- Everything else casts from the muzzle to `muzzle + f * (bearing point - muzzle)`, where f = 1 + min(1.1 R,
  500) / R against a target with a non-zero cached max speed (whole ship, ship engine) and 1 otherwise.
  - no hit, or the target or a descendant: fire;
  - a hit sharing the target's first class-`object` ancestor (only reachable for a surface element): a second
    ray to `muzzle + f * (target origin - muzzle)` fires only if its first hit is exactly the target;
  - anything else: no fire.
- Guided missile turrets skip the check (GUIDED).

Truth is uncertain when the MESH and HULL models disagree, two first hits on different instances within
TIE differ in outcome, or the answer changes between f = 1 and the f of the turret's R.

Candidates see what `check_line_of_sight` sees (`excludeself=false`, so the firing turret's own meshes too):
- current: production at cf459d0 (`benchmark.py`), two nearest modules for a station root;
- base: the `useaimtarget=true` probe, then step and look back, BLOCKED only when `Q(Z)` true and `Q(W)`
  false from the muzzle to the step point;
- base+modules: base, then current's module lines when base is not decided (the owner's hypothesis);
- base+ext: base, then along the same direction the aimed line continues to EXT: CLEAR when its first hit is a
  target member (for a beam, within R), or, for other turrets, when it hits nothing (a genuine miss).

    python3 research/issue202-line-of-fire/permission.py [--report]   # ~15 min, one niced process
"""
from __future__ import annotations

import gzip
import json
import sys
import time
from collections import Counter

import numpy as np

import settled as St
from settled import B, Gm, Sc

OUT = St.ROOT / ".x4-research-cache/issue202-settled/permission.jsonl.gz"
EXT = 30000.0         # m: the extended aimed line; must reach past X4's own endpoint (checked per row)
F_MAX = 2.1           # f = 1 + min(1.1 R, 500) / R never exceeds this
# Max fire range R (m) per benchmark turret macro: bullet `range`, else speed x lifetime; missiles use the
# missile macro's `range` (source census, not the native maxfirerange getter). Only the beam's R and f use it.
FIRE_RANGE = {"turret_bor_m_railgun_02_mk1_macro": 8100.0, "turret_bor_l_disruptor_01_mk1_macro": 9800.0,
              "turret_par_m_shotgun_01_mk1_macro": 3750.0, "turret_bor_m_laser_01_mk1_macro": 3840.0,
              "turret_bor_m_laser_02_mk1_macro": 3840.0, "turret_spl_l_laser_01_mk1_macro": 5000.0,
              "turret_kha_m_beam_01_mk1_macro": 4822.0, "turret_arg_m_dumbfire_02_mk1_macro": 5500.0,
              "turret_bor_m_dumbfire_01_mk1_macro": 5500.0, "turret_par_l_dumbfire_01_mk1_macro": 6500.0}
BEAMS = {"turret_kha_m_beam_01_mk1_macro"}    # the only benchmark turret whose bullet is a beam (attach="1")
OBJECT = {"ship surface": "P", "station surface": "ST"}   # a surface element's first class-object ancestor
METHODS = ("current", "base", "base+modules", "base+ext")


def moving(target):
    """Target slot +0x1A88 non-zero: a whole ship, or a ship engine (forwards to its ship)."""
    return target["cls"] == "whole ship" or (target["cls"] == "ship surface" and target["kind"] == "engine")


def _hit(scene, turret, target, rank, o, e=None, d=None, tmax=None, model="mesh", skip=()):
    label, t, label2, t2 = Gm.first_hit(scene.instances, o, e=e, d=d, tmax=tmax, model=model, skip=skip,
                                        runner_up=True)
    sym = St.symbol(scene, label, turret, target, rank)
    return [sym, t if label else None, St.symbol(scene, label2, turret, target, rank) if t2 - t < St.TIE else None]


def test(scene, turret, target, start, ctx, models=St.MODELS):
    record = ctx["records"][turret["key"]]
    row = dict(scene=scene.name, turret=turret["label"], macro=turret["macro"], target=target["label"],
               target_cls=target["cls"], target_kind=target.get("kind"), aim_points=len(target["points"]),
               start=start)
    if record["weapon_behavior"] == "guided_missile":
        return dict(row, state="GUIDED")
    aim, _source, _i = St.bearing_point(scene, turret, target)
    if aim is None:
        return dict(row, state=_source)
    pt = tuple(float(v) for v in Sc.to_local(aim, turret["frame"]))
    state, y, x = St.settle(record, ctx["turs"][turret["macro"]], pt, start)
    row["state"] = state
    if state != "SETTLED":
        return row
    o, z = St._muzzles(ctx["evs"][turret["macro"]], record["endpoint"]["tag"], x, y, turret["frame"])[0]
    z = z / np.linalg.norm(z)
    rank = St.module_rank(scene, target)
    lines = St._lines(scene, o, turret, target, rank, models)       # current's and base's lines
    ends = St.endpoints(scene, turret, target, o, rank)
    # the step direction and point, exactly as settled._rescue_lines builds them
    ahead = Sc.to_world(target["points"][St._select(Sc.to_local(o, target["frame"]), target["points"])],
                        target["frame"]) if target["points"] else ends["aim"]
    u = (ahead - o) / np.linalg.norm(ahead - o)
    t = Sc.to_local(turret["frame"][0], target["frame"])
    half = 0.5 * float(np.linalg.norm(t - np.clip(t, target["C"] - target["H"], target["C"] + target["H"])))
    step = o + half * u
    origin = target["frame"][0]
    own = {turret["label"]}
    row.update(beam=turret["macro"] in BEAMS, R=FIRE_RANGE.get(turret["macro"]), moving=moving(target),
               reach=float(np.linalg.norm(aim - o)), reach_origin=float(np.linalg.norm(origin - o)),
               step=half, lines={}, x4={})
    for m in models:
        row["x4"][m] = dict(      # X4's view: the firing turret ignored
            first=_hit(scene, turret, target, rank, o, d=(aim - o) / row["reach"], tmax=F_MAX * row["reach"],
                       model=m, skip=own),
            second=_hit(scene, turret, target, rank, o, d=(origin - o) / row["reach_origin"],
                        tmax=F_MAX * row["reach_origin"], model=m, skip=own),
            beam=_hit(scene, turret, target, rank, o, d=z, tmax=EXT, model=m, skip=own))
        row["lines"][m] = dict(   # check_line_of_sight's view: the firing turret seen
            {k: v[0] if v else None for k, v in lines[m].items() if not k.startswith("diag")},
            ext=_hit(scene, turret, target, rank, o, d=u, tmax=EXT, model=m)[:2],
            ext_s=_hit(scene, turret, target, rank, step, d=u, tmax=EXT, model=m)[:2])
    return row


# ---------------------------------------------------------------- truth

def _member(row, sym):
    return sym is not None and B.qualifies(St.TARGET_SYMBOL[row["target_cls"]], sym)


def _same_object(row, sym):
    obj = OBJECT.get(row["target_cls"])
    return obj is not None and sym is not None and obj in B.ancestors(sym)


def permits(row, model, f):
    """X4's pre-fire decision for one model and allowance factor: True, False, or 'tie'."""
    x4 = row["x4"][model]
    if row["beam"]:
        sym, t, tie = x4["beam"]
        if t is None or t > row["R"]:
            return False
        return "tie" if tie is not None and _member(row, tie) != _member(row, sym) else _member(row, sym)
    sym, t, tie = x4["first"]
    if t is None or t > f * row["reach"]:
        return True

    def outcome(s):
        if _member(row, s):
            return True
        if _same_object(row, s):
            s2, t2, tie2 = x4["second"]
            if t2 is None or t2 > f * row["reach_origin"]:
                return False
            ok = s2 == St.TARGET_SYMBOL[row["target_cls"]]
            return "tie" if tie2 is not None and (tie2 == St.TARGET_SYMBOL[row["target_cls"]]) != ok else ok
        return False
    first = outcome(sym)
    return "tie" if tie is not None and outcome(tie) != first else first


def truth(row):
    """PERMIT / NOT, or why X4's decision is excluded (cannot bear, ...) or uncertain."""
    if row["state"] != "SETTLED":
        return row["state"]
    f = 1 + min(1.1 * row["R"], 500.0) / row["R"] if row["moving"] and not row["beam"] else 1.0
    said = {m: permits(row, m, f) for m in row["x4"]}
    if "tie" in said.values():
        return "uncertain: first-hit tie"
    if len(set(said.values())) > 1:
        return "uncertain: shape models disagree"
    if f > 1 and {permits(row, m, 1.0) for m in row["x4"]} != set(said.values()):
        return "uncertain: depends on R"
    return "PERMIT" if said.popitem()[1] else "NOT"


def why(row, model="mesh"):
    """X4's reason, for the breakdowns."""
    x4 = row["x4"][model]
    if row["beam"]:
        sym, t, _ = x4["beam"]
        return "beam: no hit within R" if t is None or t > row["R"] else f"beam: first hit {sym}"
    sym, t, _ = x4["first"]
    if t is None:
        return "no hit (genuine miss)"
    if t > row["reach"]:
        return f"first hit {sym} past the bearing point"
    if not _member(row, sym) and _same_object(row, sym):
        return f"second ray ({x4['second'][0]})"
    return f"first hit {sym}"


# ---------------------------------------------------------------- candidates

def base(row, model):
    """(status, calls, unresolved): the probe, then step and look back; BLOCKED only on a proven non-target
    first hit short of the step point."""
    ln = row["lines"][model]
    if _member(row, ln["aim"]):
        return "C", 1, False
    if ln["qw_half"] == "W":
        ok = _member(row, ln["fwd_half"]) and ln["back_half"] == "W"
        return ("C", 4, False) if ok else ("U", 4, True)
    if ln["qw_half"] is None:                 # nothing short of the step point: Q(Z) false
        return "U", 3, True
    if _member(row, ln["qw_half"]) or _same_object(row, ln["qw_half"]):
        return "U", 3, False
    return "B", 3, False


def extended(row, model):
    """base, then the aimed line continued to EXT from the muzzle, or from the step point when the muzzle's first
    stretch meets only the firing turret and the look back proves it: +1 call Q(T), +1 Q(sector).
    A beam skips the probe: X4 tests its barrel line to R, which the probe's endpoint does not bound. Q(W) to the
    step point (+ the look back), then Q(T) along the line to R decides."""
    ln = row["lines"][model]
    own = ln["qw_half"] == "W"
    if row["beam"]:
        if own and ln["back_half"] != "W":
            return "U", 2
        sym, t = ln["ext_s"] if own else ln["ext"]
        t = None if t is None else t + (row["step"] if own else 0.0)
        return ("C" if t is not None and t <= row["R"] and _member(row, sym) else "B"), 3 if own else 2
    status, calls, open_ = base(row, model)
    if status != "U" or not open_:
        return status, calls
    if own and ln["back_half"] != "W":
        return "U", calls
    sym, t = ln["ext_s"] if own else ln["ext"]
    if _member(row, sym):
        return "C", calls + 1
    return ("C" if t is None else "U"), calls + 2


def with_modules(row, model):
    """base, then production's module lines whenever base leaves the row undecided (station roots only)."""
    status, calls, _ = base(row, model)
    if status != "U" or row["target_cls"] != "station root":
        return status, calls
    s, _r, c = current(row, model)
    return ("C" if s == "C" else "U"), calls + c


def current(row, model):
    return B.candidate(dict(id="physical", target=St.TARGET_SYMBOL[row["target_cls"]],
                            lines={k: [v] if v else [] for k, v in row["lines"][model].items()
                                   if not isinstance(v, list)}), "current")


def status(row, model, method):
    if row["state"] == "GUIDED":
        return "G", 0
    if method == "current":
        s, _r, calls = current(row, model)
        return s, calls
    if method == "base":
        return base(row, model)[:2]
    return (with_modules if method == "base+modules" else extended)(row, model)


# ---------------------------------------------------------------- report

POP = {"broad": "broad population", "sixty": "#60 representative xen_defence poses"}
CLASSES = ("station root", "station surface", "whole ship", "ship surface")


def matrix(rows, method, model="mesh"):
    c, calls = Counter(), []
    for r in rows:
        t = truth(r)
        if r["state"] == "GUIDED":
            c["GUIDED"] += 1
            continue
        if t not in ("PERMIT", "NOT"):
            c["excluded" if not t.startswith("uncertain") else "uncertain"] += 1
            continue
        s, n = status(r, model, method)
        calls.append(n)
        c[{("C", "PERMIT"): "TP", ("C", "NOT"): "FP", ("B", "NOT"): "TN", ("B", "PERMIT"): "FN",
           ("U", "PERMIT"): "U on PERMIT", ("U", "NOT"): "U on NOT"}[s, t]] += 1
    c["mean calls"] = round(sum(calls) / len(calls), 2) if calls else 0
    c["max calls"] = max(calls, default=0)
    return c


COLS = ("TP", "FP", "TN", "FN", "U on PERMIT", "U on NOT", "GUIDED", "uncertain", "excluded", "mean calls",
        "max calls")


def table(say, rows, title, models=("mesh",)):
    say(f"\n### {title} ({len(rows)} tests)\n")
    say("Predicted CLEAR = TP + FP, BLOCKED = TN + FN, UNKNOWN = the two U columns.\n")
    say("| method | model | " + " | ".join(COLS) + " |")
    say("|---|---|" + "---:|" * len(COLS))
    for method in METHODS:
        for m in models:
            c = matrix(rows, method, m)
            say(f"| {method} | {m.upper()} | " + " | ".join(str(c[k]) for k in COLS) + " |")


def report(rows):
    lines, bad = [], []
    say = lines.append
    say(f"# X4 pre-fire permission benchmark ({len(rows)} tests)\n")
    for pop in POP:
        rs = [r for r in rows if r["pop"] == pop]
        say(f"\n## {POP[pop]}\n")
        say("| truth | " + " | ".join(CLASSES) + " |")
        say("|---|" + "---:|" * len(CLASSES))
        truths = Counter((truth(r), r["target_cls"]) for r in rs)
        for t in sorted({t for t, _c in truths}):
            say(f"| {t} | " + " | ".join(str(truths[t, c]) for c in CLASSES) + " |")
        for cls in CLASSES:
            sub = [r for r in rs if r["target_cls"] == cls]
            if sub:
                table(say, sub, f"{cls}, {POP[pop]}", St.MODELS if cls == "station root" else ("mesh",))
    broad = [r for r in rows if r["pop"] == "broad"]
    empty = [r for r in broad if r["target_cls"] == "station root" and r["state"] == "SETTLED"
             and all(r["x4"][m]["first"][1] is None or r["x4"][m]["first"][1] > r["reach"] for m in St.MODELS)]
    say("\n## The station-root rows whose X4 path reaches no geometry\n")
    say(f"{len(empty)} rows (the previously excluded empty-path rows).\n")
    table(say, empty, "empty-path station roots", St.MODELS)
    for method in METHODS:
        c = Counter((status(r, "mesh", method)[0], r["macro"].split("_mk1")[0][7:], r["beam"]) for r in empty)
        say(f"- {method}: " + ", ".join(f"{k[1]}{' (beam)' if k[2] else ''} {k[0]}={v}" for k, v in sorted(c.items())))
    say("\n## Why X4 decides as it does (MESH, scored rows)\n")
    for pop in POP:
        for cls in CLASSES:
            c = Counter((truth(r), why(r)) for r in rows if r["pop"] == pop and r["target_cls"] == cls
                        and truth(r) in ("PERMIT", "NOT"))
            if c:
                say(f"- {POP[pop]}, {cls}: " + "; ".join(f"{t} {w}: {n}" for (t, w), n in sorted(c.items())))
    say("\n## Errors by first hit of the MD probe (MESH)\n")
    for method in METHODS:
        errs = Counter()
        for r in rows:
            t = truth(r)
            if t in ("PERMIT", "NOT"):
                s, _n = status(r, "mesh", method)
                if (s, t) in (("C", "NOT"), ("B", "PERMIT")):
                    errs[r["pop"], r["target_cls"], "FP" if s == "C" else "FN", r["lines"]["mesh"]["aim"],
                         why(r)] += 1
        say(f"- {method}: " + ("; ".join(f"{k}: {v}" for k, v in sorted(errs.items(), key=str)) or "none"))
    uncertain = Counter((r["pop"], r["target_cls"], truth(r)) for r in rows if truth(r).startswith("uncertain"))
    say("\n## Uncertain truth\n")
    for k, v in sorted(uncertain.items()):
        say(f"- {k[0]}, {k[1]}: {k[2]}: {v}")
    # integrity: wherever base+ext claims a miss, the extended line reaches past X4's own endpoint
    for r in rows:
        if r["state"] != "SETTLED" or r["beam"] or status(r, "mesh", "base+ext")[0] != "C":
            continue
        own = r["lines"]["mesh"]["qw_half"] == "W"
        if (r["lines"]["mesh"]["ext_s" if own else "ext"][1] is None
                and (1 + min(1.1 * r["R"], 500.0) / r["R"] if r["moving"] else 1.0) * r["reach"] > EXT):
            bad.append(f"{r['scene']} {r['turret']} {r['target']}: miss claimed short of X4's endpoint")
    far = sum(r["state"] == "SETTLED" and r["reach"] > EXT / F_MAX for r in rows)
    say(f"\nRows whose bearing point lies beyond EXT / F_MAX: {far}.")
    if not rows or not any(r["pop"] == "sixty" for r in rows):
        bad.append("missing population")
    say("\n## Integrity\n")
    say("PASS" if not bad else "FAIL\n- " + "\n- ".join(bad[:20]))
    return "\n".join(lines), bad


# ---------------------------------------------------------------- run

def run(out):
    St.check_settling()
    ships, ctx = St.context()
    St.check_kinematics(ctx)
    n, t0 = 0, time.time()
    scenes = list(St.anchor_scenes(ctx["records"])) + list(St.broad_scenes(ships, ctx))
    for i, scene in enumerate(scenes):
        for turret in scene.turrets:
            for target in scene.targets:
                for start in St.START_YAWS:
                    out.write(json.dumps(dict(test(scene, turret, target, start, ctx), pop="broad"),
                                         separators=(",", ":"), default=float) + "\n")
                    n += 1
        print(f"[{i + 1}/{len(scenes)}] {scene.name}: {n} tests, {time.time() - t0:.0f} s", flush=True)
    for k, yaw in St.SIXTY_POSES.values():
        sc, root = St.sixty_scene(k, yaw)
        for turret in sc.turrets:
            out.write(json.dumps(dict(test(sc, turret, root, 0.0, ctx), pop="sixty"), separators=(",", ":"),
                                 default=float) + "\n")


def main():
    if "--report" not in sys.argv:
        OUT.parent.mkdir(parents=True, exist_ok=True)
        with gzip.open(OUT, "wt") as stream:
            run(stream)
    with gzip.open(OUT, "rt") as stream:
        text, bad = report([json.loads(line) for line in stream])
    print(text)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
