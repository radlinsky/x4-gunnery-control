"""Offline diagnosis of Issue 205's holomap projection, X4 9.00 build 611726.

Run: python3 research/issue205/fit_holo_camera.py [--ray-aspect 1.48]
Only the standard library is required. No game/install files are changed.

refine_scans.json preserves Ray's 18 original centroids and the 14 usable M/XL
centroids from the failed 2cd5bab fixture. A centroid is the average of samples
that pick a finite slot region, NOT an exact slot-to-screen engine coordinate.
The report compares hypotheses; fitted parameters are diagnosis, not runtime
calibration. See diagnosis.md for the native source route and missing controls.
"""
import argparse
import json
import math
from pathlib import Path

# Recovered from logged predictions, not fitted to the pick centroids. The
# actual AddHoloMap aspect was not logged. 1.48 in the old analysis was wrong
# for the new scans. Ray's actual aspect is unavailable: same-layout default
# is an explicitly labelled assumption, with --ray-aspect as a sensitivity.
# 610x403 is consistent with both prediction replay and the current UI config;
# dimensions themselves were not logged, so retain that evidence limitation.
SCAN_ASPECT = 610 / 403
PROBE_TANHALF = 0.7716
# Native map constructor stores float(2*atan(.75)); do not fit this constant.
NATIVE_FOV_RADIANS = 1.2870022058486938
NATIVE_TANHALF = math.tan(NATIVE_FOV_RADIANS / 2)
GATE = 0.01
PARAMS = ("tanhalf", "scale", "orbit_x", "orbit_y", "orbit_z",
          "yaw_bias", "pitch_bias", "distance_bias", "distance_power")
PROBE = (PROBE_TANHALF, 1, 0, 0, 0, 0, 0, 0, 1)
NATIVE = (NATIVE_TANHALF, *PROBE[1:])


def load_scans(ray_aspect=SCAN_ASPECT):
    captured = json.loads(Path(__file__).with_name("refine_scans.json").read_text())
    for scan in captured["scans"]:
        scan["aspect"] = ray_aspect if scan["ship"] == "Ray" else SCAN_ASPECT
    return captured


def project(position, state, radius, aspect, params=NATIVE, *,
            orbit_rule="shared", bbox_center=None,
            angles="radians", clamp=False):
    """Zero-roll perspective projection, in mouse coordinates (-1..1, y up).

    radius is a geometric input (size/2 or the diagnostic length/2), not a
    per-ship fitted coefficient. Shared orbit coordinates are radius fractions.
    All captured poses have zero pan/roll; neither is validated by this data.
    """
    t, k, ox, oy, oz, yb, pb, db, power = params
    yaw, pitch, distance = state[3], state[4], state[6]
    if angles == "degrees":
        yaw, pitch = math.radians(yaw), math.radians(pitch)
    elif angles == "yaw_sign":
        yaw = -yaw
    elif angles == "pitch_sign":
        pitch = -pitch
    elif angles == "swap":
        yaw, pitch = pitch, yaw
    yaw, pitch = yaw + yb, pitch + pb
    distance = max(distance, 1) if clamp else distance
    distance = radius * k * (distance ** power + db)
    if orbit_rule == "bbox":
        if bbox_center is None:
            raise ValueError("bounding-box center was not captured")
        orbit = bbox_center
    else:
        orbit = (ox * radius, oy * radius, oz * radius)
    qx, qy, qz = (p - o for p, o in zip(position, orbit))
    sy, cy, sp, cp = math.sin(yaw), math.cos(yaw), math.sin(pitch), math.cos(pitch)
    depth = distance + qx * cp * sy + qy * sp + qz * cp * cy
    if depth <= 0 or t <= 0 or k <= 0:
        raise ValueError("point behind camera or invalid camera parameters")
    return ((qx * cy - qz * sy) / depth / t / aspect,
            (-qx * sp * sy + qy * cp - qz * sp * cy) / depth / t)


def residuals(scans, params, **options):
    result = []
    for scan in scans:
        radius = scan["length"] / 2 if options.get("scale_rule") == "length" else scan["size"] / 2
        for obs in scan["observations"]:
            prediction = project(obs["position"], scan["state"], radius,
                                 scan["aspect"], params,
                                 bbox_center=scan["bbox_center"],
                                 **{k: v for k, v in options.items() if k != "scale_rule"})
            result.extend(p - m for p, m in zip(prediction, obs["mouse"]))
    return result


def statistics(errors):
    return (math.sqrt(sum(v * v for v in errors) / len(errors)),
            max(abs(v) for v in errors[::2]), max(abs(v) for v in errors[1::2]))


def nelder_mead(function, initial, steps, iterations=1800):
    """Small deterministic optimizer for offline hypothesis comparisons."""
    n = len(initial)
    points = [list(initial)] + [
        [v + (steps[j] if i == j else 0) for j, v in enumerate(initial)]
        for i in range(n)]
    values = [function(p) for p in points]
    for _ in range(iterations):
        order = sorted(range(n + 1), key=values.__getitem__)
        points, values = [points[i] for i in order], [values[i] for i in order]
        if max(abs(v - points[0][j]) for p in points[1:] for j, v in enumerate(p)) < 1e-9:
            break
        center = [sum(p[j] for p in points[:-1]) / n for j in range(n)]
        reflected = [2 * c - v for c, v in zip(center, points[-1])]
        fr = function(reflected)
        if fr < values[0]:
            expanded = [c + 2 * (r - c) for c, r in zip(center, reflected)]
            fe = function(expanded)
            points[-1], values[-1] = (expanded, fe) if fe < fr else (reflected, fr)
        elif fr < values[-2]:
            points[-1], values[-1] = reflected, fr
        else:
            outside = fr < values[-1]
            source = reflected if outside else points[-1]
            contracted = [c + .5 * (v - c) for c, v in zip(center, source)]
            fc = function(contracted)
            if fc < (fr if outside else values[-1]):
                points[-1], values[-1] = contracted, fc
            else:
                for i in range(1, n + 1):
                    points[i] = [(a + b) / 2 for a, b in zip(points[0], points[i])]
                    values[i] = function(points[i])
    best = min(range(n + 1), key=values.__getitem__)
    return points[best], values[best]


def fit(scans, free, base=PROBE, **options):
    indices = [PARAMS.index(name) for name in free]

    def expand(x):
        params = list(base)
        for i, value in zip(indices, x):
            params[i] = value
        return params

    def objective(x):
        params = expand(x)
        if not (.2 < params[0] < 2 and .2 < params[1] < 2
                and abs(params[7]) < .2 and .2 < params[8] < 2):
            return 1e6
        try:
            return sum(v * v for v in residuals(scans, params, **options))
        except ValueError:
            return 1e6

    steps = [.02 for _ in indices]
    x, _ = nelder_mead(objective, [base[i] for i in indices], steps)
    return expand(x)


def report(label, scans, params, *, details=True, **options):
    try:
        rms, mx, my = statistics(residuals(scans, params, **options))
    except ValueError as error:
        print(f"{label}: REJECTED ({error})")
        return None
    print(f"{label}: axis RMS={rms:.6f}, max x/y={mx:.6f}/{my:.6f}")
    if details:
        for scan in scans:
            rms, mx, my = statistics(residuals([scan], params, **options))
            gate = "PASS" if max(mx, my) <= GATE else "FAIL"
            print(f"  {scan['pose']:6} n={len(scan['observations']):2} "
                  f"RMS={rms:.6f} max x/y={mx:.6f}/{my:.6f} {gate}")
    return rms, mx, my


def verify_capture(captured):
    scans = captured["scans"]
    assert len(scans) == 6 and sum(len(s["observations"]) for s in scans) == 32
    assert len(captured["excluded"]) == 2
    assert all(s["state"][:3] == [0, 0, 0] and s["state"][5] == 0 for s in scans)
    assert abs(NATIVE_TANHALF - .75) < 1e-7
    # Independent elementary projections: origin is centered, +X is right,
    # +Y is up, and increasing depth produces perspective foreshortening.
    state = [0, 0, 0, 0, 0, 0, 1]
    assert project([0, 0, 0], state, 10, 2) == (0, 0)
    x, y = project([3, 3, 2], state, 10, 2, (.5, *PROBE[1:]))
    assert abs(x - .25) < 1e-12 and abs(y - .5) < 1e-12
    # Replay logged probe predictions as a control, before fitting centroids.
    # Rounding of position/state/prediction accounts for the small tolerance.
    replay_error = 0
    for scan in scans:
        if scan["ship"] == "Ray":
            continue  # Original log/predictions were not preserved for Ray.
        assert scan["logged_state"] == scan["state_after"]
        for obs in scan["observations"]:
            xy = project(obs["position"], scan["state"], scan["size"] / 2,
                         scan["aspect"], PROBE)
            replay_error = max(replay_error, *(abs(a - b) for a, b in zip(xy, obs["predicted"])))
    assert replay_error < .00015, replay_error
    print(f"Capture control: 6 poses, 32 centroids; logged prediction replay max={replay_error:.6f}")
    return replay_error


def distance_uncertainty(scans):
    print("Ray rounded-distance sensitivity (nuisance bounds, NOT calibration):")
    for scan in (s for s in scans if s["ship"] == "Ray"):
        logged = scan["state"][6]

        def objective(x):
            if not logged - .05 <= x[0] <= logged + .05:
                return 1e6
            modified = dict(scan, state=scan["state"][:6] + [x[0]])
            return sum(e * e for e in residuals([modified], NATIVE))

        x, _ = nelder_mead(objective, [logged], [.01], 600)
        modified = dict(scan, state=scan["state"][:6] + [x[0]])
        print(f"  {scan['pose']}: allowed d=[{logged-.05:.2f},{logged+.05:.2f}), "
              f"diagnostic best d={x[0]:.8f}")
        report("  native model at nuisance best", [modified], NATIVE, details=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ray-aspect", type=float, default=SCAN_ASPECT,
                        help="Ray aspect sensitivity; original exact value unavailable")
    args = parser.parse_args()
    captured = load_scans(args.ray_aspect)
    scans = captured["scans"]
    verify_capture(captured)
    print(f"M/XL aspect={SCAN_ASPECT}; Ray assumed aspect={args.ray_aspect}")
    print(f"Native tanhalf={NATIVE_TANHALF:.10f}, vertical FOV={math.degrees(NATIVE_FOV_RADIANS):.6f} deg")
    print("Errors compare to finite pick-region centroids; this is NOT a new live gate.")
    report("Existing probe model, corrected offline inputs", scans, PROBE)
    report("Native-derived FOV, origin, size/2 and linear distance", scans, NATIVE)

    experiments = (
        ("FOV only", ("tanhalf",)),
        ("size scale only", ("scale",)),
        ("FOV + size scale", ("tanhalf", "scale")),
        ("orbit only (shared radius fractions)", ("orbit_x", "orbit_y", "orbit_z")),
        ("FOV + orbit", ("tanhalf", "orbit_x", "orbit_y", "orbit_z")),
        ("angle biases only", ("yaw_bias", "pitch_bias")),
        ("FOV + angle biases", ("tanhalf", "yaw_bias", "pitch_bias")),
        ("FOV + scale + affine distance", ("tanhalf", "scale", "distance_bias")),
        ("FOV + scale + distance power", ("tanhalf", "scale", "distance_power")),
    )
    print("\nJoint hypothesis fits (Ray + M + XL; all coefficients shared):")
    for label, free in experiments:
        params = fit(scans, free)
        report(label, scans, params, details=label == "FOV only")
        print("  " + ", ".join(f"{name}={params[PARAMS.index(name)]:.8f}" for name in free))

    print("\nUnfitted controls:")
    report("Old offline aspect=1.48", [dict(s, aspect=1.48) for s in scans], PROBE, details=False)
    report("Fixed 75-degree FOV", scans, (math.tan(math.radians(37.5)), *PROBE[1:]), details=False)
    report("Native FOV with length/2", scans, NATIVE, details=False, scale_rule="length")
    boxes = [s for s in scans if s["bbox_center"] is not None]
    report("Origin, M/XL subset", boxes, NATIVE, details=False)
    report("Bounding-box-center orbit, M/XL subset", boxes, NATIVE, details=False, orbit_rule="bbox")
    for angle in ("degrees", "yaw_sign", "pitch_sign", "swap"):
        report(f"Angle control {angle}", scans, NATIVE, details=False, angles=angle)
    zoom = [s for s in scans if s["ship"] == "XL" and s["state"][6] < 1]
    report("XL below-limit linear zoom", zoom, NATIVE, details=False)
    report("XL below-limit clamp to 1", zoom, NATIVE, details=False, clamp=True)
    rounded = [dict(s, state=s["state"][:6] + [round(s["state"][6], 1)]) for s in zoom]
    report("XL incorrectly replayed rounded d=0.3", rounded, NATIVE, details=False)
    distance_uncertainty(scans)

    print("\nLeave-one-ship-out FOV fit (checks shared-FOV transfer):")
    for ship in ("Ray", "M", "XL"):
        training = [s for s in scans if s["ship"] != ship]
        held_out = [s for s in scans if s["ship"] == ship]
        params = fit(training, ("tanhalf",))
        print(f"  hold out {ship}: tanhalf={params[0]:.8f}")
        report("  held-out residual", held_out, params, details=False)
    scan = zoom[0]
    anchors = {o["slot"]: project(o["position"], scan["state"], scan["size"] / 2,
                                  scan["aspect"]) for o in scan["observations"]}
    a, b = anchors[16], anchors[17]
    separation = math.hypot((a[0] - b[0]) * 610 / 2, (a[1] - b[1]) * 403 / 2)
    print(f"\nXL zoom slots 16/17: source-model anchor separation ~{separation:.2f} px")
    print("Each Refine window uses 3 px steps over +/-12 px; overlapping windows")
    print("are sampled repeatedly and their hits pooled without source-window labels.")
    print("\nConclusion: correct offline aspect/full zoom distance first; the smallest")
    print("source-derived camera correction is tanhalf=.75. Captured centroids do")
    print("not establish an exact all-pose 0.01 pass. See diagnosis.md for controls.")


if __name__ == "__main__":
    main()
