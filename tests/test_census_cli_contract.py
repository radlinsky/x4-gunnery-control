#!/usr/bin/env python3
"""Issue #78 R1 characterization: the census_turret_assets CLI argument contract."""
from __future__ import annotations

import contextlib
import io
import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    REQUIRED_SOURCE_SETS,
    _arguments,
)


class CensusCliContractTests(unittest.TestCase):
    def test_required_source_sets_constant_is_pinned(self) -> None:
        self.assertEqual(
            REQUIRED_SOURCE_SETS,
            (
                "base",
                "ego_dlc_split",
                "ego_dlc_terran",
                "ego_dlc_pirate",
                "ego_dlc_boron",
                "ego_dlc_timelines",
                "ego_dlc_mini_01",
                "ego_dlc_mini_02",
            ),
        )

    def test_repeated_source_and_resource_sets_preserve_order_and_paths(self) -> None:
        args = _arguments(
            [
                "--source-set",
                "base=/data/base",
                "--source-set",
                "ego_dlc_split=/data/dlc_split",
                "--resource-set",
                "base=/res/base",
                "--resource-set",
                "ego_dlc_terran=/res/terran",
            ]
        )
        self.assertEqual(
            args.source_set,
            [("base", Path("/data/base")), ("ego_dlc_split", Path("/data/dlc_split"))],
        )
        self.assertEqual(
            args.resource_set,
            [("base", Path("/res/base")), ("ego_dlc_terran", Path("/res/terran"))],
        )

    def test_list_option_defaults_are_empty(self) -> None:
        args = _arguments([])
        self.assertEqual(args.source_set, [])
        self.assertEqual(args.resource_set, [])

    def test_output_path_and_default(self) -> None:
        args = _arguments(["--output", "/tmp/census.json"])
        self.assertEqual(args.output, Path("/tmp/census.json"))
        self.assertIsNone(_arguments([]).output)

    def test_require_baseline_flag_default_and_set(self) -> None:
        self.assertFalse(
            _arguments([]).require_accepted_turret_active_changing_case_baseline
        )
        self.assertTrue(
            _arguments(
                ["--require-accepted-turret-active-changing-case-baseline"]
            ).require_accepted_turret_active_changing_case_baseline
        )

    def test_cache_and_reconciliation_path_options(self) -> None:
        defaults = _arguments([])
        for attribute in ("old79_components", "platform_sweep", "reconciliation_output"):
            self.assertIsNone(getattr(defaults, attribute), attribute)
        args = _arguments(
            [
                "--old79-components",
                "/tmp/old79-components.json",
                "--platform-sweep",
                "/tmp/platform-sweep.json",
                "--reconciliation-output",
                "/tmp/reconciliation.json",
            ]
        )
        self.assertEqual(args.old79_components, Path("/tmp/old79-components.json"))
        self.assertEqual(args.platform_sweep, Path("/tmp/platform-sweep.json"))
        self.assertEqual(args.reconciliation_output, Path("/tmp/reconciliation.json"))

    def test_malformed_source_and_resource_sets_exit_via_cli(self) -> None:
        malformed = (
            ["--source-set", "missing-equals"],
            ["--source-set", "=missing-name"],
            ["--source-set", "base="],
            ["--resource-set", "missing-equals"],
        )
        for argv in malformed:
            with self.assertRaises(SystemExit) as raised, contextlib.redirect_stderr(
                io.StringIO()
            ):
                _arguments(argv)
            self.assertEqual(raised.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
