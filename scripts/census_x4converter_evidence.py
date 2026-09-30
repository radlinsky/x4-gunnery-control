"""Pinned X4Converter key-record semantic lead evidence for the Issue #78 census tools."""
from __future__ import annotations

from census_ani_parser import (
    _ANI_KEY_RECORD_CANDIDATE_SLOTS,
    _ANI_KEY_RECORD_SIZE,
)


_X4CONVERTER_COMMIT = "0be4b494089ba7719d4c5d351e63160ef3843ef5"
_X4CONVERTER_KEYFRAME_HEADER = (
    "X4ConverterTools/include/X4ConverterTools/ani/Keyframe.h"
)
_X4CONVERTER_KEYFRAME_SOURCE = "X4ConverterTools/src/ani/Keyframe.cpp"
_X4CONVERTER_ANIMDESC_SOURCE = "X4ConverterTools/src/ani/AnimDesc.cpp"


def _x4converter_site(
    path: str,
    function: str,
    line_start: int,
    line_end: int,
    expression: str,
) -> dict[str, object]:
    return {
        "path": path,
        "function": function,
        "line_range_at_pinned_commit": [line_start, line_end],
        "expression": expression,
    }


def _x4converter_descriptor_offset_148_lead() -> dict[str, object]:
    return {
        "evidence_classification": "third-party-technique",
        "source_revision": {
            "repository": "https://github.com/Cgettys/X4Converter.git",
            "commit": _X4CONVERTER_COMMIT,
            "inspection": "direct pinned checkout",
        },
        "x4converter_member": "Duration",
        "member_declaration_site": _x4converter_site(
            "X4ConverterTools/include/X4ConverterTools/ani/AnimDesc.h",
            "ani::AnimDesc member declaration",
            43,
            43,
            "float Duration = 0",
        ),
        "read_site": _x4converter_site(
            _X4CONVERTER_ANIMDESC_SOURCE,
            "AnimDesc::AnimDesc(StreamReaderLE &reader)",
            21,
            26,
            "NumPostScaleKeys is read before Duration",
        ),
        "write_site": _x4converter_site(
            _X4CONVERTER_ANIMDESC_SOURCE,
            "AnimDesc::WriteToGameFiles",
            79,
            84,
            "NumPostScaleKeys is written before Duration",
        ),
        "validation_report_site": _x4converter_site(
            _X4CONVERTER_ANIMDESC_SOURCE,
            "AnimDesc::validate",
            205,
            207,
            "Duration is included in human-readable validation output",
        ),
        "other_actual_use_sites": [],
        "search_scope": (
            "pinned X4Converter commit C/C++ headers and sources; exact member"
            " search found declaration, read, write, and validation report only"
        ),
        "engine_requiredness": "unresolved",
        "absence_interpretation": (
            "X4Converter use or non-use does not establish X4 engine requiredness"
        ),
        "semantic_promotion": "not_permitted_by_this_inventory",
    }


def _x4converter_candidate_key_record_semantic_lead() -> dict[str, object]:
    field_specs = (
        ("ValueX", "candidate_vector", 45, 27),
        ("ValueY", "candidate_vector", 45, 27),
        ("ValueZ", "candidate_vector", 45, 27),
        ("InterpolationX", "per_axis_mode", 46, 28),
        ("InterpolationY", "per_axis_mode", 47, 28),
        ("InterpolationZ", "per_axis_mode", 48, 28),
        ("Time", "record_order_scalar", 49, 29),
        ("CPX1x", "control_parameters", 53, 31),
        ("CPX1y", "control_parameters", 53, 31),
        ("CPX2x", "control_parameters", 54, 32),
        ("CPX2y", "control_parameters", 54, 32),
        ("CPY1x", "control_parameters", 55, 33),
        ("CPY1y", "control_parameters", 55, 33),
        ("CPY2x", "control_parameters", 56, 34),
        ("CPY2y", "control_parameters", 56, 34),
        ("CPZ1x", "control_parameters", 57, 35),
        ("CPZ1y", "control_parameters", 57, 35),
        ("CPZ2x", "control_parameters", 58, 36),
        ("CPZ2y", "control_parameters", 58, 36),
        ("Tens", "curve_parameters", 60, 38),
        ("Cont", "curve_parameters", 61, 39),
        ("Bias", "curve_parameters", 62, 40),
        ("EaseIn", "curve_parameters", 63, 41),
        ("EaseOut", "curve_parameters", 64, 42),
        ("Deriv", "flags", 65, 43),
        ("DerivInX", "derived_vectors", 66, 44),
        ("DerivInY", "derived_vectors", 66, 44),
        ("DerivInZ", "derived_vectors", 66, 44),
        ("DerivOutX", "derived_vectors", 67, 45),
        ("DerivOutY", "derived_vectors", 67, 45),
        ("DerivOutZ", "derived_vectors", 67, 45),
        ("AngleKey", "flags", 68, 46),
    )
    read_expressions = {
        27: "reader >> ValueX >> ValueY >> ValueZ",
        28: "reader >> InterpolationX >> InterpolationY >> InterpolationZ",
        29: "reader >> Time",
        31: "reader >> CPX1x >> CPX1y",
        32: "reader >> CPX2x >> CPX2y",
        33: "reader >> CPY1x >> CPY1y",
        34: "reader >> CPY2x >> CPY2y",
        35: "reader >> CPZ1x >> CPZ1y",
        36: "reader >> CPZ2x >> CPZ2y",
        38: "reader >> Tens",
        39: "reader >> Cont",
        40: "reader >> Bias",
        41: "reader >> EaseIn",
        42: "reader >> EaseOut",
        43: "reader >> Deriv",
        44: "reader >> DerivInX >> DerivInY >> DerivInZ",
        45: "reader >> DerivOutX >> DerivOutY >> DerivOutZ",
        46: "reader >> AngleKey",
    }

    vector_uses = {
        "ValueX": (184, 185, 'axis == "X" -> ValueX'),
        "ValueY": (186, 187, 'axis == "Y" -> ValueY'),
        "ValueZ": (188, 189, 'axis == "Z" -> ValueZ'),
    }
    mode_uses = {
        "InterpolationX": (197, 198, 'axis == "X" -> InterpolationX'),
        "InterpolationY": (199, 200, 'axis == "Y" -> InterpolationY'),
        "InterpolationZ": (201, 202, 'axis == "Z" -> InterpolationZ'),
    }
    control_uses = {
        "CPX1x": (244, 245, "CPX1x, CPX1y"),
        "CPX1y": (244, 245, "CPX1x, CPX1y"),
        "CPX2x": (254, 255, "CPX2x, CPX2y"),
        "CPX2y": (254, 255, "CPX2x, CPX2y"),
        "CPY1x": (246, 247, "CPY1x, CPY1y"),
        "CPY1y": (246, 247, "CPY1x, CPY1y"),
        "CPY2x": (256, 257, "CPY2x, CPY2y"),
        "CPY2y": (256, 257, "CPY2x, CPY2y"),
        "CPZ1x": (248, 249, "CPZ1x, CPZ1y"),
        "CPZ1y": (248, 249, "CPZ1x, CPZ1y"),
        "CPZ2x": (258, 259, "CPZ2x, CPZ2y"),
        "CPZ2y": (258, 259, "CPZ2x, CPZ2y"),
    }
    curve_validation = {
        "Tens": (126, 129, "Tens != 0 -> unsupported"),
        "Cont": (131, 134, "Cont != 0 -> unsupported"),
        "Bias": (136, 139, "Bias != 0 -> unsupported"),
        "EaseIn": (141, 144, "EaseIn != 0 -> unsupported"),
        "EaseOut": (146, 149, "EaseOut != 0 -> unsupported"),
    }

    field_map = []
    for slot, (member, group, declaration_line, read_line) in zip(
        _ANI_KEY_RECORD_CANDIDATE_SLOTS, field_specs
    ):
        use_sites: list[dict[str, object]] = []
        if member in vector_uses:
            start, end, expression = vector_uses[member]
            use_sites.extend(
                (
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::getValueByAxis",
                        start,
                        end,
                        expression,
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::WriteChannel",
                        220,
                        221,
                        "getValueByAxis(axis) -> frame value attribute",
                    ),
                )
            )
        elif member in mode_uses:
            start, end, expression = mode_uses[member]
            use_sites.extend(
                (
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::getInterpByAxis",
                        start,
                        end,
                        expression,
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::validate",
                        67,
                        81,
                        "checkInterpolationType and getInterpolationTypeName",
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::WriteChannel",
                        210,
                        224,
                        "select, check, name, and emit axis mode",
                    ),
                )
            )
        elif member == "Time":
            use_sites.extend(
                (
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::validate",
                        84,
                        84,
                        "report Time",
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::WriteChannel",
                        216,
                        218,
                        "numeric_cast<int>(30.0 * Time) -> frame id",
                    ),
                )
            )
        elif member in control_uses:
            start, end, expression = control_uses[member]
            use_sites.extend(
                (
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::getControlPoint",
                        start,
                        end,
                        expression,
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::WriteHandle",
                        228,
                        238,
                        "getControlPoint(axis, right) -> handle attributes",
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::validate",
                        104,
                        123,
                        "raw mode 2 checks the corresponding four CP members",
                    ),
                )
            )
        elif member in curve_validation:
            start, end, expression = curve_validation[member]
            use_sites.append(
                _x4converter_site(
                    _X4CONVERTER_KEYFRAME_SOURCE,
                    "Keyframe::validate",
                    start,
                    end,
                    expression,
                )
            )
        elif member == "Deriv":
            use_sites.append(
                _x4converter_site(
                    _X4CONVERTER_KEYFRAME_SOURCE,
                    "Keyframe::validate",
                    98,
                    155,
                    "report Deriv; any nonzero Deriv group member is unsupported",
                )
            )
        elif member.startswith("DerivIn") or member.startswith("DerivOut"):
            use_sites.append(
                _x4converter_site(
                    _X4CONVERTER_KEYFRAME_SOURCE,
                    "Keyframe::validate",
                    100,
                    155,
                    "report vectors; any nonzero Deriv group member is unsupported",
                )
            )
        else:
            use_sites.append(
                _x4converter_site(
                    _X4CONVERTER_KEYFRAME_SOURCE,
                    "Keyframe::validate",
                    103,
                    103,
                    "report AngleKey; no branch or conversion use found",
                )
            )
        field_map.append(
            {
                **slot,
                "x4converter_member": member,
                "x4converter_group": group,
                "x4converter_declaration_site": _x4converter_site(
                    _X4CONVERTER_KEYFRAME_HEADER,
                    "ani::Keyframe member declaration",
                    declaration_line,
                    declaration_line,
                    member,
                ),
                "x4converter_read_site": _x4converter_site(
                    _X4CONVERTER_KEYFRAME_SOURCE,
                    "Keyframe::Keyframe(StreamReaderLE &reader)",
                    read_line,
                    read_line,
                    read_expressions[read_line],
                ),
                "x4converter_use_sites": use_sites,
                "evidence_classification": "third-party-technique",
                "independent_corroboration_required": True,
            }
        )

    group_hypotheses = (
        (
            "candidate_vector",
            "ValueX/ValueY/ValueZ are selected by axis and emitted as a frame value",
        ),
        (
            "per_axis_mode",
            "InterpolationX/Y/Z are selected by axis, checked, named, and emitted",
        ),
        (
            "record_order_scalar",
            "Time is multiplied by 30, integer-cast, and emitted as a frame id",
        ),
        (
            "control_parameters",
            "six axis/side pairs are selected by getControlPoint and emitted by WriteHandle",
        ),
        (
            "curve_parameters",
            "Tens, Cont, Bias, EaseIn, and EaseOut are named but rejected when nonzero",
        ),
        (
            "flags",
            "Deriv is checked as part of an unsupported group; AngleKey is reported only",
        ),
        (
            "derived_vectors",
            "DerivIn and DerivOut triples are reported and rejected when nonzero",
        ),
        (
            "unused_or_reserved",
            "no byte range is declared unused or reserved; AngleKey has no use beyond reporting",
        ),
    )
    record_field_groups = []
    for group_id, hypothesis in group_hypotheses:
        group_fields = [field for field in field_map if field["x4converter_group"] == group_id]
        record_field_groups.append(
            {
                "group_id": group_id,
                "slot_ids": [str(field["slot_id"]) for field in group_fields],
                "x4converter_members": [
                    str(field["x4converter_member"]) for field in group_fields
                ],
                "x4converter_hypothesis": hypothesis,
                "evidence_classification": "third-party-technique",
                "independent_corroboration_required": True,
            }
        )

    common_enum_branches = [
        _x4converter_site(
            _X4CONVERTER_KEYFRAME_SOURCE,
            "Keyframe::checkInterpolationType",
            163,
            170,
            (
                "type == INTERPOLATION_STEP || type == INTERPOLATION_BEZIER"
                " || type == INTERPOLATION_LINEAR"
            ),
        )
    ]
    enum_mapping = []
    for raw_value, identifier, readable_name in (
        (1, "INTERPOLATION_STEP", "STEP"),
        (2, "INTERPOLATION_LINEAR", "LINEAR"),
        (5, "INTERPOLATION_BEZIER", "BEZIER"),
    ):
        branch_sites = list(common_enum_branches)
        if raw_value == 2:
            branch_sites.extend(
                (
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::validate",
                        106,
                        110,
                        "InterpolationX == 2 -> corresponding CP nonzero is invalid",
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::validate",
                        112,
                        116,
                        "InterpolationY == 2 -> corresponding CP nonzero is invalid",
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::validate",
                        118,
                        122,
                        "InterpolationZ == 2 -> corresponding CP nonzero is invalid",
                    ),
                )
            )
        enum_mapping.append(
            {
                "raw_value": raw_value,
                "raw_bits": f"0x{raw_value:08x}",
                "x4converter_identifier": identifier,
                "x4converter_readable_name": readable_name,
                "declaration_site": _x4converter_site(
                    _X4CONVERTER_KEYFRAME_HEADER,
                    "ani::InterpolationType",
                    8,
                    16,
                    identifier,
                ),
                "branch_sites": branch_sites,
                "common_use_sites": [
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::getInterpolationTypeName",
                        173,
                        180,
                        "enumeration value indexes readable-name array",
                    ),
                    _x4converter_site(
                        _X4CONVERTER_KEYFRAME_SOURCE,
                        "Keyframe::WriteChannel",
                        210,
                        224,
                        "checked mode is emitted by readable name",
                    ),
                ],
                "observed_in_selected_conventional_inventory": True,
                "evidence_classification": "third-party-technique",
                "independent_corroboration_required": True,
            }
        )

    channel_groups = []
    for index, count_member, vector_member, read_lines, output_label in (
        (0, "NumPosKeys", "posKeys", [91, 93], "location"),
        (1, "NumRotKeys", "rotKeys", [94, 96], "rotation_euler"),
        (2, "NumScaleKeys", "scaleKeys", [97, 99], "scale"),
        (3, "NumPreScaleKeys", "preScaleKeys", [100, 102], None),
        (4, "NumPostScaleKeys", "postScaleKeys", [103, 105], None),
    ):
        channel_groups.append(
            {
                "candidate_channel_count_field_index": index,
                "x4converter_count_member": count_member,
                "x4converter_record_vector_member": vector_member,
                "record_read_site": _x4converter_site(
                    _X4CONVERTER_ANIMDESC_SOURCE,
                    "AnimDesc::read_frames",
                    read_lines[0],
                    read_lines[1],
                    f"{count_member} records -> {vector_member}",
                ),
                "intermediate_output_label": output_label,
                "intermediate_output_site": (
                    _x4converter_site(
                        _X4CONVERTER_ANIMDESC_SOURCE,
                        "AnimDesc::WriteIntermediateReprOfChannel",
                        289,
                        298,
                        f'{vector_member} selected for keyType "{output_label}"',
                    )
                    if output_label is not None
                    else None
                ),
                "evidence_classification": "third-party-technique",
                "independent_corroboration_required": True,
            }
        )

    corroboration_rows = (
        (
            "descriptor_channel_group_identity",
            "no_semantic_evidence",
            "raw channel counts and record ranges do not establish the five X4Converter group meanings",
        ),
        (
            "candidate_vector_component_identity",
            "no_semantic_evidence",
            "raw triples establish bits and ordering only",
        ),
        (
            "per_axis_mode_identity",
            "merely_consistent",
            "observed words 1, 2, and 5 match X4Converter enum ordinals but do not establish engine meanings",
        ),
        (
            "mode_specific_behavior",
            "no_semantic_evidence",
            "observed values do not demonstrate the branches or output behavior used by X4Converter",
        ),
        (
            "record_order_scalar_identity",
            "merely_consistent",
            "strictly increasing slot_024 sequences are consistency observations only",
        ),
        (
            "record_order_scalar_unit_and_30_multiplier",
            "no_semantic_evidence",
            "record ordering does not establish a unit or X4Converter's multiplication assumption",
        ),
        (
            "control_parameter_pair_identity_and_side_assignment",
            "merely_consistent",
            "slot_028 through slot_072 patterns do not discriminate X4Converter's pair or side assignments",
        ),
        (
            "curve_parameter_identities",
            "merely_consistent",
            "zero slot_076 through slot_092 values are consistency observations only",
        ),
        (
            "derivative_flag_and_vector_identities",
            "merely_consistent",
            "zero slot_096 through slot_120 values are consistency observations only",
        ),
        (
            "angle_key_flag_identity",
            "merely_consistent",
            "zero slot_124 values are consistency observations only",
        ),
        (
            "zero_tail_member_identities",
            "merely_consistent",
            "zero tail fields do not establish any named member meaning",
        ),
        (
            "intermediate_output_channel_semantics",
            "no_semantic_evidence",
            "X4Converter output labels are not independent evidence of X4 behavior",
        ),
    )
    return {
        "evidence_classification": "third-party-technique",
        "semantic_status": "hypothesis_only",
        "source_revision": {
            "repository": "https://github.com/Cgettys/X4Converter.git",
            "commit": _X4CONVERTER_COMMIT,
            "commit_date": "2019-10-21",
            "inspection": "direct pinned checkout",
        },
        "record_size_bytes": _ANI_KEY_RECORD_SIZE,
        "decision_driving_component_class": "conventional",
        "missileturret_semantic_analysis": "excluded",
        "excluded_evidence": ["archived Issue #69 conclusions"],
        "field_map": field_map,
        "record_field_groups": record_field_groups,
        "candidate_channel_grouping": channel_groups,
        "x4converter_control_parameter_routing": {
            "write_channel_call_site": _x4converter_site(
                _X4CONVERTER_KEYFRAME_SOURCE,
                "Keyframe::WriteChannel",
                222,
                223,
                "WriteHandle(..., false) then WriteHandle(..., true)",
            ),
            "output_node_branch_site": _x4converter_site(
                _X4CONVERTER_KEYFRAME_SOURCE,
                "Keyframe::WriteHandle",
                228,
                238,
                "right true -> handle_left; right false -> handle_right",
            ),
            "member_selection_branch_site": _x4converter_site(
                _X4CONVERTER_KEYFRAME_SOURCE,
                "Keyframe::getControlPoint",
                241,
                263,
                "right false -> CP1 pair; right true -> CP2 pair",
            ),
            "routes": [
                {
                    "right_argument": False,
                    "output_node": "handle_right",
                    "selected_member_suffix": "1",
                },
                {
                    "right_argument": True,
                    "output_node": "handle_left",
                    "selected_member_suffix": "2",
                },
            ],
            "evidence_classification": "third-party-technique",
            "independent_corroboration_required": True,
        },
        "observed_enum_mapping": enum_mapping,
        "independent_corroboration_assessment_scale": [
            "discriminates",
            "merely_consistent",
            "no_semantic_evidence",
        ],
        "independent_corroboration_required": [
            {
                "candidate_semantic": candidate_semantic,
                "current_observation_assessment": assessment,
                "current_observation_boundary": boundary,
                "required": True,
                "evidence_classification": "third-party-technique",
            }
            for candidate_semantic, assessment, boundary in corroboration_rows
        ],
        "discriminated_candidate_semantics": [],
        "semantic_promotion": "not_permitted_by_this_inventory",
    }
