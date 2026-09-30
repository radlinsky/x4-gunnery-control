#!/usr/bin/env python3
"""Focused synthetic subname and turret_active relationship integration tests for the Issue #72 A2.1 census."""
from __future__ import annotations

import copy
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).parent))

from census_ani_relationships import (  # noqa: E402
    _build_same_subname_structural_relationship_coverage,
)
from census_common import CensusError, render_json  # noqa: E402
from census_pipeline import build_census as _build_census  # noqa: E402
from support.census_fixture import (  # noqa: E402
    _ani_bytes,
    _candidate_key_record,
    _macros,
    _source_roots,
    _write,
    build_census,
)


class CensusRelationshipsIntegrationTests(unittest.TestCase):
    def test_conventional_same_subname_structural_relationships_are_exact_and_deduplicated(self) -> None:
        paths = {
            "Root": ["Root"],
            "Child": ["Root", "Child"],
            "Grand": ["Root", "Child", "Grand"],
            "Sibling": ["Sibling"],
        }
        selectors = [
            ("Root", "Same"),
            ("Root", "Ancestor"),
            ("Root", "Multi"),
            ("Root", "CaseName"),
            ("Child", "Multi"),
            ("Grand", "DescendantOnly"),
            ("Sibling", "SiblingOnly"),
        ]
        descriptors = [
            (0, "RootPart", "Same", "Root", (1, 0, 0, 0, 0)),
            (1, "RootPart", "DescendantOnly", "Root", (0, 0, 0, 0, 0)),
            (2, "RootPart", "casename", "Root", (0, 0, 0, 0, 0)),
            (3, "RootPart", "NoSelector", "Root", (0, 0, 0, 0, 0)),
            (4, "ChildPart", "Ancestor", "Child", (0, 0, 0, 0, 0)),
            (5, "GrandPart", "Multi", "Grand", (0, 1, 0, 0, 0)),
            (6, "GrandPart", "SiblingOnly", "Grand", (0, 0, 0, 0, 0)),
        ]
        memberships = [
            {
                "descriptor_index": index,
                "part": part,
                "subname": subname,
                "source_connection": connection,
                "root_to_source_connection_path": paths[connection],
                "channel_counts": dict(
                    zip(("position", "rotation", "scale", "pre_scale", "post_scale"), counts)
                ),
            }
            for index, part, subname, connection, counts in descriptors
        ]
        component_to_macros = [
            {
                "component": "component_a",
                "component_class": "turret",
                "connections": [
                    {"name": connection, "root_to_connection_path": path}
                    for connection, path in paths.items()
                ],
                "authored_connection_animations": [
                    {"connection": connection, "name": name}
                    for connection, name in selectors
                ],
            }
        ]
        firing_endpoints = [
            {
                "component": "component_a",
                "component_class": "turret",
                "connection": endpoint,
                "ani_descriptor_memberships": copy.deepcopy(memberships),
            }
            for endpoint in ("EndpointA", "EndpointB")
        ]

        coverage = _build_same_subname_structural_relationship_coverage(
            component_to_macros, firing_endpoints
        )

        self.assertEqual(coverage["evidence_classification"], "inference")
        with self.subTest("relationship inventory"):
            self.assertEqual(coverage["semantic_claim"], "none")
            self.assertEqual(coverage["descriptor_memberships"], 14)
            self.assertEqual(coverage["unique_descriptors"], 7)
            inventory = {
                descriptor["literal_subname"]: descriptor
                for descriptor in coverage["descriptors"]
            }
            self.assertEqual(
                inventory["Same"]["root_to_source_connection_path"], ["Root"]
            )
            self.assertEqual(inventory["Same"]["source_connection"], "Root")
            self.assertEqual(inventory["Same"]["endpoint_membership_count"], 2)
            self.assertTrue(inventory["Same"]["descriptor_has_keys"])
            self.assertEqual(
                inventory["Same"]["same_subname_selector_relationships"],
                [
                    {
                        "selector_connection": "Root",
                        "root_to_selector_connection_path": ["Root"],
                        "relation": "same_source_connection",
                        "distance": 0,
                    }
                ],
            )
            self.assertEqual(
                inventory["Ancestor"]["same_subname_selector_relationships"],
                [
                    {
                        "selector_connection": "Root",
                        "root_to_selector_connection_path": ["Root"],
                        "relation": "strict_ancestor_connection",
                        "distance": 1,
                    }
                ],
            )
            self.assertEqual(
                inventory["Multi"]["strict_ancestor_selector_distances"], [1, 2]
            )
            self.assertEqual(
                [
                    relationship["relation"]
                    for relationship in inventory["DescendantOnly"][
                        "same_subname_selector_relationships"
                    ]
                ],
                ["descendant_connection"],
            )
            self.assertEqual(
                [
                    relationship["relation"]
                    for relationship in inventory["SiblingOnly"][
                        "same_subname_selector_relationships"
                    ]
                ],
                ["unrelated_connection"],
            )
            self.assertEqual(
                inventory["casename"]["same_subname_selector_relationships"], []
            )
            self.assertEqual(
                inventory["NoSelector"]["same_subname_selector_relationships"], []
            )
            self.assertTrue(
                inventory["NoSelector"]["no_same_subname_selector_on_ancestry"]
            )
            self.assertEqual(
                coverage["relationship_occurrence_counts"],
                {
                    "same_source_connection": 1,
                    "strict_ancestor_connection": 3,
                    "descendant_connection": 1,
                    "unrelated_connection": 1,
                    "none": 2,
                },
            )
            multi_row = next(
                row
                for row in coverage["full_cross_tab"]
                if row["literal_subname"] == "Multi"
            )
            self.assertEqual(
                multi_row,
                {
                    "literal_subname": "Multi",
                    "descriptor_key_class": "has_keys",
                    "same_connection_selector": False,
                    "nearest_ancestor_same_subname_selector_distance": 1,
                    "no_same_subname_selector_on_ancestry": False,
                    "multiple_matching_ancestors": True,
                    "unique_descriptor_count": 1,
                    "endpoint_membership_count": 2,
                },
            )
            self.assertEqual(
                coverage["hypothesis_assessment"]["assessment"],
                "structurally incomplete",
            )
        self.assertEqual(
            render_json(coverage),
            render_json(
                _build_same_subname_structural_relationship_coverage(
                    component_to_macros, firing_endpoints
                )
            ),
        )

    def test_changing_turret_active_cases_preserve_raw_numeric_and_endpoint_identities(self) -> None:
        def record(
            main: tuple[float, float, float],
            enums: tuple[int, int, int],
            slot_024: float,
        ) -> bytes:
            values: list[float | int] = [0] * 32
            values[0:3] = main
            values[3:6] = enums
            values[6] = slot_024
            return _candidate_key_record(tuple(values))

        key_data = (
            record((0.0, 1.0, 2.0), (1, 2, 3), 0.0)
            + record((-0.0, 1.0, 2.0), (4, 5, 6), 1.0)
            + record((3.0, 4.0, 5.0), (7, 8, 9), 2.0)
            + record((3.0, 6.0, 5.0), (10, 11, 12), 3.0)
            + record((7.0, 8.0, 9.0), (13, 14, 15), 4.0)
            + record((10.0, 8.0, 9.0), (16, 17, 18), 5.0)
            + record((11.0, 12.0, 13.0), (19, 20, 21), 6.0)
            + record((11.0, 12.0, 14.0), (22, 23, 24), 7.0)
        )
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="changing_component" class="turret">
                    <source geometry="geometry/changing"/>
                    <connections>
                      <connection name="Root"><animations><animation name="turret_active"/></animations><parts><part name="Channel0Part"/><part name="Channel1Part"/><part name="BothPart"/></parts></connection>
                      <connection name="C0" parent="Channel0Part"><parts><part name="C0Tip"/></parts></connection>
                      <connection name="C0A" tags="laser" parent="C0Tip"/>
                      <connection name="C0B" tags="laser" parent="C0Tip"/>
                      <connection name="C1" parent="Channel1Part"><parts><part name="C1Tip"/></parts></connection>
                      <connection name="C1A" tags="laser" parent="C1Tip"/>
                      <connection name="C1B" tags="laser" parent="C1Tip"/>
                      <connection name="Both" parent="BothPart"><parts><part name="BothTip"/></parts></connection>
                      <connection name="BothA" tags="laser" parent="BothTip"/>
                      <connection name="BothB" tags="laser" parent="BothTip"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("changing_alpha_macro", "turret", "changing_component"),
                    ("changing_beta_macro", "turret", "changing_component"),
                ),
            )
            (roots["base"] / "geometry/changing.ANI").write_bytes(
                _ani_bytes(
                    ("Channel0Part", "turret_active", 2, 0, 0, 0, 0),
                    ("Channel1Part", "turret_active", 0, 2, 0, 0, 0),
                    ("BothPart", "turret_active", 2, 2, 0, 0, 0),
                    key_data=key_data,
                )
            )
            report = _build_census(
                roots,
                roots,
                expected_turret_active_changing_case_baseline=(3, 2, 2),
            )[
                "ancestry_covered_literal_turret_active_candidate_channel_inventory"
            ]["changing_first_three_stored_values_inventory"]
            with self.assertRaises(CensusError) as mismatch:
                _build_census(
                    roots,
                    roots,
                    expected_turret_active_changing_case_baseline=(4, 2, 2),
                )

        self.assertIn(
            "accepted_turret_active_changing_case_baseline_mismatch",
            mismatch.exception.codes,
        )
        self.assertEqual(report["cohort_unique_descriptor_count"], 3)
        self.assertEqual(
            report["accepted_changing_descriptor_counts"],
            {"candidate_channel_0": 2, "candidate_channel_1": 2},
        )
        self.assertEqual(report["reconciliation_status"], "pass")
        by_channel = {
            row["candidate_channel_id"]: row["changing_descriptors"]
            for row in report["candidate_channels"]
        }
        self.assertEqual(
            [[case["ani_descriptor"]["part"] for case in by_channel[channel]] for channel in by_channel],
            [["Channel0Part", "BothPart"], ["Channel1Part", "BothPart"]],
        )
        self.assertEqual(
            report["descriptors_changing_in_both_candidate_channels_0_and_1"],
            [{"component": "changing_component", "descriptor_index": 2, "part": "BothPart", "subname": "turret_active"}],
        )
        channel_0_only = next(
            case for case in by_channel["candidate_channel_0"]
            if case["ani_descriptor"]["part"] == "Channel0Part"
        )
        self.assertEqual(
            channel_0_only["equipment_macros"],
            ["changing_alpha_macro", "changing_beta_macro"],
        )
        self.assertEqual(channel_0_only["component_connection"], "Root")
        self.assertEqual(channel_0_only["same_name_ancestor_coverage_relationship"], "same_connection")
        self.assertEqual(channel_0_only["key_count_family"], [2, 0, 0, 0, 0])
        self.assertEqual(
            [item["connection"] for item in channel_0_only["muzzle_endpoint_memberships"]],
            ["C0A", "C0B"],
        )
        self.assertEqual(channel_0_only["muzzle_endpoint_membership_count"], 2)
        slot_000 = channel_0_only["first_three_slot_changes"][0]
        self.assertEqual(slot_000["raw_bits_change"], True)
        self.assertEqual(slot_000["candidate_numeric_values_change"], False)
        self.assertEqual(slot_000["change_classification"], "stored_representation_only")
        self.assertEqual(
            [record["slots"]["slot_000"] for record in channel_0_only["key_records"]],
            [
                {"raw_bits": "0x00000000", "candidate_type": "float32_le", "candidate_value": 0.0},
                {"raw_bits": "0x80000000", "candidate_type": "float32_le", "candidate_value": -0.0},
            ],
        )
        self.assertEqual(
            list(channel_0_only["key_records"][0]["slots"]),
            ["slot_000", "slot_004", "slot_008", "slot_012", "slot_016", "slot_020", "slot_024"],
        )
        both = next(
            case for case in by_channel["candidate_channel_0"]
            if case["ani_descriptor"]["part"] == "BothPart"
        )
        self.assertTrue(both["numerically_different_change_occurs"])
        self.assertEqual(
            both["first_three_slot_changes"][0]["change_classification"],
            "numerically_different",
        )
        self.assertEqual(
            len({(case["turret_component_asset"], case["descriptor_index"]) for case in by_channel["candidate_channel_0"]}),
            2,
        )

    def test_ancestry_covered_turret_active_candidate_channels_are_cohorted_and_bounded(self) -> None:
        def record(
            main: tuple[float, float, float],
            enums: tuple[int, int, int],
            slot_024: float,
            *,
            slot_028: int = 0,
            slot_076: int = 0,
        ) -> bytes:
            values: list[float | int] = [0] * 32
            values[0:3] = main
            values[3:6] = enums
            values[6] = slot_024
            values[7] = slot_028
            values[19] = slot_076
            return _candidate_key_record(tuple(values))

        included_records = (
            record((1.0, 1.0, 1.0), (1, 2, 3), 1.0)
            + record((2.0, 2.0, 2.0), (4, 5, 6), 1.0, slot_028=10)
            + record((2.0, 2.0, 2.0), (4, 5, 6), 2.0, slot_028=11)
            + record((3.0, 3.0, 3.0), (7, 8, 9), 1.0, slot_028=12)
            + record((4.0, 3.0, 3.0), (7, 8, 9), 2.0, slot_028=12)
            + record((5.0, 5.0, 5.0), (10, 11, 12), 1.0)
            + record((6.0, 6.0, 6.0), (13, 14, 15), 1.0)
            + record((7.0, 6.0, 6.0), (13, 14, 15), 2.0, slot_076=4)
        )
        excluded_records = b"".join(
            record((float(index), 0.0, 0.0), (20, 21, 22), 1.0)
            for index in range(5)
        )
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional" class="turret">
                    <source geometry="geometry/conventional"/>
                    <connections>
                      <connection name="Root"><animations><animation name="turret_active"/></animations><parts><part name="SamePart"/></parts></connection>
                      <connection name="Child" parent="SamePart"><parts><part name="AncestorPart"/></parts></connection>
                      <connection name="EndpointA" tags="laser" parent="AncestorPart"/>
                      <connection name="EndpointB" tags="laser" parent="AncestorPart"/>
                      <connection name="Sibling"><parts><part name="UnrelatedPart"/></parts></connection>
                      <connection name="EndpointC" tags="laser" parent="UnrelatedPart"/>
                    </connections>
                  </component>
                  <component name="missile" class="missileturret">
                    <source geometry="geometry/missile"/>
                    <connections><connection name="Root"><animations><animation name="turret_active"/></animations><parts><part name="MissilePart"/></parts></connection><connection name="Endpoint" tags="rocket" parent="MissilePart"/></connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("conventional_macro", "turret", "conventional"),
                    ("missile_macro", "missileturret", "missile"),
                ),
            )
            (roots["base"] / "geometry/conventional.ANI").write_bytes(
                _ani_bytes(
                    ("SamePart", "turret_active", 1, 2, 2, 1, 2),
                    ("AncestorPart", "turret_active", 0, 0, 0, 0, 0),
                    ("UnrelatedPart", "turret_active", 1, 1, 1, 1, 1),
                    key_data=included_records + excluded_records,
                )
            )
            (roots["base"] / "geometry/missile.ANI").write_bytes(
                _ani_bytes(
                    ("MissilePart", "turret_active", 1, 1, 1, 1, 1),
                    key_data=excluded_records,
                )
            )

            inventory = build_census(roots)[
                "ancestry_covered_literal_turret_active_candidate_channel_inventory"
            ]
            repeated_inventory = build_census(roots)[
                "ancestry_covered_literal_turret_active_candidate_channel_inventory"
            ]

        self.assertEqual(inventory["evidence_classification"], "inference")
        self.assertEqual(
            inventory["raw_ani_subname_path_evidence_classification"],
            "shipped-source",
        )
        self.assertEqual(
            inventory["candidate_channel_field_layout_evidence_classification"],
            "third-party-technique",
        )
        self.assertEqual(inventory["semantic_claim"], "none")
        self.assertEqual(inventory["unique_descriptor_count"], 2)
        self.assertEqual(inventory["endpoint_membership_count"], 4)
        self.assertEqual(
            [
                (descriptor["descriptor_index"], descriptor["structural_relation"])
                for descriptor in inventory["descriptors"]
            ],
            [(0, "same_connection"), (1, "strict_ancestor_distance_1")],
        )
        self.assertNotIn("missile", {item["component"] for item in inventory["descriptors"]})
        self.assertEqual(
            inventory["channel_count_families"],
            [
                {
                    "candidate_channel_key_counts": [0, 0, 0, 0, 0],
                    "unique_descriptor_count": 1,
                    "endpoint_membership_count": 2,
                },
                {
                    "candidate_channel_key_counts": [1, 2, 2, 1, 2],
                    "unique_descriptor_count": 1,
                    "endpoint_membership_count": 2,
                },
            ],
        )
        channels = {
            channel["candidate_channel_id"]: channel
            for channel in inventory["candidate_channels"]
        }
        self.assertEqual(
            channels["candidate_channel_0"]["classifications"],
            {
                "zero_keys": {"descriptor_count": 1, "key_record_count": 0},
                "one_key": {"descriptor_count": 1, "key_record_count": 1},
                "multiple_keys_identical_raw_bit_triples": {"descriptor_count": 0, "key_record_count": 0},
                "multiple_keys_changing_raw_bit_triples": {"descriptor_count": 0, "key_record_count": 0},
            },
        )
        self.assertEqual(
            channels["candidate_channel_1"]["classifications"][
                "multiple_keys_identical_raw_bit_triples"
            ],
            {"descriptor_count": 1, "key_record_count": 2},
        )
        self.assertEqual(
            channels["candidate_channel_2"]["classifications"][
                "multiple_keys_changing_raw_bit_triples"
            ],
            {"descriptor_count": 1, "key_record_count": 2},
        )
        self.assertEqual(
            channels["candidate_channel_1"]["multi_key_metadata"]["slots_028_072"][0][
                "descriptors_with_differing_raw_bits"
            ],
            1,
        )
        self.assertEqual(
            channels["candidate_channel_2"]["multi_key_metadata"]["slots_028_072"][0][
                "descriptors_with_constant_raw_bits"
            ],
            1,
        )
        self.assertEqual(
            channels["candidate_channel_3"]["classifications"]["one_key"],
            {"descriptor_count": 1, "key_record_count": 1},
        )
        self.assertEqual(
            channels["candidate_channel_4"]["multi_key_metadata"]["slots_076_124"][0][
                "raw_bit_nonzero_count"
            ],
            1,
        )
        self.assertEqual(
            {channel["candidate_channel_id"] for channel in inventory["candidate_channels"]},
            {f"candidate_channel_{index}" for index in range(5)},
        )
        self.assertEqual(
            inventory["structural_relation_channel_family_cross_tab"],
            [
                {
                    "same_connection_selector": True,
                    "nearest_strict_ancestor_distance": None,
                    "candidate_channel_key_counts": [1, 2, 2, 1, 2],
                    "unique_descriptor_count": 1,
                    "endpoint_membership_count": 2,
                },
                {
                    "same_connection_selector": False,
                    "nearest_strict_ancestor_distance": 1,
                    "candidate_channel_key_counts": [0, 0, 0, 0, 0],
                    "unique_descriptor_count": 1,
                    "endpoint_membership_count": 2,
                },
            ],
        )
        self.assertTrue(
            channels["candidate_channel_1"]["proof_scope"][
                "multi_key_metadata_varies"
            ]
        )
        self.assertEqual(
            channels["candidate_channel_1"]["proof_scope"]["enum_raw_values"],
            {
                "slot_012": ["0x00000004"],
                "slot_016": ["0x00000005"],
                "slot_020": ["0x00000006"],
            },
        )
        self.assertTrue(inventory["missileturrets_excluded_from_cohort"])
        self.assertEqual(render_json(inventory), render_json(repeated_inventory))

    def test_selected_subname_candidate_channel_inventory_is_exact_case_deduplicated_and_metadata_bounded(self) -> None:
        def record(
            main: tuple[float, float, float],
            enums: tuple[int, int, int],
            slot_024: float,
        ) -> bytes:
            values: list[float | int] = [0] * 32
            values[0:3] = main
            values[3:6] = enums
            values[6] = slot_024
            return _candidate_key_record(tuple(values))

        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_a" class="turret">
                    <source geometry="geometry/conventional_a"/>
                    <connections>
                      <connection name="Root"><animations><animation name="turret_active"/><animation name="Turret_Active"/></animations><parts><part name="ActiveA"/><part name="CaseA"/></parts></connection>
                      <connection name="EndpointA" tags="laser" parent="ActiveA"/>
                      <connection name="EndpointB" tags="laser" parent="ActiveA"/>
                      <connection name="EndpointCase" tags="laser" parent="CaseA"/>
                    </connections>
                  </component>
                  <component name="conventional_b" class="turret">
                    <source geometry="geometry/conventional_b"/>
                    <connections>
                      <connection name="Root"><animations><animation name="turret_active"/></animations><parts><part name="ActiveB"/></parts></connection>
                      <connection name="Endpoint" tags="laser" parent="ActiveB"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/missile"/>
                    <connections>
                      <connection name="Root"><animations><animation name="turret_active"/></animations><parts><part name="MissilePart"/></parts></connection>
                      <connection name="Endpoint" tags="rocket" parent="MissilePart"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("conventional_a_macro", "turret", "conventional_a"),
                    ("conventional_b_macro", "turret", "conventional_b"),
                    ("missile_macro", "missileturret", "missile_component"),
                ),
            )
            (roots["base"] / "geometry/conventional_a.ANI").write_bytes(
                _ani_bytes(
                    ("ActiveA", "turret_active", 2, 1, 0, 0, 0),
                    ("CaseA", "Turret_Active", 0, 0, 2, 0, 0),
                    key_data=(
                        record((1.0, 2.0, 3.0), (1, 2, 3), 1.0)
                        + record((1.0, 2.0, 3.0), (1, 2, 4), 2.0)
                        + record((4.0, 5.0, 6.0), (5, 6, 7), 8.0)
                        + record((0.0, 0.0, 0.0), (8, 9, 10), 3.0)
                        + record((0.0, 1.0, 0.0), (8, 9, 10), 3.0)
                    ),
                )
            )
            (roots["base"] / "geometry/conventional_b.ANI").write_bytes(
                _ani_bytes(
                    ("ActiveB", "turret_active", 0, 0, 2, 0, 0),
                    key_data=(
                        record((7.0, 8.0, 9.0), (11, 12, 13), 4.0)
                        + record((8.0, 8.0, 9.0), (11, 12, 13), 2.0)
                    ),
                )
            )
            (roots["base"] / "geometry/missile.ANI").write_bytes(
                _ani_bytes(
                    ("MissilePart", "turret_active", 0, 0, 0, 0, 1),
                    key_data=record((9.0, 9.0, 9.0), (14, 15, 16), 5.0),
                )
            )
            inventory = build_census(roots)[
                "selected_descriptor_subname_candidate_channel_inventory"
            ]

        self.assertEqual(inventory["evidence_classification"], "inference")
        self.assertEqual(
            inventory["raw_subname_counts_and_bits_evidence_classification"],
            "shipped-source",
        )
        self.assertEqual(
            inventory["candidate_channel_ownership_and_layout_evidence_classification"],
            "third-party-technique",
        )
        conventional = inventory["conventional"]
        missile = inventory["missileturret_accounting"]
        self.assertEqual(conventional["selected_endpoint_memberships"], 4)
        self.assertEqual(conventional["unique_descriptor_count"], 3)
        self.assertEqual(missile["selected_endpoint_memberships"], 1)
        self.assertTrue(missile["non_decision_driving"])

        by_subname = {entry["subname"]: entry for entry in conventional["subnames"]}
        self.assertEqual(list(by_subname), ["Turret_Active", "turret_active"])
        exact = by_subname["turret_active"]
        self.assertEqual(exact["selected_endpoint_memberships"], 3)
        self.assertEqual(exact["unique_descriptor_count"], 2)
        self.assertEqual(exact["unique_component_count"], 2)
        self.assertEqual(exact["components"], ["conventional_a", "conventional_b"])
        self.assertEqual(exact["unique_source_connection_count"], 2)
        self.assertEqual(
            exact["source_connections"],
            [
                {"component": "conventional_a", "source_connection": "Root"},
                {"component": "conventional_b", "source_connection": "Root"},
            ],
        )
        self.assertEqual(
            exact["channel_count_families"],
            [
                {
                    "candidate_channel_key_counts": [0, 0, 2, 0, 0],
                    "unique_descriptor_count": 1,
                    "selected_endpoint_memberships": 1,
                },
                {
                    "candidate_channel_key_counts": [2, 1, 0, 0, 0],
                    "unique_descriptor_count": 1,
                    "selected_endpoint_memberships": 2,
                },
            ],
        )
        channels = {
            channel["candidate_channel_id"]: channel
            for channel in exact["candidate_channels"]
        }
        self.assertEqual(
            channels["candidate_channel_0"]["classifications"],
            {
                "zero_keys": {"descriptor_count": 1, "key_record_count": 0},
                "one_key": {"descriptor_count": 0, "key_record_count": 0},
                "multiple_keys_identical_raw_bit_triples": {
                    "descriptor_count": 1,
                    "key_record_count": 2,
                },
                "multiple_keys_changing_raw_bit_triples": {
                    "descriptor_count": 0,
                    "key_record_count": 0,
                },
            },
        )
        self.assertEqual(
            channels["candidate_channel_0"]["multi_key_main_triple_masks"],
            [
                {
                    "changing_mask_slots_000_004_008": "000",
                    "descriptor_count": 1,
                    "key_record_count": 2,
                }
            ],
        )
        self.assertEqual(
            channels["candidate_channel_2"]["multi_key_main_triple_masks"],
            [
                {
                    "changing_mask_slots_000_004_008": "100",
                    "descriptor_count": 1,
                    "key_record_count": 2,
                }
            ],
        )
        self.assertEqual(
            channels["candidate_channel_0"]["observed_candidate_metadata"][
                "slot_024_ordering_shapes"
            ],
            {
                "all_equal": {"descriptor_count": 0, "key_record_count": 0},
                "strictly_increasing": {"descriptor_count": 1, "key_record_count": 2},
                "nondecreasing": {"descriptor_count": 0, "key_record_count": 0},
                "other": {"descriptor_count": 0, "key_record_count": 0},
            },
        )
        self.assertEqual(
            channels["candidate_channel_1"]["observed_candidate_metadata"][
                "candidate_enum_triplet_distribution"
            ],
            [
                {
                    "raw_bits": ["0x00000005", "0x00000006", "0x00000007"],
                    "candidate_values": [5, 6, 7],
                    "record_count": 1,
                }
            ],
        )
        self.assertEqual(by_subname["Turret_Active"]["unique_descriptor_count"], 1)
        self.assertEqual(
            by_subname["Turret_Active"]["candidate_channels"][2][
                "multi_key_main_triple_masks"
            ][0]["changing_mask_slots_000_004_008"],
            "010",
        )

        focused = inventory["focused_literal_turret_active"]
        self.assertTrue(focused["present"])
        self.assertEqual(
            focused["present_candidate_channels"],
            ["candidate_channel_0", "candidate_channel_1", "candidate_channel_2"],
        )
        self.assertEqual(
            focused["absent_candidate_channels"],
            ["candidate_channel_3", "candidate_channel_4"],
        )
        self.assertEqual(
            focused["absent_metadata_forms"][
                "candidate_channels_without_enum_triplet_values"
            ],
            ["candidate_channel_3", "candidate_channel_4"],
        )
        self.assertEqual(
            focused["absent_metadata_forms"][
                "candidate_channels_without_slot_024_values"
            ],
            ["candidate_channel_3", "candidate_channel_4"],
        )
        channel_2_absence = next(
            entry
            for entry in focused["absent_metadata_forms"][
                "by_present_candidate_channel"
            ]
            if entry["candidate_channel_id"] == "candidate_channel_2"
        )
        self.assertEqual(
            channel_2_absence["absent_multi_key_classifications"],
            ["multiple_keys_identical_raw_bit_triples"],
        )
        self.assertEqual(focused["literal_token_semantic_claim"], "none")
        rendered_inventory = render_json(inventory).lower()
        for unsupported_name in (
            "position",
            "rotation",
            "scale",
            "axis",
            "interpolation",
            "timing",
            "pivot",
            "transform",
        ):
            self.assertNotIn(unsupported_name, rendered_inventory)


if __name__ == "__main__":
    unittest.main()
