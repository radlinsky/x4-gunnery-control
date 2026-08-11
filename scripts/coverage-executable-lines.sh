#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: coverage-executable-lines.sh SOURCE.lua" >&2
  exit 2
fi
source_file=$1

# luac attributes loop-closing bookkeeping to bare `end` lines as backwards
# JMPs. Lua's debug hook cannot observe those artificial line transitions, so
# exclude only such a line. A `break` also compiles to a JMP, but is behavior
# and must stay in the denominator; a forward JMP on a bare end stays too.
luac5.1 -l -p "$source_file" | awk '
  NR == FNR { source[FNR] = $0; next }
  /^[[:space:]]*[0-9]+[[:space:]]+\[[0-9]+\][[:space:]]+/ {
    line = $2
    gsub(/\[|\]/, "", line)
    if ($3 != "JMP" || $4 !~ /^-/ || source[line] !~ /^[[:space:]]*end[[:space:]]*[,;]?[[:space:]]*(--.*)?$/) {
      executable[line] = 1
    }
  }
  END { for (line in executable) print line }
' "$source_file" - | sort -u
