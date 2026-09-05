#!/usr/bin/env python3
"""Focused regression tests for accepted Issue #83 source-semantic recognition."""
from __future__ import annotations

import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_ani_parser import _ANI_CHANNEL_COUNT_FIELDS  # noqa: E402
from census_source_semantics import (  # noqa: E402
    _resolve_supported_endpoint_source_semantics,
)


def _record(index: int, values: tuple[float, float, float]) -> dict[str, object]:
    bits = [
        f"0x{struct.unpack('<I', struct.pack('<f', value))[0]:08x}"
        for value in values
    ]
    return {"record_index": index, "raw_bits": bits, "raw_values": list(values)}


def _descriptor(
    edge_index: int,
    counts: tuple[int, int, int, int, int],
    channel_values: dict[int, tuple[float, float, float]] | None = None,
) -> dict[str, object]:
    records = []
    channels = {}
    record_index = 0
    channel_values = channel_values or {}
    for channel_index, (field, count) in enumerate(
        zip(_ANI_CHANNEL_COUNT_FIELDS, counts)
    ):
        start = record_index
        for _ in range(count):
            records.append(
                _record(
                    record_index,
                    channel_values.get(channel_index, (0.0, 0.0, 0.0)),
                )
            )
            record_index += 1
        channels[field] = {
            "record_range": {"start": start, "end_exclusive": record_index}
        }
    return {
        "descriptor_index": edge_index,
        "part": f"part_{edge_index}",
        "subname": "turret_active",
        "channel_counts": dict(zip(_ANI_CHANNEL_COUNT_FIELDS, counts)),
        "key_data": {"channels": channels},
        "_candidate_raw_key_records": records,
        "source_connection": f"connection_{edge_index}",
        "endpoint_path_edge_index": edge_index,
    }


def _endpoint(
    covered: list[dict[str, object]],
    *,
    depth: int,
    selected: list[dict[str, object]] | None = None,
) -> dict[str, object]:
    return {
        "source_part_path": [f"part_{index}" for index in range(depth)],
        "selected_ani_descriptor_memberships": selected or [],
        "_ancestry_covered_turret_active_descriptor_memberships": covered,
    }


def _restriction(
    type_token: str, minimum: float | None = None, maximum: float | None = None
) -> dict[str, object]:
    def bound(value):
        return None if value is None else {"candidate_numeric_value": value}

    return {
        "type_token": type_token,
        "authored_min": bound(minimum),
        "authored_max": bound(maximum),
    }


def _geometry(depth: int, *, rank2_restrictions: bool = False) -> dict[str, object]:
    layers = [
        {
            "source_part": f"part_{index}",
            "owning_connection": f"connection_{index}",
            "connection_authored_offset": {"marker": f"connection_{index}"},
            "part_authored_offset": {"marker": f"part_{index}"},
            "authored_restrictions": [],
        }
        for index in range(depth)
    ]
    if rank2_restrictions:
        layers[3]["authored_restrictions"] = [_restriction("rotation_y")]
        layers[4]["authored_restrictions"] = [
            _restriction("rotation_x", -10.0, 89.0)
        ]
    return {
        "endpoint_connection": "endpoint",
        "source_geometry_layers": layers,
        "endpoint_authored_offset": {"marker": "endpoint"},
    }


class SourceSemanticTests(unittest.TestCase):
    def test_depth4_translation_signature_is_name_free_and_applied(self) -> None:
        covered = [
            _descriptor(0, (0, 0, 0, 0, 0)),
            _descriptor(
                1,
                (2, 0, 0, 0, 0),
                {0: (0.0, 6.145042419433594, 0.0)},
            ),
            _descriptor(2, (0, 0, 0, 0, 0)),
            _descriptor(
                3,
                (2, 0, 0, 0, 0),
                {0: (0.0, -0.23982000350952148, 27.710205078125)},
            ),
        ]
        geometry = _geometry(4)

        result = _resolve_supported_endpoint_source_semantics(
            _endpoint(covered, depth=4),
            geometry,
            component_endpoint_count=2,
        )

        self.assertEqual(result["classification"], "SOURCE_RESOLVED")
        self.assertEqual(result["semantic_case"], "depth4_dual_translation")
        applied = result["applied_authored_geometry"]["source_geometry_layers"]
        self.assertEqual(
            applied[1]["settled_local_position_delta"],
            [0.0, 6.145042419433594, 0.0],
        )
        self.assertEqual(
            applied[3]["settled_local_position_delta"],
            [0.0, -0.23982000350952148, 27.710205078125],
        )
        self.assertNotIn(
            "settled_local_position_delta", geometry["source_geometry_layers"][1]
        )

    def test_rank2_signature_applies_rotation_and_optional_channel0_residue(self) -> None:
        for with_residue in (False, True):
            with self.subTest(with_residue=with_residue):
                edge2_counts = (
                    (2, 2, 0, 0, 0) if with_residue else (0, 2, 0, 0, 0)
                )
                edge2_values = {1: (0.6108652353286743, -0.0, 0.0)}
                if with_residue:
                    edge2_values[0] = (
                        4.6193599700927734e-7,
                        8.195638656616211e-8,
                        -2.7567148208618164e-7,
                    )
                covered = [
                    _descriptor(0, (2, 0, 0, 0, 0), {0: (0.0, 0.0, 0.0)}),
                    _descriptor(
                        1,
                        (0, 2, 0, 0, 0),
                        {1: (-0.6108652353286743, -0.0, 0.0)},
                    ),
                    _descriptor(2, edge2_counts, edge2_values),
                    _descriptor(3, (0, 0, 0, 0, 0)),
                    _descriptor(4, (0, 0, 0, 0, 0)),
                ]
                selected = [
                    _descriptor(20 + index, (2, 0, 0, 0, 0))
                    for index in range(4)
                ]

                result = _resolve_supported_endpoint_source_semantics(
                    _endpoint(covered, depth=5, selected=selected),
                    _geometry(5, rank2_restrictions=True),
                    component_endpoint_count=2,
                )

                self.assertEqual(result["classification"], "SOURCE_RESOLVED")
                self.assertEqual(
                    result["semantic_case"], "depth5_additive_x_rotation"
                )
                layers = result["applied_authored_geometry"][
                    "source_geometry_layers"
                ]
                self.assertEqual(
                    layers[1]["settled_local_euler_xyz_delta_radians"],
                    [0.6108652353286743, -0.0, 0.0],
                )
                self.assertEqual(
                    layers[2]["settled_local_euler_xyz_delta_radians"],
                    [-0.6108652353286743, -0.0, 0.0],
                )
                if with_residue:
                    self.assertEqual(
                        layers[2]["settled_local_position_delta"],
                        [
                            -4.6193599700927734e-7,
                            8.195638656616211e-8,
                            -2.7567148208618164e-7,
                        ],
                    )
                else:
                    self.assertNotIn("settled_local_position_delta", layers[2])

    def test_near_match_fails_closed(self) -> None:
        covered = [
            _descriptor(0, (0, 0, 0, 0, 0)),
            _descriptor(1, (2, 0, 0, 0, 0), {0: (0.0, 6.145, 0.0)}),
            _descriptor(2, (0, 0, 0, 0, 0)),
            _descriptor(
                3,
                (2, 0, 0, 0, 0),
                {0: (0.0, -0.23982000350952148, 27.710205078125)},
            ),
        ]

        result = _resolve_supported_endpoint_source_semantics(
            _endpoint(covered, depth=4),
            _geometry(4),
            component_endpoint_count=2,
        )

        self.assertEqual(
            result,
            {
                "classification": "UNSUPPORTED",
                "reason": "no_accepted_source_semantic_signature",
            },
        )


if __name__ == "__main__":
    unittest.main()
