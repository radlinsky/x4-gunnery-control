#!/usr/bin/env python3
"""Issue #78 R1 characterization: endpoint source-path derivation contract.

Pins the real _derive_endpoint_source_paths() on its structural path/edge
behavior against tiny in-memory records only: exact traversed connection
edges, root-to-endpoint path validity, and source-part ownership. ANI
descriptor membership and authored animation-selector behavior are
deliberately deferred: both inputs are pinned empty. No connection-hierarchy
resolution, no XML or filesystem fixtures, and no real X4 data.
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
    """Build one in-memory connection record with only the structural fields read here."""

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


class EndpointSourcePathContractTests(unittest.TestCase):
    @staticmethod
    def _derive(
        endpoints: list[dict[str, object]],
        connections: list[dict[str, object]],
    ) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
        return _derive_endpoint_source_paths(
            endpoints,
            connections,
            ani_descriptors=[],
            authored_animation_selectors=[],
            component="component_a",
            source_set=Path("x4"),
            source_file=Path("component.xml"),
        )

    def test_valid_three_connection_endpoint_path_resolves_edges_and_source_parts(
        self,
    ) -> None:
        connections = [
            _connection_record("root", owned_parts=["part_a"]),
            _connection_record(
                "child",
                parent_connection="root",
                parent_part="part_a",
                owned_parts=["part_b"],
            ),
            _connection_record(
                "muzzle",
                parent_connection="child",
                parent_part="part_b",
            ),
        ]
        endpoint = _endpoint_record("muzzle", ["root", "child", "muzzle"])

        resolved, anomalies = self._derive([endpoint], connections)

        self.assertEqual(anomalies, [])
        self.assertEqual(len(resolved), 1)
        self.assertEqual(resolved[0]["connection"], "muzzle")
        self.assertEqual(
            resolved[0]["traversed_connection_edges"],
            [
                {
                    "parent_connection": "root",
                    "child_connection": "child",
                    "child_parent_part": "part_a",
                },
                {
                    "parent_connection": "child",
                    "child_connection": "muzzle",
                    "child_parent_part": "part_b",
                },
            ],
        )
        self.assertEqual(resolved[0]["source_part_path"], ["part_a", "part_b"])
        self.assertEqual(resolved[0]["ani_descriptor_memberships"], [])
        self.assertEqual(
            resolved[0]["authored_animation_selector_occurrences"], []
        )
        self.assertEqual(resolved[0]["selected_ani_descriptor_memberships"], [])
        self.assertEqual(
            resolved[0]["unselected_ani_descriptor_memberships"], []
        )

    def test_endpoint_path_not_terminating_at_endpoint_connection_is_unresolvable(
        self,
    ) -> None:
        connections = [
            _connection_record("root", owned_parts=["part_a"]),
            _connection_record(
                "child",
                parent_connection="root",
                parent_part="part_a",
                owned_parts=["part_b"],
            ),
            _connection_record(
                "muzzle",
                parent_connection="child",
                parent_part="part_b",
            ),
        ]
        endpoint = _endpoint_record("muzzle", ["root", "child"])

        resolved, anomalies = self._derive([endpoint], connections)

        self.assertEqual(resolved, [])
        self.assertEqual(
            [item["code"] for item in anomalies],
            ["unresolvable_endpoint_connection_path"],
        )

    def test_edge_child_part_not_owned_by_parent_connection_is_invalid_ownership(
        self,
    ) -> None:
        connections = [
            _connection_record("root", owned_parts=["part_a"]),
            _connection_record(
                "child",
                parent_connection="root",
                parent_part="part_z",
                owned_parts=["part_b"],
            ),
            _connection_record(
                "muzzle",
                parent_connection="child",
                parent_part="part_b",
            ),
        ]
        endpoint = _endpoint_record("muzzle", ["root", "child", "muzzle"])

        resolved, anomalies = self._derive([endpoint], connections)

        self.assertEqual(resolved, [])
        self.assertEqual(
            [item["code"] for item in anomalies],
            ["invalid_endpoint_edge_ownership"],
        )


if __name__ == "__main__":
    unittest.main()
