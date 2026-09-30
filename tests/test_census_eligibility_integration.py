#!/usr/bin/env python3
"""Focused synthetic eligibility integration tests for the Issue #72 A2.1 census."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).parent))

from census_common import CensusError  # noqa: E402
from support.census_fixture import (  # noqa: E402
    _components,
    _macros,
    _source_roots,
    _wares,
    _write,
    build_census,
)


class CensusEligibilityIntegrationTests(unittest.TestCase):
    def test_combat_conventional_turret_eligibility_uses_exact_effective_ware_purposes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="combat_component" class="turret"><source geometry="geometry/component_a"/><connections><connection name="Endpoint" tags="laser"/></connections></component>
                  <component name="mine_named_combat_component" class="turret"><source geometry="geometry/component_b"/><connections><connection name="Endpoint" tags="laser"/></connections></component>
                  <component name="mining_component" class="turret"><source geometry="geometry/current_a"/><connections><connection name="Endpoint" tags="laser"/></connections></component>
                  <component name="salvage_component" class="turret"><source geometry="geometry/current_b"/><connections><connection name="Endpoint" tags="laser"/></connections></component>
                  <component name="missile_component" class="missileturret"><source geometry="geometry/missile"/><connections><connection name="Endpoint" tags="rocket"/></connections></component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("macro_combat", "turret", "combat_component"),
                    ("macro_misleading_mining_name", "turret", "mine_named_combat_component"),
                    ("macro_mining", "turret", "mining_component"),
                    ("macro_salvage", "turret", "salvage_component"),
                    ("macro_missile", "missileturret", "missile_component"),
                ),
            )
            _write(
                roots["base"],
                "libraries/wares.xml",
                _wares(
                    ("ware_combat", "macro_combat", None),
                    ("ware_misleading", "macro_misleading_mining_name", None),
                    ("ware_mining", "macro_mining", "mine"),
                    ("ware_salvage", "macro_salvage", "salvage"),
                    ("ware_missile", "macro_missile", "missile"),
                    ("ware_unrelated_unknown", "unreferenced_macro", "survey"),
                ),
            )

            report = build_census(roots)

            self.assertEqual(
                report["combat_conventional_turret_eligibility"]["counts"],
                {
                    "combat_candidate_macros": 2,
                    "combat_candidate_unique_components": 2,
                    "noncombat_utility_macros": 2,
                    "noncombat_utility_unique_components": 2,
                    "missileturret_excluded_macros": 1,
                    "missileturret_excluded_unique_components": 1,
                    "unresolved_macros": 0,
                    "unresolved_unique_components": 0,
                },
            )
            self.assertEqual(
                report["combat_conventional_turret_eligibility"]["observed_conventional_turret_purpose_token_inventory"],
                [
                    {"purpose_token": "mine", "macro_count": 1, "unique_component_count": 1},
                    {"purpose_token": "salvage", "macro_count": 1, "unique_component_count": 1},
                ],
            )
            self.assertEqual(
                [item["macro"] for item in report["combat_conventional_turret_eligibility"]["utility_macros"]],
                ["macro_mining", "macro_salvage"],
            )
            by_macro = {
                item["macro"]: item
                for item in report["combat_conventional_turret_eligibility"]["macro_classifications"]
            }
            self.assertEqual(by_macro["macro_combat"]["eligibility"], "COMBAT_CANDIDATE")
            self.assertEqual(
                by_macro["macro_misleading_mining_name"]["eligibility"],
                "COMBAT_CANDIDATE",
            )
            self.assertEqual(by_macro["macro_mining"]["purpose_tokens"], ["mine"])
            self.assertEqual(by_macro["macro_salvage"]["purpose_tokens"], ["salvage"])
            self.assertEqual(by_macro["macro_missile"]["eligibility"], "MISSILETURRET_EXCLUDED")

    def test_unknown_or_combined_conventional_turret_ware_purposes_fail_closed(self) -> None:
        cases = (("unknown", "survey"), ("combined", "mine salvage"))
        for label, purposes in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                roots = _source_roots(Path(tmp))
                _write(roots["base"], "assets/components.xml", _components("component_a"))
                _write(roots["base"], "assets/macros.xml", _macros(("macro_a", "turret", "component_a")))
                _write(roots["base"], "libraries/wares.xml", _wares(("ware_a", "macro_a", purposes)))

                report = build_census(roots)

                eligibility = report["combat_conventional_turret_eligibility"]
                self.assertEqual(eligibility["counts"]["unresolved_macros"], 1)
                self.assertEqual(
                    eligibility["unresolved_macros"][0]["unresolved_reason"],
                    "UNSUPPORTED_OR_COMBINED_WARE_PURPOSES",
                )

    def test_partial_ware_coverage_accounts_for_unmapped_macros_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", _components("component_a", "component_b"))
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("macro_a", "turret", "component_a"), ("macro_b", "turret", "component_b")),
            )
            _write(roots["base"], "libraries/wares.xml", _wares(("ware_a", "macro_a", None)))

            report = build_census(roots)

            eligibility = report["combat_conventional_turret_eligibility"]
            self.assertEqual(eligibility["counts"]["combat_candidate_macros"], 1)
            self.assertEqual(eligibility["counts"]["unresolved_macros"], 1)
            self.assertEqual(len(eligibility["macro_classifications"]), report["counts"]["equipment_macros"])
            self.assertEqual(eligibility["nonware_macro_exclusions"], [])
            self.assertEqual(
                eligibility["unresolved_no_ware_macros"],
                [
                    {
                        "macro": "macro_b",
                        "macro_class": "turret",
                        "component": "component_b",
                        "macro_source_set": "base",
                        "macro_source_file": "assets/macros.xml",
                        "eligibility": "UNRESOLVED",
                        "unresolved_reason": "no_exact_equipment_ware",
                        "evidence": {
                            "macro_source_set": "base",
                            "macro_source_file": "assets/macros.xml",
                            "component": "component_b",
                            "macro_class": "turret",
                        },
                    }
                ],
            )

    def test_multiple_direct_use_elements_resolve_by_purposes_attribute(self) -> None:
        cases = (
            (
                "mixed_restricted_unrestricted",
                "<wares><ware id='ware_a'><component ref='macro_a'/><use purposes='mine'/><use/></ware></wares>",
                "UNRESOLVED",
                ["mine"],
                "MULTIPLE_DIRECT_USE_ELEMENTS",
            ),
            (
                "empty_purposes_attribute",
                "<wares><ware id='ware_a'><component ref='macro_a'/><use purposes=''/><use/></ware></wares>",
                "UNRESOLVED",
                [],
                "MULTIPLE_DIRECT_USE_ELEMENTS",
            ),
            (
                "all_unrestricted",
                "<wares><ware id='ware_a'><component ref='macro_a'/><use/><use/></ware></wares>",
                "COMBAT_CANDIDATE",
                [],
                None,
            ),
            (
                "factions_only_entries",
                "<wares><ware id='ware_a'><component ref='macro_a'/><use threshold='0' factions='xenon'/><use threshold='0' factions='player'/></ware></wares>",
                "COMBAT_CANDIDATE",
                [],
                None,
            ),
        )
        for label, wares_xml, eligibility, tokens, reason in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                roots = _source_roots(Path(tmp))
                _write(roots["base"], "assets/components.xml", _components("component_a"))
                _write(roots["base"], "assets/macros.xml", _macros(("macro_a", "turret", "component_a")))
                _write(roots["base"], "libraries/wares.xml", wares_xml)

                report = build_census(roots)

                entry = report["combat_conventional_turret_eligibility"]["macro_classifications"][0]
                self.assertEqual(entry["eligibility"], eligibility)
                self.assertEqual(entry["purpose_tokens"], tokens)
                self.assertEqual(entry["direct_use_count"], 2)
                if reason is None:
                    self.assertNotIn("unresolved_reason", entry)
                else:
                    self.assertEqual(entry["unresolved_reason"], reason)

    def test_total_eligibility_classifications_equal_included_macros(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="component_a" class="turret"><source geometry="geometry/component_a"/><connections><connection name="Endpoint" tags="laser"/></connections></component>
                  <component name="component_b" class="turret"><source geometry="geometry/component_b"/><connections><connection name="Endpoint" tags="laser"/></connections></component>
                  <component name="component_z" class="missileturret"><source geometry="geometry/component_z"/><connections><connection name="Endpoint" tags="rocket"/></connections></component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("macro_a", "turret", "component_a"),
                    ("macro_b", "turret", "component_b"),
                    ("macro_z", "missileturret", "component_z"),
                ),
            )
            _write(
                roots["base"],
                "libraries/wares.xml",
                _wares(("ware_a", "macro_a", None), ("ware_z", "macro_z", "missile")),
            )

            report = build_census(roots)

            classifications = report["combat_conventional_turret_eligibility"]["macro_classifications"]
            self.assertEqual(len(classifications), report["counts"]["equipment_macros"])
            self.assertEqual(
                sum(report["combat_conventional_turret_eligibility"]["counts"][key] for key in (
                    "combat_candidate_macros",
                    "noncombat_utility_macros",
                    "missileturret_excluded_macros",
                    "unresolved_macros",
                )),
                report["counts"]["equipment_macros"],
            )

    def test_effective_ware_mapping_failures_are_closed(self) -> None:
        cases = (
            ("duplicate", _wares(("ware_a", "macro_a", None), ("ware_a", "macro_a", None)), "duplicate_effective_equipment_ware_mapping"),
            ("conflicting", _wares(("ware_a", "macro_a", None), ("ware_b", "macro_a", "mine")), "conflicting_effective_equipment_ware_mapping"),
            ("malformed", "<wares><ware><component ref='macro_a'/></ware></wares>", "malformed_effective_equipment_ware"),
        )
        for label, wares_xml, code in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                roots = _source_roots(Path(tmp))
                _write(roots["base"], "assets/components.xml", _components("component_a"))
                _write(roots["base"], "assets/macros.xml", _macros(("macro_a", "turret", "component_a")))
                if wares_xml:
                    _write(roots["base"], "libraries/wares.xml", wares_xml)
                with self.assertRaises(CensusError) as caught:
                    build_census(roots)
                self.assertIn(code, caught.exception.codes)


if __name__ == "__main__":
    unittest.main()
