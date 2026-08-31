#!/usr/bin/env python3
"""Focused synthetic tests for the Issue #72 A2.1 turret asset census."""
from __future__ import annotations

import contextlib
import io
import struct
import tempfile
import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    CensusError,
    REQUIRED_SOURCE_SETS,
    build_census as _build_census,
    build_reconciliation,
    main,
    render_json,
)


def _ani_bytes(
    *descriptors: tuple[str, str],
    version: int = 1,
    header_padding: int = 0,
    key_offset: int | None = None,
    descriptor_padding: tuple[int, int] = (0, 0),
) -> bytes:
    records = []
    for part, subname in descriptors:
        part_bytes = part.encode("ascii")
        subname_bytes = subname.encode("ascii")
        if len(part_bytes) > 63 or len(subname_bytes) > 63:
            raise ValueError("synthetic ANI descriptor strings must fit with a NUL terminator")
        records.append(
            part_bytes.ljust(64, b"\0")
            + subname_bytes.ljust(64, b"\0")
            + struct.pack(
                "<5If2I", 0, 0, 0, 0, 0, 0.0, *descriptor_padding
            )
        )
    descriptor_table = b"".join(records)
    return struct.pack(
        "<4I",
        len(descriptors),
        16 + len(descriptor_table) if key_offset is None else key_offset,
        version,
        header_padding,
    ) + descriptor_table


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
        f'<component name="{name}" class="turret"><source geometry="geometry/{name}"/></component>'
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
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/missile"/>
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
                        "connections": [],
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
                        "connections": [],
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
                component["ani_descriptors"],
                [
                    {
                        "part": "Part_CASE",
                        "subname": "Sub_CASE",
                        "source_connection": "Conn_A",
                        "root_to_source_connection_path": ["Conn_A"],
                    },
                    {
                        "part": "SharedPart",
                        "subname": "SharedSub",
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
                [{"connection": "Conn_A", "name": "Anim_CASE"}],
            )
            self.assertEqual(
                component["descriptor_parts_absent_from_source_parts"], []
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
                    <connection name="Grand" parent="ArmPart"><parts><part name="BarrelPart"/></parts></connection>
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
                        "root_to_connection_path": ["Root", "Branch"],
                        "depth": 1,
                    },
                    {
                        "name": "Child",
                        "parent_part": "BasePart",
                        "parent_connection": "Root",
                        "direct_owned_parts": ["ArmPart"],
                        "root_to_connection_path": ["Root", "Child"],
                        "depth": 1,
                    },
                    {
                        "name": "EmptyParentRoot",
                        "parent_part": None,
                        "parent_connection": None,
                        "direct_owned_parts": [],
                        "root_to_connection_path": ["EmptyParentRoot"],
                        "depth": 0,
                    },
                    {
                        "name": "Grand",
                        "parent_part": "ArmPart",
                        "parent_connection": "Child",
                        "direct_owned_parts": ["BarrelPart"],
                        "root_to_connection_path": ["Root", "Child", "Grand"],
                        "depth": 2,
                    },
                    {
                        "name": "Root",
                        "parent_part": None,
                        "parent_connection": None,
                        "direct_owned_parts": ["BasePart", "BasePart"],
                        "root_to_connection_path": ["Root"],
                        "depth": 0,
                    },
                ],
            )
            self.assertEqual(
                component["ani_descriptors"],
                [
                    {
                        "part": "BarrelPart",
                        "subname": "Sub_CASE",
                        "source_connection": "Grand",
                        "root_to_source_connection_path": ["Root", "Child", "Grand"],
                    },
                    {
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
                  <component name="component_a" class="turret"><source geometry="geometry/shared"/></component>
                  <component name="component_b" class="turret"><source geometry="geometry/shared"/></component>
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

    def test_macro_component_class_mismatch_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", _components("component_a"))
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "missileturret", "component_a")),
            )
            report = build_census(roots)
            self.assertEqual(
                report["macro_component_class_mismatches"],
                [
                    {
                        "macro": "a_macro",
                        "macro_class": "missileturret",
                        "macro_source_set": "base",
                        "macro_source_file": "assets/macros.xml",
                        "component": "component_a",
                        "component_class": "turret",
                        "component_source_set": "base",
                        "component_source_file": "assets/components.xml",
                    }
                ],
            )

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
                '<components><component name="component_a" class="turret"><source geometry="geometry/component_a"/></component></components>',
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
                '<components><component name="current_a" class="turret"><source geometry="geometry/current_a"/></component></components>',
            )
            _write(
                roots["ego_dlc_boron"],
                "assets/boron_components.xml",
                """<components>
                  <component name="current_b" class="turret"><source geometry="geometry/current_b"/></component>
                  <component name="current_c" class="missileturret"><source geometry="geometry/current_c"/></component>
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
                      <connection name="Z_Child" parent="Z_Part"/>
                      <connection name="Z_Root"><parts><part name="Z_Part"/></parts></connection>
                    </connections>
                  </component>
                  <component name="component_a" class="turret">
                    <source geometry="geometry/component_a"/>
                    <connections><connection name="A_Root"/></connections>
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
