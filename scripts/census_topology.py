"""Deterministic structural topology inventory for the Issue #72 A3 census report."""
from __future__ import annotations

from typing import Sequence

from census_ani_parser import _ANI_CHANNEL_COUNT_FIELDS

_COMBAT_CANDIDATE = "COMBAT_CANDIDATE"
_EndpointRecord = tuple[int, tuple[tuple[int, ...], ...]]
_TopologySignature = tuple[int, tuple[_EndpointRecord, ...]]


def _endpoint_topology_record(
    endpoint: dict[str, object],
) -> _EndpointRecord:
    """Reduce one resolved firing endpoint to structural numbers only.

    Part, subname, connection, macro, and component names are dropped; only the
    source-part path depth and the selected descriptor channel-count tuples
    remain. No ANI value, timing, or transform meaning is claimed.
    """
    channel_count_tuples = tuple(
        sorted(
            tuple(
                int(member["channel_counts"][field])
                for field in _ANI_CHANNEL_COUNT_FIELDS
            )
            for member in endpoint["selected_ani_descriptor_memberships"]
        )
    )
    return (
        int(len(endpoint["source_part_path"])),
        channel_count_tuples,
    )


def _build_combat_conventional_topology_inventory(
    combat_eligibility: dict[str, object],
    component_to_macros: Sequence[dict[str, object]],
) -> dict[str, object]:
    """Group exactly the COMBAT_CANDIDATE macros by structural endpoint topology.

    Grouping uses only structural numbers: the endpoint count and the sorted
    per-endpoint records of source-part path depth and selected descriptor
    channel-count tuples. Names may appear only in the membership lists.
    """
    endpoints_by_component = {
        str(record["component"]): record["firing_endpoints"]
        for record in component_to_macros
    }
    groups_by_signature: dict[_TopologySignature, dict[str, set[str]]] = {}
    eligible = [
        entry
        for entry in combat_eligibility["macro_classifications"]
        if str(entry["eligibility"]) == _COMBAT_CANDIDATE
    ]
    for entry in eligible:
        component = str(entry["component"])
        endpoints = endpoints_by_component[component]
        signature = (
            len(endpoints),
            tuple(sorted(map(_endpoint_topology_record, endpoints))),
        )
        members = groups_by_signature.setdefault(
            signature, {"macros": set(), "components": set()}
        )
        members["macros"].add(str(entry["macro"]))
        members["components"].add(component)

    groups = []
    for signature, members in sorted(
        groups_by_signature.items(),
        key=lambda item: (-len(item[1]["macros"]), item[0]),
    ):
        endpoint_count, endpoint_structure = signature
        groups.append(
            {
                "endpoint_count": endpoint_count,
                "endpoint_structure": [
                    {
                        "source_part_path_depth": depth,
                        "selected_descriptor_channel_count_tuples": [
                            list(channel_counts)
                            for channel_counts in channel_count_tuples
                        ],
                    }
                    for depth, channel_count_tuples in endpoint_structure
                ],
                "macro_count": len(members["macros"]),
                "unique_component_count": len(members["components"]),
                "macros": sorted(members["macros"]),
                "components": sorted(members["components"]),
            }
        )
    return {
        "evidence_classification": "shipped-source",
        "semantic_claim": "none",
        "macro_count": len(eligible),
        "unique_component_count": len(
            {str(entry["component"]) for entry in eligible}
        ),
        "group_count": len(groups),
        "groups": groups,
    }
