#!/usr/bin/env python3
"""Issue #78 R1 characterization: the census_turret_assets main() output contract."""
from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import (  # noqa: E402
    REQUIRED_SOURCE_SETS,
    CensusError,
    main,
    render_json,
)

REPORT = {"status": "ok", "generated": True}


def _argv(*extra: str) -> list[str]:
    argv: list[str] = []
    for name in REQUIRED_SOURCE_SETS:
        argv.extend(["--source-set", f"{name}=/tmp/ss-{name}"])
        argv.extend(["--resource-set", f"{name}=/tmp/rs-{name}"])
    argv.extend(extra)
    return argv


class CensusMainContractTests(unittest.TestCase):
    def test_success_without_output_writes_render_json_to_stdout_and_returns_zero(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with mock.patch(
            "census_turret_assets.build_census", return_value=REPORT
        ) as mock_build:
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = main(_argv())
        self.assertEqual(code, 0)
        self.assertEqual(stdout.getvalue(), render_json(REPORT))
        self.assertEqual(stderr.getvalue(), "")
        mock_build.assert_called_once()

    def test_success_with_output_flag_writes_render_json_to_file_and_returns_zero(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        target = Path(temp.name) / "nested" / "census.json"
        stdout = io.StringIO()
        stderr = io.StringIO()
        with mock.patch(
            "census_turret_assets.build_census", return_value=REPORT
        ) as mock_build:
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = main(_argv("--output", str(target)))
        self.assertEqual(code, 0)
        self.assertEqual(target.read_text(encoding="utf-8"), render_json(REPORT))
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(stderr.getvalue(), "")
        mock_build.assert_called_once()

    def test_build_census_census_error_returns_two_and_writes_stderr(self) -> None:
        error = CensusError(
            [{"code": "test_probe", "message": "deliberate test failure", "source_set": "base"}]
        )
        stdout = io.StringIO()
        stderr = io.StringIO()
        with mock.patch(
            "census_turret_assets.build_census", side_effect=error
        ) as mock_build:
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = main(_argv())
        self.assertEqual(code, 2)
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(stderr.getvalue(), str(error) + "\n")
        mock_build.assert_called_once()


if __name__ == "__main__":
    unittest.main()
