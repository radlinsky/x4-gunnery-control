#!/usr/bin/env python3
"""Focused synthetic topology inventory tests for the Issue #72 A3 census."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).parent))

from census_common import render_json  # noqa: E402
from support.census_fixture import (  # noqa: E402
    _ani_bytes,
    _macros,
    _source_roots,
    _wares,
    _write,
    build_census,
)

# component_alpha and component_beta carry different macro, component, part,
# subname, and animation names but identical structural numbers, so they must
# share one topology group. component_gamma repeats their channel-count tuple
# at a deeper endpoint path (depth is the only difference), and
# component_delta repeats their depth with a different channel-count tuple.
_COMPONENTS_XML = """<components>
  <component name="component_alpha" class="turret">
    <source geometry="geometry/component_a"/>
    <connections>
      <connection name="Root"><animations><animation name="Spin"/></animations><parts><part name="PartA"/></parts></connection>
      <connection name="Endpoint" tags="laser" parent="PartA"/>
    </connections>
  </component>
  <component name="component_beta" class="turret">
    <source geometry="geometry/component_b"/>
    <connections>
      <connection name="Root"><animations><animation name="Cycle"/></animations><parts><part name="BodyPart"/></parts></connection>
      <connection name="Muzzle" tags="laser" parent="BodyPart"/>
    </connections>
  </component>
  <component name="component_gamma" class="turret">
    <source geometry="geometry/component_z"/>
    <connections>
      <connection name="Root"><animations><animation name="Lift"/></animations><parts><part name="TrunkPart"/><part name="ArmPart"/></parts></connection>
      <connection name="Arm" parent="TrunkPart"><parts><part name="BarrelPart"/></parts></connection>
      <connection name="Muzzle" tags="laser" parent="BarrelPart"/>
    </connections>
  </component>
  <component name="component_delta" class="turret">
    <source geometry="geometry/current_a"/>
    <connections>
      <connection name="Root"><animations><animation name="Pulse"/></animations><parts><part name="PartD"/></parts></connection>
      <connection name="Endpoint" tags="laser" parent="PartD"/>
    </connections>
  </component>
  <component name="component_utility" class="turret">
    <source geometry="geometry/current_b"/>
    <connections>
      <connection name="Root"><animations><animation name="Spin"/></animations><parts><part name="PartU"/></parts></connection>
      <connection name="Endpoint" tags="laser" parent="PartU"/>
    </connections>
  </component>
  <component name="component_missile" class="missileturret">
    <source geometry="geometry/current_c"/>
    <connections><connection name="Launch" tags="rocket"><parts><part name="PartM"/></parts></connection></connections>
  </component>
  <component name="component_orphan" class="turret">
    <source geometry="geometry/shared"/>
    <connections>
      <connection name="Root"><parts><part name="PartO"/></parts></connection>
      <connection name="Endpoint" tags="laser" parent="PartO"/>
    </connections>
  </component>
  <component name="component_twin" class="turret">
    <source geometry="geometry/shared_component"/>
    <connections>
      <connection name="Root"><parts><part name="TwinPartA"/><part name="TwinPartB"/></parts></connection>
      <connection name="Near" tags="laser" parent="TwinPartA"/>
      <connection name="Arm" parent="TwinPartB"><parts><part name="TwinPartC"/></parts></connection>
      <connection name="Far" tags="laser" parent="TwinPartC"/>
    </connections>
  </component>
</components>"""

_MACROS = (
    ("macro_alpha", "turret", "component_alpha"),
    ("macro_beta", "turret", "component_beta"),
    ("macro_gamma", "turret", "component_gamma"),
    ("macro_delta", "turret", "component_delta"),
    ("macro_utility", "turret", "component_utility"),
    ("macro_missile", "missileturret", "component_missile"),
    ("macro_orphan", "turret", "component_orphan"),
    ("macro_twin", "turret", "component_twin"),
)

_WARES = (
    ("ware_alpha", "macro_alpha", None),
    ("ware_beta", "macro_beta", None),
    ("ware_gamma", "macro_gamma", None),
    ("ware_delta", "macro_delta", None),
    ("ware_utility", "macro_utility", "mine"),
    ("ware_missile", "macro_missile", "missile"),
    ("ware_twin", "macro_twin", None),
)

_ANI_BY_PATH = {
    "geometry/component_a.ANI": _ani_bytes(("PartA", "Spin", 2, 0, 1, 0, 0)),
    "geometry/component_b.ANI": _ani_bytes(("BodyPart", "Cycle", 2, 0, 1, 0, 0)),
    "geometry/component_z.ANI": _ani_bytes(("TrunkPart", "Lift", 2, 0, 1, 0, 0)),
    "geometry/current_a.ANI": _ani_bytes(("PartD", "Pulse", 0, 4, 0, 1, 0)),
    "geometry/current_b.ANI": _ani_bytes(("PartU", "Spin", 2, 0, 1, 0, 0)),
    "geometry/current_c.ANI": _ani_bytes(("PartM", "OffPath")),
}

_EXPECTED_GROUPS = [
    {
        "endpoint_count": 1,
        "endpoint_structure": [
            {
                "source_part_path_depth": 1,
                "selected_descriptor_channel_count_tuples": [[2, 0, 1, 0, 0]],
            }
        ],
        "nonzero_candidate_channel_indexes": [0, 2],
        "macro_count": 2,
        "unique_component_count": 2,
        "macros": ["macro_alpha", "macro_beta"],
        "components": ["component_alpha", "component_beta"],
    },
    {
        "endpoint_count": 1,
        "endpoint_structure": [
            {
                "source_part_path_depth": 1,
                "selected_descriptor_channel_count_tuples": [[0, 4, 0, 1, 0]],
            }
        ],
        "nonzero_candidate_channel_indexes": [1, 3],
        "macro_count": 1,
        "unique_component_count": 1,
        "macros": ["macro_delta"],
        "components": ["component_delta"],
    },
    {
        "endpoint_count": 1,
        "endpoint_structure": [
            {
                "source_part_path_depth": 2,
                "selected_descriptor_channel_count_tuples": [[2, 0, 1, 0, 0]],
            }
        ],
        "nonzero_candidate_channel_indexes": [0, 2],
        "macro_count": 1,
        "unique_component_count": 1,
        "macros": ["macro_gamma"],
        "components": ["component_gamma"],
    },
    {
        "endpoint_count": 2,
        "endpoint_structure": [
            {
                "source_part_path_depth": 1,
                "selected_descriptor_channel_count_tuples": [],
            },
            {
                "source_part_path_depth": 2,
                "selected_descriptor_channel_count_tuples": [],
            },
        ],
        "nonzero_candidate_channel_indexes": [],
        "macro_count": 1,
        "unique_component_count": 1,
        "macros": ["macro_twin"],
        "components": ["component_twin"],
    },
]

_EXPECTED_INVENTORY = {
    "evidence_classification": "shipped-source",
    "semantic_claim": "none",
    "macro_count": 5,
    "unique_component_count": 5,
    "group_count": 4,
    "groups": _EXPECTED_GROUPS,
}


def _topology_corpus(base: Path) -> dict[str, Path]:
    roots = _source_roots(base)
    _write(roots["base"], "assets/components.xml", _COMPONENTS_XML)
    _write(roots["base"], "assets/macros.xml", _macros(*_MACROS))
    _write(roots["base"], "libraries/wares.xml", _wares(*_WARES))
    for relative, data in _ANI_BY_PATH.items():
        (roots["base"] / relative).write_bytes(data)
    return roots


class CensusTopologyInventoryTests(unittest.TestCase):
    def _build_report(self) -> dict[str, object]:
        with tempfile.TemporaryDirectory() as tmp:
            return build_census(_topology_corpus(Path(tmp)))

    def _inventory(self, report: dict[str, object]) -> dict[str, object]:
        return report["combat_conventional_topology_inventory"]

    def test_inventory_is_exposed_with_full_expected_structure(self) -> None:
        report = self._build_report()
        self.assertEqual(self._inventory(report), _EXPECTED_INVENTORY)

    def test_identically_structured_macros_with_different_names_share_a_group(self) -> None:
        inventory = self._inventory(self._build_report())
        alpha_group = next(
            group
            for group in inventory["groups"]
            if "macro_alpha" in group["macros"]
        )
        self.assertIn("macro_beta", alpha_group["macros"])
        self.assertEqual(alpha_group["macros"], ["macro_alpha", "macro_beta"])
        self.assertEqual(
            alpha_group["components"], ["component_alpha", "component_beta"]
        )
        self.assertEqual(alpha_group["macro_count"], 2)
        self.assertEqual(alpha_group["unique_component_count"], 2)

    def test_different_depth_or_channel_counts_separate_groups(self) -> None:
        inventory = self._inventory(self._build_report())
        by_macro = {
            macro: group
            for group in inventory["groups"]
            for macro in group["macros"]
        }
        alpha_group = by_macro["macro_alpha"]
        self.assertNotIn("macro_gamma", alpha_group["macros"])
        self.assertNotIn("macro_delta", alpha_group["macros"])
        self.assertNotIn("macro_twin", alpha_group["macros"])
        gamma_group = by_macro["macro_gamma"]
        delta_group = by_macro["macro_delta"]
        twin_group = by_macro["macro_twin"]
        self.assertEqual(gamma_group["macros"], ["macro_gamma"])
        self.assertEqual(delta_group["macros"], ["macro_delta"])
        self.assertEqual(twin_group["macros"], ["macro_twin"])
        gamma_structure = gamma_group["endpoint_structure"][0]
        delta_structure = delta_group["endpoint_structure"][0]
        alpha_structure = alpha_group["endpoint_structure"][0]
        self.assertNotEqual(gamma_structure, alpha_structure)
        self.assertNotEqual(delta_structure, alpha_structure)
        self.assertEqual(
            gamma_structure["selected_descriptor_channel_count_tuples"],
            alpha_structure["selected_descriptor_channel_count_tuples"],
        )
        self.assertNotEqual(
            gamma_structure["source_part_path_depth"],
            alpha_structure["source_part_path_depth"],
        )
        self.assertEqual(
            delta_structure["source_part_path_depth"],
            alpha_structure["source_part_path_depth"],
        )
        self.assertEqual(gamma_group["endpoint_count"], 1)
        self.assertEqual(twin_group["endpoint_count"], 2)
        self.assertEqual(
            [record["source_part_path_depth"] for record in twin_group["endpoint_structure"]],
            [1, 2],
        )

    def test_non_combat_and_unresolved_macros_are_excluded(self) -> None:
        inventory = self._inventory(self._build_report())
        grouped_macros = {
            macro for group in inventory["groups"] for macro in group["macros"]
        }
        self.assertEqual(
            grouped_macros,
            {"macro_alpha", "macro_beta", "macro_gamma", "macro_delta", "macro_twin"},
        )
        for excluded in ("macro_utility", "macro_missile", "macro_orphan"):
            self.assertNotIn(excluded, grouped_macros)
        self.assertEqual(inventory["macro_count"], 5)
        self.assertEqual(
            sum(group["macro_count"] for group in inventory["groups"]),
            inventory["macro_count"],
        )

    def test_inventory_ordering_is_deterministic(self) -> None:
        first = self._build_report()
        second = self._build_report()
        self.assertEqual(
            render_json(self._inventory(second)),
            render_json(self._inventory(first)),
        )
        self.assertEqual(
            [group["macros"] for group in self._inventory(first)["groups"]],
            [group["macros"] for group in _EXPECTED_GROUPS],
        )
        for group in self._inventory(first)["groups"]:
            self.assertEqual(group["macros"], sorted(group["macros"]))
            self.assertEqual(group["components"], sorted(group["components"]))

    def test_inventory_counts_follow_existing_combat_eligibility(self) -> None:
        report = self._build_report()
        inventory = self._inventory(report)
        eligibility = report["combat_conventional_turret_eligibility"]
        self.assertEqual(
            inventory["macro_count"],
            eligibility["counts"]["combat_candidate_macros"],
        )
        self.assertEqual(
            inventory["unique_component_count"],
            eligibility["counts"]["combat_candidate_unique_components"],
        )
        self.assertEqual(inventory["group_count"], len(inventory["groups"]))
        self.assertEqual(
            sum(group["unique_component_count"] for group in inventory["groups"]),
            inventory["unique_component_count"],
        )
        self.assertEqual(eligibility["counts"]["combat_candidate_macros"], 5)


if __name__ == "__main__":
    unittest.main()
