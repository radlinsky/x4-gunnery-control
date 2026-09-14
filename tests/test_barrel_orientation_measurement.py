#!/usr/bin/env python3
"""Synthetic contract check for the probe measurement validator."""
import importlib.util
import pathlib

path = pathlib.Path(__file__).resolve().parents[1] / "research/barrelposition-orientation-probe/validate-measurement.py"
spec = importlib.util.spec_from_file_location("validate_measurement", path)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

STATUS = '[info] STATUS {"hooked":true,"target_rva":"0x81c960","caller_rva":"0x7c6eb1","capacity":32768}'


def capture(seq, weapon, x, sign=1):
    matrix = [x, 2, 3, 0, sign, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0]
    return ('[info] CAPTURE {"sequence":%d,"weapon":"%s","connection":"c%s","caller_rva":"0x7c6eb1","matrix":%s}'
            % (seq, weapon, weapon, matrix))


def autogeo(tick, weapon, x):
    return (f"[Scripts] *** Context:x: [X4GC TEST AUTOGEO] t=1 tick={tick} weapon={weapon} macro=m{weapon} "
            f"tgt=none mode=holdfire ready=0 aim_yaw=none aim_pitch=none barrel_x={x} barrel_y=2 barrel_z=3")


probe = [STATUS, capture(0, "w1", 1.0), capture(1, "w9", 7.0), capture(2, "w2", 5.0)]
debug = [autogeo(1, "a", 1.00001), autogeo(1, "b", 5.0)]
report, failures = module.analyze(debug, probe)
assert failures == [], failures
assert report["captures"] == 3 and report["autogeo_samples"] == 2
assert report["summary"] == "missing (non-blocking)"

# Order regression: each sample sits exactly on the *other* turret's position
# at a later (wrong) time, and 2e-5 m from its own in-order capture. Global
# nearest matching swaps a<->w2, b<->w1 consistently and passed; order must not.
probe = [STATUS] + [capture(i, w, x) for i, (w, x) in enumerate([
    ("w1", 1.0), ("w2", 5.0), ("w1", 2.0), ("w2", 6.0),
    ("w1", 5.00002), ("w1", 6.00002), ("w2", 1.00002), ("w2", 2.00002)])]
debug = [autogeo(1, "a", 1.00002), autogeo(1, "b", 5.00002),
         autogeo(2, "a", 2.00002), autogeo(2, "b", 6.00002)]
report, failures = module.analyze(debug, probe)
assert failures == [], failures
assert report["autogeo"]["a ma"]["native"] == ["w1/cw1"], report
assert report["autogeo"]["b mb"]["native"] == ["w2/cw2"], report

# Each must fail: gap, left-handed basis, SUMMARY drops, weapon changing
# connection, duplicate tick, and a sample with no in-order capture.
bad = [STATUS, capture(0, "w1", 1.0), capture(2, "w2", 5.0, sign=-1),
       capture(3, "w2", 5.0).replace('"cw2"', '"cother"'),
       '[info] SUMMARY {"captured":4,"dropped":1,"null_rejected":0}']
debug = [autogeo(1, "a", 1.0), autogeo(1, "a", 1.0), autogeo(2, "b", 9.0)]
_, failures = module.analyze(debug, bad)
text = "\n".join(failures)
for expected in ("not contiguous from 0", "left-handed", "reports drops", "changed connection",
                 "without duplicates", "no in-order capture"):
    assert expected in text, (expected, text)
print("ok")
