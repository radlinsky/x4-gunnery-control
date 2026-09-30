#!/usr/bin/env python3
"""Issue #78 R1 characterization: the census_turret_assets source-set validation contract.

Pins _validate_source_sets() against synthetic tempfile fixtures only: no real X4
data, no resource-set/ANI behavior, no production changes.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    CensusError,
    REQUIRED_SOURCE_SETS,
    _validate_source_sets,
)


def _valid_source_sets(root: Path) -> dict[str, Path]:
    source_sets: dict[str, Path] = {}
    for name in REQUIRED_SOURCE_SETS:
        path = root / name
        path.mkdir(parents=True)
        (path / "source.xml").write_text("<source/>", encoding="utf-8")
        source_sets[name] = path
    return source_sets


class CensusSourceSetContractTests(unittest.TestCase):
    def test_all_required_source_sets_valid_returns_required_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source_sets = _valid_source_sets(Path(tmp))

            normalized = _validate_source_sets(source_sets)

            self.assertEqual(tuple(normalized), tuple(REQUIRED_SOURCE_SETS))
            self.assertEqual(
                normalized,
                {name: path for name, path in source_sets.items()},
            )

    def test_omitted_required_source_set_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source_sets = _valid_source_sets(Path(tmp))
            del source_sets["ego_dlc_mini_02"]

            with self.assertRaises(CensusError) as caught:
                _validate_source_sets(source_sets)

            self.assertIn("missing_required_source_set", caught.exception.codes)

    def test_unexpected_source_set_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source_sets = _valid_source_sets(Path(tmp))
            source_sets["rogue_set"] = Path(tmp) / "rogue_set"

            with self.assertRaises(CensusError) as caught:
                _validate_source_sets(source_sets)

            self.assertIn("unexpected_source_set", caught.exception.codes)

    def test_unavailable_required_source_set_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source_sets = _valid_source_sets(Path(tmp))
            source_sets["base"] = Path(tmp) / "does_not_exist"

            with self.assertRaises(CensusError) as caught:
                _validate_source_sets(source_sets)

            self.assertIn("unavailable_required_source_set", caught.exception.codes)

    def test_empty_required_source_set_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source_sets = _valid_source_sets(Path(tmp))
            empty = Path(tmp) / "empty_base"
            empty.mkdir()
            source_sets["base"] = empty

            with self.assertRaises(CensusError) as caught:
                _validate_source_sets(source_sets)

            self.assertIn("empty_required_source_set", caught.exception.codes)


if __name__ == "__main__":
    unittest.main()
