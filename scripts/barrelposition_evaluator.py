"""Offline `weapon.barrelposition` evaluator for mounted, deployed, non-firing turrets (#166 A9).

Reconstructs the selected barrelposition connection transform from official
component/macro XML and ANI resources plus supplied joint angles, following
the executable-derived #164/A5/A6/A7/A8 rules only. Row-vector convention:
a transform is (t, R) with rows X/Y/Z, a point maps as p' = p·R + t, and
`compose(a, b)` means apply a, then b.

Unsupported source structure raises EvaluatorError instead of guessing.
"""
from __future__ import annotations

import importlib.util
import math
import struct
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Mapping

from census_ani_parser import AniDescriptorError, _parse_ani_descriptors
from census_common import CensusError
from census_endpoint_paths import _classify_firing_endpoints, _resolve_connection_hierarchy
from census_identity import (
    _build_ani_resource_inventory,
    _collect_xml_identities,
    _direct_children,
    _resolve_component_identity,
    _resolve_geometry_ani_resource_identity,
    _resolve_macro_identities,
)
from census_sources import _validate_resource_sets, _validate_source_sets

Vec = tuple[float, float, float]
Mat = tuple[Vec, Vec, Vec]
Transform = tuple[Vec, Mat]

IDENTITY: Mat = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
ZERO: Vec = (0.0, 0.0, 0.0)
_DEG = struct.unpack("<f", struct.pack("<f", 0.01745329238474369))[0]
_F32_TWO_PI = struct.unpack("<f", struct.pack("<f", 2 * math.pi))[0]


class EvaluatorError(Exception):
    """Source structure outside the recovered engine rules, or bad input."""


# ponytail: reuse the #164 hash/selection from the hyphenated generator script
# instead of copying it; move both into a shared module when production adopts A9.
_spec = importlib.util.spec_from_file_location(
    "_muzzle_generator", Path(__file__).with_name("generate-turret-muzzle-geometry.py")
)
_generator = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_generator)


# --- matrix algebra (A5/A6, row-vector) ----------------------------------------

def mat_mul(a: Mat, b: Mat) -> Mat:
    return tuple(
        tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3)
    )


def vec_mul(v: Vec, m: Mat) -> Vec:
    return tuple(sum(v[k] * m[k][j] for k in range(3)) for j in range(3))


def compose(a: Transform, b: Transform) -> Transform:
    """a ∘ b: t = a.t·b.R + b.t, R = a.R·b.R (0x14074c40b)."""
    t = vec_mul(a[0], b[1])
    return (tuple(t[i] + b[0][i] for i in range(3)), mat_mul(a[1], b[1]))


def rx(a: float) -> Mat:
    c, s = math.cos(a), math.sin(a)
    return ((1.0, 0.0, 0.0), (0.0, c, s), (0.0, -s, c))


def ry(a: float) -> Mat:
    c, s = math.cos(a), math.sin(a)
    return ((c, 0.0, -s), (0.0, 1.0, 0.0), (s, 0.0, c))


def rz(a: float) -> Mat:
    c, s = math.cos(a), math.sin(a)
    return ((c, s, 0.0), (-s, c, 0.0), (0.0, 0.0, 1.0))


def quaternion_rows(qx: float, qy: float, qz: float, qw: float) -> Mat:
    """0x1400d1fb0, not normalized."""
    x, y, z, w = qx, qy, qz, qw
    return (
        (1 - 2 * y * y - 2 * z * z, 2 * x * y + 2 * z * w, 2 * x * z - 2 * y * w),
        (2 * x * y - 2 * z * w, 1 - 2 * x * x - 2 * z * z, 2 * y * z + 2 * x * w),
        (2 * x * z + 2 * y * w, 2 * y * z - 2 * x * w, 1 - 2 * x * x - 2 * y * y),
    )


def ani_euler(x: float, y: float, z: float) -> Mat:
    """0x1411608b0: Rx(-x)·Rz(-z)·Ry(y), radians."""
    return mat_mul(mat_mul(rx(-x), rz(-z)), ry(y))


def joint_matrix(rotation_x: float, rotation_y: float) -> Mat:
    """A6 J_C rotation Rz(-z)·Rx(-x)·Ry(+y) with no rotation_z restriction."""
    return mat_mul(rx(-rotation_x), ry(rotation_y))


# --- XML offsets (A5 0x140484590) -----------------------------------------------

def _float(element: ET.Element, name: str) -> float:
    raw = element.get(name)
    if raw is None:
        return 0.0
    try:
        return float(raw)
    except ValueError as exc:
        raise EvaluatorError(f"non-numeric {element.tag}@{name}={raw!r}") from exc


def read_offset(element: ET.Element) -> Transform:
    """Direct <offset>: position, then <rotation> (precedence) or <quaternion>."""
    offsets = _direct_children(element, "offset")
    if not offsets:
        return (ZERO, IDENTITY)
    offset = offsets[0]
    positions = _direct_children(offset, "position")
    t = tuple(_float(positions[0], a) for a in "xyz") if positions else ZERO
    rotations = _direct_children(offset, "rotation")
    quaternions = _direct_children(offset, "quaternion")
    if rotations:
        p, y, r = (_float(rotations[0], a) * _DEG for a in ("pitch", "yaw", "roll"))
        rows = mat_mul(mat_mul(rz(-r), rx(-p)), ry(y))
    elif quaternions:
        rows = quaternion_rows(*(_float(quaternions[0], a) for a in ("qx", "qy", "qz", "qw")))
    else:
        rows = IDENTITY
    return (t, rows)


# --- ANI tracks (A5 0x14115fdc0 as applied in A7) -----------------------------

def _keys(descriptor: dict[str, object], channel: str) -> list[dict[str, object]]:
    span = descriptor["key_data"]["channels"][channel]["record_range"]
    keys = []
    for record in descriptor["_candidate_raw_key_records"]:
        if span["start"] <= record["record_index"] < span["end_exclusive"]:
            raw = record["raw_values"]
            # bytes 0..11 value, 12..23 enums, 24 time, 28..75 twelve handle floats
            keys.append({
                "value": tuple(raw[0:3]),
                "enums": tuple(raw[3:6]),
                "time": raw[6],
                "out": (raw[8], raw[12], raw[16]),
                "in": (raw[10], raw[14], raw[18]),
            })
    return keys


def evaluate_track(keys: list[dict[str, object]], time: float, *, rotation: bool) -> Vec:
    if time <= keys[0]["time"]:
        index, frac = 0, 0.0
    else:
        index = next(
            (j for j in range(len(keys) - 1) if time < keys[j + 1]["time"]), len(keys) - 1
        )
        frac = (
            0.0 if index == len(keys) - 1
            else (time - keys[index]["time"]) / (keys[index + 1]["time"] - keys[index]["time"])
        )
    key = keys[index]
    after = keys[index + 1] if index + 1 < len(keys) else None
    result = []
    for axis in range(3):
        enum, value = key["enums"][axis], key["value"][axis]
        target = after["value"][axis] if after else value
        if enum == 1:
            result.append(value)
        elif enum == 2:
            if rotation and after and value != target and abs(value) == _F32_TWO_PI:
                value = 0.0
            result.append(value + (target - value) * frac)
        elif enum == 5:
            if after is None:
                result.append(key["out"][axis])
            else:
                u = frac
                p1, p2 = key["out"][axis], after["in"][axis]
                result.append(
                    (1 - u) ** 3 * value + 3 * u * (1 - u) ** 2 * p1
                    + 3 * u * u * (1 - u) * p2 + u ** 3 * target
                )
        else:
            raise EvaluatorError(f"unsupported ANI key interpolation enum {enum}")
    return tuple(result)


_LOOP_TOLERANCE = 1e-6  # float32 handle noise in the Xenon corpus is ~6e-8


def track_is_constant(keys: list[dict[str, object]]) -> bool:
    """True only if the track stays within _LOOP_TOLERANCE of key 0 at every time.

    Per axis: every enum is 1/2/5, and every control point that can shape the
    curve (all key values; for enum 5 also its out handle and the next key's in
    handle) is within tolerance of key 0. Enum 1/2 stay between key values and
    a cubic Bezier stays inside its control hull, so the bound covers the whole curve.
    """
    for axis in range(3):
        base = keys[0]["value"][axis] if keys else 0.0
        for index, key in enumerate(keys):
            enum = key["enums"][axis]
            controls = [key["value"][axis]]
            if enum == 5:
                controls.append(key["out"][axis])
                if index + 1 < len(keys):
                    controls.append(keys[index + 1]["in"][axis])
            if enum not in (1, 2, 5) or any(abs(c - base) > _LOOP_TOLERANCE for c in controls):
                return False
    return True


# --- source resolution -----------------------------------------------------------

def _raise_census(anomalies: list[dict[str, object]]) -> None:
    if anomalies:
        raise EvaluatorError(str(CensusError(anomalies)))


def load_turrets(
    source_sets: Mapping[str, Path], resource_sets: Mapping[str, Path], macros: list[str]
) -> dict[str, dict[str, object]]:
    """Resolve each macro → component XML element, connections, #164 endpoint and ANI descriptors."""
    roots = _validate_source_sets(source_sets)
    resource_roots = _validate_resource_sets(resource_sets)
    components, macro_records, _wares, anomalies = _collect_xml_identities(
        roots, macro_names=frozenset(macros)
    )
    _raise_census(anomalies)
    records, anomalies = _resolve_macro_identities(macro_records)
    _raise_census(anomalies)
    missing = sorted(set(macros) - {r["name"] for r in records})
    if missing:
        raise EvaluatorError(f"macro not found: {missing}")
    inventory, _counts = _build_ani_resource_inventory(resource_roots)
    turrets = {}
    for record in records:
        macro = record["name"]
        definition, anomalies = _resolve_component_identity(
            record["component"], components.get(record["component"], []), [record]
        )
        _raise_census(anomalies)
        context = dict(component=definition["component"], source_set=definition["source_set"],
                       source_file=definition["source_file"])
        connections, _owners, anomalies = _resolve_connection_hierarchy(
            definition["connection_records"], **context
        )
        _raise_census(anomalies)
        endpoints, anomalies = _classify_firing_endpoints(
            connections, component_class=definition["component_class"], macros=[macro],
            macro_classes=[record["class"]], **context,
        )
        _raise_census(anomalies)
        match, anomalies = _resolve_geometry_ani_resource_identity(
            definition, inventory, component=definition["component"]
        )
        _raise_census(anomalies)
        try:
            descriptors = _parse_ani_descriptors(Path(match["_ani_path"]))
        except AniDescriptorError as exc:
            raise EvaluatorError(f"{exc.code}: {exc.message}") from exc
        xml_path = roots[definition["source_set"]] / definition["source_file"]
        elements = [
            c for c in ET.parse(xml_path).getroot().iter("component")
            if c.get("name", "").strip() == definition["component"]
        ]
        if len(elements) != 1:
            raise EvaluatorError(f"component element not unique in {xml_path}")
        try:
            selected = _generator._barrelposition_connection(
                [endpoint["connection"] for endpoint in endpoints], macro
            )
        except SystemExit as exc:
            raise EvaluatorError(str(exc)) from exc
        turrets[macro] = {
            "macro": macro,
            "component": definition["component"],
            "ani_resource": match["ani_resource"],
            "element": elements[0],
            "connections": {c["name"]: c for c in connections},
            "selected_connection": selected,
            "descriptors": descriptors,
        }
    return turrets


# --- evaluation -------------------------------------------------------------------

def _selected_path(turret: dict[str, object]) -> tuple[list[object], str, list[dict[str, object]]]:
    """Leaf-first path ops: fixed transforms plus "rotation_x"/"rotation_y" joint markers."""
    connections = turret["connections"]
    xml_connections = {
        c.get("name", ""): c
        for group in _direct_children(turret["element"], "connections")
        for c in _direct_children(group, "connection")
    }
    part_owner = {part: c["name"] for c in connections.values() for part in c["direct_owned_parts"]}

    def tags(name: str) -> set[str]:
        return set(connections[name]["tag_tokens"])

    def own_selectors(name: str) -> list[str]:
        return [
            animation.get("name", "").lower()
            for group in _direct_children(xml_connections[name], "animations")
            for animation in _direct_children(group, "animation")
        ]

    def parent(name: str) -> str | None:
        return connections[name]["parent_connection"]

    def effective(name: str) -> list[str]:
        """A7 0x140883570: own ++ parent effective, own-first name dedupe."""
        selectors = own_selectors(name)
        up = parent(name)
        if up is None or "truncateanimations" in tags(name):
            return selectors
        return selectors + [s for s in effective(up) if s not in selectors]

    def animated(name: str) -> bool:
        """A7 bit 9 (0x14088a203)."""
        if own_selectors(name):
            return True
        up = parent(name)
        return up is not None and animated(up) and (
            "animation" in tags(name) or not ({"trigger_nearby", "trigger_interact"} & tags(name))
        )

    # Ancestor chain of the selected connection, leaf → root.
    chain = [turret["selected_connection"]]
    while parent(chain[-1]) is not None:
        chain.append(parent(chain[-1]))

    family = "turretloop" if any(
        "turretloop_active" in effective(name) for name in chain[1:]
    ) else "turret"
    selector = f"{family}_active"
    by_identity = {
        (str(d["part"]).lower(), str(d["subname"]).lower()): d for d in turret["descriptors"]
    }

    used_types: set[str] = set()
    trace = []

    def joints(name: str) -> list[str]:
        restrictions = connections[name]["authored_restrictions"]
        types = [r["type_token"] for r in restrictions]
        if len(set(types)) != len(types) or not set(types) <= {"rotation_x", "rotation_y"}:
            raise EvaluatorError(f"unsupported restriction structure on {name}: {types}")
        for token in types:
            if token in used_types:
                raise EvaluatorError(f"more than one {token} joint on the selected path")
            used_types.add(token)
        # A6 order Rx(-x)·Ry(+y) on one connection.
        return [t for t in ("rotation_x", "rotation_y") if t in types]

    def part_local(part: str, owner: str) -> tuple[Transform, dict[str, object]]:
        part_xml = [
            p for group in _direct_children(xml_connections[owner], "parts")
            for p in _direct_children(group, "part") if p.get("name") == part
        ]
        if len(part_xml) != 1:
            raise EvaluatorError(f"part {part} not uniquely owned by {owner}")
        stored = read_offset(part_xml[0])
        if not animated(owner):
            return stored, {"source": "stored_part_local"}
        if selector not in effective(owner):
            return (ZERO, stored[1]), {"source": "animation_default"}
        descriptor = by_identity.get((part.lower(), selector))
        if descriptor is None:
            return (ZERO, stored[1]), {"source": "animation_default", "descriptor": "absent"}
        position = _keys(descriptor, "position")
        rotation = _keys(descriptor, "rotation")
        duration = struct.unpack("<f", struct.pack("<I", int(
            descriptor["descriptor_offset_148"]["raw_bits"], 16)))[0]
        if family == "turret":
            time = duration
        else:
            # ponytail: loop reference at phase 0; refuse phase-dependent loops
            # (none in the corpus, A7) rather than pick a phase.
            time = 0.0
            if not (track_is_constant(position) and track_is_constant(rotation)):
                raise EvaluatorError(f"phase-dependent loop descriptor on {part}")
        t = evaluate_track(position, time, rotation=False) if position else ZERO
        r = ani_euler(*evaluate_track(rotation, time, rotation=True)) if rotation else stored[1]
        return (t, r), {"source": "ani", "selector": selector, "time": time,
                        "position_keys": len(position), "rotation_keys": len(rotation)}

    def connection_ops(name: str) -> list[object]:
        ops: list[object] = [*joints(name), read_offset(xml_connections[name])]
        parent_part = connections[name]["parent_part"]
        entry = {"connection": name, "restrictions": [
            r["type_token"] for r in connections[name]["authored_restrictions"]]}
        trace.append(entry)
        if parent_part is None:
            return ops
        owner = part_owner[parent_part]
        local_part, entry["parent_part_local"] = part_local(parent_part, owner)
        entry["parent_part"] = parent_part
        return ops + [local_part] + connection_ops(owner)

    return connection_ops(turret["selected_connection"]), family, trace


def _compose_ops(ops: list[object], rotation_x: float, rotation_y: float) -> Transform:
    total: Transform = (ZERO, IDENTITY)
    for op in ops:
        if op == "rotation_x":
            op = (ZERO, joint_matrix(rotation_x, 0.0))
        elif op == "rotation_y":
            op = (ZERO, joint_matrix(0.0, rotation_y))
        total = compose(total, op)
    return total


def joint_segments(turret: dict[str, object]) -> dict[str, Transform]:
    """Split the selected path as T = L ∘ Rx(-x) ∘ G ∘ Ry(y) ∘ H (row-vector composition)."""
    ops, _family, _trace = _selected_path(turret)
    if ops.count("rotation_x") != 1 or ops.count("rotation_y") != 1 or ops.index("rotation_x") > ops.index("rotation_y"):
        raise EvaluatorError("selected path is not one rotation_x below one rotation_y")
    ix, iy = ops.index("rotation_x"), ops.index("rotation_y")
    return {"L": _compose_ops(ops[:ix], 0.0, 0.0), "G": _compose_ops(ops[ix + 1:iy], 0.0, 0.0),
            "H": _compose_ops(ops[iy + 1:], 0.0, 0.0)}


def evaluate(turret: dict[str, object], rotation_x: float, rotation_y: float) -> dict[str, object]:
    ops, family, trace = _selected_path(turret)
    translation, rows = _compose_ops(ops, rotation_x, rotation_y)
    return {
        "macro": turret["macro"],
        "component": turret["component"],
        "ani_resource": turret["ani_resource"],
        "selected_connection": turret["selected_connection"],
        "animation_family": family,
        "joint_radians": {"rotation_x": rotation_x, "rotation_y": rotation_y},
        "owner_scale": 1.0,
        "path": trace,
        "transform": {"translation": list(translation), "x": list(rows[0]),
                      "y": list(rows[1]), "z": list(rows[2])},
    }
