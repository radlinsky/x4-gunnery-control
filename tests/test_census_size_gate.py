#!/usr/bin/env python3
"""Issue #78 R5 census size gate.

Codifies the already-reviewed census module and test size limits. R1-R4 are
accepted; this gate pins the budget so future growth is reviewed explicitly.

Limits:
  * every scripts/census_*.py:        <= 1000 lines and <= 75 KiB
  * scripts/census_report.py:         <= 1010 lines (approved exception)
                                      and still <= 75 KiB
  * every tests/test_census*.py:      <= 1000 lines and <= 75 KiB
  * tests/support/census_fixture.py:  <= 1000 lines and <= 75 KiB
  * tests/test_census_turret_assets.py: must not exist (R4 monolith)

Paths are repository-relative, derived from __file__ so the gate works from
any working directory.
"""
from __future__ import annotations

import unittest
from pathlib import Path

MAX_LINES = 1000
MAX_LINES_CENSUS_REPORT = 1010  # explicitly approved line-count exception
MAX_BYTES = 75 * 1024  # 75 KiB

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = REPO_ROOT / "scripts"
TESTS_DIR = REPO_ROOT / "tests"
CENSUS_REPORT = "census_report.py"
FIXTURE = TESTS_DIR / "support" / "census_fixture.py"
MONOLITH = TESTS_DIR / "test_census_turret_assets.py"


def repo_relative(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def line_count(path: Path) -> int:
    return len(path.read_text(encoding="utf-8", errors="replace").splitlines())


class CensusSizeGate(unittest.TestCase):
    """Asserts the reviewed R5 size limits for census modules and tests."""

    def assert_within_limits(self, path: Path, max_lines: int) -> None:
        lines = line_count(path)
        size = path.stat().st_size
        name = repo_relative(path)
        self.assertLessEqual(
            lines,
            max_lines,
            f"{name}: {lines} lines exceeds the {max_lines}-line limit",
        )
        self.assertLessEqual(
            size,
            MAX_BYTES,
            f"{name}: {size} bytes exceeds the {MAX_BYTES}-byte (75 KiB) limit",
        )

    def census_modules(self):
        return sorted(SCRIPTS_DIR.glob("census_*.py"))

    def census_tests(self):
        return sorted(TESTS_DIR.glob("test_census*.py"))

    def test_census_module_limits(self) -> None:
        modules = self.census_modules()
        self.assertGreaterEqual(
            len(modules),
            1,
            "no scripts/census_*.py files found; the size gate would be vacuous",
        )
        for path in modules:
            max_lines = (
                MAX_LINES_CENSUS_REPORT
                if path.name == CENSUS_REPORT
                else MAX_LINES
            )
            self.assert_within_limits(path, max_lines)

    def test_census_test_limits(self) -> None:
        tests = self.census_tests()
        self.assertGreaterEqual(
            len(tests),
            1,
            "no tests/test_census*.py files found; the size gate would be vacuous",
        )
        for path in tests:
            self.assert_within_limits(path, MAX_LINES)

    def test_census_fixture_limits(self) -> None:
        self.assertTrue(
            FIXTURE.is_file(),
            f"{repo_relative(FIXTURE)} must exist for the size gate",
        )
        self.assert_within_limits(FIXTURE, MAX_LINES)

    def test_turret_assets_monolith_absent(self) -> None:
        self.assertFalse(
            MONOLITH.exists(),
            f"{repo_relative(MONOLITH)} must not exist (R4 removed the monolith)",
        )


if __name__ == "__main__":
    unittest.main()
