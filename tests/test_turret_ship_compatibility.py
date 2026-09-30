#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).parent))

from support.census_fixture import _source_roots, _write  # noqa: E402
from preflight_testlab_loadouts import PreflightError, validate_loadouts  # noqa: E402
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


def _loadouts(path: Path, assignment: str) -> Path:
    path.write_text(
        f"""<loadouts>
          <loadout id="fixture" macro="ship_macro">
            <macros>{assignment if assignment.startswith('<turret ') else ''}</macros>
            <groups>{assignment if assignment.startswith('<turrets ') else ''}</groups>
          </loadout>
        </loadouts>""",
        encoding="utf-8",
    )
    return path


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


class TestLabLoadoutPreflightTests(unittest.TestCase):
    def test_multiple_pairs_collect_official_source_once(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root)
            _write_case(
                roots,
                """
                  <connection name="con_beam" tags="advanced combat medium turret unhittable"/>
                  <connection name="con_laser" tags="standard combat medium turret unhittable"/>
                """,
            )
            _write(
                roots["base"],
                "assets/second_turret.xml",
                """<root>
                  <components>
                    <component name="second_turret_component" class="turret">
                      <connections>
                        <connection name="mating" tags="component standard combat medium turret unhittable"/>
                      </connections>
                    </component>
                  </components>
                  <macros>
                    <macro name="second_turret_macro" class="turret">
                      <component ref="second_turret_component"/>
                    </macro>
                  </macros>
                </root>""",
            )
            loadouts = root / "loadouts.xml"
            loadouts.write_text(
                """<loadouts>
                  <loadout id="fixture" macro="ship_macro">
                    <macros>
                      <turret macro="turret_macro" path="../con_beam"/>
                      <turret macro="second_turret_macro" path="../con_laser"/>
                    </macros>
                    <groups/>
                  </loadout>
                </loadouts>""",
                encoding="utf-8",
            )

            from turret_ship_compatibility import _collect_xml_identities

            with patch(
                "turret_ship_compatibility._collect_xml_identities",
                wraps=_collect_xml_identities,
            ) as collect:
                validate_loadouts(roots, loadouts)

            self.assertEqual(collect.call_count, 1)

    def test_ungrouped_compatible_path_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root)
            _write_case(
                roots,
                '<connection name="con_turret" tags="advanced combat medium turret unhittable"/>',
            )

            validate_loadouts(
                roots,
                _loadouts(root / "loadouts.xml", '<turret macro="turret_macro" path="../con_turret"/>'),
            )

    def test_path_to_named_group_member_fails_with_group(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root)
            _write_case(
                roots,
                '<connection name="con_turret" group="group_left" tags="advanced combat medium turret unhittable"/>',
            )

            with self.assertRaisesRegex(PreflightError, "group_left.*group-targeted"):
                validate_loadouts(
                    roots,
                    _loadouts(root / "loadouts.xml", '<turret macro="turret_macro" path="../con_turret"/>'),
                )

    def test_exact_one_passes_for_multi_connection_group(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root)
            _write_case(
                roots,
                """
                  <connection name="con_left" group="group_front" tags="advanced combat medium turret unhittable"/>
                  <connection name="con_right" group="group_front" tags="advanced combat medium turret unhittable"/>
                """,
            )

            validate_loadouts(
                roots,
                _loadouts(
                    root / "loadouts.xml",
                    '<turrets macro="turret_macro" group="group_front" exact="1"/>',
                ),
            )

    def test_unsupported_path_ownership_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            roots = _source_roots(root)
            _write_case(
                roots,
                '<connection name="con_turret" tags="advanced combat medium turret unhittable"/>',
            )

            with self.assertRaisesRegex(PreflightError, "unsupported path ownership"):
                validate_loadouts(
                    roots,
                    _loadouts(root / "loadouts.xml", '<turret macro="turret_macro" path="./con_turret"/>'),
                )


if __name__ == "__main__":
    unittest.main()
