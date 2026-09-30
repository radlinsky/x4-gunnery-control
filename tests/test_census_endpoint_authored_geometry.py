#!/usr/bin/env python3
"""Issue #83 B3 characterization: endpoint authored source-geometry chain.

Pins the real _derive_endpoint_authored_geometry() on tiny in-memory census
records only: it pairs each traversed source part with its owning connection
and preserves, per layer, that connection's authored offset, the part's
private authored offset, and the layer's authored restrictions, plus the
endpoint connection's own authored offset as the final leaf. Offsets are
copied verbatim; no ANI records, matrix composition, or muzzle math. Fails
closed unless each source part identifies exactly one owning-connection
transform record. No XML, filesystem, or real X4 data.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    _derive_endpoint_authored_geometry,
)


def _offset(tag: str) -> dict[str, object]:
    """Opaque authored-offset marker; the derivation copies it verbatim."""

    return {"marker": tag}


def _connection(
    name: str,
    *,
    authored_offset: dict[str, object],
    owned_part_transforms: list[tuple[str, object]] | None = None,
    authored_restrictions: list[dict[str, object]] | None = None,
) -> dict[str, object]:
    return {
        "name": name,
        "_authored_offset": authored_offset,
        "_direct_owned_part_transforms": [
            {"name": part, "_authored_offset": part_offset}
            for part, part_offset in (owned_part_transforms or [])
        ],
        "authored_restrictions": authored_restrictions or [],
    }


def _endpoint(connection: str, edges: list[tuple[str, str, str]]) -> dict[str, object]:
    return {
        "connection": connection,
        "traversed_connection_edges": [
            {
                "parent_connection": parent,
                "child_connection": child,
                "child_parent_part": part,
            }
            for parent, child, part in edges
        ],
    }


class EndpointAuthoredGeometryTests(unittest.TestCase):
    @staticmethod
    def _derive(endpoint, connections):
        return _derive_endpoint_authored_geometry(
            endpoint,
            connections,
            component="component_a",
            source_set=Path("x4"),
            source_file=Path("component.xml"),
        )

    def test_ordered_multi_part_chain_preserves_connection_and_part_offsets(self):
        connections = [
            _connection(
                "root",
                authored_offset=_offset("root_conn"),
                owned_part_transforms=[("part_a", _offset("part_a"))],
                authored_restrictions=[{"source_connection": "root"}],
            ),
            _connection(
                "child",
                authored_offset=_offset("child_conn"),
                owned_part_transforms=[("part_b", _offset("part_b"))],
                authored_restrictions=[{"source_connection": "child"}],
            ),
            _connection("muzzle", authored_offset=_offset("muzzle_conn")),
        ]
        endpoint = _endpoint(
            "muzzle",
            [("root", "child", "part_a"), ("child", "muzzle", "part_b")],
        )

        chain, anomalies = self._derive(endpoint, connections)

        self.assertEqual(anomalies, [])
        self.assertEqual(
            chain,
            {
                "endpoint_connection": "muzzle",
                "source_geometry_layers": [
                    {
                        "source_part": "part_a",
                        "owning_connection": "root",
                        "connection_authored_offset": _offset("root_conn"),
                        "part_authored_offset": _offset("part_a"),
                        "authored_restrictions": [{"source_connection": "root"}],
                    },
                    {
                        "source_part": "part_b",
                        "owning_connection": "child",
                        "connection_authored_offset": _offset("child_conn"),
                        "part_authored_offset": _offset("part_b"),
                        "authored_restrictions": [{"source_connection": "child"}],
                    },
                ],
                "endpoint_authored_offset": _offset("muzzle_conn"),
            },
        )

    def test_offset_less_part_transform_remains_valid(self):
        connections = [
            _connection(
                "root",
                authored_offset=_offset("root_conn"),
                owned_part_transforms=[("part_a", None)],
            ),
            _connection("muzzle", authored_offset=_offset("muzzle_conn")),
        ]
        endpoint = _endpoint("muzzle", [("root", "muzzle", "part_a")])

        chain, anomalies = self._derive(endpoint, connections)

        self.assertEqual(anomalies, [])
        self.assertEqual(chain["source_geometry_layers"][0]["part_authored_offset"], None)

    def test_missing_part_transform_fails_closed(self):
        connections = [
            _connection("root", authored_offset=_offset("root_conn")),
            _connection("muzzle", authored_offset=_offset("muzzle_conn")),
        ]
        endpoint = _endpoint("muzzle", [("root", "muzzle", "part_a")])

        chain, anomalies = self._derive(endpoint, connections)

        self.assertIsNone(chain)
        self.assertEqual(
            [item["code"] for item in anomalies],
            ["missing_source_part_transform_identity"],
        )

    def test_duplicate_part_transform_fails_closed(self):
        connections = [
            _connection(
                "root",
                authored_offset=_offset("root_conn"),
                owned_part_transforms=[
                    ("part_a", _offset("first")),
                    ("part_a", _offset("second")),
                ],
            ),
            _connection("muzzle", authored_offset=_offset("muzzle_conn")),
        ]
        endpoint = _endpoint("muzzle", [("root", "muzzle", "part_a")])

        chain, anomalies = self._derive(endpoint, connections)

        self.assertIsNone(chain)
        self.assertEqual(
            [item["code"] for item in anomalies],
            ["ambiguous_source_part_transform_identity"],
        )


if __name__ == "__main__":
    unittest.main()
