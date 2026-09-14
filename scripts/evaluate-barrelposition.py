#!/usr/bin/env python3
"""Print the offline `weapon.barrelposition` transform for turret macros as JSON (#166 A9).

Example:
  scripts/evaluate-barrelposition.py \
    --source-root .x4-research-cache/official-source-sets \
    --resource-root .x4-research-cache/issue72-a2-ani-resources \
    --rotation-x 0.3 --rotation-y 0.5 turret_par_l_beam_01_mk1_macro
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from barrelposition_evaluator import EvaluatorError, evaluate, load_turrets
from census_common import REQUIRED_SOURCE_SETS, CensusError, render_json


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-root", required=True, type=Path,
                        help="directory holding one official XML source set per required set name")
    parser.add_argument("--resource-root", required=True, type=Path,
                        help="directory holding one official ANI resource set per required set name")
    parser.add_argument("--rotation-x", type=float, default=0.0, help="rotation_x joint value, radians")
    parser.add_argument("--rotation-y", type=float, default=0.0, help="rotation_y joint value, radians")
    parser.add_argument("macros", nargs="+")
    args = parser.parse_args(argv)
    try:
        turrets = load_turrets(
            {name: args.source_root / name for name in REQUIRED_SOURCE_SETS},
            {name: args.resource_root / name for name in REQUIRED_SOURCE_SETS},
            args.macros,
        )
        results = [evaluate(turrets[m], args.rotation_x, args.rotation_y) for m in args.macros]
    except (EvaluatorError, CensusError) as error:
        print(error, file=sys.stderr)
        return 1
    sys.stdout.write(render_json({"status": "ok", "results": results}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
