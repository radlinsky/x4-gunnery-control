#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Black-box tests for the Claude PreToolUse ShellCheck-disable contract adapter.
# All exercises run the adapter as a subprocess with JSON payloads shaped like
# actual Claude PreToolUse input.

adapter=.agents/hooks/claude-shellcheck-disable-contract.sh
settings=.claude/settings.json
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

# Helper: emit JSON for a Write tool input.
write_payload() {
  local fpath=$1 content=$2
  python3 -c "
import json, sys
print(json.dumps({'tool_name': 'Write', 'tool_input': {'file_path': sys.argv[1], 'content': sys.argv[2]}}))
" "$fpath" "$content"
}

# Helper: emit JSON for an Edit tool input.
edit_payload() {
  local fpath=$1 old=$2 new=$3 replace_all=$4
  python3 -c "
import json, sys
print(json.dumps({'tool_name': 'Edit', 'tool_input': {'file_path': sys.argv[1], 'old_string': sys.argv[2], 'new_string': sys.argv[3], 'replace_all': sys.argv[4] == 'true'}}))
" "$fpath" "$old" "$new" "$replace_all"
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
outside_repo_path() { printf '%s' "/tmp/outside-test-contract.sh"; }

# 1. Safe Write to an in-scope contract test is allowed.
assert_ok "safe write to contract test" \
  "$(write_payload "$(contract_path)" $'grep -Fq "event.param3.$anchor" md/x4_gunnery_control.xml')"

# 2. Write introducing # shellcheck disable=SC2016 to a contract test is blocked.
assert_reject "write introduces SC2016 disable in contract" \
  "$(write_payload "$(contract_path)" '# shellcheck disable=SC2016' | python3 -c 'import json,sys; d=json.load(sys.stdin); d["tool_input"]["content"] = d["tool_input"]["content"] + "grep -Fq x\n"; print(json.dumps(d))')" \
  "tests/test_example_contract.sh"

# 3. Write introducing some other disable such as SC2086 is also blocked.
assert_reject "write introduces SC2086 disable in contract" \
  "$(write_payload "$(contract_path)" '# shellcheck disable=SC2086' | python3 -c 'import json,sys; d=json.load(sys.stdin); d["tool_input"]["content"] = d["tool_input"]["content"] + "grep -Fq x\n"; print(json.dumps(d))')" \
  "tests/test_example_contract.sh"

# 4. Write containing ordinary prose mentioning "shellcheck disable" is allowed.
assert_ok "prose mention of shellcheck disable allowed" \
  "$(write_payload "$(contract_path)" 'echo "shellcheck disable=SC2016"' | python3 -c 'import json,sys; d=json.load(sys.stdin); d["tool_input"]["content"] = d["tool_input"]["content"] + "\n"; print(json.dumps(d))')"

# 5. Write to a non-contract path containing a disable is allowed.
assert_ok "write with disable to non-contract path allowed" \
  "$(write_payload "$(noncontract_path)" '# shellcheck disable=SC2016' | python3 -c 'import json,sys; d=json.load(sys.stdin); d["tool_input"]["content"] = d["tool_input"]["content"] + "some text\n"; print(json.dumps(d))')"

# 6. Write outside the repository containing a disable is allowed.
assert_ok "write with disable outside repo allowed" \
  "$(write_payload "$(outside_repo_path)" '# shellcheck disable=SC2016' | python3 -c 'import json,sys; d=json.load(sys.stdin); d["tool_input"]["content"] = d["tool_input"]["content"] + "some text\n"; print(json.dumps(d))')"

# --- Edit tests ---
# For in-repo contract-path edits we create a temp file, copy into the repo,
# run the test, then remove the temp contract file. The cleanup trap also
# removes it so nothing leaks on failure.

# 7. Safe Edit to an in-scope contract test is allowed.
tmpfile=$(mktmp)
printf '%s\n' $'grep -Fq "event.param3.$anchor"' > "$tmpfile"
cp -- "$tmpfile" "${repo_root}/tests/test_example_contract.sh"
assert_ok "safe edit to contract test" \
  "$(edit_payload "$(contract_path)" "param3" "param4" "false")"
rm -f -- "${repo_root}/tests/test_example_contract.sh"

# 8. Edit whose new_string directly introduces a full disable directive is blocked.
tmpfile=$(mktmp)
printf '%s\n' 'normal text here' > "$tmpfile"
cp -- "$tmpfile" "${repo_root}/tests/test_example_contract.sh"
assert_reject "edit directly introduces disable in contract" \
  "$(edit_payload "$(contract_path)" "normal text here" "# shellcheck disable=SC2016" "false")" \
  "tests/test_example_contract.sh"
rm -f -- "${repo_root}/tests/test_example_contract.sh"

# 9. Edit that forms a forbidden directive only after reconstruction is blocked.
#    Regression shape: current file contains "# shellcheck source=SC2086"
#    Edit replaces "source" with "disable", yielding "# shellcheck disable=SC2086".
tmpfile=$(mktmp)
printf '%s\n' '# shellcheck source=SC2086' > "$tmpfile"
cp -- "$tmpfile" "${repo_root}/tests/test_example_contract.sh"
assert_reject "reconstruction-regression source-to-disable blocked" \
  "$(edit_payload "$(contract_path)" "source" "disable" "false")" \
  "tests/test_example_contract.sh"
rm -f -- "${repo_root}/tests/test_example_contract.sh"

# 9b. Edit with replace_all=false and old_string appearing more than once is
#     ambiguous; the hook must not guess which occurrence to replace.
#     Exit 0 lets Claude's own Edit tool reject the ambiguous edit.
tmpfile=$(mktmp)
printf '%s\n' '# shellcheck source=SC2086' '# shellcheck source=SC2016' > "$tmpfile"
cp -- "$tmpfile" "${repo_root}/tests/test_example_contract.sh"
assert_ok "ambiguous edit with multiple occurrences exits 0" \
  "$(edit_payload "$(contract_path)" "source" "disable" "false")"
rm -f -- "${repo_root}/tests/test_example_contract.sh"

# 10. A safe replace_all=true Edit reconstructs correctly and is allowed.
tmpfile=$(mktmp)
printf '%s\n' '# shellcheck source=SC2086' > "$tmpfile"
cp -- "$tmpfile" "${repo_root}/tests/test_example_contract.sh"
assert_ok "safe replace_all edit in contract test" \
  "$(edit_payload "$(contract_path)" "source" "directive" "true")"
rm -f -- "${repo_root}/tests/test_example_contract.sh"

# 11. A replace_all=true Edit that creates a disable is blocked.
# Two lines; replacing source= with disable= on the first line produces a
# line-level disable directive that the guard must reject.
tmpfile=$(mktmp)
printf '%s\n' '# shellcheck source=SC2086' 'some other text' > "$tmpfile"
cp -- "$tmpfile" "${repo_root}/tests/test_example_contract.sh"
assert_reject "replace_all edit creates disable in contract" \
  "$(edit_payload "$(contract_path)" "source=" "disable=" "true")" \
  "tests/test_example_contract.sh"
rm -f -- "${repo_root}/tests/test_example_contract.sh"

# 11b. replace_all as a JSON string (not boolean) is rejected with exit 2.
assert_reject "edit with string replace_all blocked" \
  "$(python3 -c 'import json; print(json.dumps({"tool_name": "Edit", "tool_input": {"file_path": "'"$(contract_path)"'", "old_string": "normal text here", "new_string": "# shellcheck disable=SC2016", "replace_all": "false"}}))')" \
  "could not safely inspect"

# 12. Malformed JSON is blocked with exit 2.
assert_reject "malformed json blocked" \
  'not valid json at all' \
  "could not safely inspect"

# 13. A matched Write payload missing required content is blocked.
assert_reject "write missing content blocked" \
  "$(python3 -c 'import json; print(json.dumps({"tool_name": "Write", "tool_input": {"file_path": "'"$(contract_path)"'"}}))')" \
  "could not safely inspect"

# 14. A matched Edit payload missing required reconstruction fields is blocked.
assert_reject "edit missing old_string blocked" \
  "$(python3 -c 'import json; print(json.dumps({"tool_name": "Edit", "tool_input": {"file_path": "'"$(contract_path)"'", "new_string": "something"}}))')" \
  "could not safely inspect"

# 15. A valid payload with some unrelated tool_name is allowed.
assert_ok "unrelated tool name allowed" \
  "$(python3 -c 'import json; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": "echo hello"}}))')"

# 16. Rejection stderr includes the contract-test path.
assert_reject "rejection includes contract test path" \
  "$(write_payload "$(contract_path)" '# shellcheck disable=SC2016' | python3 -c 'import json,sys; d=json.load(sys.stdin); d["tool_input"]["content"] = d["tool_input"]["content"] + "\n"; print(json.dumps(d))')" \
  "tests/test_example_contract.sh"

# 17. Rejection feedback tells Claude to fix the shell expression rather than
#     suppress the warning.
assert_reject "rejection advises fixing code" \
  "$(write_payload "$(contract_path)" '# shellcheck disable=SC2016' | python3 -c 'import json,sys; d=json.load(sys.stdin); d["tool_input"]["content"] = d["tool_input"]["content"] + "\n"; print(json.dumps(d))')" \
  "Fix the shell expression instead of suppressing the warning"

# 18. A top-level JSON array (not an object) is rejected with exit 2.
assert_reject "top-level json array blocked" \
  '[]' \
  "could not safely inspect"

# 19. A matched Write payload whose tool_input is a string is rejected with exit 2.
assert_reject "write with string tool_input blocked" \
  "$(python3 -c 'import json; print(json.dumps({"tool_name": "Write", "tool_input": "bad"}))')" \
  "could not safely inspect"

# --- Subdirectory invocation regression ---
# A Write with a disable invoked from a repository subdirectory must exit 2.
tmpfile=$(mktmp)
printf '%s\n' 'grep -Fq x' > "$tmpfile"
cp -- "$tmpfile" "${repo_root}/tests/test_example_contract.sh"
pushd "${repo_root}/tests" >/dev/null
if out=$("${repo_root}/.agents/hooks/claude-shellcheck-disable-contract.sh" <<< "$(write_payload "$(contract_path)" '# shellcheck disable=SC2086')" 2>&1); then
  status=0
else
  status=$?
fi
popd >/dev/null
if (( status != 2 )); then
  echo "FAIL: subdirectory write blocked (expected exit 2, got ${status})" >&2
  ((fail++)) || true
elif ! grep -Fq "tests/test_example_contract.sh" <<< "$out"; then
  echo "FAIL: subdirectory write blocked diagnostic missing path" >&2
  ((fail++)) || true
else
  echo "PASS: subdirectory write blocked" >&2
  ((pass++)) || true
fi
rm -f -- "${repo_root}/tests/test_example_contract.sh"

# --- Missing shared guard regression ---
# When the shared guard script is absent, the adapter must fail closed with
# exit 2 and a "could not safely inspect" diagnostic — never crash with a
# Python traceback (exit 1).
tmpdir=$(mktemp -d)
trap 'rm -rf -- "$tmpdir"' EXIT
mkdir -p "$tmpdir/.agents/hooks" "$tmpdir/tests"
cp -- "$adapter" "$tmpdir/.agents/hooks/claude-shellcheck-disable-contract.sh"
probe="$tmpdir/tests/test_probe_contract.sh"
if out=$("$tmpdir/.agents/hooks/claude-shellcheck-disable-contract.sh" \
    <<< "$(write_payload "$probe" 'grep -Fq x')" 2>&1); then
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

# --- Settings tests ---
settings_pass=0
settings_fail=0

# 18. PreToolUse contains an Edit|Write matcher invoking the adapter with args [].
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
        args = h.get("args", None)
        if sys.argv[2].split("/")[-1] in cmd and isinstance(args, list) and len(args) == 0:
            found = True
if not found:
    sys.exit(1)
PYEOF
then
  ((settings_pass++)) || true
else
  echo "FAIL: settings PreToolUse adapter with args=[]" >&2
  ((fail++)) || true
fi

# 19. The existing PostToolUse Edit|Write|NotebookEdit reload-advice hook remains present.
if python3 -c '
import json, sys
with open("'"$settings"'", "r") as f:
    data = json.load(f)
hooks = data.get("hooks", {})
post = hooks.get("PostToolUse", [])
found = False
for entry in post:
    if entry.get("matcher") == "Edit|Write|NotebookEdit":
        hook_list = entry.get("hooks", [])
        for h in hook_list:
            cmd = h.get("command", "")
            if "reload-advice.sh" in cmd:
                found = True
if not found:
    sys.exit(1)
'; then
  ((settings_pass++)) || true
else
  echo "FAIL: settings PostToolUse reload-advice hook missing" >&2
  ((fail++)) || true
fi

# 20. The settings JSON is valid.
if python3 -m json.tool "$settings" >/dev/null; then
  ((settings_pass++)) || true
else
  echo "FAIL: settings JSON is not valid" >&2
  ((fail++)) || true
fi

echo "Claude ShellCheck-disable hook checks passed: ${pass} passed, ${fail} failed"
settings_fail=$(( 3 - settings_pass ))
if ((settings_fail < 0)); then settings_fail=0; fi
echo "Settings checks passed: ${settings_pass} passed, ${settings_fail} failed"
if ((fail > 0)); then exit 1; fi
