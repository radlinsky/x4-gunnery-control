#!/usr/bin/env bash
set -euo pipefail
# Prints the reload-or-restart instruction for a changed file, per docs/RELOADING.md.
#
# Two callers, one body:
#   scripts/reload-advice.sh <path>   -> plain text on stdout, or nothing
#   <hook JSON on stdin>              -> Claude Code PostToolUse JSON, or nothing
#
# Exists because the rule in AGENTS.md is one an agent has to remember, and the
# failure is silent: telling the owner to reload when the change needed a restart
# wastes a run and looks like the change did not work.

advice_for() {
  # Match on the repo-relative path. Hook payloads carry absolute paths, so strip
  # anything up to the repo root first; a path outside the repo simply will not
  # match any pattern below and produces no advice.
  local path=${1#"$PWD"/}
  case "$path" in
    ui.xml|content.xml|t/*.xml)
      echo "RELOAD: **full restart**. Exit X4 and run scripts/launch-x4-dev.bat (it installs on its own). No reload command re-reads ${path}." ;;
    testlab/*)
      echo "RELOAD: **full restart** with scripts/launch-x4-test-lab-dev.bat. Test Lab's own files are not re-read by a reload, and it only installs when X4GC_INSTALL_TESTLAB is set." ;;
    ui/*.lua)
      echo "RELOAD: run scripts/install-dev.sh \"<game path>\" yourself, then tell the owner: sit at a gunnery console -> Test Lab -> **Reload UI**, and confirm the log shows the runtimeBuild id you just installed. Say the id. THREE Test Lab buttons exist (console action row / target browser action row / engaged panel) -- name the one matching the phase your change needs, because opening Test Lab parks the session as it is and the reload restores that. A reload wipes Lua state. If you ADDED or DELETED a file, say full restart instead." ;;
    md/*.xml)
      echo "RELOAD: run scripts/install-dev.sh \"<game path>\" yourself, then tell the owner: sit at a gunnery console -> Test Lab -> **Reload MD**, then name the cue to trigger again. THREE Test Lab buttons exist (console action row / target browser action row / engaged panel) -- name the one matching the phase your change needs. refreshmd keeps existing cue variables and will not re-run a completed cue. If you ADDED or DELETED a file, say full restart instead." ;;
    *)
      return 0 ;;
  esac
  echo "See docs/RELOADING.md. Never offer the owner a choice between reload and restart."
}

if [[ $# -ge 1 ]]; then
  advice_for "$1"
  exit 0
fi

# Hook mode. python3 rather than grepping the JSON: file paths can contain the
# characters that would break a naive match, and this is the same interpreter
# check-kb.py already requires.
path=$(python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(data.get("tool_input", {}).get("file_path", ""))
' || true)

[[ -n "$path" ]] || exit 0
text=$(advice_for "$path")
[[ -n "$text" ]] || exit 0

python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": sys.stdin.read().strip(),
}}))
' <<< "$text"
