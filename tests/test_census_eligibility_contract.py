#!/usr/bin/env python3
"""Issue #78 R1 characterization: the turret ware-eligibility classification contract.

Calls the real _build_combat_conventional_turret_eligibility() with small
in-memory macro and ware records only: no filesystem, XML, or X4 census data.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    _build_combat_conventional_turret_eligibility,
)


def _macro(name: str, macro_class: str = "turret", component: str | None = None) -> dict:
    return {
        "name": name,
        "class": macro_class,
        "source_set": "base",
        "source_file": f"{name}.xml",
        "component": component or f"{name}_component",
    }


def _ware(component: str, ware: str = "test_ware", purposes: tuple = ()) -> dict:
    return {
        "ware": ware,
        "component": component,
        "source_set": "base",
        "source_file": "wares.xml",
        "component_reference_count": 1,
        "use_count": len(purposes),
        "purpose_attributes": list(purposes),
        "use_records": [
            {"purposes": purpose, "attributes": {}} for purpose in purposes
        ],
    }


def _entry(summary: dict, name: str) -> dict:
    return next(item for item in summary["macro_classifications"] if item["macro"] == name)


class CensusEligibilityContractTests(unittest.TestCase):
    def test_turret_with_exact_ware_and_no_purposes_is_combat_candidate(self) -> None:
        macro = _macro("turret_contract_no_purpose_macro")
        summary, anomalies = _build_combat_conventional_turret_eligibility(
            [macro], [_ware(macro["name"])]
        )
        self.assertEqual(anomalies, [])
        entry = _entry(summary, macro["name"])
        self.assertEqual(entry["eligibility"], "COMBAT_CANDIDATE")
        self.assertEqual(entry["purpose_tokens"], [])

    def test_turret_with_exact_ware_and_mine_purpose_is_noncombat_utility(self) -> None:
        macro = _macro("turret_contract_mine_macro")
        summary, anomalies = _build_combat_conventional_turret_eligibility(
            [macro], [_ware(macro["name"], purposes=("mine",))]
        )
        self.assertEqual(anomalies, [])
        entry = _entry(summary, macro["name"])
        self.assertEqual(entry["eligibility"], "NONCOMBAT_UTILITY")
        self.assertEqual(entry["purpose_tokens"], ["mine"])

    def test_turret_with_exact_ware_and_salvage_purpose_is_noncombat_utility(self) -> None:
        macro = _macro("turret_contract_salvage_macro")
        summary, anomalies = _build_combat_conventional_turret_eligibility(
            [macro], [_ware(macro["name"], purposes=("salvage",))]
        )
        self.assertEqual(anomalies, [])
        entry = _entry(summary, macro["name"])
        self.assertEqual(entry["eligibility"], "NONCOMBAT_UTILITY")
        self.assertEqual(entry["purpose_tokens"], ["salvage"])

    def test_missileturret_with_exact_ware_is_missileturret_excluded(self) -> None:
        macro = _macro("missileturret_contract_macro", macro_class="missileturret")
        summary, anomalies = _build_combat_conventional_turret_eligibility(
            [macro], [_ware(macro["name"])]
        )
        self.assertEqual(anomalies, [])
        entry = _entry(summary, macro["name"])
        self.assertEqual(entry["eligibility"], "MISSILETURRET_EXCLUDED")

    def test_turret_without_matching_ware_is_unresolved_no_exact_equipment_ware(self) -> None:
        macro = _macro("turret_contract_no_ware_macro")
        summary, anomalies = _build_combat_conventional_turret_eligibility([macro], [])
        self.assertEqual(anomalies, [])
        entry = _entry(summary, macro["name"])
        self.assertEqual(entry["eligibility"], "UNRESOLVED")
        self.assertEqual(entry["unresolved_reason"], "no_exact_equipment_ware")
        self.assertIn(
            macro["name"], [item["macro"] for item in summary["unresolved_macros"]]
        )

    def test_turret_with_unsupported_survey_purpose_is_unresolved(self) -> None:
        macro = _macro("turret_contract_survey_macro")
        summary, anomalies = _build_combat_conventional_turret_eligibility(
            [macro], [_ware(macro["name"], purposes=("survey",))]
        )
        self.assertEqual(anomalies, [])
        entry = _entry(summary, macro["name"])
        self.assertEqual(entry["eligibility"], "UNRESOLVED")
        self.assertEqual(
            entry["unresolved_reason"], "UNSUPPORTED_OR_COMBINED_WARE_PURPOSES"
        )

    def test_counts_match_synthetic_records_exactly(self) -> None:
        no_purpose = _macro("turret_count_no_purpose_macro")
        mine = _macro("turret_count_mine_macro")
        salvage = _macro("turret_count_salvage_macro")
        missile = _macro("missileturret_count_macro", macro_class="missileturret")
        no_ware = _macro("turret_count_no_ware_macro")
        survey = _macro("turret_count_survey_macro")
        macros = [no_purpose, mine, salvage, missile, no_ware, survey]
        wares = [
            _ware(no_purpose["name"]),
            _ware(mine["name"], purposes=("mine",)),
            _ware(salvage["name"], purposes=("salvage",)),
            _ware(missile["name"]),
            _ware(survey["name"], purposes=("survey",)),
        ]
        summary, anomalies = _build_combat_conventional_turret_eligibility(macros, wares)
        self.assertEqual(anomalies, [])
        self.assertEqual(
            summary["counts"],
            {
                "combat_candidate_macros": 1,
                "combat_candidate_unique_components": 1,
                "noncombat_utility_macros": 2,
                "noncombat_utility_unique_components": 2,
                "missileturret_excluded_macros": 1,
                "missileturret_excluded_unique_components": 1,
                "unresolved_macros": 2,
                "unresolved_unique_components": 2,
            },
        )


if __name__ == "__main__":
    unittest.main()
