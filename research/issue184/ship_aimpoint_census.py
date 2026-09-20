"""A4.4: complete vanilla X4 9.00 + SWI 0.9.1 HF ship aim-point census.

Every unique ship component behind a `ship_s`/`ship_m`/`ship_l`/`ship_xl` macro, its authored
`aimtarget` connections in X4 selection order, and those points against the reconstructed runtime box.

    python3 research/issue184/ship_aimpoint_census.py     # census + findings summary

Reused unchanged: #167 `sources` (official index, `macro_box`, `conn_world`) and
`barrelposition_evaluator._native_connection_name_hash` (defaults-collection order).

SWI overlay, census-only (`aimpoint_map._index_swi_ships` deliberately skips both for the benchmark):
`<diff>` patches are applied to the official file at the same relative path, and SWI files that
redefine an official name replace it. Neither is free: 1,380 diff operations remove or retag
connections that feed the runtime box.

Normalization: n = (p - C) / H per axis, C/H the runtime-box centre and half-extents in the
component frame. n = 0 is the box centre, |n| = 1 a box face, |n| > 1 outside the box.
C is the reconstructed runtime box centre, not a centre of mass.
"""
from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "research/issue167-p3c"), str(ROOT / "scripts")]
import sources  # noqa: E402
from barrelposition_evaluator import _native_connection_name_hash as name_hash  # noqa: E402
from census_common import REQUIRED_SOURCE_SETS  # noqa: E402

SWI_ASSETS = ROOT / ".x4-research-cache/issue184/swi_assets"
NAME_INDEX = {}  # (root tag, name) -> the file X4's index/ resolves that name to
OUT = ROOT / ".x4-research-cache/issue184/a44_census.jsonl"
CLASSES = ("ship_s", "ship_m", "ship_l", "ship_xl")
TOL = 1e-4  # m; authored positions are float32 text


# ---------------------------------------------------------------- SWI overlay

def _sel(sel, roottag):
    """The `sel` XPath subset SWI 0.9.1 HF actually uses -> (ElementTree path relative to the document
    root element, attribute or None). `sel` is absolute, so a leading `//roottag/` is that root itself."""
    m = re.search(r"/@(\w+)$", sel)
    attr = m.group(1) if m else None
    sel = sel[: m.start()] if m else sel
    # [parts/part/@name='x'] -> [parts/part[@name='x']]: ElementTree has no descendant attribute test
    sel = re.sub(r"\[([\w/]+)/@(\w+)=('[^']*')\]", r"[\1[@\2=\3]]", sel)
    rest = re.sub(rf"^/{{1,2}}{roottag}(/|$)", "", sel)
    if rest == "":
        return ".", attr
    return ("./" if rest != sel or not sel.startswith("//") else ".//") + rest.lstrip("/"), attr


def apply_diff(root, diff):
    """Apply a SWI `<diff>` to a parsed official file in place. -> Counter of applied/unsupported ops."""
    stats = Counter()
    for op in diff:
        if op.tag not in ("add", "replace", "remove"):
            stats[f"diff op ignored: <{op.tag}>"] += 1
            continue
        path, attr = _sel(op.get("sel") or "", root.tag)
        parents = {c: p for p in root.iter() for c in p}
        # ElementTree has no nested path predicate: `a[@name='x'][b/c[@name='y']]` -> match, then filter
        nested = re.fullmatch(r"(.*)\[([\w/]+\[@\w+='[^']*'\])\]", path)
        path = nested.group(1) if nested else path
        hits = [root] if path == "." else root.findall(path)
        if nested:
            hits = [h for h in hits if h.find(nested.group(2)) is not None]
        if not hits:
            stats["diff op unmatched: sel selects nothing"] += 1
            continue
        for el in hits:
            if attr is not None:
                el.set(attr, op.text or "")
            elif op.tag == "add":
                el.extend(list(op))
            elif op.tag == "remove":
                parents[el].remove(el)
            else:  # replace
                if list(op):
                    p = parents.get(el)
                    if p is None:  # replacing the document root: swap its children
                        el[:] = list(op[0]) if op[0].tag == el.tag else list(op)
                    else:
                        p[list(p).index(el)] = op[0]
                else:
                    el.text = op.text
        stats[f"diff op applied: <{op.tag}>"] += 1
    return stats


def overlay_swi():
    """Index SWI 0.9.1 HF beside the official sources as the effective 0.9.1 HF state: diffs applied to
    the official file at the same relative path, SWI redefinitions replacing the official name, then new
    SWI definitions. -> (Counter, list of unresolved (path, reason))."""
    if any(rel.startswith("swi/") for defs in sources.MACROS.values() for rel, _m in defs):
        raise RuntimeError("SWI already indexed")
    NAME_INDEX.update(swi_name_index())
    stats, unresolved = Counter(), []
    official_files = {}
    for s in REQUIRED_SOURCE_SETS:
        for p in (ROOT / ".x4-research-cache/official-source-sets" / s).rglob("*.xml"):
            official_files.setdefault(p.relative_to(ROOT / ".x4-research-cache/official-source-sets" / s).as_posix(),
                                      []).append((s, p))
    for p in sorted(SWI_ASSETS.glob("assets/**/*.xml")):
        rel = p.relative_to(SWI_ASSETS).as_posix()
        try:
            root = ET.parse(p).getroot()
        except ET.ParseError as e:
            unresolved.append((f"swi/{rel}", f"unparseable SWI XML: {e}"))
            continue
        if root.tag == "diff":
            targets = official_files.get(rel, [])
            if not targets:
                stats["SWI diff: no official file at the same path (not applied)"] += 1
                unresolved.append((f"swi/{rel}", "diff has no official file at the same relative path"))
                continue
            for s, op in targets:
                base = ET.parse(op).getroot()
                stats.update(apply_diff(base, root))
                _reindex(base, f"{s}/{rel}", stats, patched=True)
            stats["SWI diff: applied to an official file"] += 1
            continue
        _reindex(root, "swi/" + rel, stats)
    if not stats:
        raise RuntimeError(f"no SWI asset XML under {SWI_ASSETS}: run extract_swi_assets.py")
    stats["reference resolved case-insensitively"] = _alias_case()
    return stats, unresolved


def _alias_case():
    """SWI refers to a few official assets with different capitalisation (`bridge_arg_Xl_01_macro`).
    X4 resolves those; this exact-name index would not. Alias them. -> count."""
    n = 0
    for index, attr in ((sources.COMPONENTS, "component"), (sources.MACROS, "macro")):
        lower = {k.lower(): k for k in index}
        for defs in list(sources.MACROS.values()):
            for _rel, m in defs:
                for el in ([m.find(attr)] if attr == "component" else m.findall("connections/connection/macro")):
                    ref = el.get("ref") if el is not None else None
                    if ref and ref not in index and ref.lower() in lower:
                        index[ref] = index[lower[ref.lower()]]
                        n += 1
    return n


DUPES = defaultdict(list)  # component name -> the SWI definitions not kept


def swi_name_index():
    """X4 resolves a component/macro name to one file through `index/components.xml` and
    `index/macros.xml`; SWI adds its own entries there. -> {(root tag, name): cache-relative file}."""
    out = {}
    for kind in ("components", "macros"):
        for e in ET.parse(SWI_ASSETS / "index" / f"{kind}.xml").getroot().iter("entry"):
            # e.g. `extensions\starwarsmod_m1\assets\units\size_xl\mc80crain` -> the cached relative path
            value = e.get("value", "").replace("\\", "/")
            head, sep, tail = value.partition("assets/")
            out[(kind, e.get("name"))] = (sep + tail if sep else value) + ".xml"
    return out


def _reindex(root, rel, stats, patched=False, seen=set()):
    """A SWI definition replaces the official one of the same name. A second SWI definition of a name SWI
    already defines is a duplicate SWI authors (e.g. `t65b_xwing`, defined differently in two files).
    X4 resolves the name through its `index/` entry, so keep that file's definition."""
    index = {"components": sources.COMPONENTS, "macros": sources.MACROS}.get(root.tag)
    for e in root if index is not None else ():
        name = e.get("name")
        if (root.tag, name) in seen:
            stats["SWI defines the same name in two files (load order decides in game)"] += 1
            kept = index[name][0]
            want = NAME_INDEX.get((root.tag, name))
            if want is not None and rel == "swi/" + want and kept[0] != "swi/" + want:
                index[name], kept = [(rel, e)], kept
                e, rel = kept[1], kept[0]
            if root.tag == "components":
                DUPES[name].append((rel, e))
        elif name in index:
            index[name] = [(rel, e)]
            stats["official definition replaced by a SWI " + ("diff" if patched else "file")] += 1
        else:
            index[name] = [(rel, e)]
            stats["new SWI " + root.tag[:-1]] += 1
        if not patched:
            seen.add((root.tag, name))


# ---------------------------------------------------------------- census

def aim_points(comp):
    """Authored `aimtarget` connections in X4 selection order (the defaults collection, ordered by native
    connection-name hash) -> (names, raw local positions, parented names)."""
    conns = [c for c in sources.connections(comp).values() if "aimtarget" in sources.tags(c)]
    conns.sort(key=lambda c: name_hash(c.get("name").lower()))
    pts, parented = [], []
    for c in conns:
        pos = c.find("offset/position")
        pts.append([float(np.float32(float(pos.get(a, 0)))) if pos is not None else 0.0 for a in "xyz"])
        if c.get("parent"):
            parented.append(c.get("name"))
    return [c.get("name") for c in conns], pts, parented


def census():
    """One row per unique ship component in official 9.00 + effective SWI 0.9.1 HF.
    -> (rows, unresolved, overlay stats)."""
    stats, unresolved = overlay_swi()
    ships = defaultdict(lambda: {"macros": [], "source": None, "cls": set()})
    for name, defs in sorted(sources.MACROS.items()):
        for rel, m in defs:
            ref = m.find("component")
            if m.get("class") in CLASSES and ref is not None:
                s = ships[ref.get("ref")]
                s["macros"].append(name)
                s["cls"].add(m.get("class"))
                s["source"] = "swi" if rel.startswith("swi/") else s["source"] or "official"
    rows = []
    for cname, s in sorted(ships.items()):
        try:
            comp = sources.component(cname)
        except sources.StudyError as e:
            unresolved.append((cname, f"component not resolvable: {e}"))
            continue
        names, pts, parented = aim_points(comp)
        boxes = {}
        for m in s["macros"]:
            try:
                lo, hi = sources.macro_box(m)
            except (sources.StudyError, KeyError, RecursionError) as e:
                unresolved.append((f"{cname}/{m}", f"runtime box unresolved: {type(e).__name__}: {e}"))
                continue
            boxes[m] = (np.array([(a + b) / 2 for a, b in zip(lo, hi)]),
                        np.array([(b - a) / 2 for a, b in zip(lo, hi)]))
        # A box-unresolved ship still contributes its aim points, which are the census subject.
        C, H = boxes.get(s["macros"][0], (None, None))
        P = np.array(pts).reshape(-1, 3)
        rows.append(dict(
            component=cname, source=s["source"], ship_class=sorted(s["cls"]),
            macros=s["macros"], n_points=len(pts), names=names, points=pts, parented=parented,
            rel_origin=P.tolist(),                       # authored positions are already component-frame
            C=None if C is None else C.tolist(), H=None if H is None else H.tolist(),
            box_spread_across_macros=None if C is None else
            max((float(np.max(np.abs(np.concatenate([c - C, h - H])))) for c, h in boxes.values()), default=0.0),
            rel_center=None if C is None else (P - C).tolist(),
            norm=None if C is None else np.where(H > 0, (P - C) / np.where(H > 0, H, 1), np.nan).tolist(),
        ))
    return rows, unresolved, stats


# ---------------------------------------------------------------- analysis

def _fmt(v):
    return "(" + ", ".join(f"{x:.3f}" for x in v) + ")"


def _q(a):
    a = np.asarray(a, float)
    return f"med {np.median(a):.4g} / p90 {np.percentile(a, 90):.4g} / max {np.max(a):.4g}" if len(a) else "n/a"


def report(rows, unresolved, stats):
    L = []
    P = L.append
    boxed = [r for r in rows if r["C"] is not None]
    by_src = Counter(r["source"] for r in rows)
    P(f"# A4.4 ship aim-point census: {len(rows)} unique ship components "
      f"({by_src['official']} official, {by_src['swi']} SWI), "
      f"{sum(len(r['macros']) for r in rows)} macros, {sum(r['n_points'] for r in rows)} authored aim points")
    P(f"  runtime box reconstructed for {len(boxed)}; {len(rows) - len(boxed)} box-unresolved "
      f"(aim points still recorded): {[r['component'] for r in rows if r['C'] is None]}")
    P("")
    P("## SWI overlay")
    for k, v in sorted(stats.items()):
        P(f"  {v:6d}  {k}")
    P("  SWI 0.9.1 HF is an overhaul: a vanilla game holds only the official components; a SWI game holds "
      "the SWI ones plus the official ones as SWI patches them. Any reconstruction rule has to hold within "
      "each population on its own, so every section below splits official from SWI.")
    P("")
    P("## Population by source and class")
    per = Counter((r["source"], "/".join(r["ship_class"])) for r in rows)
    for (src, cls), n in sorted(per.items()):
        P(f"  {src:9s} {cls:20s} {n:4d}")
    P("")
    P("## Aim-point count distribution")
    dist = Counter(r["n_points"] for r in rows)
    for n in sorted(dist):
        sub = Counter(r["source"] for r in rows if r["n_points"] == n)
        P(f"  {n:2d} point(s): {dist[n]:4d} components  (official {sub['official']:3d}, SWI {sub['swi']:3d})")
    P(f"  aim connections carrying a `parent` attribute: {sum(len(r['parented']) for r in rows)} "
      "(an unparented offset is already in the component frame)")
    spread = [r["box_spread_across_macros"] for r in rows if len(r["macros"]) > 1 and r["C"] is not None]
    P(f"  components used by >1 macro: {len(spread)}. Their aim points are a property of the component, so "
      "every macro of a component shares the identical ordered layout by construction.")
    P(f"  runtime box spread across a component's macros: {_q(spread)} m "
      f"(> 1 m for {sum(x > 1 for x in spread)} components: the box, unlike the points, is per macro)")

    zero = [r for r in rows if r["n_points"] == 0]
    P("")
    P(f"## Zero-point components ({len(zero)}: {Counter(r['source'] for r in zero)['official']} official, "
      f"{Counter(r['source'] for r in zero)['swi']} SWI)")
    P(f"  by class: {dict(Counter('/'.join(r['ship_class']) for r in zero))}")
    P("  These author no `aimtarget` connection at all, so the native nearest-point selector's "
      "empty-collection branch decides their aim point. That branch is not characterized by the existing "
      "native analysis, and nothing in the authored data fixes a point for them.")
    P(f"  official ships that DO author points: {sorted(r['component'] for r in rows if r['source'] == 'official' and r['n_points'])}")

    one = [r for r in rows if r["n_points"] == 1]
    P("")
    P(f"## One-point components ({len(one)})")
    for src in ("official", "swi"):
        sub = [r for r in one if r["source"] == src]
        d = np.array([np.linalg.norm(r["points"][0]) for r in sub])
        P(f"  {src}: {len(sub)}; exactly the origin {int((d < TOL).sum())}; "
          f"|point - origin| {_q(d)} m")
    d_origin = np.array([np.linalg.norm(r["points"][0]) for r in one])
    P(f"  |point - component origin|: {_q(d_origin)} m; exactly the origin: {int((d_origin < TOL).sum())} of {len(one)}")
    ob = [r for r in one if r["C"] is not None]
    d_center = np.array([np.linalg.norm(r["rel_center"][0]) for r in ob])
    P(f"  |point - runtime-box centre|: {_q(d_center)} m; exactly the centre: {int((d_center < TOL).sum())} of {len(ob)}")
    for axis, a in enumerate("xyz"):
        z = int(np.sum(np.abs([r["points"][0][axis] for r in one]) < TOL))
        P(f"  authored {a} exactly 0: {z:3d} of {len(one)}")
    N = np.array([r["norm"][0] for r in ob])
    P(f"  normalized |n| per axis: median {_fmt(np.nanmedian(np.abs(N), axis=0))}, max {_fmt(np.nanmax(np.abs(N), axis=0))}")
    P(f"  inside the runtime box (all |n| <= 1): {int(np.sum(np.all(np.abs(N) <= 1 + 1e-6, axis=1)))} of {len(ob)}")
    P("  farthest from the component origin:")
    for r in sorted(one, key=lambda r: -np.linalg.norm(r["points"][0]))[:8]:
        P(f"    {r['component']:40s} {_fmt(r['points'][0])}  |{np.linalg.norm(r['points'][0]):.2f}| m"
          + (f"  n={_fmt(r['norm'][0])}" if r["C"] is not None else "  [box unresolved]"))

    multi = [r for r in rows if r["n_points"] > 1]
    P("")
    P(f"## Multi-point components ({len(multi)}) — structure")
    planar = [r for r in multi if np.ptp(np.array(r["points"])[:, 1]) < TOL]
    onx = [r for r in multi if np.all(np.abs(np.array(r["points"])[:, 0]) < TOL)]
    mirrored = [r for r in multi if _mirror(np.array(r["points"])) * 2 + sum(
        abs(p[0]) < TOL for p in r["points"]) == r["n_points"]]
    P(f"  by source: {dict(Counter(r['source'] for r in multi))}")
    P(f"  all points at one y (flat layout): {len(planar)} of {len(multi)}")
    P(f"  all points on the x=0 centreline: {len(onx)} of {len(multi)}")
    P(f"  fully left/right symmetric (every off-centre point has a +-x twin at the same y,z): "
      f"{len(mirrored)} of {len(multi)}")
    ptp = np.array([np.ptp(np.array(r["points"]), axis=0) for r in multi])
    P(f"  dominant spread axis: {dict(Counter('xyz'[i] for i in np.argmax(ptp, axis=1)))}")
    P(f"  spread per axis (m): x {_q(ptp[:, 0])}; y {_q(ptp[:, 1])}; z {_q(ptp[:, 2])}")
    mb = [r for r in multi if r["C"] is not None]
    NB = np.concatenate([np.array(r["norm"]) for r in mb])
    P(f"  all {len(NB)} normalized multi-point positions: |n| max per axis {_fmt(np.nanmax(np.abs(NB), axis=0))}; "
      f"points outside their own box: {int(np.sum(np.any(np.abs(NB) > 1 + 1e-6, axis=1)))}")
    dup = Counter(tuple(sorted(map(tuple, np.round(r["points"], 3)))) for r in multi)
    P(f"  distinct point layouts: {len(dup)} across {len(multi)} components; "
      f"layouts shared by >1 component: {sum(v > 1 for v in dup.values())}")
    y0 = [r for r in multi if np.all(np.abs(np.array(r["points"])[:, 1]) < TOL)]
    P(f"  every point at y=0 exactly: {len(y0)} of {len(multi)}")
    grid = [r for r in multi if _even_z(r)]
    P(f"  z coordinates on an exact even grid (>=3 distinct z): {len(grid)} of "
      f"{sum(len(set(np.round(np.array(r['points'])[:, 2], 3))) >= 3 for r in multi)} eligible")
    P(f"  not left/right symmetric: {[r['component'] for r in multi if r not in mirrored]}")
    out = [(r['component'], i) for r in mb for i, n in enumerate(r['norm']) if np.any(np.abs(n) > 1 + 1e-6)]
    P(f"  points outside their own runtime box: {out}")

    P("")
    P("## Direct reconstruction")
    allpts = [(r, i) for r in rows for i in range(r["n_points"])]
    P(f"  every one of the {len(allpts)} authored points lies on x=0 or in a +-x twin pair: "
      f"{sum(abs(r['points'][i][0]) < TOL for r, i in allpts)} on the centreline, "
      f"{sum(_mirror(np.array(r['points'])) for r in rows) * 2} in twin pairs, "
      f"{len(allpts) - sum(abs(r['points'][i][0]) < TOL for r, i in allpts) - 2 * sum(_mirror(np.array(r['points'])) for r in rows)} neither")
    lg = np.array([[2 * r["H"][2], r["n_points"]] for r in boxed if r["n_points"]])
    P(f"  box length (2*Hz) vs point count over the {len(lg)} components that author any point: "
      f"Pearson r = {np.corrcoef(lg[:, 0], lg[:, 1])[0, 1]:.3f}")
    for lo, hi in ((0, 100), (100, 300), (300, 1000), (1000, 1e9)):
        sub = [r for r in boxed if lo <= 2 * r["H"][2] < hi]
        P(f"    box length {lo:5g}-{hi:<6g} m: {len(sub):4d} components, "
          f"point counts {dict(sorted(Counter(r['n_points'] for r in sub).items()))}")

    P("")
    P(f"## Multi-point components ({len(multi)}) — full listing, X4 selection order")
    for r in sorted(multi, key=lambda r: (-r["n_points"], r["component"])):
        P("")
        P(f"### {r['component']}  [{r['source']} {'/'.join(r['ship_class'])}]  {r['n_points']} points")
        P(f"macros: {', '.join(r['macros'])}")
        P("box C=" + (f"{_fmt(r['C'])} H={_fmt(r['H'])}" if r["C"] is not None else "unresolved"))
        for i, (nm, p) in enumerate(zip(r["names"], r["points"])):
            n = f"  n {_fmt(r['norm'][i])}" if r["C"] is not None else ""
            P(f"  {i:2d} {nm:34s} local {_fmt(p)}{n}")

    amb = [(r, DUPES[r["component"]]) for r in rows if r["component"] in DUPES]
    P("")
    P(f"## Ambiguous: SWI defines the component in two files ({len(amb)} census ships)")
    P("  X4 resolves the name through its `index/components.xml` entry; the census keeps that file. Only a differing aim-point set matters here.")
    for r, alts in amb:
        other = [len(aim_points(e)[1]) for _rel, e in alts]
        flag = "" if all(o == r["n_points"] for o in other) else "  <-- DIFFERS"
        P(f"  {r['component']:34s} kept {r['n_points']} point(s), other definition(s) {other}{flag}")
        for rel, _e in alts:
            P(f"      also defined in {rel}")

    P("")
    P(f"## Unresolved ({len(unresolved)})")
    for k, why in unresolved:
        P(f"  {k}: {why}")
    return "\n".join(L)


def _even_z(r):
    """Distinct z coordinates, sorted, equally spaced (>= 3 of them)."""
    z = sorted(set(np.round(np.array(r["points"])[:, 2], 3)))
    d = np.diff(z)
    return len(z) >= 3 and bool(np.all(np.abs(d - d[0]) < 1e-3))


def _mirror(A):
    """Count of +-x mirror pairs (same y/z, opposite non-zero x)."""
    used, n = set(), 0
    for i in range(len(A)):
        for j in range(i + 1, len(A)):
            if i in used or j in used:
                continue
            if abs(A[i][0] + A[j][0]) < TOL and abs(A[i][0]) > TOL and np.allclose(A[i][1:], A[j][1:], atol=TOL):
                used |= {i, j}
                n += 1
    return n


if __name__ == "__main__":
    rows, unresolved, stats = census()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    print(report(rows, unresolved, stats))
    print(f"\n[{len(rows)} rows -> {OUT}]")
