#!/usr/bin/env python3
"""Focused synthetic endpoint pipeline integration tests for the Issue #72 A2.1 census."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).parent))

from census_common import CensusError, render_json  # noqa: E402
from census_endpoint_paths import _derive_endpoint_source_paths  # noqa: E402
from support.census_fixture import (  # noqa: E402
    _ani_bytes,
    _macros,
    _source_roots,
    _write,
    build_census,
)


class CensusEndpointPipelineIntegrationTests(unittest.TestCase):
    def test_connection_graph_and_descriptor_source_paths_are_exact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/component_a"/>
                  <connections>
                    <connection name="Root"><parts><part name="BasePart"/><part name="BasePart"/></parts></connection>
                    <connection name="Child" parent="BasePart"><parts><part name="ArmPart"/></parts></connection>
                    <connection name="Grand" tags="laser" parent="ArmPart"><parts><part name="BarrelPart"/></parts></connection>
                    <connection name="Branch" parent="BasePart"><parts><part name="BranchPart"/></parts></connection>
                    <connection name="EmptyParentRoot" parent=""/>
                  </connections>
                  <metadata><connections><connection name="Nested" parent="BarrelPart"><parts><part name="NestedPart"/></parts></connection></connections></metadata>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(("BarrelPart", "Sub_CASE"), ("BasePart", "RootSub"))
            )

            report = build_census(roots)
            component = report["component_to_macros"][0]
            self.assertEqual(
                component["connections"],
                [
                    {
                        "name": "Branch",
                        "parent_part": "BasePart",
                        "parent_connection": "Root",
                        "direct_owned_parts": ["BranchPart"],
                        "authored_attributes": {"name": "Branch", "parent": "BasePart"},
                        "authored_tags": None,
                        "tag_tokens": [],
                        "authored_restrictions": [],
                        "root_to_connection_path": ["Root", "Branch"],
                        "depth": 1,
                    },
                    {
                        "name": "Child",
                        "parent_part": "BasePart",
                        "parent_connection": "Root",
                        "direct_owned_parts": ["ArmPart"],
                        "authored_attributes": {"name": "Child", "parent": "BasePart"},
                        "authored_tags": None,
                        "tag_tokens": [],
                        "authored_restrictions": [],
                        "root_to_connection_path": ["Root", "Child"],
                        "depth": 1,
                    },
                    {
                        "name": "EmptyParentRoot",
                        "parent_part": None,
                        "parent_connection": None,
                        "direct_owned_parts": [],
                        "authored_attributes": {"name": "EmptyParentRoot", "parent": ""},
                        "authored_tags": None,
                        "tag_tokens": [],
                        "authored_restrictions": [],
                        "root_to_connection_path": ["EmptyParentRoot"],
                        "depth": 0,
                    },
                    {
                        "name": "Grand",
                        "parent_part": "ArmPart",
                        "parent_connection": "Child",
                        "direct_owned_parts": ["BarrelPart"],
                        "authored_attributes": {"name": "Grand", "parent": "ArmPart", "tags": "laser"},
                        "authored_tags": "laser",
                        "tag_tokens": ["laser"],
                        "authored_restrictions": [],
                        "root_to_connection_path": ["Root", "Child", "Grand"],
                        "depth": 2,
                    },
                    {
                        "name": "Root",
                        "parent_part": None,
                        "parent_connection": None,
                        "direct_owned_parts": ["BasePart", "BasePart"],
                        "authored_attributes": {"name": "Root"},
                        "authored_tags": None,
                        "tag_tokens": [],
                        "authored_restrictions": [],
                        "root_to_connection_path": ["Root"],
                        "depth": 0,
                    },
                ],
            )
            self.assertEqual(
                [
                    {
                        key: descriptor[key]
                        for key in (
                            "descriptor_index",
                            "part",
                            "subname",
                            "source_connection",
                            "root_to_source_connection_path",
                        )
                    }
                    for descriptor in component["ani_descriptors"]
                ],
                [
                    {
                        "descriptor_index": 0,
                        "part": "BarrelPart",
                        "subname": "Sub_CASE",
                        "source_connection": "Grand",
                        "root_to_source_connection_path": ["Root", "Child", "Grand"],
                    },
                    {
                        "descriptor_index": 1,
                        "part": "BasePart",
                        "subname": "RootSub",
                        "source_connection": "Root",
                        "root_to_source_connection_path": ["Root"],
                    },
                ],
            )
            self.assertNotIn("Nested", render_json(component))
            base_part = next(
                source_part
                for source_part in component["source_parts"]
                if source_part["part"] == "BasePart"
            )
            self.assertEqual(base_part["owning_connection_count"], 2)
            self.assertEqual(base_part["distinct_owning_connection_count"], 1)
            self.assertEqual(base_part["owning_connections"], ["Root", "Root"])
            self.assertEqual(report["counts"]["connection_identities"], 5)
            self.assertEqual(report["component_root_count_distribution"], {"2": 1})
            self.assertEqual(report["connection_depth_distribution"], {"0": 2, "1": 2, "2": 1})
            self.assertEqual(report["counts"]["descriptor_source_path_joins"], 2)
            self.assertEqual(report["unresolved_or_ambiguous_parent_identities"], [])
            self.assertEqual(
                report["unresolved_or_ambiguous_descriptor_path_identities"], []
            )

    def test_connection_identity_resolution_failures_are_closed(self) -> None:
        cases = (
            (
                "missing_parent",
                '<connection name="Root"><parts><part name="Base"/></parts></connection><connection name="Child" parent="Missing"/>',
                "unresolved_parent_part_reference",
            ),
            (
                "ambiguous_parent",
                '<connection name="A"><parts><part name="Shared"/></parts></connection><connection name="B"><parts><part name="Shared"/></parts></connection><connection name="Child" parent="Shared"/>',
                "ambiguous_parent_part_reference",
            ),
            (
                "duplicate_connection",
                '<connection name="Same"/><connection name="Same"/>',
                "duplicate_connection_identity",
            ),
            (
                "cycle",
                '<connection name="A" parent="PartB"><parts><part name="PartA"/></parts></connection><connection name="B" parent="PartA"><parts><part name="PartB"/></parts></connection>',
                "connection_cycle",
            ),
            (
                "self_cycle",
                '<connection name="A" parent="PartA"><parts><part name="PartA"/></parts></connection>',
                "self_parenting_connection",
            ),
        )
        for label, connections, code in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                roots = _source_roots(Path(tmp))
                _write(
                    roots["base"],
                    "assets/component.xml",
                    f'<components><component name="component_a" class="turret"><source geometry="geometry/component_a"/><connections>{connections}</connections></component></components>',
                )
                _write(
                    roots["base"],
                    "assets/macros.xml",
                    _macros(("a_macro", "turret", "component_a")),
                )
                with self.assertRaises(CensusError) as caught:
                    build_census(roots)
                self.assertIn(code, caught.exception.codes)

    def test_descriptor_source_path_missing_or_ambiguous_ownership_fails_closed(self) -> None:
        cases = (
            (
                "missing",
                '<connection name="Root"><parts><part name="Other"/></parts></connection>',
                "unresolved_descriptor_source_path",
            ),
            (
                "ambiguous",
                '<connection name="A"><parts><part name="Target"/></parts></connection><connection name="B"><parts><part name="Target"/></parts></connection>',
                "ambiguous_descriptor_source_path",
            ),
        )
        for label, connections, code in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                roots = _source_roots(Path(tmp))
                _write(
                    roots["base"],
                    "assets/component.xml",
                    f'<components><component name="component_a" class="turret"><source geometry="geometry/component_a"/><connections>{connections}</connections></component></components>',
                )
                _write(
                    roots["base"],
                    "assets/macros.xml",
                    _macros(("a_macro", "turret", "component_a")),
                )
                (roots["base"] / "geometry/component_a.ANI").write_bytes(
                    _ani_bytes(("Target", "Sub"))
                )
                with self.assertRaises(CensusError) as caught:
                    build_census(roots)
                self.assertIn(code, caught.exception.codes)

    def test_endpoint_source_part_paths_and_exact_descriptor_membership(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/component_a"/>
                    <connections>
                      <connection name="Root"><parts><part name="SharedPart"/><part name="SiblingPart"/></parts></connection>
                      <connection name="SharedNode" parent="SharedPart"><parts><part name="BranchAPart"/><part name="BranchBPart"/></parts></connection>
                      <connection name="EndpointA" tags="laser" parent="BranchAPart"/>
                      <connection name="BranchB" parent="BranchBPart"><parts><part name="DeepPart"/></parts></connection>
                      <connection name="EndpointB" tags="laser" parent="DeepPart"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/component_b"/>
                    <connections><connection name="RootEndpoint" tags="rocket"><parts><part name="UnusedMissilePart"/></parts></connection></connections>
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
                    ("SharedPart", "SharedSub"),
                    ("BranchAPart", "SameSub"),
                    ("SiblingPart", "SameSub"),
                    ("BranchBPart", "BranchBSub"),
                    ("DeepPart", "DeepSubA"),
                    ("DeepPart", "DeepSubB"),
                )
            )
            (roots["base"] / "geometry/component_b.ANI").write_bytes(
                _ani_bytes(("UnusedMissilePart", "OffPath"))
            )

            report = build_census(roots)
            conventional, missile = report["component_to_macros"]
            endpoint_a, endpoint_b = conventional["firing_endpoints"]
            self.assertEqual(
                endpoint_a["traversed_connection_edges"],
                [
                    {
                        "parent_connection": "Root",
                        "child_connection": "SharedNode",
                        "child_parent_part": "SharedPart",
                    },
                    {
                        "parent_connection": "SharedNode",
                        "child_connection": "EndpointA",
                        "child_parent_part": "BranchAPart",
                    },
                ],
            )
            self.assertEqual(endpoint_a["source_part_path"], ["SharedPart", "BranchAPart"])
            self.assertEqual(
                [
                    (
                        descriptor["descriptor_index"],
                        descriptor["part"],
                        descriptor["subname"],
                        descriptor["source_connection"],
                        descriptor["root_to_source_connection_path"],
                        descriptor["endpoint_path_edge_index"],
                    )
                    for descriptor in endpoint_a["ani_descriptor_memberships"]
                ],
                [
                    (0, "SharedPart", "SharedSub", "Root", ["Root"], 0),
                    (
                        1,
                        "BranchAPart",
                        "SameSub",
                        "SharedNode",
                        ["Root", "SharedNode"],
                        1,
                    ),
                ],
            )
            self.assertEqual(
                endpoint_b["source_part_path"],
                ["SharedPart", "BranchBPart", "DeepPart"],
            )
            self.assertEqual(
                [(item["part"], item["subname"]) for item in endpoint_b["ani_descriptor_memberships"]],
                [
                    ("SharedPart", "SharedSub"),
                    ("BranchBPart", "BranchBSub"),
                    ("DeepPart", "DeepSubA"),
                    ("DeepPart", "DeepSubB"),
                ],
            )
            self.assertNotIn(
                ("SiblingPart", "SameSub"),
                [(item["part"], item["subname"]) for item in endpoint_a["ani_descriptor_memberships"] + endpoint_b["ani_descriptor_memberships"]],
            )
            root_endpoint = missile["firing_endpoints"][0]
            self.assertEqual(root_endpoint["traversed_connection_edges"], [])
            self.assertEqual(root_endpoint["source_part_path"], [])
            self.assertEqual(root_endpoint["ani_descriptor_memberships"], [])
            self.assertEqual(report["endpoint_path_depth_distribution"], {"0": 1, "2": 1, "3": 1})
            self.assertEqual(report["counts"]["traversed_endpoint_part_occurrences"], 5)
            self.assertEqual(report["endpoint_path_descriptor_join_distribution"], {"0": 1, "2": 1, "4": 1})
            self.assertEqual(report["endpoint_paths_by_descriptor_join_cardinality"], {"zero": 1, "one": 0, "multiple": 2})
            self.assertEqual(report["counts"]["descriptor_endpoint_path_memberships"], 6)
            self.assertEqual(report["counts"]["descriptors_on_at_least_one_endpoint_path"], 5)
            self.assertEqual(report["counts"]["descriptors_only_off_endpoint_paths"], 2)
            self.assertEqual(report["counts"]["unresolved_or_ambiguous_endpoint_path_identities"], 0)

    def test_endpoint_path_animation_selector_without_exact_descriptor_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/component_a"/>
                  <connections>
                    <connection name="Root"><animations><animation name="ExactCase"/></animations><parts><part name="PathPart"/></parts></connection>
                    <connection name="Endpoint" tags="laser" parent="PathPart"/>
                  </connections>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(("PathPart", "exactcase"))
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn(
                "unresolved_endpoint_path_animation_selector", caught.exception.codes
            )

    def test_malformed_endpoint_edge_ownership_fails_closed(self) -> None:
        endpoints = [{"connection": "Child", "root_to_endpoint_connection_path": ["Root", "Child"]}]
        connections = [
            {"name": "Root", "parent_connection": None, "parent_part": None, "direct_owned_parts": ["Other"]},
            {"name": "Child", "parent_connection": "Root", "parent_part": "Required", "direct_owned_parts": []},
        ]
        resolved, anomalies = _derive_endpoint_source_paths(
            endpoints,
            connections,
            [],
            component="component_a",
            source_set="base",
            source_file="assets/component.xml",
        )
        self.assertEqual(resolved, [])
        self.assertEqual([item["code"] for item in anomalies], ["invalid_endpoint_edge_ownership"])

        resolved, anomalies = _derive_endpoint_source_paths(
            [{"connection": "Missing", "root_to_endpoint_connection_path": ["Root", "Missing"]}],
            connections,
            [],
            component="component_a",
            source_set="base",
            source_file="assets/component.xml",
        )
        self.assertEqual(resolved, [])
        self.assertEqual([item["code"] for item in anomalies], ["unresolvable_endpoint_connection_path"])

        resolved, anomalies = _derive_endpoint_source_paths(
            [],
            connections,
            [
                {
                    "part": "Required",
                    "subname": "ExactSubname",
                    "source_connection": "Root",
                    "root_to_source_connection_path": ["Root"],
                }
            ],
            component="component_a",
            source_set="base",
            source_file="assets/component.xml",
        )
        self.assertEqual(resolved, [])
        self.assertEqual([item["code"] for item in anomalies], ["contradictory_descriptor_path_identity"])

    def test_firing_endpoints_use_authored_tags_not_connection_spelling(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/components.xml",
                """<components>
                  <component name="conventional_component" class="turret">
                    <source geometry="geometry/component_a"/>
                    <connections>
                      <connection name="Root" tags="part custom  " custom="ExactValue"><parts><part name="Pivot"/></parts></connection>
                      <connection name="Child" tags="part" parent="Pivot"><parts><part name="Barrel"/></parts></connection>
                      <connection name="NotNamedLikeEndpointA" tags="laser  " parent="Barrel"/>
                      <connection name="NotNamedLikeEndpointB" tags="laser" parent="Barrel"/>
                      <connection name="con_laser_unrelated" tags="decoration" parent="Barrel"/>
                    </connections>
                  </component>
                  <component name="missile_component" class="missileturret">
                    <source geometry="geometry/component_b"/>
                    <connections><connection name="LaunchPoint" tags="rocket " marker="preserved"/></connections>
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

            report = build_census(roots)
            conventional, missile = report["component_to_macros"]
            self.assertEqual(
                conventional["firing_endpoints"],
                [
                    {
                        "component": "conventional_component",
                        "component_class": "turret",
                        "macros": ["conventional_macro"],
                        "macro_classes": ["turret"],
                        "connection": "NotNamedLikeEndpointA",
                        "authored_evidence": {
                            "tag_attribute": "laser  ",
                            "tag_token": "laser",
                        },
                        "root_to_endpoint_connection_path": [
                            "Root",
                            "Child",
                            "NotNamedLikeEndpointA",
                        ],
                        "traversed_connection_edges": [
                            {
                                "parent_connection": "Root",
                                "child_connection": "Child",
                                "child_parent_part": "Pivot",
                            },
                            {
                                "parent_connection": "Child",
                                "child_connection": "NotNamedLikeEndpointA",
                                "child_parent_part": "Barrel",
                            },
                        ],
                        "source_part_path": ["Pivot", "Barrel"],
                        "ani_descriptor_memberships": [],
                        "authored_animation_selector_occurrences": [],
                        "selected_ani_descriptor_memberships": [],
                        "unselected_ani_descriptor_memberships": [],
                    },
                    {
                        "component": "conventional_component",
                        "component_class": "turret",
                        "macros": ["conventional_macro"],
                        "macro_classes": ["turret"],
                        "connection": "NotNamedLikeEndpointB",
                        "authored_evidence": {
                            "tag_attribute": "laser",
                            "tag_token": "laser",
                        },
                        "root_to_endpoint_connection_path": [
                            "Root",
                            "Child",
                            "NotNamedLikeEndpointB",
                        ],
                        "traversed_connection_edges": [
                            {
                                "parent_connection": "Root",
                                "child_connection": "Child",
                                "child_parent_part": "Pivot",
                            },
                            {
                                "parent_connection": "Child",
                                "child_connection": "NotNamedLikeEndpointB",
                                "child_parent_part": "Barrel",
                            },
                        ],
                        "source_part_path": ["Pivot", "Barrel"],
                        "ani_descriptor_memberships": [],
                        "authored_animation_selector_occurrences": [],
                        "selected_ani_descriptor_memberships": [],
                        "unselected_ani_descriptor_memberships": [],
                    },
                ],
            )
            self.assertEqual(
                missile["firing_endpoints"],
                [
                    {
                        "component": "missile_component",
                        "component_class": "missileturret",
                        "macros": ["missile_macro"],
                        "macro_classes": ["missileturret"],
                        "connection": "LaunchPoint",
                        "authored_evidence": {
                            "tag_attribute": "rocket ",
                            "tag_token": "rocket",
                        },
                        "root_to_endpoint_connection_path": ["LaunchPoint"],
                        "traversed_connection_edges": [],
                        "source_part_path": [],
                        "ani_descriptor_memberships": [],
                        "authored_animation_selector_occurrences": [],
                        "selected_ani_descriptor_memberships": [],
                        "unselected_ani_descriptor_memberships": [],
                    }
                ],
            )
            unrelated = next(
                connection
                for connection in conventional["connections"]
                if connection["name"] == "con_laser_unrelated"
            )
            self.assertEqual(unrelated["authored_tags"], "decoration")
            self.assertEqual(unrelated["tag_tokens"], ["decoration"])
            root = next(
                connection
                for connection in conventional["connections"]
                if connection["name"] == "Root"
            )
            self.assertEqual(root["authored_tags"], "part custom  ")
            self.assertEqual(root["tag_tokens"], ["part", "custom"])
            self.assertEqual(
                root["authored_attributes"],
                {"custom": "ExactValue", "name": "Root", "tags": "part custom  "},
            )
            self.assertEqual(report["counts"]["firing_endpoint_identities"], 3)
            self.assertEqual(report["counts"]["conventional_firing_endpoints"], 2)
            self.assertEqual(report["counts"]["missileturret_firing_endpoints"], 1)
            self.assertEqual(report["firing_endpoint_count_distribution"], {"1": 1, "2": 1})
            self.assertEqual(
                report["firing_endpoint_criterion"],
                {
                    "evidence_classification": "shipped-source",
                    "structural_rule": "exact direct connection tag token selected by exact component class",
                    "component_class_to_tag_token": {
                        "missileturret": "rocket",
                        "turret": "laser",
                    },
                },
            )
            self.assertEqual(
                report["firing_endpoint_evidence_patterns"],
                [
                    {
                        "component_class": "missileturret",
                        "tag_token": "rocket",
                        "exact_tag_attribute": "rocket ",
                        "endpoint_count": 1,
                    },
                    {
                        "component_class": "turret",
                        "tag_token": "laser",
                        "exact_tag_attribute": "laser",
                        "endpoint_count": 1,
                    },
                    {
                        "component_class": "turret",
                        "tag_token": "laser",
                        "exact_tag_attribute": "laser  ",
                        "endpoint_count": 1,
                    },
                ],
            )
            self.assertEqual(
                report["firing_endpoints"],
                conventional["firing_endpoints"] + missile["firing_endpoints"],
            )

    def test_missing_malformed_or_ambiguous_firing_endpoint_evidence_fails_closed(self) -> None:
        cases = (
            ("missing", "turret", "turret", '<connection name="con_laser_only_by_name"/>', "missing_firing_endpoint_identity"),
            ("duplicate_token", "turret", "turret", '<connection name="Endpoint" tags="laser laser"/>', "malformed_endpoint_evidence"),
            ("both_roles", "turret", "turret", '<connection name="Endpoint" tags="laser rocket"/>', "ambiguous_endpoint_evidence"),
            ("wrong_role", "turret", "turret", '<connection name="Endpoint" tags="rocket"/>', "ambiguous_endpoint_evidence"),
            ("missile_duplicate", "missileturret", "missileturret", '<connection name="Endpoint" tags="rocket rocket"/>', "malformed_endpoint_evidence"),
            ("missile_wrong_role", "missileturret", "missileturret", '<connection name="Endpoint" tags="laser"/>', "ambiguous_endpoint_evidence"),
            ("unsupported_class", "bullet", "turret", '<connection name="Endpoint" tags="laser"/>', "unsupported_endpoint_component_class"),
        )
        for label, component_class, macro_class, connections, code in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as tmp:
                roots = _source_roots(Path(tmp))
                _write(
                    roots["base"],
                    "assets/component.xml",
                    f'<components><component name="component_a" class="{component_class}"><source geometry="geometry/component_a"/><connections>{connections}</connections></component></components>',
                )
                _write(
                    roots["base"],
                    "assets/macros.xml",
                    _macros(("a_macro", macro_class, "component_a")),
                )
                with self.assertRaises(CensusError) as caught:
                    build_census(roots)
                self.assertIn(code, caught.exception.codes)

    @staticmethod
    def _ancestry_descriptor(
        index: int, part: str, subname: str, source_connection: str, path: list[str]
    ) -> dict[str, object]:
        return {
            "descriptor_index": index,
            "part": part,
            "subname": subname,
            "channel_counts": {},
            "descriptor_offset_148": None,
            "key_data": None,
            "_candidate_raw_key_records": [f"raw-{index}"],
            "source_connection": source_connection,
            "root_to_source_connection_path": list(path),
        }

    def test_ancestry_covered_turret_active_descriptors_span_same_and_ancestor_connections(
        self,
    ) -> None:
        connections = [
            {"name": "Root", "parent_connection": None, "parent_part": None, "direct_owned_parts": ["RootPart"]},
            {"name": "A", "parent_connection": "Root", "parent_part": "RootPart", "direct_owned_parts": ["APart"]},
            {"name": "B", "parent_connection": "A", "parent_part": "APart", "direct_owned_parts": ["BPart"]},
            {"name": "Endpoint", "parent_connection": "B", "parent_part": "BPart", "direct_owned_parts": []},
        ]
        d_root = self._ancestry_descriptor(0, "RootPart", "turret_active", "Root", ["Root"])
        d_a = self._ancestry_descriptor(1, "APart", "turret_active", "A", ["Root", "A"])
        d_b = self._ancestry_descriptor(2, "BPart", "turret_active", "B", ["Root", "A", "B"])
        d_b_other = self._ancestry_descriptor(3, "BPart", "not_turret_active", "B", ["Root", "A", "B"])
        # Selector authored on A: covers A itself and its descendant B, but not
        # ancestor Root; a non-turret_active literal on B is never covered.
        selector = {
            "connection": "A",
            "name": "turret_active",
            "descriptor_match_count": 1,
            "connection_ani_descriptors": [d_a],
        }
        endpoint = {"connection": "Endpoint", "root_to_endpoint_connection_path": ["Root", "A", "B", "Endpoint"]}

        resolved, anomalies = _derive_endpoint_source_paths(
            [endpoint],
            connections,
            [d_root, d_a, d_b, d_b_other],
            authored_animation_selectors=[selector],
            component="component_a",
            source_set="base",
            source_file="assets/component.xml",
        )

        self.assertEqual(anomalies, [])
        covered = resolved[0]["_ancestry_covered_turret_active_descriptor_memberships"]
        self.assertEqual(
            [
                (d["part"], d["subname"], d["source_connection"], d["endpoint_path_edge_index"])
                for d in covered
            ],
            [("APart", "turret_active", "A", 1), ("BPart", "turret_active", "B", 2)],
        )
        # Private raw ANI records are preserved on the retained memberships.
        self.assertEqual(covered[0]["_candidate_raw_key_records"], ["raw-1"])

    def test_ancestry_covered_turret_active_without_selector_is_valid_empty(self) -> None:
        connections = [
            {"name": "Root", "parent_connection": None, "parent_part": None, "direct_owned_parts": ["RootPart"]},
            {"name": "Endpoint", "parent_connection": "Root", "parent_part": "RootPart", "direct_owned_parts": []},
        ]
        d_root = self._ancestry_descriptor(0, "RootPart", "turret_active", "Root", ["Root"])
        endpoint = {"connection": "Endpoint", "root_to_endpoint_connection_path": ["Root", "Endpoint"]}

        resolved, anomalies = _derive_endpoint_source_paths(
            [endpoint],
            connections,
            [d_root],
            authored_animation_selectors=[],
            component="component_a",
            source_set="base",
            source_file="assets/component.xml",
        )

        self.assertEqual(anomalies, [])
        self.assertEqual(
            resolved[0]["_ancestry_covered_turret_active_descriptor_memberships"], []
        )

    def test_ancestry_covered_private_field_absent_from_serialized_census(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/component_a"/>
                  <connections>
                    <connection name="Root"><animations><animation name="turret_active"/></animations><parts><part name="RootPart"/></parts></connection>
                    <connection name="Endpoint" tags="laser" parent="RootPart"/>
                  </connections>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(("RootPart", "turret_active"))
            )

            report = build_census(roots)
            self.assertNotIn(
                "_ancestry_covered_turret_active_descriptor_memberships",
                render_json(report),
            )


if __name__ == "__main__":
    unittest.main()
