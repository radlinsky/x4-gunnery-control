"""Emit the accepted #185 turret-local bearing segments from the #176 corpus."""
import gzip
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "research/issue176-a4x"))
from scorer import segments  # noqa: E402


def lua(value):
    if value is None:
        return "nil"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, (int, float)):
        return repr(value)
    return "{" + ",".join(lua(item) for item in value) + "}"


records = json.load(gzip.open(ROOT / ".x4-research-cache/issue176-a4x/corpus.json.gz", "rt"))["records"]
lines = ["-- Generated from the accepted #176/#185 corpus; turret-component-local metres.",
         "X4GunneryTurretBearingGeometry = {"]
seen = {}
for key, record in sorted(records.items()):
    leaf, root, seg = segments(record)
    fields = [f"class = {lua(record['mechanical_class'])}",
              f"leaf = {{axis = {lua(leaf['axis'])}, limits = {lua(leaf['limits'])}}}",
              f"root = {{axis = {lua(root['axis'])}, limits = {lua(root['limits'])}}}"]
    for name in ("L", "G", "H"):
        fields.append(f"{name} = {{t = {lua(seg[name][0])}, R = {lua(seg[name][1])}}}")
    if record["macro"] in seen:
        assert seen[record["macro"]] == fields
        continue
    seen[record["macro"]] = fields
    lines.append(f"    [{lua(record['macro'])}] = {{" + ", ".join(fields) + "},")
lines.append("}")
(ROOT / "ui/turret_bearing_geometry.lua").write_text("\n".join(lines) + "\n")
