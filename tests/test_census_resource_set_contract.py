#!/usr/bin/env python3
"""Issue #78 R1 characterization: the census_turret_assets resource-set validation contract.

Pins _validate_resource_sets() against synthetic tempfile fixtures only: no real
X4 data, no production changes. ANI fixtures are opaque stubs; file contents are
never parsed by this test.
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
    _validate_resource_sets,
)


def _valid_resource_sets(root: Path) -> dict[str, Path]:
    resource_sets: dict[str, Path] = {}
    for name in REQUIRED_SOURCE_SETS:
        path = root / name
        path.mkdir(parents=True)
        (path / "stub.ani").write_bytes(b"stub\n")
        resource_sets[name] = path
    return resource_sets


class CensusResourceSetContractTests(unittest.TestCase):
    def test_all_required_resource_sets_valid_returns_required_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            resource_sets = _valid_resource_sets(Path(tmp))

            normalized = _validate_resource_sets(resource_sets)

            self.assertEqual(tuple(normalized), tuple(REQUIRED_SOURCE_SETS))
            self.assertEqual(
                normalized,
                {name: path for name, path in resource_sets.items()},
            )

    def test_omitted_required_resource_set_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            resource_sets = _valid_resource_sets(Path(tmp))
            del resource_sets["ego_dlc_mini_02"]

            with self.assertRaises(CensusError) as caught:
                _validate_resource_sets(resource_sets)

            self.assertIn("missing_required_resource_set", caught.exception.codes)

    def test_unexpected_resource_set_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            resource_sets = _valid_resource_sets(Path(tmp))
            resource_sets["rogue_set"] = Path(tmp) / "rogue_set"

            with self.assertRaises(CensusError) as caught:
                _validate_resource_sets(resource_sets)

            self.assertIn("unexpected_resource_set", caught.exception.codes)

    def test_unavailable_required_resource_set_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            resource_sets = _valid_resource_sets(Path(tmp))
            resource_sets["base"] = Path(tmp) / "does_not_exist"

            with self.assertRaises(CensusError) as caught:
                _validate_resource_sets(resource_sets)

            self.assertIn("unavailable_required_resource_set", caught.exception.codes)

    def test_empty_required_resource_set_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            resource_sets = _valid_resource_sets(Path(tmp))
            empty = Path(tmp) / "empty_base"
            empty.mkdir()
            resource_sets["base"] = empty

            with self.assertRaises(CensusError) as caught:
                _validate_resource_sets(resource_sets)

            self.assertIn("empty_required_resource_set", caught.exception.codes)


if __name__ == "__main__":
    unittest.main()
