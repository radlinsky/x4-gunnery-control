"""Recognize and apply accepted source-semantic cases."""
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


def _offset_matches(
    offset: dict[str, object],
    position: tuple[float, float, float],
    quaternion: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 1.0),
) -> bool:
    """Match an authored transform numerically without relying on asset names.

    An authored component may store a present-but-empty <position> or
    <quaternion> record; that is exactly the zero offset and identity rotation
    the generator emits, so it is matched as such. A key that is missing
    outright is absent source data, not an authored zero, and fails closed.
    """
    if "position" not in offset or "quaternion" not in offset:
        return False
    try:
        actual_position = (
            tuple(
                float(offset["position"][axis]["candidate_numeric_value"])
                for axis in "xyz"
            )
            if offset["position"] is not None
            else (0.0, 0.0, 0.0)
        )
        actual_quaternion = (
            tuple(
                float(offset["quaternion"][axis]["candidate_numeric_value"])
                for axis in ("qx", "qy", "qz", "qw")
            )
            if offset["quaternion"] is not None
            else (0.0, 0.0, 0.0, 1.0)
        )
    except (KeyError, TypeError, ValueError, AttributeError):
        return False
    return actual_position == position and actual_quaternion == quaternion


def _state_boundary_bits(
    endpoint: dict[str, object], edge_index: int, channel_index: int
) -> tuple[tuple[str, ...], tuple[str, ...]] | None:
    """Last turret_activating and first turret_deactivating value on one edge."""
    memberships = endpoint.get("ani_descriptor_memberships")
    if memberships is None:
        return None
    edges = [
        membership
        for membership in memberships
        if int(membership.get("endpoint_path_edge_index", -1)) == edge_index
    ]
    bounds: list[tuple[str, ...]] = []
    for subname, index in (("turret_activating", -1), ("turret_deactivating", 0)):
        matches = [
            membership
            for membership in edges
            if membership.get("subname") == subname
            and _channel_records(membership, channel_index)
        ]
        if len(matches) != 1:
            return None
        records = _channel_records(matches[0], channel_index)
        bounds.append(tuple(str(bit) for bit in records[index]["raw_bits"][:3]))
    return bounds[0], bounds[1]


def _resolve_supported_endpoint_source_semantics(
    endpoint: dict[str, object],
    authored_geometry: dict[str, object],
    *,
    component_endpoint_count: int,
) -> dict[str, object]:
    """Apply only accepted name-free semantic signatures; otherwise fail closed."""

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

    # Accepted P6 semantic case (Issue #132): the depth-4 gun/barrel
    # composition with exact identity-valued gun companions. The live-backed
    # conclusion that channels 1 and 2 add no material settled transform is
    # bounded to this complete signature; only channel-0 translations are
    # applied.
    p6_active_bits = {
        (2, 0): (("0x00000000", "0x00000000", "0x00000000"),) * 2,
        (2, 1): (("0x00000000", "0x80000000", "0x00000000"),) * 2,
        (2, 2): (("0x3f800000", "0x3f800000", "0x3f800000"),) * 2,
        (3, 0): (("0x00000000", "0xb5fffe54", "0x00000000"),) * 2,
    }
    selector_occurrences = endpoint.get(
        "authored_animation_selector_occurrences", []
    )
    turret_active_occurrences = [
        occurrence
        for occurrence in selector_occurrences
        if occurrence.get("animation_name") == "turret_active"
    ]
    p6_selector_match = False
    if len(turret_active_occurrences) == 1:
        occurrence = turret_active_occurrences[0]
        span = occurrence.get("_authored_frame_span") or {}
        selector_descriptors = occurrence.get(
            "selector_connection_ani_descriptors", []
        )
        selected_path_descriptors = occurrence.get(
            "selected_endpoint_path_ani_descriptor_memberships", []
        )
        p6_selector_match = (
            str(span.get("start", "")) == "60"
            and str(span.get("end", "")) == "61"
            and occurrence.get("selector_connection_descriptor_match_count") == 1
            and len(selector_descriptors) == 1
            and selector_descriptors[0].get("subname") == "turret_active"
            and _counts(selector_descriptors[0]) == (0, 0, 0, 0, 0)
            and len(selected_path_descriptors) == 1
            and selected_path_descriptors[0].get("subname") == "turret_active"
            and selected_path_descriptors[0].get("endpoint_path_edge_index") == 0
            and _counts(selected_path_descriptors[0]) == (0, 0, 0, 0, 0)
        )

    p6_boundary_match = False
    all_memberships = endpoint.get("ani_descriptor_memberships")
    if all_memberships is not None:
        p6_boundary_match = True
        for (edge_index, channel_index), active_bits in p6_active_bits.items():
            edge_memberships = [
                membership
                for membership in all_memberships
                if int(membership.get("endpoint_path_edge_index", -1)) == edge_index
            ]
            activating = [
                membership
                for membership in edge_memberships
                if membership.get("subname") == "turret_activating"
                and _channel_records(membership, channel_index)
            ]
            deactivating = [
                membership
                for membership in edge_memberships
                if membership.get("subname") == "turret_deactivating"
                and _channel_records(membership, channel_index)
            ]
            if len(activating) != 1 or len(deactivating) != 1:
                p6_boundary_match = False
                break
            active_value = active_bits[0]
            activating_value = tuple(
                str(bit)
                for bit in _channel_records(activating[0], channel_index)[-1][
                    "raw_bits"
                ][:3]
            )
            deactivating_value = tuple(
                str(bit)
                for bit in _channel_records(deactivating[0], channel_index)[0][
                    "raw_bits"
                ][:3]
            )
            if activating_value != active_value or deactivating_value != active_value:
                p6_boundary_match = False
                break

    p6_layers = authored_geometry.get("source_geometry_layers", [])
    p6_yaw = p6_layers[1]["authored_restrictions"] if len(p6_layers) == 4 else []
    p6_pitch = p6_layers[2]["authored_restrictions"] if len(p6_layers) == 4 else []
    p6_connection_positions = (
        (0.0, 0.0, 0.0),
        (-0.0244168, 17.52643, -0.1001702),
        (2.980232e-8, -0.02269363, -5.565336),
        (-4.023314e-6, 0.1448975, 11.62085),
    )
    p6_endpoint_positions = {
        (4.560871, -0.1317711, 23.71955),
        (-4.823473, -0.001207352, 23.71955),
    }
    p6_geometry_match = (
        len(p6_yaw) == 1
        and p6_yaw[0].get("type_token") == "rotation_y"
        and p6_yaw[0].get("authored_min") is None
        and p6_yaw[0].get("authored_max") is None
        and len(p6_pitch) == 1
        and p6_pitch[0].get("type_token") == "rotation_x"
        and _limit(p6_pitch[0], "authored_min") == -5.0
        and _limit(p6_pitch[0], "authored_max") == 90.0
        and all(
            _offset_matches(layer.get("connection_authored_offset", {}), position)
            and _offset_matches(
                layer.get("part_authored_offset", {}), (0.0, 0.0, 0.0)
            )
            for layer, position in zip(p6_layers, p6_connection_positions)
        )
        and any(
            _offset_matches(
                authored_geometry.get("endpoint_authored_offset", {}), position
            )
            for position in p6_endpoint_positions
        )
    )
    if (
        component_endpoint_count == 2
        and depth == 4
        and covered is not None
        and set(covered) == {0, 1, 2, 3}
        and tuple(_counts(covered[index]) for index in range(4))
        == (
            (0, 0, 0, 0, 0),
            (0, 0, 0, 0, 0),
            (2, 2, 2, 0, 0),
            (2, 0, 0, 0, 0),
        )
        and all(
            _first_three_bits(covered[edge_index], channel_index) == bits
            for (edge_index, channel_index), bits in p6_active_bits.items()
        )
        and p6_selector_match
        and p6_boundary_match
        and p6_geometry_match
    ):
        return {
            "classification": "SOURCE_RESOLVED",
            "semantic_case": "depth4_p6_translation",
            "applied_authored_geometry": _apply(
                authored_geometry,
                positions={
                    2: [0.0, 0.0, 0.0],
                    3: [0.0, -1.9072999748459551e-6, 0.0],
                },
            ),
        }

    # Accepted P8 semantic case (Issue #135): the depth-4 rotator/barrel
    # composition where the muzzle path stores no key at all in candidate
    # channels 1-4, both keyed edges carry two bit-identical channel-0 records,
    # and those values also hold at both adjacent state boundaries. Bounded to
    # this component's own exact stored bits and authored transforms; the
    # applied math is the existing depth-4 channel-0 translation.
    p8_active_bits = {
        1: (("0x00000000", "0x00000000", "0x00000000"),) * 2,
        3: (("0x00000000", "0x00000000", "0x367ffe54"),) * 2,
    }
    p8_connection_positions = (
        (0.0, 0.0, 0.0),
        (0.0, 8.5, 0.0),
        (0.0, 2.064657, -6.057116),
        (0.0, 0.6179247, 45.60182),
    )
    p8_endpoint_positions = {
        (2.003361, 4.62532e-3, 17.78848),
        (-2.000694, 0.135191, 17.78848),
    }
    p8_layers = authored_geometry.get("source_geometry_layers", [])
    p8_yaw = p8_layers[1]["authored_restrictions"] if len(p8_layers) == 4 else []
    p8_pitch = p8_layers[2]["authored_restrictions"] if len(p8_layers) == 4 else []
    p8_geometry_match = (
        len(p8_yaw) == 1
        and p8_yaw[0].get("type_token") == "rotation_y"
        and p8_yaw[0].get("authored_min") is None
        and p8_yaw[0].get("authored_max") is None
        and len(p8_pitch) == 1
        and p8_pitch[0].get("type_token") == "rotation_x"
        and _limit(p8_pitch[0], "authored_min") == -5.0
        and _limit(p8_pitch[0], "authored_max") == 80.0
        and all(
            _offset_matches(layer.get("connection_authored_offset", {}), position)
            and _offset_matches(
                layer.get("part_authored_offset", {}), (0.0, 0.0, 0.0)
            )
            for layer, position in zip(p8_layers, p8_connection_positions)
        )
        and any(
            _offset_matches(
                authored_geometry.get("endpoint_authored_offset", {}), position
            )
            for position in p8_endpoint_positions
        )
    )
    p8_selector_match = False
    p8_occurrences = [
        occurrence
        for occurrence in endpoint.get("authored_animation_selector_occurrences", [])
        if occurrence.get("animation_name") == "turret_active"
    ]
    if len(p8_occurrences) == 1:
        span = p8_occurrences[0].get("_authored_frame_span") or {}
        p8_selector_match = (
            str(span.get("start", "")) == "60" and str(span.get("end", "")) == "61"
        )
    p8_boundary_match = all(
        _state_boundary_bits(endpoint, edge_index, 0) == (bits[0], bits[0])
        for edge_index, bits in p8_active_bits.items()
    )
    # Accepted A1 proof boundary (Issue #135): the muzzle path stores no key at
    # all in candidate channels 1-4, under every animation selector -- not just
    # turret_active. Any such record puts a settled transform outside the
    # applied channel-0 math, so the case fails closed.
    p8_channel0_only = all(
        _counts(descriptor)[1:] == (0, 0, 0, 0)
        and not any(
            _channel_records(descriptor, channel) for channel in range(1, 5)
        )
        for descriptor in list(covered.values() if covered else [])
        + list(endpoint.get("ani_descriptor_memberships") or [])
    )
    if (
        component_endpoint_count == 2
        and depth == 4
        and covered is not None
        and set(covered) == {0, 1, 2, 3}
        and tuple(_counts(covered[index]) for index in range(4))
        == (
            (0, 0, 0, 0, 0),
            (2, 0, 0, 0, 0),
            (0, 0, 0, 0, 0),
            (2, 0, 0, 0, 0),
        )
        and all(
            _first_three_bits(covered[edge_index], 0) == bits
            for edge_index, bits in p8_active_bits.items()
        )
        and p8_channel0_only
        and p8_selector_match
        and p8_boundary_match
        and p8_geometry_match
    ):
        return {
            "classification": "SOURCE_RESOLVED",
            "semantic_case": "depth4_p8_translation",
            "applied_authored_geometry": _apply(
                authored_geometry,
                positions={
                    1: [0.0, 0.0, 0.0],
                    3: [0.0, 0.0, 3.8145999496919103e-06],
                },
            ),
        }

    # Accepted one-key barrel cases (Issue #79 / #125 A2, Issue #128 P2,
    # Issue #137): the rotator/barrel compositions where the barrel stores a
    # single
    # settled turret_active channel-0 key instead of the doubled form. The
    # barrel rule is structural/name-free; each accepted variant stays bounded
    # to its own live-backed rotator value and companion-channel evidence.
    #
    # (rotator channel-0 bits, barrel counts, {barrel channel: bits}). The
    # beam_02 companions are a full-turn additive rotation and a unit scale,
    # both proved to add no material settled transform, so the applied math is
    # the channel-0 translations either way.
    one_key_barrel_signatures = (
        (
            (("0x00000000", "0x403d92e4", "0x00000000"),) * 2,
            (1, 0, 0, 0, 0),
            {},
        ),
        (
            (("0x00000000", "0x40178ddc", "0x00000000"),) * 2,
            (1, 2, 2, 0, 0),
            {
                1: (("0xc0c90fdb", "0x80000000", "0x00000000"),) * 2,
                2: (("0x3f7ffffd", "0x3f800000", "0x3f800002"),) * 2,
            },
        ),
    )
    one_key_layout = None
    if depth == 4 and set(keyed) == {1, 3}:
        one_key_layout = {
            "rotator_edge": 1,
            "barrel_edge": 3,
            "yaw_edge": 1,
            "pitch_edge": 2,
            "semantic_case": "depth4_one_key_barrel_translation",
            "selector_frame": None,
        }
    elif (
        depth == 3
        and covered is not None
        and set(covered) == {0, 1, 2}
        and set(keyed) == {0, 2}
    ):
        one_key_layout = {
            "rotator_edge": 0,
            "barrel_edge": 2,
            "yaw_edge": 0,
            "pitch_edge": 1,
            "semantic_case": "depth3_one_key_barrel_translation",
            "selector_frame": 50,
        }

    one_key_barrel_match = False
    one_key_rotator_pos: list[float] = []
    one_key_barrel_pos: list[float] = []
    if (
        component_endpoint_count == 2
        and one_key_layout is not None
        and _counts(keyed[one_key_layout["rotator_edge"]])
        == (2, 0, 0, 0, 0)
    ):
        rotator_edge = one_key_layout["rotator_edge"]
        barrel_edge = one_key_layout["barrel_edge"]
        # Repeated rotator storage alone does not justify arbitrary
        # translations; only the accepted signatures pass.
        rotator_match = any(
            _first_three_bits(keyed[rotator_edge], 0) == rotator_bits
            and _counts(keyed[barrel_edge]) == barrel_counts
            and all(
                _first_three_bits(keyed[barrel_edge], channel) == bits
                for channel, bits in companions.items()
            )
            for rotator_bits, barrel_counts, companions in (
                one_key_barrel_signatures
            )
        )

        # Rule 4: barrel active key must use STEP interpolation:
        # raw_bits indexes 3, 4, 5 are all "0x00000001".
        barrel_records = _channel_records(keyed[barrel_edge], 0)
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
                    start = int(start_raw)
                    end = int(end_raw)
                    one_frame = start == end and (
                        one_key_layout["selector_frame"] is None
                        or start == one_key_layout["selector_frame"]
                    )
                except (ValueError, TypeError):
                    one_frame = False

        # Rule 6: boundary match on edge 3.
        # turret_activating and turret_deactivating descriptors with non-empty
        # channel-0 must exist; last activating rec[0:3] == barrel active
        # rec[0:3] == first deactivating rec[0:3].
        boundary_match = False
        all_memberships = endpoint.get("ani_descriptor_memberships")
        # barrel_step also guarantees barrel_records[0] exists; a declared
        # channel-0 count with no usable raw record must fail closed here.
        if barrel_step and all_memberships is not None:
            barrel_memberships = [
                m
                for m in all_memberships
                if int(m.get("endpoint_path_edge_index", -1)) == barrel_edge
            ]
            activating_descs = [
                m
                for m in barrel_memberships
                if m.get("subname") == "turret_activating"
                and _channel_records(m, 0)
            ]
            deactivating_descs = [
                m
                for m in barrel_memberships
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
        yaw_edge = one_key_layout["yaw_edge"]
        pitch_edge = one_key_layout["pitch_edge"]
        rot_y_restrictions = (
            one_key_layers[yaw_edge]["authored_restrictions"]
            if len(one_key_layers) > yaw_edge
            else []
        )
        rot_x_restrictions = (
            one_key_layers[pitch_edge]["authored_restrictions"]
            if len(one_key_layers) > pitch_edge
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
                _channel_records(keyed[rotator_edge], 0)[0]["raw_values"][:3]
            )
            one_key_barrel_pos = list(barrel_records[0]["raw_values"][:3])

    if one_key_barrel_match:
        return {
            "classification": "SOURCE_RESOLVED",
            "semantic_case": one_key_layout["semantic_case"],
            "applied_authored_geometry": _apply(
                authored_geometry,
                positions={
                    one_key_layout["rotator_edge"]: one_key_rotator_pos,
                    one_key_layout["barrel_edge"]: one_key_barrel_pos,
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
        component_endpoint_count in (1, 2, 5)
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
