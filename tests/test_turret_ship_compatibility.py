#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).parent))

from support.census_fixture import _source_roots, _write  # noqa: E402
from turret_ship_compatibility import query_compatibility  # noqa: E402


def _write_case(roots: dict[str, Path], ship_connections: str, turret_connections: str | None = None) -> None:
    _write(
        roots["base"],
        "assets/compatibility.xml",
        f"""<root>
          <components>
            <component name="turret_component" class="turret">
              <connections>{turret_connections or '<connection name="mating" tags="component advanced combat medium turret unhittable"/>'}</connections>
            </component>
            <component name="ship_component" class="ship_m">
              <connections>{ship_connections}</connections>
            </component>
          </components>
          <macros>
            <macro name="turret_macro" class="turret"><component ref="turret_component"/></macro>
            <macro name="ship_macro" class="ship_m"><component ref="ship_component"/></macro>
          </macros>
        </root>""",
    )


class TurretShipCompatibilityTests(unittest.TestCase):
    def test_compatible_connections_allow_extra_tags_and_normalize_groups(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write_case(
                roots,
                """
                  <connection name="con_b" tags="unhittable turret medium combat advanced missile"/>
                  <connection name="con_a" group=" group_a  " tags="advanced combat medium turret unhittable extra"/>
                  <connection name="wrong" group="group_wrong" tags="combat medium turret standard hittable"/>
                """,
            )

            result = query_compatibility(roots, "turret_macro", "ship_macro")

            self.assertEqual(result["status"], "compatible")
            self.assertEqual(result["compatible_mount_count"], 2)
            self.assertEqual(
                result["compatible_connections"],
                [
                    {"connection": "con_a", "group": "group_a"},
                    {"connection": "con_b", "group": None},
                ],
            )

    def test_valid_group_does_not_make_incompatible_tags_compatible(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write_case(
                roots,
                '<connection name="con_turret" group="group_valid" tags="combat medium turret standard hittable"/>',
            )

            result = query_compatibility(roots, "turret_macro", "ship_macro")

            self.assertEqual(result["status"], "incompatible")
            self.assertEqual(result["compatible_connections"], [])
            self.assertEqual(result["compatible_mount_count"], 0)

    def test_missing_exact_macro_is_unresolved(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write_case(roots, '<connection name="con_a" tags="advanced combat medium turret unhittable"/>')

            result = query_compatibility(roots, "turret_macro", "absent_ship_macro")

            self.assertEqual(result["status"], "unresolved")
            self.assertEqual(result["reason"], "missing_macro")

    def test_ambiguous_turret_mating_connection_is_unresolved(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write_case(
                roots,
                '<connection name="con_a" tags="advanced combat medium turret unhittable"/>',
                """
                  <connection name="mating_a" tags="component advanced combat medium turret unhittable"/>
                  <connection name="mating_b" tags="component advanced combat medium turret unhittable"/>
                """,
            )

            result = query_compatibility(roots, "turret_macro", "ship_macro")

            self.assertEqual(result["status"], "unresolved")
            self.assertEqual(result["reason"], "mating_connection_identity")


if __name__ == "__main__":
    unittest.main()
