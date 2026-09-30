#!/usr/bin/env python3
"""Focused synthetic Paranid L Beam anchor integration tests for the Issue #72 A2.1 census."""
from __future__ import annotations

import copy
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).parent))

from census_anchor_evidence import _evaluate_paranid_l_beam_trace  # noqa: E402
from census_pipeline import build_census as _build_census  # noqa: E402
from support.census_fixture import (  # noqa: E402
    _ani_bytes,
    _candidate_key_record,
    _macros,
    _source_roots,
    _write,
)


class CensusAnchorIntegrationTests(unittest.TestCase):
    def test_paranid_l_beam_live_anchor_fails_closed_on_every_provenance_break(self) -> None:
        def record(vector: tuple[float, float, float], slot_024: float) -> bytes:
            values: list[float | int] = [0] * 32
            values[0:3] = vector
            values[3:6] = [1, 1, 1]
            values[6] = slot_024
            return _candidate_key_record(tuple(values))

        production_formula = {
            "production_sha": "synthetic-production-sha",
            "downstream_vector": [20.0, 52.0, 64.0],
            "yaw_origin_expression_terms": [
                [1.0, 2.0, 3.0],
                [0.0, 20.0, 0.0],
            ],
            "pivot_vector": [4.0, 5.0, 6.0],
            "runtime_inputs": ["target_bearing_yaw", "target_bearing_pitch"],
            "operation_sequence": [
                "weapon_local_look_at_target_useaimtarget_true",
                "md_create_rotation_pitch_equals_runtime_bearing_pitch",
                "md_transform_downstream_vector_by_pitch_rotation",
                "add_pivot_vector",
                "md_create_rotation_yaw_equals_runtime_bearing_yaw",
                "md_transform_pivoted_vector_by_yaw_rotation",
                "add_yaw_origin",
            ],
            "untraced_constants": [],
        }
        trace_spec = {
            "endpoint_connection": "con_laser_02",
            "root_connection": "Connection01",
            "pivot_connection": "Connection04",
            "barrel_connection": "Connection05",
            "laser_connection": "con_laser_02",
            "rotator_active_descriptor": {
                "descriptor_index": 1,
                "part": "part_rotator",
                "subname": "turret_active",
                "candidate_channel_index": 0,
                "triple_slot_indexes": [0, 1, 2],
            },
            "barrel_active_descriptor": {
                "descriptor_index": 3,
                "part": "anim_barrel",
                "subname": "turret_active",
                "candidate_channel_index": 0,
                "triple_slot_indexes": [0, 1, 2],
            },
        }

        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="turret_par_l_beam_01_mk1" class="turret">
                    <source geometry="geometry/beam"/>
                    <connections>
                      <connection name="Connection01"><offset><position x="1" y="2" z="3"/></offset><animations><animation name="turret_active"/></animations><parts><part name="part_socket"/></parts></connection>
                      <connection name="Connection03" parent="part_socket"><parts><part name="part_rotator"/></parts></connection>
                      <connection name="Connection04" parent="part_rotator"><offset><position x="4" y="5" z="6"/><quaternion qx="0" qy="0" qz="0" qw="1"/></offset><parts><part name="anim_gun"/></parts></connection>
                      <connection name="Connection05" parent="anim_gun"><offset><position x="7" y="8" z="9"/><quaternion qx="0" qy="0" qz="0" qw="1"/></offset><parts><part name="anim_barrel"/></parts></connection>
                      <connection name="con_laser_01" tags="laser" parent="anim_barrel"><offset><position x="10" y="11" z="12"/></offset></connection>
                      <connection name="con_laser_02" tags="laser" parent="anim_barrel"><offset><position x="13" y="14" z="15"/></offset></connection>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    (
                        "turret_par_l_beam_01_mk1_macro",
                        "turret",
                        "turret_par_l_beam_01_mk1",
                    ),
                ),
            )
            (roots["base"] / "geometry/beam.ANI").write_bytes(
                _ani_bytes(
                    ("part_socket", "turret_active", 0, 0, 0, 0, 0),
                    ("part_rotator", "turret_active", 2, 0, 0, 0, 0),
                    ("anim_gun", "turret_active", 0, 0, 0, 0, 0),
                    ("anim_barrel", "turret_active", 2, 0, 0, 0, 0),
                    key_data=(
                        record((0.0, 20.0, 0.0), 0.0)
                        + record((0.0, 20.0, 0.0), 1.0)
                        + record((0.0, 30.0, 40.0), 0.0)
                        + record((0.0, 30.0, 40.0), 1.0)
                    ),
                )
            )
            census = _build_census(
                roots,
                roots,
                anchor_production_formula=production_formula,
                anchor_trace_spec=trace_spec,
            )

        anchor = census["paranid_l_beam_accepted_live_anchor"]
        source_trace_bundle = anchor["source_trace_bundle"]
        self.assertEqual(anchor["status"], "pass")
        self.assertEqual(anchor["failures"], [])
        self.assertEqual(
            anchor["identity_chain"]["root_to_endpoint_connection_path"],
            [
                "Connection01",
                "Connection03",
                "Connection04",
                "Connection05",
                "con_laser_02",
            ],
        )
        self.assertEqual(
            len(anchor["endpoint_descriptor_inventory"]),
            4,
        )
        self.assertEqual(
            [
                descriptor["descriptor_index"]
                for descriptor in anchor["selector_selected_descriptor_inventory"]
            ],
            [0],
        )
        rotator = next(
            descriptor
            for descriptor in anchor["literal_turret_active_descriptors"]
            if descriptor["descriptor_index"] == 1
        )
        self.assertEqual(rotator["candidate_channel_counts"], [2, 0, 0, 0, 0])
        broadened_inventory = census[
            "ancestry_covered_literal_turret_active_candidate_channel_inventory"
        ]
        self.assertEqual(
            [
                (
                    descriptor["descriptor_index"],
                    descriptor["candidate_channel_key_counts"],
                    descriptor["structural_relation"],
                )
                for descriptor in broadened_inventory["descriptors"]
                if descriptor["descriptor_index"] in (1, 3)
            ],
            [
                (1, [2, 0, 0, 0, 0], "strict_ancestor_distance_1"),
                (3, [2, 0, 0, 0, 0], "strict_ancestor_distance_3"),
            ],
        )
        relationships = anchor["same_subname_structural_relationship_coverage"]
        self.assertEqual(
            relationships["exact_matching_selector_connections"], ["Connection01"]
        )
        self.assertEqual(
            [
                (
                    descriptor["descriptor_index"],
                    descriptor["source_connection"],
                    descriptor["root_to_source_connection_path"],
                    descriptor["strict_ancestor_selector_distances"],
                )
                for descriptor in relationships["descriptor_relationships"]
            ],
            [
                (1, "Connection03", ["Connection01", "Connection03"], [1]),
                (
                    3,
                    "Connection05",
                    ["Connection01", "Connection03", "Connection04", "Connection05"],
                    [3],
                ),
            ],
        )
        self.assertEqual(
            rotator["candidate_channels"][0]["records"][0]["raw_bits"][1],
            "0x41a00000",
        )
        self.assertEqual(
            len(rotator["candidate_channels"][0]["records"][0]["raw_bits"]),
            32,
        )
        self.assertEqual(
            anchor["endpoint_resolution"][
                "production_matching_endpoint_connections"
            ],
            ["con_laser_02"],
        )
        self.assertTrue(anchor["endpoint_resolution"]["exact_unique_match"])
        self.assertEqual(
            anchor["literal_turret_active_candidate_channel_contributions"],
            {
                "contributing": ["candidate_channel_0"],
                "not_contributing": [
                    "candidate_channel_1",
                    "candidate_channel_2",
                    "candidate_channel_3",
                    "candidate_channel_4",
                ],
            },
        )
        self.assertTrue(
            all(
                row["trace_status"] != "UNTRACED"
                for row in anchor["formula_constant_provenance"]
            )
        )

        altered_formula = copy.deepcopy(production_formula)
        altered_formula["downstream_vector"][0] = 21.0
        altered = _evaluate_paranid_l_beam_trace(
            source_trace_bundle,
            production_formula=altered_formula,
            trace_spec=trace_spec,
        )
        self.assertIn("formula_numeric_mismatch", altered["failure_codes"])

        wrong_descriptor = copy.deepcopy(trace_spec)
        wrong_descriptor["barrel_active_descriptor"]["descriptor_index"] = 2
        descriptor_failure = _evaluate_paranid_l_beam_trace(
            source_trace_bundle,
            production_formula=production_formula,
            trace_spec=wrong_descriptor,
        )
        self.assertIn("ani_trace_unresolved", descriptor_failure["failure_codes"])

        wrong_connection = copy.deepcopy(trace_spec)
        wrong_connection["laser_connection"] = "con_laser_01"
        connection_failure = _evaluate_paranid_l_beam_trace(
            source_trace_bundle,
            production_formula=production_formula,
            trace_spec=wrong_connection,
        )
        self.assertIn("formula_numeric_mismatch", connection_failure["failure_codes"])

        wrong_slot = copy.deepcopy(trace_spec)
        wrong_slot["barrel_active_descriptor"]["triple_slot_indexes"] = [0, 2, 1]
        slot_failure = _evaluate_paranid_l_beam_trace(
            source_trace_bundle,
            production_formula=production_formula,
            trace_spec=wrong_slot,
        )
        self.assertIn("formula_numeric_mismatch", slot_failure["failure_codes"])

        untraced_formula = copy.deepcopy(production_formula)
        untraced_formula["untraced_constants"] = [99.0]
        untraced = _evaluate_paranid_l_beam_trace(
            source_trace_bundle,
            production_formula=untraced_formula,
            trace_spec=trace_spec,
        )
        self.assertIn("untraced_production_constant", untraced["failure_codes"])
        self.assertTrue(
            any(
                row["trace_status"] == "UNTRACED"
                for row in untraced["formula_constant_provenance"]
            )
        )


if __name__ == "__main__":
    unittest.main()
