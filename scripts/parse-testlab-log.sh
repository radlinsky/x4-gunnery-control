#!/usr/bin/env bash
set -euo pipefail
log_file=${1:?usage: scripts/parse-testlab-log.sh /path/to/debug.log}
if [[ ! -f "$log_file" ]]; then
  echo "log file not found: $log_file" >&2
  exit 2
fi
awk '
BEGIN {
  key_count=split("event ship_macro ship_name ship_id group_key group_path group_name turret_macro turret_name turret_id target_id target_connection target_name target_macro target_preserved technical visual reason applied restored queued inspected technical_pass visual_pass visual_fail skipped retries group_pass group_fail", keys, " ")
  header=""
  for (i = 1; i <= key_count; i++) header=header (i == 1 ? "" : ",") keys[i]
  print header
}
index($0, "[X4GC TEST] ") {
  line=$0
  sub(/^.*\[X4GC TEST\] /, "", line)
  for (i = 1; i <= key_count; i++) data[keys[i]]=""
  count=split(line, words, " ")
  for (i = 1; i <= count; i++) {
    split(words[i], pair, "=")
    for (j = 1; j <= key_count; j++) if (pair[1] == keys[j]) data[pair[1]]=pair[2]
  }
  output=""
  for (i = 1; i <= key_count; i++) output=output (i == 1 ? "" : ",") data[keys[i]]
  print output
}' "$log_file"
