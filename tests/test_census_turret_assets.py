#!/usr/bin/env python3
"""Focused synthetic tests for the Issue #72 A2.1 turret asset census."""
from __future__ import annotations

import contextlib
import copy
import io
import struct
import tempfile
import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    AniDescriptorError,
    CensusError,
    REQUIRED_SOURCE_SETS,
    _ANI_KEY_RECORD_CANDIDATE_SLOTS,
    _build_same_subname_structural_relationship_coverage,
    _parse_ani_descriptors,
    _derive_endpoint_source_paths,
    _evaluate_paranid_l_beam_trace,
    build_census as _build_census,
    build_reconciliation,
    main,
    render_json,
)


def _ani_bytes(
    *descriptors: (
        tuple[str, str]
        | tuple[str, str, int, int, int, int, int]
        | tuple[str, str, int, int, int, int, int, int]
    ),
    version: int = 1,
    header_padding: int = 0,
    key_offset: int | None = None,
    descriptor_padding: tuple[int, int] = (0, 0),
    key_data: bytes | None = None,
) -> bytes:
    records = []
    total_key_records = 0
    for descriptor in descriptors:
        part, subname = descriptor[:2]
        channel_counts = descriptor[2:7] or (0, 0, 0, 0, 0)
        descriptor_offset_148_raw_bits = descriptor[7] if len(descriptor) == 8 else 0
        total_key_records += sum(channel_counts)
        part_bytes = part.encode("ascii")
        subname_bytes = subname.encode("ascii")
        if len(part_bytes) > 63 or len(subname_bytes) > 63:
            raise ValueError("synthetic ANI descriptor strings must fit with a NUL terminator")
        records.append(
            part_bytes.ljust(64, b"\0")
            + subname_bytes.ljust(64, b"\0")
            + struct.pack(
                "<8I",
                *channel_counts,
                descriptor_offset_148_raw_bits,
                *descriptor_padding,
            )
        )
    descriptor_table = b"".join(records)
    if key_data is None:
        key_data = b"".join(
            bytes([(record_index % 251) + 1]) * 128
            for record_index in range(total_key_records)
        )
    return (
        struct.pack(
            "<4I",
            len(descriptors),
            16 + len(descriptor_table) if key_offset is None else key_offset,
            version,
            header_padding,
        )
        + descriptor_table
        + key_data
    )


def _candidate_key_record(values: tuple[float | int, ...]) -> bytes:
    if len(values) != 32:
        raise ValueError("candidate ANI key record requires exactly 32 typed slots")
    return struct.pack("<3f3if17fi6fI", *values)


def _source_roots(root: Path) -> dict[str, Path]:
    roots = {}
    for name in REQUIRED_SOURCE_SETS:
        path = root / name
        path.mkdir(parents=True)
        (path / "source_set.xml").write_text("<source/>", encoding="utf-8")
        inventory = path / "inventory" / f"unrelated_{name}.ANI"
        inventory.parent.mkdir()
        inventory.write_bytes(_ani_bytes())
        roots[name] = path
    for resource in (
        "geometry/shared.ANI",
        "geometry/missile.ANI",
        "geometry/shared_component.ANI",
        "geometry/component_a.ANI",
        "geometry/component_b.ANI",
        "geometry/component_z.ANI",
        "geometry/current_a.ANI",
        "geometry/current_b.ANI",
        "geometry/current_c.ANI",
        "ASSETS/Exact_CASE_Data.ANI",
    ):
        target = roots["base"] / resource
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(_ani_bytes())
    return roots


def build_census(source_sets: dict[str, Path]) -> dict[str, object]:
    return _build_census(source_sets, source_sets)


def _write(path: Path, relative: str, text: str) -> None:
    target = path / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def _components(*names: str) -> str:
    body = "".join(
        f'<component name="{name}" class="turret"><source geometry="geometry/{name}"/><connections><connection name="{name}_endpoint" tags="laser"/></connections></component>'
        for name in names
    )
    return f"<components>{body}</components>"


def _macros(*records: tuple[str, str, str | None]) -> str:
    body = []
    for name, macro_class, component in records:
        child = "" if component is None else f'<component ref="{component}"/>'
        body.append(f'<macro name="{name}" class="{macro_class}">{child}</macro>')
    return "<macros>" + "".join(body) + "</macros>"


class CensusTests(unittest.TestCase):
    def test_macro_driven_inclusion_deduplication_and_inversion(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="shared_component" class="turret">
                    <source geometry="geometry/shared"/>
                    <connections><connection name="SharedEndpoint" tags="laser "/></connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/missile"/>
                    <connections><connection name="MissileEndpoint" tags="rocket"/></connections>
                  </component>
                  <component name="unrelated_component" class="engine"/>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros/base.xml",
                _macros(
                    ("turret_beta_macro", "turret", "shared_component"),
                    ("engine_ignored_macro", "engine", "unrelated_component"),
                ),
            )
            _write(
                roots["ego_dlc_split"],
                "assets/macros/split.xml",
                _macros(
                    ("turret_alpha_macro", "turret", "shared_component"),
                    ("missile_macro", "missileturret", "missile_component"),
                ),
            )

            report = build_census(roots)

            self.assertEqual(
                [record["name"] for record in report["equipment_macros"]],
                ["missile_macro", "turret_alpha_macro", "turret_beta_macro"],
            )
            self.assertEqual(report["counts"]["equipment_macros"], 3)
            self.assertEqual(report["counts"]["turret_macros"], 2)
            self.assertEqual(report["counts"]["missileturret_macros"], 1)
            self.assertEqual(report["counts"]["unique_components"], 2)
            self.assertEqual(
                report["component_to_macros"],
                [
                    {
                        "component": "missile_component",
                        "component_class": "missileturret",
                        "source_set": "base",
                        "source_file": "assets/components.xml",
                        "geometry_source": "geometry/missile",
                        "ani_source_set": "base",
                        "ani_resource": "geometry/missile.ANI",
                        "connections": [
                            {
                                "name": "MissileEndpoint",
                                "parent_part": None,
                                "parent_connection": None,
                                "direct_owned_parts": [],
                                "authored_attributes": {"name": "MissileEndpoint", "tags": "rocket"},
                                "authored_tags": "rocket",
                                "tag_tokens": ["rocket"],
                                "authored_restrictions": [],
                                "root_to_connection_path": ["MissileEndpoint"],
                                "depth": 0,
                            }
                        ],
                        "firing_endpoints": [
                            {
                                "component": "missile_component",
                                "component_class": "missileturret",
                                "macros": ["missile_macro"],
                                "macro_classes": ["missileturret"],
                                "connection": "MissileEndpoint",
                                "authored_evidence": {"tag_attribute": "rocket", "tag_token": "rocket"},
                                "root_to_endpoint_connection_path": ["MissileEndpoint"],
                                "traversed_connection_edges": [],
                                "source_part_path": [],
                                "ani_descriptor_memberships": [],
                                "authored_animation_selector_occurrences": [],
                                "selected_ani_descriptor_memberships": [],
                                "unselected_ani_descriptor_memberships": [],
                            }
                        ],
                        "ani_descriptors": [],
                        "source_parts": [],
                        "authored_connection_animations": [],
                        "descriptor_parts_absent_from_source_parts": [],
                        "macro_count": 1,
                        "macros": ["missile_macro"],
                    },
                    {
                        "component": "shared_component",
                        "component_class": "turret",
                        "source_set": "base",
                        "source_file": "assets/components.xml",
                        "geometry_source": "geometry/shared",
                        "ani_source_set": "base",
                        "ani_resource": "geometry/shared.ANI",
                        "connections": [
                            {
                                "name": "SharedEndpoint",
                                "parent_part": None,
                                "parent_connection": None,
                                "direct_owned_parts": [],
                                "authored_attributes": {"name": "SharedEndpoint", "tags": "laser "},
                                "authored_tags": "laser ",
                                "tag_tokens": ["laser"],
                                "authored_restrictions": [],
                                "root_to_connection_path": ["SharedEndpoint"],
                                "depth": 0,
                            }
                        ],
                        "firing_endpoints": [
                            {
                                "component": "shared_component",
                                "component_class": "turret",
                                "macros": ["turret_alpha_macro", "turret_beta_macro"],
                                "macro_classes": ["turret"],
                                "connection": "SharedEndpoint",
                                "authored_evidence": {"tag_attribute": "laser ", "tag_token": "laser"},
                                "root_to_endpoint_connection_path": ["SharedEndpoint"],
                                "traversed_connection_edges": [],
                                "source_part_path": [],
                                "ani_descriptor_memberships": [],
                                "authored_animation_selector_occurrences": [],
                                "selected_ani_descriptor_memberships": [],
                                "unselected_ani_descriptor_memberships": [],
                            }
                        ],
                        "ani_descriptors": [],
                        "source_parts": [],
                        "authored_connection_animations": [],
                        "descriptor_parts_absent_from_source_parts": [],
                        "macro_count": 2,
                        "macros": ["turret_alpha_macro", "turret_beta_macro"],
                    },
                ],
            )
            self.assertEqual(report["component_macro_cardinality"], {"1": 1, "2": 1})
            self.assertEqual(report["counts"]["ani_descriptor_pairs_total"], 0)
            self.assertEqual(report["counts"]["unique_ani_descriptor_pairs"], 0)
            self.assertEqual(report["ani_descriptor_count_cardinality"], {"0": 2})
            self.assertEqual(report["counts"]["source_part_ownerships"], 0)
            self.assertEqual(report["counts"]["component_source_parts"], 0)
            self.assertEqual(report["source_part_owning_connection_cardinality"], {})
            self.assertEqual(report["descriptor_parts_absent_from_component_source_parts"], [])
            self.assertEqual(report["counts"]["unique_geometry_sources"], 2)
            self.assertEqual(
                report["geometry_source_to_components"],
                [
                    {
                        "geometry_source": "geometry/missile",
                        "component_count": 1,
                        "components": ["missile_component"],
                    },
                    {
                        "geometry_source": "geometry/shared",
                        "component_count": 1,
                        "components": ["shared_component"],
                    },
                ],
            )
            self.assertEqual(report["geometry_source_component_cardinality"], {"1": 2})
            self.assertEqual(report["counts"]["unique_ani_resources"], 2)
            self.assertEqual(report["ani_inventory_counts_by_source_set"]["base"], 11)
            self.assertEqual(report["ani_inventory_counts_by_source_set"]["ego_dlc_split"], 1)
            self.assertEqual(
                report["ani_resource_to_geometry_sources_components"],
                [
                    {
                        "ani_source_set": "base",
                        "ani_resource": "geometry/missile.ANI",
                        "geometry_source_count": 1,
                        "geometry_sources": ["geometry/missile"],
                        "component_count": 1,
                        "components": ["missile_component"],
                    },
                    {
                        "ani_source_set": "base",
                        "ani_resource": "geometry/shared.ANI",
                        "geometry_source_count": 1,
                        "geometry_sources": ["geometry/shared"],
                        "component_count": 1,
                        "components": ["shared_component"],
                    },
                ],
            )
            self.assertEqual(report["ani_resource_geometry_source_cardinality"], {"1": 2})
            self.assertEqual(report["ani_resource_component_cardinality"], {"1": 2})
            self.assertEqual(report["macro_component_class_mismatches"], [])
            self.assertEqual(
                report["counts_by_source_set"]["base"],
                {"equipment_macros": 1, "turret_macros": 1, "missileturret_macros": 0},
            )
            self.assertEqual(
                report["counts_by_source_set"]["ego_dlc_split"],
                {"equipment_macros": 2, "turret_macros": 1, "missileturret_macros": 1},
            )
            self.assertEqual(
                report["counts_by_source_set"]["ego_dlc_mini_01"],
                {"equipment_macros": 0, "turret_macros": 0, "missileturret_macros": 0},
            )
            self.assertEqual(report["anomalies"], [])
            split = next(r for r in report["equipment_macros"] if r["name"] == "missile_macro")
            self.assertEqual(split["source_set"], "ego_dlc_split")
            self.assertEqual(split["component"], "missile_component")

    def test_missing_component_reference_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/macros/bad.xml", _macros(("bad", "turret", None)))
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("missing_component_reference", caught.exception.codes)

    def test_unresolved_component_reference_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/macros/bad.xml",
                _macros(("bad", "missileturret", "absent_component")),
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("unresolved_component_reference", caught.exception.codes)

    def test_multiple_full_component_definitions_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/a.xml", _components("shared_component"))
            _write(roots["ego_dlc_split"], "assets/b.xml", _components("shared_component"))
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("turret_macro", "turret", "shared_component")),
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("multiple_component_definitions", caught.exception.codes)

    def test_exact_direct_geometry_source_is_preserved_and_nested_source_is_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="Assets\\Exact_CASE_Data"/>
                  <connections><connection name="Endpoint" tags="laser"/></connections>
                  <metadata><source geometry="nested/misleading"/></metadata>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            report = build_census(roots)
            component = report["component_to_macros"][0]
            self.assertEqual(component["geometry_source"], "Assets\\Exact_CASE_Data")
            self.assertEqual(component["ani_source_set"], "base")
            self.assertEqual(component["ani_resource"], "ASSETS/Exact_CASE_Data.ANI")

    def test_ani_descriptors_source_parts_and_animation_names_are_exact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/component_a"/>
                  <connections>
                    <connection name="Conn_A">
                      <animations><animation name="Anim_CASE"/></animations>
                      <parts>
                        <part name="Part_CASE"/>
                        <part name="SharedPart"/>
                        <part name="DuplicateUnused"/>
                        <part name="DuplicateUnused"/>
                      </parts>
                      <metadata><parts><part name="NestedPart"/></parts></metadata>
                    </connection>
                    <connection name="Conn_B"><parts><part name="DuplicateUnused"/></parts></connection>
                    <connection name="Endpoint" tags="laser"/>
                  </connections>
                  <metadata><connection name="UnrelatedConn"><parts><part name="UnrelatedPart"/></parts></connection></metadata>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(
                    ("SharedPart", "SharedSub"),
                    ("Part_CASE", "Sub_CASE"),
                )
            )

            report = build_census(roots)
            component = report["component_to_macros"][0]
            self.assertEqual(
                [
                    {
                        key: descriptor[key]
                        for key in (
                            "descriptor_index",
                            "part",
                            "subname",
                            "source_connection",
                            "root_to_source_connection_path",
                        )
                    }
                    for descriptor in component["ani_descriptors"]
                ],
                [
                    {
                        "descriptor_index": 0,
                        "part": "SharedPart",
                        "subname": "SharedSub",
                        "source_connection": "Conn_A",
                        "root_to_source_connection_path": ["Conn_A"],
                    },
                    {
                        "descriptor_index": 1,
                        "part": "Part_CASE",
                        "subname": "Sub_CASE",
                        "source_connection": "Conn_A",
                        "root_to_source_connection_path": ["Conn_A"],
                    },
                ],
            )
            self.assertEqual(
                component["source_parts"],
                [
                    {
                        "part": "DuplicateUnused",
                        "owning_connection_count": 3,
                        "distinct_owning_connection_count": 2,
                        "owning_connections": ["Conn_A", "Conn_A", "Conn_B"],
                    },
                    {
                        "part": "Part_CASE",
                        "owning_connection_count": 1,
                        "distinct_owning_connection_count": 1,
                        "owning_connections": ["Conn_A"],
                    },
                    {
                        "part": "SharedPart",
                        "owning_connection_count": 1,
                        "distinct_owning_connection_count": 1,
                        "owning_connections": ["Conn_A"],
                    },
                ],
            )
            self.assertEqual(
                component["authored_connection_animations"],
                [
                    {
                        "connection": "Conn_A",
                        "name": "Anim_CASE",
                        "descriptor_match_count": 0,
                        "connection_ani_descriptors": [],
                    }
                ],
            )
            self.assertEqual(
                component["descriptor_parts_absent_from_source_parts"], []
            )
            self.assertEqual(
                report["authored_animation_selectors_with_zero_descriptor_matches"],
                [
                    {
                        "component": "component_a",
                        "connection": "Conn_A",
                        "animation_name": "Anim_CASE",
                    }
                ],
            )
            self.assertNotIn("NestedPart", render_json(component))
            self.assertNotIn("UnrelatedPart", render_json(component))
            self.assertEqual(report["counts"]["ani_descriptor_pairs_total"], 2)
            self.assertEqual(report["counts"]["unique_ani_descriptor_pairs"], 2)
            self.assertEqual(report["ani_descriptor_count_cardinality"], {"2": 1})
            self.assertEqual(report["counts"]["source_part_ownerships"], 5)
            self.assertEqual(report["counts"]["component_source_parts"], 3)
            self.assertEqual(
                report["source_part_owning_connection_cardinality"], {"1": 2, "3": 1}
            )
            self.assertEqual(
                report["source_part_distinct_owning_connection_cardinality"],
                {"1": 2, "2": 1},
            )
            self.assertEqual(
                report["descriptor_parts_absent_from_component_source_parts"], []
            )

    def test_connection_graph_and_descriptor_source_paths_are_exact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/component_a"/>
                  <connections>
                    <connection name="Root"><parts><part name="BasePart"/><part name="BasePart"/></parts></connection>
                    <connection name="Child" parent="BasePart"><parts><part name="ArmPart"/></parts></connection>
                    <connection name="Grand" tags="laser" parent="ArmPart"><parts><part name="BarrelPart"/></parts></connection>
                    <connection name="Branch" parent="BasePart"><parts><part name="BranchPart"/></parts></connection>
                    <connection name="EmptyParentRoot" parent=""/>
                  </connections>
                  <metadata><connections><connection name="Nested" parent="BarrelPart"><parts><part name="NestedPart"/></parts></connection></connections></metadata>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(("BarrelPart", "Sub_CASE"), ("BasePart", "RootSub"))
            )

            report = build_census(roots)
            component = report["component_to_macros"][0]
            self.assertEqual(
                component["connections"],
                [
                    {
                        "name": "Branch",
                        "parent_part": "BasePart",
                        "parent_connection": "Root",
                        "direct_owned_parts": ["BranchPart"],
                        "authored_attributes": {"name": "Branch", "parent": "BasePart"},
                        "authored_tags": None,
                        "tag_tokens": [],
                        "authored_restrictions": [],
                        "root_to_connection_path": ["Root", "Branch"],
                        "depth": 1,
                    },
                    {
                        "name": "Child",
                        "parent_part": "BasePart",
                        "parent_connection": "Root",
                        "direct_owned_parts": ["ArmPart"],
                        "authored_attributes": {"name": "Child", "parent": "BasePart"},
                        "authored_tags": None,
                        "tag_tokens": [],
                        "authored_restrictions": [],
                        "root_to_connection_path": ["Root", "Child"],
                        "depth": 1,
                    },
                    {
                        "name": "EmptyParentRoot",
                        "parent_part": None,
                        "parent_connection": None,
                        "direct_owned_parts": [],
                        "authored_attributes": {"name": "EmptyParentRoot", "parent": ""},
                        "authored_tags": None,
                        "tag_tokens": [],
                        "authored_restrictions": [],
                        "root_to_connection_path": ["EmptyParentRoot"],
                        "depth": 0,
                    },
                    {
                        "name": "Grand",
                        "parent_part": "ArmPart",
                        "parent_connection": "Child",
                        "direct_owned_parts": ["BarrelPart"],
                        "authored_attributes": {"name": "Grand", "parent": "ArmPart", "tags": "laser"},
                        "authored_tags": "laser",
                        "tag_tokens": ["laser"],
                        "authored_restrictions": [],
                        "root_to_connection_path": ["Root", "Child", "Grand"],
                        "depth": 2,
                    },
                    {
                        "name": "Root",
                        "parent_part": None,
                        "parent_connection": None,
                        "direct_owned_parts": ["BasePart", "BasePart"],
                        "authored_attributes": {"name": "Root"},
                        "authored_tags": None,
                        "tag_tokens": [],
                        "authored_restrictions": [],
                        "root_to_connection_path": ["Root"],
                        "depth": 0,
                    },
                ],
            )
            self.assertEqual(
                [
                    {
                        key: descriptor[key]
                        for key in (
                            "descriptor_index",
                            "part",
                            "subname",
                            "source_connection",
                            "root_to_source_connection_path",
                        )
                    }
                    for descriptor in component["ani_descriptors"]
                ],
                [
                    {
                        "descriptor_index": 0,
                        "part": "BarrelPart",
                        "subname": "Sub_CASE",
                        "source_connection": "Grand",
                        "root_to_source_connection_path": ["Root", "Child", "Grand"],
                    },
                    {
                        "descriptor_index": 1,
                        "part": "BasePart",
                        "subname": "RootSub",
                        "source_connection": "Root",
                        "root_to_source_connection_path": ["Root"],
                    },
                ],
            )
            self.assertNotIn("Nested", render_json(component))
            base_part = next(
                source_part
                for source_part in component["source_parts"]
                if source_part["part"] == "BasePart"
            )
            self.assertEqual(base_part["owning_connection_count"], 2)
            self.assertEqual(base_part["distinct_owning_connection_count"], 1)
            self.assertEqual(base_part["owning_connections"], ["Root", "Root"])
            self.assertEqual(report["counts"]["connection_identities"], 5)
            self.assertEqual(report["component_root_count_distribution"], {"2": 1})
            self.assertEqual(report["connection_depth_distribution"], {"0": 2, "1": 2, "2": 1})
            self.assertEqual(report["counts"]["descriptor_source_path_joins"], 2)
            self.assertEqual(report["unresolved_or_ambiguous_parent_identities"], [])
            self.assertEqual(
                report["unresolved_or_ambiguous_descriptor_path_identities"], []
            )

    def test_connection_identity_resolution_failures_are_closed(self) -> None:
        cases = (
            (
                "missing_parent",
                '<connection name="Root"><parts><part name="Base"/></parts></connection><connection name="Child" parent="Missing"/>',
                "unresolved_parent_part_reference",
            ),
            (
                "ambiguous_parent",
                '<connection name="A"><parts><part name="Shared"/></parts></connection><connection name="B"><parts><part name="Shared"/></parts></connection><connection name="Child" parent="Shared"/>',
                "ambiguous_parent_part_reference",
            ),
            (
                "duplicate_connection",
                '<connection name="Same"/><connection name="Same"/>',
                "duplicate_connection_identity",
            ),
            (
                "cycle",
                '<connection name="A" parent="PartB"><parts><part name="PartA"/></parts></connection><connection name="B" parent="PartA"><parts><part name="PartB"/></parts></connection>',
                "connection_cycle",
            ),
            (
                "self_cycle",
                '<connection name="A" parent="PartA"><parts><part name="PartA"/></parts></connection>',
                "self_parenting_connection",
            ),
        )
        for label, connections, code in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                roots = _source_roots(Path(tmp))
                _write(
                    roots["base"],
                    "assets/component.xml",
                    f'<components><component name="component_a" class="turret"><source geometry="geometry/component_a"/><connections>{connections}</connections></component></components>',
                )
                _write(
                    roots["base"],
                    "assets/macros.xml",
                    _macros(("a_macro", "turret", "component_a")),
                )
                with self.assertRaises(CensusError) as caught:
                    build_census(roots)
                self.assertIn(code, caught.exception.codes)

    def test_descriptor_source_path_missing_or_ambiguous_ownership_fails_closed(self) -> None:
        cases = (
            (
                "missing",
                '<connection name="Root"><parts><part name="Other"/></parts></connection>',
                "unresolved_descriptor_source_path",
            ),
            (
                "ambiguous",
                '<connection name="A"><parts><part name="Target"/></parts></connection><connection name="B"><parts><part name="Target"/></parts></connection>',
                "ambiguous_descriptor_source_path",
            ),
        )
        for label, connections, code in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                roots = _source_roots(Path(tmp))
                _write(
                    roots["base"],
                    "assets/component.xml",
                    f'<components><component name="component_a" class="turret"><source geometry="geometry/component_a"/><connections>{connections}</connections></component></components>',
                )
                _write(
                    roots["base"],
                    "assets/macros.xml",
                    _macros(("a_macro", "turret", "component_a")),
                )
                (roots["base"] / "geometry/component_a.ANI").write_bytes(
                    _ani_bytes(("Target", "Sub"))
                )
                with self.assertRaises(CensusError) as caught:
                    build_census(roots)
                self.assertIn(code, caught.exception.codes)

    def test_firing_endpoints_use_authored_tags_not_connection_spelling(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/component_a"/>
                    <connections>
                      <connection name="Root" tags="part custom  " custom="ExactValue"><parts><part name="Pivot"/></parts></connection>
                      <connection name="Child" tags="part" parent="Pivot"><parts><part name="Barrel"/></parts></connection>
                      <connection name="NotNamedLikeEndpointA" tags="laser  " parent="Barrel"/>
                      <connection name="NotNamedLikeEndpointB" tags="laser" parent="Barrel"/>
                      <connection name="con_laser_unrelated" tags="decoration" parent="Barrel"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/component_b"/>
                    <connections><connection name="LaunchPoint" tags="rocket " marker="preserved"/></connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("conventional_macro", "turret", "conventional_component"),
                    ("missile_macro", "missileturret", "missile_component"),
                ),
            )

            report = build_census(roots)
            conventional, missile = report["component_to_macros"]
            self.assertEqual(
                conventional["firing_endpoints"],
                [
                    {
                        "component": "conventional_component",
                        "component_class": "turret",
                        "macros": ["conventional_macro"],
                        "macro_classes": ["turret"],
                        "connection": "NotNamedLikeEndpointA",
                        "authored_evidence": {
                            "tag_attribute": "laser  ",
                            "tag_token": "laser",
                        },
                        "root_to_endpoint_connection_path": [
                            "Root",
                            "Child",
                            "NotNamedLikeEndpointA",
                        ],
                        "traversed_connection_edges": [
                            {
                                "parent_connection": "Root",
                                "child_connection": "Child",
                                "child_parent_part": "Pivot",
                            },
                            {
                                "parent_connection": "Child",
                                "child_connection": "NotNamedLikeEndpointA",
                                "child_parent_part": "Barrel",
                            },
                        ],
                        "source_part_path": ["Pivot", "Barrel"],
                        "ani_descriptor_memberships": [],
                        "authored_animation_selector_occurrences": [],
                        "selected_ani_descriptor_memberships": [],
                        "unselected_ani_descriptor_memberships": [],
                    },
                    {
                        "component": "conventional_component",
                        "component_class": "turret",
                        "macros": ["conventional_macro"],
                        "macro_classes": ["turret"],
                        "connection": "NotNamedLikeEndpointB",
                        "authored_evidence": {
                            "tag_attribute": "laser",
                            "tag_token": "laser",
                        },
                        "root_to_endpoint_connection_path": [
                            "Root",
                            "Child",
                            "NotNamedLikeEndpointB",
                        ],
                        "traversed_connection_edges": [
                            {
                                "parent_connection": "Root",
                                "child_connection": "Child",
                                "child_parent_part": "Pivot",
                            },
                            {
                                "parent_connection": "Child",
                                "child_connection": "NotNamedLikeEndpointB",
                                "child_parent_part": "Barrel",
                            },
                        ],
                        "source_part_path": ["Pivot", "Barrel"],
                        "ani_descriptor_memberships": [],
                        "authored_animation_selector_occurrences": [],
                        "selected_ani_descriptor_memberships": [],
                        "unselected_ani_descriptor_memberships": [],
                    },
                ],
            )
            self.assertEqual(
                missile["firing_endpoints"],
                [
                    {
                        "component": "missile_component",
                        "component_class": "missileturret",
                        "macros": ["missile_macro"],
                        "macro_classes": ["missileturret"],
                        "connection": "LaunchPoint",
                        "authored_evidence": {
                            "tag_attribute": "rocket ",
                            "tag_token": "rocket",
                        },
                        "root_to_endpoint_connection_path": ["LaunchPoint"],
                        "traversed_connection_edges": [],
                        "source_part_path": [],
                        "ani_descriptor_memberships": [],
                        "authored_animation_selector_occurrences": [],
                        "selected_ani_descriptor_memberships": [],
                        "unselected_ani_descriptor_memberships": [],
                    }
                ],
            )
            unrelated = next(
                connection
                for connection in conventional["connections"]
                if connection["name"] == "con_laser_unrelated"
            )
            self.assertEqual(unrelated["authored_tags"], "decoration")
            self.assertEqual(unrelated["tag_tokens"], ["decoration"])
            root = next(
                connection
                for connection in conventional["connections"]
                if connection["name"] == "Root"
            )
            self.assertEqual(root["authored_tags"], "part custom  ")
            self.assertEqual(root["tag_tokens"], ["part", "custom"])
            self.assertEqual(
                root["authored_attributes"],
                {"custom": "ExactValue", "name": "Root", "tags": "part custom  "},
            )
            self.assertEqual(report["counts"]["firing_endpoint_identities"], 3)
            self.assertEqual(report["counts"]["conventional_firing_endpoints"], 2)
            self.assertEqual(report["counts"]["missileturret_firing_endpoints"], 1)
            self.assertEqual(report["firing_endpoint_count_distribution"], {"1": 1, "2": 1})
            self.assertEqual(
                report["firing_endpoint_criterion"],
                {
                    "evidence_classification": "shipped-source",
                    "structural_rule": "exact direct connection tag token selected by exact component class",
                    "component_class_to_tag_token": {
                        "missileturret": "rocket",
                        "turret": "laser",
                    },
                },
            )
            self.assertEqual(
                report["firing_endpoint_evidence_patterns"],
                [
                    {
                        "component_class": "missileturret",
                        "tag_token": "rocket",
                        "exact_tag_attribute": "rocket ",
                        "endpoint_count": 1,
                    },
                    {
                        "component_class": "turret",
                        "tag_token": "laser",
                        "exact_tag_attribute": "laser",
                        "endpoint_count": 1,
                    },
                    {
                        "component_class": "turret",
                        "tag_token": "laser",
                        "exact_tag_attribute": "laser  ",
                        "endpoint_count": 1,
                    },
                ],
            )
            self.assertEqual(
                report["firing_endpoints"],
                conventional["firing_endpoints"] + missile["firing_endpoints"],
            )

    def test_endpoint_source_part_paths_and_exact_descriptor_membership(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/component_a"/>
                    <connections>
                      <connection name="Root"><parts><part name="SharedPart"/><part name="SiblingPart"/></parts></connection>
                      <connection name="SharedNode" parent="SharedPart"><parts><part name="BranchAPart"/><part name="BranchBPart"/></parts></connection>
                      <connection name="EndpointA" tags="laser" parent="BranchAPart"/>
                      <connection name="BranchB" parent="BranchBPart"><parts><part name="DeepPart"/></parts></connection>
                      <connection name="EndpointB" tags="laser" parent="DeepPart"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/component_b"/>
                    <connections><connection name="RootEndpoint" tags="rocket"><parts><part name="UnusedMissilePart"/></parts></connection></connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("conventional_macro", "turret", "conventional_component"),
                    ("missile_macro", "missileturret", "missile_component"),
                ),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(
                    ("SharedPart", "SharedSub"),
                    ("BranchAPart", "SameSub"),
                    ("SiblingPart", "SameSub"),
                    ("BranchBPart", "BranchBSub"),
                    ("DeepPart", "DeepSubA"),
                    ("DeepPart", "DeepSubB"),
                )
            )
            (roots["base"] / "geometry/component_b.ANI").write_bytes(
                _ani_bytes(("UnusedMissilePart", "OffPath"))
            )

            report = build_census(roots)
            conventional, missile = report["component_to_macros"]
            endpoint_a, endpoint_b = conventional["firing_endpoints"]
            self.assertEqual(
                endpoint_a["traversed_connection_edges"],
                [
                    {
                        "parent_connection": "Root",
                        "child_connection": "SharedNode",
                        "child_parent_part": "SharedPart",
                    },
                    {
                        "parent_connection": "SharedNode",
                        "child_connection": "EndpointA",
                        "child_parent_part": "BranchAPart",
                    },
                ],
            )
            self.assertEqual(endpoint_a["source_part_path"], ["SharedPart", "BranchAPart"])
            self.assertEqual(
                [
                    (
                        descriptor["descriptor_index"],
                        descriptor["part"],
                        descriptor["subname"],
                        descriptor["source_connection"],
                        descriptor["root_to_source_connection_path"],
                        descriptor["endpoint_path_edge_index"],
                    )
                    for descriptor in endpoint_a["ani_descriptor_memberships"]
                ],
                [
                    (0, "SharedPart", "SharedSub", "Root", ["Root"], 0),
                    (
                        1,
                        "BranchAPart",
                        "SameSub",
                        "SharedNode",
                        ["Root", "SharedNode"],
                        1,
                    ),
                ],
            )
            self.assertEqual(
                endpoint_b["source_part_path"],
                ["SharedPart", "BranchBPart", "DeepPart"],
            )
            self.assertEqual(
                [(item["part"], item["subname"]) for item in endpoint_b["ani_descriptor_memberships"]],
                [
                    ("SharedPart", "SharedSub"),
                    ("BranchBPart", "BranchBSub"),
                    ("DeepPart", "DeepSubA"),
                    ("DeepPart", "DeepSubB"),
                ],
            )
            self.assertNotIn(
                ("SiblingPart", "SameSub"),
                [(item["part"], item["subname"]) for item in endpoint_a["ani_descriptor_memberships"] + endpoint_b["ani_descriptor_memberships"]],
            )
            root_endpoint = missile["firing_endpoints"][0]
            self.assertEqual(root_endpoint["traversed_connection_edges"], [])
            self.assertEqual(root_endpoint["source_part_path"], [])
            self.assertEqual(root_endpoint["ani_descriptor_memberships"], [])
            self.assertEqual(report["endpoint_path_depth_distribution"], {"0": 1, "2": 1, "3": 1})
            self.assertEqual(report["counts"]["traversed_endpoint_part_occurrences"], 5)
            self.assertEqual(report["endpoint_path_descriptor_join_distribution"], {"0": 1, "2": 1, "4": 1})
            self.assertEqual(report["endpoint_paths_by_descriptor_join_cardinality"], {"zero": 1, "one": 0, "multiple": 2})
            self.assertEqual(report["counts"]["descriptor_endpoint_path_memberships"], 6)
            self.assertEqual(report["counts"]["descriptors_on_at_least_one_endpoint_path"], 5)
            self.assertEqual(report["counts"]["descriptors_only_off_endpoint_paths"], 2)
            self.assertEqual(report["counts"]["unresolved_or_ambiguous_endpoint_path_identities"], 0)

    def test_exact_authored_animation_selector_joins_on_endpoint_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/component_a"/>
                  <connections>
                    <connection name="Root">
                      <animations><animation name="ExactSelector"/><animation name="SiblingOnly"/></animations>
                      <parts><part name="PathPart"/><part name="SiblingPart"/></parts>
                    </connection>
                    <connection name="Child" parent="PathPart">
                      <animations><animation name="ExactSelector"/></animations>
                      <parts><part name="ChildPart"/></parts>
                    </connection>
                    <connection name="Endpoint" tags="laser" parent="ChildPart"/>
                    <connection name="OffPath">
                      <animations><animation name="OffPathSelector"/></animations>
                      <parts><part name="OffPathPart"/></parts>
                    </connection>
                  </connections>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(
                    ("PathPart", "ExactSelector"),
                    ("SiblingPart", "ExactSelector"),
                    ("SiblingPart", "SiblingOnly"),
                    ("PathPart", "exactselector"),
                    ("PathPart", "NoSelector"),
                    ("ChildPart", "ExactSelector"),
                    ("OffPathPart", "OffPathSelector"),
                )
            )

            report = build_census(roots)
            component = report["component_to_macros"][0]
            root_selector = next(
                selector
                for selector in component["authored_connection_animations"]
                if selector["connection"] == "Root"
            )
            self.assertEqual(root_selector["descriptor_match_count"], 2)
            self.assertEqual(
                [(item["part"], item["subname"]) for item in root_selector["connection_ani_descriptors"]],
                [
                    ("PathPart", "ExactSelector"),
                    ("SiblingPart", "ExactSelector"),
                ],
            )
            endpoint = component["firing_endpoints"][0]
            self.assertEqual(
                [
                    (
                        occurrence["source_connection"],
                        occurrence["animation_name"],
                        occurrence["selector_connection_descriptor_match_count"],
                        occurrence["endpoint_path_edge_index"],
                    )
                    for occurrence in endpoint["authored_animation_selector_occurrences"]
                ],
                [
                    ("Root", "ExactSelector", 2, 0),
                    ("Root", "SiblingOnly", 1, 0),
                    ("Child", "ExactSelector", 1, 1),
                ],
            )
            self.assertEqual(
                [
                    (item["part"], item["subname"], item["source_connection"])
                    for item in endpoint["selected_ani_descriptor_memberships"]
                ],
                [
                    ("PathPart", "ExactSelector", "Root"),
                    ("ChildPart", "ExactSelector", "Child"),
                ],
            )
            self.assertEqual(
                [(item["part"], item["subname"]) for item in endpoint["unselected_ani_descriptor_memberships"]],
                [
                    ("PathPart", "exactselector"),
                    ("PathPart", "NoSelector"),
                ],
            )
            self.assertNotIn(
                "OffPathSelector",
                [
                    occurrence["animation_name"]
                    for occurrence in endpoint["authored_animation_selector_occurrences"]
                ],
            )
            sibling_only = endpoint["authored_animation_selector_occurrences"][1]
            self.assertEqual(
                [(item["part"], item["subname"]) for item in sibling_only["selector_connection_ani_descriptors"]],
                [("SiblingPart", "SiblingOnly")],
            )
            self.assertEqual(
                sibling_only["selected_endpoint_path_ani_descriptor_memberships"],
                [],
            )
            self.assertEqual(report["authored_animation_selector_descriptor_cardinality"], {"1": 3, "2": 1})
            self.assertEqual(report["endpoint_path_selector_connection_descriptor_cardinality"], {"1": 2, "2": 1})
            self.assertEqual(report["counts"]["endpoint_path_animation_selector_occurrences"], 3)
            self.assertEqual(report["counts"]["conventional_endpoint_path_animation_selector_occurrences"], 3)
            self.assertEqual(report["counts"]["missileturret_endpoint_path_animation_selector_occurrences"], 0)
            self.assertEqual(report["counts"]["selected_endpoint_path_descriptor_memberships"], 2)
            self.assertEqual(report["counts"]["path_local_descriptors_left_unselected"], 2)
            self.assertEqual(report["counts"]["selected_endpoint_path_descriptor_identities"], 2)
            self.assertEqual(report["endpoint_paths_by_selected_descriptor_cardinality"], {"zero": 0, "one": 0, "multiple": 1})
            self.assertEqual(
                report["authored_animation_selector_identity_rule"][
                    "evidence_classification"
                ],
                "shipped-source",
            )
            self.assertEqual(
                report["authored_animation_selector_identity_rule"]["corroboration"][
                    "evidence_classification"
                ],
                "third-party-technique",
            )
            self.assertEqual(
                endpoint["authored_animation_selector_occurrences"][0][
                    "authored_selector_evidence"
                ],
                {"connection": "Root", "name": "ExactSelector"},
            )
            self.assertEqual(report["unresolved_endpoint_path_animation_selectors"], [])
            self.assertEqual(render_json(report), render_json(build_census(roots)))

    def test_conventional_same_subname_structural_relationships_are_exact_and_deduplicated(self) -> None:
        paths = {
            "Root": ["Root"],
            "Child": ["Root", "Child"],
            "Grand": ["Root", "Child", "Grand"],
            "Sibling": ["Sibling"],
        }
        selectors = [
            ("Root", "Same"),
            ("Root", "Ancestor"),
            ("Root", "Multi"),
            ("Root", "CaseName"),
            ("Child", "Multi"),
            ("Grand", "DescendantOnly"),
            ("Sibling", "SiblingOnly"),
        ]
        descriptors = [
            (0, "RootPart", "Same", "Root", (1, 0, 0, 0, 0)),
            (1, "RootPart", "DescendantOnly", "Root", (0, 0, 0, 0, 0)),
            (2, "RootPart", "casename", "Root", (0, 0, 0, 0, 0)),
            (3, "RootPart", "NoSelector", "Root", (0, 0, 0, 0, 0)),
            (4, "ChildPart", "Ancestor", "Child", (0, 0, 0, 0, 0)),
            (5, "GrandPart", "Multi", "Grand", (0, 1, 0, 0, 0)),
            (6, "GrandPart", "SiblingOnly", "Grand", (0, 0, 0, 0, 0)),
        ]
        memberships = [
            {
                "descriptor_index": index,
                "part": part,
                "subname": subname,
                "source_connection": connection,
                "root_to_source_connection_path": paths[connection],
                "channel_counts": dict(
                    zip(("position", "rotation", "scale", "pre_scale", "post_scale"), counts)
                ),
            }
            for index, part, subname, connection, counts in descriptors
        ]
        component_to_macros = [
            {
                "component": "component_a",
                "component_class": "turret",
                "connections": [
                    {"name": connection, "root_to_connection_path": path}
                    for connection, path in paths.items()
                ],
                "authored_connection_animations": [
                    {"connection": connection, "name": name}
                    for connection, name in selectors
                ],
            }
        ]
        firing_endpoints = [
            {
                "component": "component_a",
                "component_class": "turret",
                "connection": endpoint,
                "ani_descriptor_memberships": copy.deepcopy(memberships),
            }
            for endpoint in ("EndpointA", "EndpointB")
        ]

        coverage = _build_same_subname_structural_relationship_coverage(
            component_to_macros, firing_endpoints
        )

        self.assertEqual(coverage["evidence_classification"], "inference")
        with self.subTest("relationship inventory"):
            self.assertEqual(coverage["semantic_claim"], "none")
            self.assertEqual(coverage["descriptor_memberships"], 14)
            self.assertEqual(coverage["unique_descriptors"], 7)
            inventory = {
                descriptor["literal_subname"]: descriptor
                for descriptor in coverage["descriptors"]
            }
            self.assertEqual(
                inventory["Same"]["root_to_source_connection_path"], ["Root"]
            )
            self.assertEqual(inventory["Same"]["source_connection"], "Root")
            self.assertEqual(inventory["Same"]["endpoint_membership_count"], 2)
            self.assertTrue(inventory["Same"]["descriptor_has_keys"])
            self.assertEqual(
                inventory["Same"]["same_subname_selector_relationships"],
                [
                    {
                        "selector_connection": "Root",
                        "root_to_selector_connection_path": ["Root"],
                        "relation": "same_source_connection",
                        "distance": 0,
                    }
                ],
            )
            self.assertEqual(
                inventory["Ancestor"]["same_subname_selector_relationships"],
                [
                    {
                        "selector_connection": "Root",
                        "root_to_selector_connection_path": ["Root"],
                        "relation": "strict_ancestor_connection",
                        "distance": 1,
                    }
                ],
            )
            self.assertEqual(
                inventory["Multi"]["strict_ancestor_selector_distances"], [1, 2]
            )
            self.assertEqual(
                [
                    relationship["relation"]
                    for relationship in inventory["DescendantOnly"][
                        "same_subname_selector_relationships"
                    ]
                ],
                ["descendant_connection"],
            )
            self.assertEqual(
                [
                    relationship["relation"]
                    for relationship in inventory["SiblingOnly"][
                        "same_subname_selector_relationships"
                    ]
                ],
                ["unrelated_connection"],
            )
            self.assertEqual(
                inventory["casename"]["same_subname_selector_relationships"], []
            )
            self.assertEqual(
                inventory["NoSelector"]["same_subname_selector_relationships"], []
            )
            self.assertTrue(
                inventory["NoSelector"]["no_same_subname_selector_on_ancestry"]
            )
            self.assertEqual(
                coverage["relationship_occurrence_counts"],
                {
                    "same_source_connection": 1,
                    "strict_ancestor_connection": 3,
                    "descendant_connection": 1,
                    "unrelated_connection": 1,
                    "none": 2,
                },
            )
            multi_row = next(
                row
                for row in coverage["full_cross_tab"]
                if row["literal_subname"] == "Multi"
            )
            self.assertEqual(
                multi_row,
                {
                    "literal_subname": "Multi",
                    "descriptor_key_class": "has_keys",
                    "same_connection_selector": False,
                    "nearest_ancestor_same_subname_selector_distance": 1,
                    "no_same_subname_selector_on_ancestry": False,
                    "multiple_matching_ancestors": True,
                    "unique_descriptor_count": 1,
                    "endpoint_membership_count": 2,
                },
            )
            self.assertEqual(
                coverage["hypothesis_assessment"]["assessment"],
                "structurally incomplete",
            )
        self.assertEqual(
            render_json(coverage),
            render_json(
                _build_same_subname_structural_relationship_coverage(
                    component_to_macros, firing_endpoints
                )
            ),
        )

    def test_ani_key_ranges_follow_descriptor_table_and_channel_count_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "mixed.ANI"
            path.write_bytes(
                _ani_bytes(
                    ("ZuluPart", "Second", 1, 0, 1, 0, 0),
                    ("AlphaPart", "First", 0, 2, 0, 0, 1),
                )
            )

            descriptors = _parse_ani_descriptors(path)

            self.assertEqual(
                [(item["descriptor_index"], item["part"]) for item in descriptors],
                [(0, "ZuluPart"), (1, "AlphaPart")],
            )
            self.assertEqual(
                descriptors[0]["key_data"],
                {
                    "record_range": {"start": 0, "end_exclusive": 2},
                    "byte_range": {"start": 336, "end_exclusive": 592},
                    "channels": {
                        "position": {
                            "record_count": 1,
                            "record_range": {"start": 0, "end_exclusive": 1},
                            "byte_range": {"start": 336, "end_exclusive": 464},
                        },
                        "rotation": {
                            "record_count": 0,
                            "record_range": {"start": 1, "end_exclusive": 1},
                            "byte_range": {"start": 464, "end_exclusive": 464},
                        },
                        "scale": {
                            "record_count": 1,
                            "record_range": {"start": 1, "end_exclusive": 2},
                            "byte_range": {"start": 464, "end_exclusive": 592},
                        },
                        "pre_scale": {
                            "record_count": 0,
                            "record_range": {"start": 2, "end_exclusive": 2},
                            "byte_range": {"start": 592, "end_exclusive": 592},
                        },
                        "post_scale": {
                            "record_count": 0,
                            "record_range": {"start": 2, "end_exclusive": 2},
                            "byte_range": {"start": 592, "end_exclusive": 592},
                        },
                    },
                },
            )
            self.assertEqual(
                descriptors[1]["key_data"],
                {
                    "record_range": {"start": 2, "end_exclusive": 5},
                    "byte_range": {"start": 592, "end_exclusive": 976},
                    "channels": {
                        "position": {
                            "record_count": 0,
                            "record_range": {"start": 2, "end_exclusive": 2},
                            "byte_range": {"start": 592, "end_exclusive": 592},
                        },
                        "rotation": {
                            "record_count": 2,
                            "record_range": {"start": 2, "end_exclusive": 4},
                            "byte_range": {"start": 592, "end_exclusive": 848},
                        },
                        "scale": {
                            "record_count": 0,
                            "record_range": {"start": 4, "end_exclusive": 4},
                            "byte_range": {"start": 848, "end_exclusive": 848},
                        },
                        "pre_scale": {
                            "record_count": 0,
                            "record_range": {"start": 4, "end_exclusive": 4},
                            "byte_range": {"start": 848, "end_exclusive": 848},
                        },
                        "post_scale": {
                            "record_count": 1,
                            "record_range": {"start": 4, "end_exclusive": 5},
                            "byte_range": {"start": 848, "end_exclusive": 976},
                        },
                    },
                },
            )

    def test_candidate_key_record_slot_map_covers_all_128_bytes_and_parses_raw_values(self) -> None:
        expected_types = (
            ["float32_le"] * 3
            + ["enum32_le"] * 3
            + ["float32_le"] * 18
            + ["int32_le"]
            + ["float32_le"] * 6
            + ["uint32_le"]
        )
        self.assertEqual(len(_ANI_KEY_RECORD_CANDIDATE_SLOTS), 32)
        self.assertEqual(
            [slot["byte_offset"] for slot in _ANI_KEY_RECORD_CANDIDATE_SLOTS],
            list(range(0, 128, 4)),
        )
        self.assertEqual(
            [slot["width_bytes"] for slot in _ANI_KEY_RECORD_CANDIDATE_SLOTS],
            [4] * 32,
        )
        self.assertEqual(
            [slot["candidate_type"] for slot in _ANI_KEY_RECORD_CANDIDATE_SLOTS],
            expected_types,
        )
        self.assertEqual(
            sum(int(slot["width_bytes"]) for slot in _ANI_KEY_RECORD_CANDIDATE_SLOTS),
            128,
        )

        values = tuple(
            float(index) if candidate_type == "float32_le" else index
            for index, candidate_type in enumerate(expected_types)
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "typed.ANI"
            path.write_bytes(
                _ani_bytes(
                    ("Part", "Sub", 1, 0, 0, 0, 0),
                    key_data=_candidate_key_record(values),
                )
            )
            descriptor = _parse_ani_descriptors(path)[0]

        raw_record = descriptor["_candidate_raw_key_records"][0]
        self.assertEqual(raw_record["record_index"], 0)
        self.assertEqual(raw_record["byte_offset"], 176)
        self.assertEqual(raw_record["raw_values"], list(values))

    def test_channel_1_restriction_correlation_uses_exact_source_connections_and_masks(self) -> None:
        def main_triple_record(x: float, y: float, z: float) -> bytes:
            values: list[float | int] = [0] * 32
            values[0:3] = [x, y, z]
            return _candidate_key_record(tuple(values))

        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="correlation_component" class="turret">
                    <source geometry="geometry/correlation"/>
                    <connections>
                      <connection name="WrongAncestor">
                        <restrictions><restriction type="rotation_y"><limits><min value="-90"/><max value="90"/></limits></restriction></restrictions>
                        <parts><part name="AncestorPart"/></parts>
                      </connection>
                      <connection name="ExactA" parent="AncestorPart">
                        <animations><animation name="Selected"/></animations>
                        <restrictions><restriction type="rotation_x"><limits><min value="-10 "/><max value=" 20"/></limits></restriction></restrictions>
                        <parts><part name="PartA"/></parts>
                      </connection>
                      <connection name="EndpointA1" tags="laser" parent="PartA"/>
                      <connection name="EndpointA2" tags="laser" parent="PartA"/>
                      <connection name="ExactB">
                        <animations><animation name="Selected"/></animations>
                        <restrictions><restriction type="rotation_x"/><restriction type="rotation_y"><limits><min value="-5"/></limits></restriction></restrictions>
                        <parts><part name="PartB"/></parts>
                      </connection>
                      <connection name="EndpointB" tags="laser" parent="PartB"/>
                      <connection name="ExactC">
                        <animations><animation name="Selected"/></animations>
                        <parts><part name="PartC"/></parts>
                      </connection>
                      <connection name="EndpointC" tags="laser" parent="PartC"/>
                      <connection name="ControlD">
                        <animations><animation name="Selected"/></animations>
                        <restrictions><restriction type="rotation_y"/></restrictions>
                        <parts><part name="PartD"/></parts>
                      </connection>
                      <connection name="EndpointD" tags="laser" parent="PartD"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    (
                        "correlation_macro",
                        "turret",
                        "correlation_component",
                    )
                ),
            )
            (roots["base"] / "geometry/correlation.ANI").write_bytes(
                _ani_bytes(
                    ("PartA", "Selected", 0, 2, 0, 0, 0),
                    ("PartB", "Selected", 0, 2, 0, 0, 0),
                    ("PartC", "Selected", 0, 2, 0, 0, 0),
                    ("PartD", "Selected", 0, 2, 0, 0, 0),
                    key_data=b"".join(
                        (
                            main_triple_record(1.0, 3.0, 4.0),
                            main_triple_record(2.0, 3.0, 5.0),
                            main_triple_record(0.0, 0.0, 0.0),
                            main_triple_record(0.0, 1.0, 0.0),
                            main_triple_record(1.0, 1.0, 1.0),
                            main_triple_record(2.0, 2.0, 2.0),
                            main_triple_record(7.0, 8.0, 9.0),
                            main_triple_record(7.0, 8.0, 9.0),
                        )
                    ),
                )
            )
            report = build_census(roots)

        component = report["component_to_macros"][0]
        connections = {
            connection["name"]: connection for connection in component["connections"]
        }
        self.assertEqual(
            connections["ExactA"]["authored_restrictions"],
            [
                {
                    "source_connection": "ExactA",
                    "restriction_index": 0,
                    "type_token": "rotation_x",
                    "type_token_raw_text": "rotation_x",
                    "authored_min": {
                        "raw_text": "-10 ",
                        "candidate_numeric_value": -10.0,
                    },
                    "authored_max": {
                        "raw_text": " 20",
                        "candidate_numeric_value": 20.0,
                    },
                    "evidence_classification": "shipped-source",
                }
            ],
        )
        self.assertEqual(
            connections["ExactB"]["authored_restrictions"][0]["authored_min"],
            None,
        )
        self.assertEqual(
            connections["ExactB"]["authored_restrictions"][1]["authored_max"],
            None,
        )

        study = report["candidate_channel_1_authored_restriction_correlation"]
        self.assertEqual(study["evidence_classification"], "inference")
        self.assertEqual(
            study["identity_join_evidence_classification"], "shipped-source"
        )
        self.assertEqual(
            study["x4converter_label_lead"],
            {
                "label": "rotation_euler",
                "evidence_classification": "third-party-technique",
                "semantic_promotion": "not_permitted_by_this_study",
            },
        )
        primary = study["primary_changing_main_triple_cohort"]
        control = study["identical_main_triple_control_cohort"]
        self.assertEqual(primary["selected_descriptor_memberships"], 4)
        self.assertEqual(primary["unique_descriptor_count"], 3)
        self.assertEqual(control["selected_descriptor_memberships"], 1)
        self.assertEqual(control["unique_descriptor_count"], 1)

        records = {record["part"]: record for record in primary["descriptors"]}
        self.assertEqual(records["PartA"]["source_connection"], "ExactA")
        self.assertEqual(records["PartA"]["restriction_count"], 1)
        self.assertEqual(records["PartA"]["restriction_type_tokens"], ["rotation_x"])
        self.assertEqual(records["PartA"]["changing_component_mask"], "101")
        self.assertEqual(
            [
                component["changes_by_exact_raw_bits"]
                for component in records["PartA"]["candidate_main_components"]
            ],
            [True, False, True],
        )
        self.assertEqual(
            records["PartA"]["candidate_main_components"][0]["raw_bit_sequence"],
            ["0x3f800000", "0x40000000"],
        )
        self.assertEqual(
            records["PartA"]["candidate_main_components"][0][
                "candidate_numeric_extrema"
            ],
            {"finite_count": 2, "non_finite_count": 0, "minimum": 1.0, "maximum": 2.0},
        )
        self.assertNotIn("rotation_y", records["PartA"]["restriction_type_tokens"])
        self.assertEqual(records["PartA"]["selected_endpoint_membership_count"], 2)
        self.assertEqual(records["PartB"]["restriction_count"], 2)
        self.assertEqual(records["PartC"]["restriction_count"], 0)

        self.assertEqual(
            primary["restriction_type_token_by_changing_component_mask"],
            [
                {
                    "restriction_type_token": None,
                    "changing_component_mask": "111",
                    "restriction_record_or_unrestricted_descriptor_count": 1,
                },
                {
                    "restriction_type_token": "rotation_x",
                    "changing_component_mask": "010",
                    "restriction_record_or_unrestricted_descriptor_count": 1,
                },
                {
                    "restriction_type_token": "rotation_x",
                    "changing_component_mask": "101",
                    "restriction_record_or_unrestricted_descriptor_count": 1,
                },
                {
                    "restriction_type_token": "rotation_y",
                    "changing_component_mask": "010",
                    "restriction_record_or_unrestricted_descriptor_count": 1,
                },
            ],
        )
        self.assertEqual(
            primary["unique_source_connection_restriction_counts"],
            {"restricted": 2, "unrestricted": 1},
        )
        self.assertEqual(
            primary["ambiguous_or_multiple_restriction_cases"],
            [
                {
                    "component": "correlation_component",
                    "descriptor_index": 1,
                    "source_connection": "ExactB",
                    "restriction_count": 2,
                    "restriction_type_tokens": ["rotation_x", "rotation_y"],
                    "reasons": ["multiple_authored_restrictions"],
                }
            ],
        )
        self.assertEqual(
            control["descriptors"][0]["changing_component_mask"], "000"
        )
        self.assertEqual(
            control["descriptors"][0]["restriction_type_tokens"], ["rotation_y"]
        )
        rotation_x = study["single_rotation_x_or_y_restriction_comparisons"][
            "rotation_x"
        ]
        self.assertEqual(rotation_x["primary_descriptor_count"], 1)
        self.assertEqual(rotation_x["corresponding_candidate_component"], "slot_000")
        self.assertEqual(rotation_x["corresponding_component_changed_count"], 1)
        self.assertEqual(
            rotation_x["other_component_changed_counts"],
            {"slot_004": 0, "slot_008": 1},
        )
        self.assertEqual(
            study["semantic_discriminator_assessment"]["status"],
            "not_strong_one_to_one",
        )
        rendered = render_json(study)
        self.assertNotIn('"candidate_channel_1_label": "rotation"', rendered)
        self.assertNotIn('"evidence_classification": "live-tested"', rendered)

    def test_descriptor_offset_148_inventory_and_slot_024_relationships_are_exact(self) -> None:
        def record(slot_024: float) -> bytes:
            values: list[float | int] = [0] * 32
            values[6] = slot_024
            return _candidate_key_record(tuple(values))

        with tempfile.TemporaryDirectory() as tmp:
            signed_zero_path = Path(tmp) / "descriptor_signed_zero.ANI"
            signed_zero_path.write_bytes(
                _ani_bytes(
                    ("PlusZero", "Selected", 0, 0, 0, 0, 0, 0x00000000),
                    ("MinusZero", "Selected", 0, 0, 0, 0, 0, 0x80000000),
                )
            )
            signed_zero_descriptors = _parse_ani_descriptors(signed_zero_path)
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_a" class="turret">
                    <source geometry="geometry/offset_a"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="PartA"/></parts></connection>
                      <connection name="EndpointA" tags="laser" parent="PartA"/>
                      <connection name="EndpointB" tags="laser" parent="PartA"/>
                    </connections>
                  </component>
                  <component name="conventional_b" class="turret">
                    <source geometry="geometry/offset_b"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="PartB"/></parts></connection>
                      <connection name="Endpoint" tags="laser" parent="PartB"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/offset_missile"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="MissilePart"/></parts></connection>
                      <connection name="Endpoint" tags="rocket" parent="MissilePart"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("conventional_a_macro", "turret", "conventional_a"),
                    ("conventional_b_macro", "turret", "conventional_b"),
                    ("missile_macro", "missileturret", "missile_component"),
                ),
            )
            (roots["base"] / "geometry/offset_a.ANI").write_bytes(
                _ani_bytes(
                    ("PartA", "Selected", 0, 1, 2, 2, 2, 0x80000000),
                    key_data=b"".join(
                        record(value)
                        for value in (+0.0, -1.0, -0.0, -0.0, 1.0, -1.0, 1.0)
                    ),
                )
            )
            (roots["base"] / "geometry/offset_b.ANI").write_bytes(
                _ani_bytes(
                    ("PartB", "Selected", 2, 2, 2, 2, 0, 0x40400000),
                    key_data=b"".join(
                        record(value)
                        for value in (1.0, 2.0, 4.0, 5.0, 3.0, 3.0, 1.0, 3.0)
                    ),
                )
            )
            (roots["base"] / "geometry/offset_missile.ANI").write_bytes(
                _ani_bytes(
                    ("MissilePart", "Selected", 0, 0, 0, 0, 0, 0x7FC00001)
                )
            )
            report = build_census(roots)

        self.assertEqual(
            [
                descriptor["descriptor_offset_148"]["raw_bits"]
                for descriptor in signed_zero_descriptors
            ],
            ["0x00000000", "0x80000000"],
        )
        self.assertEqual(
            [
                descriptor["descriptor_offset_148"]["candidate_float32_decode"][
                    "value"
                ]
                for descriptor in signed_zero_descriptors
            ],
            [+0.0, -0.0],
        )
        self.assertEqual(
            len(
                {
                    descriptor["descriptor_offset_148"]["raw_bits"]
                    for descriptor in signed_zero_descriptors
                }
            ),
            2,
        )

        component_a = next(
            record
            for record in report["component_to_macros"]
            if record["component"] == "conventional_a"
        )
        descriptor_field = component_a["ani_descriptors"][0]["descriptor_offset_148"]
        self.assertEqual(descriptor_field["byte_offset_within_descriptor"], 148)
        self.assertEqual(descriptor_field["width_bytes"], 4)
        self.assertEqual(descriptor_field["raw_bits"], "0x80000000")
        self.assertEqual(
            descriptor_field["candidate_float32_decode"],
            {"kind": "finite", "value": -0.0},
        )
        self.assertEqual(
            descriptor_field["raw_bits_evidence_classification"], "shipped-source"
        )
        self.assertEqual(
            descriptor_field["candidate_decode_evidence_classification"],
            "third-party-technique",
        )
        self.assertNotIn("duration", descriptor_field)

        inventory = report[
            "selected_descriptor_offset_148_inventory_and_slot_024_relationships"
        ]
        self.assertEqual(inventory["evidence_classification"], "inference")
        self.assertEqual(inventory["engine_requiredness"], "unresolved")
        lead = inventory["x4converter_lead"]
        self.assertEqual(lead["evidence_classification"], "third-party-technique")
        self.assertEqual(lead["x4converter_member"], "Duration")
        self.assertEqual(lead["read_site"]["line_range_at_pinned_commit"], [21, 26])
        self.assertEqual(lead["write_site"]["line_range_at_pinned_commit"], [79, 84])
        self.assertEqual(lead["validation_report_site"]["line_range_at_pinned_commit"], [205, 207])
        self.assertEqual(lead["other_actual_use_sites"], [])
        self.assertEqual(lead["engine_requiredness"], "unresolved")

        conventional = inventory["conventional"]
        missile = inventory["missileturret"]
        self.assertEqual(conventional["selected_descriptor_memberships"], 3)
        self.assertEqual(conventional["unique_selected_descriptors"], 2)
        self.assertEqual(missile["selected_descriptor_memberships"], 1)
        self.assertEqual(missile["unique_selected_descriptors"], 1)
        self.assertEqual(
            conventional["offset_148_value_inventory"],
            {
                "descriptor_count": 2,
                "finite_count": 2,
                "non_finite_count": 0,
                "numeric_zero_count": 1,
                "numeric_nonzero_count": 1,
                "positive_zero_raw_bit_count": 0,
                "negative_zero_raw_bit_count": 1,
                "distinct_raw_bit_pattern_count": 2,
                "raw_bit_pattern_distribution_limit": 256,
                "raw_bit_pattern_distribution_is_complete": True,
                "raw_bit_pattern_distribution": [
                    {
                        "raw_bits": "0x40400000",
                        "candidate_float32_decode": {"kind": "finite", "value": 3.0},
                        "descriptor_count": 1,
                    },
                    {
                        "raw_bits": "0x80000000",
                        "candidate_float32_decode": {"kind": "finite", "value": -0.0},
                        "descriptor_count": 1,
                    },
                ],
            },
        )
        self.assertEqual(missile["offset_148_value_inventory"]["finite_count"], 0)
        self.assertEqual(missile["offset_148_value_inventory"]["non_finite_count"], 1)
        self.assertEqual(
            missile["offset_148_value_inventory"]["raw_bit_pattern_distribution"],
            [
                {
                    "raw_bits": "0x7fc00001",
                    "candidate_float32_decode": {"kind": "nan", "value": None},
                    "descriptor_count": 1,
                }
            ],
        )

        channels = {
            channel["candidate_channel_id"]: channel
            for channel in conventional["candidate_channel_slot_024_relationships"]
        }
        self.assertEqual(
            channels["candidate_channel_0"]["key_count_distribution"],
            {"no_keys": 1, "one_key": 0, "multiple_keys": 1},
        )
        self.assertEqual(
            channels["candidate_channel_0"]["numeric_relationship_distribution"],
            {
                "no_keys": 1,
                "non_finite": 0,
                "equals_both": 0,
                "equals_first": 0,
                "equals_last": 0,
                "greater_than_sequence_maximum": 1,
                "less_than_sequence_minimum": 0,
                "other": 0,
            },
        )
        self.assertEqual(
            channels["candidate_channel_1"]["key_count_distribution"],
            {"no_keys": 0, "one_key": 1, "multiple_keys": 1},
        )
        self.assertEqual(
            channels["candidate_channel_1"]["raw_bit_relationship_distribution"]["other"],
            2,
        )
        self.assertEqual(
            channels["candidate_channel_1"]["numeric_relationship_distribution"]["equals_both"],
            1,
        )
        self.assertEqual(
            channels["candidate_channel_1"]["numeric_relationship_distribution"]["less_than_sequence_minimum"],
            1,
        )
        self.assertEqual(
            channels["candidate_channel_2"]["raw_bit_relationship_distribution"],
            {
                "no_keys": 0,
                "equals_both": 1,
                "equals_first": 0,
                "equals_last": 1,
                "other": 0,
            },
        )
        self.assertEqual(
            channels["candidate_channel_3"]["numeric_relationship_distribution"],
            {
                "no_keys": 0,
                "non_finite": 0,
                "equals_both": 0,
                "equals_first": 1,
                "equals_last": 1,
                "greater_than_sequence_maximum": 0,
                "less_than_sequence_minimum": 0,
                "other": 0,
            },
        )
        self.assertEqual(
            channels["candidate_channel_4"]["numeric_relationship_distribution"]["other"],
            1,
        )
        self.assertEqual(
            channels["candidate_channel_4"]["numeric_relationship_distribution"]["no_keys"],
            1,
        )

        rendered = render_json(inventory).lower()
        self.assertNotIn('"evidence_classification": "live-tested"', rendered)
        self.assertNotIn('"semantic_status": "resolved"', rendered)
        self.assertNotIn('"semantic_status": "final"', rendered)
        self.assertEqual(inventory["semantic_claim"], "none")

    def test_selected_raw_slot_distributions_are_unique_separate_and_nonsemantic(self) -> None:
        conventional_first = [0] * 32
        conventional_second = [0] * 32
        conventional_second[0] = -0.0
        conventional_second[1] = 2.5
        conventional_second[3] = 7
        conventional_second[24] = -2
        conventional_second[31] = 9
        missile_values = [0] * 32
        missile_values[0] = float("nan")
        missile_values[1] = float("inf")
        missile_values[3] = -4
        missile_values[31] = 0xFFFFFFFF

        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/component_a"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="PathPart"/></parts></connection>
                      <connection name="EndpointA" tags="laser" parent="PathPart"/>
                      <connection name="EndpointB" tags="laser" parent="PathPart"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/component_b"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="MissilePart"/></parts></connection>
                      <connection name="Endpoint" tags="rocket" parent="MissilePart"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("conventional_macro", "turret", "conventional_component"),
                    ("missile_macro", "missileturret", "missile_component"),
                ),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(
                    ("PathPart", "Selected", 2, 0, 0, 0, 0),
                    key_data=(
                        _candidate_key_record(tuple(conventional_first))
                        + _candidate_key_record(tuple(conventional_second))
                    ),
                )
            )
            (roots["base"] / "geometry/component_b.ANI").write_bytes(
                _ani_bytes(
                    ("MissilePart", "Selected", 0, 1, 0, 0, 0),
                    key_data=_candidate_key_record(tuple(missile_values)),
                )
            )
            inventory = build_census(roots)["ani_key_record_field_inventory"]

        layout = inventory["candidate_slot_layout"]
        self.assertEqual(layout["evidence_classification"], "third-party-technique")
        self.assertEqual(layout["record_size_bytes"], 128)
        self.assertEqual(layout["covered_byte_range"], {"start": 0, "end_exclusive": 128})
        self.assertEqual(layout["unaccounted_bytes"], [])
        self.assertEqual(layout["overlapping_bytes"], [])
        self.assertNotIn("time", render_json(inventory).lower())
        self.assertNotIn("interpolation", render_json(inventory).lower())
        self.assertNotIn("tangent", render_json(inventory).lower())
        self.assertNotIn("derivative", render_json(inventory).lower())

        distributions = inventory["candidate_assigned_shipped_value_distributions"]
        self.assertEqual(distributions["evidence_classification"], "inference")
        self.assertEqual(
            distributions["shipped_source_basis"]["evidence_classification"],
            "shipped-source",
        )
        self.assertEqual(
            distributions["candidate_decode_basis"]["evidence_classification"],
            "third-party-technique",
        )
        conventional = distributions["conventional"]
        missile = distributions["missileturret"]
        self.assertEqual(conventional["selected_descriptor_memberships"], 2)
        self.assertEqual(conventional["unique_selected_descriptors"], 1)
        self.assertEqual(conventional["candidate_assigned_key_records"], 2)
        self.assertEqual(missile["selected_descriptor_memberships"], 1)
        self.assertEqual(missile["unique_selected_descriptors"], 1)
        self.assertEqual(missile["candidate_assigned_key_records"], 1)

        conventional_slots = {slot["slot_id"]: slot for slot in conventional["slots"]}
        self.assertEqual(
            conventional_slots["slot_004"],
            {
                "slot_id": "slot_004",
                "byte_offset": 4,
                "width_bytes": 4,
                "candidate_type": "float32_le",
                "value_count": 2,
                "finite_count": 2,
                "non_finite_count": 0,
                "zero_count": 1,
                "nonzero_count": 1,
                "distinct_raw_bit_patterns": 2,
                "constant_raw_bits": None,
            },
        )
        self.assertEqual(
            conventional_slots["slot_012"]["integer_value_distribution"],
            [{"value": 0, "count": 1}, {"value": 7, "count": 1}],
        )
        self.assertEqual(
            conventional_slots["slot_096"]["integer_value_distribution"],
            [{"value": -2, "count": 1}, {"value": 0, "count": 1}],
        )
        self.assertEqual(
            conventional_slots["slot_124"]["integer_value_distribution"],
            [{"value": 0, "count": 1}, {"value": 9, "count": 1}],
        )
        self.assertIn("slot_008", conventional["constant_slots"])
        self.assertIn("slot_008", conventional["reserved_looking_zero_constant_slot_candidates"])
        self.assertEqual(
            conventional["distinct_candidate_typed_structural_anomalies"], []
        )

        missile_slots = {slot["slot_id"]: slot for slot in missile["slots"]}
        self.assertEqual(missile_slots["slot_000"]["finite_count"], 0)
        self.assertEqual(missile_slots["slot_000"]["non_finite_count"], 1)
        self.assertEqual(missile_slots["slot_004"]["non_finite_count"], 1)
        self.assertEqual(
            missile_slots["slot_124"]["integer_value_distribution"],
            [{"value": 0xFFFFFFFF, "count": 1}],
        )
        self.assertEqual(
            missile["distinct_candidate_typed_structural_anomalies"],
            [
                {
                    "code": "candidate_non_finite_float_values",
                    "slot_id": "slot_000",
                    "count": 1,
                    "evidence_classification": "inference",
                },
                {
                    "code": "candidate_non_finite_float_values",
                    "slot_id": "slot_004",
                    "count": 1,
                    "evidence_classification": "inference",
                },
            ],
        )
        self.assertEqual(
            inventory["reserved_looking_classification"],
            {
                "evidence_classification": "inference",
                "criterion": "slot is raw-bit constant and its raw numeric values all compare equal to zero",
                "semantic_claim": "none",
            },
        )

    def test_selected_subname_candidate_channel_inventory_is_exact_case_deduplicated_and_metadata_bounded(self) -> None:
        def record(
            main: tuple[float, float, float],
            enums: tuple[int, int, int],
            slot_024: float,
        ) -> bytes:
            values: list[float | int] = [0] * 32
            values[0:3] = main
            values[3:6] = enums
            values[6] = slot_024
            return _candidate_key_record(tuple(values))

        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_a" class="turret">
                    <source geometry="geometry/conventional_a"/>
                    <connections>
                      <connection name="Root"><animations><animation name="turret_active"/><animation name="Turret_Active"/></animations><parts><part name="ActiveA"/><part name="CaseA"/></parts></connection>
                      <connection name="EndpointA" tags="laser" parent="ActiveA"/>
                      <connection name="EndpointB" tags="laser" parent="ActiveA"/>
                      <connection name="EndpointCase" tags="laser" parent="CaseA"/>
                    </connections>
                  </component>
                  <component name="conventional_b" class="turret">
                    <source geometry="geometry/conventional_b"/>
                    <connections>
                      <connection name="Root"><animations><animation name="turret_active"/></animations><parts><part name="ActiveB"/></parts></connection>
                      <connection name="Endpoint" tags="laser" parent="ActiveB"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/missile"/>
                    <connections>
                      <connection name="Root"><animations><animation name="turret_active"/></animations><parts><part name="MissilePart"/></parts></connection>
                      <connection name="Endpoint" tags="rocket" parent="MissilePart"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("conventional_a_macro", "turret", "conventional_a"),
                    ("conventional_b_macro", "turret", "conventional_b"),
                    ("missile_macro", "missileturret", "missile_component"),
                ),
            )
            (roots["base"] / "geometry/conventional_a.ANI").write_bytes(
                _ani_bytes(
                    ("ActiveA", "turret_active", 2, 1, 0, 0, 0),
                    ("CaseA", "Turret_Active", 0, 0, 2, 0, 0),
                    key_data=(
                        record((1.0, 2.0, 3.0), (1, 2, 3), 1.0)
                        + record((1.0, 2.0, 3.0), (1, 2, 4), 2.0)
                        + record((4.0, 5.0, 6.0), (5, 6, 7), 8.0)
                        + record((0.0, 0.0, 0.0), (8, 9, 10), 3.0)
                        + record((0.0, 1.0, 0.0), (8, 9, 10), 3.0)
                    ),
                )
            )
            (roots["base"] / "geometry/conventional_b.ANI").write_bytes(
                _ani_bytes(
                    ("ActiveB", "turret_active", 0, 0, 2, 0, 0),
                    key_data=(
                        record((7.0, 8.0, 9.0), (11, 12, 13), 4.0)
                        + record((8.0, 8.0, 9.0), (11, 12, 13), 2.0)
                    ),
                )
            )
            (roots["base"] / "geometry/missile.ANI").write_bytes(
                _ani_bytes(
                    ("MissilePart", "turret_active", 0, 0, 0, 0, 1),
                    key_data=record((9.0, 9.0, 9.0), (14, 15, 16), 5.0),
                )
            )
            inventory = build_census(roots)[
                "selected_descriptor_subname_candidate_channel_inventory"
            ]

        self.assertEqual(inventory["evidence_classification"], "inference")
        self.assertEqual(
            inventory["raw_subname_counts_and_bits_evidence_classification"],
            "shipped-source",
        )
        self.assertEqual(
            inventory["candidate_channel_ownership_and_layout_evidence_classification"],
            "third-party-technique",
        )
        conventional = inventory["conventional"]
        missile = inventory["missileturret_accounting"]
        self.assertEqual(conventional["selected_endpoint_memberships"], 4)
        self.assertEqual(conventional["unique_descriptor_count"], 3)
        self.assertEqual(missile["selected_endpoint_memberships"], 1)
        self.assertTrue(missile["non_decision_driving"])

        by_subname = {entry["subname"]: entry for entry in conventional["subnames"]}
        self.assertEqual(list(by_subname), ["Turret_Active", "turret_active"])
        exact = by_subname["turret_active"]
        self.assertEqual(exact["selected_endpoint_memberships"], 3)
        self.assertEqual(exact["unique_descriptor_count"], 2)
        self.assertEqual(exact["unique_component_count"], 2)
        self.assertEqual(exact["components"], ["conventional_a", "conventional_b"])
        self.assertEqual(exact["unique_source_connection_count"], 2)
        self.assertEqual(
            exact["source_connections"],
            [
                {"component": "conventional_a", "source_connection": "Root"},
                {"component": "conventional_b", "source_connection": "Root"},
            ],
        )
        self.assertEqual(
            exact["channel_count_families"],
            [
                {
                    "candidate_channel_key_counts": [0, 0, 2, 0, 0],
                    "unique_descriptor_count": 1,
                    "selected_endpoint_memberships": 1,
                },
                {
                    "candidate_channel_key_counts": [2, 1, 0, 0, 0],
                    "unique_descriptor_count": 1,
                    "selected_endpoint_memberships": 2,
                },
            ],
        )
        channels = {
            channel["candidate_channel_id"]: channel
            for channel in exact["candidate_channels"]
        }
        self.assertEqual(
            channels["candidate_channel_0"]["classifications"],
            {
                "zero_keys": {"descriptor_count": 1, "key_record_count": 0},
                "one_key": {"descriptor_count": 0, "key_record_count": 0},
                "multiple_keys_identical_raw_bit_triples": {
                    "descriptor_count": 1,
                    "key_record_count": 2,
                },
                "multiple_keys_changing_raw_bit_triples": {
                    "descriptor_count": 0,
                    "key_record_count": 0,
                },
            },
        )
        self.assertEqual(
            channels["candidate_channel_0"]["multi_key_main_triple_masks"],
            [
                {
                    "changing_mask_slots_000_004_008": "000",
                    "descriptor_count": 1,
                    "key_record_count": 2,
                }
            ],
        )
        self.assertEqual(
            channels["candidate_channel_2"]["multi_key_main_triple_masks"],
            [
                {
                    "changing_mask_slots_000_004_008": "100",
                    "descriptor_count": 1,
                    "key_record_count": 2,
                }
            ],
        )
        self.assertEqual(
            channels["candidate_channel_0"]["observed_candidate_metadata"][
                "slot_024_ordering_shapes"
            ],
            {
                "all_equal": {"descriptor_count": 0, "key_record_count": 0},
                "strictly_increasing": {"descriptor_count": 1, "key_record_count": 2},
                "nondecreasing": {"descriptor_count": 0, "key_record_count": 0},
                "other": {"descriptor_count": 0, "key_record_count": 0},
            },
        )
        self.assertEqual(
            channels["candidate_channel_1"]["observed_candidate_metadata"][
                "candidate_enum_triplet_distribution"
            ],
            [
                {
                    "raw_bits": ["0x00000005", "0x00000006", "0x00000007"],
                    "candidate_values": [5, 6, 7],
                    "record_count": 1,
                }
            ],
        )
        self.assertEqual(by_subname["Turret_Active"]["unique_descriptor_count"], 1)
        self.assertEqual(
            by_subname["Turret_Active"]["candidate_channels"][2][
                "multi_key_main_triple_masks"
            ][0]["changing_mask_slots_000_004_008"],
            "010",
        )

        focused = inventory["focused_literal_turret_active"]
        self.assertTrue(focused["present"])
        self.assertEqual(
            focused["present_candidate_channels"],
            ["candidate_channel_0", "candidate_channel_1", "candidate_channel_2"],
        )
        self.assertEqual(
            focused["absent_candidate_channels"],
            ["candidate_channel_3", "candidate_channel_4"],
        )
        self.assertEqual(
            focused["absent_metadata_forms"][
                "candidate_channels_without_enum_triplet_values"
            ],
            ["candidate_channel_3", "candidate_channel_4"],
        )
        self.assertEqual(
            focused["absent_metadata_forms"][
                "candidate_channels_without_slot_024_values"
            ],
            ["candidate_channel_3", "candidate_channel_4"],
        )
        channel_2_absence = next(
            entry
            for entry in focused["absent_metadata_forms"][
                "by_present_candidate_channel"
            ]
            if entry["candidate_channel_id"] == "candidate_channel_2"
        )
        self.assertEqual(
            channel_2_absence["absent_multi_key_classifications"],
            ["multiple_keys_identical_raw_bit_triples"],
        )
        self.assertEqual(focused["literal_token_semantic_claim"], "none")
        rendered_inventory = render_json(inventory).lower()
        for unsupported_name in (
            "position",
            "rotation",
            "scale",
            "axis",
            "interpolation",
            "timing",
            "pivot",
            "transform",
        ):
            self.assertNotIn(unsupported_name, rendered_inventory)

    def test_paranid_l_beam_live_anchor_fails_closed_on_every_provenance_break(self) -> None:
        def record(vector: tuple[float, float, float], slot_024: float) -> bytes:
            values: list[float | int] = [0] * 32
            values[0:3] = vector
            values[3:6] = [1, 1, 1]
            values[6] = slot_024
            return _candidate_key_record(tuple(values))

        production_formula = {
            "production_sha": "synthetic-production-sha",
            "downstream_vector": [20.0, 52.0, 64.0],
            "yaw_origin_expression_terms": [
                [1.0, 2.0, 3.0],
                [0.0, 20.0, 0.0],
            ],
            "pivot_vector": [4.0, 5.0, 6.0],
            "runtime_inputs": ["target_bearing_yaw", "target_bearing_pitch"],
            "operation_sequence": [
                "weapon_local_look_at_target_useaimtarget_true",
                "md_create_rotation_pitch_equals_runtime_bearing_pitch",
                "md_transform_downstream_vector_by_pitch_rotation",
                "add_pivot_vector",
                "md_create_rotation_yaw_equals_runtime_bearing_yaw",
                "md_transform_pivoted_vector_by_yaw_rotation",
                "add_yaw_origin",
            ],
            "untraced_constants": [],
        }
        trace_spec = {
            "endpoint_connection": "con_laser_02",
            "root_connection": "Connection01",
            "pivot_connection": "Connection04",
            "barrel_connection": "Connection05",
            "laser_connection": "con_laser_02",
            "rotator_active_descriptor": {
                "descriptor_index": 1,
                "part": "part_rotator",
                "subname": "turret_active",
                "candidate_channel_index": 0,
                "triple_slot_indexes": [0, 1, 2],
            },
            "barrel_active_descriptor": {
                "descriptor_index": 3,
                "part": "anim_barrel",
                "subname": "turret_active",
                "candidate_channel_index": 0,
                "triple_slot_indexes": [0, 1, 2],
            },
        }

        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="turret_par_l_beam_01_mk1" class="turret">
                    <source geometry="geometry/beam"/>
                    <connections>
                      <connection name="Connection01"><offset><position x="1" y="2" z="3"/></offset><animations><animation name="turret_active"/></animations><parts><part name="part_socket"/></parts></connection>
                      <connection name="Connection03" parent="part_socket"><parts><part name="part_rotator"/></parts></connection>
                      <connection name="Connection04" parent="part_rotator"><offset><position x="4" y="5" z="6"/><quaternion qx="0" qy="0" qz="0" qw="1"/></offset><parts><part name="anim_gun"/></parts></connection>
                      <connection name="Connection05" parent="anim_gun"><offset><position x="7" y="8" z="9"/><quaternion qx="0" qy="0" qz="0" qw="1"/></offset><parts><part name="anim_barrel"/></parts></connection>
                      <connection name="con_laser_01" tags="laser" parent="anim_barrel"><offset><position x="10" y="11" z="12"/></offset></connection>
                      <connection name="con_laser_02" tags="laser" parent="anim_barrel"><offset><position x="13" y="14" z="15"/></offset></connection>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    (
                        "turret_par_l_beam_01_mk1_macro",
                        "turret",
                        "turret_par_l_beam_01_mk1",
                    ),
                ),
            )
            (roots["base"] / "geometry/beam.ANI").write_bytes(
                _ani_bytes(
                    ("part_socket", "turret_active", 0, 0, 0, 0, 0),
                    ("part_rotator", "turret_active", 2, 0, 0, 0, 0),
                    ("anim_gun", "turret_active", 0, 0, 0, 0, 0),
                    ("anim_barrel", "turret_active", 2, 0, 0, 0, 0),
                    key_data=(
                        record((0.0, 20.0, 0.0), 0.0)
                        + record((0.0, 20.0, 0.0), 1.0)
                        + record((0.0, 30.0, 40.0), 0.0)
                        + record((0.0, 30.0, 40.0), 1.0)
                    ),
                )
            )
            census = _build_census(
                roots,
                roots,
                anchor_production_formula=production_formula,
                anchor_trace_spec=trace_spec,
            )

        anchor = census["paranid_l_beam_accepted_live_anchor"]
        source_trace_bundle = anchor["source_trace_bundle"]
        self.assertEqual(anchor["status"], "pass")
        self.assertEqual(anchor["failures"], [])
        self.assertEqual(
            anchor["identity_chain"]["root_to_endpoint_connection_path"],
            [
                "Connection01",
                "Connection03",
                "Connection04",
                "Connection05",
                "con_laser_02",
            ],
        )
        self.assertEqual(
            len(anchor["endpoint_descriptor_inventory"]),
            4,
        )
        self.assertEqual(
            [
                descriptor["descriptor_index"]
                for descriptor in anchor["selector_selected_descriptor_inventory"]
            ],
            [0],
        )
        rotator = next(
            descriptor
            for descriptor in anchor["literal_turret_active_descriptors"]
            if descriptor["descriptor_index"] == 1
        )
        self.assertEqual(rotator["candidate_channel_counts"], [2, 0, 0, 0, 0])
        relationships = anchor["same_subname_structural_relationship_coverage"]
        self.assertEqual(
            relationships["exact_matching_selector_connections"], ["Connection01"]
        )
        self.assertEqual(
            [
                (
                    descriptor["descriptor_index"],
                    descriptor["source_connection"],
                    descriptor["root_to_source_connection_path"],
                    descriptor["strict_ancestor_selector_distances"],
                )
                for descriptor in relationships["descriptor_relationships"]
            ],
            [
                (1, "Connection03", ["Connection01", "Connection03"], [1]),
                (
                    3,
                    "Connection05",
                    ["Connection01", "Connection03", "Connection04", "Connection05"],
                    [3],
                ),
            ],
        )
        self.assertEqual(
            rotator["candidate_channels"][0]["records"][0]["raw_bits"][1],
            "0x41a00000",
        )
        self.assertEqual(
            len(rotator["candidate_channels"][0]["records"][0]["raw_bits"]),
            32,
        )
        self.assertEqual(
            anchor["endpoint_resolution"][
                "production_matching_endpoint_connections"
            ],
            ["con_laser_02"],
        )
        self.assertTrue(anchor["endpoint_resolution"]["exact_unique_match"])
        self.assertEqual(
            anchor["literal_turret_active_candidate_channel_contributions"],
            {
                "contributing": ["candidate_channel_0"],
                "not_contributing": [
                    "candidate_channel_1",
                    "candidate_channel_2",
                    "candidate_channel_3",
                    "candidate_channel_4",
                ],
            },
        )
        self.assertTrue(
            all(
                row["trace_status"] != "UNTRACED"
                for row in anchor["formula_constant_provenance"]
            )
        )

        altered_formula = copy.deepcopy(production_formula)
        altered_formula["downstream_vector"][0] = 21.0
        altered = _evaluate_paranid_l_beam_trace(
            source_trace_bundle,
            production_formula=altered_formula,
            trace_spec=trace_spec,
        )
        self.assertIn("formula_numeric_mismatch", altered["failure_codes"])

        wrong_descriptor = copy.deepcopy(trace_spec)
        wrong_descriptor["barrel_active_descriptor"]["descriptor_index"] = 2
        descriptor_failure = _evaluate_paranid_l_beam_trace(
            source_trace_bundle,
            production_formula=production_formula,
            trace_spec=wrong_descriptor,
        )
        self.assertIn("ani_trace_unresolved", descriptor_failure["failure_codes"])

        wrong_connection = copy.deepcopy(trace_spec)
        wrong_connection["laser_connection"] = "con_laser_01"
        connection_failure = _evaluate_paranid_l_beam_trace(
            source_trace_bundle,
            production_formula=production_formula,
            trace_spec=wrong_connection,
        )
        self.assertIn("formula_numeric_mismatch", connection_failure["failure_codes"])

        wrong_slot = copy.deepcopy(trace_spec)
        wrong_slot["barrel_active_descriptor"]["triple_slot_indexes"] = [0, 2, 1]
        slot_failure = _evaluate_paranid_l_beam_trace(
            source_trace_bundle,
            production_formula=production_formula,
            trace_spec=wrong_slot,
        )
        self.assertIn("formula_numeric_mismatch", slot_failure["failure_codes"])

        untraced_formula = copy.deepcopy(production_formula)
        untraced_formula["untraced_constants"] = [99.0]
        untraced = _evaluate_paranid_l_beam_trace(
            source_trace_bundle,
            production_formula=untraced_formula,
            trace_spec=trace_spec,
        )
        self.assertIn("untraced_production_constant", untraced["failure_codes"])
        self.assertTrue(
            any(
                row["trace_status"] == "UNTRACED"
                for row in untraced["formula_constant_provenance"]
            )
        )

    def test_candidate_channel_dynamics_are_deduplicated_separate_and_raw_bit_exact(self) -> None:
        def record(
            first: float, second: float, third: float, later_slot: int = 0
        ) -> bytes:
            values: list[float | int] = [0] * 32
            values[0:4] = [first, second, third, later_slot]
            return _candidate_key_record(tuple(values))

        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/conventional"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="ConventionalPart"/></parts></connection>
                      <connection name="EndpointA" tags="laser" parent="ConventionalPart"/>
                      <connection name="EndpointB" tags="laser" parent="ConventionalPart"/>
                    </connections>
                  </component>
                  <component name="conventional_component_b" class="turret">
                    <source geometry="geometry/conventional_b"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="ConventionalPartB"/></parts></connection>
                      <connection name="Endpoint" tags="laser" parent="ConventionalPartB"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/missile"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="MissilePart"/></parts></connection>
                      <connection name="Endpoint" tags="rocket" parent="MissilePart"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("conventional_macro", "turret", "conventional_component"),
                    ("conventional_macro_b", "turret", "conventional_component_b"),
                    ("missile_macro", "missileturret", "missile_component"),
                ),
            )
            (roots["base"] / "geometry/conventional.ANI").write_bytes(
                _ani_bytes(
                    ("ConventionalPart", "Selected", 0, 1, 2, 2, 0),
                    key_data=(
                        record(9.0, 8.0, 7.0)
                        + record(1.0, 2.0, 3.0, 1)
                        + record(1.0, 2.0, 3.0, 2)
                        + record(+0.0, 4.0, 5.0)
                        + record(-0.0, 4.0, 5.0)
                    ),
                )
            )
            (roots["base"] / "geometry/conventional_b.ANI").write_bytes(
                _ani_bytes(("ConventionalPartB", "Selected", 0, 0, 0, 0, 0))
            )
            (roots["base"] / "geometry/missile.ANI").write_bytes(
                _ani_bytes(
                    ("MissilePart", "Selected", 1, 0, 0, 0, 0),
                    key_data=record(6.0, 5.0, 4.0),
                )
            )
            dynamics = build_census(roots)[
                "selected_descriptor_candidate_channel_dynamics"
            ]

        self.assertEqual(dynamics["evidence_classification"], "inference")
        self.assertEqual(
            dynamics["candidate_channel_ownership_order"][
                "evidence_classification"
            ],
            "third-party-technique",
        )
        conventional = dynamics["conventional"]
        missile = dynamics["missileturret"]
        self.assertEqual(conventional["selected_descriptor_memberships"], 3)
        self.assertEqual(conventional["unique_selected_descriptors"], 2)
        self.assertEqual(conventional["candidate_assigned_key_records"], 5)
        self.assertEqual(missile["selected_descriptor_memberships"], 1)
        self.assertEqual(missile["unique_selected_descriptors"], 1)
        self.assertEqual(missile["candidate_assigned_key_records"], 1)

        zero = {"descriptor_count": 0, "key_record_count": 0}
        self.assertEqual(
            conventional["candidate_channels"],
            [
                {
                    "candidate_channel_id": "candidate_channel_0",
                    "candidate_channel_count_field_index": 0,
                    "classifications": {
                        "zero_keys": {"descriptor_count": 2, "key_record_count": 0},
                        "one_key": zero,
                        "multiple_keys_identical_raw_bit_triples": zero,
                        "multiple_keys_changing_raw_bit_triples": zero,
                    },
                },
                {
                    "candidate_channel_id": "candidate_channel_1",
                    "candidate_channel_count_field_index": 1,
                    "classifications": {
                        "zero_keys": {"descriptor_count": 1, "key_record_count": 0},
                        "one_key": {"descriptor_count": 1, "key_record_count": 1},
                        "multiple_keys_identical_raw_bit_triples": zero,
                        "multiple_keys_changing_raw_bit_triples": zero,
                    },
                },
                {
                    "candidate_channel_id": "candidate_channel_2",
                    "candidate_channel_count_field_index": 2,
                    "classifications": {
                        "zero_keys": {"descriptor_count": 1, "key_record_count": 0},
                        "one_key": zero,
                        "multiple_keys_identical_raw_bit_triples": {
                            "descriptor_count": 1,
                            "key_record_count": 2,
                        },
                        "multiple_keys_changing_raw_bit_triples": zero,
                    },
                },
                {
                    "candidate_channel_id": "candidate_channel_3",
                    "candidate_channel_count_field_index": 3,
                    "classifications": {
                        "zero_keys": {"descriptor_count": 1, "key_record_count": 0},
                        "one_key": zero,
                        "multiple_keys_identical_raw_bit_triples": zero,
                        "multiple_keys_changing_raw_bit_triples": {
                            "descriptor_count": 1,
                            "key_record_count": 2,
                        },
                    },
                },
                {
                    "candidate_channel_id": "candidate_channel_4",
                    "candidate_channel_count_field_index": 4,
                    "classifications": {
                        "zero_keys": {"descriptor_count": 2, "key_record_count": 0},
                        "one_key": zero,
                        "multiple_keys_identical_raw_bit_triples": zero,
                        "multiple_keys_changing_raw_bit_triples": zero,
                    },
                },
            ],
        )
        self.assertEqual(
            missile["candidate_channels"][0]["classifications"],
            {
                "zero_keys": zero,
                "one_key": {"descriptor_count": 1, "key_record_count": 1},
                "multiple_keys_identical_raw_bit_triples": zero,
                "multiple_keys_changing_raw_bit_triples": zero,
            },
        )
        for candidate_channel in missile["candidate_channels"][1:]:
            self.assertEqual(
                candidate_channel["classifications"]["zero_keys"],
                {"descriptor_count": 1, "key_record_count": 0},
            )
        rendered_dynamics = render_json(dynamics).lower()
        for unsupported_name in (
            "time",
            "interpolation",
            "transform",
            "position",
            "rotation",
            "scale",
            "pre_scale",
            "post_scale",
        ):
            self.assertNotIn(unsupported_name, rendered_dynamics)

    def test_conventional_multi_key_candidate_metadata_patterns_are_raw_and_separate(self) -> None:
        def record(
            main: tuple[float, float, float],
            enums: tuple[int, int, int],
            slot_024: float,
            later: dict[int, float | int] | None = None,
        ) -> bytes:
            values: list[float | int] = [0] * 32
            values[0:3] = main
            values[3:6] = enums
            values[6] = slot_024
            for slot_index, value in (later or {}).items():
                values[slot_index] = value
            return _candidate_key_record(tuple(values))

        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/conventional"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="ConventionalPart"/></parts></connection>
                      <connection name="EndpointA" tags="laser" parent="ConventionalPart"/>
                      <connection name="EndpointB" tags="laser" parent="ConventionalPart"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/missile"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="MissilePart"/></parts></connection>
                      <connection name="Endpoint" tags="rocket" parent="MissilePart"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("conventional_macro", "turret", "conventional_component"),
                    ("missile_macro", "missileturret", "missile_component"),
                ),
            )
            (roots["base"] / "geometry/conventional.ANI").write_bytes(
                _ani_bytes(
                    ("ConventionalPart", "Selected", 2, 2, 3, 0, 0),
                    key_data=(
                        record((1.0, 2.0, 3.0), (1, 2, 3), 1.0)
                        + record(
                            (1.0, 2.0, 3.0),
                            (1, 2, 4),
                            2.0,
                            {7: 9.0, 19: 5.0},
                        )
                        + record(
                            (0.0, 0.0, 0.0),
                            (5, 6, 7),
                            3.0,
                            {7: 4.0, 19: 8.0},
                        )
                        + record(
                            (1.0, 0.0, 0.0),
                            (5, 6, 7),
                            3.0,
                            {7: 4.0, 19: 8.0},
                        )
                        + record((7.0, 8.0, 9.0), (-1, 0, 1), 2.0)
                        + record((7.0, 8.0, 9.0), (-1, 0, 1), 1.0)
                        + record((7.0, 8.0, 9.0), (-1, 0, 1), 3.0)
                    ),
                )
            )
            (roots["base"] / "geometry/missile.ANI").write_bytes(
                _ani_bytes(
                    ("MissilePart", "Selected", 2, 0, 0, 0, 0),
                    key_data=(
                        record((4.0, 5.0, 6.0), (8, 9, 10), 4.0)
                        + record((4.0, 5.0, 6.0), (8, 9, 10), 5.0)
                    ),
                )
            )
            inventory = build_census(roots)[
                "selected_conventional_candidate_channel_metadata_patterns"
            ]

        self.assertEqual(inventory["evidence_classification"], "inference")
        self.assertEqual(
            inventory["candidate_field_layout"]["evidence_classification"],
            "third-party-technique",
        )
        conventional = inventory["conventional"]
        missile = inventory["missileturret_accounting"]
        self.assertEqual(conventional["selected_descriptor_memberships"], 2)
        self.assertEqual(conventional["unique_selected_descriptors"], 1)
        self.assertEqual(missile["selected_descriptor_memberships"], 1)
        self.assertEqual(missile["unique_selected_descriptors"], 1)

        channels = {
            channel["candidate_channel_id"]: channel
            for channel in conventional["candidate_channels"]
        }
        channel_0 = channels["candidate_channel_0"]["multiple_key_descriptors"][
            "identical_raw_bit_triples"
        ]
        self.assertEqual(channel_0["descriptor_count"], 1)
        self.assertEqual(channel_0["key_record_count"], 2)
        self.assertEqual(
            channel_0["candidate_enum_triplet_distribution"],
            [
                {
                    "raw_bits": ["0x00000001", "0x00000002", "0x00000003"],
                    "candidate_values": [1, 2, 3],
                    "record_count": 1,
                },
                {
                    "raw_bits": ["0x00000001", "0x00000002", "0x00000004"],
                    "candidate_values": [1, 2, 4],
                    "record_count": 1,
                },
            ],
        )
        self.assertEqual(
            channel_0["slot_024"]["descriptor_numeric_ordering_shapes"],
            {
                "all_equal": {"descriptor_count": 0, "key_record_count": 0},
                "strictly_increasing": {
                    "descriptor_count": 1,
                    "key_record_count": 2,
                },
                "nondecreasing": {"descriptor_count": 0, "key_record_count": 0},
                "other": {"descriptor_count": 0, "key_record_count": 0},
            },
        )
        slot_028 = channel_0["slots_028_072"][0]
        self.assertEqual(slot_028["raw_bit_zero_count"], 1)
        self.assertEqual(slot_028["raw_bit_nonzero_count"], 1)
        self.assertEqual(slot_028["distinct_raw_bit_pattern_count"], 2)
        self.assertEqual(slot_028["descriptors_with_differing_raw_bits"], 1)
        slot_076 = channel_0["slots_076_124"][0]
        self.assertEqual(slot_076["raw_bit_zero_count"], 1)
        self.assertEqual(slot_076["raw_bit_nonzero_count"], 1)
        self.assertEqual(slot_076["descriptors_with_differing_raw_bits"], 1)

        channel_1 = channels["candidate_channel_1"]["multiple_key_descriptors"][
            "changing_raw_bit_triples"
        ]
        self.assertEqual(channel_1["descriptor_count"], 1)
        self.assertEqual(
            channel_1["slot_024"]["descriptor_numeric_ordering_shapes"][
                "all_equal"
            ],
            {"descriptor_count": 1, "key_record_count": 2},
        )
        self.assertEqual(
            channel_1["slots_028_072"][0]["descriptors_with_constant_raw_bits"],
            1,
        )
        self.assertEqual(
            channel_1["slots_076_124"][0]["descriptors_with_constant_raw_bits"],
            1,
        )

        channel_2 = channels["candidate_channel_2"]["multiple_key_descriptors"][
            "identical_raw_bit_triples"
        ]
        self.assertEqual(
            channel_2["slot_024"]["descriptor_numeric_ordering_shapes"]["other"],
            {"descriptor_count": 1, "key_record_count": 3},
        )
        missile_channel_0 = missile["candidate_channels"][0]
        self.assertEqual(
            missile_channel_0["multiple_key_descriptors"],
            {
                "identical_raw_bit_triples": {
                    "descriptor_count": 1,
                    "key_record_count": 2,
                },
                "changing_raw_bit_triples": {
                    "descriptor_count": 0,
                    "key_record_count": 0,
                },
            },
        )
        rendered_inventory = render_json(inventory).lower()
        for unsupported_name in (
            "time",
            "interpolation",
            "control_point",
            "tangent",
            "derivative",
            "position",
            "rotation",
            "scale",
        ):
            self.assertNotIn(unsupported_name, rendered_inventory)

    def test_x4converter_semantic_lead_is_complete_and_requires_corroboration(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            lead = build_census(_source_roots(Path(tmp)))[
                "x4converter_candidate_key_record_semantic_lead"
            ]

        self.assertEqual(lead["evidence_classification"], "third-party-technique")
        self.assertEqual(
            lead["source_revision"]["commit"],
            "0be4b494089ba7719d4c5d351e63160ef3843ef5",
        )
        self.assertEqual(lead["record_size_bytes"], 128)
        self.assertEqual(lead["decision_driving_component_class"], "conventional")
        self.assertEqual(lead["missileturret_semantic_analysis"], "excluded")

        fields = lead["field_map"]
        self.assertEqual([field["byte_offset"] for field in fields], list(range(0, 128, 4)))
        self.assertEqual(
            [field["x4converter_member"] for field in fields],
            [
                "ValueX", "ValueY", "ValueZ",
                "InterpolationX", "InterpolationY", "InterpolationZ",
                "Time",
                "CPX1x", "CPX1y", "CPX2x", "CPX2y",
                "CPY1x", "CPY1y", "CPY2x", "CPY2y",
                "CPZ1x", "CPZ1y", "CPZ2x", "CPZ2y",
                "Tens", "Cont", "Bias", "EaseIn", "EaseOut",
                "Deriv",
                "DerivInX", "DerivInY", "DerivInZ",
                "DerivOutX", "DerivOutY", "DerivOutZ",
                "AngleKey",
            ],
        )
        self.assertEqual(
            [group["group_id"] for group in lead["record_field_groups"]],
            [
                "candidate_vector",
                "per_axis_mode",
                "record_order_scalar",
                "control_parameters",
                "curve_parameters",
                "flags",
                "derived_vectors",
                "unused_or_reserved",
            ],
        )
        for field in fields:
            self.assertEqual(field["evidence_classification"], "third-party-technique")
            self.assertTrue(field["independent_corroboration_required"])
            self.assertTrue(field["x4converter_read_site"]["expression"])
            self.assertTrue(field["x4converter_use_sites"])

        self.assertEqual(
            [
                (
                    group["candidate_channel_count_field_index"],
                    group["x4converter_count_member"],
                    group["x4converter_record_vector_member"],
                    group["intermediate_output_label"],
                )
                for group in lead["candidate_channel_grouping"]
            ],
            [
                (0, "NumPosKeys", "posKeys", "location"),
                (1, "NumRotKeys", "rotKeys", "rotation_euler"),
                (2, "NumScaleKeys", "scaleKeys", "scale"),
                (3, "NumPreScaleKeys", "preScaleKeys", None),
                (4, "NumPostScaleKeys", "postScaleKeys", None),
            ],
        )
        self.assertEqual(
            lead["x4converter_control_parameter_routing"]["routes"],
            [
                {
                    "right_argument": False,
                    "output_node": "handle_right",
                    "selected_member_suffix": "1",
                },
                {
                    "right_argument": True,
                    "output_node": "handle_left",
                    "selected_member_suffix": "2",
                },
            ],
        )

        enum_mapping = {
            mapping["raw_value"]: mapping for mapping in lead["observed_enum_mapping"]
        }
        self.assertEqual(
            {value: mapping["x4converter_identifier"] for value, mapping in enum_mapping.items()},
            {
                1: "INTERPOLATION_STEP",
                2: "INTERPOLATION_LINEAR",
                5: "INTERPOLATION_BEZIER",
            },
        )
        self.assertIn("Keyframe::checkInterpolationType", enum_mapping[1]["branch_sites"][0]["function"])
        self.assertTrue(
            any(
                "InterpolationX == 2" in site["expression"]
                for site in enum_mapping[2]["branch_sites"]
            )
        )
        self.assertIn("Keyframe::checkInterpolationType", enum_mapping[5]["branch_sites"][0]["function"])

        matrix = lead["independent_corroboration_required"]
        self.assertEqual(
            {row["current_observation_assessment"] for row in matrix},
            {"merely_consistent", "no_semantic_evidence"},
        )
        self.assertTrue(all(row["required"] for row in matrix))
        self.assertIn(
            "record_order_scalar_identity",
            {row["candidate_semantic"] for row in matrix},
        )
        self.assertIn(
            "zero_tail_member_identities",
            {row["candidate_semantic"] for row in matrix},
        )

        string_values: list[str] = []
        evidence_labels: list[str] = []
        pending: list[object] = [lead]
        while pending:
            value = pending.pop()
            if isinstance(value, dict):
                if "evidence_classification" in value:
                    evidence_labels.append(str(value["evidence_classification"]))
                pending.extend(value.values())
            elif isinstance(value, list):
                pending.extend(value)
            elif isinstance(value, str):
                string_values.append(value.lower())
        self.assertEqual(set(evidence_labels), {"third-party-technique"})
        self.assertNotIn("shipped-source", string_values)
        self.assertNotIn("live-tested", string_values)
        self.assertFalse(any(value in {"final", "resolved"} for value in string_values))

    def test_ani_key_section_wrong_width_truncation_and_extra_bytes_fail_closed(self) -> None:
        cases = (
            (
                "truncated_record",
                _ani_bytes(("Part", "Sub", 1, 0, 0, 0, 0), key_data=b"x" * 127),
                "truncated_ani_key_section",
            ),
            (
                "impossible_count",
                _ani_bytes(("Part", "Sub", 0xFFFFFFFF, 0, 0, 0, 0), key_data=b""),
                "truncated_ani_key_section",
            ),
            (
                "unconsumed_byte",
                _ani_bytes(("Part", "Sub"), key_data=b"x"),
                "unconsumed_ani_key_section",
            ),
        )
        for label, data, code in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "invalid.ANI"
                path.write_bytes(data)
                with self.assertRaises(AniDescriptorError) as caught:
                    _parse_ani_descriptors(path)
                self.assertEqual(caught.exception.code, code)

    def test_framing_evidence_boundary_separates_shipped_source_from_order_inference(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/component_a"/>
                    <connections>
                      <connection name="Root">
                        <animations><animation name="Selector"/></animations>
                        <parts><part name="RootPart"/></parts>
                      </connection>
                      <connection name="Endpoint" tags="laser" parent="RootPart"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("conventional_macro", "turret", "conventional_component")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(("RootPart", "Selector", 1, 2, 0, 0, 0))
            )

            framing = build_census(roots)["ani_key_data_framing"]

            # Structural facts a file-size invariant can actually prove.
            structural = framing["structural_framing"]
            self.assertEqual(structural["evidence_classification"], "shipped-source")
            self.assertEqual(structural["record_size_bytes"], 128)
            self.assertEqual(
                structural["key_section_termination"], "exactly at end of file"
            )
            # The shipped invariant must not claim to prove byte ordering.
            self.assertEqual(
                structural["does_not_discriminate"],
                ["descriptor_order", "channel_order"],
            )
            self.assertNotIn("descriptor_order", structural)
            self.assertNotIn("channel_order", structural)

            # Ordering is inference only; it never carries a shipped-source label.
            ownership = framing["key_ownership_order"]
            self.assertEqual(
                ownership["evidence_classification"], "third-party-technique"
            )
            self.assertEqual(ownership["descriptor_order"], "descriptor table index order")
            self.assertEqual(
                ownership["channel_order"],
                ["position", "rotation", "scale", "pre_scale", "post_scale"],
            )

    def test_file_size_invariant_is_blind_to_key_order(self) -> None:
        # Two ANIs with the same total key-record count but different descriptor
        # and channel orderings occupy identical file sizes and both satisfy the
        # structural parser. That is exactly why the invariant cannot corroborate
        # order: it is a sum, and a sum does not see permutation.
        with tempfile.TemporaryDirectory() as tmp:
            first = Path(tmp) / "first.ANI"
            second = Path(tmp) / "second.ANI"
            first.write_bytes(
                _ani_bytes(
                    ("Alpha", "One", 3, 0, 0, 0, 0),
                    ("Bravo", "Two", 0, 0, 2, 0, 0),
                )
            )
            second.write_bytes(
                _ani_bytes(
                    ("Bravo", "Two", 0, 0, 0, 0, 2),
                    ("Alpha", "One", 0, 3, 0, 0, 0),
                )
            )
            self.assertEqual(first.stat().st_size, second.stat().st_size)
            # Both parse cleanly; the invariant alone cannot tell them apart.
            self.assertEqual(len(_parse_ani_descriptors(first)), 2)
            self.assertEqual(len(_parse_ani_descriptors(second)), 2)

    def test_selected_descriptor_channel_count_families_are_preserved_and_separated(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/component_a"/>
                    <connections>
                      <connection name="ConventionalRoot">
                        <animations><animation name="RootSelector"/></animations>
                        <parts><part name="RootPart"/></parts>
                      </connection>
                      <connection name="ConventionalChild" parent="RootPart">
                        <animations><animation name="ChildSelector"/></animations>
                        <parts><part name="ChildPart"/></parts>
                      </connection>
                      <connection name="ConventionalEndpointA" tags="laser" parent="ChildPart"/>
                      <connection name="ConventionalEndpointB" tags="laser" parent="ChildPart"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/component_b"/>
                    <connections>
                      <connection name="MissileRoot">
                        <animations><animation name="MissileSelector"/></animations>
                        <parts><part name="MissilePart"/></parts>
                      </connection>
                      <connection name="MissileEndpoint" tags="rocket" parent="MissilePart"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("conventional_macro", "turret", "conventional_component"),
                    ("missile_macro", "missileturret", "missile_component"),
                ),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(
                    ("RootPart", "RootSelector", 3, 4, 0, 0, 0),
                    ("ChildPart", "ChildSelector", 0, 1, 2, 3, 4),
                )
            )
            (roots["base"] / "geometry/component_b.ANI").write_bytes(
                _ani_bytes(("MissilePart", "MissileSelector", 8, 7, 6, 5, 4))
            )

            report = build_census(roots)
            conventional, missile = report["component_to_macros"]
            self.assertEqual(
                [descriptor["channel_counts"] for descriptor in conventional["ani_descriptors"]],
                [
                    {"position": 3, "rotation": 4, "scale": 0, "pre_scale": 0, "post_scale": 0},
                    {"position": 0, "rotation": 1, "scale": 2, "pre_scale": 3, "post_scale": 4},
                ],
            )
            self.assertEqual(
                [
                    descriptor["channel_counts"]
                    for descriptor in conventional["firing_endpoints"][0][
                        "selected_ani_descriptor_memberships"
                    ]
                ],
                [
                    {"position": 3, "rotation": 4, "scale": 0, "pre_scale": 0, "post_scale": 0},
                    {"position": 0, "rotation": 1, "scale": 2, "pre_scale": 3, "post_scale": 4},
                ],
            )
            self.assertEqual(
                missile["firing_endpoints"][0]["selected_ani_descriptor_memberships"][0][
                    "channel_counts"
                ],
                {"position": 8, "rotation": 7, "scale": 6, "pre_scale": 5, "post_scale": 4},
            )
            self.assertEqual(
                [descriptor["descriptor_index"] for descriptor in conventional["ani_descriptors"]],
                [0, 1],
            )
            self.assertEqual(
                conventional["firing_endpoints"][0]["selected_ani_descriptor_memberships"][0][
                    "key_data"
                ],
                conventional["ani_descriptors"][0]["key_data"],
            )
            self.assertEqual(
                report["selected_endpoint_path_descriptor_key_data_accounting"],
                {
                    "conventional": {
                        "selected_descriptor_memberships": 4,
                        "opaque_key_records": 34,
                        "opaque_key_bytes": 4352,
                    },
                    "missileturret": {
                        "selected_descriptor_memberships": 1,
                        "opaque_key_records": 30,
                        "opaque_key_bytes": 3840,
                    },
                },
            )
            self.assertEqual(
                report["ani_key_data_framing"],
                {
                    "structural_framing": {
                        "evidence_classification": "shipped-source",
                        "x4_version": "9.00",
                        "record_size_bytes": 128,
                        "key_section_termination": "exactly at end of file",
                        "invariant": (
                            "descriptor-table end offset"
                            " + sum(all descriptor channel counts) * record_size_bytes"
                            " == file size"
                        ),
                        "linked_ani_resources": 2,
                        "resources_with_exact_framing": 2,
                        "exceptions": [],
                        "does_not_discriminate": [
                            "descriptor_order",
                            "channel_order",
                        ],
                    },
                    "key_ownership_order": {
                        "evidence_classification": "third-party-technique",
                        "descriptor_order": "descriptor table index order",
                        "channel_order": [
                            "position",
                            "rotation",
                            "scale",
                            "pre_scale",
                            "post_scale",
                        ],
                        "note": (
                            "byte order of descriptor and channel key records is not"
                            " discriminated by the shipped-source structural invariant;"
                            " the parser assigns key-record ranges in this order per the"
                            " third-party lead only"
                        ),
                        "third_party_lead": {
                            "source": "X4Converter 0be4b494089ba7719d4c5d351e63160ef3843ef5 X4ConverterTools/src/ani/AnimFile.cpp, AnimDesc.cpp, and Keyframe.h",
                        },
                    },
                },
            )
            self.assertEqual(
                report["selected_endpoint_path_descriptor_channel_count_families"],
                {
                    "conventional": [
                        {
                            "channel_counts": {
                                "position": 0,
                                "rotation": 1,
                                "scale": 2,
                                "pre_scale": 3,
                                "post_scale": 4,
                            },
                            "selected_descriptor_memberships": 2,
                        },
                        {
                            "channel_counts": {
                                "position": 3,
                                "rotation": 4,
                                "scale": 0,
                                "pre_scale": 0,
                                "post_scale": 0,
                            },
                            "selected_descriptor_memberships": 2,
                        },
                    ],
                    "missileturret": [
                        {
                            "channel_counts": {
                                "position": 8,
                                "rotation": 7,
                                "scale": 6,
                                "pre_scale": 5,
                                "post_scale": 4,
                            },
                            "selected_descriptor_memberships": 1,
                        }
                    ],
                },
            )

    def test_endpoint_path_animation_selector_without_exact_descriptor_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/component_a"/>
                  <connections>
                    <connection name="Root"><animations><animation name="ExactCase"/></animations><parts><part name="PathPart"/></parts></connection>
                    <connection name="Endpoint" tags="laser" parent="PathPart"/>
                  </connections>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(("PathPart", "exactcase"))
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn(
                "unresolved_endpoint_path_animation_selector", caught.exception.codes
            )

    def test_duplicate_authored_animation_selector_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/component_a"/>
                  <connections>
                    <connection name="Root">
                      <animations><animation name="Exact"/><animation name="Exact"/></animations>
                      <parts><part name="PathPart"/></parts>
                    </connection>
                    <connection name="Endpoint" tags="laser" parent="PathPart"/>
                  </connections>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(("PathPart", "Exact"))
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn(
                "duplicate_authored_animation_selector_identity",
                caught.exception.codes,
            )

    def test_malformed_endpoint_edge_ownership_fails_closed(self) -> None:
        endpoints = [{"connection": "Child", "root_to_endpoint_connection_path": ["Root", "Child"]}]
        connections = [
            {"name": "Root", "parent_connection": None, "parent_part": None, "direct_owned_parts": ["Other"]},
            {"name": "Child", "parent_connection": "Root", "parent_part": "Required", "direct_owned_parts": []},
        ]
        resolved, anomalies = _derive_endpoint_source_paths(
            endpoints,
            connections,
            [],
            component="component_a",
            source_set="base",
            source_file="assets/component.xml",
        )
        self.assertEqual(resolved, [])
        self.assertEqual([item["code"] for item in anomalies], ["invalid_endpoint_edge_ownership"])

        resolved, anomalies = _derive_endpoint_source_paths(
            [{"connection": "Missing", "root_to_endpoint_connection_path": ["Root", "Missing"]}],
            connections,
            [],
            component="component_a",
            source_set="base",
            source_file="assets/component.xml",
        )
        self.assertEqual(resolved, [])
        self.assertEqual([item["code"] for item in anomalies], ["unresolvable_endpoint_connection_path"])

        resolved, anomalies = _derive_endpoint_source_paths(
            [],
            connections,
            [
                {
                    "part": "Required",
                    "subname": "ExactSubname",
                    "source_connection": "Root",
                    "root_to_source_connection_path": ["Root"],
                }
            ],
            component="component_a",
            source_set="base",
            source_file="assets/component.xml",
        )
        self.assertEqual(resolved, [])
        self.assertEqual([item["code"] for item in anomalies], ["contradictory_descriptor_path_identity"])

    def test_missing_malformed_or_ambiguous_firing_endpoint_evidence_fails_closed(self) -> None:
        cases = (
            ("missing", "turret", "turret", '<connection name="con_laser_only_by_name"/>', "missing_firing_endpoint_identity"),
            ("duplicate_token", "turret", "turret", '<connection name="Endpoint" tags="laser laser"/>', "malformed_endpoint_evidence"),
            ("both_roles", "turret", "turret", '<connection name="Endpoint" tags="laser rocket"/>', "ambiguous_endpoint_evidence"),
            ("wrong_role", "turret", "turret", '<connection name="Endpoint" tags="rocket"/>', "ambiguous_endpoint_evidence"),
            ("missile_duplicate", "missileturret", "missileturret", '<connection name="Endpoint" tags="rocket rocket"/>', "malformed_endpoint_evidence"),
            ("missile_wrong_role", "missileturret", "missileturret", '<connection name="Endpoint" tags="laser"/>', "ambiguous_endpoint_evidence"),
            ("unsupported_class", "bullet", "turret", '<connection name="Endpoint" tags="laser"/>', "unsupported_endpoint_component_class"),
        )
        for label, component_class, macro_class, connections, code in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                roots = _source_roots(Path(tmp))
                _write(
                    roots["base"],
                    "assets/component.xml",
                    f'<components><component name="component_a" class="{component_class}"><source geometry="geometry/component_a"/><connections>{connections}</connections></component></components>',
                )
                _write(
                    roots["base"],
                    "assets/macros.xml",
                    _macros(("a_macro", macro_class, "component_a")),
                )
                with self.assertRaises(CensusError) as caught:
                    build_census(roots)
                self.assertIn(code, caught.exception.codes)

    def test_invalid_connection_owned_part_and_animation_identities_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/component_a"/>
                  <connections><connection name="">
                    <animations><animation/></animations>
                    <parts><part/></parts>
                  </connection></connections>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("malformed_connection_identity", caught.exception.codes)
            self.assertIn("invalid_source_part_ownership", caught.exception.codes)
            self.assertIn("invalid_authored_connection_animation", caught.exception.codes)

    def test_duplicate_exact_ani_descriptor_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", _components("component_a"))
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(("Part", "Sub"), ("Part", "Sub"))
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("duplicate_ani_descriptor", caught.exception.codes)

    def test_truncated_and_unsupported_ani_fail_closed(self) -> None:
        for label, ani, code in (
            ("truncated_header", b"short", "truncated_ani_header"),
            ("truncated_descriptors", _ani_bytes(("Part", "Sub"))[:-1], "truncated_ani_descriptor_section"),
            ("unsupported_version", _ani_bytes(version=2), "unsupported_ani_layout"),
            ("header_padding", _ani_bytes(header_padding=1), "unsupported_ani_layout"),
            ("key_offset", _ani_bytes(key_offset=17), "unsupported_ani_layout"),
            (
                "descriptor_padding",
                _ani_bytes(("Part", "Sub"), descriptor_padding=(1, 0)),
                "unsupported_ani_layout",
            ),
        ):
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                roots = _source_roots(Path(tmp))
                _write(roots["base"], "assets/components.xml", _components("component_a"))
                _write(
                    roots["base"],
                    "assets/macros.xml",
                    _macros(("a_macro", "turret", "component_a")),
                )
                (roots["base"] / "geometry/component_a.ANI").write_bytes(ani)
                with self.assertRaises(CensusError) as caught:
                    build_census(roots)
                self.assertIn(code, caught.exception.codes)

    def test_invalid_ani_descriptor_strings_fail_closed(self) -> None:
        valid = _ani_bytes(("Part", "Sub"))
        no_terminator = bytearray(valid)
        no_terminator[16:80] = b"A" * 64
        non_ascii = bytearray(valid)
        non_ascii[16] = 0xFF
        non_printable = bytearray(valid)
        non_printable[16] = 0x01
        for label, ani in (
            ("empty", _ani_bytes(("", "Sub"))),
            ("unterminated", bytes(no_terminator)),
            ("non_ascii", bytes(non_ascii)),
            ("non_printable", bytes(non_printable)),
        ):
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                roots = _source_roots(Path(tmp))
                _write(roots["base"], "assets/components.xml", _components("component_a"))
                _write(
                    roots["base"],
                    "assets/macros.xml",
                    _macros(("a_macro", "turret", "component_a")),
                )
                (roots["base"] / "geometry/component_a.ANI").write_bytes(ani)
                with self.assertRaises(CensusError) as caught:
                    build_census(roots)
                self.assertIn("invalid_ani_descriptor_string", caught.exception.codes)

    def test_wrong_directory_ani_basename_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                '<components><component name="component_a" class="turret"><source geometry="wanted/shared_name"/></component></components>',
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            (roots["base"] / "wrong").mkdir()
            (roots["base"] / "wrong/shared_name.ANI").write_bytes(b"unrelated")
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("unresolved_ani_resource", caught.exception.codes)

    def test_missing_ani_resource_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                '<components><component name="component_a" class="turret"><source geometry="geometry/missing"/></component></components>',
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("unresolved_ani_resource", caught.exception.codes)

    def test_duplicate_matching_ani_resources_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                '<components><component name="component_a" class="turret"><source geometry="extensions\\ego_dlc_split\\Geometry\\Duplicate"/></component></components>',
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            for source_set, resource in (
                ("base", "extensions/ego_dlc_split/geometry/duplicate.ANI"),
                ("ego_dlc_split", "GEOMETRY/DUPLICATE.ani"),
            ):
                target = roots[source_set] / resource
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"duplicate normalized identity")
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("multiple_ani_resources", caught.exception.codes)

    def test_unrelated_ani_resources_are_not_included_in_inversion(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", _components("component_a"))
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            unrelated = roots["ego_dlc_boron"] / "unrelated/not_a_turret.ANI"
            unrelated.parent.mkdir(parents=True)
            unrelated.write_bytes(b"unrelated")
            report = build_census(roots)
            self.assertEqual(report["counts"]["unique_ani_resources"], 1)
            self.assertEqual(
                [entry["ani_resource"] for entry in report["ani_resource_to_geometry_sources_components"]],
                ["geometry/component_a.ANI"],
            )

    def test_missing_direct_geometry_source_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <metadata><source geometry="nested/misleading"/></metadata>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("missing_geometry_source", caught.exception.codes)

    def test_empty_direct_geometry_source_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                '<components><component name="component_a" class="turret"><source geometry="  "/></component></components>',
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("empty_geometry_source", caught.exception.codes)

    def test_multiple_direct_geometry_sources_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/a"/><source geometry="geometry/b"/>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("multiple_geometry_sources", caught.exception.codes)

    def test_shared_geometry_source_is_inverted_with_cardinality(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="component_a" class="turret"><source geometry="geometry/shared"/><connections><connection name="AEndpoint" tags="laser"/></connections></component>
                  <component name="component_b" class="turret"><source geometry="geometry/shared"/><connections><connection name="BEndpoint" tags="laser"/></connections></component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("a_macro", "turret", "component_a"),
                    ("b_macro", "turret", "component_b"),
                ),
            )
            report = build_census(roots)
            self.assertEqual(
                report["geometry_source_to_components"],
                [
                    {
                        "geometry_source": "geometry/shared",
                        "component_count": 2,
                        "components": ["component_a", "component_b"],
                    }
                ],
            )
            self.assertEqual(report["geometry_source_component_cardinality"], {"2": 1})

    def test_macro_component_class_mismatch_blocks_endpoint_accounting(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", _components("component_a"))
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "missileturret", "component_a")),
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("ambiguous_endpoint_class_accounting", caught.exception.codes)

    def test_missing_required_source_set_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            del roots["ego_dlc_mini_02"]
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("missing_required_source_set", caught.exception.codes)

    def test_empty_required_source_set_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            (roots["ego_dlc_mini_02"] / "source_set.xml").unlink()
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("empty_required_source_set", caught.exception.codes)

    def test_extension_mounted_ani_identity_is_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root / "sources")
            resource_roots = _source_roots(root / "resources")
            _write(
                roots["ego_dlc_split"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="extensions\\ego_dlc_split\\Weapons\\Exact"/>
                  <connections><connection name="Endpoint" tags="laser"/></connections>
                </component></components>""",
            )
            _write(
                roots["ego_dlc_split"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            target = resource_roots["ego_dlc_split"] / "WEAPONS/EXACT.ANI"
            target.parent.mkdir()
            target.write_bytes(_ani_bytes())
            report = _build_census(roots, resource_roots)
            component = report["component_to_macros"][0]
            self.assertEqual(component["ani_source_set"], "ego_dlc_split")
            self.assertEqual(
                component["ani_resource"],
                "extensions/ego_dlc_split/WEAPONS/EXACT.ANI",
            )
            self.assertEqual(report["cross_source_set_ani_bindings"], [])

    def test_cross_source_set_ani_binding_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root / "sources")
            resource_roots = _source_roots(root / "resources")
            _write(
                roots["ego_dlc_split"],
                "assets/component.xml",
                '<components><component name="component_a" class="turret"><source geometry="geometry/component_a"/><connections><connection name="Endpoint" tags="laser"/></connections></component></components>',
            )
            _write(
                roots["ego_dlc_split"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            report = _build_census(roots, resource_roots)
            self.assertEqual(report["counts"]["cross_source_set_ani_bindings"], 1)
            self.assertEqual(
                report["cross_source_set_ani_bindings"],
                [
                    {
                        "component": "component_a",
                        "component_source_set": "ego_dlc_split",
                        "geometry_source": "geometry/component_a",
                        "ani_source_set": "base",
                        "ani_resource": "geometry/component_a.ANI",
                    }
                ],
            )

    def test_missing_required_resource_set_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            resource_roots = dict(roots)
            del resource_roots["ego_dlc_mini_02"]
            with self.assertRaises(CensusError) as caught:
                _build_census(roots, resource_roots)
            self.assertIn("missing_required_resource_set", caught.exception.codes)

    def test_unavailable_required_resource_set_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root / "sources")
            resource_roots = _source_roots(root / "resources")
            resource_roots["ego_dlc_mini_02"] = root / "missing-resources"
            with self.assertRaises(CensusError) as caught:
                _build_census(roots, resource_roots)
            self.assertIn("unavailable_required_resource_set", caught.exception.codes)

    def test_empty_required_resource_set_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root / "sources")
            resource_roots = _source_roots(root / "resources")
            for path in resource_roots["ego_dlc_mini_02"].rglob("*"):
                if path.is_file() and path.suffix.lower() == ".ani":
                    path.unlink()
            with self.assertRaises(CensusError) as caught:
                _build_census(roots, resource_roots)
            self.assertIn("empty_required_resource_set", caught.exception.codes)

    def test_conflicting_duplicate_macro_identity_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", _components("component_a", "component_b"))
            _write(
                roots["base"],
                "assets/macros/a.xml",
                _macros(("duplicate_macro", "turret", "component_a")),
            )
            _write(
                roots["ego_dlc_split"],
                "assets/macros/b.xml",
                _macros(("duplicate_macro", "turret", "component_b")),
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("conflicting_duplicate_macro_identity", caught.exception.codes)

    def test_malformed_macro_record_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/macros/bad.xml",
                '<macros><macro class="turret"><component ref="component_a"/></macro></macros>',
            )
            _write(roots["base"], "assets/components.xml", _components("component_a"))
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("malformed_macro_record", caught.exception.codes)

    def test_reconciliation_uses_xml_component_identities_and_groups_differences(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root / "current")
            _write(
                roots["base"],
                "assets/base_components.xml",
                '<components><component name="current_a" class="turret"><source geometry="geometry/current_a"/><connections><connection name="AEndpoint" tags="laser"/></connections></component></components>',
            )
            _write(
                roots["ego_dlc_boron"],
                "assets/boron_components.xml",
                """<components>
                  <component name="current_b" class="turret"><source geometry="geometry/current_b"/><connections><connection name="BEndpoint" tags="laser"/></connections></component>
                  <component name="current_c" class="missileturret"><source geometry="geometry/current_c"/><connections><connection name="CEndpoint" tags="rocket"/></connections></component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/base_macros.xml",
                _macros(("a_macro", "turret", "current_a")),
            )
            _write(
                roots["ego_dlc_boron"],
                "assets/boron_macros.xml",
                _macros(
                    ("b_macro", "turret", "current_b"),
                    ("c_macro", "missileturret", "current_c"),
                ),
            )
            old = root / "old"
            platform = root / "platform"
            _write(
                old,
                "misleading_filename.xml",
                """<components>
                  <component name="current_a" class="turret"/>
                  <component name="old_only" class="missileturret"/>
                </components>""",
            )
            _write(
                platform,
                "also_not_an_identity.xml",
                """<components>
                  <component name="current_b" class="turret"/>
                  <component name="platform_only" class="turret"/>
                </components>""",
            )

            reconciliation = build_reconciliation(build_census(roots), old, platform)

            comparisons = reconciliation["comparisons"]
            self.assertEqual(comparisons["current_intersection_old79"]["components"], ["current_a"])
            self.assertEqual(comparisons["current_only_vs_old79"]["components"], ["current_b", "current_c"])
            self.assertEqual(comparisons["old79_only"]["components"], ["old_only"])
            self.assertEqual(comparisons["current_intersection_platform_sweep"]["components"], ["current_b"])
            self.assertEqual(comparisons["current_only_vs_historical_union"]["components"], ["current_c"])
            self.assertEqual(
                comparisons["historical_union_only"]["components"],
                ["old_only", "platform_only"],
            )
            groups = comparisons["current_only_vs_historical_union"]["groups"]
            self.assertEqual(groups["by_current_source_set"], {"ego_dlc_boron": ["current_c"]})
            self.assertEqual(groups["by_macro_class"], {"missileturret": ["current_c"]})
            self.assertEqual(groups["by_component_class"], {"missileturret": ["current_c"]})
            self.assertTrue(reconciliation["resolution"]["all_current_only_have_exact_provenance"])
            self.assertEqual(reconciliation["resolution"]["current_minus_old79_count"], 1)
            self.assertEqual(reconciliation["resolution"]["current_only_vs_old79_count"], 2)
            self.assertEqual(reconciliation["resolution"]["old79_only_count"], 1)
            self.assertEqual(reconciliation["resolution"]["current_only_found_in_platform_sweep_count"], 1)
            self.assertEqual(reconciliation["resolution"]["current_only_absent_from_historical_union_count"], 1)
            self.assertEqual(
                render_json(reconciliation),
                render_json(build_reconciliation(build_census(dict(reversed(list(roots.items())))), old, platform)),
            )

    def test_missing_historical_cache_blocks_reconciliation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root / "current")
            _write(roots["base"], "assets/components.xml", _components("component_a"))
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            old = root / "old"
            platform = root / "platform"
            _write(old, "components.xml", _components("component_a"))
            _write(platform, "components.xml", _components("component_a"))
            for old_path, platform_path in (
                (root / "missing-old", platform),
                (old, root / "missing-platform"),
            ):
                with self.subTest(old=old_path, platform=platform_path):
                    with self.assertRaises(CensusError) as caught:
                        build_reconciliation(build_census(roots), old_path, platform_path)
                    self.assertIn("missing_historical_cache", caught.exception.codes)

    def test_historical_cache_with_no_component_definitions_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root / "current")
            _write(roots["base"], "assets/components.xml", _components("component_a"))
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            old = root / "old"
            platform = root / "platform"
            _write(old, "not_components.xml", "<macros/>")
            _write(platform, "components.xml", _components("component_a"))
            with self.assertRaises(CensusError) as caught:
                build_reconciliation(build_census(roots), old, platform)
            self.assertIn("no_historical_component_definitions", caught.exception.codes)

    def test_same_historical_cache_cannot_fill_both_roles(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root / "current")
            _write(roots["base"], "assets/components.xml", _components("component_a"))
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            historical = root / "historical"
            _write(historical, "components.xml", _components("component_a"))
            with self.assertRaises(CensusError) as caught:
                build_reconciliation(build_census(roots), historical, historical)
            self.assertIn("historical_cache_paths_not_distinct", caught.exception.codes)

    def test_cli_writes_both_artifacts_and_rejects_partial_reconciliation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root / "current")
            _write(roots["base"], "assets/components.xml", _components("component_a"))
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            old = root / "old"
            platform = root / "platform"
            _write(old, "components.xml", _components("component_a"))
            _write(platform, "components.xml", _components("component_a"))
            source_args = [item for name in REQUIRED_SOURCE_SETS for item in ("--source-set", f"{name}={roots[name]}")]
            resource_args = [
                item for name in REQUIRED_SOURCE_SETS for item in ("--resource-set", f"{name}={roots[name]}")
            ]
            census_output = root / "census.json"
            reconciliation_output = root / "reconciliation.json"
            self.assertEqual(
                main(
                    source_args
                    + resource_args
                    + [
                        "--output",
                        str(census_output),
                        "--old79-components",
                        str(old),
                        "--platform-sweep",
                        str(platform),
                        "--reconciliation-output",
                        str(reconciliation_output),
                    ]
                ),
                0,
            )
            self.assertEqual(census_output.read_text(encoding="utf-8"), render_json(build_census(roots)))
            self.assertTrue(reconciliation_output.is_file())
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(main(source_args + resource_args + ["--old79-components", str(old)]), 2)

    def test_output_is_deterministic_across_input_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "z/components.xml",
                """<components>
                  <component name="component_z" class="turret">
                    <source geometry="geometry/component_z"/>
                    <connections>
                      <connection name="Z_Child" tags="laser" parent="Z_Part"/>
                      <connection name="Z_Root"><parts><part name="Z_Part"/></parts></connection>
                    </connections>
                  </component>
                  <component name="component_a" class="missileturret">
                    <source geometry="geometry/component_a"/>
                    <connections><connection name="A_Root" tags="rocket"/></connections>
                  </component>
                </components>""",
            )
            _write(
                roots["ego_dlc_boron"],
                "z/macros.xml",
                _macros(
                    ("z_macro", "turret", "component_z"),
                    ("a_macro", "missileturret", "component_a"),
                ),
            )
            reversed_roots = dict(reversed(list(roots.items())))
            self.assertEqual(render_json(build_census(roots)), render_json(build_census(reversed_roots)))


if __name__ == "__main__":
    unittest.main()
