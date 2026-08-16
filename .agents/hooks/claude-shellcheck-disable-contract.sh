#!/usr/bin/env bash
set -euo pipefail
# Claude PreToolUse adapter for the shared ShellCheck-disable contract policy.
#
# Receives Claude's PreToolUse JSON payload on stdin, reconstructs the candidate
# file contents that would exist if the tool call succeeded, and delegates to
# .agents/hooks/shellcheck-disable-contract-guard.sh.
#
# Exit 0 = allowed; exit 2 = blocked (Claude Code blocks the tool call).

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GUARD="$REPO_ROOT/.agents/hooks/shellcheck-disable-contract-guard.sh"

python3 -c "
import json, os, subprocess, sys


def die(msg):
    print(
        'Claude pre-edit policy hook could not safely inspect the proposed edit: ' + msg,
        file=sys.stderr,
    )
    sys.exit(2)


try:
    data = json.load(sys.stdin)
except Exception as exc:
    die('invalid JSON (' + str(exc) + ')')

if not isinstance(data, dict):
    die('expected JSON object at top level')

tool_name = data.get('tool_name')
if tool_name not in ('Edit', 'Write'):
    sys.exit(0)

tool_input = data.get('tool_input') or {}
if not isinstance(tool_input, dict):
    die('expected tool_input object')

file_path = tool_input.get('file_path')
if not isinstance(file_path, str) or not file_path:
    die('missing file_path')

abspath = os.path.abspath(file_path)

# Normalize to repo-relative path.  Use realpath-style comparison against the
# known repository root so a sibling directory such as /repo-other/ is not
# mistaken for being inside /repo/.
norm_root = os.path.normpath(sys.argv[1])
if abspath.startswith(norm_root + os.sep):
    rel_path = abspath[len(norm_root) + 1:]
else:
    # Out-of-tree path — let the guard see the absolute path; it will not match
    # tests/*contract*.sh and will allow it through.
    rel_path = abspath

if tool_name == 'Write':
    content = tool_input.get('content')
    if not isinstance(content, str):
        die('Write payload missing content')
    candidate = content

elif tool_name == 'Edit':
    old_string = tool_input.get('old_string')
    new_string = tool_input.get('new_string')
    replace_all = tool_input.get('replace_all', False)
    if not isinstance(replace_all, bool):
        die('replace_all is not a boolean')

    if not isinstance(old_string, str) or not isinstance(new_string, str):
        die('Edit payload missing old_string or new_string')

    try:
        with open(abspath, 'r', encoding='utf-8') as fh:
            current = fh.read()
    except FileNotFoundError:
        # New file via Edit — cannot reconstruct a candidate. Claude itself will
        # reject an invalid edit, so let the tool call proceed.
        sys.exit(0)
    except OSError as exc:
        die('cannot read target file (' + str(exc) + ')')

    if replace_all:
        candidate = current.replace(old_string, new_string)
    else:
        count = current.count(old_string)
        if count == 0:
            # Claude's Edit tool will reject an invalid edit itself.
            sys.exit(0)
        elif count == 1:
            candidate = current.replace(old_string, new_string, 1)
        else:
            # Multiple occurrences — ambiguous. Let Claude's Edit tool reject it.
            sys.exit(0)

else:
    sys.exit(0)

guard_path = sys.argv[2]
try:
    result = subprocess.run(
        [guard_path, rel_path],
        input=candidate,
        capture_output=True,
        text=True,
    )
except OSError as exc:
    die('cannot execute shared guard (' + str(exc) + ')')
if result.returncode != 0:
    sys.stderr.write(result.stderr)
    sys.exit(2)

sys.exit(0)
" "$REPO_ROOT" "$GUARD"
