#!/usr/bin/env python3
"""Mechanical measurement-contract checks for one probe run.

Usage: validate-measurement.py DEBUG_LOG BARREL_ORIENTATION_LOG

Reports probe STATUS/caller, capture continuity/capacity/overflow, native
identities, raw-basis diagnostics, AUTOGEO counts, and AUTOGEO<->native
translation pairing. It does not interpret basis semantics or score geometry.
Exits non-zero when a check fails.

Pairing is order-aware: AUTOGEO samples, in debug.log order, are matched to a
strictly increasing subsequence of native captures. Each sample takes the
earliest capture after the previous match whose translation is within
PAIR_TOLERANCE_M; unmatched native captures (extra reads) are allowed.
Translation is pairing/provenance evidence only.
"""
import json
import math
import re
import sys
from collections import defaultdict

CALLER = "0x7c6eb1"
TARGET = "0x81c960"
# Generous pairing gate; captures of different turrets sit centimetres apart.
PAIR_TOLERANCE_M = 0.001
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

    statuses, captures, overflows = [], [], []
    for line in probe_lines:
        for marker, sink in (("STATUS", statuses), ("CAPTURE", captures),
                             ("OVERFLOW", overflows)):
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
                  overflow=len(overflows))

    identities = defaultdict(int)
    connections = defaultdict(set)
    stream = []  # (identity, translation) in sequence order
    det_range, norm_err, dot_err = [math.inf, -math.inf], 0.0, 0.0
    for c in captures:
        m = c["matrix"]
        if len(m) != 16 or not all(math.isfinite(v) for v in m):
            failures.append(f"sequence {c['sequence']}: non-finite or short matrix")
            continue
        identity = (c["weapon"], c["connection"])
        identities[identity] += 1
        connections[c["weapon"]].add(c["connection"])
        stream.append((identity, m[0:3]))
        x, y, z = m[4:7], m[8:11], m[12:15]
        det = dot(x, (y[1] * z[2] - y[2] * z[1], y[2] * z[0] - y[0] * z[2], y[0] * z[1] - y[1] * z[0]))
        det_range = [min(det_range[0], det), max(det_range[1], det)]
        norm_err = max(norm_err, *(abs(math.sqrt(dot(v, v)) - 1) for v in (x, y, z)))
        dot_err = max(dot_err, abs(dot(x, y)), abs(dot(y, z)), abs(dot(z, x)))
    check(det_range[0] > 0.5, f"degenerate or left-handed basis rows: determinant range {det_range}")
    for weapon, conns in connections.items():
        check(len(conns) == 1, f"native weapon {weapon} changed connection: {sorted(conns)}")
    report.update(identities={f"{w}/{c}": n for (w, c), n in identities.items()},
                  determinant_range=det_range, max_row_norm_error=norm_err,
                  max_row_dot=dot_err)

    samples = [AUTOGEO.search(line) for line in debug_lines]
    samples = [s for s in samples if s]
    check(bool(samples), "no AUTOGEO samples")
    ticks, matched = defaultdict(list), defaultdict(set)
    cursor, worst = 0, 0.0
    for s in samples:
        key = (s[2], s[3])
        ticks[key].append(int(s[1]))
        pos = tuple(map(float, s.groups()[3:6]))
        while cursor < len(stream) and math.dist(pos, stream[cursor][1]) > PAIR_TOLERANCE_M:
            cursor += 1
        if cursor == len(stream):
            failures.append(f"{s[2]} tick {s[1]}: no in-order capture within {PAIR_TOLERANCE_M} m")
            break
        worst = max(worst, math.dist(pos, stream[cursor][1]))
        matched[key].add(stream[cursor][0])
        cursor += 1

    report["autogeo"] = {}
    for (weapon, macro), rows in ticks.items():
        first = min(rows)
        check(sorted(rows) == list(range(first, first + len(rows))),
              f"{weapon} ticks are not contiguous without duplicates")
        check(len(matched[(weapon, macro)]) == 1,
              f"{weapon} pairs with {len(matched[(weapon, macro)])} native identities")
        report["autogeo"][f"{weapon} {macro}"] = {
            "samples": len(rows), "ticks": [first, max(rows)],
            "native": sorted("/".join(i) for i in matched[(weapon, macro)])}
    all_matched = [i for m in matched.values() for i in m]
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
