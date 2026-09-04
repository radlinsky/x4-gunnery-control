#!/usr/bin/env python3
"""Build the Issue #72 macro-driven X4 9.00 turret asset census.

This tool stops at exact authored connection paths, firing-endpoint connection
identities, ANI descriptor/source-part identity, descriptor channel counts,
candidate key-record byte ownership, and raw candidate typed-slot patterns. It
does not assign key-record field semantics or interpret transforms, timing,
interpolation, pivots, axes, joints, descriptor relevance, active pose, or
prospective muzzle position.
"""
from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path
from typing import Mapping, Sequence

from census_anchor_evidence import (
    _PARANID_L_BEAM_ACCEPTED_PRODUCTION_FORMULA,
    _PARANID_L_BEAM_TRACE_SPEC,
    _anchor_add,
    _anchor_ani_vector,
    _anchor_connection_vector,
    _anchor_descriptor_inventory,
    _anchor_quaternion_apply,
    _anchor_quaternion_multiply,
    _anchor_vectors_equal,
    _build_paranid_l_beam_live_anchor,
    _evaluate_paranid_l_beam_trace,
)
from census_ani_analysis import (
    _ANI_KEY_RECORD_CANDIDATE_CHANNEL_TRIPLE_SLOTS,
    _CANDIDATE_MAIN_SLOT_IDS,
    _CANDIDATE_MAIN_SLOT_INDEXES,
    _DESCRIPTOR_RAW_BIT_DISTRIBUTION_LIMIT,
    _DESCRIPTOR_SLOT_024_NUMERIC_RELATIONSHIPS,
    _DESCRIPTOR_SLOT_024_RAW_RELATIONSHIPS,
    _build_channel_1_restriction_correlation,
    _candidate_main_component_observations,
    _classify_descriptor_slot_024_numeric_relationship,
    _classify_descriptor_slot_024_raw_relationship,
    _descriptor_offset_148_float,
    _descriptor_offset_148_raw_uint,
    _inventory_candidate_multi_key_metadata,
    _restriction_cohort_summary,
    _restriction_correlation_descriptor_record,
    _single_restriction_comparison,
    _summarize_candidate_channel_dynamics,
    _summarize_candidate_raw_key_records,
    _summarize_descriptor_offset_148_values,
    _summarize_descriptor_slot_024_relationships,
)
from census_ani_parser import (
    AniDescriptorError,
    _ANI_CHANNEL_COUNT_FIELDS,
    _ANI_DESCRIPTOR_OFFSET_148,
    _ANI_DESCRIPTOR_SIZE,
    _ANI_HEADER_SIZE,
    _ANI_KEY_RECORD_CANDIDATE_BYTE_COUNTS,
    _ANI_KEY_RECORD_CANDIDATE_OVERLAPPING_BYTES,
    _ANI_KEY_RECORD_CANDIDATE_SLOTS,
    _ANI_KEY_RECORD_CANDIDATE_TYPES,
    _ANI_KEY_RECORD_CANDIDATE_UNACCOUNTED_BYTES,
    _ANI_KEY_RECORD_SIZE,
    _ANI_STRING_SIZE,
    _candidate_float32_decode,
    _decode_ani_descriptor_string,
    _parse_ani_descriptors,
    _parse_candidate_key_record,
)
from census_ani_relationships import (
    _build_ancestry_covered_turret_active_candidate_channel_inventory,
    _build_changing_turret_active_case_inventory,
    _build_same_subname_structural_relationship_coverage,
    _build_subname_candidate_channel_inventory,
    _candidate_first_three_change_case,
    _focused_literal_turret_active,
    _subname_candidate_channel_summary,
    _subname_inventory_for_class,
)
from census_common import (
    REQUIRED_SOURCE_SETS,
    CensusError,
    _anomaly,
    render_json,
)
from census_eligibility import (
    _build_combat_conventional_turret_eligibility,
    _purpose_tokens,
)
from census_endpoint_paths import (
    _FIRING_ENDPOINT_TAG_BY_COMPONENT_CLASS,
    _classify_firing_endpoints,
    _derive_endpoint_authored_geometry,
    _derive_endpoint_source_paths,
    _join_authored_animation_selectors,
    _resolve_connection_hierarchy,
)
from census_identity import (
    _INCLUDED_CLASSES,
    _authored_numeric_attributes,
    _authored_restriction_limit,
    _build_ani_resource_inventory,
    _collect_xml_identities,
    _direct_children,
    _normalized_resource_identity,
    _parse_authored_connection_offset,
    _parse_authored_connection_restrictions,
    _resolve_component_identity,
    _resolve_geometry_ani_resource_identity,
    _resolve_macro_identities,
    _validate_authored_animation_selectors,
)
from census_pipeline import build_census
from census_reconciliation import (
    _comparison,
    _current_historical_comparison,
    _group_current_components,
    _group_historical_components,
    _parse_historical_components,
    build_reconciliation,
)
from census_report import _assemble_census_report, _strip_candidate_raw_key_records
from census_sources import (
    _validate_resource_sets,
    _validate_source_sets,
    _xml_files,
)
from census_x4converter_evidence import (
    _X4CONVERTER_ANIMDESC_SOURCE,
    _X4CONVERTER_COMMIT,
    _X4CONVERTER_KEYFRAME_HEADER,
    _X4CONVERTER_KEYFRAME_SOURCE,
    _x4converter_candidate_key_record_semantic_lead,
    _x4converter_descriptor_offset_148_lead,
    _x4converter_site,
)

_ACCEPTED_TURRET_ACTIVE_CHANGING_CASE_BASELINE = (444, 2, 2)


def _parse_source_set(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected NAME=PATH")
    name, raw_path = value.split("=", 1)
    if not name or not raw_path:
        raise argparse.ArgumentTypeError("expected non-empty NAME=PATH")
    return name, Path(raw_path)


def _arguments(argv: Sequence[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Census official X4 9.00 turret/missile-turret macros and referenced components."
    )
    parser.add_argument(
        "--source-set",
        action="append",
        default=[],
        metavar="NAME=PATH",
        type=_parse_source_set,
        help="repeat exactly once for base and each required official extension XML root",
    )
    parser.add_argument(
        "--resource-set",
        action="append",
        default=[],
        metavar="NAME=PATH",
        type=_parse_source_set,
        help="repeat exactly once for each complete official ANI resource root",
    )
    parser.add_argument("--output", type=Path, help="write census JSON here instead of stdout")
    parser.add_argument(
        "--require-accepted-turret-active-changing-case-baseline",
        action="store_true",
        help=(
            "fail unless the 444-descriptor turret_active cohort has exactly"
            " two changing cases in each of candidate channels 0 and 1"
        ),
    )
    parser.add_argument("--old79-components", type=Path, help="preserved old 79-component cache")
    parser.add_argument("--platform-sweep", type=Path, help="preserved platform-sweep cache")
    parser.add_argument("--reconciliation-output", type=Path, help="write historical reconciliation JSON here")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _arguments(argv)
    source_sets: dict[str, Path] = {}
    resource_sets: dict[str, Path] = {}
    duplicate_arguments: list[dict[str, object]] = []
    for name, path in args.source_set:
        if name in source_sets:
            duplicate_arguments.append(
                _anomaly("duplicate_source_set_argument", "source set was supplied more than once", source_set=name)
            )
        source_sets[name] = path
    for name, path in args.resource_set:
        if name in resource_sets:
            duplicate_arguments.append(
                _anomaly(
                    "duplicate_resource_set_argument",
                    "ANI resource set was supplied more than once",
                    source_set=name,
                )
            )
        resource_sets[name] = path

    try:
        if duplicate_arguments:
            raise CensusError(duplicate_arguments)
        reconciliation_arguments = (args.old79_components, args.platform_sweep, args.reconciliation_output)
        if any(reconciliation_arguments) and not all(reconciliation_arguments):
            raise CensusError(
                [
                    _anomaly(
                        "incomplete_reconciliation_arguments",
                        "old79, platform-sweep, and reconciliation output must be supplied together",
                    )
                ]
            )
        report = build_census(
            source_sets,
            resource_sets,
            expected_turret_active_changing_case_baseline=(
                _ACCEPTED_TURRET_ACTIVE_CHANGING_CASE_BASELINE
                if args.require_accepted_turret_active_changing_case_baseline
                else None
            ),
        )
        reconciliation = (
            build_reconciliation(report, args.old79_components, args.platform_sweep)
            if all(reconciliation_arguments)
            else None
        )
    except CensusError as exc:
        sys.stderr.write(str(exc) + "\n")
        return 2

    output = render_json(report)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)
    if reconciliation is not None:
        args.reconciliation_output.parent.mkdir(parents=True, exist_ok=True)
        args.reconciliation_output.write_text(render_json(reconciliation), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
