"""Shared definitions for the Issue #78 X4 9.00 census tools."""
from __future__ import annotations

import json
from typing import Iterable

REQUIRED_SOURCE_SETS = (
    "base",
    "ego_dlc_split",
    "ego_dlc_terran",
    "ego_dlc_pirate",
    "ego_dlc_boron",
    "ego_dlc_timelines",
    "ego_dlc_mini_01",
    "ego_dlc_mini_02",
)


class CensusError(Exception):
    """A fail-closed census error with deterministic machine-readable details."""

    def __init__(self, anomalies: Iterable[dict[str, object]]):
        self.anomalies = sorted(
            anomalies,
            key=lambda item: (
                str(item.get("code", "")),
                str(item.get("source_set", "")),
                str(item.get("source_file", "")),
                str(item.get("macro", "")),
                str(item.get("component", "")),
            ),
        )
        self.codes = tuple(str(item["code"]) for item in self.anomalies)
        super().__init__(render_json({"status": "error", "anomalies": self.anomalies}).rstrip())


def _anomaly(code: str, message: str, **details: object) -> dict[str, object]:
    return {"code": code, "message": message, **details}


def render_json(report: object) -> str:
    return json.dumps(report, indent=2, sort_keys=True, ensure_ascii=True) + "\n"
