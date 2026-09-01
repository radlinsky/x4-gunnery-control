#!/usr/bin/env python3
"""Pinned Issue #78 R1 characterization: equipment-macro identity and direct component-ref contract.

Characterization-only (OFFLINE evidence). These tests exercise the real
``build_census()`` production path against tiny synthetic eight-source/
eight-resource fixtures; they never reimplement production decision logic.
Scope is equipment-macro XML identity only:

- a valid included turret macro preserves exact name/class/component/
  source_set/source_file identity in the census report;
- direct component-ref violations fail closed with exact codes;
- duplicate macro identities fail closed with exact codes.

Component-definition duplication/geometry, reporting, ANI semantics, and
baseline output are deliberately out of scope (later tasks).
"""
from __future__ import annotations

import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    REQUIRED_SOURCE_SETS,
    CensusError,
    build_census,
)

# Zero-descriptor ANI resource: 16-byte header only (adapted from the monolith
# fixture ``_ani_bytes()`` with no descriptor records).
_EMPTY_ANI = struct.pack("<4I", 0, 16, 1, 0)

# Valid component definition referenced by the valid-macro fixture: a single
# direct geometry source plus the class's firing-endpoint connection.
_COMPONENT_A_XML = (
    '<components>'
    '<component name="component_a" class="turret">'
    '<source geometry="geometry/component_a"/>'
    '<connections><connection name="component_a_endpoint" tags="laser"/></connections>'
    '</component>'
    '</components>'
)


def _source_roots(root: Path) -> dict[str, Path]:
    """Create the eight official source/resource set roots, each non-empty."""
    roots: dict[str, Path] = {}
    for name in REQUIRED_SOURCE_SETS:
        path = root / name
        path.mkdir(parents=True)
        (path / "source_set.xml").write_text("<source/>", encoding="utf-8")
        inventory = path / "inventory" / f"unrelated_{name}.ANI"
        inventory.parent.mkdir()
        inventory.write_bytes(_EMPTY_ANI)
        roots[name] = path
    return roots


def _write(root: Path, relative: str, text: str) -> None:
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


class CensusMacroComponentIdentityContractTests(unittest.TestCase):
    def test_valid_included_macro_preserves_exact_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", _COMPONENT_A_XML)
            _write(
                roots["base"],
                "assets/macros.xml",
                '<macros>'
                '<macro name="turret_macro_a" class="turret">'
                '<component ref="component_a"/>'
                '</macro>'
                '</macros>',
            )
            ani = roots["base"] / "geometry" / "component_a.ANI"
            ani.parent.mkdir(parents=True)
            ani.write_bytes(_EMPTY_ANI)

            report = build_census(roots, roots)

        self.assertEqual(
            report["equipment_macros"],
            [
                {
                    "name": "turret_macro_a",
                    "class": "turret",
                    "source_set": "base",
                    "source_file": "assets/macros.xml",
                    "component": "component_a",
                }
            ],
        )

    def _expect_reference_failure(self, macro_body: str, code: str) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/macros.xml", f"<macros>{macro_body}</macros>")
            with self.assertRaises(CensusError) as raised:
                build_census(roots, roots)
        error = raised.exception
        self.assertEqual(error.codes, (code,))
        self.assertEqual(error.anomalies[0]["macro"], "turret_macro_a")

    def test_macro_without_direct_component_child_fails_missing(self) -> None:
        self._expect_reference_failure(
            '<macro name="turret_macro_a" class="turret"></macro>',
            "missing_component_reference",
        )

    def test_macro_with_empty_component_ref_fails_missing(self) -> None:
        self._expect_reference_failure(
            '<macro name="turret_macro_a" class="turret">'
            '<component ref=""/>'
            '</macro>',
            "missing_component_reference",
        )

    def test_macro_with_multiple_component_children_fails_malformed(self) -> None:
        self._expect_reference_failure(
            '<macro name="turret_macro_a" class="turret">'
            '<component ref="component_a"/>'
            '<component ref="component_b"/>'
            '</macro>',
            "malformed_component_reference",
        )

    def _expect_duplicate_identity_failure(
        self,
        code: str,
        first_macro: str,
        second_macro: str,
    ) -> dict[str, object]:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/macros_01.xml", f"<macros>{first_macro}</macros>")
            _write(roots["base"], "assets/macros_02.xml", f"<macros>{second_macro}</macros>")
            with self.assertRaises(CensusError) as raised:
                build_census(roots, roots)
        error = raised.exception
        self.assertEqual(error.codes, (code,))
        anomaly = error.anomalies[0]
        self.assertEqual(anomaly["macro"], "turret_macro_a")
        return anomaly

    def test_duplicate_macro_identity_with_identical_definition_fails(self) -> None:
        definition = (
            '<macro name="turret_macro_a" class="turret">'
            '<component ref="component_a"/>'
            '</macro>'
        )
        anomaly = self._expect_duplicate_identity_failure(
            "duplicate_macro_identity", definition, definition
        )
        self.assertEqual(
            anomaly["definitions"],
            [
                {
                    "class": "turret",
                    "component": "component_a",
                    "source_set": "base",
                    "source_file": "assets/macros_01.xml",
                },
                {
                    "class": "turret",
                    "component": "component_a",
                    "source_set": "base",
                    "source_file": "assets/macros_02.xml",
                },
            ],
        )

    def test_duplicate_macro_identity_with_differing_component_fails(self) -> None:
        first = (
            '<macro name="turret_macro_a" class="turret">'
            '<component ref="component_a"/>'
            '</macro>'
        )
        second = (
            '<macro name="turret_macro_a" class="turret">'
            '<component ref="component_b"/>'
            '</macro>'
        )
        anomaly = self._expect_duplicate_identity_failure(
            "conflicting_duplicate_macro_identity", first, second
        )
        self.assertEqual(
            anomaly["definitions"],
            [
                {
                    "class": "turret",
                    "component": "component_a",
                    "source_set": "base",
                    "source_file": "assets/macros_01.xml",
                },
                {
                    "class": "turret",
                    "component": "component_b",
                    "source_set": "base",
                    "source_file": "assets/macros_02.xml",
                },
            ],
        )

    def test_duplicate_macro_identity_with_differing_class_fails(self) -> None:
        first = (
            '<macro name="turret_macro_a" class="turret">'
            '<component ref="component_a"/>'
            '</macro>'
        )
        second = (
            '<macro name="turret_macro_a" class="missileturret">'
            '<component ref="component_a"/>'
            '</macro>'
        )
        anomaly = self._expect_duplicate_identity_failure(
            "conflicting_duplicate_macro_identity", first, second
        )
        self.assertEqual(
            anomaly["definitions"],
            [
                {
                    "class": "turret",
                    "component": "component_a",
                    "source_set": "base",
                    "source_file": "assets/macros_01.xml",
                },
                {
                    "class": "missileturret",
                    "component": "component_a",
                    "source_set": "base",
                    "source_file": "assets/macros_02.xml",
                },
            ],
        )


if __name__ == "__main__":
    unittest.main()
