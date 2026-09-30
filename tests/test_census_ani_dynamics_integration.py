#!/usr/bin/env python3
"""Focused synthetic ANI dynamics integration tests for the Issue #72 A2.1 census."""
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
    _candidate_key_record,
    _macros,
    _source_roots,
    _write,
    build_census,
)


class CensusAniDynamicsIntegrationTests(unittest.TestCase):
    def test_candidate_channel_dynamics_are_deduplicated_separate_and_raw_bit_exact(self) -> None:
        def record(
            first: float, second: float, third: float, later_slot: int = 0
        ) -> bytes:
            values: list[float | int] = [0] * 32
            values[0:4] = [first, second, third, later_slot]
            return _candidate_key_record(tuple(values))

        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/conventional"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="ConventionalPart"/></parts></connection>
                      <connection name="EndpointA" tags="laser" parent="ConventionalPart"/>
                      <connection name="EndpointB" tags="laser" parent="ConventionalPart"/>
                    </connections>
                  </component>
                  <component name="conventional_component_b" class="turret">
                    <source geometry="geometry/conventional_b"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="ConventionalPartB"/></parts></connection>
                      <connection name="Endpoint" tags="laser" parent="ConventionalPartB"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/missile"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="MissilePart"/></parts></connection>
                      <connection name="Endpoint" tags="rocket" parent="MissilePart"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("conventional_macro", "turret", "conventional_component"),
                    ("conventional_macro_b", "turret", "conventional_component_b"),
                    ("missile_macro", "missileturret", "missile_component"),
                ),
            )
            (roots["base"] / "geometry/conventional.ANI").write_bytes(
                _ani_bytes(
                    ("ConventionalPart", "Selected", 0, 1, 2, 2, 0),
                    key_data=(
                        record(9.0, 8.0, 7.0)
                        + record(1.0, 2.0, 3.0, 1)
                        + record(1.0, 2.0, 3.0, 2)
                        + record(+0.0, 4.0, 5.0)
                        + record(-0.0, 4.0, 5.0)
                    ),
                )
            )
            (roots["base"] / "geometry/conventional_b.ANI").write_bytes(
                _ani_bytes(("ConventionalPartB", "Selected", 0, 0, 0, 0, 0))
            )
            (roots["base"] / "geometry/missile.ANI").write_bytes(
                _ani_bytes(
                    ("MissilePart", "Selected", 1, 0, 0, 0, 0),
                    key_data=record(6.0, 5.0, 4.0),
                )
            )
            dynamics = build_census(roots)[
                "selected_descriptor_candidate_channel_dynamics"
            ]

        self.assertEqual(dynamics["evidence_classification"], "inference")
        self.assertEqual(
            dynamics["candidate_channel_ownership_order"][
                "evidence_classification"
            ],
            "third-party-technique",
        )
        conventional = dynamics["conventional"]
        missile = dynamics["missileturret"]
        self.assertEqual(conventional["selected_descriptor_memberships"], 3)
        self.assertEqual(conventional["unique_selected_descriptors"], 2)
        self.assertEqual(conventional["candidate_assigned_key_records"], 5)
        self.assertEqual(missile["selected_descriptor_memberships"], 1)
        self.assertEqual(missile["unique_selected_descriptors"], 1)
        self.assertEqual(missile["candidate_assigned_key_records"], 1)

        zero = {"descriptor_count": 0, "key_record_count": 0}
        self.assertEqual(
            conventional["candidate_channels"],
            [
                {
                    "candidate_channel_id": "candidate_channel_0",
                    "candidate_channel_count_field_index": 0,
                    "classifications": {
                        "zero_keys": {"descriptor_count": 2, "key_record_count": 0},
                        "one_key": zero,
                        "multiple_keys_identical_raw_bit_triples": zero,
                        "multiple_keys_changing_raw_bit_triples": zero,
                    },
                },
                {
                    "candidate_channel_id": "candidate_channel_1",
                    "candidate_channel_count_field_index": 1,
                    "classifications": {
                        "zero_keys": {"descriptor_count": 1, "key_record_count": 0},
                        "one_key": {"descriptor_count": 1, "key_record_count": 1},
                        "multiple_keys_identical_raw_bit_triples": zero,
                        "multiple_keys_changing_raw_bit_triples": zero,
                    },
                },
                {
                    "candidate_channel_id": "candidate_channel_2",
                    "candidate_channel_count_field_index": 2,
                    "classifications": {
                        "zero_keys": {"descriptor_count": 1, "key_record_count": 0},
                        "one_key": zero,
                        "multiple_keys_identical_raw_bit_triples": {
                            "descriptor_count": 1,
                            "key_record_count": 2,
                        },
                        "multiple_keys_changing_raw_bit_triples": zero,
                    },
                },
                {
                    "candidate_channel_id": "candidate_channel_3",
                    "candidate_channel_count_field_index": 3,
                    "classifications": {
                        "zero_keys": {"descriptor_count": 1, "key_record_count": 0},
                        "one_key": zero,
                        "multiple_keys_identical_raw_bit_triples": zero,
                        "multiple_keys_changing_raw_bit_triples": {
                            "descriptor_count": 1,
                            "key_record_count": 2,
                        },
                    },
                },
                {
                    "candidate_channel_id": "candidate_channel_4",
                    "candidate_channel_count_field_index": 4,
                    "classifications": {
                        "zero_keys": {"descriptor_count": 2, "key_record_count": 0},
                        "one_key": zero,
                        "multiple_keys_identical_raw_bit_triples": zero,
                        "multiple_keys_changing_raw_bit_triples": zero,
                    },
                },
            ],
        )
        self.assertEqual(
            missile["candidate_channels"][0]["classifications"],
            {
                "zero_keys": zero,
                "one_key": {"descriptor_count": 1, "key_record_count": 1},
                "multiple_keys_identical_raw_bit_triples": zero,
                "multiple_keys_changing_raw_bit_triples": zero,
            },
        )
        for candidate_channel in missile["candidate_channels"][1:]:
            self.assertEqual(
                candidate_channel["classifications"]["zero_keys"],
                {"descriptor_count": 1, "key_record_count": 0},
            )
        rendered_dynamics = render_json(dynamics).lower()
        for unsupported_name in (
            "time",
            "interpolation",
            "transform",
            "position",
            "rotation",
            "scale",
            "pre_scale",
            "post_scale",
        ):
            self.assertNotIn(unsupported_name, rendered_dynamics)

    def test_conventional_multi_key_candidate_metadata_patterns_are_raw_and_separate(self) -> None:
        def record(
            main: tuple[float, float, float],
            enums: tuple[int, int, int],
            slot_024: float,
            later: dict[int, float | int] | None = None,
        ) -> bytes:
            values: list[float | int] = [0] * 32
            values[0:3] = main
            values[3:6] = enums
            values[6] = slot_024
            for slot_index, value in (later or {}).items():
                values[slot_index] = value
            return _candidate_key_record(tuple(values))

        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/conventional"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="ConventionalPart"/></parts></connection>
                      <connection name="EndpointA" tags="laser" parent="ConventionalPart"/>
                      <connection name="EndpointB" tags="laser" parent="ConventionalPart"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/missile"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="MissilePart"/></parts></connection>
                      <connection name="Endpoint" tags="rocket" parent="MissilePart"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    ("conventional_macro", "turret", "conventional_component"),
                    ("missile_macro", "missileturret", "missile_component"),
                ),
            )
            (roots["base"] / "geometry/conventional.ANI").write_bytes(
                _ani_bytes(
                    ("ConventionalPart", "Selected", 2, 2, 3, 0, 0),
                    key_data=(
                        record((1.0, 2.0, 3.0), (1, 2, 3), 1.0)
                        + record(
                            (1.0, 2.0, 3.0),
                            (1, 2, 4),
                            2.0,
                            {7: 9.0, 19: 5.0},
                        )
                        + record(
                            (0.0, 0.0, 0.0),
                            (5, 6, 7),
                            3.0,
                            {7: 4.0, 19: 8.0},
                        )
                        + record(
                            (1.0, 0.0, 0.0),
                            (5, 6, 7),
                            3.0,
                            {7: 4.0, 19: 8.0},
                        )
                        + record((7.0, 8.0, 9.0), (-1, 0, 1), 2.0)
                        + record((7.0, 8.0, 9.0), (-1, 0, 1), 1.0)
                        + record((7.0, 8.0, 9.0), (-1, 0, 1), 3.0)
                    ),
                )
            )
            (roots["base"] / "geometry/missile.ANI").write_bytes(
                _ani_bytes(
                    ("MissilePart", "Selected", 2, 0, 0, 0, 0),
                    key_data=(
                        record((4.0, 5.0, 6.0), (8, 9, 10), 4.0)
                        + record((4.0, 5.0, 6.0), (8, 9, 10), 5.0)
                    ),
                )
            )
            inventory = build_census(roots)[
                "selected_conventional_candidate_channel_metadata_patterns"
            ]

        self.assertEqual(inventory["evidence_classification"], "inference")
        self.assertEqual(
            inventory["candidate_field_layout"]["evidence_classification"],
            "third-party-technique",
        )
        conventional = inventory["conventional"]
        missile = inventory["missileturret_accounting"]
        self.assertEqual(conventional["selected_descriptor_memberships"], 2)
        self.assertEqual(conventional["unique_selected_descriptors"], 1)
        self.assertEqual(missile["selected_descriptor_memberships"], 1)
        self.assertEqual(missile["unique_selected_descriptors"], 1)

        channels = {
            channel["candidate_channel_id"]: channel
            for channel in conventional["candidate_channels"]
        }
        channel_0 = channels["candidate_channel_0"]["multiple_key_descriptors"][
            "identical_raw_bit_triples"
        ]
        self.assertEqual(channel_0["descriptor_count"], 1)
        self.assertEqual(channel_0["key_record_count"], 2)
        self.assertEqual(
            channel_0["candidate_enum_triplet_distribution"],
            [
                {
                    "raw_bits": ["0x00000001", "0x00000002", "0x00000003"],
                    "candidate_values": [1, 2, 3],
                    "record_count": 1,
                },
                {
                    "raw_bits": ["0x00000001", "0x00000002", "0x00000004"],
                    "candidate_values": [1, 2, 4],
                    "record_count": 1,
                },
            ],
        )
        self.assertEqual(
            channel_0["slot_024"]["descriptor_numeric_ordering_shapes"],
            {
                "all_equal": {"descriptor_count": 0, "key_record_count": 0},
                "strictly_increasing": {
                    "descriptor_count": 1,
                    "key_record_count": 2,
                },
                "nondecreasing": {"descriptor_count": 0, "key_record_count": 0},
                "other": {"descriptor_count": 0, "key_record_count": 0},
            },
        )
        slot_028 = channel_0["slots_028_072"][0]
        self.assertEqual(slot_028["raw_bit_zero_count"], 1)
        self.assertEqual(slot_028["raw_bit_nonzero_count"], 1)
        self.assertEqual(slot_028["distinct_raw_bit_pattern_count"], 2)
        self.assertEqual(slot_028["descriptors_with_differing_raw_bits"], 1)
        slot_076 = channel_0["slots_076_124"][0]
        self.assertEqual(slot_076["raw_bit_zero_count"], 1)
        self.assertEqual(slot_076["raw_bit_nonzero_count"], 1)
        self.assertEqual(slot_076["descriptors_with_differing_raw_bits"], 1)

        channel_1 = channels["candidate_channel_1"]["multiple_key_descriptors"][
            "changing_raw_bit_triples"
        ]
        self.assertEqual(channel_1["descriptor_count"], 1)
        self.assertEqual(
            channel_1["slot_024"]["descriptor_numeric_ordering_shapes"][
                "all_equal"
            ],
            {"descriptor_count": 1, "key_record_count": 2},
        )
        self.assertEqual(
            channel_1["slots_028_072"][0]["descriptors_with_constant_raw_bits"],
            1,
        )
        self.assertEqual(
            channel_1["slots_076_124"][0]["descriptors_with_constant_raw_bits"],
            1,
        )

        channel_2 = channels["candidate_channel_2"]["multiple_key_descriptors"][
            "identical_raw_bit_triples"
        ]
        self.assertEqual(
            channel_2["slot_024"]["descriptor_numeric_ordering_shapes"]["other"],
            {"descriptor_count": 1, "key_record_count": 3},
        )
        missile_channel_0 = missile["candidate_channels"][0]
        self.assertEqual(
            missile_channel_0["multiple_key_descriptors"],
            {
                "identical_raw_bit_triples": {
                    "descriptor_count": 1,
                    "key_record_count": 2,
                },
                "changing_raw_bit_triples": {
                    "descriptor_count": 0,
                    "key_record_count": 0,
                },
            },
        )
        rendered_inventory = render_json(inventory).lower()
        for unsupported_name in (
            "time",
            "interpolation",
            "control_point",
            "tangent",
            "derivative",
            "position",
            "rotation",
            "scale",
        ):
            self.assertNotIn(unsupported_name, rendered_inventory)


if __name__ == "__main__":
    unittest.main()
