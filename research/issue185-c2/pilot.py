"""Small exact-aim-point pilot for the dedicated CANNOT BEAR benchmark."""
from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "research/issue176-a4x"))

import scorer  # noqa: E402


CASES = (
    {
        "id": "official-ordinary-can-aim",
        "group": "normal supported",
        "turret": "official:turret_arg_l_beam_01_mk1_macro",
        "aim_point": (10.0, 20.0, 100.0),
        "expected": "CAN AIM",
    },
    {
        "id": "swi-ordinary-can-aim",
        "group": "normal supported",
        "turret": "swi:subjugator_ion_weapon_macro",
        "aim_point": (0.0, 100.0, 0.0),
        "expected": "CAN AIM",
    },
    {
        "id": "swi-bounded-cannot-bear",
        "group": "difficult supported",
        "turret": "swi:turret_l_imp_exe_quad_ball_blue_macro",
        "aim_point": (10.0, -20.0, -100.0),
        "expected": "CANNOT BEAR",
    },
    {
        "id": "swi-reversed-can-aim",
        "group": "difficult supported",
        "turret": "swi:turret_m_wall_sith_macro",
        "aim_point": (10.0, 20.0, 100.0),
        "expected": "CAN AIM",
    },
    {
        "id": "swi-rotation-z-unknown",
        "group": "stress-only",
        "turret": "swi:turret_arrestor_dish_macro",
        "aim_point": (0.0, 0.0, 100.0),
        "expected": "UNKNOWN",
    },
)

GROUPS = ("normal supported", "difficult supported", "stress-only")
REQUIRED_SOURCES = {"official", "swi"}
REQUIRED_LAYOUTS = {"ordinary_xy", "bounded_traverse", "reversed_xy", "rotation_z"}
RESULT = {True: "CAN AIM", False: "CANNOT BEAR", None: "UNKNOWN"}


def main() -> None:
    try:
        records = scorer.load()
    except FileNotFoundError as exc:
        raise SystemExit(
            "accepted corpus cache missing; run python3 research/issue176-a4x/corpus.py"
        ) from exc
    rows = []
    for case in CASES:
        try:
            record = records[case["turret"]]
        except KeyError as exc:
            raise SystemExit(f"pilot case {case['id']}: corpus record missing: {exc}") from exc
        truth = scorer.score(record, case["aim_point"])
        result = RESULT[truth["decision"]]
        if result != case["expected"]:
            raise SystemExit(
                f"pilot case {case['id']}: expected {case['expected']}, got {result} ({truth['state']})"
            )
        rows.append((case, record, result, truth["state"]))

    sources = {record["source"] for _, record, _, _ in rows}
    layouts = {record["mechanical_class"] for _, record, _, _ in rows}
    groups = {case["group"] for case, _, _, _ in rows}
    if sources != REQUIRED_SOURCES:
        raise SystemExit(f"pilot source coverage mismatch: {sorted(sources)}")
    if layouts != REQUIRED_LAYOUTS:
        raise SystemExit(f"pilot layout coverage mismatch: {sorted(layouts)}")
    if groups != set(GROUPS):
        raise SystemExit(f"pilot case-group coverage mismatch: {sorted(groups)}")

    for group in GROUPS:
        print(group)
        for case, record, result, state in rows:
            if case["group"] != group:
                continue
            print(
                f"  {case['id']}: {result}"
                f" | source={record['source']} layout={record['mechanical_class']}"
                f" aim_point={case['aim_point']} scorer_state={state}"
            )
    counts = Counter(result for _, _, result, _ in rows)
    print(
        "PASS:"
        f" {len(rows)} exact aim points;"
        f" results={dict(counts)};"
        f" sources={sorted(sources)};"
        f" layouts={sorted(layouts)}"
    )


if __name__ == "__main__":
    main()
