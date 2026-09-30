#!/usr/bin/env python3
"""Add/remove only this experiment's two entries in the ignored-local host."""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install", "remove"))
    parser.add_argument("--host", type=Path, required=True)
    args = parser.parse_args()
    fragment = json.loads(Path(__file__).with_name("internal-functions.json").read_text())
    path = args.host / "native/version_db/internal_functions.json"
    database = json.loads(path.read_text())
    functions = database.get("functions")
    if not isinstance(functions, dict):
        raise SystemExit(f"invalid X4Native database: {path}")
    for name, expected in fragment.items():
        if functions.get(name) not in (None, expected):
            raise SystemExit(f"refusing to change conflicting {name} entry")
    for name, expected in fragment.items():
        if args.action == "install":
            functions[name] = expected
        else:
            functions.pop(name, None)
    path.write_text(json.dumps(database, indent=2) + "\n")


if __name__ == "__main__":
    main()
