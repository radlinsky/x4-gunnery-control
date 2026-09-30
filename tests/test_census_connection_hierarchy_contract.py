#!/usr/bin/env python3
"""Issue #78 R1 characterization: connection hierarchy/path resolution contract.

Pins the real _resolve_connection_hierarchy() against tiny in-memory records
only: exact connection identity, parent-connection resolution, root-to-
connection paths, depths, and source-part ownership. No firing-endpoint
classification, no ANI descriptors, no XML or filesystem fixtures, and no
real X4 data.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    _resolve_connection_hierarchy,
)


def _connection_record(
    name: str,
    *,
    parent_part: str | None = None,
    owned_parts: list[str] | None = None,
) -> dict[str, object]:
    """Build one in-memory connection record with every field the resolver reads."""

    return {
        "name": name,
        "parent_part": parent_part,
        "direct_owned_parts": list(owned_parts or []),
        "authored_attributes": {},
        "authored_tags": [],
        "tag_tokens": [],
        "authored_restrictions": [],
        "authored_offset": {},
    }


class ConnectionHierarchyContractTests(unittest.TestCase):
    @staticmethod
    def _resolve(records: list[dict[str, object]]):
        return _resolve_connection_hierarchy(
            records,
            component="component_a",
            source_set=Path("x4"),
            source_file=Path("component.xml"),
        )

    def test_valid_three_connection_hierarchy_resolves_paths_and_depths(self) -> None:
        records = [
            _connection_record("root", owned_parts=["part_a"]),
            _connection_record("child", parent_part="part_a", owned_parts=["part_b"]),
            _connection_record("leaf", parent_part="part_b"),
        ]

        connections, source_part_owners, anomalies = self._resolve(records)

        self.assertEqual(anomalies, [])
        self.assertEqual(
            {item["name"]: item["parent_connection"] for item in connections},
            {"root": None, "child": "root", "leaf": "child"},
        )
        self.assertEqual(
            {item["name"]: item["root_to_connection_path"] for item in connections},
            {
                "root": ["root"],
                "child": ["root", "child"],
                "leaf": ["root", "child", "leaf"],
            },
        )
        self.assertEqual(
            {item["name"]: item["depth"] for item in connections},
            {"root": 0, "child": 1, "leaf": 2},
        )
        self.assertEqual(
            source_part_owners,
            {"part_a": ["root"], "part_b": ["child"]},
        )

    def test_parent_part_without_owner_returns_unresolved_anomaly_and_no_connections(
        self,
    ) -> None:
        records = [
            _connection_record("root", owned_parts=["part_a"]),
            _connection_record("orphan", parent_part="part_z"),
        ]

        connections, _owners, anomalies = self._resolve(records)

        self.assertEqual(connections, [])
        self.assertEqual(
            [item["code"] for item in anomalies],
            ["unresolved_parent_part_reference"],
        )

    def test_duplicate_connection_names_return_duplicate_anomaly_and_no_connections(
        self,
    ) -> None:
        records = [
            _connection_record("same", owned_parts=["part_a"]),
            _connection_record("same", owned_parts=["part_b"]),
        ]

        connections, _owners, anomalies = self._resolve(records)

        self.assertEqual(connections, [])
        self.assertEqual(
            [item["code"] for item in anomalies],
            ["duplicate_connection_identity"],
        )


if __name__ == "__main__":
    unittest.main()
