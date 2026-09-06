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


_STEP_BITS = "0x00000001"


def _record(
    index: int,
    values: tuple[float, float, float],
    *,
    interp_bits: str = _STEP_BITS,
) -> dict[str, object]:
    bits = [
        f"0x{struct.unpack('<I', struct.pack('<f', value))[0]:08x}"
        for value in values
    ]
    # Slots 3-5 are the enum32 interpolation fields; default to STEP.
    bits += [interp_bits, interp_bits, interp_bits]
    return {"record_index": index, "raw_bits": bits, "raw_values": list(values)}


def _descriptor(
    edge_index: int,
    counts: tuple[int, int, int, int, int],
    channel_values: dict[int, tuple[float, float, float]] | None = None,
    *,
    subname: str = "turret_active",
    interp_bits: str = _STEP_BITS,
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
                    interp_bits=interp_bits,
                )
            )
            record_index += 1
        channels[field] = {
            "record_range": {"start": start, "end_exclusive": record_index}
        }
    return {
        "descriptor_index": edge_index,
        "part": f"part_{edge_index}",
        "subname": subname,
        "channel_counts": dict(zip(_ANI_CHANNEL_COUNT_FIELDS, counts)),
        "key_data": {"channels": channels},
        "_candidate_raw_key_records": records,
        "source_connection": f"connection_{edge_index}",
        "endpoint_path_edge_index": edge_index,
    }


def _one_frame_selector(animation_name: str = "turret_active", frame: int = 0) -> dict[str, object]:
    """Authored animation selector occurrence for a one-frame animation."""
    return {
        "animation_name": animation_name,
        "_authored_frame_span": {"start": str(frame), "end": str(frame)},
        "selector_connection_descriptor_match_count": 1,
        "selector_connection_ani_descriptors": [],
        "selected_endpoint_path_ani_descriptor_memberships": [],
    }


def _endpoint(
    covered: list[dict[str, object]],
    *,
    depth: int,
    selected: list[dict[str, object]] | None = None,
    ani_descriptor_memberships: list[dict[str, object]] | None = None,
    authored_animation_selector_occurrences: list[dict[str, object]] | None = None,
) -> dict[str, object]:
    return {
        "source_part_path": [f"part_{index}" for index in range(depth)],
        "selected_ani_descriptor_memberships": selected or [],
        "_ancestry_covered_turret_active_descriptor_memberships": covered,
        "ani_descriptor_memberships": ani_descriptor_memberships if ani_descriptor_memberships is not None else [],
        "authored_animation_selector_occurrences": authored_animation_selector_occurrences if authored_animation_selector_occurrences is not None else [],
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


def _geometry(
    depth: int,
    *,
    rank2_restrictions: bool = False,
    one_key_barrel_restrictions: bool = False,
    one_key_barrel_pitch_max: float = 90.0,
) -> dict[str, object]:
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
    if one_key_barrel_restrictions and depth >= 3:
        layers[1]["authored_restrictions"] = [_restriction("rotation_y")]
        layers[2]["authored_restrictions"] = [
            _restriction("rotation_x", -10.0, one_key_barrel_pitch_max)
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

    def test_depth4_zero_translation_signature_is_recognized(self) -> None:
        covered = [
            _descriptor(0, (0, 0, 0, 0, 0)),
            _descriptor(1, (0, 0, 0, 0, 0)),
            _descriptor(2, (2, 0, 0, 0, 0), {0: (0.0, 0.0, 0.0)}),
            _descriptor(3, (2, 0, 0, 0, 0), {0: (0.0, 0.0, 0.0)}),
        ]

        result = _resolve_supported_endpoint_source_semantics(
            _endpoint(covered, depth=4),
            _geometry(4),
            component_endpoint_count=2,
        )

        self.assertEqual(result["classification"], "SOURCE_RESOLVED")
        self.assertEqual(result["semantic_case"], "depth4_zero_translation")
        applied = result["applied_authored_geometry"]["source_geometry_layers"]
        for index in (2, 3):
            self.assertEqual(
                applied[index]["settled_local_position_delta"], [0.0, 0.0, 0.0]
            )
        for index in (0, 1):
            self.assertNotIn("settled_local_position_delta", applied[index])

    def test_single_key_zero_translation_fails_closed(self) -> None:
        # The *_m_plasma_02 one-key groups share the zero values but not the
        # proved two-record signature.
        covered = [
            _descriptor(0, (0, 0, 0, 0, 0)),
            _descriptor(1, (0, 0, 0, 0, 0)),
            _descriptor(2, (1, 0, 0, 0, 0), {0: (0.0, 0.0, 0.0)}),
            _descriptor(3, (1, 0, 0, 0, 0), {0: (0.0, 0.0, 0.0)}),
        ]

        result = _resolve_supported_endpoint_source_semantics(
            _endpoint(covered, depth=4),
            _geometry(4),
            component_endpoint_count=2,
        )

        self.assertEqual(result["classification"], "UNSUPPORTED")

    def test_nonzero_translation_on_zero_signature_fails_closed(self) -> None:
        covered = [
            _descriptor(0, (0, 0, 0, 0, 0)),
            _descriptor(1, (0, 0, 0, 0, 0)),
            _descriptor(2, (2, 0, 0, 0, 0), {0: (0.0, 0.0, 0.0)}),
            _descriptor(3, (2, 0, 0, 0, 0), {0: (0.0, 0.0, 1e-7)}),
        ]

        result = _resolve_supported_endpoint_source_semantics(
            _endpoint(covered, depth=4),
            _geometry(4),
            component_endpoint_count=2,
        )

        self.assertEqual(result["classification"], "UNSUPPORTED")

    # --- one-key barrel helpers ---

    _PLASMA_02_ROTATOR = (0.0, 2.962090492248535, 0.0)
    _PLASMA_02_BARREL = (0.0, -3.575999869553925e-07, 3.3641886711120605)
    _LASER_02_ROTATOR = (0.0, 2.962090492248535, 0.0)
    _LASER_02_BARREL = (0.0, 0.0, 3.521183967590332)

    def _one_key_barrel_covered(
        self,
        barrel: tuple[float, float, float],
        rotator: tuple[float, float, float] | None = None,
        barrel_count: int = 1,
        barrel_interp_bits: str = _STEP_BITS,
    ) -> list[dict[str, object]]:
        if rotator is None:
            rotator = self._PLASMA_02_ROTATOR
        return [
            _descriptor(0, (0, 0, 0, 0, 0)),
            _descriptor(1, (2, 0, 0, 0, 0), {0: rotator}),
            _descriptor(2, (0, 0, 0, 0, 0)),
            _descriptor(3, (barrel_count, 0, 0, 0, 0), {0: barrel}, interp_bits=barrel_interp_bits),
        ]

    def _one_key_barrel_boundary_memberships(
        self,
        barrel: tuple[float, float, float],
    ) -> list[dict[str, object]]:
        """Boundary descriptors at edge 3 consistent with the given barrel value."""
        # turret_activating: two keys, last one matches barrel
        activating = _descriptor(
            3, (2, 0, 0, 0, 0),
            {0: barrel},
            subname="turret_activating",
        )
        # turret_deactivating: two keys, first one matches barrel
        deactivating = _descriptor(
            3, (2, 0, 0, 0, 0),
            {0: barrel},
            subname="turret_deactivating",
        )
        return [activating, deactivating]

    def _one_key_barrel_endpoint(
        self,
        barrel: tuple[float, float, float],
        rotator: tuple[float, float, float] | None = None,
        barrel_count: int = 1,
        barrel_interp_bits: str = _STEP_BITS,
        selector_occurrences: list | None = None,
        boundary_memberships: list | None = None,
    ) -> dict[str, object]:
        covered = self._one_key_barrel_covered(
            barrel,
            rotator=rotator,
            barrel_count=barrel_count,
            barrel_interp_bits=barrel_interp_bits,
        )
        if selector_occurrences is None:
            selector_occurrences = [_one_frame_selector("turret_active")]
        if boundary_memberships is None:
            boundary_memberships = self._one_key_barrel_boundary_memberships(barrel)
        return _endpoint(
            covered,
            depth=4,
            ani_descriptor_memberships=boundary_memberships,
            authored_animation_selector_occurrences=selector_occurrences,
        )

    def test_depth4_one_key_barrel_translation_is_recognized(self) -> None:
        """plasma_02 values still resolve and apply exactly as before."""
        barrel = self._PLASMA_02_BARREL

        result = _resolve_supported_endpoint_source_semantics(
            self._one_key_barrel_endpoint(barrel),
            _geometry(4, one_key_barrel_restrictions=True),
            component_endpoint_count=2,
        )

        self.assertEqual(result["classification"], "SOURCE_RESOLVED")
        self.assertEqual(result["semantic_case"], "depth4_one_key_barrel_translation")
        applied = result["applied_authored_geometry"]["source_geometry_layers"]
        self.assertEqual(
            applied[1]["settled_local_position_delta"],
            [0.0, 2.962090492248535, 0.0],
        )
        self.assertEqual(applied[3]["settled_local_position_delta"], list(barrel))

    def test_laser_02_values_resolve_from_source(self) -> None:
        """A different source-derived barrel value resolves and applies that value."""
        barrel = self._LASER_02_BARREL
        rotator = self._LASER_02_ROTATOR

        result = _resolve_supported_endpoint_source_semantics(
            self._one_key_barrel_endpoint(barrel, rotator=rotator),
            _geometry(4, one_key_barrel_restrictions=True),
            component_endpoint_count=2,
        )

        self.assertEqual(result["classification"], "SOURCE_RESOLVED")
        self.assertEqual(result["semantic_case"], "depth4_one_key_barrel_translation")
        applied = result["applied_authored_geometry"]["source_geometry_layers"]
        self.assertEqual(
            applied[1]["settled_local_position_delta"],
            [0.0, 2.962090492248535, 0.0],
        )
        self.assertEqual(applied[3]["settled_local_position_delta"], list(barrel))

    def test_one_key_barrel_fail_closed_subtests(self) -> None:
        """Each subtest flips exactly one structural condition."""
        barrel = self._PLASMA_02_BARREL

        # Non-STEP interpolation on the active key
        with self.subTest("non_step_interp"):
            result = _resolve_supported_endpoint_source_semantics(
                self._one_key_barrel_endpoint(
                    barrel, barrel_interp_bits="0x00000000"
                ),
                _geometry(4, one_key_barrel_restrictions=True),
                component_endpoint_count=2,
            )
            self.assertEqual(result["classification"], "UNSUPPORTED")

        # Multi-frame turret_active selector (start != end)
        with self.subTest("multi_frame_selector"):
            result = _resolve_supported_endpoint_source_semantics(
                self._one_key_barrel_endpoint(
                    barrel,
                    selector_occurrences=[{
                        "animation_name": "turret_active",
                        "_authored_frame_span": {"start": "0", "end": "1"},
                        "selector_connection_descriptor_match_count": 1,
                        "selector_connection_ani_descriptors": [],
                        "selected_endpoint_path_ani_descriptor_memberships": [],
                    }],
                ),
                _geometry(4, one_key_barrel_restrictions=True),
                component_endpoint_count=2,
            )
            self.assertEqual(result["classification"], "UNSUPPORTED")

        # Missing turret_active selector occurrence
        with self.subTest("missing_selector"):
            result = _resolve_supported_endpoint_source_semantics(
                self._one_key_barrel_endpoint(barrel, selector_occurrences=[]),
                _geometry(4, one_key_barrel_restrictions=True),
                component_endpoint_count=2,
            )
            self.assertEqual(result["classification"], "UNSUPPORTED")

        # Activating/deactivating boundary value mismatch. gun_firing recoil
        # displaces this same barrel channel-0 Z, so a record holding a
        # recoil-displaced value must not pass as the settled active pose.
        with self.subTest("boundary_mismatch_recoil_value"):
            mismatch_barrel = (0.0, 0.0, 0.2962638735771179)
            activating = _descriptor(
                3, (2, 0, 0, 0, 0), {0: mismatch_barrel}, subname="turret_activating"
            )
            deactivating = _descriptor(
                3, (2, 0, 0, 0, 0), {0: mismatch_barrel}, subname="turret_deactivating"
            )
            result = _resolve_supported_endpoint_source_semantics(
                self._one_key_barrel_endpoint(
                    barrel, boundary_memberships=[activating, deactivating]
                ),
                _geometry(4, one_key_barrel_restrictions=True),
                component_endpoint_count=2,
            )
            self.assertEqual(result["classification"], "UNSUPPORTED")

        # Missing boundary descriptors
        with self.subTest("missing_boundary"):
            result = _resolve_supported_endpoint_source_semantics(
                self._one_key_barrel_endpoint(barrel, boundary_memberships=[]),
                _geometry(4, one_key_barrel_restrictions=True),
                component_endpoint_count=2,
            )
            self.assertEqual(result["classification"], "UNSUPPORTED")

        # Rotator two keys not identical to each other
        with self.subTest("rotator_keys_not_identical"):
            covered = [
                _descriptor(0, (0, 0, 0, 0, 0)),
                _descriptor(1, (2, 0, 0, 0, 0)),
                _descriptor(2, (0, 0, 0, 0, 0)),
                _descriptor(3, (1, 0, 0, 0, 0), {0: barrel}),
            ]
            # The rotator's settled form stores one value twice; two differing
            # keys are a ramp, not a settled pose.
            covered[1]["_candidate_raw_key_records"][0]["raw_bits"][1] = "0x40000000"
            covered[1]["_candidate_raw_key_records"][1]["raw_bits"][1] = "0x3f800000"
            result = _resolve_supported_endpoint_source_semantics(
                _endpoint(
                    covered,
                    depth=4,
                    ani_descriptor_memberships=self._one_key_barrel_boundary_memberships(barrel),
                    authored_animation_selector_occurrences=[_one_frame_selector("turret_active")],
                ),
                _geometry(4, one_key_barrel_restrictions=True),
                component_endpoint_count=2,
            )
            self.assertEqual(result["classification"], "UNSUPPORTED")

        # Barrel with 2 keys (already covered by nearby test but explicit here)
        with self.subTest("barrel_two_keys"):
            result = _resolve_supported_endpoint_source_semantics(
                self._one_key_barrel_endpoint(barrel, barrel_count=2),
                _geometry(4, one_key_barrel_restrictions=True),
                component_endpoint_count=2,
            )
            self.assertEqual(result["classification"], "UNSUPPORTED")

        # Authored pitch limit near-miss: the rank-2 89-degree maximum is not
        # the supported depth-4 layout.
        with self.subTest("wrong_rotation_x_max"):
            result = _resolve_supported_endpoint_source_semantics(
                self._one_key_barrel_endpoint(barrel),
                _geometry(
                    4,
                    one_key_barrel_restrictions=True,
                    one_key_barrel_pitch_max=89.0,
                ),
                component_endpoint_count=2,
            )
            self.assertEqual(result["classification"], "UNSUPPORTED")

        # Absent yaw-pitch restrictions
        with self.subTest("absent_restrictions"):
            result = _resolve_supported_endpoint_source_semantics(
                self._one_key_barrel_endpoint(barrel),
                _geometry(4),  # plain, no restrictions
                component_endpoint_count=2,
            )
            self.assertEqual(result["classification"], "UNSUPPORTED")

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
