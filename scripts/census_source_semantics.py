"""Recognize and apply the two accepted Issue #83 source-semantic cases."""
from __future__ import annotations

from copy import deepcopy

from census_ani_parser import _ANI_CHANNEL_COUNT_FIELDS


def _counts(descriptor: dict[str, object]) -> tuple[int, ...]:
    return tuple(
        int(descriptor["channel_counts"][field])
        for field in _ANI_CHANNEL_COUNT_FIELDS
    )


def _first_three_bits(
    descriptor: dict[str, object], channel_index: int
) -> tuple[tuple[str, str, str], ...]:
    field = _ANI_CHANNEL_COUNT_FIELDS[channel_index]
    record_range = descriptor["key_data"]["channels"][field]["record_range"]
    records = sorted(
        (
            record
            for record in descriptor["_candidate_raw_key_records"]
            if int(record_range["start"])
            <= int(record["record_index"])
            < int(record_range["end_exclusive"])
        ),
        key=lambda record: int(record["record_index"]),
    )
    return tuple(
        tuple(str(raw_bit) for raw_bit in record["raw_bits"][:3])
        for record in records
    )


def _covered_by_edge(
    endpoint: dict[str, object],
) -> dict[int, dict[str, object]] | None:
    covered: dict[int, dict[str, object]] = {}
    for descriptor in endpoint.get(
        "_ancestry_covered_turret_active_descriptor_memberships", []
    ):
        edge_index = int(descriptor["endpoint_path_edge_index"])
        if edge_index in covered:
            return None
        covered[edge_index] = descriptor
    return covered


def _apply(
    authored_geometry: dict[str, object],
    *,
    positions: dict[int, list[float]] | None = None,
    rotations: dict[int, list[float]] | None = None,
) -> dict[str, object]:
    # ANI stores X in the opposite handedness from authored XML geometry.
    # Normalize accepted ANI position/rotation triples at this boundary so
    # their raw literals remain byte-faithful to the source records.
    def _native(triple: list[float]) -> list[float]:
        return [-triple[0], triple[1], triple[2]]

    result = deepcopy(authored_geometry)
    layers = result["source_geometry_layers"]
    for edge_index, value in (positions or {}).items():
        layers[edge_index]["settled_local_position_delta"] = _native(value)
    for edge_index, value in (rotations or {}).items():
        layers[edge_index]["settled_local_euler_xyz_delta_radians"] = _native(value)
    return result


def _limit(restriction: dict[str, object], field: str) -> float | None:
    record = restriction.get(field)
    if record is None or record.get("candidate_numeric_value") is None:
        return None
    return float(record["candidate_numeric_value"])


def _resolve_supported_endpoint_source_semantics(
    endpoint: dict[str, object],
    authored_geometry: dict[str, object],
    *,
    component_endpoint_count: int,
) -> dict[str, object]:
    """Apply only the two accepted name-free semantic signatures; otherwise fail closed."""

    covered = _covered_by_edge(endpoint)
    depth = len(endpoint.get("source_part_path", []))

    # Accepted B1 semantic case: the depth-4 profile shared by the three
    # source-identical components, distinguished by its two exact live-backed
    # channel-0 translation triples. Endpoint leaf offsets are deliberately
    # outside the signature.
    b1_bits = {
        1: (("0x00000000", "0x40c4a430", "0x00000000"),) * 2,
        3: (("0x00000000", "0xbe759360", "0x41ddae80"),) * 2,
    }
    b1_keyed = (
        {
            edge_index: descriptor
            for edge_index, descriptor in covered.items()
            if _counts(descriptor) != (0, 0, 0, 0, 0)
        }
        if covered is not None
        else {}
    )
    if (
        component_endpoint_count == 2
        and depth == 4
        and set(b1_keyed) == {1, 3}
        and all(
            _counts(b1_keyed[index]) == (2, 0, 0, 0, 0) for index in (1, 3)
        )
        and all(
            _first_three_bits(b1_keyed[index], 0) == bits
            for index, bits in b1_bits.items()
        )
    ):
        return {
            "classification": "SOURCE_RESOLVED",
            "semantic_case": "depth4_dual_translation",
            "applied_authored_geometry": _apply(
                authored_geometry,
                positions={
                    1: [0.0, 6.145042419433594, 0.0],
                    3: [0.0, -0.23982000350952148, 27.710205078125],
                },
            ),
        }

    # Accepted rank-2 case. The selector-selected guard is the existing
    # corpus-uniqueness guard; the five ancestry-covered records then have one
    # descriptor per edge. Only the exact optional channel-0 residue is allowed.
    rank2_counts_without_residue = (
        (2, 0, 0, 0, 0),
        (0, 2, 0, 0, 0),
        (0, 2, 0, 0, 0),
        (0, 0, 0, 0, 0),
        (0, 0, 0, 0, 0),
    )
    rank2_counts_with_residue = (
        (2, 0, 0, 0, 0),
        (0, 2, 0, 0, 0),
        (2, 2, 0, 0, 0),
        (0, 0, 0, 0, 0),
        (0, 0, 0, 0, 0),
    )
    selected = endpoint.get("selected_ani_descriptor_memberships", [])
    rank2_counts = (
        tuple(_counts(covered[index]) for index in range(5))
        if covered is not None and set(covered) == set(range(5))
        else None
    )
    rank2_layers = authored_geometry.get("source_geometry_layers", [])
    rotation_y = (
        rank2_layers[3]["authored_restrictions"] if len(rank2_layers) == 5 else []
    )
    rotation_x = (
        rank2_layers[4]["authored_restrictions"] if len(rank2_layers) == 5 else []
    )
    rank2_matches = (
        component_endpoint_count == 2
        and depth == 5
        and len(selected) == 4
        and all(
            _counts(descriptor) == (2, 0, 0, 0, 0) for descriptor in selected
        )
        and rank2_counts
        in (rank2_counts_without_residue, rank2_counts_with_residue)
        and _first_three_bits(covered[0], 0)
        == (("0x00000000", "0x00000000", "0x00000000"),) * 2
        and _first_three_bits(covered[1], 1)
        == (("0xbf1c61aa", "0x80000000", "0x00000000"),) * 2
        and _first_three_bits(covered[2], 1)
        == (("0x3f1c61aa", "0x80000000", "0x00000000"),) * 2
        and len(rotation_y) == 1
        and rotation_y[0].get("type_token") == "rotation_y"
        and rotation_y[0].get("authored_min") is None
        and rotation_y[0].get("authored_max") is None
        and len(rotation_x) == 1
        and rotation_x[0].get("type_token") == "rotation_x"
        and _limit(rotation_x[0], "authored_min") == -10.0
        and _limit(rotation_x[0], "authored_max") == 89.0
    )
    positions: dict[int, list[float]] = {}
    if rank2_matches and rank2_counts == rank2_counts_with_residue:
        if _first_three_bits(covered[2], 0) != (
            ("0x34f80000", "0x33b00000", "0xb4940000"),
        ) * 2:
            rank2_matches = False
        else:
            positions[2] = [
                4.6193599700927734e-7,
                8.195638656616211e-8,
                -2.7567148208618164e-7,
            ]
    if rank2_matches:
        return {
            "classification": "SOURCE_RESOLVED",
            "semantic_case": "depth5_additive_x_rotation",
            "applied_authored_geometry": _apply(
                authored_geometry,
                positions=positions,
                rotations={
                    1: [-0.6108652353286743, -0.0, 0.0],
                    2: [0.6108652353286743, -0.0, 0.0],
                },
            ),
        }

    return {
        "classification": "UNSUPPORTED",
        "reason": "no_accepted_source_semantic_signature",
    }
