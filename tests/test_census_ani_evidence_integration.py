#!/usr/bin/env python3
"""Focused synthetic ANI evidence integration tests for the Issue #72 A2.1 census."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).parent))

from support.census_fixture import (  # noqa: E402
    _ani_bytes,
    _macros,
    _source_roots,
    _write,
    build_census,
)


class CensusAniEvidenceIntegrationTests(unittest.TestCase):
    def test_x4converter_semantic_lead_is_complete_and_requires_corroboration(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            lead = build_census(_source_roots(Path(tmp)))[
                "x4converter_candidate_key_record_semantic_lead"
            ]

        self.assertEqual(lead["evidence_classification"], "third-party-technique")
        self.assertEqual(
            lead["source_revision"]["commit"],
            "0be4b494089ba7719d4c5d351e63160ef3843ef5",
        )
        self.assertEqual(lead["record_size_bytes"], 128)
        self.assertEqual(lead["decision_driving_component_class"], "conventional")
        self.assertEqual(lead["missileturret_semantic_analysis"], "excluded")

        fields = lead["field_map"]
        self.assertEqual([field["byte_offset"] for field in fields], list(range(0, 128, 4)))
        self.assertEqual(
            [field["x4converter_member"] for field in fields],
            [
                "ValueX", "ValueY", "ValueZ",
                "InterpolationX", "InterpolationY", "InterpolationZ",
                "Time",
                "CPX1x", "CPX1y", "CPX2x", "CPX2y",
                "CPY1x", "CPY1y", "CPY2x", "CPY2y",
                "CPZ1x", "CPZ1y", "CPZ2x", "CPZ2y",
                "Tens", "Cont", "Bias", "EaseIn", "EaseOut",
                "Deriv",
                "DerivInX", "DerivInY", "DerivInZ",
                "DerivOutX", "DerivOutY", "DerivOutZ",
                "AngleKey",
            ],
        )
        self.assertEqual(
            [group["group_id"] for group in lead["record_field_groups"]],
            [
                "candidate_vector",
                "per_axis_mode",
                "record_order_scalar",
                "control_parameters",
                "curve_parameters",
                "flags",
                "derived_vectors",
                "unused_or_reserved",
            ],
        )
        for field in fields:
            self.assertEqual(field["evidence_classification"], "third-party-technique")
            self.assertTrue(field["independent_corroboration_required"])
            self.assertTrue(field["x4converter_read_site"]["expression"])
            self.assertTrue(field["x4converter_use_sites"])

        self.assertEqual(
            [
                (
                    group["candidate_channel_count_field_index"],
                    group["x4converter_count_member"],
                    group["x4converter_record_vector_member"],
                    group["intermediate_output_label"],
                )
                for group in lead["candidate_channel_grouping"]
            ],
            [
                (0, "NumPosKeys", "posKeys", "location"),
                (1, "NumRotKeys", "rotKeys", "rotation_euler"),
                (2, "NumScaleKeys", "scaleKeys", "scale"),
                (3, "NumPreScaleKeys", "preScaleKeys", None),
                (4, "NumPostScaleKeys", "postScaleKeys", None),
            ],
        )
        self.assertEqual(
            lead["x4converter_control_parameter_routing"]["routes"],
            [
                {
                    "right_argument": False,
                    "output_node": "handle_right",
                    "selected_member_suffix": "1",
                },
                {
                    "right_argument": True,
                    "output_node": "handle_left",
                    "selected_member_suffix": "2",
                },
            ],
        )

        enum_mapping = {
            mapping["raw_value"]: mapping for mapping in lead["observed_enum_mapping"]
        }
        self.assertEqual(
            {value: mapping["x4converter_identifier"] for value, mapping in enum_mapping.items()},
            {
                1: "INTERPOLATION_STEP",
                2: "INTERPOLATION_LINEAR",
                5: "INTERPOLATION_BEZIER",
            },
        )
        self.assertIn("Keyframe::checkInterpolationType", enum_mapping[1]["branch_sites"][0]["function"])
        self.assertTrue(
            any(
                "InterpolationX == 2" in site["expression"]
                for site in enum_mapping[2]["branch_sites"]
            )
        )
        self.assertIn("Keyframe::checkInterpolationType", enum_mapping[5]["branch_sites"][0]["function"])

        matrix = lead["independent_corroboration_required"]
        self.assertEqual(
            {row["current_observation_assessment"] for row in matrix},
            {"merely_consistent", "no_semantic_evidence"},
        )
        self.assertTrue(all(row["required"] for row in matrix))
        self.assertIn(
            "record_order_scalar_identity",
            {row["candidate_semantic"] for row in matrix},
        )
        self.assertIn(
            "zero_tail_member_identities",
            {row["candidate_semantic"] for row in matrix},
        )

        string_values: list[str] = []
        evidence_labels: list[str] = []
        pending: list[object] = [lead]
        while pending:
            value = pending.pop()
            if isinstance(value, dict):
                if "evidence_classification" in value:
                    evidence_labels.append(str(value["evidence_classification"]))
                pending.extend(value.values())
            elif isinstance(value, list):
                pending.extend(value)
            elif isinstance(value, str):
                string_values.append(value.lower())
        self.assertEqual(set(evidence_labels), {"third-party-technique"})
        self.assertNotIn("shipped-source", string_values)
        self.assertNotIn("live-tested", string_values)
        self.assertFalse(any(value in {"final", "resolved"} for value in string_values))

    def test_framing_evidence_boundary_separates_shipped_source_from_order_inference(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/component_a"/>
                    <connections>
                      <connection name="Root">
                        <animations><animation name="Selector"/></animations>
                        <parts><part name="RootPart"/></parts>
                      </connection>
                      <connection name="Endpoint" tags="laser" parent="RootPart"/>
                    </connections>
                  </component>
                </components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("conventional_macro", "turret", "conventional_component")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(("RootPart", "Selector", 1, 2, 0, 0, 0))
            )

            framing = build_census(roots)["ani_key_data_framing"]

            # Structural facts a file-size invariant can actually prove.
            structural = framing["structural_framing"]
            self.assertEqual(structural["evidence_classification"], "shipped-source")
            self.assertEqual(structural["record_size_bytes"], 128)
            self.assertEqual(
                structural["key_section_termination"], "exactly at end of file"
            )
            # The shipped invariant must not claim to prove byte ordering.
            self.assertEqual(
                structural["does_not_discriminate"],
                ["descriptor_order", "channel_order"],
            )
            self.assertNotIn("descriptor_order", structural)
            self.assertNotIn("channel_order", structural)

            # Ordering is inference only; it never carries a shipped-source label.
            ownership = framing["key_ownership_order"]
            self.assertEqual(
                ownership["evidence_classification"], "third-party-technique"
            )
            self.assertEqual(ownership["descriptor_order"], "descriptor table index order")
            self.assertEqual(
                ownership["channel_order"],
                ["position", "rotation", "scale", "pre_scale", "post_scale"],
            )

    def test_selected_descriptor_channel_count_families_are_preserved_and_separated(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/component_a"/>
                    <connections>
                      <connection name="ConventionalRoot">
                        <animations><animation name="RootSelector"/></animations>
                        <parts><part name="RootPart"/></parts>
                      </connection>
                      <connection name="ConventionalChild" parent="RootPart">
                        <animations><animation name="ChildSelector"/></animations>
                        <parts><part name="ChildPart"/></parts>
                      </connection>
                      <connection name="ConventionalEndpointA" tags="laser" parent="ChildPart"/>
                      <connection name="ConventionalEndpointB" tags="laser" parent="ChildPart"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/component_b"/>
                    <connections>
                      <connection name="MissileRoot">
                        <animations><animation name="MissileSelector"/></animations>
                        <parts><part name="MissilePart"/></parts>
                      </connection>
                      <connection name="MissileEndpoint" tags="rocket" parent="MissilePart"/>
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
                    ("RootPart", "RootSelector", 3, 4, 0, 0, 0),
                    ("ChildPart", "ChildSelector", 0, 1, 2, 3, 4),
                )
            )
            (roots["base"] / "geometry/component_b.ANI").write_bytes(
                _ani_bytes(("MissilePart", "MissileSelector", 8, 7, 6, 5, 4))
            )

            report = build_census(roots)
            conventional, missile = report["component_to_macros"]
            self.assertEqual(
                [descriptor["channel_counts"] for descriptor in conventional["ani_descriptors"]],
                [
                    {"position": 3, "rotation": 4, "scale": 0, "pre_scale": 0, "post_scale": 0},
                    {"position": 0, "rotation": 1, "scale": 2, "pre_scale": 3, "post_scale": 4},
                ],
            )
            self.assertEqual(
                [
                    descriptor["channel_counts"]
                    for descriptor in conventional["firing_endpoints"][0][
                        "selected_ani_descriptor_memberships"
                    ]
                ],
                [
                    {"position": 3, "rotation": 4, "scale": 0, "pre_scale": 0, "post_scale": 0},
                    {"position": 0, "rotation": 1, "scale": 2, "pre_scale": 3, "post_scale": 4},
                ],
            )
            self.assertEqual(
                missile["firing_endpoints"][0]["selected_ani_descriptor_memberships"][0][
                    "channel_counts"
                ],
                {"position": 8, "rotation": 7, "scale": 6, "pre_scale": 5, "post_scale": 4},
            )
            self.assertEqual(
                [descriptor["descriptor_index"] for descriptor in conventional["ani_descriptors"]],
                [0, 1],
            )
            self.assertEqual(
                conventional["firing_endpoints"][0]["selected_ani_descriptor_memberships"][0][
                    "key_data"
                ],
                conventional["ani_descriptors"][0]["key_data"],
            )
            self.assertEqual(
                report["selected_endpoint_path_descriptor_key_data_accounting"],
                {
                    "conventional": {
                        "selected_descriptor_memberships": 4,
                        "opaque_key_records": 34,
                        "opaque_key_bytes": 4352,
                    },
                    "missileturret": {
                        "selected_descriptor_memberships": 1,
                        "opaque_key_records": 30,
                        "opaque_key_bytes": 3840,
                    },
                },
            )
            self.assertEqual(
                report["ani_key_data_framing"],
                {
                    "structural_framing": {
                        "evidence_classification": "shipped-source",
                        "x4_version": "9.00",
                        "record_size_bytes": 128,
                        "key_section_termination": "exactly at end of file",
                        "invariant": (
                            "descriptor-table end offset"
                            " + sum(all descriptor channel counts) * record_size_bytes"
                            " == file size"
                        ),
                        "linked_ani_resources": 2,
                        "resources_with_exact_framing": 2,
                        "exceptions": [],
                        "does_not_discriminate": [
                            "descriptor_order",
                            "channel_order",
                        ],
                    },
                    "key_ownership_order": {
                        "evidence_classification": "third-party-technique",
                        "descriptor_order": "descriptor table index order",
                        "channel_order": [
                            "position",
                            "rotation",
                            "scale",
                            "pre_scale",
                            "post_scale",
                        ],
                        "note": (
                            "byte order of descriptor and channel key records is not"
                            " discriminated by the shipped-source structural invariant;"
                            " the parser assigns key-record ranges in this order per the"
                            " third-party lead only"
                        ),
                        "third_party_lead": {
                            "source": "X4Converter 0be4b494089ba7719d4c5d351e63160ef3843ef5 X4ConverterTools/src/ani/AnimFile.cpp, AnimDesc.cpp, and Keyframe.h",
                        },
                    },
                },
            )
            self.assertEqual(
                report["selected_endpoint_path_descriptor_channel_count_families"],
                {
                    "conventional": [
                        {
                            "channel_counts": {
                                "position": 0,
                                "rotation": 1,
                                "scale": 2,
                                "pre_scale": 3,
                                "post_scale": 4,
                            },
                            "selected_descriptor_memberships": 2,
                        },
                        {
                            "channel_counts": {
                                "position": 3,
                                "rotation": 4,
                                "scale": 0,
                                "pre_scale": 0,
                                "post_scale": 0,
                            },
                            "selected_descriptor_memberships": 2,
                        },
                    ],
                    "missileturret": [
                        {
                            "channel_counts": {
                                "position": 8,
                                "rotation": 7,
                                "scale": 6,
                                "pre_scale": 5,
                                "post_scale": 4,
                            },
                            "selected_descriptor_memberships": 1,
                        }
                    ],
                },
            )


if __name__ == "__main__":
    unittest.main()
