"""Issue #202: how often CLEAR LINE OF FIRE (guarded full, production d95e607) is likely wrong or UNKNOWN in
vanilla X4 9.00 and Star Wars Interworlds (SWI) 0.9.1 HF, and what would fix it.

1. `census`: static inventory per game. Ship components and macros (the #184 census rows), surface-element
   component types (turret, missile turret, shield, engine) with their authored aim points and whether the
   point X4 bears on lies inside the element's own collision body, beam turrets, and element instances in
   the shipped loadouts.
2. `sample`: a few hundred targeted settled tests on the susceptible SWI whole-ship families, scored with
   `permission.py`'s truth and a model of the production MD, beside the saved vanilla rows.

    python3 research/issue202-line-of-fire/susceptibility.py census    # < 2 min
    nice python3 research/issue202-line-of-fire/susceptibility.py sample    # a few minutes

SWI files are read in place from the owner's local copy; nothing is extracted into the repository.
"""
from __future__ import annotations

import json
import math
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

import permission as P
import settled as St
from settled import Gm, Sc

S = Sc.S
SWI_DIR = Path("/mnt/c/Users/PC/Documents/temp_swi_location/starwarsmod_m1_091hf/starwarsmod_m1")
CACHE = St.ROOT / ".x4-research-cache/issue202-susceptibility"
KINDS = {"turret": "turret", "missileturret": "turret", "shieldgenerator": "shield", "engine": "engine"}
LARGE = Sc.LARGE_TARGET_RADIUS


_jcs = Gm.jcs_hulls


def _jcs_or_empty(data):
    """SWI's `-hull.jcs` (built for X4 8.00) does not parse as a 9.00 ConvexHullShape; such parts get an
    empty HULL model, so SWI is scored on the MESH model only."""
    try:
        return _jcs(data)
    except Exception:                                   # noqa: BLE001
        return [(np.zeros((1, 3)), np.array([[0.0, 0.0, 0.0, 1.0]]))]


def add_swi_catalogs():
    """SWI's catalogs after the game's, as X4 loads an extension: its collision files resolve too."""
    Gm.jcs_hulls = _jcs_or_empty
    index = Gm._catalog()
    for cat in sorted(SWI_DIR.glob("*.cat")):
        offset = 0
        for line in open(cat, encoding="utf-8", errors="replace"):
            path, size, _stamp, _md5 = line.rstrip("\n").rsplit(" ", 3)
            index[path.lower()] = (str(cat)[:-4] + ".dat", offset, int(size))
            offset += int(size)


def index_swi():
    import aimpoint_map as am
    am._index_swi_ships()


def swi_version():
    root = ET.parse(SWI_DIR / "content.xml").getroot()
    return f"{root.get('description')} (content.xml version {root.get('version')}, {root.get('date')})"


# ---------------------------------------------------------------- ships (#184 census rows)

def ship_rows(game):
    return [json.loads(line) for line in open(St.ROOT / f".x4-research-cache/issue184/a44_census_{game}.jsonl")]


def ship_flags(row):
    radius = math.sqrt(sum(h * h for h in row["H"])) if row.get("H") else 0.0
    n, pts = row["n_points"], row["points"]
    flags = []
    if n == 0 and radius > LARGE:
        flags.append("large target, no aim point")
    if n == 1 and all(abs(v) < 1e-4 for v in pts[0]):
        flags.append("single aim point at origin")
    if n >= 2:
        flags.append("several aim points")
    if any(abs(x) > 1 for p in row.get("norm") or [] for x in p):
        flags.append("aim point outside box")
    return flags


# ---------------------------------------------------------------- surface elements

def _points(comp):
    out = []
    for c in S.connections(comp).values():
        if "aimtarget" in S.tags(c):
            pos = c.find("offset/position")
            out.append(np.array([float(pos.get(a, 0)) if pos is not None else 0.0 for a in "xyz"]))
    return out


def element_types(game):
    """{component: dict(kind, macros, points, flags)} of one game's surface-element components."""
    out = {}
    for name, defs in sorted(S.MACROS.items()):
        rel, m = defs[0]
        if (game == "swi") != rel.startswith("swi/") or KINDS.get(m.get("class")) is None:
            continue
        if m.find("component") is None:
            continue
        comp_name = m.find("component").get("ref")
        try:
            comp = S.component(comp_name)
        except S.StudyError:
            continue
        entry = out.setdefault(comp_name, dict(kind=KINDS[m.get("class")], macros=[], flags=[]))
        entry["macros"].append(name)
        if len(entry["macros"]) > 1:
            continue
        pts = _points(comp)
        try:
            b = Gm.body(comp_name)
        except Exception:                       # noqa: BLE001 - unreadable collision counts as none
            b = None
        entry["points"] = len(pts)
        if b is None:
            entry["flags"].append("no collision body")
            continue
        C, _H = Sc.box(name)
        bear = pts if pts else [C]
        if len(pts) == 1 and np.allclose(pts[0], 0, atol=1e-4):
            entry["flags"].append("single aim point at origin")
        if len(pts) > 1:
            entry["flags"].append("several aim points")
        if not all(Gm.inside(b, p, "mesh") or (game == "vanilla" and Gm.inside(b, p, "hull")) for p in bear):
            entry["flags"].append("aim point off its own collision")
    return out


def beam_turrets(game):
    """Turret macros whose bullet is attached to the weapon (`attach="1"`): the source signature of X4's
    beams (inference: the loader field behind `isbeam` was not traced to this attribute)."""
    out, total = [], 0
    for name, defs in sorted(S.MACROS.items()):
        rel, m = defs[0]
        if (game == "swi") != rel.startswith("swi/") or m.get("class") != "turret":
            continue
        total += 1
        bullet = m.find("properties/bullet")
        try:
            bm = S.macro(bullet.get("class")) if bullet is not None else None
        except S.StudyError:
            bm = None
        props = bm.find("properties/bullet") if bm is not None else None
        if props is not None and props.get("attach") == "1":
            out.append(name)
    return out, total


def _catalog_files(path, cats):
    """The bytes of `path` in each catalog that ships it (not only the last one, as Gm.read gives)."""
    out = []
    for cat in cats:
        offset = 0
        for line in open(cat, encoding="utf-8", errors="replace"):
            name, size, _stamp, _md5 = line.rstrip("\n").rsplit(" ", 3)
            if name.lower() == path:
                with open(str(cat)[:-4] + ".dat", "rb") as stream:
                    stream.seek(offset)
                    out.append(stream.read(int(size)))
            offset += int(size)
    return out


def loadout_counts(game):
    """Element macro references in the shipped loadouts. These are scripted loadouts only: X4 equips most
    NPC ships procedurally, so they are not an installed-instance census."""
    cats = (sorted(SWI_DIR.glob("*.cat")) if game == "swi" else
            sorted(Gm.X4.glob("*.cat")) + sorted(Gm.X4.glob("extensions/ego_*/*.cat")))
    counts = Counter()
    for data in _catalog_files("libraries/loadouts.xml", [c for c in cats if not str(c).endswith("_sig.cat")]):
        for tag in ("engine", "shield", "turret"):
            for m in ET.fromstring(data.decode("utf-8", "replace")).iter(tag):
                if m.get("macro"):
                    counts[m.get("macro")] += 1
    return counts


def slot_counts(rows):
    """Turret, shield and engine mount slots over one macro per ship component (exposure, not installs)."""
    out = Counter()
    for r in rows:
        try:
            comp = S.component(r["component"])
        except S.StudyError:
            continue
        for conn in S.connections(comp).values():
            kind = Sc.slot_kind(S.tags(conn))
            if kind and "component" not in S.tags(conn):
                out[kind] += 1
    return out


def census():
    lines = [f"# Susceptibility census\n\nSWI: {swi_version()}, `{SWI_DIR}`\n"]
    say = lines.append
    games = {}
    games["vanilla"] = dict(elements=element_types("vanilla"), beams=beam_turrets("vanilla"),
                            loadouts=loadout_counts("vanilla"))
    add_swi_catalogs()
    index_swi()
    games["swi"] = dict(elements=element_types("swi"), beams=beam_turrets("swi"), loadouts=loadout_counts("swi"))
    for game in ("vanilla", "swi"):
        rows = ship_rows(game)
        flags = Counter(f for r in rows for f in ship_flags(r))
        by_class = Counter(r["ship_class"][0] for r in rows)
        say(f"\n## {game}\n")
        say(f"Ship components {len(rows)}, macros {sum(len(r['macros']) for r in rows)}; "
            f"by class {dict(sorted(by_class.items()))}")
        for f, n in sorted(flags.items()):
            members = [r["component"] for r in rows if f in ship_flags(r)]
            say(f"- {f}: {n} components ({100 * n / len(rows):.0f} %): " + ", ".join(members[:60]))
        els = games[game]["elements"]
        kinds = Counter(e["kind"] for e in els.values())
        say(f"\nElement components {len(els)} {dict(sorted(kinds.items()))}; "
            f"macros {sum(len(e['macros']) for e in els.values())}")
        for kind in sorted(kinds):
            sub = {n: e for n, e in els.items() if e["kind"] == kind}
            fl = Counter(f for e in sub.values() for f in e["flags"])
            pts = Counter(min(e.get("points", 0), 2) for e in sub.values())
            say(f"- {kind}: {len(sub)} types; aim points 0/1/2+: {pts[0]}/{pts[1]}/{pts[2]}; "
                + "; ".join(f"{f} {n}" for f, n in sorted(fl.items())))
            for f in sorted(fl):
                say(f"  - {f}: " + ", ".join(sorted(n for n, e in sub.items() if f in e["flags"]))[:1500])
        say(f"\nMount slots over all ship components: {dict(sorted(slot_counts(rows).items()))}")
        beams, total = games[game]["beams"]
        say(f"\nBeam turret macros: {len(beams)} of {total}: " + ", ".join(beams))
        counts = games[game]["loadouts"]
        if counts:
            by_macro = {m: n for n, e in els.items() for m in e["macros"]}
            installed = Counter()
            for macro, n in counts.items():
                comp = by_macro.get(macro)
                if comp is None:
                    continue
                e = els[comp]
                installed[e["kind"], "all"] += n
                for f in e["flags"]:
                    installed[e["kind"], f] += n
                if macro in beams:
                    installed["turret", "beam"] += n
            say("\nElement references in scripted loadouts: " + "; ".join(
                f"{k} {f} {n}" for (k, f), n in sorted(installed.items())))
    text = "\n".join(lines)
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE / "census.md").write_text(text)
    print(text)


# ---------------------------------------------------------------- targeted sample

OUT = CACHE / "sample.jsonl.gz"
BEAM_OUT = CACHE / "beams.jsonl.gz"
METHODS = ("production", "exact endpoint", "origin metadata", "large-target metadata", "large-target dual check",
           "large-target conditional dual", "both", "ideal")


def _aim_points(macro):
    """Sc.aim_points, but an aim connection without an offset is at the component origin (SWI authors 47)."""
    return _points(S.component(Sc.comp_of(macro)))


def hosts():
    """(game, ship macro, why) chosen by fixed rules from the census, before any scoring."""
    out = []
    lt = sorted((r for r in ship_rows("vanilla") if "large target, no aim point" in ship_flags(r)),
                key=lambda r: math.dist(r["H"], (0, 0, 0)))
    out += [("vanilla", lt[i]["macros"][0], "large target, radius rank %d of 36" % i) for i in (0, 9, 18, 27)]
    swi = [r for r in ship_rows("swi") if r.get("H")]
    for flag, fractions in (("single aim point at origin", (0, 0.5, 1)), ("aim point outside box", (0, 1)),
                            ("several aim points", (0, 0.5, 1)), ("large target, no aim point", (0,))):
        taken = {m for _g, m, _w in out}
        rows = sorted((r for r in swi if flag in ship_flags(r) and r["macros"][0] not in taken),
                      key=lambda r: math.dist(r["H"], (0, 0, 0)))
        out += [("swi", rows[round(f * (len(rows) - 1))]["macros"][0], flag) for f in fractions]
    return out


def _cast(scene, turret, target, rank, a, b=None, d=None, tmax=None, model="mesh", skip=()):
    return P._hit(scene, turret, target, rank, a, e=b, d=d, tmax=tmax, model=model, skip=skip)[:2]


def line_set(scene, turret, target, rank, o, point, md_end, half, models):
    """check_line_of_sight's lines along the direction from the muzzle `o` to `point`: the step point, the
    look back, forward to `md_end` (the probe endpoint), and the aimed line continued (distance kept)."""
    u = (point - o) / np.linalg.norm(point - o)
    step = o + half * u
    out = {}
    for m in models:
        out[m] = dict(qw=_cast(scene, turret, target, rank, o, step, model=m)[0],
                      back=_cast(scene, turret, target, rank, step, o, model=m)[0],
                      fwd=_cast(scene, turret, target, rank, step, md_end, model=m)[0],
                      ext=_cast(scene, turret, target, rank, o, d=u, tmax=P.EXT, model=m),
                      ext_s=_cast(scene, turret, target, rank, step, d=u, tmax=P.EXT, model=m))
    return out


def sample_test(scene, turret, target, ctx, models):
    """One settled test: X4's truth (permission.py) and the lines each method needs."""
    row = P.test(scene, turret, target, 0.0, ctx, models)
    if row["state"] != "SETTLED":
        return row
    record = ctx["records"][turret["key"]]
    aim, source, _i = St.bearing_point(scene, turret, target)
    pt = tuple(float(v) for v in Sc.to_local(aim, turret["frame"]))
    _state, y, x = St.settle(record, ctx["turs"][turret["macro"]], pt, 0.0)
    o = St._muzzles(ctx["evs"][turret["macro"]], record["endpoint"]["tag"], x, y, turret["frame"])[0][0]
    rank = St.module_rank(scene, target)
    md_end = St.endpoints(scene, turret, target, o, rank)["aim"]      # the useaimtarget probe's endpoint
    centre = Sc.to_world(target["C"], target["frame"])
    pts, f = target["points"], target["frame"]
    t = Sc.to_local(turret["frame"][0], f)
    half = 0.5 * float(np.linalg.norm(t - np.clip(t, target["C"] - target["H"], target["C"] + target["H"])))
    comp = Sc.comp_of(target["macro"])
    radius = float(np.linalg.norm(target["H"]))
    origin_point = len(pts) == 1 and np.allclose(pts[0], 0, atol=1e-4)
    if not pts or origin_point:                   # useaimtarget true == false: production aims at the box
        prod = centre
        amb = (not pts and target["cls"] == "whole ship" and radius > LARGE) or comp in P.ORIGIN_AIM
    else:
        near_muzzle = St._select(Sc.to_local(o, f), pts)
        prod = Sc.to_world(pts[near_muzzle], f)
        amb = near_muzzle != St._select(t, pts)
    row.update(points_n=len(pts), origin_point=bool(origin_point), large=not pts and target["cls"] == "whole ship"
               and radius > LARGE, amb=bool(amb), aim_source=source, game=scene.info.get("game"),
               lines_prod=line_set(scene, turret, target, rank, o, prod, md_end, half, models),
               lines_true=line_set(scene, turret, target, rank, o, aim, aim, half, models),
               probe_true={m: _cast(scene, turret, target, rank, o, aim, model=m)[0] for m in models})
    if row["large"]:        # X4's LargeTarget offset point, whether or not X4 keeps it (script-computable)
        Cf, Hf = Sc.box(scene.firing["ship"])
        off = Sc.to_world(target["C"] + (turret["origin_ship"] - Cf) / Hf * target["H"] * St.LT_SCALE, f)
        row.update(lines_offset=line_set(scene, turret, target, rank, o, off, off, half, models),
                   probe_offset={m: _cast(scene, turret, target, rank, o, off, model=m)[0] for m in models})
    return row


def known_endpoint(row):
    """Distance from the muzzle to X4's aim point as the production MD can know it, or None. MD takes it as
    the dot product of the muzzle-to-point offset with the unit `rotation.forward` it already builds
    (`.length` and `distanceto` are approximate, about 7e-4). It needs an
    established direction (not ambiguous) toward the point X4 bears on: a no-collection target's live box
    centre, or an authored point both orientations select. A single authored point at the origin is read
    as no collection and aimed at the box centre, so its endpoint is not knowable."""
    if row["amb"] or row.get("origin_point"):
        return None
    return row["reach"]


def md_status(row, model, method):
    """(status, rays) of the production MD (guarded full), with the method's direction and ambiguity."""
    if row["state"] == "GUIDED":
        return "G", 0
    if method == "large-target dual check" and row["large"]:
        # both script-computable candidates, the box centre and the offset point; only agreement decides
        a, na = md_status(dict(row, large=False, amb=False), model, "production")
        b, nb = md_status(dict(row, large=False, amb=False, lines_prod=row["lines_offset"],
                               lines=dict(row["lines"], **{model: dict(row["lines"][model],
                                                                        aim=row["probe_offset"][model])})),
                          model, "production")
        return (a if a == b else "U"), na + nb
    if method == "large-target conditional dual" and row["large"]:
        # the guarded check first (probe only); the dual check only when it leaves UNKNOWN. A non-beam
        # dual's centre chain starts with that same probe, so the probe is not cast twice.
        a, na = md_status(row, model, "production")
        if a != "U":
            return a, na
        b, nb = md_status(row, model, "large-target dual check")
        return b, na + nb - (0 if row["beam"] else 1)
    member = lambda sym: P._member(row, sym)                          # noqa: E731
    fixed_lt = method in ("large-target metadata", "both", "ideal") and row["large"]
    fixed_origin = method in ("origin metadata", "both", "ideal") and row["origin_point"]
    true_lines = fixed_lt or fixed_origin or method == "ideal"
    amb = row["amb"] and not (fixed_lt or fixed_origin or method == "ideal")
    ln = (row["lines_true"] if true_lines else row["lines_prod"])[model]
    probe = (row["probe_true"][model] if fixed_lt else row["lines"][model]["aim"])
    bound, R, beam, rays = row["bound"], row["R"], row["beam"], 0
    if amb:                         # a beam casts the probe only when its aim point is surely within R
        cast = not beam or bound <= R
        return ("C" if cast and member(probe) else "U"), int(cast)
    own = ln["qw"] == "W"
    if beam:
        if own and ln["back"] != "W":
            return "U", 2
        sym, t = ln["ext_s"] if own else ln["ext"]
        t = None if t is None else t + (row["step"] if own else 0.0)
        return ("C" if t is not None and t <= R and member(sym) else "B"), (3 if own else 2)
    rays += 1
    if member(probe):
        return "C", rays
    rays += 1
    if own:
        rays += 1
        if ln["back"] != "W":
            return "U", rays
        rays += 1
        if member(ln["fwd"]):
            return "C", rays
    elif ln["qw"] is not None:
        rays += 2
        return ("U" if member(ln["qw"]) or P._same_object(row, ln["qw"]) else "B"), rays
    else:
        rays += 1
    known = known_endpoint(row) if method == "exact endpoint" else None
    if known is None:
        length = (1 + min(1.1 * R, 500.0) / R) * bound * 1.001 + 1.0 - (row["step"] if own else 0.0)
    else:                           # X4's own endpoint: f is 1 unless the target can move
        f = 1 + min(1.1 * R, 500.0) / R if row["moving"] else 1.0
        # in-game positions and MD arithmetic are lower precision than this model; the margin is
        # conservative (a longer line sees more) and, in every cached row, far below the 5.5 m gap
        length = f * known * 1.0001 + 1.0 - (row["step"] if own else 0.0)
    sym, t = ln["ext_s"] if own else ln["ext"]
    if t is not None and t > length:
        sym, t = None, None
    rays += 1
    if member(sym):
        return "C", rays
    rays += 1
    return ("C" if t is None else "U"), rays


def sample():
    import gzip
    add_swi_catalogs()
    index_swi()
    Sc.aim_points = _aim_points
    ships, ctx = St.context()
    for s in ships:
        s["variants"] = s["variants"][:1]                             # loadout A only
    CACHE.mkdir(parents=True, exist_ok=True)
    n = 0
    with gzip.open(OUT, "wt") as out:
        for h, (game, name, why) in enumerate(hosts()):
            models = St.MODELS if game == "vanilla" else ("mesh",)
            _sc, targets, _C, _H = St._posed(name, "ship", np.eye(3), True)
            multi = next((t for t in targets if len(t["points"]) > 1), None)
            pair = None
            if multi is not None:
                M, u, v = Sc.nearest_pair(multi["points"])
                pair = (Sc.to_world(M, multi["frame"]), u @ multi["frame"][1], v @ multi["frame"][1])
            for gap in ("ordinary", "boundary"):                      # 1,500 m and a close 300 m
                saved = Sc.GAPS["ordinary"]
                Sc.GAPS["ordinary"] = Sc.GAPS[gap]
                for v, view in enumerate(Sc.views(pair)):
                    if gap == "boundary" and view[0] != "ordinary":
                        continue
                    for scene in St._view_scenes(name, "ship", True, h, v, view, pair, ships, ctx, why):
                        scene.info.update(game=game, gap=gap)
                        for turret in scene.turrets:
                            for target in scene.targets:
                                row = sample_test(scene, turret, target, ctx, models)
                                row.update(game=game, host=name, why=why, gap=gap, view=scene.info["view"])
                                out.write(json.dumps(row, separators=(",", ":"), default=float) + "\n")
                                n += 1
                Sc.GAPS["ordinary"] = saved
            print(f"[{h + 1}] {game} {name}: {n} tests", flush=True)


# ---------------------------------------------------------------- report

def _cell(counter, keys):
    return " | ".join(str(counter[k]) for k in keys)


OUTCOMES = ("TP", "FP", "TN", "FN", "U on PERMIT", "U on NOT")


def outcome(status, truth):
    return {("C", "PERMIT"): "TP", ("C", "NOT"): "FP", ("B", "NOT"): "TN", ("B", "PERMIT"): "FN",
            ("U", "PERMIT"): "U on PERMIT", ("U", "NOT"): "U on NOT"}[status, truth]


def why_unknown(row, model="mesh"):
    """The production MD's reason for an UNKNOWN (guarded full, saved permission rows)."""
    ln = row["lines"][model]
    if row.get("ambiguous") and row["target_cls"] != "station root":
        return "aim direction ambiguous"
    if ln["qw_half"] == "W":
        return "own socket, look back fails" if ln["back_half"] != "W" else "extended line from step meets other"
    if ln["qw_half"] is not None:
        return "target or own parent before step"
    return "extended line meets other"


def report():
    import gzip
    lines = [(CACHE / "census.md").read_text(), "\n# Frequency\n"]
    say = lines.append
    saved = [json.loads(x) for x in gzip.open(P.OUT, "rt")]
    P.mark_ambiguous(saved)
    say("## Saved vanilla benchmark rows, production (guarded full), MESH\n")
    say("| target class | view | " + " | ".join(OUTCOMES) + " |")
    say("|---|---|" + "---:|" * len(OUTCOMES))
    cells, causes = Counter(), Counter()
    for r in saved:
        t = P.truth(r)
        if r["state"] != "SETTLED" or t not in ("PERMIT", "NOT"):
            continue
        gap = "#60 pose" if r["pop"] == "sixty" else r["scene"].split(":")[1].split("/")[0]
        o = outcome(P.status(r, "mesh", "guarded full")[0], t)
        cells[r["target_cls"], gap, o] += 1
        if o.startswith("U"):
            causes[r["target_cls"], o, why_unknown(r)] += 1
    for cls, gap in sorted({k[:2] for k in cells}):
        say(f"| {cls} | {gap} | " + _cell(cells, [(cls, gap, o) for o in OUTCOMES]) + " |")
    say("\nUNKNOWN by cause: " + "; ".join(f"{c} {o} {w}: {n}" for (c, o, w), n in sorted(causes.items())))
    if OUT.exists():
        rows = [json.loads(x) for x in gzip.open(OUT, "rt")]
        say(f"\n## Targeted sample ({len(rows)} tests)\n")
        say("MESH model. Truth: permission.py. Uncertain truth and CANNOT BEAR are excluded.\n")
        excluded = Counter((r["game"], r["why"], r["state"] if r["state"] != "SETTLED" else P.truth(r))
                           for r in rows if r["state"] != "SETTLED" or P.truth(r) not in ("PERMIT", "NOT"))
        for method in METHODS:
            say(f"\n### {method}\n")
            say("| game | host family | target | gap | " + " | ".join(OUTCOMES) + " | mean / max rays |")
            say("|---|---|---|---|" + "---:|" * (len(OUTCOMES) + 1))
            cells, rays = Counter(), defaultdict(list)
            for r in rows:
                t = P.truth(r)
                if r["state"] != "SETTLED" or t not in ("PERMIT", "NOT"):
                    continue
                st, n = md_status(r, "mesh", method)
                key = (r["game"], r["why"], r["target_cls"], r["gap"])
                cells[key + (outcome(st, t),)] += 1
                rays[key].append(n)
            for key in sorted({k[:4] for k in cells}):
                say(f"| {' | '.join(key)} | " + _cell(cells, [key + (o,) for o in OUTCOMES])
                    + f" | {sum(rays[key]) / len(rays[key]):.2f} / {max(rays[key])} |")
        say("\nExcluded: " + "; ".join(f"{g} {w} {s}: {n}" for (g, w, s), n in sorted(excluded.items())))
    text = "\n".join(lines)
    (CACHE / "report.md").write_text(text)
    print(text)


def beams():
    """Supplement: the benchmark's only beam turret (L2 loadout carrying `kha_m_beam_01`) against the four
    vanilla large-target hosts, whole-ship targets only. 16 scenes."""
    import gzip
    ships, ctx = St.context()
    l2 = next(s for s in ships if s["tag"] == "L2")
    l2["variants"] = [v for v in l2["variants"] if any(P.BEAMS & {ctx["records"][k]["macro"] for k in v[1].values()})][:1]
    n = 0
    with gzip.open(BEAM_OUT, "wt") as out:
        for h, (game, name, why) in enumerate(hosts()[:4]):
            for gap in ("ordinary", "boundary"):
                saved = Sc.GAPS["ordinary"]
                Sc.GAPS["ordinary"] = Sc.GAPS[gap]
                for v, view in enumerate(Sc.views(None)):
                    for scene in St._view_scenes(name, "ship", True, h, v, view, None, [l2], ctx, why):
                        scene.info.update(game=game, gap=gap)
                        for turret in scene.turrets:
                            if turret["macro"] not in P.BEAMS:
                                continue
                            row = sample_test(scene, turret, scene.targets[0], ctx, St.MODELS)
                            row.update(game=game, host=name, why=why, gap=gap, view=scene.info["view"])
                            out.write(json.dumps(row, separators=(",", ":"), default=float) + "\n")
                            n += 1
                Sc.GAPS["ordinary"] = saved
    print(f"{n} beam tests")


def compare():
    """Large-target whole-ship rows of the saved sample: production, always-dual and conditional dual."""
    import gzip
    rows = [json.loads(x) for x in gzip.open(OUT, "rt")]
    rows += [json.loads(x) for x in gzip.open(BEAM_OUT, "rt")] if BEAM_OUT.exists() else []
    rows = [r for r in rows if r["state"] == "SETTLED" and r.get("large") and P.truth(r) in ("PERMIT", "NOT")]
    methods = ("production", "large-target dual check", "large-target conditional dual")
    lines = [f"Large-target whole-ship rows, sample, MESH: {len(rows)} scored "
             f"({sum(r['beam'] for r in rows)} beam)\n",
             "| method | turrets | " + " | ".join(OUTCOMES) + " | mean rays | observed max | theoretical max |",
             "|---|---|" + "---:|" * (len(OUTCOMES) + 3)]
    theory = {"production": (1, 1), "large-target dual check": (12, 6), "large-target conditional dual": (12, 7)}
    for method in methods:
        for label, beam in (("non-beam", False), ("beam", True)):
            sub = [r for r in rows if r["beam"] == beam]
            if not sub:
                continue
            res = [md_status(r, "mesh", method) for r in sub]
            c = Counter(outcome(st, P.truth(r)) for (st, _n), r in zip(res, sub))
            n = [x for _s, x in res]
            say_max = theory[method][beam]
            lines.append(f"| {method} | {label} | " + " | ".join(str(c[o]) for o in OUTCOMES)
                         + f" | {sum(n) / len(n):.2f} | {max(n)} | {say_max} |")
    # where the conditional accepts the first-probe CLEAR, does always-dual say otherwise?
    diff = Counter()
    for r in rows:
        first = md_status(r, "mesh", "production")[0]
        dual = md_status(r, "mesh", "large-target dual check")[0]
        if first == "C" and dual != "C":
            diff[r["host"], "beam" if r["beam"] else "non-beam", dual, P.truth(r)] += 1
    lines.append("\nFirst-probe CLEAR where always-dual disagrees: "
                 + ("; ".join(f"{k}: {v}" for k, v in sorted(diff.items())) or "none"))
    runs = Counter()
    for r in rows:
        probe_decides = md_status(r, "mesh", "production")[0] != "U"
        runs["turrets"] += 1
        runs["dual runs (conditional)"] += not probe_decides
    lines.append(f"Dual evaluation needed by the conditional variant: {runs['dual runs (conditional)']} of "
                 f"{runs['turrets']} turret results")
    # non-ray work: the 4-orientation collection test runs for a beam, or after a non-beam probe fails;
    # the always-dual variant must run it for every turret to know the target is a large-target one
    guarded = sum(r["beam"] or md_status(r, "mesh", "production")[0] == "U" for r in rows)
    lines.append(f"Turrets running the 4-orientation test and needing the target box: production and "
                 f"conditional {guarded} of {len(rows)}; always-dual {len(rows)} of {len(rows)}")
    text = "\n".join(lines)
    print(text)
    return text


def _as_sample(r):
    """A saved permission.py row in md_status's shape; its benchmark direction is production's."""
    ln = {m: dict(qw=v["qw_half"], back=v["back_half"], fwd=v["fwd_half"], ext=v["ext"], ext_s=v["ext_s"])
          for m, v in r["lines"].items()}
    return dict(r, lines_prod=ln, lines_true=ln, probe_true={m: v["aim"] for m, v in r["lines"].items()},
                amb=bool(r.get("ambiguous")) and r["target_cls"] != "station root", large=False,
                origin_point=False, game="vanilla", source="saved")


def shot(row):
    """'off-mesh' when X4's own line reaches the aim point without meeting the target, else 'ordinary'."""
    why = P.why(row)
    return "off-mesh" if why.startswith("no hit") or "past the bearing point" in why else "ordinary"


def endpoint():
    """The exact-endpoint miss check against production on every cached row (MESH)."""
    import gzip
    saved = [json.loads(x) for x in gzip.open(P.OUT, "rt")]
    P.mark_ambiguous(saved)
    rows = [_as_sample(r) for r in saved if r["state"] == "SETTLED"]
    rows += [dict(json.loads(x), source="sample") for x in gzip.open(OUT, "rt")]
    rows += [dict(json.loads(x), source="beam supplement") for x in gzip.open(BEAM_OUT, "rt")]
    rows = [r for r in rows if r["state"] == "SETTLED" and P.truth(r) in ("PERMIT", "NOT")]
    cells, rays, changes, exceptions = Counter(), defaultdict(list), Counter(), Counter()
    for r in rows:
        key = (r["source"], r["game"], r["target_cls"], shot(r), "beam" if r["beam"] else "non-beam")
        t = P.truth(r)
        a, na = md_status(r, "mesh", "production")
        b, nb = md_status(r, "mesh", "exact endpoint")
        cells[key + ("production", outcome(a, t))] += 1
        cells[key + ("exact", outcome(b, t))] += 1
        rays[key + ("production",)].append(na)
        rays[key + ("exact",)].append(nb)
        if a != b:
            changes[key + (outcome(a, t), outcome(b, t))] += 1
        if a == "U" and not r["beam"] and known_endpoint(r) is None:
            exceptions[r["source"], r["game"], r["target_cls"], "large target" if r.get("large") else
                       "authored point at origin" if r.get("origin_point") else "ambiguous direction",
                       outcome(a, t)] += 1
    lines = ["| source | game | target | X4 shot | turret | method | " + " | ".join(OUTCOMES)
             + " | mean / max rays |", "|---|---|---|---|---|---|" + "---:|" * (len(OUTCOMES) + 1)]
    for key in sorted({k[:5] for k in cells}):
        for m in ("production", "exact"):
            n = rays[key + (m,)]
            lines.append("| " + " | ".join(key) + f" | {m} | "
                         + " | ".join(str(cells[key + (m, o)]) for o in OUTCOMES)
                         + f" | {sum(n) / len(n):.2f} / {max(n)} |")
    lines.append("\nChanged results: " + ("; ".join(f"{k}: {v}" for k, v in sorted(changes.items())) or "none"))
    lines.append("\nProduction UNKNOWN whose endpoint the mod cannot know (kept on the bound): "
                 + ("; ".join(f"{k}: {v}" for k, v in sorted(exceptions.items())) or "none"))
    text = "\n".join(lines)
    print(text)
    return text


if __name__ == "__main__":
    {"census": census, "sample": sample, "beams": beams, "report": report, "compare": compare,
     "endpoint": endpoint}[sys.argv[1]]()
