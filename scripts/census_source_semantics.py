"""Recognize and apply the two accepted Issue #83 source-semantic cases."""
from __future__ import annotations

from copy import deepcopy

from census_ani_parser import _ANI_CHANNEL_COUNT_FIELDS


def _counts(descriptor: dict[str, object]) -> tuple[int, ...]:
    return tuple(
        int(descriptor["channel_counts"][field])
        for field in _ANI_CHANNEL_COUNT_FIELDS
    )


def _channel_records(
    descriptor: dict[str, object], channel_index: int
) -> list[dict[str, object]]:
    """Return one channel's key records for a descriptor, in stored order."""
    field = _ANI_CHANNEL_COUNT_FIELDS[channel_index]
    channel = descriptor.get("key_data", {}).get("channels", {}).get(field)
    if channel is None:
        return []
    record_range = channel["record_range"]
    return sorted(
        (
            record
            for record in descriptor.get("_candidate_raw_key_records", [])
            if int(record_range["start"])
            <= int(record["record_index"])
            < int(record_range["end_exclusive"])
        ),
        key=lambda record: int(record["record_index"]),
    )


def _first_three_bits(
    descriptor: dict[str, object], channel_index: int
) -> tuple[tuple[str, str, str], ...]:
    records = _channel_records(descriptor, channel_index)
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
    keyed = (
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
        and set(keyed) == {1, 3}
        and all(
            _counts(keyed[index]) == (2, 0, 0, 0, 0) for index in (1, 3)
        )
        and all(
            _first_three_bits(keyed[index], 0) == bits
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

    # Accepted Split L semantic case (Issue #79): the same depth-4 composition,
    # keyed instead on the gun and barrel edges, where both channel-0 records
    # store exact zeros. Channel-0 composition is additive (Issue #83), so these
    # settled translations are no-ops and the authored offsets carry the muzzle.
    zero_bits = (("0x00000000", "0x00000000", "0x00000000"),) * 2
    if (
        component_endpoint_count == 2
        and depth == 4
        and set(keyed) == {2, 3}
        and all(
            _counts(keyed[index]) == (2, 0, 0, 0, 0) for index in (2, 3)
        )
        and all(
            _first_three_bits(keyed[index], 0) == zero_bits for index in (2, 3)
        )
    ):
        return {
            "classification": "SOURCE_RESOLVED",
            "semantic_case": "depth4_zero_translation",
            "applied_authored_geometry": _apply(
                authored_geometry,
                positions={2: [0.0, 0.0, 0.0], 3: [0.0, 0.0, 0.0]},
            ),
        }

    # Accepted one-key barrel case (Issue #79 / #125 A2): the depth-4
    # rotator/barrel composition where the barrel stores a single settled
    # turret_active channel-0 key instead of the doubled form. The barrel rule
    # is structural/name-free; the rotator remains bounded to its separately
    # accepted repeated source value.
    one_key_barrel_match = False
    one_key_rotator_pos: list[float] = []
    one_key_barrel_pos: list[float] = []
    if (
        component_endpoint_count == 2
        and depth == 4
        and set(keyed) == {1, 3}
        and _counts(keyed[1]) == (2, 0, 0, 0, 0)
        and _counts(keyed[3]) == (1, 0, 0, 0, 0)
    ):
        # The accepted A1 evidence resolves this exact repeated rotator value;
        # repeated storage alone does not justify arbitrary translations.
        accepted_rotator_bits = (
            ("0x00000000", "0x403d92e4", "0x00000000"),
        ) * 2
        rotator_match = _first_three_bits(keyed[1], 0) == accepted_rotator_bits

        # Rule 4: barrel active key must use STEP interpolation:
        # raw_bits indexes 3, 4, 5 are all "0x00000001".
        barrel_records = _channel_records(keyed[3], 0)
        barrel_step = (
            len(barrel_records) == 1
            and len(barrel_records[0]["raw_bits"]) >= 6
            and barrel_records[0]["raw_bits"][3] == "0x00000001"
            and barrel_records[0]["raw_bits"][4] == "0x00000001"
            and barrel_records[0]["raw_bits"][5] == "0x00000001"
        )

        # Rule 5: turret_active must be a one-frame authored selector —
        # exactly one occurrence in authored_animation_selector_occurrences
        # with animation_name == "turret_active" whose _authored_frame_span
        # has non-empty start and end that parse as equal integers.
        selector_occurrences = endpoint.get(
            "authored_animation_selector_occurrences", []
        )
        turret_active_occurrences = [
            occ
            for occ in selector_occurrences
            if occ.get("animation_name") == "turret_active"
        ]
        one_frame = False
        if len(turret_active_occurrences) == 1:
            span = turret_active_occurrences[0].get("_authored_frame_span") or {}
            start_raw = span.get("start", "")
            end_raw = span.get("end", "")
            if start_raw and end_raw:
                try:
                    one_frame = int(start_raw) == int(end_raw)
                except (ValueError, TypeError):
                    one_frame = False

        # Rule 6: boundary match on edge 3.
        # turret_activating and turret_deactivating descriptors with non-empty
        # channel-0 must exist; last activating rec[0:3] == barrel active
        # rec[0:3] == first deactivating rec[0:3].
        boundary_match = False
        all_memberships = endpoint.get("ani_descriptor_memberships")
        if all_memberships is not None:
            edge3_memberships = [
                m
                for m in all_memberships
                if int(m.get("endpoint_path_edge_index", -1)) == 3
            ]
            activating_descs = [
                m
                for m in edge3_memberships
                if m.get("subname") == "turret_activating"
                and _channel_records(m, 0)
            ]
            deactivating_descs = [
                m
                for m in edge3_memberships
                if m.get("subname") == "turret_deactivating"
                and _channel_records(m, 0)
            ]
            if len(activating_descs) == 1 and len(deactivating_descs) == 1:
                act_recs = _channel_records(activating_descs[0], 0)
                deact_recs = _channel_records(deactivating_descs[0], 0)
                barrel_bits_0_3 = tuple(
                    str(b) for b in barrel_records[0]["raw_bits"][:3]
                )
                act_last_bits = tuple(
                    str(b) for b in act_recs[-1]["raw_bits"][:3]
                )
                deact_first_bits = tuple(
                    str(b) for b in deact_recs[0]["raw_bits"][:3]
                )
                boundary_match = (
                    act_last_bits == barrel_bits_0_3 == deact_first_bits
                )

        # Rule 7: authored yaw/pitch layout.
        one_key_layers = authored_geometry.get("source_geometry_layers", [])
        rot_y_restrictions = (
            one_key_layers[1]["authored_restrictions"]
            if len(one_key_layers) > 1
            else []
        )
        rot_x_restrictions = (
            one_key_layers[2]["authored_restrictions"]
            if len(one_key_layers) > 2
            else []
        )
        geo_match = (
            len(rot_y_restrictions) == 1
            and rot_y_restrictions[0].get("type_token") == "rotation_y"
            and rot_y_restrictions[0].get("authored_min") is None
            and rot_y_restrictions[0].get("authored_max") is None
            and len(rot_x_restrictions) == 1
            and rot_x_restrictions[0].get("type_token") == "rotation_x"
            and _limit(rot_x_restrictions[0], "authored_min") == -10.0
            and _limit(rot_x_restrictions[0], "authored_max") == 90.0
        )

        if (
            rotator_match
            and barrel_step
            and one_frame
            and boundary_match
            and geo_match
        ):
            one_key_barrel_match = True
            # Read the accepted translations from the verified source records
            # after the evidence-bounded guards have matched.
            one_key_rotator_pos = list(
                _channel_records(keyed[1], 0)[0]["raw_values"][:3]
            )
            one_key_barrel_pos = list(barrel_records[0]["raw_values"][:3])

    if one_key_barrel_match:
        return {
            "classification": "SOURCE_RESOLVED",
            "semantic_case": "depth4_one_key_barrel_translation",
            "applied_authored_geometry": _apply(
                authored_geometry,
                positions={
                    1: one_key_rotator_pos,
                    3: one_key_barrel_pos,
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
