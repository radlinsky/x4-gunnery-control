"""P3c study: official 9.00 source index, macro.boundingbox reconstruction, aimtarget census."""
import math, sys, xml.etree.ElementTree as ET
from functools import lru_cache
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))
from barrelposition_evaluator import read_offset, compose, IDENTITY, ZERO  # noqa: E402
from census_common import REQUIRED_SOURCE_SETS  # noqa: E402

SRC = REPO / ".x4-research-cache/official-source-sets"
EXCLUDE = {"nocollision", "nocollision_jolt", "platformcollision"}
PART_OFFSETS = False


class StudyError(Exception):
    pass


def _index():
    components, macros = {}, {}
    for s in REQUIRED_SOURCE_SETS:
        for p in sorted((SRC / s).rglob("*.xml")):
            try:
                root = ET.parse(p).getroot()
            except ET.ParseError:
                continue
            rel = f"{s}/{p.relative_to(SRC / s).as_posix()}"
            if root.tag == "components":
                for c in root.findall("component"):
                    components.setdefault(c.get("name"), []).append((rel, c))
            elif root.tag == "macros":
                for m in root.findall("macro"):
                    macros.setdefault(m.get("name"), []).append((rel, m))
    return components, macros


COMPONENTS, MACROS = _index()


def component(name):
    found = COMPONENTS.get(name)
    if not found or len(found) != 1:
        raise StudyError(f"component {name!r}: {len(found or [])} definitions")
    return found[0][1]


def macro(name):
    found = MACROS.get(name)
    if not found or len(found) != 1:
        raise StudyError(f"macro {name!r}: {len(found or [])} definitions")
    return found[0][1]


def tags(el):
    return set((el.get("tags") or "").split())


def connections(comp):
    return {c.get("name"): c for g in comp.findall("connections") for c in g.findall("connection")}


def part_owner(comp):
    return {p.get("name"): c for c in connections(comp).values() for g in c.findall("parts") for p in g.findall("part")}


def conn_world(comp, conn):
    """Connection offset, then parent-part chain (child-local first)."""
    t = read_offset(conn)
    owners = part_owner(comp)
    seen = set()
    while conn.get("parent"):
        name = conn.get("parent")
        if name in seen or name not in owners:
            raise StudyError(f"bad parent {name!r} in {comp.get('name')}")
        seen.add(name)
        conn = owners[name]
        t = compose(t, read_offset(conn))
    return t


def _size(el):
    s = el.find("size")
    if s is None:
        return None
    mx, ce = s.find("max"), s.find("center")
    h = tuple(float(mx.get(a, 0)) for a in "xyz") if mx is not None else ZERO
    c = tuple(float(ce.get(a, 0)) for a in "xyz") if ce is not None else ZERO
    return c, h


def _xf(point, tr):
    (tx, R) = tr
    return tuple(sum(point[k] * R[k][j] for k in range(3)) + tr[0][j] for j in range(3))


def _union(box, pts):
    lo, hi = box
    for p in pts:
        lo = tuple(min(a, b) for a, b in zip(lo, p))
        hi = tuple(max(a, b) for a, b in zip(hi, p))
    return lo, hi


def _corners(c, h):
    return [tuple(c[i] + (h[i] if (k >> i) & 1 else -h[i]) for i in range(3)) for k in range(8)]


@lru_cache(None)
def template_box(name):
    comp = component(name)
    box = (ZERO, ZERO)  # origin always included
    for el in [comp] + comp.findall("layers/layer"):
        sz = _size(el)
        if sz:
            box = _union(box, _corners(*sz))
    for conn in connections(comp).values():
        parts = [p for g in conn.findall("parts") for p in g.findall("part")]
        if not parts:
            continue
        eff = tags(conn)
        sizes = []
        for p in parts:
            sz = _size(p)
            if p.get("ref"):
                src_comp, src_part = p.get("ref").split(".", 1)
                src_conn = part_owner(component(src_comp)).get(src_part)
                if src_conn is None:
                    raise StudyError(f"unresolved part ref {p.get('ref')}")
                eff |= tags(src_conn)
                if sz is None:
                    sz = _size([q for g in src_conn.findall("parts") for q in g.findall("part") if q.get("name") == src_part][0])
            sizes.append((p, sz))
        if eff & EXCLUDE:
            continue
        world = conn_world(comp, conn)
        for p, sz in sizes:
            if sz is None:
                continue
            tr = compose(read_offset(p), world) if PART_OFFSETS else world
            box = _union(box, [_xf(q, tr) for q in _corners(*sz)])
    return box


def _inverse(tr):
    t, R = tr
    Rt = tuple(tuple(R[j][i] for j in range(3)) for i in range(3))
    ti = _xf(tuple(-v for v in t), (ZERO, Rt))
    return (ti, Rt)


@lru_cache(None)
def macro_box(name):
    m = macro(name)
    cname = m.find("component").get("ref")
    box = template_box(cname)
    comp = component(cname)
    conns = connections(comp)
    for mc in m.findall("connections/connection"):
        child = mc.find("macro")
        if child is None or not child.get("ref"):
            continue
        clo, chi = macro_box(child.get("ref"))
        c = tuple((a + b) / 2 for a, b in zip(clo, chi))
        h = tuple((b - a) / 2 for a, b in zip(clo, chi))
        if math.sqrt(sum(v * v for v in h)) < 1e-4:
            continue
        ccomp = component(macro(child.get("ref")).find("component").get("ref"))
        attach = connections(ccomp).get(child.get("connection"))
        pconn = conns.get(mc.get("ref"))
        if attach is None or pconn is None:
            raise StudyError(f"unresolved macro connection {name}:{mc.get('ref')}->{child.get('connection')}")
        tr = compose(_inverse(conn_world(ccomp, attach)), conn_world(comp, pconn))
        box = _union(box, [_xf(q, tr) for q in _corners(c, h)])
    return box


def center_half(name):
    lo, hi = macro_box(name)
    return tuple((a + b) / 2 for a, b in zip(lo, hi)), tuple((b - a) / 2 for a, b in zip(lo, hi))


if __name__ == "__main__":
    print(sum(len(v) for v in COMPONENTS.values()), len(COMPONENTS))
    for n in ["ship_tel_xl_builder_01_a_macro", "ship_arg_m_frigate_01_a_macro", "turret_tel_m_gatling_01_mk1_macro",
              "engine_arg_l_allround_01_mk1_macro", "ship_tel_l_trans_container_03_a_macro"]:
        print(n, *("(%s)" % ",".join("%.8f" % v for v in x) for x in center_half(n)))
