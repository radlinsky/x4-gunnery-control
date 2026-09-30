#!/usr/bin/env python3
"""Install or remove the probe's one ignored-local X4Native RVA entry."""

import argparse
import json
from pathlib import Path


NAME = "BarrelpositionConnectionTransform"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install", "remove"))
    parser.add_argument("--host", type=Path, required=True)
    args = parser.parse_args()

    here = Path(__file__).resolve().parent
    fragment = json.loads((here / "internal-function.json").read_text())
    database_path = args.host / "native/version_db/internal_functions.json"
    database = json.loads(database_path.read_text())
    functions = database.get("functions")
    if not isinstance(functions, dict):
        raise SystemExit(f"invalid X4Native database: {database_path}")

    if args.action == "install":
        expected = fragment[NAME]
        current = functions.get(NAME)
        if current is not None and current != expected:
            raise SystemExit(f"refusing to replace conflicting {NAME} entry")
        functions[NAME] = expected
    else:
        current = functions.get(NAME)
        if current is not None and current != fragment[NAME]:
            raise SystemExit(f"refusing to remove conflicting {NAME} entry")
        functions.pop(NAME, None)

    database_path.write_text(json.dumps(database, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
