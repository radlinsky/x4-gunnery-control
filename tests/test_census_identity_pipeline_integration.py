#!/usr/bin/env python3
"""Focused synthetic identity and source-pipeline integration tests for the Issue #72 A2.1 census."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).parent))

from census_common import CensusError  # noqa: E402
from census_pipeline import build_census as _build_census  # noqa: E402
from support.census_fixture import (  # noqa: E402
    _ani_bytes,
    _components,
    _macros,
    _source_roots,
    _write,
    build_census,
)


class CensusIdentityPipelineIntegrationTests(unittest.TestCase):
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



if __name__ == "__main__":
    unittest.main()
