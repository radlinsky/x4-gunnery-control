"""Combat conventional turret eligibility classification for the Issue #78 census tools."""
from __future__ import annotations

from collections import defaultdict
from typing import Sequence

from census_common import _anomaly


def _purpose_tokens(attributes: Sequence[object]) -> list[str]:
    return sorted(
        {
            token
            for value in attributes
            if value is not None
            for token in str(value).split()
        }
    )


def _build_combat_conventional_turret_eligibility(
    equipment_macros: Sequence[dict[str, str]],
    ware_records: Sequence[dict[str, object]],
) -> tuple[dict[str, object] | None, list[dict[str, object]]]:
    anomalies: list[dict[str, object]] = []
    included_macros = {record["name"] for record in equipment_macros}
    records_by_macro = {record["name"]: record for record in equipment_macros}
    wares_by_macro: dict[str, list[dict[str, object]]] = defaultdict(list)
    for record in ware_records:
        if str(record["component"]) in included_macros:
            wares_by_macro[str(record["component"])].append(record)

    resolved_by_macro: dict[str, dict[str, object]] = {}
    no_ware_by_macro: dict[str, dict[str, object]] = {}
    for macro in sorted(included_macros):
        matches = wares_by_macro.get(macro, [])
        macro_record = records_by_macro[macro]
        if not matches:
            no_ware_by_macro[macro] = {
                "macro": macro,
                "macro_class": macro_record["class"],
                "component": macro_record["component"],
                "macro_source_set": macro_record["source_set"],
                "macro_source_file": macro_record["source_file"],
                "eligibility": "UNRESOLVED",
                "unresolved_reason": "no_exact_equipment_ware",
                "evidence": {
                    "macro_source_set": macro_record["source_set"],
                    "macro_source_file": macro_record["source_file"],
                    "component": macro_record["component"],
                    "macro_class": macro_record["class"],
                },
            }
            continue
        malformed = [
            record
            for record in matches
            if not str(record.get("ware", ""))
            or int(record.get("component_reference_count", 0)) != 1
        ]
        if malformed:
            anomalies.append(
                _anomaly(
                    "malformed_effective_equipment_ware",
                    "effective equipment ware mapping is missing required exact identity data or has ambiguous direct use data",
                    macro=macro,
                    component=macro_record["component"],
                    definitions=sorted(
                        malformed,
                        key=lambda item: (
                            str(item.get("source_set", "")),
                            str(item.get("source_file", "")),
                            str(item.get("ware", "")),
                        ),
                    ),
                )
            )
            continue
        if len(matches) > 1:
            signatures = {
                (
                    str(record["ware"]),
                    tuple(_purpose_tokens(record["purpose_attributes"])),
                )
                for record in matches
            }
            anomalies.append(
                _anomaly(
                    "conflicting_effective_equipment_ware_mapping"
                    if len(signatures) > 1
                    else "duplicate_effective_equipment_ware_mapping",
                    "included macro resolves to more than one effective equipment ware mapping",
                    macro=macro,
                    component=macro_record["component"],
                    definitions=sorted(
                        matches,
                        key=lambda item: (
                            str(item.get("source_set", "")),
                            str(item.get("source_file", "")),
                            str(item.get("ware", "")),
                        ),
                    ),
                )
            )
            continue
        resolved_by_macro[macro] = matches[0]

    if anomalies:
        return None, anomalies

    macro_classifications: list[dict[str, object]] = []
    utility_macros: list[dict[str, object]] = []
    unresolved_components: set[str] = set()
    purpose_inventory: dict[str, dict[str, set[str]]] = defaultdict(
        lambda: {"macros": set(), "components": set()}
    )
    for record in sorted(equipment_macros, key=lambda item: item["name"]):
        if record["name"] in no_ware_by_macro:
            entry = no_ware_by_macro[record["name"]]
            macro_classifications.append(entry)
            unresolved_components.add(record["component"])
            continue
        ware = resolved_by_macro[record["name"]]
        tokens = _purpose_tokens(ware["purpose_attributes"])
        if record["class"] == "missileturret":
            eligibility = "MISSILETURRET_EXCLUDED"
        elif int(ware.get("use_count", 0)) > 1:
            if not any(value is not None for value in ware["purpose_attributes"]):
                eligibility = "COMBAT_CANDIDATE"
            else:
                eligibility = "UNRESOLVED"
                unresolved_reason = "MULTIPLE_DIRECT_USE_ELEMENTS"
                unresolved_components.add(record["component"])
        elif not tokens:
            eligibility = "COMBAT_CANDIDATE"
        elif tokens in (["mine"], ["salvage"]):
            eligibility = "NONCOMBAT_UTILITY"
        else:
            eligibility = "UNRESOLVED"
            unresolved_reason = "UNSUPPORTED_OR_COMBINED_WARE_PURPOSES"
            unresolved_components.add(record["component"])
        if record["class"] == "turret":
            for token in tokens:
                purpose_inventory[token]["macros"].add(record["name"])
                purpose_inventory[token]["components"].add(record["component"])
        entry = {
            "macro": record["name"],
            "macro_class": record["class"],
            "component": record["component"],
            "macro_source_set": record["source_set"],
            "macro_source_file": record["source_file"],
            "ware": ware["ware"],
            "purpose_tokens": tokens,
            "direct_use_count": ware["use_count"],
            "direct_use_records": ware.get("use_records", []),
            "eligibility": eligibility,
            "ware_source_set": ware["source_set"],
            "ware_source_file": ware["source_file"],
        }
        if eligibility == "UNRESOLVED":
            entry["unresolved_reason"] = unresolved_reason

        macro_classifications.append(entry)
        if eligibility == "NONCOMBAT_UTILITY":
            utility_macros.append(entry)

    def counted(eligibility: str, macro_class: str | None = None) -> tuple[int, int]:
        selected = [
            item
            for item in macro_classifications
            if item["eligibility"] == eligibility
            and (macro_class is None or item["macro_class"] == macro_class)
        ]
        return len(selected), len({str(item["component"]) for item in selected})

    combat_macros, combat_components = counted("COMBAT_CANDIDATE", "turret")
    utility_count, utility_components = counted("NONCOMBAT_UTILITY", "turret")
    missile_macros, missile_components = counted("MISSILETURRET_EXCLUDED", "missileturret")
    unresolved_macros, unresolved_unique_components = counted("UNRESOLVED")
    return {
        "evidence_classification": "shipped-source",
        "mapping_rule": "exact direct ware/component ref identity equals exact included equipment macro name identity",
        "purpose_rule": {
            "no_purpose_token": "COMBAT_CANDIDATE",
            "exactly_mine_or_salvage": "NONCOMBAT_UTILITY",
            "missileturret": "MISSILETURRET_EXCLUDED",
            "other": "UNRESOLVED_FAIL_CLOSED",
        },
        "counts": {
            "combat_candidate_macros": combat_macros,
            "combat_candidate_unique_components": combat_components,
            "noncombat_utility_macros": utility_count,
            "noncombat_utility_unique_components": utility_components,
            "missileturret_excluded_macros": missile_macros,
            "missileturret_excluded_unique_components": missile_components,
            "unresolved_macros": unresolved_macros,
            "unresolved_unique_components": unresolved_unique_components,
        },
        "observed_conventional_turret_purpose_token_inventory": [
            {
                "purpose_token": token,
                "macro_count": len(purpose_inventory[token]["macros"]),
                "unique_component_count": len(purpose_inventory[token]["components"]),
            }
            for token in sorted(purpose_inventory)
        ],
        "utility_macros": utility_macros,
        "nonware_macro_exclusions": [],
        "unresolved_macros": [
            item for item in macro_classifications if item["eligibility"] == "UNRESOLVED"
        ],
        "unresolved_no_ware_macros": [
            item
            for item in macro_classifications
            if item.get("unresolved_reason") == "no_exact_equipment_ware"
        ],
        "macro_classifications": macro_classifications,
        "required_macro_local_classifications": [
            item
            for item in macro_classifications
            if item["macro"]
            in {
                "turret_bor_m_mining_01_mk1_macro",
                "turret_gen_m_scrapbeam_01_mk1_macro",
                "turret_gen_m_disabler_01_mk1_macro",
            }
        ],
    }, []
