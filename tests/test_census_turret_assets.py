#!/usr/bin/env python3
"""Focused synthetic tests for the Issue #72 A2.1 turret asset census."""
from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    CensusError,
    REQUIRED_SOURCE_SETS,
    build_census,
    build_reconciliation,
    main,
    render_json,
)


def _source_roots(root: Path) -> dict[str, Path]:
    roots = {}
    for name in REQUIRED_SOURCE_SETS:
        path = root / name
        path.mkdir(parents=True)
        (path / "source_set.xml").write_text("<source/>", encoding="utf-8")
        roots[name] = path
    return roots


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
                        "macro_count": 1,
                        "macros": ["missile_macro"],
                    },
                    {
                        "component": "shared_component",
                        "component_class": "turret",
                        "source_set": "base",
                        "source_file": "assets/components.xml",
                        "geometry_source": "geometry/shared",
                        "macro_count": 2,
                        "macros": ["turret_alpha_macro", "turret_beta_macro"],
                    },
                ],
            )
            self.assertEqual(report["component_macro_cardinality"], {"1": 1, "2": 1})
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
            self.assertEqual(report["component_to_macros"][0]["geometry_source"], "Assets\\Exact_CASE_Data")

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
            census_output = root / "census.json"
            reconciliation_output = root / "reconciliation.json"
            self.assertEqual(
                main(
                    source_args
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
                self.assertEqual(main(source_args + ["--old79-components", str(old)]), 2)

    def test_output_is_deterministic_across_input_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "z/components.xml", _components("component_z", "component_a"))
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
