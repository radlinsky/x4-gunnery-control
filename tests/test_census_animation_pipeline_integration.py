#!/usr/bin/env python3
"""Focused synthetic animation pipeline integration tests for the Issue #72 A2.1 census."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
sys.path.insert(0, str(Path(__file__).parent))

from census_common import CensusError, render_json  # noqa: E402
from support.census_fixture import (  # noqa: E402
    _ani_bytes,
    _macros,
    _source_roots,
    _write,
    build_census,
)


class CensusAnimationPipelineIntegrationTests(unittest.TestCase):
    def test_ani_descriptors_source_parts_and_animation_names_are_exact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/component_a"/>
                  <connections>
                    <connection name="Conn_A">
                      <animations><animation name="Anim_CASE"/></animations>
                      <parts>
                        <part name="Part_CASE"/>
                        <part name="SharedPart"/>
                        <part name="DuplicateUnused"/>
                        <part name="DuplicateUnused"/>
                      </parts>
                      <metadata><parts><part name="NestedPart"/></parts></metadata>
                    </connection>
                    <connection name="Conn_B"><parts><part name="DuplicateUnused"/></parts></connection>
                    <connection name="Endpoint" tags="laser"/>
                  </connections>
                  <metadata><connection name="UnrelatedConn"><parts><part name="UnrelatedPart"/></parts></connection></metadata>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(
                    ("SharedPart", "SharedSub"),
                    ("Part_CASE", "Sub_CASE"),
                )
            )

            report = build_census(roots)
            component = report["component_to_macros"][0]
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
                        "part": "SharedPart",
                        "subname": "SharedSub",
                        "source_connection": "Conn_A",
                        "root_to_source_connection_path": ["Conn_A"],
                    },
                    {
                        "descriptor_index": 1,
                        "part": "Part_CASE",
                        "subname": "Sub_CASE",
                        "source_connection": "Conn_A",
                        "root_to_source_connection_path": ["Conn_A"],
                    },
                ],
            )
            self.assertEqual(
                component["source_parts"],
                [
                    {
                        "part": "DuplicateUnused",
                        "owning_connection_count": 3,
                        "distinct_owning_connection_count": 2,
                        "owning_connections": ["Conn_A", "Conn_A", "Conn_B"],
                    },
                    {
                        "part": "Part_CASE",
                        "owning_connection_count": 1,
                        "distinct_owning_connection_count": 1,
                        "owning_connections": ["Conn_A"],
                    },
                    {
                        "part": "SharedPart",
                        "owning_connection_count": 1,
                        "distinct_owning_connection_count": 1,
                        "owning_connections": ["Conn_A"],
                    },
                ],
            )
            self.assertEqual(
                component["authored_connection_animations"],
                [
                    {
                        "connection": "Conn_A",
                        "name": "Anim_CASE",
                        "descriptor_match_count": 0,
                        "connection_ani_descriptors": [],
                    }
                ],
            )
            self.assertEqual(
                component["descriptor_parts_absent_from_source_parts"], []
            )
            self.assertEqual(
                report["authored_animation_selectors_with_zero_descriptor_matches"],
                [
                    {
                        "component": "component_a",
                        "connection": "Conn_A",
                        "animation_name": "Anim_CASE",
                    }
                ],
            )
            self.assertNotIn("NestedPart", render_json(component))
            self.assertNotIn("UnrelatedPart", render_json(component))
            self.assertEqual(report["counts"]["ani_descriptor_pairs_total"], 2)
            self.assertEqual(report["counts"]["unique_ani_descriptor_pairs"], 2)
            self.assertEqual(report["ani_descriptor_count_cardinality"], {"2": 1})
            self.assertEqual(report["counts"]["source_part_ownerships"], 5)
            self.assertEqual(report["counts"]["component_source_parts"], 3)
            self.assertEqual(
                report["source_part_owning_connection_cardinality"], {"1": 2, "3": 1}
            )
            self.assertEqual(
                report["source_part_distinct_owning_connection_cardinality"],
                {"1": 2, "2": 1},
            )
            self.assertEqual(
                report["descriptor_parts_absent_from_component_source_parts"], []
            )

    def test_exact_authored_animation_selector_joins_on_endpoint_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/component_a"/>
                  <connections>
                    <connection name="Root">
                      <animations><animation name="ExactSelector"/><animation name="SiblingOnly"/></animations>
                      <parts><part name="PathPart"/><part name="SiblingPart"/></parts>
                    </connection>
                    <connection name="Child" parent="PathPart">
                      <animations><animation name="ExactSelector"/></animations>
                      <parts><part name="ChildPart"/></parts>
                    </connection>
                    <connection name="Endpoint" tags="laser" parent="ChildPart"/>
                    <connection name="OffPath">
                      <animations><animation name="OffPathSelector"/></animations>
                      <parts><part name="OffPathPart"/></parts>
                    </connection>
                  </connections>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            (roots["base"] / "geometry/component_a.ANI").write_bytes(
                _ani_bytes(
                    ("PathPart", "ExactSelector"),
                    ("SiblingPart", "ExactSelector"),
                    ("SiblingPart", "SiblingOnly"),
                    ("PathPart", "exactselector"),
                    ("PathPart", "NoSelector"),
                    ("ChildPart", "ExactSelector"),
                    ("OffPathPart", "OffPathSelector"),
                )
            )

            report = build_census(roots)
            component = report["component_to_macros"][0]
            root_selector = next(
                selector
                for selector in component["authored_connection_animations"]
                if selector["connection"] == "Root"
            )
            self.assertEqual(root_selector["descriptor_match_count"], 2)
            self.assertEqual(
                [(item["part"], item["subname"]) for item in root_selector["connection_ani_descriptors"]],
                [
                    ("PathPart", "ExactSelector"),
                    ("SiblingPart", "ExactSelector"),
                ],
            )
            endpoint = component["firing_endpoints"][0]
            self.assertEqual(
                [
                    (
                        occurrence["source_connection"],
                        occurrence["animation_name"],
                        occurrence["selector_connection_descriptor_match_count"],
                        occurrence["endpoint_path_edge_index"],
                    )
                    for occurrence in endpoint["authored_animation_selector_occurrences"]
                ],
                [
                    ("Root", "ExactSelector", 2, 0),
                    ("Root", "SiblingOnly", 1, 0),
                    ("Child", "ExactSelector", 1, 1),
                ],
            )
            self.assertEqual(
                [
                    (item["part"], item["subname"], item["source_connection"])
                    for item in endpoint["selected_ani_descriptor_memberships"]
                ],
                [
                    ("PathPart", "ExactSelector", "Root"),
                    ("ChildPart", "ExactSelector", "Child"),
                ],
            )
            self.assertEqual(
                [(item["part"], item["subname"]) for item in endpoint["unselected_ani_descriptor_memberships"]],
                [
                    ("PathPart", "exactselector"),
                    ("PathPart", "NoSelector"),
                ],
            )
            self.assertNotIn(
                "OffPathSelector",
                [
                    occurrence["animation_name"]
                    for occurrence in endpoint["authored_animation_selector_occurrences"]
                ],
            )
            sibling_only = endpoint["authored_animation_selector_occurrences"][1]
            self.assertEqual(
                [(item["part"], item["subname"]) for item in sibling_only["selector_connection_ani_descriptors"]],
                [("SiblingPart", "SiblingOnly")],
            )
            self.assertEqual(
                sibling_only["selected_endpoint_path_ani_descriptor_memberships"],
                [],
            )
            self.assertEqual(report["authored_animation_selector_descriptor_cardinality"], {"1": 3, "2": 1})
            self.assertEqual(report["endpoint_path_selector_connection_descriptor_cardinality"], {"1": 2, "2": 1})
            self.assertEqual(report["counts"]["endpoint_path_animation_selector_occurrences"], 3)
            self.assertEqual(report["counts"]["conventional_endpoint_path_animation_selector_occurrences"], 3)
            self.assertEqual(report["counts"]["missileturret_endpoint_path_animation_selector_occurrences"], 0)
            self.assertEqual(report["counts"]["selected_endpoint_path_descriptor_memberships"], 2)
            self.assertEqual(report["counts"]["path_local_descriptors_left_unselected"], 2)
            self.assertEqual(report["counts"]["selected_endpoint_path_descriptor_identities"], 2)
            self.assertEqual(report["endpoint_paths_by_selected_descriptor_cardinality"], {"zero": 0, "one": 0, "multiple": 1})
            self.assertEqual(
                report["authored_animation_selector_identity_rule"][
                    "evidence_classification"
                ],
                "shipped-source",
            )
            self.assertEqual(
                report["authored_animation_selector_identity_rule"]["corroboration"][
                    "evidence_classification"
                ],
                "third-party-technique",
            )
            self.assertEqual(
                endpoint["authored_animation_selector_occurrences"][0][
                    "authored_selector_evidence"
                ],
                {"connection": "Root", "name": "ExactSelector"},
            )
            self.assertEqual(report["unresolved_endpoint_path_animation_selectors"], [])
            self.assertEqual(render_json(report), render_json(build_census(roots)))

    def test_duplicate_authored_animation_selector_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/component_a"/>
                  <connections>
                    <connection name="Root">
                      <animations><animation name="Exact"/><animation name="Exact"/></animations>
                      <parts><part name="PathPart"/></parts>
                    </connection>
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
                _ani_bytes(("PathPart", "Exact"))
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn(
                "duplicate_authored_animation_selector_identity",
                caught.exception.codes,
            )

    def test_invalid_connection_owned_part_and_animation_identities_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            roots = _source_roots(Path(tmp))
            _write(
                roots["base"],
                "assets/component.xml",
                """<components><component name="component_a" class="turret">
                  <source geometry="geometry/component_a"/>
                  <connections><connection name="">
                    <animations><animation/></animations>
                    <parts><part/></parts>
                  </connection></connections>
                </component></components>""",
            )
            _write(
                roots["base"],
                "assets/macros.xml",
                _macros(("a_macro", "turret", "component_a")),
            )
            with self.assertRaises(CensusError) as caught:
                build_census(roots)
            self.assertIn("malformed_connection_identity", caught.exception.codes)
            self.assertIn("invalid_source_part_ownership", caught.exception.codes)
            self.assertIn("invalid_authored_connection_animation", caught.exception.codes)


if __name__ == "__main__":
    unittest.main()
