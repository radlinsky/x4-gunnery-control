#!/usr/bin/env python3
"""Pinned Issue #78 R1 characterization: referenced-component → direct geometry-source → ANI-resource identity contract.

Characterization-only (OFFLINE evidence). These tests exercise the real
``build_census()`` production path against tiny synthetic eight-source/
eight-resource fixtures; they never reimplement production decision logic.
Scope is the component-resource identity seam only:

- a valid referenced component preserves exact component class/source_set/
  source_file identity in the census report;
- only a direct ``<source geometry=...>`` supplies geometry identity; nested
  source elements do not;
- geometry identity matching normalizes only separator/case as production
  does, while report output preserves the authored geometry string and the
  exact enumerated ANI resource identity;
- referenced-component definition failures fail closed with exact codes;
- direct geometry-source failures fail closed with exact codes;
- ANI-resource resolution failures fail closed with exact codes.

Macro/component-ref identity is accepted in its own pinned contract
(``test_census_macro_component_identity_contract.py``); ware eligibility,
endpoint/connection behavior, ANI binary parsing, and baseline output are
deliberately out of scope (later tasks).
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

# Authored geometry identity with backslash separators and mixed case; it
# matches the enumerated ``ASSETS/Exact_CASE_Data.ANI`` resource only through
# production's separator/case normalization.
_VALID_COMPONENT_XML = (
    '<components>'
    '<component name="component_a" class="turret">'
    '<source geometry="Assets\\Exact_CASE_Data"/>'
    '<connections><connection name="Endpoint" tags="laser"/></connections>'
    '<metadata><source geometry="nested/misleading"/></metadata>'
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


def _write_ani(roots: dict[str, Path], source_set: str, relative: str, data: bytes) -> None:
    target = roots[source_set] / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)


def _macros_xml(component_ref: str) -> str:
    return (
        "<macros>"
        '<macro name="turret_macro_a" class="turret">'
        f'<component ref="{component_ref}"/>'
        '</macro>'
        '</macros>'
    )


class CensusComponentResourceIdentityContractTests(unittest.TestCase):
    def _fail_single(self, roots: dict[str, Path], code: str) -> dict[str, object]:
        with self.assertRaises(CensusError) as raised:
            build_census(roots, roots)
        error = raised.exception
        self.assertEqual(error.codes, (code,))
        return error.anomalies[0]

    def test_valid_referenced_component_preserves_exact_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", _VALID_COMPONENT_XML)
            _write(roots["base"], "assets/macros.xml", _macros_xml("component_a"))
            _write_ani(roots, "base", "ASSETS/Exact_CASE_Data.ANI", _EMPTY_ANI)

            report = build_census(roots, roots)

        self.assertEqual(report["anomalies"], [])
        self.assertEqual(len(report["component_to_macros"]), 1)
        entry = report["component_to_macros"][0]
        self.assertEqual(
            {
                "component": entry["component"],
                "component_class": entry["component_class"],
                "source_set": entry["source_set"],
                "source_file": entry["source_file"],
                "geometry_source": entry["geometry_source"],
                "ani_source_set": entry["ani_source_set"],
                "ani_resource": entry["ani_resource"],
                "macro_count": entry["macro_count"],
                "macros": entry["macros"],
            },
            {
                "component": "component_a",
                "component_class": "turret",
                "source_set": "base",
                "source_file": "assets/components.xml",
                # The authored geometry string is preserved exactly; only
                # separator/case are normalized for the resource match.
                "geometry_source": "Assets\\Exact_CASE_Data",
                "ani_source_set": "base",
                "ani_resource": "ASSETS/Exact_CASE_Data.ANI",
                "macro_count": 1,
                "macros": ["turret_macro_a"],
            },
        )

    def test_absent_component_definition_fails_unresolved(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/macros.xml", _macros_xml("absent_component"))
            anomaly = self._fail_single(roots, "unresolved_component_reference")
        self.assertEqual(anomaly["component"], "absent_component")
        self.assertEqual(anomaly["macros"], ["turret_macro_a"])

    def test_multiple_full_component_definitions_fail(self) -> None:
        definition = (
            '<components>'
            '<component name="shared_component" class="turret">'
            '<source geometry="geometry/shared_component"/>'
            '<connections><connection name="shared_component_endpoint" tags="laser"/></connections>'
            '</component>'
            '</components>'
        )
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components_a.xml", definition)
            _write(roots["ego_dlc_split"], "assets/components_b.xml", definition)
            _write(roots["base"], "assets/macros.xml", _macros_xml("shared_component"))
            anomaly = self._fail_single(roots, "multiple_component_definitions")
        self.assertEqual(anomaly["component"], "shared_component")
        self.assertEqual(
            [
                (item["source_set"], item["source_file"], item["component_class"])
                for item in anomaly["definitions"]
            ],
            [
                ("base", "assets/components_a.xml", "turret"),
                ("ego_dlc_split", "assets/components_b.xml", "turret"),
            ],
        )

    def test_empty_component_class_fails_malformed(self) -> None:
        # The empty class also fails the firing-endpoint class gate; that
        # second, deterministic anomaly is part of the pinned behavior.
        component_xml = (
            '<components>'
            '<component name="component_a" class="">'
            '<source geometry="geometry/component_a"/>'
            '<connections><connection name="Endpoint" tags="laser"/></connections>'
            '</component>'
            '</components>'
        )
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", component_xml)
            _write(roots["base"], "assets/macros.xml", _macros_xml("component_a"))
            _write_ani(roots, "base", "geometry/component_a.ANI", _EMPTY_ANI)
            with self.assertRaises(CensusError) as raised:
                build_census(roots, roots)
        error = raised.exception
        self.assertEqual(
            error.codes,
            (
                "malformed_component_definition",
                "unsupported_endpoint_component_class",
            ),
        )
        malformed, endpoint = error.anomalies
        self.assertEqual(malformed["component"], "component_a")
        self.assertEqual(malformed["source_set"], "base")
        self.assertEqual(malformed["source_file"], "assets/components.xml")
        self.assertEqual(endpoint["component"], "component_a")
        self.assertEqual(endpoint["component_class"], "")

    def test_missing_direct_geometry_source_fails(self) -> None:
        # Only a nested source is present, so no direct geometry source exists.
        component_xml = (
            '<components>'
            '<component name="component_a" class="turret">'
            '<metadata><source geometry="nested/misleading"/></metadata>'
            '<connections><connection name="Endpoint" tags="laser"/></connections>'
            '</component>'
            '</components>'
        )
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", component_xml)
            _write(roots["base"], "assets/macros.xml", _macros_xml("component_a"))
            anomaly = self._fail_single(roots, "missing_geometry_source")
        self.assertEqual(anomaly["component"], "component_a")
        self.assertEqual(anomaly["source_set"], "base")
        self.assertEqual(anomaly["source_file"], "assets/components.xml")

    def test_multiple_direct_geometry_sources_fail(self) -> None:
        component_xml = (
            '<components>'
            '<component name="component_a" class="turret">'
            '<source geometry="geometry/a"/>'
            '<source geometry="geometry/b"/>'
            '<connections><connection name="Endpoint" tags="laser"/></connections>'
            '</component>'
            '</components>'
        )
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", component_xml)
            _write(roots["base"], "assets/macros.xml", _macros_xml("component_a"))
            anomaly = self._fail_single(roots, "multiple_geometry_sources")
        self.assertEqual(anomaly["component"], "component_a")
        self.assertEqual(anomaly["geometry_sources"], ["geometry/a", "geometry/b"])

    def test_empty_direct_geometry_source_fails(self) -> None:
        component_xml = (
            '<components>'
            '<component name="component_a" class="turret">'
            '<source geometry="  "/>'
            '<connections><connection name="Endpoint" tags="laser"/></connections>'
            '</component>'
            '</components>'
        )
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", component_xml)
            _write(roots["base"], "assets/macros.xml", _macros_xml("component_a"))
            anomaly = self._fail_single(roots, "empty_geometry_source")
        self.assertEqual(anomaly["component"], "component_a")

    def test_no_matching_ani_resource_fails_unresolved(self) -> None:
        component_xml = (
            '<components>'
            '<component name="component_a" class="turret">'
            '<source geometry="geometry/missing"/>'
            '<connections><connection name="Endpoint" tags="laser"/></connections>'
            '</component>'
            '</components>'
        )
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", component_xml)
            _write(roots["base"], "assets/macros.xml", _macros_xml("component_a"))
            anomaly = self._fail_single(roots, "unresolved_ani_resource")
        self.assertEqual(anomaly["component"], "component_a")
        self.assertEqual(anomaly["geometry_source"], "geometry/missing")

    def test_multiple_matching_ani_resources_fail(self) -> None:
        # One file per official set with the same normalized stem; the authored
        # geometry carries backslash separators and mixed case.
        component_xml = (
            '<components>'
            '<component name="component_a" class="turret">'
            '<source geometry="extensions\\ego_dlc_split\\Geometry\\Duplicate"/>'
            '<connections><connection name="Endpoint" tags="laser"/></connections>'
            '</component>'
            '</components>'
        )
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", component_xml)
            _write(roots["base"], "assets/macros.xml", _macros_xml("component_a"))
            _write_ani(
                roots,
                "base",
                "extensions/ego_dlc_split/geometry/duplicate.ANI",
                b"duplicate normalized identity",
            )
            _write_ani(roots, "ego_dlc_split", "GEOMETRY/DUPLICATE.ani", b"duplicate normalized identity")
            anomaly = self._fail_single(roots, "multiple_ani_resources")
        self.assertEqual(anomaly["component"], "component_a")
        self.assertEqual(
            anomaly["geometry_source"], "extensions\\ego_dlc_split\\Geometry\\Duplicate"
        )
        self.assertEqual(
            anomaly["matches"],
            [
                {
                    "ani_source_set": "base",
                    "ani_resource": "extensions/ego_dlc_split/geometry/duplicate.ANI",
                },
                {
                    "ani_source_set": "ego_dlc_split",
                    "ani_resource": "extensions/ego_dlc_split/GEOMETRY/DUPLICATE.ani",
                },
            ],
        )


if __name__ == "__main__":
    unittest.main()
