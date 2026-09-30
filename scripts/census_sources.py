"""Shared source/resource-set validation and file enumeration for the Issue #78 X4 9.00 census tools."""
from __future__ import annotations

from pathlib import Path
from typing import Mapping

from census_common import (
    REQUIRED_SOURCE_SETS,
    CensusError,
    _anomaly,
)


def _validate_source_sets(source_sets: Mapping[str, Path]) -> dict[str, Path]:
    anomalies: list[dict[str, object]] = []
    expected = set(REQUIRED_SOURCE_SETS)
    supplied = set(source_sets)

    for name in sorted(expected - supplied):
        anomalies.append(
            _anomaly("missing_required_source_set", "required official source set was not supplied", source_set=name)
        )
    for name in sorted(supplied - expected):
        anomalies.append(
            _anomaly("unexpected_source_set", "source set is outside the Issue #72 official set", source_set=name)
        )

    normalized: dict[str, Path] = {}
    for name in REQUIRED_SOURCE_SETS:
        if name not in source_sets:
            continue
        path = Path(source_sets[name])
        if not path.is_dir():
            anomalies.append(
                _anomaly(
                    "unavailable_required_source_set",
                    "required official source-set directory is unavailable",
                    source_set=name,
                )
            )
        elif not _xml_files(path):
            anomalies.append(
                _anomaly(
                    "empty_required_source_set",
                    "required official source-set directory contains no XML source",
                    source_set=name,
                )
            )
        else:
            normalized[name] = path

    if anomalies:
        raise CensusError(anomalies)
    return normalized


def _validate_resource_sets(resource_sets: Mapping[str, Path]) -> dict[str, Path]:
    anomalies: list[dict[str, object]] = []
    expected = set(REQUIRED_SOURCE_SETS)
    supplied = set(resource_sets)

    for name in sorted(expected - supplied):
        anomalies.append(
            _anomaly(
                "missing_required_resource_set",
                "required official ANI resource set was not supplied",
                source_set=name,
            )
        )
    for name in sorted(supplied - expected):
        anomalies.append(
            _anomaly(
                "unexpected_resource_set",
                "ANI resource set is outside the Issue #72 official set",
                source_set=name,
            )
        )

    normalized: dict[str, Path] = {}
    for name in REQUIRED_SOURCE_SETS:
        if name not in resource_sets:
            continue
        path = Path(resource_sets[name])
        if not path.is_dir():
            anomalies.append(
                _anomaly(
                    "unavailable_required_resource_set",
                    "required official ANI resource-set directory is unavailable",
                    source_set=name,
                )
            )
        elif not _ani_files(path):
            anomalies.append(
                _anomaly(
                    "empty_required_resource_set",
                    "required official ANI resource-set directory contains no ANI resources",
                    source_set=name,
                )
            )
        else:
            normalized[name] = path

    if anomalies:
        raise CensusError(anomalies)
    return normalized


def _xml_files(root: Path) -> list[Path]:
    return sorted(
        (path for path in root.rglob("*") if path.is_file() and path.suffix.lower() == ".xml"),
        key=lambda path: path.relative_to(root).as_posix(),
    )


def _ani_files(root: Path) -> list[Path]:
    return sorted(
        (path for path in root.rglob("*") if path.is_file() and path.suffix.lower() == ".ani"),
        key=lambda path: path.relative_to(root).as_posix(),
    )
