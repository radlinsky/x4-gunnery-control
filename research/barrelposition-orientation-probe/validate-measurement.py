#!/usr/bin/env python3
"""Mechanical measurement-contract checks for one probe run.

Usage: validate-measurement.py DEBUG_LOG BARREL_ORIENTATION_LOG

Reports probe STATUS/caller, capture continuity/capacity/overflow, native
identities, raw-basis diagnostics, AUTOGEO counts, and AUTOGEO<->native
translation pairing. It does not interpret basis semantics or score geometry.
Exits non-zero when a check fails.
"""
import json
import math
import re
import sys
from collections import defaultdict

CALLER = "0x7c6eb1"
TARGET = "0x81c960"
PAIR_TOLERANCE_M = 0.001  # ponytail: generous pairing gate; tighten if identities ever sit this close
AUTOGEO = re.compile(
    r"\[X4GC TEST AUTOGEO\] .*?tick=(\d+) weapon=(\S+) macro=(\S+) .*?"
    r"barrel_x=(\S+) barrel_y=(\S+) barrel_z=(\S+)")


def payload(line, marker):
    at = line.find(marker + " {")
    return json.loads(line[at + len(marker) + 1:]) if at >= 0 else None


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def analyze(debug_lines, probe_lines):
    failures, report = [], {}

    def check(ok, message):
        if not ok:
            failures.append(message)

    statuses, captures, overflows, summaries = [], [], [], []
    for line in probe_lines:
        for marker, sink in (("STATUS", statuses), ("CAPTURE", captures),
                             ("OVERFLOW", overflows), ("SUMMARY", summaries)):
            item = payload(line, marker)
            if item is not None:
                sink.append(item)

    check(len(statuses) == 1, f"expected one STATUS, found {len(statuses)}")
    status = statuses[0] if statuses else {}
    check(status.get("hooked") is True, f"probe not hooked: {status}")
    check(status.get("target_rva") == TARGET and status.get("caller_rva") == CALLER,
          f"unexpected STATUS RVAs: {status}")
    capacity = status.get("capacity", 0)

    sequences = [c["sequence"] for c in captures]
    check(bool(captures), "no CAPTURE records")
    check(sequences == list(range(len(captures))), "CAPTURE sequences are not contiguous from 0")
    check(len(captures) <= capacity, f"{len(captures)} captures exceed capacity {capacity}")
    check(not overflows, f"OVERFLOW present: {overflows}")
    check(all(c["caller_rva"] == CALLER for c in captures), "capture with unexpected caller")
    report.update(status=status, captures=len(captures), capacity=capacity,
                  overflow=len(overflows),
                  summary=summaries[-1] if summaries else "missing (non-blocking)")

    identities = defaultdict(list)
    det_range, norm_err, dot_err = [math.inf, -math.inf], 0.0, 0.0
    for c in captures:
        m = c["matrix"]
        if len(m) != 16 or not all(math.isfinite(v) for v in m):
            failures.append(f"sequence {c['sequence']}: non-finite or short matrix")
            continue
        identities[(c["weapon"], c["connection"])].append(m[0:3])
        x, y, z = m[4:7], m[8:11], m[12:15]
        det = dot(x, (y[1] * z[2] - y[2] * z[1], y[2] * z[0] - y[0] * z[2], y[0] * z[1] - y[1] * z[0]))
        det_range = [min(det_range[0], det), max(det_range[1], det)]
        norm_err = max(norm_err, *(abs(math.sqrt(dot(v, v)) - 1) for v in (x, y, z)))
        dot_err = max(dot_err, abs(dot(x, y)), abs(dot(y, z)), abs(dot(z, x)))
    check(det_range[0] > 0.5, f"degenerate or left-handed basis rows: determinant range {det_range}")
    report.update(identities={f"{w}/{c}": len(t) for (w, c), t in identities.items()},
                  determinant_range=det_range, max_row_norm_error=norm_err,
                  max_row_dot=dot_err)

    samples = [AUTOGEO.search(line) for line in debug_lines]
    samples = [s for s in samples if s]
    check(bool(samples), "no AUTOGEO samples")
    by_weapon = defaultdict(list)
    for s in samples:
        by_weapon[(s[2], s[3])].append((int(s[1]), tuple(map(float, s.groups()[3:6]))))
    report["autogeo"] = {}
    paired, worst = {}, 0.0
    for (weapon, macro), rows in by_weapon.items():
        ticks = sorted(t for t, _ in rows)
        matched = set()
        for _, pos in rows:
            distance, identity = min(
                (min(math.dist(pos, t) for t in translations), identity)
                for identity, translations in identities.items())
            worst = max(worst, distance)
            check(distance <= PAIR_TOLERANCE_M, f"{weapon} sample {distance:.6f} m from any capture")
            matched.add(identity)
        check(len(matched) == 1, f"{weapon} pairs with {len(matched)} native identities")
        paired[weapon] = matched
        report["autogeo"][f"{weapon} {macro}"] = {
            "samples": len(rows), "ticks": [ticks[0], ticks[-1]],
            "native": sorted("/".join(i) for i in matched)}
    all_matched = [i for m in paired.values() for i in m]
    check(len(all_matched) == len(set(all_matched)), "two AUTOGEO weapons share a native identity")
    report.update(autogeo_samples=len(samples), max_pairing_distance_m=worst)
    return report, failures


def main(argv):
    if len(argv) != 3:
        sys.exit(__doc__)
    with open(argv[1], encoding="utf-8", errors="replace") as debug, \
            open(argv[2], encoding="utf-8", errors="replace") as probe:
        report, failures = analyze(debug, probe)
    print(json.dumps(report, indent=2))
    for failure in failures:
        print("FAIL:", failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
