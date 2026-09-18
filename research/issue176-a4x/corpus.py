"""Expanded-A4 turret corpus: 124 official + 164 SWI 0.9.1 HF macros as ordered mechanical paths.

Research only. Builds the input layer for the later #176 generalized truth scorer; no
benchmark, no scorer, no production change. The accepted historical A4 under
`research/issue176-a4/` is untouched.
"""
from __future__ import annotations

import gzip
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from barrelposition_evaluator import (  # noqa: E402
    IDENTITY,
    ZERO,
    EvaluatorError,
    _barrelposition_connection,
    _keys,
    ani_euler,
    evaluate_track,
    load_turrets,
    read_offset,
    _selected_path,
)
from census_ani_parser import _parse_ani_descriptors  # noqa: E402
from census_common import REQUIRED_SOURCE_SETS  # noqa: E402
from census_identity import _direct_children  # noqa: E402

CACHE = ROOT / ".x4-research-cache"
OFFICIAL_SRC = CACHE / "official-source-sets"
OFFICIAL_ANI = CACHE / "issue72-a2-ani-resources"
SWI_XML = CACHE / "issue179" / "swi_xml"
SWI_ANI = CACHE / "issue176-swi-ani"
SWI_SCOPE = CACHE / "issue176-swi-wares" / "scope.json"
SWI_COMBAT = CACHE / "issue176-swi-combat" / "combat.json"
OUT = CACHE / "issue176-a4x"

EXPECTED = {
    "official_total": 124, "official_conventional": 92, "official_missile": 32,
    "swi_total": 164, "swi_ordinary_xy": 154, "swi_bounded_traverse": 8,
    "swi_reversed_xy": 1, "swi_rotation_z": 1, "swi_missile": 4,
    "swi_missing_selector": 84, "swi_undeclared_parent": 11,
    "official_conventional_gun": 92, "official_guided_missile": 16,
    "official_dumbfire_missile": 16, "official_unresolved_other": 0,
}
BEHAVIORS = ("conventional_gun", "guided_missile", "dumbfire_missile", "unresolved_other")
SWI_PROJECTILES = CACHE / "issue176-swi-combat" / "swi_xml"
ENDPOINT_TAG = {"turret": "laser", "missileturret": "rocket"}


class CorpusError(Exception):
    pass


def _tags(element):
    return set((element.get("tags") or "").split())


def _limits(restriction):
    out = []
    for bound in ("min", "max"):
        node = restriction.find(f"limits/{bound}")
        out.append(None if node is None else float(node.get("value")))
    return None if out[0] is None or out[1] is None else out


def _axis(token):
    if token not in ("rotation_x", "rotation_y", "rotation_z"):
        raise CorpusError(f"unsupported restriction type {token!r}")
    return token[-1]


def _classify(joints):
    """joints: root-side to leaf-side [(axis, limits|None), ...]."""
    shape = tuple((axis, limits is not None) for axis, limits in joints)
    if shape == (("y", False), ("x", True)):
        return "ordinary_xy"
    if shape == (("y", True), ("x", True)):
        return "bounded_traverse"
    if len(shape) == 2 and shape[0][0] == "x" and shape[1][0] == "y":
        return "reversed_xy"
    if len(shape) == 2 and shape[0][0] == "z" and shape[1][0] == "x":
        return "rotation_z"
    return "other"


def _record(ops, **fields):
    joints = [(op["axis"], op["limits"]) for op in reversed(ops) if op["kind"] == "joint"]
    return dict(ops=ops, joints_root_to_leaf=[dict(axis=a, limits=l) for a, l in joints],
                mechanical_class=_classify(joints), **fields)


# --- weapon behavior ----------------------------------------------------------

def _collect_projectile(element, projectiles):
    if element.get("class") not in ("bullet", "missile"):
        return
    missile = element.find("properties/missile")
    name = element.get("name").lower()
    authored = (element.get("class"), None if missile is None else missile.get("guided"))
    if projectiles.setdefault(name, authored) != authored:
        raise CorpusError(f"projectile {name} is authored twice with conflicting behavior: "
                          f"{projectiles[name]} then {authored}")


def _collect_swi_projectiles(projectiles):
    for path in sorted(SWI_PROJECTILES.rglob("*.xml")) + sorted(SWI_XML.rglob("*.xml")):
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError:
            continue
        for element in root.iter("macro"):
            if element.get("name"):
                _collect_projectile(element, projectiles)


def _behavior(element, projectiles):
    """Authored evidence only: the referenced projectile macro's class and `missile@guided`."""
    reference = element.find("properties/bullet")
    if reference is None:
        reference = element.find("properties/missile")
    if reference is None or not reference.get("class"):
        return "unresolved_other"
    projectile = projectiles.get(reference.get("class").lower())
    if projectile is None:
        return "unresolved_other"
    kind, guided = projectile
    if kind == "bullet":
        return "conventional_gun"
    return {"1": "guided_missile", "0": "dumbfire_missile"}.get(guided, "unresolved_other")


# --- official 124 ---------------------------------------------------------------

def _official_macros(projectiles, turrets):
    """Collect official macros in one pass: turret scope plus every projectile macro."""
    lua = (ROOT / "ui/turret_muzzle_geometry.lua").read_text()
    conventional = sorted(b.split('"', 1)[0] for b in re.split(r'\n    \["', lua)[1:] if "chain = {" in b)
    missile = []
    for name in REQUIRED_SOURCE_SETS:
        for path in sorted((OFFICIAL_SRC / name).rglob("*.xml")):
            try:
                root = ET.parse(path).getroot()
            except ET.ParseError:
                continue
            if root.tag != "macros":
                continue
            for element in root.findall("macro"):
                _collect_projectile(element, projectiles)
                if element.get("class") in ("turret", "missileturret"):
                    turrets.setdefault(element.get("name"), element)
                if element.get("class") == "missileturret":
                    missile.append(element.get("name"))
    missile = sorted(set(missile))
    if len(conventional) != EXPECTED["official_conventional"] or len(missile) != EXPECTED["official_missile"]:
        raise CorpusError(f"official scope drift: {len(conventional)} conventional, {len(missile)} missile")
    if set(conventional) & set(missile):
        raise CorpusError("official conventional/missile scope overlap")
    return conventional, missile


def _official_records():
    projectiles, turret_macros = {}, {}
    conventional, missile = _official_macros(projectiles, turret_macros)
    _collect_swi_projectiles(projectiles)
    loaded = load_turrets({n: OFFICIAL_SRC / n for n in REQUIRED_SOURCE_SETS},
                          {n: OFFICIAL_ANI / n for n in REQUIRED_SOURCE_SETS}, conventional + missile)
    records = {}
    for macro in conventional + missile:
        turret = loaded[macro]
        path_ops, family, trace = _selected_path(turret)
        ops, index = [], 0
        for entry in trace:
            name = entry["connection"]
            bounds = {r["type_token"]: [r["authored_min"], r["authored_max"]]
                      for r in turret["connections"][name]["authored_restrictions"]}
            while isinstance(path_ops[index], str):
                token = path_ops[index]
                limits = [None if b is None else b["candidate_numeric_value"] for b in bounds[token]]
                ops.append(dict(kind="joint", axis=_axis(token), connection=name,
                                limits=None if None in limits else limits))
                index += 1
            ops.append(dict(kind="fixed", role="connection_offset", connection=name,
                            transform=_transform(path_ops[index])))
            index += 1
            if "parent_part" in entry:
                ops.append(dict(kind="fixed", role="part_local", part=entry["parent_part"], owner=name,
                                transform=_transform(path_ops[index]), local_source=entry["parent_part_local"]))
                index += 1
        if index != len(path_ops):
            raise CorpusError(f"{macro}: unconsumed selected-path ops")
        behavior = _behavior(turret_macros[macro], projectiles)
        ammunition = turret_macros[macro].find("properties/ammunition")
        tokens = set((ammunition.get("tags") or "").split()) if ammunition is not None else set()
        expected = {"guided_missile": "guided", "dumbfire_missile": "dumbfire"}.get(behavior)
        if expected is not None and expected not in tokens:
            raise CorpusError(f"{macro}: projectile says {behavior} but ammunition tags are {sorted(tokens)}")
        records["official:" + macro] = _record(
            ops, macro=macro, source="official", component=turret["component"],
            macro_class="missileturret" if macro in missile else "turret",
            weapon_behavior=behavior,
            endpoint=dict(connection=turret["selected_connection"],
                          tag=ENDPOINT_TAG["missileturret" if macro in missile else "turret"]),
            animation_family=family, ani_locals="bound", uncertainty={})
    return records, projectiles


def _transform(transform):
    translation, rows = transform
    return dict(t=[float(v) for v in translation], R=[[float(v) for v in row] for row in rows])


# --- SWI 164 --------------------------------------------------------------------

def _index_xml(roots, tag):
    index = {}
    for base in roots:
        for path in sorted(base.rglob("*.xml")):
            if tag == "component" and "macros" in [p.lower() for p in path.parts]:
                continue
            try:
                root = ET.parse(path).getroot()
            except ET.ParseError:
                continue
            for element in root.iter(tag):
                if element.get("name"):
                    index.setdefault(element.get("name").lower(), (element, path))
    return index


def _ani_index():
    index = {}
    for base in (SWI_ANI, OFFICIAL_ANI):
        for path in sorted(base.rglob("*")):
            if path.is_file() and path.suffix.lower() == ".ani":
                index.setdefault(path.stem.lower(), path)
    return index


def _swi_scope():
    scope = json.loads(SWI_SCOPE.read_text())
    combat = json.loads(SWI_COMBAT.read_text())
    supported = sorted(m for m, row in scope.items()
                       if row["status"] == "COMBAT_EQUIPABLE" and combat.get(m, {}).get("verdict") == "COMBAT")
    if len(supported) != EXPECTED["swi_total"]:
        raise CorpusError(f"SWI supported scope drift: {len(supported)}")
    return supported, combat


def _descriptor_local(descriptor, stored_rows):
    position, rotation = _keys(descriptor, "position"), _keys(descriptor, "rotation")
    duration = struct.unpack("<f", struct.pack("<I", int(descriptor["descriptor_offset_148"]["raw_bits"], 16)))[0]
    t = evaluate_track(position, duration, rotation=False) if position else ZERO
    R = ani_euler(*evaluate_track(rotation, duration, rotation=True)) if rotation else stored_rows
    return (t, R)


def _swi_records(supported, combat, projectiles):
    components = _index_xml([SWI_XML, OFFICIAL_SRC], "component")
    macros = _index_xml([SWI_XML], "macro")
    anis = _ani_index()
    records = {}
    for macro in supported:
        element, _path = macros[macro.lower()]
        reference = element.find("component")
        component_name = reference.get("ref")
        component = components[component_name.lower()][0]
        connections = {c.get("name"): c for group in _direct_children(component, "connections")
                       for c in _direct_children(group, "connection") if c.get("name")}
        owner = {p.get("name"): name for name, c in connections.items()
                 for group in _direct_children(c, "parts") for p in _direct_children(group, "part")}
        tag = ENDPOINT_TAG.get(component.get("class"), "laser")
        endpoints = [n for n, c in connections.items() if tag in _tags(c)]
        if not endpoints:
            tag = "rocket" if tag == "laser" else "laser"
            endpoints = [n for n, c in connections.items() if tag in _tags(c)]
        selected = _barrelposition_connection(sorted(endpoints), macro)

        chain, undeclared, name = [], False, selected
        while True:
            chain.append(name)
            parent = connections[name].get("parent")
            if not parent:
                break
            if parent not in owner:
                undeclared = True
                break
            name = owner[parent]
        declares_active = any(
            animation.get("name", "").lower() == "turret_active"
            for link in chain
            for group in _direct_children(connections[link], "animations")
            for animation in _direct_children(group, "animation"))

        source = component.find("source")
        geometry = (source.get("geometry") or "") if source is not None else ""
        descriptors = {}
        stem = geometry.replace("\\", "/").rsplit("/", 1)[-1].lower()
        if stem and stem in anis:
            descriptors = {(str(d["part"]).lower(), str(d["subname"]).lower()): d
                           for d in _parse_ani_descriptors(anis[stem])}

        ops, ani_offpath, ani_nonzero = [], False, False
        for index, name in enumerate(chain):
            connection = connections[name]
            restrictions = [r for group in _direct_children(connection, "restrictions")
                            for r in _direct_children(group, "restriction")]
            if len(restrictions) > 1:
                raise CorpusError(f"{macro}: {name} authors {len(restrictions)} restrictions")
            for restriction in restrictions:
                ops.append(dict(kind="joint", axis=_axis(restriction.get("type")), connection=name,
                                limits=_limits(restriction)))
            ops.append(dict(kind="fixed", role="connection_offset", connection=name,
                            transform=_transform(read_offset(connection))))
            parent = connection.get("parent")
            if not parent or parent not in owner:
                continue
            host = owner[parent]
            part = [p for group in _direct_children(connections[host], "parts")
                    for p in _direct_children(group, "part") if p.get("name") == parent]
            if len(part) != 1:
                raise CorpusError(f"{macro}: part {parent} not uniquely owned by {host}")
            stored = read_offset(part[0])
            op = dict(kind="fixed", role="part_local", part=parent, owner=host,
                      transform=_transform(stored), local_source="stored_part_local")
            descriptor = descriptors.get((parent.lower(), "turret_active"))
            if descriptor is not None:
                alternative = _descriptor_local(descriptor, stored[1])
                op["ani_alternative"] = _transform(alternative)
                if declares_active:
                    op["transform"], op["local_source"] = _transform(alternative), "ani"
                    op.pop("ani_alternative")
                else:
                    op["local_source"] = "stored_part_local_ani_unbound"
                    ani_offpath = True
                    ani_nonzero |= any(abs(v) > 1e-9 for v in alternative[0])
            ops.append(op)

        uncertainty = {}
        if ani_nonzero:
            uncertainty["missing_selector_ani"] = ("path parts carry non-zero turret_active ANI translations "
                                                   "but no effective selector declares that animation")
        elif ani_offpath:
            uncertainty["missing_selector_ani_zero"] = "unbound turret_active descriptors are zero-translation"
        if undeclared:
            uncertainty["undeclared_parent"] = ("selected-path root connection names a part no connection declares; "
                                                "loader behaviour unresolved, root attachment assumed")
        records["swi:" + macro] = _record(
            ops, macro=macro, source="swi", component=component_name,
            macro_class=element.get("class"), component_class=component.get("class"),
            weapon_behavior=_behavior(element, projectiles),
            combat_verdict=combat[macro]["verdict"],
            endpoint=dict(connection=selected, tag=tag, count=len(endpoints)),
            mount_resolvable=sum("component" in _tags(c) for c in connections.values()) == 1,
            ani_locals="bound" if declares_active else "unbound", uncertainty=uncertainty)
    return records


# --- build ------------------------------------------------------------------------

def _validate(records):
    official = [r for r in records.values() if r["source"] == "official"]
    swi = [r for r in records.values() if r["source"] == "swi"]
    classes = Counter(r["mechanical_class"] for r in swi)
    actual = {
        "official_total": len(official),
        "official_conventional": sum(r["macro_class"] == "turret" for r in official),
        "official_missile": sum(r["macro_class"] == "missileturret" for r in official),
        "swi_total": len(swi),
        "swi_ordinary_xy": classes["ordinary_xy"],
        "swi_bounded_traverse": classes["bounded_traverse"],
        "swi_reversed_xy": classes["reversed_xy"],
        "swi_rotation_z": classes["rotation_z"],
        "swi_missile": sum(r["macro_class"] == "missileturret" for r in swi),
        "swi_missing_selector": sum("missing_selector_ani" in r["uncertainty"] for r in swi),
        "swi_undeclared_parent": sum("undeclared_parent" in r["uncertainty"] for r in swi),
    }
    for behavior in BEHAVIORS:
        actual["official_" + behavior] = sum(r["weapon_behavior"] == behavior for r in official)
        actual["swi_" + behavior] = sum(r["weapon_behavior"] == behavior for r in swi)
    if {k: actual[k] for k in EXPECTED} != EXPECTED:
        raise CorpusError("count mismatch: " + json.dumps(
            {k: [v, EXPECTED[k]] for k, v in actual.items() if v != EXPECTED[k]}))
    if classes["other"]:
        raise CorpusError("unclassified SWI mechanical layouts: "
                          + str(sorted(r["macro"] for r in swi if r["mechanical_class"] == "other")))
    for record in records.values():
        if record["weapon_behavior"] not in BEHAVIORS:
            raise CorpusError(f"{record['macro']}: bad weapon behavior {record['weapon_behavior']!r}")
        if not record["joints_root_to_leaf"]:
            raise CorpusError(f"{record['macro']}: no rotation joint on the selected path")
        if not any(op["kind"] == "fixed" for op in record["ops"]):
            raise CorpusError(f"{record['macro']}: no fixed transform on the selected path")
        for op in record["ops"]:
            if op["kind"] != "fixed":
                continue
            rows = op["transform"]["R"]
            if len(rows) != 3 or any(len(row) != 3 or any(v != v for v in row) for row in rows):
                raise CorpusError(f"{record['macro']}: malformed transform on {op['role']}")
    return actual


def main():
    records, projectiles = _official_records()
    supported, combat = _swi_scope()
    swi = _swi_records(supported, combat, projectiles)
    if set(records) & set(swi):
        raise CorpusError("duplicate corpus keys")
    records.update(swi)
    actual = _validate(records)
    OUT.mkdir(parents=True, exist_ok=True)
    with gzip.open(OUT / "corpus.json.gz", "wt") as stream:
        json.dump(dict(counts=actual, records=records), stream, indent=1, sort_keys=True)
    print(json.dumps(actual, indent=1))
    print("official classes", dict(Counter(r["mechanical_class"] for r in records.values() if r["source"] == "official")))
    print("swi behavior", dict(Counter(r["weapon_behavior"] for r in records.values() if r["source"] == "swi")))
    print("swi mount-resolvable", sum(r.get("mount_resolvable") is True for r in records.values()))
    print("wrote", OUT / "corpus.json.gz")


if __name__ == "__main__":
    try:
        main()
    except (CorpusError, EvaluatorError) as exc:
        raise SystemExit(f"corpus build failed: {exc}")
