#!/usr/bin/env python3
"""Standalone turret kinematics extractor for X4 9.00 turret components.

Parses component XML and ANI binary files to extract the ordered transform
chain from mount to muzzle endpoint(s). Classifies each asset as:
  RESOLVED   – full geometry derived from source; muzzle computable
  AMBIGUOUS  – structure valid but required ANI data not available
  UNSUPPORTED – structure does not conform to any supported topology

No faction/macro/name-based special cases. Classification is purely
structural: hierarchy shape, restriction types, and part-name semantics.
"""
from __future__ import annotations

import argparse
import math
import struct
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator


# ---------------------------------------------------------------------------
# Math primitives (no numpy dependency)
# ---------------------------------------------------------------------------

@dataclass
class Vec3:
    x: float
    y: float
    z: float

    def __add__(self, o: Vec3) -> Vec3:
        return Vec3(self.x + o.x, self.y + o.y, self.z + o.z)

    def __sub__(self, o: Vec3) -> Vec3:
        return Vec3(self.x - o.x, self.y - o.y, self.z - o.z)

    def length(self) -> float:
        return (self.x**2 + self.y**2 + self.z**2) ** 0.5

    def __repr__(self) -> str:
        return f"Vec3({self.x:.6g}, {self.y:.6g}, {self.z:.6g})"


ZERO = Vec3(0.0, 0.0, 0.0)


@dataclass
class Quat:
    """Unit quaternion (qx, qy, qz, qw) representing a rotation."""
    qx: float
    qy: float
    qz: float
    qw: float

    def rotate(self, v: Vec3) -> Vec3:
        """Apply this rotation to a vector."""
        tx = 2 * (self.qy * v.z - self.qz * v.y)
        ty = 2 * (self.qz * v.x - self.qx * v.z)
        tz = 2 * (self.qx * v.y - self.qy * v.x)
        return Vec3(
            v.x + self.qw * tx + self.qy * tz - self.qz * ty,
            v.y + self.qw * ty + self.qz * tx - self.qx * tz,
            v.z + self.qw * tz + self.qx * ty - self.qy * tx,
        )

    def __mul__(self, o: Quat) -> Quat:
        """Compose two quaternions: self then o."""
        return Quat(
            self.qw * o.qx + self.qx * o.qw + self.qy * o.qz - self.qz * o.qy,
            self.qw * o.qy - self.qx * o.qz + self.qy * o.qw + self.qz * o.qx,
            self.qw * o.qz + self.qx * o.qy - self.qy * o.qx + self.qz * o.qw,
            self.qw * o.qw - self.qx * o.qx - self.qy * o.qy - self.qz * o.qz,
        )

    def norm_sq(self) -> float:
        return self.qx**2 + self.qy**2 + self.qz**2 + self.qw**2

    def __repr__(self) -> str:
        return f"Quat({self.qx:.6g}, {self.qy:.6g}, {self.qz:.6g}, {self.qw:.6g})"


IDENTITY = Quat(0.0, 0.0, 0.0, 1.0)


# ---------------------------------------------------------------------------
# ANI binary parser
# ---------------------------------------------------------------------------

_ANI_DESC_RECORD = 160   # bytes per descriptor record
_ANI_KF_BLOCK    = 128   # bytes per keyframe block

def parse_ani(path: Path) -> dict[tuple[str, str], Vec3]:
    """Parse source-proven ANI v1 translation records.

    The extractor only represents translation channels.  Every key of a
    ``turret_active`` record must carry the same translation, which proves a
    stable active pose for the narrow model.  Truncated records or changing
    active translations are deliberately rejected rather than guessed.
    """
    data = path.read_bytes()
    if len(data) < 16:
        raise ValueError("ANI header is truncated")
    num_records, _desc_size = struct.unpack_from("<II", data, 0)
    desc_start = 16
    desc_end = desc_start + num_records * _ANI_DESC_RECORD
    if desc_end > len(data):
        raise ValueError("ANI descriptor section is truncated")

    records: list[tuple[str, str, int]] = []
    for i in range(num_records):
        off = desc_start + i * _ANI_DESC_RECORD
        part = data[off: off + 64].split(b"\x00")[0].decode("ascii", errors="replace")
        anim = data[off + 64: off + 128].split(b"\x00")[0].decode("ascii", errors="replace")
        records.append((part, anim, struct.unpack_from("<I", data, off + 128)[0]))

    translations: dict[tuple[str, str], Vec3] = {}
    kf_offset = 0
    for part, anim, nkeys in records:
        end = desc_end + kf_offset + nkeys * _ANI_KF_BLOCK
        if end > len(data):
            raise ValueError(f"ANI keyframes truncated for {part}/{anim}")
        if nkeys:
            keys = [Vec3(*map(float, struct.unpack_from("<3f", data, desc_end + kf_offset + i * _ANI_KF_BLOCK))) for i in range(nkeys)]
            if anim == "turret_active" and any(k != keys[0] for k in keys[1:]):
                raise ValueError(f"ANI active pose is not constant for {part}")
            translations[(part, anim)] = keys[0]
        else:
            # An explicit zero-key descriptor source-proves an identity transform.
            translations[(part, anim)] = ZERO
        kf_offset += nkeys * _ANI_KF_BLOCK
    return translations


# ---------------------------------------------------------------------------
# XML connection model
# ---------------------------------------------------------------------------

@dataclass
class ConnInfo:
    name: str
    tags: set[str]
    parent: str          # parent part name, empty string = root
    pos: Vec3
    quat: Quat           # stored quaternion values used directly (not conjugated)
    restriction: str     # "rotation_y", "rotation_x", or ""
    limits: tuple[float, float] | None
    parts: list[str]     # direct geometry part names created by this connection
    declares_active: bool # XML explicitly declares the turret_active animation


def _parse_quat(elem: ET.Element | None) -> Quat:
    if elem is None:
        return IDENTITY
    # Turret component internal connections use stored quaternion values directly.
    # (The KB inverted-quaternion finding applies to ship-hull-to-weapon-slot connections,
    # not to the turret's own kinematic connections.)
    return Quat(
        float(elem.get("qx", 0)),
        float(elem.get("qy", 0)),
        float(elem.get("qz", 0)),
        float(elem.get("qw", 1)),
    )


def _parse_pos(elem: ET.Element | None) -> Vec3:
    if elem is None:
        return ZERO
    return Vec3(
        float(elem.get("x", 0)),
        float(elem.get("y", 0)),
        float(elem.get("z", 0)),
    )


def parse_xml(path: Path) -> tuple[str, str, str, list[ConnInfo]]:
    """Parse component XML.  Returns (class, name, geometry_source, connections)."""
    doc = ET.parse(path)
    comp = doc.find('.//component[@class="turret"]')
    if comp is None:
        comp = doc.find('.//component[@class="missileturret"]')
    if comp is None:
        return "", "", "", []

    cls = comp.get("class", "")
    name = comp.get("name", "")
    src = comp.findtext(".//source", default="")
    if src == "":
        src_elem = comp.find("source")
        src = src_elem.get("geometry", "") if src_elem is not None else ""

    conns: list[ConnInfo] = []
    for conn in comp.findall(".//connection"):
        cname = conn.get("name", "")
        tags = set(conn.get("tags", "").split())
        parent = conn.get("parent", "")
        offset = conn.find("offset")
        pos = _parse_pos(offset.find("position") if offset is not None else None)
        quat = _parse_quat(offset.find("quaternion") if offset is not None else None)
        restriction = ""
        limits: tuple[float, float] | None = None
        for r in conn.findall(".//restriction"):
            rt = r.get("type", "")
            if rt in ("rotation_y", "rotation_x"):
                restriction = rt
                lim = r.find("limits")
                if lim is not None:
                    mn = lim.find("min")
                    mx = lim.find("max")
                    if mn is not None and mx is not None:
                        limits = (float(mn.get("value", 0)), float(mx.get("value", 0)))
        parts_elem = conn.find("parts")
        parts = [p.get("name", "") for p in (parts_elem.findall("part") if parts_elem is not None else [])]
        conns.append(ConnInfo(
            name=cname,
            tags=tags,
            parent=parent,
            pos=pos,
            quat=quat,
            restriction=restriction,
            limits=limits,
            parts=parts,
            declares_active=any(a.get("name") == "turret_active" for a in conn.findall("animations/animation")),
        ))
    return cls, name, src, conns


# ---------------------------------------------------------------------------
# ANI file discovery
# ---------------------------------------------------------------------------

def find_ani(geometry_source: str, search_dirs: list[Path]) -> Path | None:
    """Locate the ANI file for a component given its geometry source path."""
    if not geometry_source:
        return None
    # geometry_source looks like "assets\props\WeaponSystems\energy\turret_par_l_beam_01_mk1_data"
    # ANI filename is the last path component (uppercase) + ".ANI"
    leaf = geometry_source.replace("\\", "/").split("/")[-1]
    ani_name = leaf.upper() + ".ANI"
    for root in search_dirs:
        # Walk the research cache tree looking for the file case-insensitively
        for candidate in root.rglob("*"):
            if candidate.name.upper() == ani_name:
                return candidate
    return None


# ---------------------------------------------------------------------------
# Kinematic extractor
# ---------------------------------------------------------------------------

@dataclass
class KinematicTransform:
    """One source-derived connection on a root-to-endpoint path."""
    connection: str
    position: Vec3
    rotation: Quat
    joint_axis: str
    active_translation: Vec3


@dataclass
class KinematicPath:
    endpoint: str
    transforms: list[KinematicTransform]


@dataclass
class TurretKinematics:
    component: str
    status: str           # RESOLVED | AMBIGUOUS | UNSUPPORTED
    reason: str           # empty if RESOLVED
    topology: str         # descriptive topology group label
    # RESOLVED-only fields
    yaw_origin: Vec3 | None = None            # in component space, active pose
    elevation_pivot: Vec3 | None = None       # from yaw_origin, pre-yaw-rotation
    muzzle_offsets: list[Vec3] = field(default_factory=list)  # from elev_pivot, pre-pitch-rotation
    pitch_limits: tuple[float, float] | None = None
    # Frames are retained rather than lowering joints to component-space Ry/Rx.
    yaw_joint_frame: Quat = field(default_factory=lambda: IDENTITY)
    fixed_rot_yaw_to_pitch: Quat = field(default_factory=lambda: IDENTITY)
    paths: list[KinematicPath] = field(default_factory=list)
    muzzle_count: int = 0


def _ancestors(conn_name: str, conn_map: dict[str, ConnInfo],
               part_to_conn: dict[str, str]) -> list[ConnInfo]:
    """Walk from conn upward to root, returning path [conn ... root] inclusive."""
    path = []
    cursor = conn_name
    seen = set()
    while cursor and cursor not in seen:
        seen.add(cursor)
        info = conn_map.get(cursor)
        if info is None:
            break
        path.append(info)
        parent_part = info.parent
        if not parent_part:
            break
        creator = part_to_conn.get(parent_part)
        if creator is None:
            break
        cursor = creator
    return path  # path[0] = laser conn, path[-1] = root conn


def extract_kinematics(
    xml_path: Path,
    search_dirs: list[Path],
) -> TurretKinematics:
    comp_name = xml_path.stem

    cls, name, geo_src, conns = parse_xml(xml_path)

    if not cls:
        return TurretKinematics(
            component=comp_name, status="UNSUPPORTED",
            reason="no-supported-class", topology="",
        )

    conn_map = {c.name: c for c in conns}
    # Part → which connection creates it
    part_to_conn: dict[str, str] = {}
    for c in conns:
        for p in c.parts:
            part_to_conn[p] = c.name

    # Identify joints and endpoints
    yaw_conns  = [c for c in conns if c.restriction == "rotation_y"]
    pitch_conns = [c for c in conns if c.restriction == "rotation_x"]
    laser_conns = [c for c in conns if "laser" in c.tags]
    rocket_conns = [c for c in conns if "rocket" in c.tags]
    endpoint_conns = laser_conns + rocket_conns

    if not yaw_conns or not pitch_conns:
        return TurretKinematics(
            component=comp_name, status="UNSUPPORTED",
            reason=f"missing-joints(yaw={len(yaw_conns)},pitch={len(pitch_conns)})",
            topology="",
        )
    if not endpoint_conns:
        return TurretKinematics(
            component=comp_name, status="UNSUPPORTED",
            reason="no-muzzle-endpoints", topology="",
        )
    if len(yaw_conns) != 1 or len(pitch_conns) != 1:
        return TurretKinematics(
            component=comp_name, status="UNSUPPORTED",
            reason=f"ambiguous-joints(yaw={len(yaw_conns)},pitch={len(pitch_conns)})",
            topology="",
        )

    yaw_c  = yaw_conns[0]
    pitch_c = pitch_conns[0]

    # Verify ordering: yaw must be an ancestor of pitch
    pitch_path = _ancestors(pitch_c.name, conn_map, part_to_conn)
    pitch_path_names = {c.name for c in pitch_path}
    if yaw_c.name not in pitch_path_names:
        return TurretKinematics(
            component=comp_name, status="UNSUPPORTED",
            reason="yaw-not-above-pitch", topology="",
        )

    # Verify each endpoint has pitch as an ancestor
    for ep in endpoint_conns:
        ep_path = _ancestors(ep.name, conn_map, part_to_conn)
        ep_path_names = {c.name for c in ep_path}
        if pitch_c.name not in ep_path_names:
            return TurretKinematics(
                component=comp_name, status="UNSUPPORTED",
                reason=f"endpoint-{ep.name}-not-below-pitch", topology="",
            )

    # XML declares the active pose; its scope is the actual endpoint ancestor
    # path, not a convention in a geometry part name.  ANI records then identify
    # which of those path parts move.  A sibling ANI record is intentionally not
    # a transform of this muzzle path.
    endpoint_paths = {ep.name: _path for ep in endpoint_conns
                      for _path in [_ancestors(ep.name, conn_map, part_to_conn)]}
    active_declared_on_path = any(c.declares_active for path in endpoint_paths.values() for c in path)

    # An ANI can attach active transforms to a path even when its XML declaration
    # is elsewhere in the component. Parse a discoverable source unconditionally;
    # only a declared active path makes a missing ANI ambiguous.
    ani_data: dict[tuple[str, str], Vec3] = {}
    ani_path = find_ani(geo_src, search_dirs)
    if ani_path is None:
        if active_declared_on_path:
            return TurretKinematics(component=comp_name, status="AMBIGUOUS",
                                    reason="active-path-ani-not-found", topology="ANI_PATH")
    else:
        try:
            ani_data = parse_ani(ani_path)
        except (OSError, ValueError) as exc:
            return TurretKinematics(component=comp_name, status="AMBIGUOUS",
                                    reason=f"active-path-ani-unparseable({exc})", topology="ANI_PATH")
    needs_ani = bool(ani_data) or active_declared_on_path

    def _path_part(path: list[ConnInfo], index: int) -> str | None:
        """The exact part carrying this connection to the next path node."""
        if index + 1 >= len(path):
            return None
        part = path[index + 1].parent
        return part if part in path[index].parts else None

    def _active_for(path: list[ConnInfo], index: int) -> Vec3:
        part = _path_part(path, index)
        return ani_data.get((part, "turret_active"), ZERO) if part else ZERO

    # A declared active pose requires an explicit ANI record (including a
    # zero-key identity record) for every carried path part. Missing data is not
    # evidence of a zero transform.
    if active_declared_on_path:
        # endpoint_paths are child→root here, so each non-root connection's
        # parent attribute names the carried part required from its creator.
        required_parts = {c.parent for path in endpoint_paths.values() for c in path if c.parent}
        missing_parts = sorted(part for part in required_parts if (part, "turret_active") not in ani_data)
        if missing_parts:
            return TurretKinematics(component=comp_name, status="AMBIGUOUS",
                                    reason="active-path-ani-missing(" + ",".join(missing_parts) + ")",
                                    topology="ANI_PATH")

    # -----------------------------------------------------------------------
    # Accumulate transforms from root to yaw, then yaw to pitch, then to each
    # endpoint.  YAW and PITCH joints are set to 0 (rest/prospective pose).
    # -----------------------------------------------------------------------

    # Build ordered path from root to an arbitrary target connection
    def _path_to_root(conn_name: str) -> list[ConnInfo]:
        return list(reversed(_ancestors(conn_name, conn_map, part_to_conn)))

    def _accumulate(
        path: list[ConnInfo],
        stop_before: str | None,
        ani: dict[tuple[str, str], Vec3],
    ) -> tuple[Vec3, Quat]:
        """Accumulate transforms along path, stopping before stop_before.

        ANI translations are applied in the parent frame (before the
        connection's own quaternion), matching the Lua test ordering:
            pos_child = parent_rot * (connection.pos + ani_t)
            rot_child  = parent_rot * connection.quat
        """
        pos = ZERO
        rot = IDENTITY
        for index, c in enumerate(path):
            if stop_before and c.name == stop_before:
                break
            pos = pos + rot.rotate(c.pos)
            # The carried part is the only one on this endpoint path.
            pos = pos + rot.rotate(_active_for(path, index))
            rot = rot * c.quat
        return pos, rot

    path_to_yaw   = _path_to_root(yaw_c.name)
    path_yaw_to_pitch = _path_to_root(pitch_c.name)
    # Segment path_yaw_to_pitch into [yaw..root] portion to find intermediate nodes
    try:
        yaw_idx = next(i for i, c in enumerate(path_yaw_to_pitch) if c.name == yaw_c.name)
        path_below_yaw = path_yaw_to_pitch[yaw_idx:]  # [yaw, pitch, ...]  (root→pitch order)
    except StopIteration:
        return TurretKinematics(
            component=comp_name, status="UNSUPPORTED",
            reason="yaw-not-in-pitch-path", topology="",
        )

    # --- Yaw origin in component space ---
    # _accumulate stops BEFORE yaw_c to avoid double-counting yaw_c's ANI below.
    yaw_origin, rot_at_yaw = _accumulate(path_to_yaw, stop_before=yaw_c.name, ani=ani_data)
    yaw_origin = yaw_origin + rot_at_yaw.rotate(yaw_c.pos)
    yaw_index = next(i for i, c in enumerate(path_yaw_to_pitch) if c.name == yaw_c.name)
    yaw_origin = yaw_origin + rot_at_yaw.rotate(_active_for(path_yaw_to_pitch, yaw_index))
    rot_at_yaw = rot_at_yaw * yaw_c.quat  # quat applied after ANI

    # --- Elevation pivot: from yaw to pitch (local to yaw frame, yaw-DOF=0) ---
    elev_local = ZERO
    rot_yaw_local = IDENTITY
    for index, c in enumerate(path_below_yaw[1:], start=1):  # skip yaw
        if c.name == pitch_c.name:
            break
        elev_local = elev_local + rot_yaw_local.rotate(c.pos)
        elev_local = elev_local + rot_yaw_local.rotate(_active_for(path_below_yaw, index))
        rot_yaw_local = rot_yaw_local * c.quat
    # The pitch connection's carried part belongs to an endpoint path, not the
    # truncated yaw→pitch segment.  A legacy common pivot is only valid when all
    # endpoints carry the same pitch-created part; full paths remain canonical.
    pitch_paths = [_path_to_root(ep.name) for ep in endpoint_conns]
    pitch_indices = [next(i for i, c in enumerate(path) if c.name == pitch_c.name)
                     for path in pitch_paths]
    pitch_carriers = {_path_part(path, index) for path, index in zip(pitch_paths, pitch_indices)}
    if len(pitch_carriers) != 1:
        return TurretKinematics(component=comp_name, status="UNSUPPORTED",
                                reason="endpoint-specific-pitch-carrier", topology="")
    elev_local = elev_local + rot_yaw_local.rotate(pitch_c.pos)
    elev_local = elev_local + rot_yaw_local.rotate(_active_for(pitch_paths[0], pitch_indices[0]))
    rot_at_pitch = rot_yaw_local * pitch_c.quat

    # --- Muzzle offsets: from pitch pivot to each endpoint ---
    # Expressed in the pitch-DOF=0 frame.  rot_at_pitch (the pitch joint's fixed
    # quaternion) is the starting orientation – this matches how the Lua test applies
    # gun_base_rotation to the downstream vector before the pitch DOF is applied.
    def _muzzle_from_pitch(ep: ConnInfo) -> Vec3:
        ep_path = _path_to_root(ep.name)
        try:
            pitch_idx = next(i for i, c in enumerate(ep_path) if c.name == pitch_c.name)
        except StopIteration:
            return ZERO
        local_pos = ZERO
        local_rot = rot_at_pitch  # start in the pitch-fixed-rotation frame
        for index, c in enumerate(ep_path[pitch_idx + 1:], start=pitch_idx + 1):
            if c.name == ep.name:
                break
            local_pos = local_pos + local_rot.rotate(c.pos)
            local_pos = local_pos + local_rot.rotate(_active_for(ep_path, index))
            local_rot = local_rot * c.quat
        local_pos = local_pos + local_rot.rotate(ep.pos)
        return local_pos

    muzzle_offsets = [_muzzle_from_pitch(ep) for ep in endpoint_conns]

    # --- Topology label ---
    _angle = 2.0 * math.acos(min(1.0, abs(rot_at_pitch.qw)))
    has_fixed_rot = _angle > math.radians(0.5)  # > ~0.5 degrees
    if needs_ani:
        topology = "ANI_BARREL"
    elif cls == "missileturret":
        topology = "MISSILE_SIMPLE"
    elif has_fixed_rot:
        topology = "FIXED_ROT_YAW_PITCH"
    else:
        topology = "SIMPLE_YAW_PITCH"

    model_paths = []
    for ep in endpoint_conns:
        path = _path_to_root(ep.name)
        model_paths.append(KinematicPath(
            endpoint=ep.name,
            transforms=[KinematicTransform(
                connection=c.name, position=c.pos, rotation=c.quat,
                joint_axis=c.restriction, active_translation=_active_for(path, i),
            ) for i, c in enumerate(path)],
        ))

    return TurretKinematics(
        component=comp_name,
        status="RESOLVED",
        reason="",
        topology=topology,
        yaw_origin=yaw_origin,
        elevation_pivot=elev_local,
        muzzle_offsets=muzzle_offsets,
        pitch_limits=pitch_c.limits,
        yaw_joint_frame=rot_at_yaw,
        fixed_rot_yaw_to_pitch=rot_at_pitch,
        paths=model_paths,
        muzzle_count=len(muzzle_offsets),
    )


# ---------------------------------------------------------------------------
# Census
# ---------------------------------------------------------------------------

def _xml_files(root: Path) -> Iterator[Path]:
    yield from sorted(root.rglob("*.xml"))


def run_census(
    corpus_dir: Path,
    search_dirs: list[Path],
) -> list[TurretKinematics]:
    results = []
    for xml_path in _xml_files(corpus_dir):
        if "macros" in xml_path.parts:
            continue
        results.append(extract_kinematics(xml_path, search_dirs))
    return results


def print_census(results: list[TurretKinematics]) -> None:
    total = len(results)
    by_status: dict[str, list[TurretKinematics]] = {}
    for r in results:
        by_status.setdefault(r.status, []).append(r)

    print(f"total: {total}")
    for status in ("RESOLVED", "AMBIGUOUS", "UNSUPPORTED"):
        entries = by_status.get(status, [])
        print(f"{status}: {len(entries)}")

    # Topology groups for RESOLVED
    if "RESOLVED" in by_status:
        topo_counts: dict[str, int] = {}
        for r in by_status["RESOLVED"]:
            topo_counts[r.topology] = topo_counts.get(r.topology, 0) + 1
        print("\nresolved topology groups:")
        for topo, count in sorted(topo_counts.items()):
            print(f"  {topo}: {count}")

    # Non-resolved detail
    for status in ("AMBIGUOUS", "UNSUPPORTED"):
        entries = by_status.get(status, [])
        if entries:
            print(f"\n{status.lower()} detail:")
            reason_counts: dict[str, list[str]] = {}
            for r in entries:
                reason_counts.setdefault(r.reason, []).append(r.component)
            for reason, comps in sorted(reason_counts.items()):
                print(f"  {reason} ({len(comps)}): {', '.join(comps)}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(
        description="Extract turret kinematics from X4 9.00 component sources."
    )
    ap.add_argument("corpus", type=Path, help="directory containing turret component XMLs")
    ap.add_argument(
        "--search-dir", action="append", type=Path, dest="search_dirs", default=[],
        metavar="DIR", help="additional directory to search for ANI files (repeatable)",
    )
    args = ap.parse_args()

    if not args.corpus.is_dir():
        print(f"error: not a directory: {args.corpus}", file=sys.stderr)
        return 1

    results = run_census(args.corpus, args.search_dirs)
    print_census(results)
    return 0


if __name__ == "__main__":
    sys.exit(main())
