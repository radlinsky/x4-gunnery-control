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


def capture(seq, weapon, x):
    matrix = [x, 2, 3, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0]
    return ('[info] CAPTURE {"sequence":%d,"weapon":"%s","connection":"c%s","caller_rva":"0x7c6eb1","matrix":%s}'
            % (seq, weapon, weapon, matrix))


def autogeo(tick, weapon, x):
    return (f"[Scripts] *** Context:x: [X4GC TEST AUTOGEO] t=1 tick={tick} weapon={weapon} macro=m{weapon} "
            f"tgt=none mode=holdfire ready=0 aim_yaw=none aim_pitch=none barrel_x={x} barrel_y=2 barrel_z=3")


probe = [STATUS, capture(0, "w1", 1.0), capture(1, "w2", 5.0)]
debug = [autogeo(1, "a", 1.00001), autogeo(1, "b", 5.0)]
report, failures = module.analyze(debug, probe)
assert failures == [], failures
assert report["captures"] == 2 and report["autogeo_samples"] == 2
assert report["summary"] == "missing (non-blocking)"

# Gap, left-handed basis, and an unpaired sample must each fail.
bad = [STATUS, capture(0, "w1", 1.0), capture(2, "w2", 5.0).replace("[5.0, 2, 3, 0, 1", "[5.0, 2, 3, 0, -1")]
_, failures = module.analyze(debug + [autogeo(2, "a", 9.0)], bad)
text = "\n".join(failures)
for expected in ("not contiguous", "left-handed", "from any capture"):
    assert expected in text, (expected, text)
print("ok")
