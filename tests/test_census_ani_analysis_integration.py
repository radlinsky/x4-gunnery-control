#!/usr/bin/env python3
"""Focused synthetic ANI analysis integration tests for the Issue #72 A2.1 census."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).parent))

from census_ani_parser import (  # noqa: E402
    _ANI_KEY_RECORD_CANDIDATE_SLOTS,
    _parse_ani_descriptors,
    AniDescriptorError,
)
from census_common import CensusError, render_json  # noqa: E402
from support.census_fixture import (  # noqa: E402
    _ani_bytes,
    _candidate_key_record,
    _components,
    _macros,
    _source_roots,
    _write,
    build_census,
)


class CensusAniAnalysisIntegrationTests(unittest.TestCase):

    def test_ani_key_ranges_follow_descriptor_table_and_channel_count_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "mixed.ANI"
            path.write_bytes(
                _ani_bytes(
                    ("ZuluPart", "Second", 1, 0, 1, 0, 0),
                    ("AlphaPart", "First", 0, 2, 0, 0, 1),
                )
            )

            descriptors = _parse_ani_descriptors(path)

            self.assertEqual(
                [(item["descriptor_index"], item["part"]) for item in descriptors],
                [(0, "ZuluPart"), (1, "AlphaPart")],
            )
            self.assertEqual(
                descriptors[0]["key_data"],
                {
                    "record_range": {"start": 0, "end_exclusive": 2},
                    "byte_range": {"start": 336, "end_exclusive": 592},
                    "channels": {
                        "position": {
                            "record_count": 1,
                            "record_range": {"start": 0, "end_exclusive": 1},
                            "byte_range": {"start": 336, "end_exclusive": 464},
                        },
                        "rotation": {
                            "record_count": 0,
                            "record_range": {"start": 1, "end_exclusive": 1},
                            "byte_range": {"start": 464, "end_exclusive": 464},
                        },
                        "scale": {
                            "record_count": 1,
                            "record_range": {"start": 1, "end_exclusive": 2},
                            "byte_range": {"start": 464, "end_exclusive": 592},
                        },
                        "pre_scale": {
                            "record_count": 0,
                            "record_range": {"start": 2, "end_exclusive": 2},
                            "byte_range": {"start": 592, "end_exclusive": 592},
                        },
                        "post_scale": {
                            "record_count": 0,
                            "record_range": {"start": 2, "end_exclusive": 2},
                            "byte_range": {"start": 592, "end_exclusive": 592},
                        },
                    },
                },
            )
            self.assertEqual(
                descriptors[1]["key_data"],
                {
                    "record_range": {"start": 2, "end_exclusive": 5},
                    "byte_range": {"start": 592, "end_exclusive": 976},
                    "channels": {
                        "position": {
                            "record_count": 0,
                            "record_range": {"start": 2, "end_exclusive": 2},
                            "byte_range": {"start": 592, "end_exclusive": 592},
                        },
                        "rotation": {
                            "record_count": 2,
                            "record_range": {"start": 2, "end_exclusive": 4},
                            "byte_range": {"start": 592, "end_exclusive": 848},
                        },
                        "scale": {
                            "record_count": 0,
                            "record_range": {"start": 4, "end_exclusive": 4},
                            "byte_range": {"start": 848, "end_exclusive": 848},
                        },
                        "pre_scale": {
                            "record_count": 0,
                            "record_range": {"start": 4, "end_exclusive": 4},
                            "byte_range": {"start": 848, "end_exclusive": 848},
                        },
                        "post_scale": {
                            "record_count": 1,
                            "record_range": {"start": 4, "end_exclusive": 5},
                            "byte_range": {"start": 848, "end_exclusive": 976},
                        },
                    },
                },
            )

    def test_candidate_key_record_slot_map_covers_all_128_bytes_and_parses_raw_values(self) -> None:
        expected_types = (
            ["float32_le"] * 3
            + ["enum32_le"] * 3
            + ["float32_le"] * 18
            + ["int32_le"]
            + ["float32_le"] * 6
            + ["uint32_le"]
        )
        self.assertEqual(len(_ANI_KEY_RECORD_CANDIDATE_SLOTS), 32)
        self.assertEqual(
            [slot["byte_offset"] for slot in _ANI_KEY_RECORD_CANDIDATE_SLOTS],
            list(range(0, 128, 4)),
        )
        self.assertEqual(
            [slot["width_bytes"] for slot in _ANI_KEY_RECORD_CANDIDATE_SLOTS],
            [4] * 32,
        )
        self.assertEqual(
            [slot["candidate_type"] for slot in _ANI_KEY_RECORD_CANDIDATE_SLOTS],
            expected_types,
        )
        self.assertEqual(
            sum(int(slot["width_bytes"]) for slot in _ANI_KEY_RECORD_CANDIDATE_SLOTS),
            128,
        )

        values = tuple(
            float(index) if candidate_type == "float32_le" else index
            for index, candidate_type in enumerate(expected_types)
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "typed.ANI"
            path.write_bytes(
                _ani_bytes(
                    ("Part", "Sub", 1, 0, 0, 0, 0),
                    key_data=_candidate_key_record(values),
                )
            )
            descriptor = _parse_ani_descriptors(path)[0]

        raw_record = descriptor["_candidate_raw_key_records"][0]
        self.assertEqual(raw_record["record_index"], 0)
        self.assertEqual(raw_record["byte_offset"], 176)
        self.assertEqual(raw_record["raw_values"], list(values))

    def test_ani_key_section_wrong_width_truncation_and_extra_bytes_fail_closed(self) -> None:
        cases = (
            (
                "truncated_record",
                _ani_bytes(("Part", "Sub", 1, 0, 0, 0, 0), key_data=b"x" * 127),
                "truncated_ani_key_section",
            ),
            (
                "impossible_count",
                _ani_bytes(("Part", "Sub", 0xFFFFFFFF, 0, 0, 0, 0), key_data=b""),
                "truncated_ani_key_section",
            ),
            (
                "unconsumed_byte",
                _ani_bytes(("Part", "Sub"), key_data=b"x"),
                "unconsumed_ani_key_section",
            ),
        )
        for label, data, code in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "invalid.ANI"
                path.write_bytes(data)
                with self.assertRaises(AniDescriptorError) as caught:
                    _parse_ani_descriptors(path)
                self.assertEqual(caught.exception.code, code)

    def test_file_size_invariant_is_blind_to_key_order(self) -> None:
        # Two ANIs with the same total key-record count but different descriptor
        # and channel orderings occupy identical file sizes and both satisfy the
        # structural parser. That is exactly why the invariant cannot corroborate
        # order: it is a sum, and a sum does not see permutation.
        with tempfile.TemporaryDirectory() as tmp:
            first = Path(tmp) / "first.ANI"
            second = Path(tmp) / "second.ANI"
            first.write_bytes(
                _ani_bytes(
                    ("Alpha", "One", 3, 0, 0, 0, 0),
                    ("Bravo", "Two", 0, 0, 2, 0, 0),
                )
            )
            second.write_bytes(
                _ani_bytes(
                    ("Bravo", "Two", 0, 0, 0, 0, 2),
                    ("Alpha", "One", 0, 3, 0, 0, 0),
                )
            )
            self.assertEqual(first.stat().st_size, second.stat().st_size)
            # Both parse cleanly; the invariant alone cannot tell them apart.
            self.assertEqual(len(_parse_ani_descriptors(first)), 2)
            self.assertEqual(len(_parse_ani_descriptors(second)), 2)

    def test_duplicate_exact_ani_descriptor_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(roots["base"], "assets/components.xml", _components("component_a"))
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(("Part", "Sub"), ("Part", "Sub"))
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("duplicate_ani_descriptor", caught.exception.codes)

    def test_truncated_and_unsupported_ani_fail_closed(self) -> None:
        for label, ani, code in (
            ("truncated_header", b"short", "truncated_ani_header"),
            ("truncated_descriptors", _ani_bytes(("Part", "Sub"))[:-1], "truncated_ani_descriptor_section"),
            ("unsupported_version", _ani_bytes(version=2), "unsupported_ani_layout"),
            ("header_padding", _ani_bytes(header_padding=1), "unsupported_ani_layout"),
            ("key_offset", _ani_bytes(key_offset=17), "unsupported_ani_layout"),
            (
                "descriptor_padding",
                _ani_bytes(("Part", "Sub"), descriptor_padding=(1, 0)),
                "unsupported_ani_layout",
            ),
        ):
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                roots = _source_roots(Path(tmp))
                _write(roots["base"], "assets/components.xml", _components("component_a"))
                _write(
                    roots["base"],
                    "assets/macros.xml",
                    _macros(("a_macro", "turret", "component_a")),
                )
                (roots["base"] / "geometry/component_a.ANI").write_bytes(ani)
                with self.assertRaises(CensusError) as caught:
                    build_census(roots)
                self.assertIn(code, caught.exception.codes)

    def test_invalid_ani_descriptor_strings_fail_closed(self) -> None:
        valid = _ani_bytes(("Part", "Sub"))
        no_terminator = bytearray(valid)
        no_terminator[16:80] = b"A" * 64
        non_ascii = bytearray(valid)
        non_ascii[16] = 0xFF
        non_printable = bytearray(valid)
        non_printable[16] = 0x01
        for label, ani in (
            ("empty", _ani_bytes(("", "Sub"))),
            ("unterminated", bytes(no_terminator)),
            ("non_ascii", bytes(non_ascii)),
            ("non_printable", bytes(non_printable)),
        ):
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                roots = _source_roots(Path(tmp))
                _write(roots["base"], "assets/components.xml", _components("component_a"))
                _write(
                    roots["base"],
                    "assets/macros.xml",
                    _macros(("a_macro", "turret", "component_a")),
                )
                (roots["base"] / "geometry/component_a.ANI").write_bytes(ani)
                with self.assertRaises(CensusError) as caught:
                    build_census(roots)
                self.assertIn("invalid_ani_descriptor_string", caught.exception.codes)

    def test_channel_1_restriction_correlation_uses_exact_source_connections_and_masks(self) -> None:
        def main_triple_record(x: float, y: float, z: float) -> bytes:
            values: list[float | int] = [0] * 32
            values[0:3] = [x, y, z]
            return _candidate_key_record(tuple(values))

        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="correlation_component" class="turret">
                    <source geometry="geometry/correlation"/>
                    <connections>
                      <connection name="WrongAncestor">
                        <restrictions><restriction type="rotation_y"><limits><min value="-90"/><max value="90"/></limits></restriction></restrictions>
                        <parts><part name="AncestorPart"/></parts>
                      </connection>
                      <connection name="ExactA" parent="AncestorPart">
                        <animations><animation name="Selected"/></animations>
                        <restrictions><restriction type="rotation_x"><limits><min value="-10 "/><max value=" 20"/></limits></restriction></restrictions>
                        <parts><part name="PartA"/></parts>
                      </connection>
                      <connection name="EndpointA1" tags="laser" parent="PartA"/>
                      <connection name="EndpointA2" tags="laser" parent="PartA"/>
                      <connection name="ExactB">
                        <animations><animation name="Selected"/></animations>
                        <restrictions><restriction type="rotation_x"/><restriction type="rotation_y"><limits><min value="-5"/></limits></restriction></restrictions>
                        <parts><part name="PartB"/></parts>
                      </connection>
                      <connection name="EndpointB" tags="laser" parent="PartB"/>
                      <connection name="ExactC">
                        <animations><animation name="Selected"/></animations>
                        <parts><part name="PartC"/></parts>
                      </connection>
                      <connection name="EndpointC" tags="laser" parent="PartC"/>
                      <connection name="ControlD">
                        <animations><animation name="Selected"/></animations>
                        <restrictions><restriction type="rotation_y"/></restrictions>
                        <parts><part name="PartD"/></parts>
                      </connection>
                      <connection name="EndpointD" tags="laser" parent="PartD"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(
                    (
                        "correlation_macro",
                        "turret",
                        "correlation_component",
                    )
                ),
            )
            (roots["base"] / "geometry/correlation.ANI").write_bytes(
                _ani_bytes(
                    ("PartA", "Selected", 0, 2, 0, 0, 0),
                    ("PartB", "Selected", 0, 2, 0, 0, 0),
                    ("PartC", "Selected", 0, 2, 0, 0, 0),
                    ("PartD", "Selected", 0, 2, 0, 0, 0),
                    key_data=b"".join(
                        (
                            main_triple_record(1.0, 3.0, 4.0),
                            main_triple_record(2.0, 3.0, 5.0),
                            main_triple_record(0.0, 0.0, 0.0),
                            main_triple_record(0.0, 1.0, 0.0),
                            main_triple_record(1.0, 1.0, 1.0),
                            main_triple_record(2.0, 2.0, 2.0),
                            main_triple_record(7.0, 8.0, 9.0),
                            main_triple_record(7.0, 8.0, 9.0),
                        )
                    ),
                )
            )
            report = build_census(roots)

        component = report["component_to_macros"][0]
        connections = {
            connection["name"]: connection for connection in component["connections"]
        }
        self.assertEqual(
            connections["ExactA"]["authored_restrictions"],
            [
                {
                    "source_connection": "ExactA",
                    "restriction_index": 0,
                    "type_token": "rotation_x",
                    "type_token_raw_text": "rotation_x",
                    "authored_min": {
                        "raw_text": "-10 ",
                        "candidate_numeric_value": -10.0,
                    },
                    "authored_max": {
                        "raw_text": " 20",
                        "candidate_numeric_value": 20.0,
                    },
                    "evidence_classification": "shipped-source",
                }
            ],
        )
        self.assertEqual(
            connections["ExactB"]["authored_restrictions"][0]["authored_min"],
            None,
        )
        self.assertEqual(
            connections["ExactB"]["authored_restrictions"][1]["authored_max"],
            None,
        )

        study = report["candidate_channel_1_authored_restriction_correlation"]
        self.assertEqual(study["evidence_classification"], "inference")
        self.assertEqual(
            study["identity_join_evidence_classification"], "shipped-source"
        )
        self.assertEqual(
            study["x4converter_label_lead"],
            {
                "label": "rotation_euler",
                "evidence_classification": "third-party-technique",
                "semantic_promotion": "not_permitted_by_this_study",
            },
        )
        primary = study["primary_changing_main_triple_cohort"]
        control = study["identical_main_triple_control_cohort"]
        self.assertEqual(primary["selected_descriptor_memberships"], 4)
        self.assertEqual(primary["unique_descriptor_count"], 3)
        self.assertEqual(control["selected_descriptor_memberships"], 1)
        self.assertEqual(control["unique_descriptor_count"], 1)

        records = {record["part"]: record for record in primary["descriptors"]}
        self.assertEqual(records["PartA"]["source_connection"], "ExactA")
        self.assertEqual(records["PartA"]["restriction_count"], 1)
        self.assertEqual(records["PartA"]["restriction_type_tokens"], ["rotation_x"])
        self.assertEqual(records["PartA"]["changing_component_mask"], "101")
        self.assertEqual(
            [
                component["changes_by_exact_raw_bits"]
                for component in records["PartA"]["candidate_main_components"]
            ],
            [True, False, True],
        )
        self.assertEqual(
            records["PartA"]["candidate_main_components"][0]["raw_bit_sequence"],
            ["0x3f800000", "0x40000000"],
        )
        self.assertEqual(
            records["PartA"]["candidate_main_components"][0][
                "candidate_numeric_extrema"
            ],
            {"finite_count": 2, "non_finite_count": 0, "minimum": 1.0, "maximum": 2.0},
        )
        self.assertNotIn("rotation_y", records["PartA"]["restriction_type_tokens"])
        self.assertEqual(records["PartA"]["selected_endpoint_membership_count"], 2)
        self.assertEqual(records["PartB"]["restriction_count"], 2)
        self.assertEqual(records["PartC"]["restriction_count"], 0)

        self.assertEqual(
            primary["restriction_type_token_by_changing_component_mask"],
            [
                {
                    "restriction_type_token": None,
                    "changing_component_mask": "111",
                    "restriction_record_or_unrestricted_descriptor_count": 1,
                },
                {
                    "restriction_type_token": "rotation_x",
                    "changing_component_mask": "010",
                    "restriction_record_or_unrestricted_descriptor_count": 1,
                },
                {
                    "restriction_type_token": "rotation_x",
                    "changing_component_mask": "101",
                    "restriction_record_or_unrestricted_descriptor_count": 1,
                },
                {
                    "restriction_type_token": "rotation_y",
                    "changing_component_mask": "010",
                    "restriction_record_or_unrestricted_descriptor_count": 1,
                },
            ],
        )
        self.assertEqual(
            primary["unique_source_connection_restriction_counts"],
            {"restricted": 2, "unrestricted": 1},
        )
        self.assertEqual(
            primary["ambiguous_or_multiple_restriction_cases"],
            [
                {
                    "component": "correlation_component",
                    "descriptor_index": 1,
                    "source_connection": "ExactB",
                    "restriction_count": 2,
                    "restriction_type_tokens": ["rotation_x", "rotation_y"],
                    "reasons": ["multiple_authored_restrictions"],
                }
            ],
        )
        self.assertEqual(
            control["descriptors"][0]["changing_component_mask"], "000"
        )
        self.assertEqual(
            control["descriptors"][0]["restriction_type_tokens"], ["rotation_y"]
        )
        rotation_x = study["single_rotation_x_or_y_restriction_comparisons"][
            "rotation_x"
        ]
        self.assertEqual(rotation_x["primary_descriptor_count"], 1)
        self.assertEqual(rotation_x["corresponding_candidate_component"], "slot_000")
        self.assertEqual(rotation_x["corresponding_component_changed_count"], 1)
        self.assertEqual(
            rotation_x["other_component_changed_counts"],
            {"slot_004": 0, "slot_008": 1},
        )
        self.assertEqual(
            study["semantic_discriminator_assessment"]["status"],
            "not_strong_one_to_one",
        )
        rendered = render_json(study)
        self.assertNotIn('"candidate_channel_1_label": "rotation"', rendered)
        self.assertNotIn('"evidence_classification": "live-tested"', rendered)

    def test_descriptor_offset_148_inventory_and_slot_024_relationships_are_exact(self) -> None:
        def record(slot_024: float) -> bytes:
            values: list[float | int] = [0] * 32
            values[6] = slot_024
            return _candidate_key_record(tuple(values))

        with tempfile.TemporaryDirectory() as tmp:
            signed_zero_path = Path(tmp) / "descriptor_signed_zero.ANI"
            signed_zero_path.write_bytes(
                _ani_bytes(
                    ("PlusZero", "Selected", 0, 0, 0, 0, 0, 0x00000000),
                    ("MinusZero", "Selected", 0, 0, 0, 0, 0, 0x80000000),
                )
            )
            signed_zero_descriptors = _parse_ani_descriptors(signed_zero_path)
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_a" class="turret">
                    <source geometry="geometry/offset_a"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="PartA"/></parts></connection>
                      <connection name="EndpointA" tags="laser" parent="PartA"/>
                      <connection name="EndpointB" tags="laser" parent="PartA"/>
                    </connections>
                  </component>
                  <component name="conventional_b" class="turret">
                    <source geometry="geometry/offset_b"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="PartB"/></parts></connection>
                      <connection name="Endpoint" tags="laser" parent="PartB"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/offset_missile"/>
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
                    ("conventional_a_macro", "turret", "conventional_a"),
                    ("conventional_b_macro", "turret", "conventional_b"),
                    ("missile_macro", "missileturret", "missile_component"),
                ),
            )
            (roots["base"] / "geometry/offset_a.ANI").write_bytes(
                _ani_bytes(
                    ("PartA", "Selected", 0, 1, 2, 2, 2, 0x80000000),
                    key_data=b"".join(
                        record(value)
                        for value in (+0.0, -1.0, -0.0, -0.0, 1.0, -1.0, 1.0)
                    ),
                )
            )
            (roots["base"] / "geometry/offset_b.ANI").write_bytes(
                _ani_bytes(
                    ("PartB", "Selected", 2, 2, 2, 2, 0, 0x40400000),
                    key_data=b"".join(
                        record(value)
                        for value in (1.0, 2.0, 4.0, 5.0, 3.0, 3.0, 1.0, 3.0)
                    ),
                )
            )
            (roots["base"] / "geometry/offset_missile.ANI").write_bytes(
                _ani_bytes(
                    ("MissilePart", "Selected", 0, 0, 0, 0, 0, 0x7FC00001)
                )
            )
            report = build_census(roots)

        self.assertEqual(
            [
                descriptor["descriptor_offset_148"]["raw_bits"]
                for descriptor in signed_zero_descriptors
            ],
            ["0x00000000", "0x80000000"],
        )
        self.assertEqual(
            [
                descriptor["descriptor_offset_148"]["candidate_float32_decode"][
                    "value"
                ]
                for descriptor in signed_zero_descriptors
            ],
            [+0.0, -0.0],
        )
        self.assertEqual(
            len(
                {
                    descriptor["descriptor_offset_148"]["raw_bits"]
                    for descriptor in signed_zero_descriptors
                }
            ),
            2,
        )

        component_a = next(
            record
            for record in report["component_to_macros"]
            if record["component"] == "conventional_a"
        )
        descriptor_field = component_a["ani_descriptors"][0]["descriptor_offset_148"]
        self.assertEqual(descriptor_field["byte_offset_within_descriptor"], 148)
        self.assertEqual(descriptor_field["width_bytes"], 4)
        self.assertEqual(descriptor_field["raw_bits"], "0x80000000")
        self.assertEqual(
            descriptor_field["candidate_float32_decode"],
            {"kind": "finite", "value": -0.0},
        )
        self.assertEqual(
            descriptor_field["raw_bits_evidence_classification"], "shipped-source"
        )
        self.assertEqual(
            descriptor_field["candidate_decode_evidence_classification"],
            "third-party-technique",
        )
        self.assertNotIn("duration", descriptor_field)

        inventory = report[
            "selected_descriptor_offset_148_inventory_and_slot_024_relationships"
        ]
        self.assertEqual(inventory["evidence_classification"], "inference")
        self.assertEqual(inventory["engine_requiredness"], "unresolved")
        lead = inventory["x4converter_lead"]
        self.assertEqual(lead["evidence_classification"], "third-party-technique")
        self.assertEqual(lead["x4converter_member"], "Duration")
        self.assertEqual(lead["read_site"]["line_range_at_pinned_commit"], [21, 26])
        self.assertEqual(lead["write_site"]["line_range_at_pinned_commit"], [79, 84])
        self.assertEqual(lead["validation_report_site"]["line_range_at_pinned_commit"], [205, 207])
        self.assertEqual(lead["other_actual_use_sites"], [])
        self.assertEqual(lead["engine_requiredness"], "unresolved")

        conventional = inventory["conventional"]
        missile = inventory["missileturret"]
        self.assertEqual(conventional["selected_descriptor_memberships"], 3)
        self.assertEqual(conventional["unique_selected_descriptors"], 2)
        self.assertEqual(missile["selected_descriptor_memberships"], 1)
        self.assertEqual(missile["unique_selected_descriptors"], 1)
        self.assertEqual(
            conventional["offset_148_value_inventory"],
            {
                "descriptor_count": 2,
                "finite_count": 2,
                "non_finite_count": 0,
                "numeric_zero_count": 1,
                "numeric_nonzero_count": 1,
                "positive_zero_raw_bit_count": 0,
                "negative_zero_raw_bit_count": 1,
                "distinct_raw_bit_pattern_count": 2,
                "raw_bit_pattern_distribution_limit": 256,
                "raw_bit_pattern_distribution_is_complete": True,
                "raw_bit_pattern_distribution": [
                    {
                        "raw_bits": "0x40400000",
                        "candidate_float32_decode": {"kind": "finite", "value": 3.0},
                        "descriptor_count": 1,
                    },
                    {
                        "raw_bits": "0x80000000",
                        "candidate_float32_decode": {"kind": "finite", "value": -0.0},
                        "descriptor_count": 1,
                    },
                ],
            },
        )
        self.assertEqual(missile["offset_148_value_inventory"]["finite_count"], 0)
        self.assertEqual(missile["offset_148_value_inventory"]["non_finite_count"], 1)
        self.assertEqual(
            missile["offset_148_value_inventory"]["raw_bit_pattern_distribution"],
            [
                {
                    "raw_bits": "0x7fc00001",
                    "candidate_float32_decode": {"kind": "nan", "value": None},
                    "descriptor_count": 1,
                }
            ],
        )

        channels = {
            channel["candidate_channel_id"]: channel
            for channel in conventional["candidate_channel_slot_024_relationships"]
        }
        self.assertEqual(
            channels["candidate_channel_0"]["key_count_distribution"],
            {"no_keys": 1, "one_key": 0, "multiple_keys": 1},
        )
        self.assertEqual(
            channels["candidate_channel_0"]["numeric_relationship_distribution"],
            {
                "no_keys": 1,
                "non_finite": 0,
                "equals_both": 0,
                "equals_first": 0,
                "equals_last": 0,
                "greater_than_sequence_maximum": 1,
                "less_than_sequence_minimum": 0,
                "other": 0,
            },
        )
        self.assertEqual(
            channels["candidate_channel_1"]["key_count_distribution"],
            {"no_keys": 0, "one_key": 1, "multiple_keys": 1},
        )
        self.assertEqual(
            channels["candidate_channel_1"]["raw_bit_relationship_distribution"]["other"],
            2,
        )
        self.assertEqual(
            channels["candidate_channel_1"]["numeric_relationship_distribution"]["equals_both"],
            1,
        )
        self.assertEqual(
            channels["candidate_channel_1"]["numeric_relationship_distribution"]["less_than_sequence_minimum"],
            1,
        )
        self.assertEqual(
            channels["candidate_channel_2"]["raw_bit_relationship_distribution"],
            {
                "no_keys": 0,
                "equals_both": 1,
                "equals_first": 0,
                "equals_last": 1,
                "other": 0,
            },
        )
        self.assertEqual(
            channels["candidate_channel_3"]["numeric_relationship_distribution"],
            {
                "no_keys": 0,
                "non_finite": 0,
                "equals_both": 0,
                "equals_first": 1,
                "equals_last": 1,
                "greater_than_sequence_maximum": 0,
                "less_than_sequence_minimum": 0,
                "other": 0,
            },
        )
        self.assertEqual(
            channels["candidate_channel_4"]["numeric_relationship_distribution"]["other"],
            1,
        )
        self.assertEqual(
            channels["candidate_channel_4"]["numeric_relationship_distribution"]["no_keys"],
            1,
        )

        rendered = render_json(inventory).lower()
        self.assertNotIn('"evidence_classification": "live-tested"', rendered)
        self.assertNotIn('"semantic_status": "resolved"', rendered)
        self.assertNotIn('"semantic_status": "final"', rendered)
        self.assertEqual(inventory["semantic_claim"], "none")

    def test_selected_raw_slot_distributions_are_unique_separate_and_nonsemantic(self) -> None:
        conventional_first = [0] * 32
        conventional_second = [0] * 32
        conventional_second[0] = -0.0
        conventional_second[1] = 2.5
        conventional_second[3] = 7
        conventional_second[24] = -2
        conventional_second[31] = 9
        missile_values = [0] * 32
        missile_values[0] = float("nan")
        missile_values[1] = float("inf")
        missile_values[3] = -4
        missile_values[31] = 0xFFFFFFFF

        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/component_a"/>
                    <connections>
                      <connection name="Root"><animations><animation name="Selected"/></animations><parts><part name="PathPart"/></parts></connection>
                      <connection name="EndpointA" tags="laser" parent="PathPart"/>
                      <connection name="EndpointB" tags="laser" parent="PathPart"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/component_b"/>
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
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(
                    ("PathPart", "Selected", 2, 0, 0, 0, 0),
                    key_data=(
                        _candidate_key_record(tuple(conventional_first))
                        + _candidate_key_record(tuple(conventional_second))
                    ),
                )
            )
            (roots["base"] / "geometry/component_b.ANI").write_bytes(
                _ani_bytes(
                    ("MissilePart", "Selected", 0, 1, 0, 0, 0),
                    key_data=_candidate_key_record(tuple(missile_values)),
                )
            )
            inventory = build_census(roots)["ani_key_record_field_inventory"]

        layout = inventory["candidate_slot_layout"]
        self.assertEqual(layout["evidence_classification"], "third-party-technique")
        self.assertEqual(layout["record_size_bytes"], 128)
        self.assertEqual(layout["covered_byte_range"], {"start": 0, "end_exclusive": 128})
        self.assertEqual(layout["unaccounted_bytes"], [])
        self.assertEqual(layout["overlapping_bytes"], [])
        self.assertNotIn("time", render_json(inventory).lower())
        self.assertNotIn("interpolation", render_json(inventory).lower())
        self.assertNotIn("tangent", render_json(inventory).lower())
        self.assertNotIn("derivative", render_json(inventory).lower())

        distributions = inventory["candidate_assigned_shipped_value_distributions"]
        self.assertEqual(distributions["evidence_classification"], "inference")
        self.assertEqual(
            distributions["shipped_source_basis"]["evidence_classification"],
            "shipped-source",
        )
        self.assertEqual(
            distributions["candidate_decode_basis"]["evidence_classification"],
            "third-party-technique",
        )
        conventional = distributions["conventional"]
        missile = distributions["missileturret"]
        self.assertEqual(conventional["selected_descriptor_memberships"], 2)
        self.assertEqual(conventional["unique_selected_descriptors"], 1)
        self.assertEqual(conventional["candidate_assigned_key_records"], 2)
        self.assertEqual(missile["selected_descriptor_memberships"], 1)
        self.assertEqual(missile["unique_selected_descriptors"], 1)
        self.assertEqual(missile["candidate_assigned_key_records"], 1)

        conventional_slots = {slot["slot_id"]: slot for slot in conventional["slots"]}
        self.assertEqual(
            conventional_slots["slot_004"],
            {
                "slot_id": "slot_004",
                "byte_offset": 4,
                "width_bytes": 4,
                "candidate_type": "float32_le",
                "value_count": 2,
                "finite_count": 2,
                "non_finite_count": 0,
                "zero_count": 1,
                "nonzero_count": 1,
                "distinct_raw_bit_patterns": 2,
                "constant_raw_bits": None,
            },
        )
        self.assertEqual(
            conventional_slots["slot_012"]["integer_value_distribution"],
            [{"value": 0, "count": 1}, {"value": 7, "count": 1}],
        )
        self.assertEqual(
            conventional_slots["slot_096"]["integer_value_distribution"],
            [{"value": -2, "count": 1}, {"value": 0, "count": 1}],
        )
        self.assertEqual(
            conventional_slots["slot_124"]["integer_value_distribution"],
            [{"value": 0, "count": 1}, {"value": 9, "count": 1}],
        )
        self.assertIn("slot_008", conventional["constant_slots"])
        self.assertIn("slot_008", conventional["reserved_looking_zero_constant_slot_candidates"])
        self.assertEqual(
            conventional["distinct_candidate_typed_structural_anomalies"], []
        )

        missile_slots = {slot["slot_id"]: slot for slot in missile["slots"]}
        self.assertEqual(missile_slots["slot_000"]["finite_count"], 0)
        self.assertEqual(missile_slots["slot_000"]["non_finite_count"], 1)
        self.assertEqual(missile_slots["slot_004"]["non_finite_count"], 1)
        self.assertEqual(
            missile_slots["slot_124"]["integer_value_distribution"],
            [{"value": 0xFFFFFFFF, "count": 1}],
        )
        self.assertEqual(
            missile["distinct_candidate_typed_structural_anomalies"],
            [
                {
                    "code": "candidate_non_finite_float_values",
                    "slot_id": "slot_000",
                    "count": 1,
                    "evidence_classification": "inference",
                },
                {
                    "code": "candidate_non_finite_float_values",
                    "slot_id": "slot_004",
                    "count": 1,
                    "evidence_classification": "inference",
                },
            ],
        )
        self.assertEqual(
            inventory["reserved_looking_classification"],
            {
                "evidence_classification": "inference",
                "criterion": "slot is raw-bit constant and its raw numeric values all compare equal to zero",
                "semantic_claim": "none",
            },
        )



if __name__ == "__main__":
    unittest.main()
