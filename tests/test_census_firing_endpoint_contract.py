#!/usr/bin/env python3
"""Issue #78 R1 characterization: firing-endpoint classification contract.

Pins the real _classify_firing_endpoints() against tiny in-memory connection
records only: endpoint identity, authored-evidence fields, root-to-endpoint
paths, and the per-connection anomaly codes. No connection-hierarchy
resolution, no ANI descriptors, no XML or filesystem fixtures, no real X4
data, no unsupported component classes, and no macro-class accounting.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    _classify_firing_endpoints,
)


def _firing_connection(
    name: str,
    *,
    tag_tokens: list[str] | None = None,
    authored_tags: str | None = None,
    root_to_connection_path: list[str] | None = None,
) -> dict[str, object]:
    """Build one in-memory connection record with only the fields the classifier reads."""

    return {
        "name": name,
        "tag_tokens": list(tag_tokens or []),
        "authored_tags": authored_tags,
        "root_to_connection_path": list(root_to_connection_path or []),
    }


class FiringEndpointContractTests(unittest.TestCase):
    @staticmethod
    def _classify(
        connections: list[dict[str, object]],
        *,
        component_class: str,
        macros: list[str] | None = None,
    ) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
        return _classify_firing_endpoints(
            connections,
            component="component_a",
            component_class=component_class,
            macros=list(macros or ["macro_a"]),
            macro_classes=[component_class],
            source_set=Path("x4"),
            source_file=Path("component.xml"),
        )

    def test_turret_laser_connection_classifies_endpoint_with_authored_evidence(self) -> None:
        connection = _firing_connection(
            "conn_laser",
            tag_tokens=["laser"],
            authored_tags="laser ",
            root_to_connection_path=["root", "conn_laser"],
        )

        endpoints, anomalies = self._classify([connection], component_class="turret")

        self.assertEqual(anomalies, [])
        self.assertEqual(len(endpoints), 1)
        self.assertEqual(endpoints[0]["connection"], "conn_laser")
        self.assertEqual(
            endpoints[0]["authored_evidence"],
            {"tag_attribute": "laser ", "tag_token": "laser"},
        )
        self.assertEqual(
            endpoints[0]["root_to_endpoint_connection_path"],
            ["root", "conn_laser"],
        )

    def test_missileturret_rocket_connection_classifies_endpoint(self) -> None:
        connection = _firing_connection(
            "conn_rocket",
            tag_tokens=["rocket"],
            authored_tags="rocket",
            root_to_connection_path=["root", "conn_rocket"],
        )

        endpoints, anomalies = self._classify(
            [connection], component_class="missileturret"
        )

        self.assertEqual(anomalies, [])
        self.assertEqual(len(endpoints), 1)
        self.assertEqual(endpoints[0]["authored_evidence"]["tag_token"], "rocket")
        self.assertEqual(
            endpoints[0]["root_to_endpoint_connection_path"],
            ["root", "conn_rocket"],
        )

    def test_turret_without_role_tag_reports_missing_identity(self) -> None:
        connection = _firing_connection("conn_plain", tag_tokens=[])

        endpoints, anomalies = self._classify([connection], component_class="turret")

        self.assertEqual(endpoints, [])
        self.assertEqual(
            [item["code"] for item in anomalies],
            ["missing_firing_endpoint_identity"],
        )

    def test_turret_with_rocket_tag_reports_ambiguous_evidence(self) -> None:
        connection = _firing_connection("conn_rocket", tag_tokens=["rocket"])

        endpoints, anomalies = self._classify([connection], component_class="turret")

        self.assertEqual(endpoints, [])
        self.assertEqual(
            [item["code"] for item in anomalies],
            ["ambiguous_endpoint_evidence"],
        )

    def test_turret_with_repeated_laser_tag_reports_malformed_evidence(self) -> None:
        connection = _firing_connection("conn_laser", tag_tokens=["laser", "laser"])

        endpoints, anomalies = self._classify([connection], component_class="turret")

        self.assertEqual(endpoints, [])
        self.assertEqual(
            [item["code"] for item in anomalies],
            ["malformed_endpoint_evidence"],
        )


if __name__ == "__main__":
    unittest.main()
