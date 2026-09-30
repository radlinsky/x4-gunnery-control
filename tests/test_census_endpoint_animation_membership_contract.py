#!/usr/bin/env python3
"""Issue #78 R1 characterization: ANI descriptor / authored selector membership.

Pins the real _derive_endpoint_source_paths() on its ANI descriptor and
authored animation selector joining behavior against tiny in-memory
connection, endpoint, descriptor, and selector records only. The single
scenario mirrors the monolith ExactSelector / case-mismatch / off-path
scenario at the helper level and pins, on one focused traversed path:

- ANI membership requires the descriptor's source_connection to be the
  traversed edge parent AND its part to equal that edge's child parent-part;
- endpoint_path_edge_index records which traversed edge admitted a descriptor;
- authored selectors are considered only on traversed parent connections;
- selector/subname matching is exact and case-sensitive;
- exact matches appear in selected_ani_descriptor_memberships;
- on-path descriptors without an exact selector match appear in
  unselected_ani_descriptor_memberships;
- off-path descriptors and selectors never enter endpoint-path structures;
- selector occurrences preserve source connection, selector name, edge index,
  and descriptor-match evidence/count.

No XML or filesystem fixtures, no ANI binary parsing, and no production
logic is re-implemented here: the test calls the real helper and pins its
output on the behavioral reference scenario.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    _derive_endpoint_source_paths,
)


def _connection_record(
    name: str,
    *,
    parent_connection: str | None = None,
    parent_part: str | None = None,
    owned_parts: list[str] | None = None,
) -> dict[str, object]:
    """Build one in-memory connection record with only the fields read here."""

    return {
        "name": name,
        "parent_connection": parent_connection,
        "parent_part": parent_part,
        "direct_owned_parts": list(owned_parts or []),
    }


def _endpoint_record(connection: str, path: list[str]) -> dict[str, object]:
    """Build one in-memory endpoint record with the two fields the derivation reads."""

    return {
        "connection": connection,
        "root_to_endpoint_connection_path": list(path),
    }


def _descriptor_record(
    index: int,
    part: str,
    subname: str,
    source_connection: str,
    root_path: list[str],
) -> dict[str, object]:
    """Build one in-memory ANI descriptor record with sentinel identity fields."""

    return {
        "descriptor_index": index,
        "part": part,
        "subname": subname,
        "channel_counts": {
            "position": index,
            "rotation": 0,
            "scale": 0,
            "pre_scale": 0,
            "post_scale": 0,
        },
        "descriptor_offset_148": 148 * (index + 1),
        "key_data": f"key-data-{index}",
        "_candidate_raw_key_records": [f"raw-key-{index}"],
        "source_connection": source_connection,
        "root_to_source_connection_path": list(root_path),
    }


def _selector_record(
    connection: str,
    name: str,
    connection_descriptors: list[dict[str, object]],
    frame_span: dict[str, str] | None = None,
) -> dict[str, object]:
    """Build one in-memory authored selector record shaped like the real join output."""

    return {
        "connection": connection,
        "name": name,
        "_authored_frame_span": frame_span,
        "descriptor_match_count": len(connection_descriptors),
        "connection_ani_descriptors": list(connection_descriptors),
    }


class EndpointAnimationMembershipContractTests(unittest.TestCase):
    def test_traversed_path_membership_is_exact_case_sensitive_and_path_local(
        self,
    ) -> None:
        connections = [
            _connection_record("Root", owned_parts=["PathPart", "SiblingPart"]),
            _connection_record(
                "Child",
                parent_connection="Root",
                parent_part="PathPart",
                owned_parts=["ChildPart"],
            ),
            _connection_record(
                "Endpoint",
                parent_connection="Child",
                parent_part="ChildPart",
            ),
            _connection_record("OffPath", owned_parts=["OffPathPart"]),
        ]
        endpoint = _endpoint_record("Endpoint", ["Root", "Child", "Endpoint"])

        exact_selector_path = _descriptor_record(
            0, "PathPart", "ExactSelector", "Root", ["Root"]
        )
        exact_selector_sibling = _descriptor_record(
            1, "SiblingPart", "ExactSelector", "Root", ["Root"]
        )
        sibling_only = _descriptor_record(
            2, "SiblingPart", "SiblingOnly", "Root", ["Root"]
        )
        case_mismatch = _descriptor_record(
            3, "PathPart", "exactselector", "Root", ["Root"]
        )
        no_selector = _descriptor_record(
            4, "PathPart", "NoSelector", "Root", ["Root"]
        )
        child_exact = _descriptor_record(
            5, "ChildPart", "ExactSelector", "Child", ["Root", "Child"]
        )
        off_path_selector = _descriptor_record(
            6, "OffPathPart", "OffPathSelector", "OffPath", ["OffPath"]
        )
        ani_descriptors = [
            exact_selector_path,
            exact_selector_sibling,
            sibling_only,
            case_mismatch,
            no_selector,
            child_exact,
            off_path_selector,
        ]
        selectors = [
            _selector_record(
                "Root",
                "ExactSelector",
                [exact_selector_path, exact_selector_sibling],
                frame_span={"start": "3", "end": "3"},
            ),
            _selector_record("Root", "SiblingOnly", [sibling_only]),
            _selector_record("Child", "ExactSelector", [child_exact]),
            _selector_record("OffPath", "OffPathSelector", [off_path_selector]),
        ]

        resolved, anomalies = _derive_endpoint_source_paths(
            [endpoint],
            connections,
            ani_descriptors=ani_descriptors,
            authored_animation_selectors=selectors,
            component="component_a",
            source_set=Path("x4"),
            source_file=Path("component.xml"),
        )

        self.assertEqual(anomalies, [])
        self.assertEqual(len(resolved), 1)
        result = resolved[0]
        self.assertEqual(result["connection"], "Endpoint")
        self.assertEqual(
            result["traversed_connection_edges"],
            [
                {
                    "parent_connection": "Root",
                    "child_connection": "Child",
                    "child_parent_part": "PathPart",
                },
                {
                    "parent_connection": "Child",
                    "child_connection": "Endpoint",
                    "child_parent_part": "ChildPart",
                },
            ],
        )

        # Membership requires the descriptor's source_connection to be the
        # traversed edge parent AND its part to equal that edge's child
        # parent-part. SiblingPart descriptors share Root but not PathPart;
        # OffPath is never a traversed parent. Membership order is per edge,
        # in descriptor input order.
        self.assertEqual(
            [
                (
                    item["part"],
                    item["subname"],
                    item["source_connection"],
                    item["endpoint_path_edge_index"],
                )
                for item in result["ani_descriptor_memberships"]
            ],
            [
                ("PathPart", "ExactSelector", "Root", 0),
                ("PathPart", "exactselector", "Root", 0),
                ("PathPart", "NoSelector", "Root", 0),
                ("ChildPart", "ExactSelector", "Child", 1),
            ],
        )
        self.assertEqual(
            [item["descriptor_index"] for item in result["ani_descriptor_memberships"]],
            [0, 3, 4, 5],
        )
        membership_identities = {
            (item["part"], item["subname"], item["source_connection"])
            for item in result["ani_descriptor_memberships"]
        }
        self.assertNotIn(
            ("SiblingPart", "ExactSelector", "Root"), membership_identities
        )
        self.assertNotIn(("SiblingPart", "SiblingOnly", "Root"), membership_identities)
        self.assertNotIn(
            ("OffPathPart", "OffPathSelector", "OffPath"), membership_identities
        )
        self.assertEqual(
            result["ani_descriptor_memberships"][0],
            {
                "descriptor_index": 0,
                "part": "PathPart",
                "subname": "ExactSelector",
                "channel_counts": {
                    "position": 0,
                    "rotation": 0,
                    "scale": 0,
                    "pre_scale": 0,
                    "post_scale": 0,
                },
                "descriptor_offset_148": 148,
                "key_data": "key-data-0",
                "_candidate_raw_key_records": ["raw-key-0"],
                "source_connection": "Root",
                "root_to_source_connection_path": ["Root"],
                "endpoint_path_edge_index": 0,
            },
        )

        # Authored selectors are considered only on traversed parent
        # connections: the OffPath selector never appears, and occurrences
        # preserve source connection, name, edge index, and match count.
        occurrences = result["authored_animation_selector_occurrences"]
        self.assertEqual(
            [
                (
                    item["source_connection"],
                    item["animation_name"],
                    item["endpoint_path_edge_index"],
                    item["selector_connection_descriptor_match_count"],
                )
                for item in occurrences
            ],
            [
                ("Root", "ExactSelector", 0, 2),
                ("Root", "SiblingOnly", 0, 1),
                ("Child", "ExactSelector", 1, 1),
            ],
        )
        self.assertNotIn(
            "OffPathSelector", [item["animation_name"] for item in occurrences]
        )
        root_exact, root_sibling_only, child_exact = occurrences
        self.assertEqual(
            root_exact["authored_selector_evidence"],
            {"connection": "Root", "name": "ExactSelector"},
        )
        self.assertEqual(
            child_exact["authored_selector_evidence"],
            {"connection": "Child", "name": "ExactSelector"},
        )
        # Authored frame-span evidence rides along per occurrence.
        self.assertEqual(root_exact["_authored_frame_span"], {"start": "3", "end": "3"})
        self.assertIsNone(child_exact["_authored_frame_span"])
        # Connection-local match evidence is preserved as authored: Root's
        # ExactSelector still counts its SiblingPart connection-local match
        # even though that part is not on the traversed path.
        self.assertEqual(
            [
                (item["part"], item["subname"])
                for item in root_exact["selector_connection_ani_descriptors"]
            ],
            [("PathPart", "ExactSelector"), ("SiblingPart", "ExactSelector")],
        )
        # Only path-local memberships are selected by a selector; the
        # connection-local SiblingPart match never becomes a selection.
        self.assertEqual(
            [
                (item["part"], item["subname"], item["endpoint_path_edge_index"])
                for item in root_exact["selected_endpoint_path_ani_descriptor_memberships"]
            ],
            [("PathPart", "ExactSelector", 0)],
        )
        # Selector/subname matching is exact and case-sensitive: the
        # "exactselector" descriptor neither selects here nor via
        # "ExactSelector", leaving SiblingOnly with zero path matches.
        self.assertEqual(root_sibling_only["selected_endpoint_path_ani_descriptor_memberships"], [])
        self.assertEqual(
            root_sibling_only["selector_connection_descriptor_match_count"],
            1,
        )
        self.assertEqual(
            [
                (item["part"], item["subname"])
                for item in child_exact["selected_endpoint_path_ani_descriptor_memberships"]
            ],
            [("ChildPart", "ExactSelector")],
        )

        # Exact matches become selected memberships, annotated with their
        # selector evidence; everything else on the path is unselected.
        self.assertEqual(
            [
                (
                    item["part"],
                    item["subname"],
                    item["source_connection"],
                    item["endpoint_path_edge_index"],
                )
                for item in result["selected_ani_descriptor_memberships"]
            ],
            [
                ("PathPart", "ExactSelector", "Root", 0),
                ("ChildPart", "ExactSelector", "Child", 1),
            ],
        )
        self.assertEqual(
            [item["authored_selector_evidence"] for item in result["selected_ani_descriptor_memberships"]],
            [
                {"connection": "Root", "name": "ExactSelector"},
                {"connection": "Child", "name": "ExactSelector"},
            ],
        )
        self.assertEqual(
            [
                (
                    item["part"],
                    item["subname"],
                    item["source_connection"],
                    item["endpoint_path_edge_index"],
                )
                for item in result["unselected_ani_descriptor_memberships"]
            ],
            [
                ("PathPart", "exactselector", "Root", 0),
                ("PathPart", "NoSelector", "Root", 0),
            ],
        )


if __name__ == "__main__":
    unittest.main()
