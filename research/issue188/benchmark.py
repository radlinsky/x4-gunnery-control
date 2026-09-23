#!/usr/bin/env python3
"""Abstract E7 ENGAGEABLE pipeline benchmark; no upstream physics is modeled."""
from dataclasses import dataclass
from itertools import product
from pathlib import Path

NE = "NOT_EVALUATED"
UNKNOWN = "UNKNOWN"
BLOCKED = "LINE OF FIRE BLOCKED"
CLASSES = ("conventional", "guided missile", "ordinary unguided missile",
           "distributing cluster missile", "unknown turret", "ambiguous turret",
           "missile unknown guidance", "missile ambiguous guidance")


@dataclass(frozen=True)
class Origin:
    result: str
    queries: int = 1


@dataclass(frozen=True)
class Point:
    aim: str
    origins: tuple[Origin, ...] = ()


@dataclass(frozen=True)
class Turret:
    distance: int
    max_range: int
    weapon: str
    points: tuple[Point, ...]


@dataclass(frozen=True)
class Case:
    name: str
    authorized: bool
    turrets: tuple[Turret, ...]


def pair_result(weapon, origin):
    assert 0 <= origin.queries <= 3
    if weapon == "guided missile":
        return "clear", 0
    if weapon in CLASSES[4:]:
        return UNKNOWN, 0
    return origin.result, origin.queries


def ordered_evaluate(case):
    """Return final answers, detailed per-point states, and measured work."""
    work = dict(range_checks=0, search=0, aim_points=0, origins=0, pairs=0, queries=0)
    details = []
    answers = []
    if case.authorized:
        for turret in case.turrets:
            work["range_checks"] += 1
            answers.append(False if turret.distance > turret.max_range else None)
        if any(answer is None for answer in answers):
            work["search"] = 1
    else:
        answers = [False] * len(case.turrets)
    for index, turret in enumerate(case.turrets):
        rows = []
        found = False
        for point in turret.points:
            if answers[index] is False or found:
                rows.append((NE, NE, tuple(NE for _ in point.origins)))
                continue
            work["aim_points"] += 1
            if point.aim != "CAN AIM":
                rows.append((point.aim, NE, tuple(NE for _ in point.origins)))
                continue
            states = []
            clear = False
            unknown = False
            for origin in point.origins:
                if clear:
                    states.append(NE)
                    continue
                result, queries = pair_result(turret.weapon, origin)
                work["origins"] += 1
                work["pairs"] += 1
                work["queries"] += queries
                states.append(result)
                clear |= result == "clear"
                unknown |= result == UNKNOWN
            line = "clear" if clear else UNKNOWN if unknown else BLOCKED
            rows.append((point.aim, line, tuple(states)))
            found |= clear
        details.append(tuple(rows))
        if answers[index] is None:
            answers[index] = found
    return tuple(answers), tuple(details), work


def reference_evaluate(case):
    """Exhaust every logically available upstream result, regardless of success."""
    work = dict(range_checks=0, search=0, aim_points=0, origins=0, pairs=0, queries=0)
    if not case.authorized:
        return ((False,) * len(case.turrets),
                tuple(tuple((NE, NE, tuple(NE for _ in p.origins)) for p in t.points)
                      for t in case.turrets), work)
    work["range_checks"] = len(case.turrets)
    survivors = [t.distance <= t.max_range for t in case.turrets]
    work["search"] = int(any(survivors))
    answers, details = [], []
    for turret, survives in zip(case.turrets, survivors):
        rows = []
        for point in turret.points:
            if not survives:
                rows.append((NE, NE, tuple(NE for _ in point.origins)))
            else:
                work["aim_points"] += 1
                if point.aim != "CAN AIM":
                    rows.append((point.aim, NE, tuple(NE for _ in point.origins)))
                else:
                    outcomes = tuple(pair_result(turret.weapon, origin)
                                     for origin in point.origins)
                    work["origins"] += len(outcomes)
                    work["pairs"] += len(outcomes)
                    work["queries"] += sum(cost for _, cost in outcomes)
                    states = tuple(state for state, _ in outcomes)
                    line = ("clear" if "clear" in states else UNKNOWN if UNKNOWN in states
                            else BLOCKED)
                    rows.append((point.aim, line, states))
        details.append(tuple(rows))
        answers.append(survives and any(aim == "CAN AIM" and line == "clear"
                                        for aim, line, _ in rows))
    return tuple(answers), tuple(details), work


def patterns():
    yield Point("CANNOT BEAR")
    yield Point(UNKNOWN)
    yield Point("CAN AIM")  # invalid upstream output: fail safely
    for length in (1, 2):
        for states in product(("clear", BLOCKED, UNKNOWN), repeat=length):
            yield Point("CAN AIM", tuple(Origin(state) for state in states))


def check(case):
    reference = reference_evaluate(case)
    ordered = ordered_evaluate(case)
    assert reference[0] == ordered[0], case.name
    assert ordered[2]["search"] == int(case.authorized and any(
        t.distance <= t.max_range for t in case.turrets)), case.name
    assert ordered[2]["search"] <= 1
    for ti, turret in enumerate(case.turrets):
        expected = case.authorized and turret.distance <= turret.max_range and any(
            point.aim == "CAN AIM" and any(pair_result(turret.weapon, o)[0] == "clear"
                                          for o in point.origins)
            for point in turret.points)
        assert ordered[0][ti] == expected, case.name
        stopped = not case.authorized or turret.distance > turret.max_range
        for point, (aim, line, origins) in zip(turret.points, ordered[1][ti]):
            if stopped:
                assert aim == line == NE and all(x == NE for x in origins), case.name
                continue
            assert aim == point.aim, case.name
            if aim != "CAN AIM":
                assert line == NE and all(x == NE for x in origins), case.name
                continue
            seen_clear = False
            evaluated = []
            for supplied, actual in zip(point.origins, origins):
                if seen_clear:
                    assert actual == NE, case.name
                else:
                    assert actual == pair_result(turret.weapon, supplied)[0], case.name
                    evaluated.append(actual)
                    seen_clear = actual == "clear"
            assert line == ("clear" if "clear" in evaluated else
                            UNKNOWN if UNKNOWN in evaluated else BLOCKED), case.name
            stopped = line == "clear"
    assert all(ordered[2][key] <= reference[2][key] for key in ordered[2]), case.name
    return reference, ordered


def named_cases():
    b, u, c = Origin(BLOCKED), Origin(UNKNOWN), Origin("clear")
    def t(*points, distance=5, weapon="conventional"):
        return Turret(distance, 10, weapon, points)
    return (
        Case("FIRE NOT AUTHORIZED", False, (t(Point("CAN AIM", (c,))),)),
        Case("all OUT OF RANGE", True, (t(Point("CAN AIM", (c,)), distance=11),)),
        Case("exact range boundary", True, (t(Point("CAN AIM", (c,)), distance=10),)),
        Case("first origin clear", True, (t(Point("CAN AIM", (c, b))),)),
        Case("later origin clear", True, (t(Point("CAN AIM", (b, c))),)),
        Case("all origins blocked", True, (t(Point("CAN AIM", (b, b))),)),
        Case("blocked plus UNKNOWN", True, (t(Point("CAN AIM", (b, u))),)),
        Case("early aim point ENGAGEABLE", True, (t(Point("CAN AIM", (c,)), Point("CAN AIM", (b,))),)),
        Case("failed aim point before success", True, (t(Point(UNKNOWN), Point("CAN AIM", (b, c))),)),
        Case("aim-point consistency trap", True, (t(Point("CAN AIM", (b,)), Point("CANNOT BEAR", (c,))),)),
        Case("CAN AIM without origin", True, (t(Point("CAN AIM")),)),
        Case("guided missile zero queries", True, (t(Point("CAN AIM", (b,)), weapon="guided missile"),)),
        Case("unknown weapon classification", True, (t(Point("CAN AIM", (c,)), weapon="unknown turret"),)),
    )


def generated_cases():
    pats = tuple(patterns())
    for weapon, authorized, in_range, points in product(CLASSES[:4], (False, True),
                                                       (False, True), product(pats, repeat=2)):
        yield Case("generated single", authorized, (Turret(5 if in_range else 11, 10,
                                                           weapon, points),))
    # Four range masks, with both turrets having independently varying results.
    for mask, left, right in product(range(4), pats, pats):
        yield Case("generated two-turret", True, (
            Turret(5 if mask & 1 else 11, 10, "conventional", (left,)),
            Turret(5 if mask & 2 else 11, 10, "conventional", (right,))))
    worst_points = (Point("CAN AIM", (Origin(BLOCKED, 3), Origin(UNKNOWN, 3))),
                    Point("CAN AIM", (Origin(UNKNOWN, 3), Origin(BLOCKED, 3))))
    yield Case("generated worst case", True, (Turret(5, 10, "conventional", worst_points),
                                              Turret(5, 10, "conventional", worst_points)))
    for weapon in CLASSES[:4]:
        for result, queries in product(("clear", BLOCKED, UNKNOWN), range(4)):
            yield Case("generated weapon", True, (Turret(5, 10, weapon,
                       (Point("CAN AIM", (Origin(result, queries),)),)),))
    for weapon in CLASSES[4:]:
        yield Case("generated weapon", True, (Turret(5, 10, weapon,
                   (Point("CAN AIM", (Origin("clear"),)),)),))


def main():
    named = named_cases()
    generated = tuple(generated_cases())
    results = [(case, *check(case)) for case in (*named, *generated)]
    assert len(tuple(patterns())) == 15
    path_inputs = set(product((False, True), (False, True), product(patterns(), repeat=2)))
    for weapon in CLASSES[:4]:
        assert {(case.authorized, case.turrets[0].distance <= case.turrets[0].max_range,
                 case.turrets[0].points) for case in generated
                if case.name == "generated single" and case.turrets[0].weapon == weapon} == path_inputs
    assert {case.turrets[0].weapon for case in generated
            if case.name == "generated weapon" and case.turrets[0].weapon in CLASSES[4:]} == set(CLASSES[4:])
    assert {case.authorized for case in generated} == {False, True}
    assert {t.distance <= t.max_range for case in generated for t in case.turrets} == {False, True}
    assert {t.weapon for case in generated for t in case.turrets} == set(CLASSES)
    assert {p.aim for case in generated for t in case.turrets for p in t.points} == {"CAN AIM", "CANNOT BEAR", UNKNOWN}
    assert {o.result for case in generated for t in case.turrets for p in t.points for o in p.origins} == {"clear", BLOCKED, UNKNOWN}
    assert {o.queries for case in generated for t in case.turrets for p in t.points for o in p.origins} == set(range(4))
    assert any(UNKNOWN in str(ordered[1]) and NE in str(ordered[1]) for _, _, ordered in results)
    assert all(ordered[2]["queries"] == 0 for case, _, ordered in results
               if all(t.weapon == "guided missile" for t in case.turrets))
    keys = ("range_checks", "search", "aim_points", "origins", "pairs", "queries")
    rows = []
    for case, ref, ordered in results[:len(named)]:
        saved = [ref[2][key] - ordered[2][key] for key in keys]
        rows.append(f"| {case.name} | {'yes' if any(ordered[0]) else 'no'} | " + " | ".join(map(str, saved)) + " |")
    worst = {key: max(ordered[2][key] for _, _, ordered in results) for key in keys}
    findings = f"""# Issue #188 E8: ENGAGEABLE pipeline benchmark

`python3 research/issue188/benchmark.py` passed: **{len(generated)} generated cases** and {len(named)} named cases; reference and ordered ENGAGEABLE answers agree throughout.

The full two-aim-point sweep covers both target authorization states, both range states, 15 per-point upstream result patterns (including zero origins), and all clear/blocked/UNKNOWN origin orderings through two origins for each supported weapon class. Four two-turret range masks and abstract normal-path query costs 0–3 are also covered. The four supported classes are conventional, guided missile, ordinary unguided missile, and distributing cluster missile. Unknown or ambiguous turret type and loaded-ammunition guidance remain LINE OF FIRE UNKNOWN. Guided missiles are clear with zero queries. Exact bbox distance equal to max fire range passes; greater distance fails.

UNKNOWN is recorded only for evaluated uncertain checks; deliberately skipped checks and later work remain NOT_EVALUATED. The consistency trap stays not ENGAGEABLE. CAN AIM with zero origins fails safely.

## Named-case work avoided versus full reference

Columns count range checks, shared searches, aim points, firing origins, LINE OF FIRE pairs, and individual queries, respectively.

| Case | ENGAGEABLE | Range | Search | Aim | Origins | Pairs | Queries |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
""" + "\n".join(rows) + "\n\n"
    findings += "Maximum measured ordered work in one two-surviving-turret calculation: " + ", ".join(f"{key}={worst[key]}" for key in keys) + ". The aim-point search is shared and counted once. When no result is decisive early, every remaining aim point and firing origin may need evaluation. These are abstract work counts, not gameplay-average savings.\n"
    Path(__file__).with_name("findings.md").write_text(findings)
    print(f"PASS: {len(generated)} generated + {len(named)} named cases; reference and ordered agree")


if __name__ == "__main__":
    main()
