#!/usr/bin/env python3
"""Validate durable X4 evidence records without reading proprietary sources."""

from __future__ import annotations

import pathlib
import re
import sys


STATUSES = {
    "documented-public",
    "shipped-source",
    "third-party-technique",
    "inference",
    "live-tested",
}
REQUIRED = ("X4", "Status", "Source", "Live test")


def records(path: pathlib.Path):
    heading = None
    lines: list[tuple[int, str]] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        match = re.match(r"^#{3,4} (.+)$", line)
        if match:
            if heading is not None:
                yield heading, lines
            heading = (number, match.group(1))
            lines = []
        elif heading is not None:
            lines.append((number, line))
    if heading is not None:
        yield heading, lines


def main() -> int:
    # Default to the skill directory this script lives in, not the caller's cwd.
    # A "." default made the glob match nothing from the repo root, so the check
    # reported success having validated zero records.
    root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent
    errors: list[str] = []
    checked = 0
    for path in sorted((root / "references").glob("*.md")):
        for (heading_line, heading), body in records(path):
            fields: dict[str, tuple[int, str]] = {}
            for number, line in body:
                match = re.match(r"^- ([A-Za-z][A-Za-z0-9 ]*):\s*(.*)$", line)
                if match:
                    fields[match.group(1)] = (number, match.group(2))
            if "Status" not in fields:
                continue
            checked += 1
            for field in REQUIRED:
                if field not in fields:
                    errors.append(f"{path}:{heading_line}: {heading!r} lacks '- {field}:'")
            status_line, status = fields["Status"]
            if status not in STATUSES:
                errors.append(
                    f"{path}:{status_line}: noncanonical Status {status!r}; "
                    f"expected exactly one of {sorted(STATUSES)}"
                )
            if not any(line.startswith("- Finding") for _, line in body):
                errors.append(f"{path}:{heading_line}: {heading!r} lacks a Finding field")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    # A validator that validated nothing must not report success: an empty run
    # means the root is wrong, not that the knowledge base is clean.
    if not checked:
        print(f"no evidence records found under {root / 'references'}", file=sys.stderr)
        return 1
    print(f"X4 KB checks passed ({checked} records)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
