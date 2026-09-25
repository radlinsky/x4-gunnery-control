"""Issue #202: selected-target CLEAR LINE OF FIRE decision-rule regression tests.

Scenes state the ordered first hits along each tested line; they are hand-written
arrangements, not X4 physics, so they check decision rules and are outside the
physical accuracy totals (those come from `settled.py` on real collision geometry,
which reuses `candidate()` below). Truth here applies #202's membership rules to
the stated hits on each tested line. Candidates are a model of the production MD
cue (structurally checked against md/x4_gunnery_control.xml so it cannot drift
silently), the proposed seven-point surface scan, and `eight` (seven plus the old
centre). Query counts are simulated `check_line_of_sight` calls, not X4 frame cost.

    python3 research/issue202-line-of-fire/benchmark.py [--population]
"""
from __future__ import annotations

import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# ---------------------------------------------------------------- world
# Physical parent links. Z zone; S firing ship with turret W and siblings;
# P target ship; ST target station (M1..M4 operational, MC construction);
# the rest are unrelated bodies. Elements own no body: their meshes are
# sub-shapes of the owning ship/module body (native inference).
PARENT = dict(
    S="Z", W="S", W2="S", SSH="S", SEN="S",
    P="Z", T="P", T2="P", PSH="P", PEN="P",
    ST="Z", M1="ST", M2="ST", M3="ST", M4="ST", MC="ST", MT="M1", MT2="M1", MS="M2", MT3="M3",
    DK="P", DKS="M1",                      # craft docked on the target ship / module
    F="Z", X="Z", A="Z", WR="Z", GONE="Z", K="Z", KM="K", KT="KM", KS="KM", O="Z",   # O: small object
)
STATIONS, MODULES = {"ST", "K"}, {"M1", "M2", "M3", "M4", "MC", "KM"}
SIX = ("x25", "x75", "y25", "y75", "z25", "z75")
END = "|"          # hits after this marker lie beyond the tested endpoint


def ancestors(c):
    while c:
        yield c
        c = PARENT.get(c)


def md_chain(sc, h):
    """`+0x70` walk as check_line_of_sight sees it; `link` is the unproven module->station edge."""
    for c in ancestors(h):
        yield c
        if c in MODULES and sc.get("link") == "null":
            return
        if c in MODULES and sc.get("link") == "zone":
            yield "Z"
            return


def hits(sc, origin, e):
    lines = sc["lines"].get(origin, sc["lines"]) if "origins" in sc else sc["lines"]
    return lines.get(e, lines.get("*", []))


# ---------------------------------------------------------------- truth: #202 rules on the stated hits

def qualifies(target, h):
    """A selected element counts only itself; a selected hull counts itself and any descendant."""
    if target in ("T", "MT", "T2"):
        return h == target
    return target in ancestors(h)


def truth_line(sc, origin, e, target):
    for h in hits(sc, origin, e):
        if h == END:
            return "MISS"
        if h in sc.get("absent", ()):
            continue
        if isinstance(h, tuple):
            q = {qualifies(target, x) for x in h}
            return "TIE" if len(q) > 1 else ("CLEAR" if q.pop() else "BLOCKED")
        if h == "W":
            return "SELF"          # native ignores its own meshes; MD cannot see past them
        return "CLEAR" if qualifies(target, h) else "BLOCKED"
    return "MISS"


def weapon_gate(sc):
    w = sc.get("weapon", {})
    if w.get("cls", "turret") == "missileturret":
        ammo = w.get("ammo")
        if ammo in (None, "missing"):
            return "U"
        if ammo == "guided":
            return "G"
    elif w.get("cls", "turret") != "turret":
        return "U"
    if sc.get("zone_diff") or sc.get("frame_lost"):
        return "U"
    return None


def expected(sc, plan):
    gate = weapon_gate(sc)
    if gate:
        return gate
    if not plan["endpoints"]:
        return "U"
    ts = [truth_line(sc, sc.get("query", "b0"), e, sc["target"]) for e, _ in plan["endpoints"]]
    if "TIE" in ts:
        return "?"
    return "C" if "CLEAR" in ts else "B" if "BLOCKED" in ts else "U"


# ---------------------------------------------------------------- candidates

def los(sc, e, declared, mut):
    """Simulated check_line_of_sight, useaimtarget per endpoint, excludeself=false."""
    for h in hits(sc, sc.get("query", "b0"), e):
        if h == END:
            return False
        if isinstance(h, tuple):
            h = h[0]                       # engine tie-break is unknown; take the listed order
        if h in sc.get("absent", ()) or ("excludeself" in mut and h in ("W", "S")):
            continue
        return declared in md_chain(sc, h)
    return False


def plan_for(sc, strategy, mut=frozenset()):
    t, station = sc["target"], sc["target"] in STATIONS
    # Production breaks on `$index gt 2`; MD loop counters are 1-based, so two modules.
    modules = sc.get("modules", ["M1", "M2", "M3", "M4"])[:3 if "three_modules" in mut else 2]
    declared = PARENT[t] if "declare_parent" in mut and t in ("T", "MT") else t
    if strategy == "legacy":                                        # #60 ENGAGEABLE root probe
        return dict(endpoints=[("aim", t)], blocker=None)
    if station:
        root = strategy.startswith("root")
        return dict(endpoints=[(m, t if root else m) for m in modules],
                    blocker="Z" if strategy == "root_zone" else "S")
    if strategy in ("seven", "lazy", "eight") and t in ("T", "MT"):
        centre = [("c", declared)] if strategy == "eight" else []   # eight: the old centre after the seven
        return dict(endpoints=[("aim", declared)] + [(p, declared) for p in SIX] + centre, blocker="Z")
    return dict(endpoints=[("c", declared)], blocker="Z")


def candidate(sc, strategy, mut=frozenset()):
    """(status, reason, calls). Mirrors LineOfFireTurret; `lazy` classifies only after every point fails."""
    w = sc.get("weapon", {})
    if sc.get("frame_lost"):
        return "U", "frame", 0
    if w.get("cls", "turret") == "missileturret":
        ammo = w.get("ammo")
        if ammo is None and "unloaded_unguided" not in mut:
            return "U", "guidance", 0
        if ammo == "guided":
            return ("C" if "guided_clear" in mut else "G"), "", 0
    elif w.get("cls", "turret") != "turret":
        return "U", "class", 0
    if sc.get("zone_diff") and strategy == "legacy":
        return "B", "", 1               # the old probe had no zone gate; its ray cannot see the target
    if sc.get("zone_diff") and "zone_skip" not in mut:
        return "U", "zone", 0
    plan = plan_for(sc, strategy, mut)
    if not plan["endpoints"]:
        return "U", "frame", 0
    calls, reason, blocked, failed = 0, "", False, []
    station = sc["target"] in STATIONS
    for e, declared in plan["endpoints"]:
        calls += 1
        if los(sc, e, declared, mut):
            return "C", "", calls
        if strategy == "legacy":
            return "B", "", calls
        if e != "aim":                  # a useaimtarget endpoint cannot be re-declared
            failed.append(e)
        if strategy != "lazy" and e != "aim":
            calls, reason, blocked = classify(sc, e, plan, mut, calls, reason, blocked, station)
            if blocked and "first_blocked_stops" in mut:
                return "B", "", calls
    if strategy == "lazy":
        for e in failed:
            calls, reason, blocked = classify(sc, e, plan, mut, calls, reason, blocked, station)
            if blocked:
                break
    return ("B", "", calls) if blocked else ("U", reason, calls)


def classify(sc, e, plan, mut, calls, reason, blocked, station):
    if "no_classify" in mut:
        return calls, reason, True
    calls += 1
    if not los(sc, e, plan["blocker"], mut):
        return calls, reason or ("module" if station else "miss"), blocked
    if "no_self_query" in mut:
        return calls, reason, True
    calls += 1
    if los(sc, e, "W", mut):
        return calls, reason or "self", blocked
    return calls, reason, True


STRATEGIES = ("current", "seven", "lazy")

# ---------------------------------------------------------------- scenes
# level: live | native | source | hypothetical — evidence for the stated first-hit
# arrangement. Classification rules themselves are native inference / #202 design.
# `expect` rows are independent hand statements; `reach` is target-level evidence
# that some real shot path exists (e.g. LIVE hits).

def S(sid, group, target, lines, level="hypothetical", **kw):
    return dict(id=sid, group=group, target=target, lines=lines, level=level, **kw)


def on_all(*h):
    return {"*": list(h)}


SCENES = [
    # 1 blockers and first-hit order on a selected ship surface element
    S("own-hull", "blocker", "T", on_all("S", "T"), "native", expect=dict(current="B")),
    S("own-turret-mesh", "blocker", "T", on_all("W", "T"), "native", expect=dict(current="U")),
    S("own-mesh-then-hull", "blocker", "T", on_all("W", "S", "T")),
    S("sibling-turret", "blocker", "T", on_all("W2", "T")),
    S("sibling-shield", "blocker", "T", on_all("SSH", "T")),
    S("sibling-engine", "blocker", "T", on_all("SEN", "T")),
    S("friendly-ship", "blocker", "T", on_all("F", "T")),
    S("hostile-ship", "blocker", "T", on_all("X", "T")),
    S("target-hull-first", "blocker", "T", on_all("P", "T"), expect=dict(current="B", seven="B")),
    S("target-shield-first", "blocker", "T", on_all("PSH", "T")),
    S("target-engine-first", "blocker", "T", on_all("PEN", "T")),
    S("neighbour-element", "blocker", "T", on_all("T2", "T")),
    S("station-module", "blocker", "T", on_all("KM", "T")),
    S("station-turret", "blocker", "T", on_all("KT", "T")),
    S("station-shield", "blocker", "T", on_all("KS", "T")),
    S("asteroid", "blocker", "T", on_all("A", "T")),
    S("ship-wreck", "blocker", "T", on_all("WR", "T"), "native"),
    S("destroyed-no-wreck", "blocker", "T", on_all("GONE", "T"), "native", absent={"GONE"}),
    S("target-before-blocker", "blocker", "T", on_all("T", "X")),
    S("genuine-miss", "blocker", "T", on_all(), expect=dict(current="U")),
    S("hit-beyond-endpoint", "blocker", "T", on_all(END, "T")),
    S("uncertain-tie", "blocker", "T", on_all(("T", "P")), scored=False),
    # 2 exact target membership
    S("hull:own-element-first", "membership", "P", on_all("PSH", "P"), "native", expect=dict(current="C")),
    S("hull:hull-first", "membership", "P", on_all("P")),
    S("hull:blocker", "membership", "P", on_all("X", "P")),
    S("hull:own-turret-mesh", "membership", "P", on_all("W", "P")),
    S("hull:hollow-centre", "membership", "P", on_all(END, "P")),
    S("hull:docked-ship", "membership", "P", on_all("DK", "P"), scored=False,
      note="a docked craft is a hull descendant; #202 does not say whether it counts"),
    S("station:nearest-module", "membership", "ST", {"M1": ["M1"], "*": []}, expect=dict(current="C")),
    S("station:module-turret", "membership", "ST", {"M1": ["MT"], "*": []}),
    S("station:other-module", "membership", "ST", {"M1": ["M2"], "*": ["X"]}, expect=dict(current="U")),
    S("station:non-nearest-module", "membership", "ST", on_all("M4")),
    S("station:third-module", "membership", "ST", on_all("M3"), expect=dict(current="U"),
      note="the third-nearest module is outside the two-module cap"),
    S("station:second-module-clear", "membership", "ST", {"M1": ["X", "M1"], "M2": ["M2"]},
      expect=dict(current="C"), note="modules are ranked from the firing ship, not the turret"),
    S("station:single-module", "membership", "ST", on_all("M1"), modules=["M1"]),
    S("station:module-destroyed-mid-pass", "membership", "ST", {"M1": [], "M2": ["M2"]}, absent={"M1"},
      scored=False, note="the module list is fixed at pass start; a dead entry's MD behavior is unestablished"),
    S("station:docked-ship", "membership", "ST", on_all("DKS"), scored=False,
      note="a docked craft is a module descendant; #202 does not say whether it counts"),
    S("station:construction-module", "membership", "ST", {"MC": ["MC"], "*": []},
      modules=["MC", "M1", "M2", "M3"]),
    S("station:module-wreck", "membership", "ST", {"M1": ["M2"], "*": ["X"]}, scored=False,
      note="a wrecked module keeps a body (native); its station membership is unproven"),
    S("station:firing-ship", "membership", "ST", on_all("S", "M1")),
    S("station:own-turret-mesh", "membership", "ST", on_all("W", "M1")),
    S("station:external-blocker", "membership", "ST", on_all("X", "M1")),
    S("station:no-modules", "membership", "ST", on_all("M1"), modules=[]),
    S("station:link-null", "membership", "ST", on_all("M1"), link="null"),
    S("station:link-zone", "membership", "ST", on_all("M1"), link="zone"),
    S("station-element:exact", "membership", "MT", on_all("MT")),
    S("station-element:parent-module", "membership", "MT", on_all("M1", "MT"), expect=dict(current="B")),
    S("station-element:sibling", "membership", "MT", on_all("MT2", "MT")),
    S("station-element:other-module", "membership", "MT", on_all("M2", "MT")),
    S("station-element:link-null", "membership", "MT", on_all("M1", "MT"), link="null"),
    # 3 point selection on a selected element (centre is the current endpoint)
    S("aim-first", "points", "T", {"aim": ["T"], "*": ["P", "T"]}, expect=dict(current="B", seven="C")),
    *[S(f"first-clear-{p}", "points", "T", {p: ["T"], "*": ["P", "T"]}) for p in SIX],
    S("all-seven-blocked", "points", "T", on_all("P", "T"), expect=dict(seven="B")),
    S("all-seven-self", "points", "T", on_all("W", "T")),
    S("all-seven-miss", "points", "T", on_all()),
    S("mixed-blocked-unknown", "points", "T",
      {"aim": ["X"], "x25": [], "x75": ["W"], "y25": ["P"], "*": []}, expect=dict(seven="B")),
    S("mixed-unknown-only", "points", "T", {"aim": ["X"], "x25": [], "*": ["W"]}, expect=dict(seven="U")),
    S("stop-at-first-clear", "points", "T", {"aim": ["P"], "x25": ["T"], "*": ["W"]}),
    S("aim-outside-box", "points", "T", {"aim": [], "y75": ["T"], "*": ["P", "T"]},
      note="68/88 official turret-element aim points lie outside the collision box (#184 data)"),
    S("hollow-centre-element", "points", "T", {"c": [], "x25": ["T"], "*": ["P"]}),
    S("only-centre-clear", "points", "T", {"c": ["T"], "aim": [], "*": ["P", "T"]},
      note="seven drops the centre when an authored aim point exists"),
    S("no-authored-aim", "points", "T", {"c": ["P"], "aim": ["P"], "z75": ["T"], "*": ["P"]},
      note="aim falls back to the box centre, so the probe repeats the centre line"),
    S("two-aim-points", "points", "T", {"aim": ["P"], "x75": ["T"], "*": ["P"]},
      note="nearest authored point to the origin is occluded; the other is never probed"),
    # 4 turret position and firing origin (lines keyed by origin; query = barrelposition now)
    S("parked", "origin", "T", {"b0": on_all("S", "T"), "fire": on_all("T")}, "live", origins=1,
      reach=True, note="#69 FAR: resting barrelposition self-blocked, fired pose clear and hit"),
    S("turning", "origin", "T", {"b0": on_all("W", "T"), "fire": on_all("T")}, origins=1, reach=True),
    S("settled", "origin", "T", {"b0": on_all("T")}, origins=1),
    S("retargeting-away", "origin", "T", {"b0": on_all("W2", "T"), "fire": on_all("T")}, origins=1,
      reach=True),
    S("rest-a", "origin", "T", {"b0": on_all("S", "T")}, origins=1, note="one of several resting yaws"),
    S("rest-b", "origin", "T", {"b0": on_all("T")}, origins=1, note="another resting yaw of the same turret"),
    S("barrel-2-clear", "origin", "T", {"b0": on_all("W2", "T"), "b1": on_all("T")}, "source", origins=1,
      reach=True, note="barrelposition is element 0; shots cycle endpoints (native)"),
    S("barrel-5-gatling", "origin", "T", {"b0": on_all("SSH", "T"), "b3": on_all("T")}, origins=1,
      reach=True),
    S("barrel-4-unguided-missile", "origin", "T", {"b0": on_all("S", "T"), "b2": on_all("T")}, origins=1,
      reach=True, weapon=dict(cls="missileturret", ammo="unguided")),
    # 5 weapon families
    S("beam-clear", "weapon", "T", on_all("T")),
    S("projectile-blocked", "weapon", "T", on_all("X", "T")),
    S("flak-spread", "weapon", "T", on_all("T")),
    S("unguided-own-hull", "weapon", "T", on_all("S", "T"), "native",
      weapon=dict(cls="missileturret", ammo="unguided"), expect=dict(current="B")),
    S("cluster-carrier", "weapon", "T", on_all("X", "T"), "native",
      weapon=dict(cls="missileturret", ammo="cluster")),
    S("guided-through-hull", "weapon", "T", on_all("S", "T"), "live",
      weapon=dict(cls="missileturret", ammo="guided"), expect=dict(current="G", seven="G")),
    S("guided-external-blocker", "weapon", "T", on_all("X", "T"), "native",
      weapon=dict(cls="missileturret", ammo="guided"), expect=dict(current="G")),
    S("missile-unloaded", "weapon", "T", on_all("T"), weapon=dict(cls="missileturret"),
      expect=dict(current="U")),
    S("missile-missing-guidance", "weapon", "T", on_all("T"), "source",
      weapon=dict(cls="missileturret", ammo="missing"),
      note="any loaded macro that is not guided takes the physical path; "
           "cf. missile_story_dumbfire_light_mk2_macro"),
    S("unknown-class", "weapon", "T", on_all("T"), weapon=dict(cls="other")),
    # 6 uncertainty (MD pre-checks; Lua pass behavior is runtime.lua)
    S("zones-differ", "uncertainty", "T", on_all("T"), zone_diff=True, expect=dict(current="U")),
    S("frame-lost", "uncertainty", "T", on_all("T"), frame_lost=True),
    S("cross-zone-blocker-unseen", "uncertainty", "T", on_all("T"), scored=False,
      note="a blocker in another zone's physics world is not a query candidate"),
    # negative controls
    S("neg:69-near-all-blocked", "negative", "T", on_all("X", "T"), "live",
      expect=dict(current="B", seven="B"), note="#69 NEAR: fast probe and all six blocked by a Terraformer"),
    S("neg:parent-not-selected", "negative", "T", on_all("P", "T"), expect=dict(current="B", seven="B")),
    S("neg:own-hull-kept", "negative", "T", on_all("S", "T"), expect=dict(current="B", seven="B")),
    S("neg:guided-not-physical", "negative", "T", on_all("S"), weapon=dict(cls="missileturret", ammo="guided"),
      expect=dict(current="G", seven="G")),
]

# ---------------------------------------------------------------- historical witnesses

RAY = ["railgun(1 endpoint)"] * 12 + ["disruptor(3 endpoints)"] * 2


def witness_202(hyp):
    """Selected Osaka element 0x17c090. LIVE: every centre line was Q(T)=F, Q(Z)=T, Q(W)=F
    (0/14, 42 calls) while railgun 0x3e59e hit it 11 times; the aim-target probe was clear
    for three turrets that hit it. Hypotheses decide the other lines."""
    out = []
    for i, layout in enumerate(RAY):
        lines = {"c": ["P", "T"]}
        if hyp == "centre-occluded":
            lines.update({"aim": ["T"], "*": ["P", "T"]})
        elif hyp == "aim-only-verified":
            lines.update({"aim": ["T"] if i < 3 else ["P"], "y75": ["T"], "*": ["P", "T"]})
        elif hyp == "all-seven-occluded":
            lines.update({"aim": ["T"] if i < 3 else ["P"], "*": ["P", "T"]})
        elif hyp == "alternate-barrel":
            lines.update({"*": ["T2", "T"]})
        out.append(dict(id=f"202:{hyp}:{i}", target="T", lines=lines, level="live", layout=layout))
    return out


def witness_60(hyp):
    """Xenon Defence Platform: legacy root useaimtarget probe 0/14 while turrets hit it."""
    base = dict(target="ST", modules=["M1", "M2", "M3", "M4"], level="live")
    if hyp == "centre-gap":
        return dict(base, lines={"aim": [], "*": ["M1"]})
    if hyp == "module-link-null":
        return dict(base, lines={"*": ["M1"]}, link="null")
    return dict(base, lines={"*": ["M1"]}, zone_diff=True)


# ---------------------------------------------------------------- production drift check

MODEL_SIGNATURE = dict(
    rays=[("$weapon", "$weapon.barrelposition", "$declared", "$endpoint", "false", "false"),
          ("$weapon", "$weapon.barrelposition", "$blocker", "$blockerpoint", "false", "false"),
          ("$weapon", "$weapon.barrelposition", "$weapon", "$weaponpoint", "false", "false")],
    blocker="if $station then LineOfFireService.$ship else $weapon.zone",
    module_cap="$index gt 2",
    reasons=["class", "frame", "guidance", "miss", "module", "self", "zone"],
    statuses=["B", "C", "G", "U"],
)


def production_signature():
    md = ET.parse(ROOT / "md/x4_gunnery_control.xml").getroot()
    cues = {c.get("name"): c for c in md.iter("cue")}
    turret, begin = cues["LineOfFireTurret"], cues["LineOfFireBegin"]
    text = ET.tostring(turret, encoding="unicode")
    return dict(
        rays=[tuple(r.get(k) for k in ("object", "objectoffset", "target", "targetoffset",
                                        "useaimtarget", "excludeself"))
              for r in turret.iter("check_line_of_sight")],
        blocker=next(v.get("exact") for v in turret.iter("set_value") if v.get("name") == "$blocker"),
        module_cap=next(d.get("value") for d in begin.iter("do_if") if "$index" in d.get("value", "")),
        reasons=sorted(set(re.findall(r"'([a-z]+)'", " ".join(
            v.get("exact", "") for v in turret.iter("set_value") if v.get("name") == "$reason"))) - {""}),
        statuses=sorted(set(re.findall(r"^'([A-Z])'$", "\n".join(
            v.get("exact", "") for v in turret.iter("set_value") if v.get("name") == "$status"), re.M))),
        _endpoint_space='space="$declared"' in text,
    )


# ---------------------------------------------------------------- optional population input

def population():
    """#184 authored aim points against element collision boxes, and firing-endpoint layouts."""
    sys.path.insert(0, str(ROOT / "research/issue184"))
    import aimpoint_map as am  # noqa: E402  (needs numpy and the official source cache)
    rows = Counter()
    for t in am.targets():
        for p in t["points"]:
            u = max(abs(p[i] - t["C"][i]) / max(t["H"][i], 1e-9) for i in range(3))
            rows[t["kind"], "outside" if u > 1 else "inside"] += 1
        if not t["points"]:
            rows[t["kind"], "none"] += 1
    layouts = Counter()
    for f in (ROOT / ".x4-research-cache/official-source-sets").glob("**/assets/props/**/turret_*.xml"):
        comp = ET.parse(f).getroot().find("component")
        if comp is None or comp.get("class") not in ("turret", "missileturret"):
            continue
        for role in ("laser", "rocket"):
            n = sum(role in (c.get("tags") or "").split() for c in comp.iter("connection"))
            if n:
                layouts[comp.get("class"), n] += 1
    return rows, layouts


# ---------------------------------------------------------------- scoring and report

MUTANTS = ("no_classify", "excludeself", "declare_parent", "guided_clear", "unloaded_unguided",
           "first_blocked_stops", "no_self_query", "zone_skip", "three_modules")


def score(obs, exp):
    if exp == "?" or obs == exp:
        return "ok"
    if obs == "C" or obs == "G":
        return "WRONG CLEAR"
    if obs == "B":
        return "WRONG BLOCKED"
    return "excess UNKNOWN" if obs == "U" else "WRONG"


def run(scenes, mut=frozenset(), strategies=STRATEGIES):
    rows = []
    for sc in scenes:
        for st in strategies:
            obs, reason, calls = candidate(sc, st, mut)
            exp = expected(sc, plan_for(sc, st))
            hand = sc.get("expect", {}).get(st)
            rows.append(dict(sc=sc, st=st, obs=obs, reason=reason, calls=calls, exp=exp,
                             verdict=score(obs, exp), hand_ok=hand in (None, obs)))
    return rows


def main():
    failures, defects = [], []
    prod = production_signature()
    drift = {k: (v, prod[k]) for k, v in MODEL_SIGNATURE.items() if prod[k] != v}
    if not prod["_endpoint_space"]:
        drift["endpoint frame"] = ("declared-target space", "missing")
    print("# Issue #202 selected-target CLEAR LINE OF FIRE benchmark (OFFLINE)\n")
    head = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    print(f"Production MD at {head}: model drift check {'PASS' if not drift else 'FAIL'}")
    for k, (want, got) in drift.items():
        failures.append(f"model drift: {k}")
        print(f"  {k}: model {want!r} != production {got!r}")

    rows = run(SCENES)
    print("\n## Scenarios\n")
    print("| scene | group | level | target | current | seven (lazy calls) | expected cur/seven |")
    print("|---|---|---|---|---|---|---|")
    for i in range(0, len(rows), 3):
        cur, sev, lz = rows[i:i + 3]
        sc = cur["sc"]
        flag = "" if sc.get("scored", True) else " (unscored)"
        print(f"| {sc['id']}{flag} | {sc['group']} | {sc['level']} | {sc['target']} "
              f"| {cur['obs']} {cur['reason']} [{cur['calls']}] | {sev['obs']} {sev['reason']} "
              f"[{sev['calls']}] ({lz['calls']}) | {cur['exp']} / {sev['exp']} |")
        if lz["obs"] != sev["obs"]:
            failures.append(f"lazy status differs: {sc['id']}")
        for r in (cur, sev, lz):
            if not r["hand_ok"]:
                failures.append(f"hand expectation: {sc['id']} {r['st']} observed {r['obs']}")
            if r["verdict"] in ("WRONG CLEAR", "WRONG BLOCKED", "WRONG") and sc.get("scored", True):
                defects.append(f"{r['verdict']}: {sc['id']} {r['st']} ({sc.get('note', sc['level'])})")

    print("\n## Verdicts (scored scenes; YES and NO counted separately)\n")
    for st in STRATEGIES:
        c = Counter((r["verdict"], r["obs"]) for r in rows if r["st"] == st and r["sc"].get("scored", True))
        print(f"- {st}: " + ", ".join(f"{v}/{o}={n}" for (v, o), n in sorted(c.items())))
    live = [r for r in rows if r["sc"]["level"] == "live"]
    print(f"- rules on LIVE-recorded first-hit arrangements: {len(live) // 3} scenes, "
          f"{sum(r['verdict'] != 'ok' and r['verdict'] != 'excess UNKNOWN' for r in live)} wrong "
          "(decision rules only; physical accuracy is settled.py)")

    print("\n## Target-level reachability versus tested-path answer\n")
    for sc in SCENES:
        if sc.get("reach"):
            other = [o for o in sc["lines"] if o != "b0"
                     and truth_line(sc, o, "c", sc["target"]) == "CLEAR"]
            res = {st: candidate(sc, st)[0] for st in ("current", "seven")}
            print(f"- {sc['id']}: current {res['current']}, seven {res['seven']}; clear from {other} "
                  f"({sc.get('note', sc['level'])})")

    print("\n## Issue #202 witness (14 Ray turrets, selected Osaka element)\n")
    print("| hypothesis | current | calls | seven | eager calls | lazy calls | recovers |")
    print("|---|---|---|---|---|---|---|")
    for hyp in ("centre-occluded", "aim-only-verified", "all-seven-occluded", "alternate-barrel"):
        ws = witness_202(hyp)
        cur = [candidate(w, "current") for w in ws]
        sev = [candidate(w, "seven") for w in ws]
        lz = [candidate(w, "lazy") for w in ws]
        ncur, nsev = sum(s == "C" for s, _, _ in cur), sum(s == "C" for s, _, _ in sev)
        if ncur != 0 or sum(c for _, _, c in cur) != 42 or any(s != "B" for s, _, _ in cur):
            failures.append(f"#202 witness does not reproduce 0/14 with 42 calls: {hyp}")
        note = {"alternate-barrel": "2 disruptors at most; 12 railguns have one endpoint"}.get(hyp, "")
        print(f"| {hyp} | {ncur}/14 | {sum(c for *_, c in cur)} | {nsev}/14 | {sum(c for *_, c in sev)} "
              f"| {sum(c for *_, c in lz)} | {note} |")

    print("\n## Issue #60 witness (Xenon station, legacy root useaimtarget probe)\n")
    for hyp in ("centre-gap", "module-link-null", "cross-zone"):
        w = witness_60(hyp)
        res = {st: candidate(w, st)[:2] for st in ("legacy", "current", "root_zone", "root_ship")}
        if res["legacy"][0] == "C":
            failures.append(f"#60 witness does not reproduce 0/14: {hyp}")
        print(f"- {hyp}: " + ", ".join(f"{k} {s}{(' ' + r) if r else ''}" for k, (s, r) in res.items()))
    print("- discriminator: module-declared vs root-declared on one module-centre endpoint separates "
          "link-null from centre-gap; weapon.zone vs target.zone separates cross-zone (LIVE needed)")

    print("\n## Station root declaration under the unproven module link\n")
    for sc in [s for s in SCENES if s["target"] == "ST"]:
        res = {st: candidate(sc, st)[0] for st in ("current", "root_zone", "root_ship")}
        exp = expected(sc, plan_for(sc, "current"))
        print(f"- {sc['id']}: expected {exp}; " + ", ".join(f"{k} {v}" for k, v in res.items()))

    print("\n## Query cost per turret and per 14-turret pass (simulated calls)\n")
    worst = {st: max(r["calls"] for r in rows if r["st"] == st) for st in STRATEGIES}
    for label, sc in (("all seven blocked", "all-seven-blocked"), ("all seven self", "all-seven-self"),
                      ("all seven miss", "all-seven-miss"), ("aim clear", "aim-first"),
                      ("station, no module clear", "station:other-module")):
        s = next(x for x in SCENES if x["id"] == sc)
        c = {st: candidate(s, st)[2] for st in STRATEGIES}
        print(f"- {label}: current {c['current']} ({14 * c['current']}), seven {c['seven']} "
              f"({14 * c['seven']}), lazy {c['lazy']} ({14 * c['lazy']})")
    print(f"- worst observed per turret: {worst}; pass worst = 14 x that")
    for st in STRATEGIES:
        vals = sorted(r["calls"] for r in rows if r["st"] == st and r["obs"] in "CBU" and r["calls"])
        print(f"- {st} median over ray-issuing scenes: {vals[len(vals) // 2]}")

    print("\n## Mutation check (deliberately wrong behavior must fail)\n")
    for m in MUTANTS:
        bad = [r for r in run(SCENES, frozenset({m})) if r["sc"].get("scored", True)
               and (r["verdict"] in ("WRONG CLEAR", "WRONG BLOCKED", "WRONG") or not r["hand_ok"])]
        print(f"- {m}: {'killed' if bad else 'SURVIVED'} ({len(bad)} failing rows)")
        if not bad:
            failures.append(f"mutant survived: {m}")

    if "--population" in sys.argv:
        pts, layouts = population()
        print("\n## Population inputs (#184 aim points; official firing-endpoint layouts)\n")
        print("- aim point vs collision box:", dict(sorted(pts.items())))
        print("- endpoint layouts (class, count): components", dict(sorted(layouts.items())))

    print("\n## Result\n")
    print("Candidate definite failures:" + ("".join(f"\n- FAIL {d}" for d in defects) or " none"))
    print("Benchmark integrity: " + ("PASS" if not failures else "FAIL\n- " + "\n- ".join(failures)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
