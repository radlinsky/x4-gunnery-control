#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Black-box tests for the Codex PreToolUse ShellCheck-disable contract adapter.
# All exercises run the adapter as a subprocess with JSON payloads shaped like
# actual Codex PreToolUse input.

adapter=.agents/hooks/codex-shellcheck-disable-contract.sh
settings=.codex/hooks.json
repo_root=$(pwd)
pass=0
fail=0

tmpfiles=()
cleanup() {
  for f in "${tmpfiles[@]}"; do
    rm -f -- "$f"
  done
}
trap cleanup EXIT

mktmp() {
  local t
  t=$(mktemp)
  tmpfiles+=("$t")
  printf '%s\n' "$t"
}

# Helper: emit a JSON payload for apply_patch with the given patch text.
apply_patch_payload() {
  local patch=$1
  python3 -c "
import json, sys
print(json.dumps({'tool_name': 'apply_patch', 'tool_input': {'command': sys.argv[1]}}))
" "$patch"
}

# Helper: emit a JSON payload for an unrelated tool.
unrelated_payload() {
  python3 -c "
import json, sys
print(json.dumps({'tool_name': 'Bash', 'tool_input': {'command': 'echo hello'}}))
"
}

# Helpers — exact exit-code assertions.
assert_ok() {
  local desc=$1 payload=$2
  local status out
  out=$("$adapter" <<< "$payload" 2>&1) && status=0 || status=$?
  if (( status != 0 )); then
    echo "FAIL: $desc (expected exit 0, got exit ${status}; stderr was: ${out:-<empty>})" >&2
    ((fail++)) || true
    return
  fi
  ((pass++)) || true
}

assert_reject() {
  local desc=$1 payload=$2 needle=$3
  local status out
  out=$("$adapter" <<< "$payload" 2>&1) && status=0 || status=$?
  if (( status != 2 )); then
    echo "FAIL: $desc (expected exit 2, got exit ${status}; output was: ${out:-<empty>})" >&2
    ((fail++)) || true
    return
  fi
  if ! grep -Fq "$needle" <<< "$out"; then
    echo "FAIL: $desc (diagnostic missing needle '$needle'; stderr was: ${out:-<empty>})" >&2
    ((fail++)) || true
    return
  fi
  ((pass++)) || true
}

contract_path() { printf '%s' "${repo_root}/tests/test_example_contract.sh"; }
noncontract_path() { printf '%s' "${repo_root}/docs/shellcheck-policy.md"; }

# 1. Safe update to a contract file exits 0.
assert_ok "safe update to contract test" \
  "$(apply_patch_payload $'*** Update File: tests/test_example_contract.sh\n+# grep -Fq \'safe text\' "$md"\n')"

# 2. Contract update adding # shellcheck disable=SC2016 exits exactly 2.
assert_reject "update adds SC2016 disable to contract" \
  "$(apply_patch_payload $'*** Update File: tests/test_example_contract.sh\n+# shellcheck disable=SC2016\n')" \
  "tests/test_example_contract.sh"

# 3. Contract update adding another disable (SC2086) exits exactly 2.
assert_reject "update adds SC2086 disable to contract" \
  "$(apply_patch_payload $'*** Update File: tests/test_example_contract.sh\n+# shellcheck disable=SC2086\n')" \
  "tests/test_example_contract.sh"

# 4. Contract update changing source to disable exits exactly 2.
assert_reject "update changes source to disable in contract" \
  "$(apply_patch_payload $'*** Update File: tests/test_example_contract.sh\n-# shellcheck source=SC2086\n+# shellcheck disable=SC2086\n')" \
  "tests/test_example_contract.sh"

# 5. A disable added to a non-contract path exits 0.
assert_ok "disable on non-contract path allowed" \
  "$(apply_patch_payload $'*** Update File: docs/shellcheck-policy.md\n+# shellcheck disable=SC2016\n')"

# 6. Multi-file patch where one contract file adds a disable exits exactly 2.
assert_reject "multi-file patch with contract disable rejected" \
  "$(apply_patch_payload $'*** Update File: docs/shellcheck-policy.md\n+# some safe text\n\n*** Update File: tests/test_example_contract.sh\n+# shellcheck disable=SC2016\n')" \
  "tests/test_example_contract.sh"

# 7. An unrelated tool_name exits 0.
assert_ok "unrelated tool name allowed" \
  "$(unrelated_payload)"

# 11. Moving a file that carries an existing shellcheck disable into a
# contract path exits exactly 2, even when the patch adds no lines.
move_source="${repo_root}/tests/test_codex_move_source.sh"
printf '%s\n' '# shellcheck disable=SC2086' > "$move_source"
assert_reject "move carries existing disable into contract" \
  "$(apply_patch_payload $'*** Update File: tests/test_codex_move_source.sh\n*** Move to: tests/test_codex_move_probe_contract.sh\n')" \
  "tests/test_codex_move_probe_contract.sh"
rm -f -- "$move_source"

# 8. A top-level JSON array (not an object) exits exactly 2.
assert_reject "top-level JSON array rejected" \
  '[]' \
  "could not safely inspect"

# 9. tool_input as a string (not an object) exits exactly 2.
assert_reject "string tool_input rejected" \
  '{"tool_name":"apply_patch","tool_input":"bad"}' \
  "could not safely inspect"

# --- Missing shared guard regression ---
# When the shared guard script is absent, the adapter must fail closed with
# exit 2 and a "could not safely inspect" diagnostic — never crash with a
# Python traceback (exit 1).
tmpdir=$(mktemp -d)
trap 'rm -rf -- "$tmpdir"' EXIT
mkdir -p "$tmpdir/.agents/hooks"
cp -- "$adapter" "$tmpdir/.agents/hooks/codex-shellcheck-disable-contract.sh"
probe="$tmpdir/tests/test_probe_contract.sh"
mkdir -p "$(dirname "$probe")"
if out=$("$tmpdir/.agents/hooks/codex-shellcheck-disable-contract.sh" \
    <<< "$(apply_patch_payload $'*** Add File: '"$probe"$'\n+# grep -Fq safe text')" 2>&1); then
  status=0
else
  status=$?
fi
if (( status != 2 )); then
  echo "FAIL: missing shared guard (expected exit 2, got ${status}; output was: ${out:-<empty>})" >&2
  ((fail++)) || true
elif ! grep -Fq "could not safely inspect" <<< "$out"; then
  echo "FAIL: missing shared guard diagnostic missing needle 'could not safely inspect'; output was: ${out:-<empty>}" >&2
  ((fail++)) || true
else
  echo "PASS: missing shared guard exits 2" >&2
  ((pass++)) || true
fi

# --- Settings checks ---
settings_pass=0
settings_fail=0

# 8. PreToolUse contains matcher Edit|Write invoking the new Codex adapter.
if python3 - "$settings" "$adapter" <<'PYEOF'
import json, sys
with open(sys.argv[1], "r") as f:
    data = json.load(f)
hooks = data.get("hooks", {})
pre = hooks.get("PreToolUse", [])
found = False
for entry in pre:
    if entry.get("matcher") != "Edit|Write":
        continue
    hook_list = entry.get("hooks", [])
    for h in hook_list:
        cmd = h.get("command", "")
        if sys.argv[2].split("/")[-1] in cmd:
            found = True
if not found:
    sys.exit(1)
PYEOF
then
  ((settings_pass++)) || true
else
  echo "FAIL: settings PreToolUse adapter invocation" >&2
  ((fail++)) || true
fi

# 9. Existing PostToolUse reload-advice configuration matches the expected
#    inline contract — one entry, correct matcher, command path and message.
if python3 - "$settings" <<'PYEOF'
import json, sys
expected = [
    {
        "matcher": "apply_patch|Edit|Write|NotebookEdit",
        "hooks": [
            {
                "type": "command",
                "command": '"$(git rev-parse --show-toplevel)/.agents/hooks/reload-advice.sh"',
                "commandWindows": 'bash -lc \'"$(git rev-parse --show-toplevel)/.agents/hooks/reload-advice.sh"\'',
                "statusMessage": "Checking the required X4 reset",
            }
        ],
    }
]
with open(sys.argv[1], "r") as f:
    data = json.load(f)
hooks = data.get("hooks", {})
post = hooks.get("PostToolUse", [])
if post != expected:
    sys.exit(1)
PYEOF
then
  ((settings_pass++)) || true
else
  echo "FAIL: PostToolUse reload-advice configuration changed" >&2
  ((fail++)) || true
fi

# 10. .codex/hooks.json remains valid JSON.
if python3 -m json.tool "$settings" >/dev/null; then
  ((settings_pass++)) || true
else
  echo "FAIL: settings JSON is not valid" >&2
  ((fail++)) || true
fi

echo "Codex ShellCheck-disable hook checks passed: ${pass} passed, ${fail} failed"
settings_fail=$(( 3 - settings_pass ))
if ((settings_fail < 0)); then settings_fail=0; fi
echo "Settings checks passed: ${settings_pass} passed, ${settings_fail} failed"
if ((fail > 0)); then exit 1; fi
