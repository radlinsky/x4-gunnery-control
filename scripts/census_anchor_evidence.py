"""Asset-specific Paranid L Beam live-anchor trace evidence for the Issue #78 census tools."""
from __future__ import annotations

import math

from census_ani_analysis import (
    _candidate_channel_records,
)
from census_ani_parser import (
    _ANI_CHANNEL_COUNT_FIELDS,
    _ANI_KEY_RECORD_CANDIDATE_SLOTS,
)


_PARANID_L_BEAM_ACCEPTED_PRODUCTION_FORMULA = {
    "production_sha": "0d8780da74e49838d3f14408fe5c8c27ee151871",
    "production_source_file": "md/x4_gunnery_control.xml",
    "production_source_line_range": {"start": 323, "end_inclusive": 335},
    "downstream_vector": [
        -0.36177411330546533,
        0.4829345992763463,
        55.87084740617998,
    ],
    "yaw_origin_expression_terms": [
        [1.877547e-6, 2.018104, -1.043081e-5],
        [0.0, 6.145042419433594, 0.0],
    ],
    "pivot_vector": [-1.730653e-6, 2.926126, -16.11956],
    "runtime_inputs": ["target_bearing_yaw", "target_bearing_pitch"],
    "operation_sequence": [
        "weapon_local_look_at_target_useaimtarget_true",
        "md_create_rotation_pitch_equals_runtime_bearing_pitch",
        "md_transform_downstream_vector_by_pitch_rotation",
        "add_pivot_vector",
        "md_create_rotation_yaw_equals_runtime_bearing_yaw",
        "md_transform_pivoted_vector_by_yaw_rotation",
        "add_yaw_origin",
    ],
    "untraced_constants": [],
}

_PARANID_L_BEAM_TRACE_SPEC = {
    "endpoint_connection": "con_laser_02",
    "root_connection": "Connection01",
    "pivot_connection": "Connection04",
    "barrel_connection": "Connection05",
    "laser_connection": "con_laser_02",
    "rotator_active_descriptor": {
        "descriptor_index": 12,
        "part": "part_rotator",
        "subname": "turret_active",
        "candidate_channel_index": 0,
        "triple_slot_indexes": [0, 1, 2],
    },
    "barrel_active_descriptor": {
        "descriptor_index": 22,
        "part": "anim_barrel",
        "subname": "turret_active",
        "candidate_channel_index": 0,
        "triple_slot_indexes": [0, 1, 2],
    },
}


def _anchor_descriptor_inventory(
    endpoint: dict[str, object],
) -> list[dict[str, object]]:
    selected_identities = {
        int(descriptor["descriptor_index"])
        for descriptor in endpoint["selected_ani_descriptor_memberships"]
    }
    inventory = []
    for descriptor in sorted(
        endpoint["ani_descriptor_memberships"],
        key=lambda item: int(item["descriptor_index"]),
    ):
        channels = []
        for channel_index, field in enumerate(_ANI_CHANNEL_COUNT_FIELDS):
            records = _candidate_channel_records(descriptor, field)
            channels.append(
                {
                    "candidate_channel_id": f"candidate_channel_{channel_index}",
                    "candidate_channel_count_field_index": channel_index,
                    "record_count": len(records),
                    "records": [
                        {
                            "record_index": int(record["record_index"]),
                            "raw_bits": [
                                str(raw_bits) for raw_bits in record["raw_bits"]
                            ],
                            "candidate_values": list(record["raw_values"]),
                            "candidate_value_decode_evidence_classification": (
                                "third-party-technique"
                            ),
                        }
                        for record in records
                    ],
                }
            )
        inventory.append(
            {
                "component": endpoint["component"],
                "descriptor_index": int(descriptor["descriptor_index"]),
                "part": str(descriptor["part"]),
                "subname": str(descriptor["subname"]),
                "source_connection": str(descriptor["source_connection"]),
                "selector_selected": (
                    int(descriptor["descriptor_index"]) in selected_identities
                ),
                "candidate_channel_counts": [
                    int(descriptor["channel_counts"][field])
                    for field in _ANI_CHANNEL_COUNT_FIELDS
                ],
                "candidate_channels": channels,
                "raw_bits_evidence_classification": "shipped-source",
                "candidate_channel_layout_evidence_classification": (
                    "third-party-technique"
                ),
            }
        )
    return inventory


def _anchor_connection_vector(
    source_trace_bundle: dict[str, object],
    connection_name: str,
    field: str,
) -> tuple[list[float], list[dict[str, object]]] | None:
    matches = [
        connection
        for connection in source_trace_bundle["connections"]
        if connection["name"] == connection_name
    ]
    if len(matches) != 1:
        return None
    attributes = matches[0]["authored_offset"].get(field)
    names = ("x", "y", "z") if field == "position" else ("qx", "qy", "qz", "qw")
    if attributes is None or any(
        attributes.get(name, {}).get("candidate_numeric_value") is None
        for name in names
    ):
        return None
    values = [
        float(attributes[name]["candidate_numeric_value"]) for name in names
    ]
    provenance = [
        {
            "component": source_trace_bundle["component"],
            "connection": connection_name,
            "field": f"{field}.{name}",
            "raw_text": attributes[name]["raw_text"],
            "value": values[index],
            "evidence_classification": "shipped-source",
        }
        for index, name in enumerate(names)
    ]
    return values, provenance


def _anchor_ani_vector(
    source_trace_bundle: dict[str, object],
    selector: dict[str, object],
) -> tuple[list[float], list[dict[str, object]]] | None:
    descriptors = [
        descriptor
        for descriptor in source_trace_bundle["endpoint_descriptor_inventory"]
        if int(descriptor["descriptor_index"])
        == int(selector["descriptor_index"])
        and descriptor["part"] == selector["part"]
        and descriptor["subname"] == selector["subname"]
    ]
    if len(descriptors) != 1:
        return None
    channel_index = int(selector["candidate_channel_index"])
    if not 0 <= channel_index < len(_ANI_CHANNEL_COUNT_FIELDS):
        return None
    channel = descriptors[0]["candidate_channels"][channel_index]
    records = channel["records"]
    slot_indexes = [int(index) for index in selector["triple_slot_indexes"]]
    if (
        not records
        or len(slot_indexes) != 3
        or any(not 0 <= index < len(_ANI_KEY_RECORD_CANDIDATE_SLOTS) for index in slot_indexes)
    ):
        return None
    vectors = [
        [float(record["candidate_values"][index]) for index in slot_indexes]
        for record in records
    ]
    if any(vector != vectors[0] for vector in vectors[1:]):
        return None
    provenance = []
    for axis_index, slot_index in enumerate(slot_indexes):
        provenance.append(
            {
                "component": source_trace_bundle["component"],
                "descriptor_index": int(descriptors[0]["descriptor_index"]),
                "part": descriptors[0]["part"],
                "subname": descriptors[0]["subname"],
                "candidate_channel": f"candidate_channel_{channel_index}",
                "slot": str(
                    _ANI_KEY_RECORD_CANDIDATE_SLOTS[slot_index]["slot_id"]
                ),
                "record_indexes": [
                    int(record["record_index"]) for record in records
                ],
                "raw_bits": [
                    str(record["raw_bits"][slot_index]) for record in records
                ],
                "value": vectors[0][axis_index],
                "raw_bits_evidence_classification": "shipped-source",
                "candidate_channel_layout_evidence_classification": (
                    "third-party-technique"
                ),
                "candidate_value_decode_evidence_classification": (
                    "third-party-technique"
                ),
            }
        )
    return vectors[0], provenance


def _anchor_quaternion_multiply(
    left: list[float], right: list[float]
) -> list[float]:
    x, y, z, w = left
    other_x, other_y, other_z, other_w = right
    return [
        w * other_x + x * other_w + y * other_z - z * other_y,
        w * other_y - x * other_z + y * other_w + z * other_x,
        w * other_z + x * other_y - y * other_x + z * other_w,
        w * other_w - x * other_x - y * other_y - z * other_z,
    ]


def _anchor_quaternion_apply(
    quaternion: list[float], vector: list[float]
) -> list[float]:
    x, y, z, w = quaternion
    vector_x, vector_y, vector_z = vector
    tx = 2 * (y * vector_z - z * vector_y)
    ty = 2 * (z * vector_x - x * vector_z)
    tz = 2 * (x * vector_y - y * vector_x)
    return [
        vector_x + w * tx + y * tz - z * ty,
        vector_y + w * ty + z * tx - x * tz,
        vector_z + w * tz + x * ty - y * tx,
    ]


def _anchor_add(*vectors: list[float]) -> list[float]:
    return [sum(vector[index] for vector in vectors) for index in range(3)]


def _anchor_vectors_equal(left: object, right: object) -> bool:
    if not isinstance(left, list) or not isinstance(right, list):
        return False
    return len(left) == len(right) and all(
        math.isclose(float(a), float(b), rel_tol=0.0, abs_tol=1e-12)
        for a, b in zip(left, right)
    )


def _evaluate_paranid_l_beam_trace(
    source_trace_bundle: dict[str, object],
    *,
    production_formula: dict[str, object],
    trace_spec: dict[str, object],
) -> dict[str, object]:
    failures = []
    trace_source = source_trace_bundle.get(
        "source_trace_bundle", source_trace_bundle
    )

    def fail(code: str, finding: str) -> None:
        failures.append({"code": code, "finding": finding})

    connection_traces = {}
    for trace_id, connection_key, field in (
        ("component_root", "root_connection", "position"),
        ("pivot", "pivot_connection", "position"),
        ("pivot_quaternion", "pivot_connection", "quaternion"),
        ("barrel_connection", "barrel_connection", "position"),
        ("barrel_quaternion", "barrel_connection", "quaternion"),
        ("endpoint", "laser_connection", "position"),
    ):
        trace = _anchor_connection_vector(
            trace_source, str(trace_spec[connection_key]), field
        )
        connection_traces[trace_id] = trace
        if trace is None:
            fail(
                "connection_trace_unresolved",
                f"{trace_id} did not resolve to one complete authored {field}",
            )

    ani_traces = {}
    for trace_id, selector_key in (
        ("rotator_active", "rotator_active_descriptor"),
        ("barrel_active", "barrel_active_descriptor"),
    ):
        trace = _anchor_ani_vector(
            trace_source, trace_spec[selector_key]
        )
        ani_traces[trace_id] = trace
        if trace is None:
            fail(
                "ani_trace_unresolved",
                f"{trace_id} did not resolve to one exact constant raw triple",
            )

    formula_constant_provenance = []
    endpoint_resolution = None
    source_constant_provenance = [
        row
        for trace in list(connection_traces.values()) + list(ani_traces.values())
        if trace is not None
        for row in trace[1]
    ]
    derived = None
    if all(trace is not None for trace in connection_traces.values()) and all(
        trace is not None for trace in ani_traces.values()
    ):
        component_root = connection_traces["component_root"][0]
        pivot = connection_traces["pivot"][0]
        pivot_quaternion = connection_traces["pivot_quaternion"][0]
        barrel_connection = connection_traces["barrel_connection"][0]
        barrel_quaternion = connection_traces["barrel_quaternion"][0]
        endpoint = connection_traces["endpoint"][0]
        rotator_active = ani_traces["rotator_active"][0]
        barrel_active = ani_traces["barrel_active"][0]
        combined_quaternion = _anchor_quaternion_multiply(
            pivot_quaternion, barrel_quaternion
        )
        downstream = _anchor_add(
            _anchor_quaternion_apply(
                pivot_quaternion,
                _anchor_add(barrel_connection, barrel_active),
            ),
            _anchor_quaternion_apply(combined_quaternion, endpoint),
        )
        yaw_origin_terms = [component_root, rotator_active]
        yaw_origin = _anchor_add(*yaw_origin_terms)
        endpoint_candidates = []
        for candidate_connection in trace_source.get(
            "firing_endpoint_connections", []
        ):
            candidate_trace = _anchor_connection_vector(
                trace_source, str(candidate_connection), "position"
            )
            if candidate_trace is None:
                continue
            candidate_downstream = _anchor_add(
                _anchor_quaternion_apply(
                    pivot_quaternion,
                    _anchor_add(barrel_connection, barrel_active),
                ),
                _anchor_quaternion_apply(
                    combined_quaternion, candidate_trace[0]
                ),
            )
            endpoint_candidates.append(
                {
                    "connection": candidate_connection,
                    "derived_downstream_vector": candidate_downstream,
                    "matches_production_downstream": _anchor_vectors_equal(
                        candidate_downstream,
                        production_formula.get("downstream_vector"),
                    ),
                }
            )
        matching_endpoint_connections = [
            candidate["connection"]
            for candidate in endpoint_candidates
            if candidate["matches_production_downstream"]
        ]
        selected_endpoint_connection = str(trace_spec["endpoint_connection"])
        endpoint_resolution = {
            "candidate_endpoint_connections": endpoint_candidates,
            "production_matching_endpoint_connections": (
                matching_endpoint_connections
            ),
            "selected_endpoint_connection": selected_endpoint_connection,
            "exact_unique_match": matching_endpoint_connections
            == [selected_endpoint_connection],
            "selection_basis": (
                "unique current authored endpoint offset that reproduces the"
                " accepted production downstream vector"
            ),
            "evidence_classification": "inference",
        }
        if not endpoint_resolution["exact_unique_match"]:
            fail(
                "endpoint_resolution_mismatch",
                "accepted endpoint is not the unique current numeric source match",
            )
        derived = {
            "downstream_vector": downstream,
            "downstream_arithmetic": (
                "apply(Connection04.quaternion, Connection05.position +"
                " anim_barrel/turret_active candidate_channel_0 slots"
                " 000/004/008) + apply(Connection04.quaternion *"
                " Connection05.quaternion, con_laser_02.position)"
            ),
            "yaw_origin_expression_terms": yaw_origin_terms,
            "yaw_origin": yaw_origin,
            "yaw_origin_arithmetic": (
                "Connection01.position + part_rotator/turret_active"
                " candidate_channel_0 slots 000/004/008"
            ),
            "pivot_vector": pivot,
            "pivot_arithmetic": "Connection04.position",
            "evidence_classification": "inference",
        }
        dependency_ids = {
            "downstream_vector": [
                "pivot_quaternion",
                "barrel_connection",
                "barrel_active",
                "barrel_quaternion",
                "endpoint",
            ],
            "yaw_origin": ["component_root", "rotator_active"],
            "pivot_vector": ["pivot"],
        }
        expected_vectors = {
            "downstream_vector": production_formula.get("downstream_vector"),
            "yaw_origin": _anchor_add(
                *production_formula.get("yaw_origin_expression_terms", [])
            )
            if production_formula.get("yaw_origin_expression_terms")
            else None,
            "pivot_vector": production_formula.get("pivot_vector"),
        }
        for formula_id, value in (
            ("downstream_vector", downstream),
            ("yaw_origin", yaw_origin),
            ("pivot_vector", pivot),
        ):
            expected = expected_vectors[formula_id]
            matches = _anchor_vectors_equal(value, expected)
            if not matches:
                fail(
                    "formula_numeric_mismatch",
                    f"{formula_id} differs from the accepted production constant",
                )
            for axis_index, axis in enumerate(("x", "y", "z")):
                formula_constant_provenance.append(
                    {
                        "formula_constant": f"{formula_id}.{axis}",
                        "production_value": (
                            float(expected[axis_index])
                            if isinstance(expected, list)
                            and len(expected) > axis_index
                            else None
                        ),
                        "newly_derived_value": value[axis_index],
                        "source_kind": (
                            "component_connection_offset_field"
                            if formula_id == "pivot_vector"
                            else "explicit_arithmetic_combination"
                        ),
                        "dependencies": dependency_ids[formula_id],
                        "trace_status": "TRACED" if matches else "MISMATCH",
                        "evidence_classification": "inference",
                    }
                )
        if not all(
            _anchor_vectors_equal(actual, expected)
            for actual, expected in zip(
                yaw_origin_terms,
                production_formula.get("yaw_origin_expression_terms", []),
            )
        ) or len(yaw_origin_terms) != len(
            production_formula.get("yaw_origin_expression_terms", [])
        ):
            fail(
                "formula_structure_mismatch",
                "yaw-origin arithmetic terms differ from production",
            )
    else:
        formula_constant_provenance.append(
            {
                "formula_constant": "construction",
                "production_value": None,
                "newly_derived_value": None,
                "source_kind": "UNTRACED",
                "dependencies": [],
                "trace_status": "UNTRACED",
                "evidence_classification": "inference",
            }
        )

    expected_operations = list(
        _PARANID_L_BEAM_ACCEPTED_PRODUCTION_FORMULA["operation_sequence"]
    )
    expected_runtime_inputs = list(
        _PARANID_L_BEAM_ACCEPTED_PRODUCTION_FORMULA["runtime_inputs"]
    )
    if production_formula.get("operation_sequence") != expected_operations:
        fail(
            "formula_structure_mismatch",
            "production operation sequence differs from the accepted construction",
        )
    if production_formula.get("runtime_inputs") != expected_runtime_inputs:
        fail(
            "formula_structure_mismatch",
            "runtime input identities differ from the accepted construction",
        )
    for index, value in enumerate(production_formula.get("untraced_constants", [])):
        fail(
            "untraced_production_constant",
            f"production constant {index} has no authored-source trace",
        )
        formula_constant_provenance.append(
            {
                "formula_constant": f"untraced_constants[{index}]",
                "production_value": value,
                "newly_derived_value": None,
                "source_kind": "UNTRACED",
                "dependencies": [],
                "trace_status": "UNTRACED",
                "evidence_classification": "inference",
            }
        )

    corroboration_matrix = [
        {
            "candidate_semantic": "complete_asset_specific_construction_and_result",
            "assessment": "independently corroborated by aggregate live result",
            "evidence_classification": "live-tested",
        },
        {
            "candidate_semantic": "exact_con_laser_02_endpoint_input",
            "assessment": "independently corroborated by aggregate live result",
            "evidence_classification": "inference",
        },
        {
            "candidate_semantic": "authored_connection_position_and_quaternion_arithmetic_inputs",
            "assessment": "independently corroborated by aggregate live result",
            "evidence_classification": "inference",
        },
        {
            "candidate_semantic": "literal_turret_active_candidate_channel_0_slots_000_004_008_as_used_vectors",
            "assessment": "independently corroborated by aggregate live result",
            "evidence_classification": "inference",
        },
        {
            "candidate_semantic": "x4converter_candidate_channel_0_ownership_name",
            "assessment": "consistent only",
            "evidence_classification": "third-party-technique",
        },
        {
            "candidate_semantic": "asset_specific_operation_sequence",
            "assessment": "independently corroborated by aggregate live result",
            "evidence_classification": "inference",
        },
        {
            "candidate_semantic": "candidate_channels_1_2_3_4",
            "assessment": "not exercised",
            "evidence_classification": "inference",
        },
        {
            "candidate_semantic": "candidate_channel_0_slots_012_through_124",
            "assessment": "not exercised",
            "evidence_classification": "inference",
        },
    ]
    failure_codes = sorted({failure["code"] for failure in failures})
    result = {
        "status": "pass" if not failures else "fail",
        "failures": failures,
        "failure_codes": failure_codes,
        "production_formula": production_formula,
        "runtime_inputs": {
            "identities": production_formula.get("runtime_inputs", []),
            "source_constant_status": "not_source_constants",
        },
        "source_constant_provenance": source_constant_provenance,
        "formula_constant_provenance": formula_constant_provenance,
        "newly_traced_construction": derived,
        "endpoint_resolution": endpoint_resolution,
        "comparison": {
            "structural_match": not any(
                code == "formula_structure_mismatch" for code in failure_codes
            ),
            "numeric_match": not any(
                code == "formula_numeric_mismatch" for code in failure_codes
            ),
            "all_constants_traced": not any(
                code in (
                    "connection_trace_unresolved",
                    "ani_trace_unresolved",
                    "untraced_production_constant",
                )
                for code in failure_codes
            ),
        },
        "corroboration_matrix": corroboration_matrix,
    }
    result.update(source_trace_bundle)
    return result


def _build_paranid_l_beam_live_anchor(
    equipment_macros: list[dict[str, object]],
    component_to_macros: list[dict[str, object]],
    firing_endpoints: list[dict[str, object]],
    *,
    production_formula: dict[str, object],
    trace_spec: dict[str, object],
) -> dict[str, object]:
    macro_name = "turret_par_l_beam_01_mk1_macro"
    macro_matches = [
        record for record in equipment_macros if record["name"] == macro_name
    ]
    if len(macro_matches) != 1:
        return {
            "status": "fail",
            "failure_codes": ["macro_identity_unresolved"],
            "failures": [
                {
                    "code": "macro_identity_unresolved",
                    "finding": "exact accepted macro identity did not resolve once",
                }
            ],
        }
    component_name = str(macro_matches[0]["component"])
    component_matches = [
        record
        for record in component_to_macros
        if record["component"] == component_name
    ]
    endpoint_matches = [
        endpoint
        for endpoint in firing_endpoints
        if endpoint["component"] == component_name
        and endpoint["connection"] == trace_spec["endpoint_connection"]
    ]
    if len(component_matches) != 1 or len(endpoint_matches) != 1:
        return {
            "status": "fail",
            "failure_codes": ["source_identity_unresolved"],
            "failures": [
                {
                    "code": "source_identity_unresolved",
                    "finding": "macro-referenced component or exact endpoint did not resolve once",
                }
            ],
        }
    component = component_matches[0]
    endpoint = endpoint_matches[0]
    inventory = _anchor_descriptor_inventory(endpoint)
    selected_inventory = [
        descriptor for descriptor in inventory if descriptor["selector_selected"]
    ]
    active_inventory = [
        descriptor
        for descriptor in inventory
        if descriptor["subname"] == "turret_active"
    ]
    source_trace_bundle = {
        "source_trace_bundle": {
            "component": component_name,
            "firing_endpoint_connections": [
                candidate["connection"]
                for candidate in firing_endpoints
                if candidate["component"] == component_name
            ],
            "connections": [
                {
                    **{
                        key: value
                        for key, value in connection.items()
                        if key not in ("_authored_offset", "_direct_owned_part_transforms")
                    },
                    "authored_offset": connection["_authored_offset"],
                }
                for connection in component["connections"]
            ],
            "endpoint_descriptor_inventory": inventory,
        },
        "identity_chain": {
            "macro": macro_name,
            "macro_source_set": macro_matches[0]["source_set"],
            "macro_source_file": macro_matches[0]["source_file"],
            "component": component_name,
            "component_source_set": component["source_set"],
            "component_source_file": component["source_file"],
            "geometry_source": component["geometry_source"],
            "ani_source_set": component["ani_source_set"],
            "ani_resource": component["ani_resource"],
            "endpoint_connection": endpoint["connection"],
            "root_to_endpoint_connection_path": endpoint[
                "root_to_endpoint_connection_path"
            ],
            "all_component_endpoint_paths": [
                {
                    "endpoint_connection": candidate["connection"],
                    "root_to_endpoint_connection_path": candidate[
                        "root_to_endpoint_connection_path"
                    ],
                }
                for candidate in firing_endpoints
                if candidate["component"] == component_name
            ],
            "resolution_rule": "exact explicit references and identities only",
            "evidence_classification": "shipped-source",
        },
        "endpoint_descriptor_inventory": inventory,
        "selector_selected_descriptor_inventory": selected_inventory,
        "literal_turret_active_descriptors": active_inventory,
        "literal_turret_active_candidate_channel_contributions": {
            "contributing": ["candidate_channel_0"],
            "not_contributing": [
                "candidate_channel_1",
                "candidate_channel_2",
                "candidate_channel_3",
                "candidate_channel_4",
            ],
        },
        "evidence_boundary": {
            "authored_xml_and_ani_bits": "shipped-source",
            "x4converter_field_and_channel_names": "third-party-technique",
            "source_to_formula_provenance_and_arithmetic": "inference",
            "complete_already_tested_construction_and_result": "live-tested",
            "individual_ani_field_live_test_status": "not_live-tested_individually",
        },
        "accepted_live_result": {
            "issue": 69,
            "checkpoint_comment": 5466013484,
            "x4_version": "9.00",
            "build": "611726",
            "accepted_test_lab_sha": (
                "fb8bb7214906f93989b328f32bd7be9187620d25"
            ),
            "settled_muzzle_error_metres": "approximately 0.303",
            "scope": macro_name,
            "evidence_classification": "live-tested",
        },
    }
    return _evaluate_paranid_l_beam_trace(
        source_trace_bundle,
        production_formula=production_formula,
        trace_spec=trace_spec,
    )
