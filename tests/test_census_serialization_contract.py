#!/usr/bin/env python3
"""Issue #78 R1 characterization: the census_turret_assets JSON serialization contract."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from census_turret_assets import CensusError, render_json  # noqa: E402

FIRST = {
    "code": "aa_first",
    "message": "first",
    "source_set": "base",
    "source_file": "a.xml",
    "macro": "m_a",
    "component": "c_a",
}

LAST = {
    "code": "zz_last",
    "message": "last",
    "source_set": "base",
    "source_file": "b.xml",
    "macro": "m_b",
    "component": "c_b",
}

EXPECTED_ERROR_JSON = """{
  "anomalies": [
    {
      "code": "aa_first",
      "component": "c_a",
      "macro": "m_a",
      "message": "first",
      "source_file": "a.xml",
      "source_set": "base"
    },
    {
      "code": "zz_last",
      "component": "c_b",
      "macro": "m_b",
      "message": "last",
      "source_file": "b.xml",
      "source_set": "base"
    }
  ],
  "status": "error"
}"""


class CensusRenderJsonTests(unittest.TestCase):
    def test_keys_sorted_at_all_levels_with_two_space_indent(self) -> None:
        rendered = render_json({"b": 2, "a": [{"y": 1, "x": "v"}]})
        self.assertEqual(
            rendered,
            """{
  "a": [
    {
      "x": "v",
      "y": 1
    }
  ],
  "b": 2
}
""",
        )

    def test_non_ascii_characters_are_escaped(self) -> None:
        rendered = render_json({"k": "héllo ☂"})
        self.assertEqual(
            rendered,
            r"""{
  "k": "h\u00e9llo \u2602"
}
""",
        )
        self.assertTrue(all(ord(char) <= 127 for char in rendered))

    def test_exactly_one_trailing_newline(self) -> None:
        self.assertEqual(render_json({}), "{}\n")
        rendered = render_json({"b": 2, "a": 1})
        self.assertTrue(rendered.endswith("\n"))
        self.assertFalse(rendered.endswith("\n\n"))


class CensusErrorSerializationTests(unittest.TestCase):
    def test_error_string_is_exact_json_without_trailing_newline(self) -> None:
        error = CensusError([LAST, FIRST])
        self.assertEqual(str(error), EXPECTED_ERROR_JSON)
        self.assertFalse(str(error).endswith("\n"))
        self.assertEqual(json.loads(str(error))["status"], "error")

    def test_anomalies_sorted_by_existing_keys_and_codes_are_stable(self) -> None:
        error = CensusError([LAST, FIRST])
        self.assertEqual(error.anomalies, [FIRST, LAST])
        self.assertEqual(error.codes, ("aa_first", "zz_last"))

    def test_missing_ordering_fields_sort_as_empty_strings(self) -> None:
        naked = {"code": "aa_first", "message": "naked"}
        error = CensusError([FIRST, naked])
        self.assertEqual(error.anomalies, [naked, FIRST])
        self.assertEqual(error.codes, ("aa_first", "aa_first"))


if __name__ == "__main__":
    unittest.main()
