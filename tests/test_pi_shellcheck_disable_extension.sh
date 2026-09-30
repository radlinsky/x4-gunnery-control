#!/usr/bin/env bash
set -euo pipefail

# Black-box tests for the Pi shellcheck-disable-contract extension.
# All exercises run the ACTUAL extension module as an .mjs against a fake repo,
# with mocks for pi.on and ctx.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

# Some restricted agent sandboxes deny child-process creation from Node.  Node
# 22 can then hang in spawnSync when stdin is piped, which is exactly how the
# production extension supplies proposed file content to its shared guard.
# Detect that environment without a piped child before running the black-box
# suite.  CI and ordinary developer shells still exercise every assertion.
set +e
timeout 5s node -e '
  const { spawnSync } = require("node:child_process");
  const result = spawnSync("/bin/true", []);
  if (result.error?.code === "EPERM") process.exit(77);
  if (result.error || result.status !== 0) process.exit(1);
' >/dev/null 2>&1
NODE_SPAWN_STATUS=$?
set -e
if [[ $NODE_SPAWN_STATUS -eq 77 ]]; then
  echo "Pi shellcheck-disable extension tests skipped: sandbox denies Node child processes"
  exit 0
fi
if [[ $NODE_SPAWN_STATUS -ne 0 ]]; then
  echo "FAIL: Node child-process preflight failed or timed out (status $NODE_SPAWN_STATUS)" >&2
  exit 1
fi

assert_ok() {
  local desc=$1 handler_js=$2 expected=$3
  local out
  if ! out=$(node --input-type=module <<< "$handler_js"); then
    echo "FAIL: $desc (node execution failed; stderr was: ${out:-<empty>})" >&2
    ((FAIL++)) || true
    return
  fi
  if [[ "$out" != "$expected" ]]; then
    echo "FAIL: $desc (expected [$expected], got [$out])" >&2
    ((FAIL++)) || true
    return
  fi
  ((PASS++)) || true
}

assert_block() {
  local desc=$1 handler_js=$2 needle=$3
  local out
  if ! out=$(node --input-type=module <<< "$handler_js"); then
    echo "FAIL: $desc (node execution failed; stderr was: ${out:-<empty>})" >&2
    ((FAIL++)) || true
    return
  fi
  if [[ "$out" != "BLOCKED:$needle" ]]; then
    echo "FAIL: $desc (expected blocked with needle [$needle], got [$out])" >&2
    ((FAIL++)) || true
    return
  fi
  ((PASS++)) || true
}

# ---------------------------------------------------------------------------
# Build a temp fake repo and populate it with the guard + extension .mjs.
# ---------------------------------------------------------------------------
TEMP_REPO=$(mktemp -d)
trap 'rm -rf "$TEMP_REPO"' EXIT

mkdir -p "$TEMP_REPO/.pi/extensions"
mkdir -p "$TEMP_REPO/.agents/hooks"
mkdir -p "$TEMP_REPO/tests"
mkdir -p "$TEMP_REPO/docs"

cp "$PROJECT_ROOT/.agents/hooks/shellcheck-disable-contract-guard.sh" \
   "$TEMP_REPO/.agents/hooks/shellcheck-disable-contract-guard.sh"
chmod +x "$TEMP_REPO/.agents/hooks/shellcheck-disable-contract-guard.sh"

# The TS extension is valid JS that also uses only Node built-ins and import.meta.url.
# Pi auto-loads .ts, but Node needs .mjs; copy as-is since no TS-specific syntax
# is used.
cp "$PROJECT_ROOT/.pi/extensions/shellcheck-disable-contract.ts" \
   "$TEMP_REPO/.pi/extensions/shellcheck-disable-contract.mjs"

EXT_MJS="$TEMP_REPO/.pi/extensions/shellcheck-disable-contract.mjs"

# ---------------------------------------------------------------------------
# Test 1: safe contract write allowed
# ---------------------------------------------------------------------------
HANDLER_JS_1=$(cat <<INNER_EOF
const mod = await import("$EXT_MJS");

let capturedHandler = null;
const mockPi = {
  on(eventName, handler) {
    if (eventName === "tool_call") capturedHandler = handler;
  }
};
mod.default(mockPi);

const result = capturedHandler(
  { toolName: "write", input: { path: "tests/test_ok_contract.sh", content: "echo hello\n" } },
  { cwd: "$TEMP_REPO" }
);
console.log(result === undefined ? "OK" : JSON.stringify(result));
INNER_EOF
)
assert_ok "safe contract write allowed" "$HANDLER_JS_1" "OK"

# ---------------------------------------------------------------------------
# Test 2: contract write with # shellcheck disable=SC2086 blocked
# ---------------------------------------------------------------------------
HANDLER_JS_2=$(cat <<INNER_EOF
const mod = await import("$EXT_MJS");

let capturedHandler = null;
const mockPi = {
  on(eventName, handler) {
    if (eventName === "tool_call") capturedHandler = handler;
  }
};
mod.default(mockPi);

const result = capturedHandler(
  { toolName: "write", input: { path: "tests/test_bad_contract.sh", content: "# shellcheck disable=SC2086\necho hello\n" } },
  { cwd: "$TEMP_REPO" }
);
if (result && result.block) {
  console.log("BLOCKED:" + result.reason);
} else {
  console.log("OK");
}
INNER_EOF
)
assert_block "contract write with disable=SC2086 blocked" "$HANDLER_JS_2" \
  "REJECTED in tests/test_bad_contract.sh: Line-level ShellCheck disable directives are not allowed in shell contract tests. Fix the shell expression instead of suppressing the warning."

# ---------------------------------------------------------------------------
# Test 3: block reason contains contract path
# ---------------------------------------------------------------------------
HANDLER_JS_3=$(cat <<INNER_EOF
const mod = await import("$EXT_MJS");

let capturedHandler = null;
const mockPi = {
  on(eventName, handler) {
    if (eventName === "tool_call") capturedHandler = handler;
  }
};
mod.default(mockPi);

const result = capturedHandler(
  { toolName: "write", input: { path: "tests/test_path_contract.sh", content: "# shellcheck disable=SC2016\necho hello\n" } },
  { cwd: "$TEMP_REPO" }
);
if (result && result.block) {
  console.log("BLOCKED:" + result.reason);
} else {
  console.log("OK");
}
INNER_EOF
)
assert_block "block reason contains contract path" "$HANDLER_JS_3" \
  "REJECTED in tests/test_path_contract.sh: Line-level ShellCheck disable directives are not allowed in shell contract tests. Fix the shell expression instead of suppressing the warning."

# ---------------------------------------------------------------------------
# Test 4: non-contract write with disable allowed
# ---------------------------------------------------------------------------
HANDLER_JS_4=$(cat <<INNER_EOF
const mod = await import("$EXT_MJS");

let capturedHandler = null;
const mockPi = {
  on(eventName, handler) {
    if (eventName === "tool_call") capturedHandler = handler;
  }
};
mod.default(mockPi);

const result = capturedHandler(
  { toolName: "write", input: { path: "docs/shellcheck-policy.md", content: "# shellcheck disable=SC2016\nsome prose\n" } },
  { cwd: "$TEMP_REPO" }
);
console.log(result === undefined ? "OK" : JSON.stringify(result));
INNER_EOF
)
assert_ok "non-contract write with disable allowed" "$HANDLER_JS_4" "OK"

# ---------------------------------------------------------------------------
# Test 5: malformed write payload blocked
# ---------------------------------------------------------------------------
HANDLER_JS_5=$(cat <<INNER_EOF
const mod = await import("$EXT_MJS");

let capturedHandler = null;
const mockPi = {
  on(eventName, handler) {
    if (eventName === "tool_call") capturedHandler = handler;
  }
};
mod.default(mockPi);

// Malformed: missing content field
const result = capturedHandler(
  { toolName: "write", input: { path: "tests/foo.sh" } },
  { cwd: "$TEMP_REPO" }
);
if (result && result.block) {
  console.log("BLOCKED:" + result.reason);
} else {
  console.log("OK");
}
INNER_EOF
)
assert_block "malformed write payload blocked" "$HANDLER_JS_5" "could not safely inspect write payload"

# ---------------------------------------------------------------------------
# Test 6: missing shared guard blocked with "could not safely inspect"
# ---------------------------------------------------------------------------
ALT_TEMP_REPO=$(mktemp -d)
trap 'rm -rf "$TEMP_REPO" "$ALT_TEMP_REPO"' EXIT

mkdir -p "$ALT_TEMP_REPO/.pi/extensions"
mkdir -p "$ALT_TEMP_REPO/.agents/hooks"
mkdir -p "$ALT_TEMP_REPO/tests"

cp "$PROJECT_ROOT/.pi/extensions/shellcheck-disable-contract.ts" \
   "$ALT_TEMP_REPO/.pi/extensions/variant.mjs"

# Patch REPO_ROOT to point at ALT_TEMP_REPO so the guard path is absent.
VARIANT_SRC=$(sed "s|const REPO_ROOT = resolve(EXT_DIR, \"\\.\\.\", \"\\.\\.\");|const REPO_ROOT = \"$(realpath "$ALT_TEMP_REPO")\";|" \
  "$ALT_TEMP_REPO/.pi/extensions/variant.mjs")
printf '%s' "$VARIANT_SRC" > "$ALT_TEMP_REPO/.pi/extensions/variant.mjs"

HANDLER_JS_6=$(cat <<INNER_EOF
const mod = await import("$(realpath "$ALT_TEMP_REPO/.pi/extensions/variant.mjs")");

let capturedHandler = null;
const mockPi = {
  on(eventName, handler) {
    if (eventName === "tool_call") capturedHandler = handler;
  }
};
mod.default(mockPi);

const result = capturedHandler(
  { toolName: "write", input: { path: "tests/foo.sh", content: "echo hi\n" } },
  { cwd: "$(realpath "$ALT_TEMP_REPO")" }
);
if (result && result.block) {
  console.log("BLOCKED:" + result.reason);
} else {
  console.log("OK");
}
INNER_EOF
)
assert_block "missing shared guard blocked" "$HANDLER_JS_6" "could not safely inspect"

# ---------------------------------------------------------------------------
# Test 7: unrelated edit tool allowed
# ---------------------------------------------------------------------------
HANDLER_JS_7=$(cat <<INNER_EOF
const mod = await import("$EXT_MJS");

let capturedHandler = null;
const mockPi = {
  on(eventName, handler) {
    if (eventName === "tool_call") capturedHandler = handler;
  }
};
mod.default(mockPi);

// An unrelated tool should pass through unchanged (undefined)
const result = capturedHandler(
  { toolName: "edit", input: { path: "tests/foo.sh", oldText: "a", newText: "b" } },
  { cwd: "$TEMP_REPO" }
);
console.log(result === undefined ? "OK" : JSON.stringify(result));
INNER_EOF
)
# Update test 7 to use proper Pi edit payload format (edits array).
HANDLER_JS_7=$(cat <<INNER_EOF
const mod = await import("$EXT_MJS");

let capturedHandler = null;
const mockPi = {
  on(eventName, handler) {
    if (eventName === "tool_call") capturedHandler = handler;
  }
};
mod.default(mockPi);

// A non-contract edit should pass through unchanged (undefined)
const result = capturedHandler(
  { toolName: "edit", input: { path: "docs/shellcheck-policy.md", edits: [{ oldText: "a", newText: "b" }] } },
  { cwd: "$TEMP_REPO" }
);
console.log(result === undefined ? "OK" : JSON.stringify(result));
INNER_EOF
)
assert_ok "non-contract edit allowed" "$HANDLER_JS_7" "OK"

# ---------------------------------------------------------------------------
# Test 8: safe exact contract edit allowed
# ---------------------------------------------------------------------------
cat > "$TEMP_REPO/tests/test_ok_contract_edit.sh" <<'EOF'
echo hello
EOF

HANDLER_JS_8=$(cat <<INNER_EOF
const mod = await import("$EXT_MJS");

let capturedHandler = null;
const mockPi = {
  on(eventName, handler) {
    if (eventName === "tool_call") capturedHandler = handler;
  }
};
mod.default(mockPi);

const result = capturedHandler(
  { toolName: "edit", input: { path: "tests/test_ok_contract_edit.sh", edits: [{ oldText: "echo hello", newText: "echo world" }] } },
  { cwd: "$TEMP_REPO" }
);
console.log(result === undefined ? "OK" : JSON.stringify(result));
INNER_EOF
)
assert_ok "safe exact contract edit allowed" "$HANDLER_JS_8" "OK"

# ---------------------------------------------------------------------------
# Test 9: contract file with source directive, edit creates disable => blocked
# ---------------------------------------------------------------------------
cat > "$TEMP_REPO/tests/test_source_contract.sh" <<'EOF'
# shellcheck source=SC2016
echo hello
EOF

HANDLER_JS_9=$(cat <<INNER_EOF
const mod = await import("$EXT_MJS");

let capturedHandler = null;
const mockPi = {
  on(eventName, handler) {
    if (eventName === "tool_call") capturedHandler = handler;
  }
};
mod.default(mockPi);

const result = capturedHandler(
  { toolName: "edit", input: { path: "tests/test_source_contract.sh", edits: [{ oldText: "source", newText: "disable" }] } },
  { cwd: "$TEMP_REPO" }
);
if (result && result.block) {
  console.log("BLOCKED:" + result.reason);
} else {
  console.log("OK");
}
INNER_EOF
)
assert_block "contract edit creates disable directive" "$HANDLER_JS_9" \
  "REJECTED in tests/test_source_contract.sh: Line-level ShellCheck disable directives are not allowed in shell contract tests. Fix the shell expression instead of suppressing the warning."

# ---------------------------------------------------------------------------
# Test 10: multi-edit contract call where one replacement creates a disable => blocked
# ---------------------------------------------------------------------------
cat > "$TEMP_REPO/tests/test_multi_contract.sh" <<'EOF'
#!/bin/sh
x=1
y=2
EOF

HANDLER_JS_10=$(cat <<INNER_EOF
const mod = await import("$EXT_MJS");

let capturedHandler = null;
const mockPi = {
  on(eventName, handler) {
    if (eventName === "tool_call") capturedHandler = handler;
  }
};
mod.default(mockPi);

const result = capturedHandler(
  { toolName: "edit", input: { path: "tests/test_multi_contract.sh", edits: [{ oldText: "x=1", newText: "# shellcheck disable=SC2086" }, { oldText: "y=2", newText: "z=3" }] } },
  { cwd: "$TEMP_REPO" }
);
if (result && result.block) {
  console.log("BLOCKED:" + result.reason);
} else {
  console.log("OK");
}
INNER_EOF
)
assert_block "multi-edit contract creates disable directive" "$HANDLER_JS_10" \
  "REJECTED in tests/test_multi_contract.sh: Line-level ShellCheck disable directives are not allowed in shell contract tests. Fix the shell expression instead of suppressing the warning."

# ---------------------------------------------------------------------------
# Test 11: malformed edit payload => blocked
# ---------------------------------------------------------------------------
HANDLER_JS_11=$(cat <<INNER_EOF
const mod = await import("$EXT_MJS");

let capturedHandler = null;
const mockPi = {
  on(eventName, handler) {
    if (eventName === "tool_call") capturedHandler = handler;
  }
};
mod.default(mockPi);

// Malformed: edits is not an array
const result = capturedHandler(
  { toolName: "edit", input: { path: "tests/foo.sh", edits: "not-an-array" } },
  { cwd: "$TEMP_REPO" }
);
if (result && result.block) {
  console.log("BLOCKED:" + result.reason);
} else {
  console.log("OK");
}
INNER_EOF
)
assert_block "malformed edit payload blocked" "$HANDLER_JS_11" "could not safely inspect edit payload"

# ---------------------------------------------------------------------------
# Test 12: non-contract edit whose oldText does NOT exist => allowed
# ---------------------------------------------------------------------------
HANDLER_JS_12=$(cat <<INNER_EOF
const mod = await import("$EXT_MJS");

let capturedHandler = null;
const mockPi = {
  on(eventName, handler) {
    if (eventName === "tool_call") capturedHandler = handler;
  }
};
mod.default(mockPi);

// Non-contract path: guard accepts sentinel, so we never attempt reconstruction.
const result = capturedHandler(
  { toolName: "edit", input: { path: "docs/shellcheck-policy.md", edits: [{ oldText: "nonexistent-string", newText: "replacement" }] } },
  { cwd: "$TEMP_REPO" }
);
console.log(result === undefined ? "OK" : JSON.stringify(result));
INNER_EOF
)
assert_ok "non-contract edit nonexistent oldText allowed" "$HANDLER_JS_12" "OK"

# ---------------------------------------------------------------------------
echo ""
echo "Pi shellcheck-disable extension tests: ${PASS} passed, ${FAIL} failed"
if ((FAIL > 0)); then exit 1; fi
