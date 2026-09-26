"""Issue #202 LIVE case: Ray turret 0x3e594 read CLEAR against the LEFT Osaka's XEN M Shield Generator Mk2
(0x1793c7) but never fired. One-turret reconstruction from the owner's Test Lab log (debug log SHA-256
1f69e3d0..., not stored in the repository).

The logged `rel` (target origin in the weapon frame), `aim` (useaimtarget bearing from the weapon origin) and
`barrel` (current muzzle in the weapon frame) fix the scene: the Osaka's pose comes from its origin, the
shield and the graviton turret it fired at (a rigid fit over the Osaka's mirror-symmetric slots).

    python3 research/issue202-line-of-fire/shield_case.py [debug.log]

With the log, it also replays every Ray turret's mark_6 row from its logged muzzle.
"""
from __future__ import annotations

import math
import re
import sys

import numpy as np

import permission as P
import settled as St
import susceptibility as SU
from settled import Sc

S = Sc.S
OSAKA = "ship_ter_l_destroyer_01_a_macro"
SHIELD = "shield_xen_m_standard_02_mk2_macro"      # size 17.4104 m = the logged tgtsize 17.4102
ORIGIN_SHIP = np.array([-84.122, 27.507, 68.473])  # 0x3e594 in the Ray frame
# 0x3e594's logged rows (weapon frame): target origin, useaimtarget bearing (yaw, pitch), muzzle
OSAKA_REL = np.array([-1053.542, 314.82, 3351.524])
GRAVITON = dict(rel=np.array([-969.658, 329.453, 3409.089]), aim=(-0.276565, 0.0963537),
                barrel=np.array([-0.935546, 2.51832, 2.21221]))          # marks 2-3; it fired
SHIELD_LOG = dict(rel=np.array([-734.073, 251.89, 3220.362]), aim=(-0.224133, 0.0756575),
                  barrels={"mark_6": np.array([-0.911906, 2.44372, 2.23247]),
                           "mark_7": np.array([-0.764306, 2.44372, 2.26955])})


def direction(yaw, pitch):
    return np.array([math.cos(pitch) * math.sin(yaw), math.sin(pitch), math.cos(pitch) * math.cos(yaw)])


def fit_osaka():
    """(error, shield slot, turret slot, R) with p_weapon = p_osaka @ R + OSAKA_REL, best rigid fit."""
    comp = S.component(Sc.comp_of(OSAKA))
    slots = {n: (Sc.slot_kind(S.tags(c)), np.asarray(S.conn_world(comp, c)[0]))
             for n, c in S.connections(comp).items() if "component" not in S.tags(c)}
    b = np.array([GRAVITON["rel"] - OSAKA_REL, SHIELD_LOG["rel"] - OSAKA_REL])
    best = None
    for ns, (ks, ts) in slots.items():
        for ng, (kg, tg) in slots.items():
            if ks != "shield" or kg != "turret":
                continue
            a = np.array([tg, ts])
            u, _s, vt = np.linalg.svd(a.T @ b)
            d = np.sign(np.linalg.det(u @ vt))
            R = u @ np.diag([1, 1, d]) @ vt
            if d < 0:
                continue                                                   # a mirror, not a rotation
            err = float(np.abs(a @ R - b).max())
            if best is None or err < best[0]:
                best = (err, ns, ng, R)
    return best


def settled_muzzle(record, ctx, turret, point, start):
    """(state, muzzle in the weapon frame, barrel-to-point angle): the gate's alignment test (0x008176C1)."""
    state, y, x = St.settle(record, ctx["turs"][turret["macro"]], tuple(map(float, point)), start)
    if state != "SETTLED":
        return state, None, None
    world, z = St._muzzles(ctx["evs"][turret["macro"]], record["endpoint"]["tag"], x, y, turret["frame"])[0]
    to = Sc.to_world(np.asarray(point), turret["frame"]) - world
    angle = math.acos(min(1.0, float(z @ to / np.linalg.norm(z) / np.linalg.norm(to))))
    return state, Sc.to_local(world, turret["frame"]), angle


def main():
    ships, ctx = St.context()
    sc = St._ray_scene("shield-case")
    turret = min(sc.turrets, key=lambda t: float(np.linalg.norm(t["origin_ship"] - ORIGIN_SHIP)))
    record = ctx["records"][turret["key"]]
    print(f"turret {turret['mount']} {turret['macro']}: origin off by "
          f"{np.linalg.norm(turret['origin_ship'] - ORIGIN_SHIP):.3f} m")

    err, shield_slot, grav_slot, R = fit_osaka()
    print(f"Osaka fit: shield {shield_slot}, graviton {grav_slot}, max residual {err:.3f} m")
    osaka_pose = Sc.compose(Sc.frame(OSAKA_REL, R), turret["frame"])

    def choose(name, kind, tags):
        return SHIELD if name == shield_slot else Sc.stated_macro(kind, tags, Sc.faction(OSAKA))
    host = St._add_ship(sc, "H", OSAKA, osaka_pose, choose, "H")
    shield = St._element(next(e for e in host if e["conn"] == shield_slot), "ship surface")
    sc.targets, sc.info = [shield], dict(game="vanilla")
    got = Sc.to_local(shield["frame"][0], turret["frame"])
    print(f"shield origin, reconstructed vs logged rel: {np.linalg.norm(got - SHIELD_LOG['rel']):.3f} m apart")

    # 1. the settling model reproduces the muzzle where the turret did fire (graviton)
    pt = direction(*GRAVITON["aim"]) * float(np.linalg.norm(GRAVITON["rel"]))
    for start in St.START_YAWS:
        state, m, a = settled_muzzle(record, ctx, turret, pt, start)
        print(f"graviton, start yaw {start:.2f}: {state}, predicted muzzle {None if m is None else m.round(4)}"
              f", barrel-to-aim {a:.2e} rad, logged {GRAVITON['barrel']}"
              + ("" if m is None else f", off by {np.linalg.norm(m - GRAVITON['barrel']):.4f} m"))
    # 2. where the same turret would rest aimed at the shield's aim point
    aim, source, _i = St.bearing_point(sc, turret, shield)
    pt = Sc.to_local(aim, turret["frame"])
    print(f"shield bearing point ({source}), weapon frame: {pt.round(2)}; logged bearing direction "
          f"{direction(*SHIELD_LOG['aim']).round(5)} vs reconstructed {(pt / np.linalg.norm(pt)).round(5)}")
    for start in St.START_YAWS:
        state, m, a = settled_muzzle(record, ctx, turret, pt, start)
        print(f"shield, start yaw {start:.2f}: {state}, predicted muzzle {None if m is None else m.round(4)}, "
              f"barrel-to-aim {a:.2e} rad")
    for mark, b in SHIELD_LOG["barrels"].items():
        print(f"  logged muzzle at {mark}: {b}")
    # 3. X4's rays and the production MD's decision from the settled muzzle
    for start in St.START_YAWS:
        row = SU.sample_test(sc, turret, shield, ctx, St.MODELS)
        if row["state"] != "SETTLED":
            print("not settled:", row["state"])
            continue
        for m in St.MODELS:
            x4 = row["x4"][m]
            print(f"start {start:.2f} {m}: X4 first hit {x4['first'][:2]} (aim point at {row['reach']:.1f} m), "
                  f"second ray {x4['second'][:2]}; X4 truth {P.truth(row)} ({P.why(row, m)})")
            print(f"   MD probe first hit {row['lines'][m]['aim']}, step {row['lines_prod'][m]['qw']}, "
                  f"extended {row['lines_prod'][m]['ext']}; production {SU.md_status(row, m, 'production')}, "
                  f"with the exact endpoint {SU.md_status(row, m, 'exact endpoint')}")
        break
    # 4. the same rays from the muzzle the log actually recorded
    own = {turret["label"]}
    for mark, b in SHIELD_LOG["barrels"].items():
        o = Sc.to_world(b, turret["frame"])
        for m in St.MODELS:
            first = P._hit(sc, turret, shield, {}, o, e=aim, model=m, skip=own)[:2]
            probe = P._hit(sc, turret, shield, {}, o, e=aim, model=m)[:2]
            print(f"{mark} {m}: from the logged muzzle, X4 first hit {first}, MD probe first hit {probe}")
    # 5. the live probe says rays do not see this shield: the lines again with it removed, from mark_7's muzzle
    o = Sc.to_world(SHIELD_LOG["barrels"]["mark_7"], turret["frame"])
    d, R, bound = float(np.linalg.norm(aim - o)), row["R"], row["bound"]
    lengths = {"X4 first ray (f = 1)": d, "exact endpoint (fef5c7d)": 1.0001 * d + 1.0,
               "box bound (before fef5c7d)": (1 + min(1.1 * R, 500.0) / R) * bound * 1.001 + 1.0}
    for name, length in lengths.items():
        for m in St.MODELS:
            hit = P._hit(sc, turret, shield, {}, o, e=o + (aim - o) * length / d, model=m,
                         skip={turret["label"], shield["label"]})[:2]
            print(f"shield invisible, {name} {length:.1f} m, {m}: first hit {hit}")
    if len(sys.argv) > 1:
        replay(sys.argv[1], sc, shield, aim)


def replay(log, sc, shield, aim):
    """Every Ray turret at mark_6 (logged muzzle): the model's probe and native first ray against the
    logged probe (muzzle_los_self) and production result."""
    rows = [dict(re.findall(r"(\w+)=(\S+)", line)) for line in open(log, errors="replace")
            if "SOLUTION] label=mark_6" in line and "isturret=1" in line]
    results = dict(re.findall(r"(\d+)=([^,\s]+)", next(line for line in open(log, errors="replace")
                                                      if "line_of_fire action=first" in line
                                                      and "target=1545159" in line).split("results=")[1]))
    for r in rows:
        ship = np.array([float(r[f"origin_ship_{k}"]) for k in "xyz"])
        t = min(sc.turrets, key=lambda t: float(np.linalg.norm(t["origin_ship"] - ship)))
        o = Sc.to_world(np.array([float(r[f"barrel_{k}"]) for k in "xyz"]), t["frame"])
        d = float(np.linalg.norm(aim - o))
        far = o + (aim - o) * (1.0001 * d + 1.0) / d
        probe = P._hit(sc, t, shield, {}, o, e=aim)[:2]
        native = P._hit(sc, t, shield, {}, o, e=aim, skip={t["label"]})[:2]
        ext = P._hit(sc, t, shield, {}, o, e=far, skip={t["label"]})[:2]
        blind = P._hit(sc, t, shield, {}, o, e=far, skip={t["label"], shield["label"]})[:2]
        print(f"{r['weapon']} {t['mount']:16s} logged probe {r['muzzle_los_self']} production "
              f"{results[str(int(r['weapon'], 16))]:7s} | model probe {probe}, native first ray {native}, "
              f"exact-endpoint line {ext} (aim point {d:.1f} m); shield invisible: that line {blind}")


if __name__ == "__main__":
    main()
