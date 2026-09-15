"""Target-only stable-resting-point gate for X4 turret yaw (#166 A11).

Classifies the decoded yaw target map F(y) for one turret and one target as
having exactly one, several, or no stable resting yaw, from source-derived
geometry alone. Row-vector convention as in barrelposition_evaluator.

Decoded map (X4 9.00 build 611726; see the research reference
turret-yaw-resting-point-gate.md):
  pivot(y) = (t_G·Ry(y))·R_H + t_H           pitch-joint origin, component frame
  d        = normalize(target - pivot(y))    component frame
  d_i      = 0 where |d_i| < 1e-3f, then renormalized
  dH       = d·R_Hᵀ                          pre-yaw-joint frame
  F(y)     = 0 if |dH_x| < 1e-4f and |dH_z| < 1e-4f, else atan2(dH_x, dH_z) - β
  g(y)     = F(y) - y wrapped into [-π, π)   the mover's unwrap; the corpus yaw is unlimited

The mover moves yaw toward the sign of g. An attractor is a point where g changes
from positive to negative. Close to its target the mover either snaps to it
(inside 1e-4f) or lands exactly on it (its sqrt-profile step exceeds the
remaining distance whenever that distance is below ~1.62·accel·dt²), so near an
attractor the engine iterates y <- F(y) frame by frame for every speed,
acceleration and frame time. An attractor is therefore a resting point when g
vanishes on both sides to within the 1e-4f snap distance and |F'| < 1 on both
sides. Otherwise the turret is drawn to it but never settles: it holds the target
directly astern, or oscillates when F' <= -1. Those are counted as traps.

Between any two consecutive "events" the zeroing mask and the zenith flag are
fixed, so sign(g) equals the sign of a trig polynomial of degree <= 2 in y.
Every mask/zenith boundary and every zero of those polynomials is a root of
such a polynomial, so all events are found exactly as roots of quartics in
z = e^{iy}. The circle is split at those roots and sign(g) is evaluated once
per arc. No angle scan is involved.
"""
from __future__ import annotations

import cmath
import math
import struct

from barrelposition_evaluator import EvaluatorError, joint_segments, mat_mul, vec_mul

_f32 = lambda v: struct.unpack("<f", struct.pack("<f", v))[0]  # noqa: E731
ZEROING = _f32(1e-3)  # component zeroing, caller 0x140e22425..0x140e22460
ZENITH = _f32(1e-4)   # yaw projection degenerate, solver 0x140e219cc..0x140e219f1
SNAP = _f32(1e-4)     # mover snaps to its target inside this distance, 0x140e1f944
# ponytail: engine yaw is float32 (~6e-8 rad resolution near π); candidate
# events closer than this are one event, and roots off the unit circle by less
# than this still count (extra partition points cannot change a sign count).
_ANGLE_EPS = 1e-9


def yaw_geometry(turret: dict[str, object]) -> dict[str, object]:
    """Fixed yaw-dynamics geometry from the A9 path split."""
    for connection in turret["connections"].values():
        for restriction in connection["authored_restrictions"]:
            if restriction["type_token"] != "rotation_y":
                continue
            limits = [b["candidate_numeric_value"] for b in (restriction["authored_min"], restriction["authored_max"]) if b]
            # the solver and mover ignore limits whose radian values are both below 1e-4
            if any(abs(math.radians(v)) >= 1e-4 for v in limits):
                raise EvaluatorError("authored yaw limits are outside the supported unlimited-yaw boundary")
    seg = joint_segments(turret)
    aim = vec_mul(seg["L"][1][2], seg["G"][1])  # rest-pitch +Z aim axis in the yaw frame
    if math.hypot(aim[0], aim[2]) < ZENITH:
        raise EvaluatorError("aim axis has no yaw projection")
    return {"t_G": seg["G"][0], "t_H": seg["H"][0], "R_H": seg["H"][1], "beta": math.atan2(aim[0], aim[2])}


# --- degree-1/2 trig polynomials: (a0, cos y, sin y[, cos 2y, sin 2y]) ------------

def _mul(p, q):
    return (p[0] * q[0] + (p[1] * q[1] + p[2] * q[2]) / 2, p[0] * q[1] + p[1] * q[0],
            p[0] * q[2] + p[2] * q[0], (p[1] * q[1] - p[2] * q[2]) / 2, (p[1] * q[2] + p[2] * q[1]) / 2)


def _add(*ps):
    return tuple(sum(c) for c in zip(*ps))


def _scale(p, k):
    return tuple(c * k for c in p)


def _poly_roots(coeffs: list[complex]) -> list[complex]:
    """Aberth iteration; coeffs highest power first."""
    big = max(abs(c) for c in coeffs)
    if big == 0:
        return []
    while abs(coeffs[0]) <= 1e-14 * big:   # roots at infinity/zero are off the unit circle
        coeffs = coeffs[1:]
    while abs(coeffs[-1]) <= 1e-14 * big:
        coeffs = coeffs[:-1]
    n = len(coeffs) - 1
    if n < 1:
        return []
    coeffs = [c / coeffs[0] for c in coeffs]
    roots = [cmath.rect(1.0, 0.4 + 2.1 * k) for k in range(n)]
    for _ in range(500):
        worst = 0.0
        for i, r in enumerate(roots):
            p = dp = 0j
            for c in coeffs:
                dp = dp * r + p
                p = p * r + c
            if p == 0:
                continue
            ratio = p / dp if dp else p
            s = sum(1 / (r - o) for j, o in enumerate(roots) if j != i and r != o)
            step = ratio / (1 - ratio * s)
            roots[i] = r - step
            worst = max(worst, abs(step))
        if worst < 1e-15:
            break
    return roots


def _trig_roots(p) -> list[float]:
    a0, a1, b1, a2, b2 = p
    out = []
    for z in _poly_roots([(a2 - 1j * b2) / 2, (a1 - 1j * b1) / 2, a0, (a1 + 1j * b1) / 2, (a2 + 1j * b2) / 2]):
        if abs(abs(z) - 1.0) < 1e-6:
            out.append(cmath.phase(z))
    return out


def classify(geometry: dict[str, object], target: tuple[float, float, float]) -> dict[str, object]:
    """Return {"class": "one"|"several"|"none", "resting": [yaw...], "traps": [yaw...]}."""
    gx, gy, gz = geometry["t_G"]
    rh = geometry["R_H"]
    rht = tuple(zip(*rh))
    beta = geometry["beta"]
    q = tuple(t - h for t, h in zip(target, geometry["t_H"]))
    # e(y) = q - (t_G·Ry(y))·R_H = E0 + EC cos y + ES sin y
    e0 = vec_mul((0.0, gy, 0.0), rh)
    ec = vec_mul((gx, 0.0, gz), rh)
    es = vec_mul((gz, 0.0, -gx), rh)
    e = [(q[i] - e0[i], -ec[i], -es[i]) for i in range(3)]
    sq = [_mul(c, c) for c in e]
    norm2 = _add(*sq)
    cos_a, sin_a = (0.0, math.cos(beta), -math.sin(beta)), (0.0, math.sin(beta), math.cos(beta))

    events = [0.0, -math.pi]  # zenith map F = 0: g = wrap(-y) changes sign only here
    for i in range(3):
        events += _trig_roots(_add(sq[i], _scale(norm2, -ZEROING * ZEROING)))
    for mask in range(8):
        z = [(0.0, 0.0, 0.0) if mask >> i & 1 else e[i] for i in range(3)]
        w = [_add(*(_scale(z[i], rht[i][j]) for i in range(3))) for j in (0, 2)]
        zn2 = _add(*(sq[i] for i in range(3) if not mask >> i & 1)) if mask != 7 else (0.0,) * 5
        events += _trig_roots(_add(_mul(w[0], cos_a), _scale(_mul(w[1], sin_a), -1)))
        for wj in w:
            events += _trig_roots(_add(_mul(wj, wj), _scale(zn2, -ZENITH * ZENITH)))

    def state(y):
        c, s = math.cos(y), math.sin(y)
        d = [k0 + kc * c + ks * s for k0, kc, ks in e]
        n = math.sqrt(sum(v * v for v in d))
        return tuple(abs(v) < ZEROING * n for v in d), d

    def g_sign(y, mask, d):
        z = [0.0 if m else v for m, v in zip(mask, d)]
        dh = vec_mul(z, rht)
        n = math.sqrt(sum(v * v for v in z))
        if abs(dh[0]) < ZENITH * n and abs(dh[2]) < ZENITH * n:
            return True, -math.sin(y), 0.0
        a = y + beta
        f = math.atan2(dh[0], dh[2]) - beta
        return False, dh[0] * math.cos(a) - dh[2] * math.sin(a), f

    def g_and_slope(y, mask, zenith):
        """One-sided g and F' with the arc's mask/zenith state held fixed."""
        if zenith:
            return (-y + math.pi) % (2 * math.pi) - math.pi, 0.0
        c, s = math.cos(y), math.sin(y)
        z = [0.0 if m else k0 + kc * c + ks * s for m, (k0, kc, ks) in zip(mask, e)]
        dz = [0.0 if m else ks * c - kc * s for m, (k0, kc, ks) in zip(mask, e)]
        dh, ddh = vec_mul(z, rht), vec_mul(dz, rht)
        f = math.atan2(dh[0], dh[2]) - beta
        slope = (dh[2] * ddh[0] - dh[0] * ddh[2]) / (dh[0] * dh[0] + dh[2] * dh[2])
        return (f - y + math.pi) % (2 * math.pi) - math.pi, slope

    points = sorted((y + math.pi) % (2 * math.pi) - math.pi for y in events)
    merged = [points[0]]
    for y in points[1:]:
        if y - merged[-1] > _ANGLE_EPS:
            merged.append(y)
    if len(merged) > 1 and merged[0] + 2 * math.pi - merged[-1] <= _ANGLE_EPS:
        merged.pop()
    arcs = []  # (mask, zenith, sign) of the arc starting at merged[k]
    for k, y0 in enumerate(merged):
        y1 = merged[k + 1] if k + 1 < len(merged) else merged[0] + 2 * math.pi
        mid = (y0 + y1) / 2
        mask, d = state(mid)
        zenith, h, _ = g_sign(mid, mask, d)
        arcs.append((mask, zenith, (h > 0) - (h < 0)))
    resting, traps = [], []
    for k, y in enumerate(merged):
        left, right = arcs[k - 1], arcs[k]
        if left[2] > 0 and right[2] < 0:
            sides = (g_and_slope(y, left[0], left[1]), g_and_slope(y, right[0], right[1]))
            settles = all(abs(g) < SNAP and abs(slope) < 1.0 for g, slope in sides)
            (resting if settles else traps).append(y)
    return {"class": "one" if len(resting) == 1 else "several" if resting else "none",
            "resting": resting, "traps": traps}
