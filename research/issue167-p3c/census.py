"""P3c: build corpus.pkl (aimtarget records, boxes, pairs, turret geometry, arc limits)."""
import pickle, re
from sources import COMPONENTS, MACROS, REPO, SRC, StudyError, center_half, connections, tags
from barrelposition_evaluator import _native_connection_name_hash, joint_segments, load_turrets
from census_common import REQUIRED_SOURCE_SETS
from yaw_rest_gate import yaw_geometry
import numpy as np

F = lambda v: float(np.float32(v))  # noqa: E731
SURFACE = {"turret", "missileturret", "shieldgenerator", "engine"}

aim = {}
for name, defs in COMPONENTS.items():
    for _rel, comp in defs:
        conns = [c for c in connections(comp).values() if "aimtarget" in tags(c)]
        if conns:
            if len(defs) != 1:
                raise StudyError(f"duplicate aimtarget component {name}")
            aim[name] = (comp.get("class"), conns)
cand = {n: v for n, v in aim.items() if v[0].startswith("ship_") or v[0] in SURFACE}

records = []
for mname, defs in MACROS.items():
    for rel, m in defs:
        ref = m.find("component")
        if ref is not None and ref.get("ref") in cand:
            records.append((ref.get("ref"), rel, mname))
records.sort()
comps = sorted({r[0] for r in records})

out = []
for cname, rel, mname in records:
    conns = sorted(cand[cname][1], key=lambda c: _native_connection_name_hash(c.get("name").lower()))
    pts = []
    for c in conns:
        pos = c.find("offset/position")
        pts.append(tuple(F(float(pos.get(a, 0))) if pos is not None else 0.0 for a in "xyz"))
    C, H = center_half(mname)
    out.append({"component": cname, "path": rel, "macro": mname, "names": [c.get("name") for c in conns],
                "points": pts, "C": C, "H": H})
pairs = [(ri, a, b) for ri, r in enumerate(out) for a in range(len(r["points"])) for b in range(a + 1, len(r["points"]))]
multi = sorted({r["component"] for r in out if len(r["points"]) > 1})
counts = dict(aim=len(aim), candidates=len(cand), macro_referenced=len(comps), records=len(out), multi=len(multi),
              component_pairs=sum(len(cand[c][1]) * (len(cand[c][1]) - 1) // 2 for c in multi), pairs=len(pairs))
print(counts)
assert counts == dict(aim=336, candidates=255, macro_referenced=248, records=270, multi=15, component_pairs=33, pairs=38), counts

lua = (REPO / "ui/turret_muzzle_geometry.lua").read_text()
blocks = re.split(r'\n    \["', lua)[1:]
turret_names = sorted(b.split('"', 1)[0] for b in blocks if "chain = {" in b)
assert len(turret_names) == 92
arcs = {m: (float(a), float(b)) for m, a, b in re.findall(
    r'\["(\w+)"\] = \{ (-?[\d.]+), (-?[\d.]+) \}', (REPO / "ui/turret_arc_limits.lua").read_text())}
cache = REPO / ".x4-research-cache"
outdir = cache / "issue167-p3c"
outdir.mkdir(exist_ok=True)
loaded = load_turrets({n: SRC / n for n in REQUIRED_SOURCE_SETS},
                      {n: cache / "issue72-a2-ani-resources" / n for n in REQUIRED_SOURCE_SETS}, turret_names)
turrets = [{"macro": m, "yaw": yaw_geometry(loaded[m]), "seg": joint_segments(loaded[m]), "arc": arcs[m]} for m in turret_names]
pickle.dump({"records": out, "pairs": pairs, "turrets": turrets, "counts": counts}, open(outdir / "corpus.pkl", "wb"))
