#!/usr/bin/env python3
"""Regression coverage for the Issue #125 one-key rotator evidence boundary."""
from __future__ import annotations

import unittest

from test_census_source_semantics import SourceSemanticTests, _geometry
from census_source_semantics import _resolve_supported_endpoint_source_semantics


class OneKeyRotatorGuardTests(unittest.TestCase):
    def test_arbitrary_repeated_rotator_value_fails_closed(self) -> None:
        helper = SourceSemanticTests(
            methodName="test_depth4_one_key_barrel_translation_is_recognized"
        )
        result = _resolve_supported_endpoint_source_semantics(
            helper._one_key_barrel_endpoint(
                helper._PLASMA_02_BARREL,
                rotator=(0.0, 3.0, 0.0),
            ),
            _geometry(4, one_key_barrel_restrictions=True),
            component_endpoint_count=2,
        )

        self.assertEqual(result["classification"], "UNSUPPORTED")


if __name__ == "__main__":
    unittest.main()
