import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INDEX = ROOT / ".agents/skills/research-x4-modding/references/index.md"


def test_reference_index_omits_issue_task_labels():
    rows = [
        (line_number, line)
        for line_number, line in enumerate(INDEX.read_text(encoding="utf-8").splitlines(), start=1)
        if line.startswith("|") and not line.startswith("|---")
    ]
    task_label = re.compile(r"\bIssue\s+#\d+\b|#\d+\s+[A-Z]\d+\b")
    offenders = [(line_number, line) for line_number, line in rows if task_label.search(line)]

    assert not offenders, "reference index contains GitHub issue/task labels: " + "; ".join(
        f"line {line_number}: {line}" for line_number, line in offenders
    )


if __name__ == "__main__":
    test_reference_index_omits_issue_task_labels()
    print("research index contract checks passed")
