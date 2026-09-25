"""Issue #202: X4 9.00 collision geometry and ray casting for the settled-shot benchmark.

Reads the installed game catalogs directly (read-only, nothing extracted into the repository):
`-collision.xmf` triangle meshes and the Jolt `-hull.jcs` convex shapes that X4's geometry loader
(`0x140F51360`) loads next to its `-mesh.jcs` triangle shape. Which of the two shapes the layer-3
pre-fire / `check_line_of_sight` body uses is not traced, so every ray is cast against both:

- MESH: the collision triangle mesh, two-sided;
- HULL: the Jolt convex pieces, solid (Jolt's default `mTreatConvexAsSolid`).

Parts whose effective tags include `nocollision`, `triggerpart` or `platformcollision` are skipped,
as the layer-3 builder does (`weapon-path-obstruction-groups.md`); `nocollision_jolt` parts are kept.
Row-vector transforms `(t, R)` as in `scripts/barrelposition_evaluator.py`.
"""
from __future__ import annotations

import glob
import re
import struct
import sys
import zlib
from functools import lru_cache
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "research/issue167-p3c"), str(ROOT / "scripts")]
import sources as S  # noqa: E402

X4 = Path("/mnt/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations")
LAYER3_SKIP = {"nocollision", "triggerpart", "platformcollision"}


# ---------------------------------------------------------------- catalogs

@lru_cache(maxsize=None)
def _catalog():
    index = {}
    cats = sorted(glob.glob(str(X4 / "*.cat"))) + sorted(glob.glob(str(X4 / "extensions/*/*.cat")))
    for cat in (c for c in cats if not c.endswith("_sig.cat")):
        offset = 0
        for line in open(cat, encoding="utf-8", errors="replace"):
            path, size, _stamp, _md5 = line.rstrip("\n").rsplit(" ", 3)
            index[path.lower()] = (cat[:-4] + ".dat", offset, int(size))  # later catalogs override
            offset += int(size)
    return index


def read(path):
    """Bytes of one catalog file, or None if the game does not ship it."""
    entry = _catalog().get(path.lower())
    if entry is None:
        return None
    dat, offset, size = entry
    with open(dat, "rb") as stream:
        stream.seek(offset)
        return stream.read(size)


# ---------------------------------------------------------------- file formats

_ELEMENT_SIZE = {0: 4, 1: 8, 2: 12, 3: 16, 4: 4, 5: 4, 6: 4, 7: 8, 8: 4, 9: 4, 10: 8, 11: 4, 12: 8,
                 13: 4, 14: 4, 15: 4, 16: 8}


def xmf_triangles(data):
    """XUMF v3 -> (n, 3, 3) float64 triangles in the part frame (reader recovered from #171)."""
    assert data[:5] == b"XUMF\x03" and struct.unpack_from("<I", data, 22)[0] == 4
    nbuf, dsize, nmat, msize = data[8], data[9], data[10], data[11]
    descs, o = [], 0x40
    for _ in range(nbuf):
        kind, _u, doff, packed, _x, fmt, csize, nitems, isize, _n = struct.unpack_from("<10I", data, o)
        count = struct.unpack_from("<I", data, o + 56)[0]
        elems = [struct.unpack_from("<IBB", data, o + 60 + 8 * k) for k in range(16)][:count]
        descs.append((kind, doff, packed, fmt, csize, nitems, isize, elems))
        o += dsize
    base, verts, index = o + nmat * msize, None, None
    for kind, doff, packed, fmt, csize, nitems, isize, elems in descs:
        raw = data[base + doff:base + doff + csize]
        raw = zlib.decompress(raw) if packed else raw
        if kind == 30:
            index = np.frombuffer(raw, np.uint16 if fmt == 30 else np.uint32).astype(np.int64)
            continue
        elems = elems or ([(fmt, 0, 0)] if kind in (0, 1) else [])
        at = 0
        for etype, usage, uindex in elems:
            if usage == 0 and uindex == 0 and verts is None:
                rows = np.frombuffer(raw, np.uint8).reshape(nitems, isize)[:, at:at + 12]
                verts = rows.copy().view(np.float32).reshape(nitems, 3).astype(np.float64)
            at += _ELEMENT_SIZE[etype]
    return verts[index.reshape(-1, 3)]


def _floats(data, o, n):
    return np.array(struct.unpack_from(f"<{n}f", data, o))


def _convex(data, o):
    """Jolt ConvexHullShape binary state at the subtype byte `o` -> (points, planes n·x + c <= 0)."""
    assert data[o] == 6
    com = _floats(data, o + 13, 3)                       # points are stored about the centre of mass
    n = struct.unpack_from("<I", data, o + 113)[0]
    p = o + 117
    points = np.array([_floats(data, p + 32 * i, 3) for i in range(n)]) + com
    p += 32 * n
    p += 4 + 4 * struct.unpack_from("<I", data, p)[0]    # faces
    m = struct.unpack_from("<I", data, p)[0]
    planes = np.array([_floats(data, p + 4 + 16 * i, 4) for i in range(m)])
    planes[:, 3] -= planes[:, :3] @ com
    return points, planes


_CHILD = re.compile(re.escape(b"\x06" + b"\0" * 8 + struct.pack("<f", 1000.0)))


def jcs_hulls(data):
    """X4 `-hull.jcs`: one ConvexHull (subtype 6) or a StaticCompound (7) of unrotated ConvexHulls."""
    if data[4] == 6:
        return [_convex(data, 4)]
    assert data[4] == 7, data[4]
    com, n = _floats(data, 13, 3), struct.unpack_from("<I", data, 53)[0]
    starts = [m.start() for m in _CHILD.finditer(data)]
    assert len(starts) == n, (len(starts), n)
    hulls = []
    for i, s in enumerate(starts):
        pos, rot = _floats(data, 61 + 28 * i, 3), _floats(data, 73 + 28 * i, 3)
        assert not rot.any(), "rotated compound child"
        points, planes = _convex(data, s)
        shift = pos + com - _floats(data, s + 13, 3)
        planes[:, 3] -= planes[:, :3] @ shift
        hulls.append((points + shift, planes))
    return hulls


# ---------------------------------------------------------------- components

def _geometry_dir(comp):
    path = comp.find("source").get("geometry").replace("\\", "/").lower()
    return re.sub(r"^extensions/[^/]+/", "", re.sub("/+", "/", path))


class Body:
    """Layer-3 collision parts of one component in its own frame, in both shape models."""

    def __init__(self, triangles, hulls, parts, part_of):
        self.tris, self.hulls, self.parts = triangles, hulls, parts
        self.planes = np.concatenate([planes for _points, planes in hulls])
        self.starts = np.cumsum([0] + [len(planes) for _points, planes in hulls])[:-1]
        self.lo, self.hi = triangles.reshape(-1, 3).min(0), triangles.reshape(-1, 3).max(0)
        order = _median_order(triangles.mean(1))
        self.tris, self.part_of = triangles[order], part_of[order]
        leaves = self.tris.reshape(-1, 3)[:len(order) // LEAF * LEAF * 3].reshape(-1, LEAF * 3, 3)
        tail = self.tris[len(order) // LEAF * LEAF:].reshape(-1, 3)
        self.leaf_lo = np.array([leaf.min(0) for leaf in leaves] + ([tail.min(0)] if len(tail) else []))
        self.leaf_hi = np.array([leaf.max(0) for leaf in leaves] + ([tail.max(0)] if len(tail) else []))


LEAF = 64


def _median_order(points):
    """Spatial triangle order (recursive median split) so consecutive LEAF-sized runs are compact."""
    idx = np.arange(len(points))
    stack, out = [idx], []
    while stack:
        cur = stack.pop()
        if len(cur) <= LEAF:
            out.append(cur)
            continue
        axis = np.ptp(points[cur], 0).argmax()
        cur = cur[np.argsort(points[cur, axis], kind="stable")]
        half = (len(cur) // 2 + LEAF - 1) // LEAF * LEAF
        stack += [cur[half:], cur[:half]]
    return np.concatenate(out)


@lru_cache(maxsize=None)
def body(component):
    """Collision Body of an official component (static parts; connection frames as #167/#171)."""
    comp = S.component(component)
    tris, hulls, parts, part_of = [], [], [], []
    for conn in S.connections(comp).values():
        for part in (p for g in conn.findall("parts") for p in g.findall("part")):
            owner, name, tags = comp, part.get("name"), S.tags(conn)
            if part.get("ref"):
                src, name = part.get("ref").split(".", 1)
                owner = S.component(src)
                tags |= S.tags(S.part_owner(owner)[name])
            if tags & LAYER3_SKIP:
                continue
            stem = f"{_geometry_dir(owner)}/{name.lower()}"
            mesh, hull = read(stem + "-collision.xmf"), read(stem + "-hull.jcs")
            if mesh is None or hull is None:
                raise FileNotFoundError(f"{component}: {stem} lacks collision mesh or hull")
            t, R = (np.asarray(v) for v in S.conn_world(comp, conn))
            tris.append(xmf_triangles(mesh) @ R + t)
            part_of.append(np.full(len(tris[-1]), len(parts)))
            for points, planes in jcs_hulls(hull):
                normals = planes[:, :3] @ R                     # rigid: n' = n·R, c' = c - n'·t
                hulls.append((points @ R + t, np.column_stack([normals, planes[:, 3] - normals @ t])))
            parts.append(name)
    return Body(np.concatenate(tris), hulls, tuple(parts), np.concatenate(part_of)) if tris else None


# ---------------------------------------------------------------- ray casting

EPS = 1e-6


def _slab(o, inv, lo, hi):
    t1, t2 = (lo - o) * inv, (hi - o) * inv
    return np.minimum(t1, t2).max(-1), np.maximum(t1, t2).min(-1)


def cast_mesh(b, o, d, tmax):
    """Closest two-sided triangle hit distance along unit `d` within (EPS, tmax], or None."""
    with np.errstate(divide="ignore", invalid="ignore"):
        inv = 1.0 / d
        near, far = _slab(o, inv, b.lo, b.hi)
        if not (near <= far and far >= 0 and near <= tmax):
            return None
        near, far = _slab(o, inv, b.leaf_lo, b.leaf_hi)
    leaves = np.nonzero((near <= far) & (far >= 0) & (near <= tmax))[0]
    if not len(leaves):
        return None
    ids = (leaves[:, None] * LEAF + np.arange(LEAF)).ravel()
    tri = b.tris[ids[ids < len(b.tris)]]
    e1, e2 = tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]
    p = np.cross(d, e2)
    det = (e1 * p).sum(1)
    ok = np.abs(det) > 1e-12
    inv_det = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    s = o - tri[:, 0]
    u = (s * p).sum(1) * inv_det
    q = np.cross(s, e1)
    v = (q @ d) * inv_det
    t = (e2 * q).sum(1) * inv_det
    hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > EPS) & (t <= tmax)
    return float(t[hit].min()) if hit.any() else None


def cast_hull(b, o, d, tmax):
    """Closest entry into a solid convex piece along unit `d` within [0, tmax], or None."""
    n, c = b.planes[:, :3], b.planes[:, 3]
    dn, on = n @ d, n @ o + c
    with np.errstate(divide="ignore", invalid="ignore"):
        t = -on / dn
    enter = np.maximum(np.maximum.reduceat(np.where(dn < 0, t, -np.inf), b.starts), 0.0)
    leave = np.minimum.reduceat(np.where(dn > 0, t, np.inf), b.starts)
    outside = np.logical_or.reduceat((dn == 0) & (on > 0), b.starts)
    hit = ~outside & (enter <= leave) & (enter <= tmax)
    return float(enter[hit].min()) if hit.any() else None


_BOXES = {}


def _world_boxes(instances):
    key = id(instances)
    if key not in _BOXES or _BOXES[key][0] is not instances:
        lo, hi = [], []
        for _label, b, (t, R) in instances:
            c = np.array([[(b.hi if k >> i & 1 else b.lo)[i] for i in range(3)] for k in range(8)]) @ R + t
            lo.append(c.min(0))
            hi.append(c.max(0))
        _BOXES[key] = (instances, np.array(lo), np.array(hi))
    return _BOXES[key][1:]


def first_hit(instances, o, e=None, d=None, tmax=None, model="mesh", skip=(), runner_up=False):
    """Closest hit (label, distance) on segment o->e (or ray o + t·d, t <= tmax), else (None, inf).
    With runner_up, also the closest hit on any other instance: (label, t, label2, t2).

    instances: [(label, Body, (t, R))]; the list must not be mutated after its first use."""
    if e is not None:
        seg = np.asarray(e) - o
        tmax = float(np.linalg.norm(seg))
        d = seg / tmax
    lo, hi = _world_boxes(instances)
    with np.errstate(divide="ignore", invalid="ignore"):
        near, far = _slab(o, 1.0 / d, lo, hi)
    cast = cast_mesh if model == "mesh" else cast_hull
    best, second = (None, np.inf), (None, np.inf)
    for i in np.nonzero((near <= far) & (far >= 0) & (near <= tmax))[0]:
        label, b, (t, R) = instances[i]
        if label in skip:
            continue
        hit = cast(b, (o - t) @ R.T, d @ R.T, tmax)       # into the body frame; rigid, t is preserved
        if hit is not None and hit < best[1]:
            best, second = (label, hit), best
        elif hit is not None and hit < second[1]:
            second = (label, hit)
    return (*best, *second) if runner_up else best


def inside(b, p, model):
    """Is body-frame point p inside the body? HULL: inside any solid convex piece. MESH: odd crossings of
    one part's two-sided triangles along +Y, as Jolt's closed-mesh CollidePoint (parity, per part)."""
    if model == "hull":
        on = b.planes[:, :3] @ p + b.planes[:, 3]
        return bool(np.logical_and.reduceat(on <= 0, b.starts).any())
    d = np.array([0.0, 1.0, 0.0])
    tri = b.tris
    e1, e2 = tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]
    q = np.cross(d, e2)
    det = (e1 * q).sum(1)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
    s = p - tri[:, 0]
    u = (s * q).sum(1) * inv
    r = np.cross(s, e1)
    v = (r @ d) * inv
    t = (e2 * r).sum(1) * inv
    crossed = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)
    return bool((np.bincount(b.part_of[crossed], minlength=len(b.parts)) % 2).any())
