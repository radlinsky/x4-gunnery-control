#!/usr/bin/env python3
"""Focused synthetic tests for the Issue #72 A2.1 turret asset census."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    CensusError,
    REQUIRED_SOURCE_SETS,
    build_census,
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
    body = "".join(f'<component name="{name}" class="turret"/>' for name in names)
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
                _components("shared_component", "missile_component", "unrelated_component"),
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
                        "macro_count": 1,
                        "macros": ["missile_macro"],
                    },
                    {
                        "component": "shared_component",
                        "macro_count": 2,
                        "macros": ["turret_alpha_macro", "turret_beta_macro"],
                    },
                ],
            )
            self.assertEqual(report["component_macro_cardinality"], {"1": 1, "2": 1})
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
