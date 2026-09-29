#!/usr/bin/env python3
"""Check this disposable measurement contract, without projecting/scoring points."""
import json
import math
from pathlib import Path
import re
import struct
import sys


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def validate(record):
    assert record["valid"] is True, record.get("reason")
    native = record["native"]
    for ui, field in (("request", "request"), ("holomap", "holomap_id"), ("ship", "ship_id"), ("component", "component_id")):
        assert record[ui] == native[field], f"identity mismatch: {field}"
    assert native["public_type"] == "turret" and record["slot"] == native["public_slot"]
    assert native["capacity"] == 1 and native["icons"] == 1 and native["dropped"] == 0
    assert native["sequence"] > 0 and native["thread"] > 0
    assert native["pass_caller_rva"] == "0xe1669a" and native["icon_caller_rva"] == "0xe1814b"
    assert native["exe_sha256"] == "19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891"
    assert native["build"] == "900-611726" and native["probe_dirty"] is False
    assert re.fullmatch(r"[a-f0-9]{40}", native["probe_sha"])
    for field in ("probe_source_sha256", "lua_source_sha256", "md_source_sha256", "fixture_template_sha256"):
        assert re.fullmatch(r"[a-f0-9]{64}", native[field])
    assert len(native["connection_pair"]) == 2 and native["connection_pair"][1] != "0x0"
    assert native["slot_pivot"] == native["slot_transform"][:3]
    assert record["before"] == record["after"]
    assert record["before"] == [f32(x) for x in native["before"]] == [f32(x) for x in native["after"]]
    assert native["raw_before"] == native["raw_after"] and native["orientation_before"] == native["orientation_after"]
    assert native["raw_distance_before"] == native["raw_distance_after"]
    assert record["widget_before"] == record["widget_after"]
    widget = record["widget_before"]
    left, top, right, bottom = widget["bounds"]
    assert right - left == widget["width"] > 0 and bottom - top == widget["height"] > 0
    creation = record["add_holomap"]
    assert creation["bounds"] == widget["normalized"]
    assert [f32(x) for x in creation["bounds"]] == creation["bounds_float"]
    assert [f32(x) for x in creation["aspect"]] == creation["aspect_float"]
    assert len(creation["aspect"]) == 2 and all(x > 0 for x in creation["aspect"])
    assert record["ship_radius"] > 0
    positions = record["positions"]
    assert positions and len({p["slot"] for p in positions}) == len(positions)
    assert any(p["slot"] == record["slot"] and p["component"] == record["component"] for p in positions)
    assert all(p["radius"] == record["ship_radius"] and len(p["position"]) == 3 for p in positions)
    for field in ("slot_transform", "camera_pose", "descriptor_camera", "view_matrix", "projection", "view_projection", "projection_variant", "variant_view_projection"):
        assert len(native[field]) == 16 and all(math.isfinite(x) for x in native[field]), field
    assert len(native["parameters"]) == 5 and native["radius"][0] > 0


def main():
    seen, sequences, failures = set(), set(), []
    for line_number, line in enumerate(Path(sys.argv[1]).read_text(errors="replace").splitlines(), 1):
        if "ANCHOR_RECORD " not in line:
            continue
        try:
            record = json.loads(line.split("ANCHOR_RECORD ", 1)[1])
            validate(record)
            assert record["request"] not in seen, "duplicate request"
            assert record["native"]["sequence"] not in sequences, "duplicate native sequence"
            seen.add(record["request"])
            sequences.add(record["native"]["sequence"])
        except (AssertionError, KeyError, TypeError, ValueError, OverflowError) as error:
            failures.append(f"line {line_number}: {error}")
    if not seen:
        failures.append("no structurally valid captures")
    print(json.dumps({"captures": len(seen), "failures": failures, "live_verified": False}, indent=2))
    return bool(failures)


if __name__ == "__main__":
    sys.exit(main())
