#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Interval between polls in seconds (override for tests).
POLL_INTERVAL=${TAIL_GUNNERY_POLL_INTERVAL:-2}

# Defines X4GC_LOG_PATTERN and returns without running its own filter.
source "scripts/filter-gunnery-log.sh"

find_log_file() {
  local base
  # Try USERPROFILE/Documents first, then OneDrive fallback — mirrors launch-x4-dev.bat:103-116.
  local userprofile_win
  userprofile_win=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')
  local candidates=()

  if [[ -n "$userprofile_win" ]]; then
    base=$(wslpath "$userprofile_win" 2>/dev/null || true)
    [[ -n "$base" ]] && candidates+=("$base/Documents/Egosoft/X4")
  fi

  local onedrive_win
  onedrive_win=$(cmd.exe /c "echo %OneDrive%" 2>/dev/null | tr -d '\r')
  if [[ -n "$onedrive_win" && "$onedrive_win" != "%OneDrive%" ]]; then
    base=$(wslpath "$onedrive_win" 2>/dev/null || true)
    [[ -n "$base" ]] && candidates+=("$base/Documents/Egosoft/X4")
  fi

  for dir in "${candidates[@]}"; do
    [[ -d "$dir" ]] || continue
    # Pick the most recently modified all-digit subdirectory (newest by mtime,
    # not by numeric id — the largest account id is not necessarily the active one).
    local found
    found=$(find "$dir" -maxdepth 1 -mindepth 1 -type d -name '[0-9]*' -printf '%T@ %f\n' \
      | grep -E '^[0-9.]+ [0-9]+$' \
      | sort -rn \
      | head -1 \
      | awk '{print $2}')
    if [[ -n "$found" ]]; then
      echo "$dir/$found/debug.log"
      return 0
    fi
  done
  return 1
}

if [[ $# -ge 1 ]]; then
  log_file=$1
else
  if ! log_file=$(find_log_file); then
    echo "Could not locate X4 log directory under USERPROFILE or OneDrive Documents/Egosoft/X4" >&2
    echo "Usage: $0 [/path/to/debug.log]" >&2
    exit 2
  fi
fi

# X4 may not have written the log yet when the tail window opens alongside it.
# Poll until the file appears, then start tailing. 120 s is enough for any
# normal X4 startup; if it never appears that is a typo or a real problem.
WAIT_TIMEOUT=${TAIL_GUNNERY_WAIT_TIMEOUT:-120}
# Whether anything was on disk before we started deciding what counts as history.
# A file we had to wait for was created by the run we are here to watch, so it
# has no previous run in it and none of it may be skipped.
existed_at_start=0
[[ -f "$log_file" ]] && existed_at_start=1
if [[ ! -f "$log_file" ]]; then
  echo "Waiting for $log_file ..." >&2
  deadline=$(( SECONDS + WAIT_TIMEOUT ))
  while [[ ! -f "$log_file" ]]; do
    if (( SECONDS >= deadline )); then
      echo "Log file not found after ${WAIT_TIMEOUT}s: $log_file" >&2
      exit 2
    fi
    sleep "$POLL_INTERVAL"
  done
fi

echo "Tailing $log_file (Ctrl-C to stop)" >&2

# Track a byte offset rather than re-reading the file each poll: with -debug all
# an X4 log reaches hundreds of MB in one session, so a full re-read would not
# keep up. Reading past the offset also sidesteps the stale-metadata problem,
# because it never consults size or mtime to decide whether there is new data.
offset=0
first_line=""
# The log on disk right now belongs to the PREVIOUS run: X4 truncates on launch,
# and this window opens before that has happened. Printing it replayed the whole
# last session as if it were live -- an easy way to chase an error that was
# already fixed. Skip whatever is there at startup and print only what arrives
# afterwards. The truncation check below resets the offset the moment X4 writes
# its new header, so the run being launched is still shown from its first line.
priming=$existed_at_start

chunk=$(mktemp)
trap 'rm -f "$chunk"' EXIT

while true; do
  # X4 truncates the log on every launch, and the header line it writes then is
  # the only reliable relaunch signal: file size cannot be trusted here, so a
  # shrunk file is not detectable. head reads real bytes, so this check is safe.
  current_first=$(head -n 1 "$log_file")
  if [[ -n "$first_line" && "$current_first" != "$first_line" ]]; then
    echo "--- log truncated, resetting ---" >&2
    offset=0
  fi
  first_line=$current_first

  # Never ask for the file's size — only read past the offset and count what
  # actually came back. Everything stat-derived is stale while X4 holds the
  # handle open; the bytes themselves are not.
  tail -c "+$((offset + 1))" "$log_file" > "$chunk"
  read_bytes=$(wc -c < "$chunk")

  # A poll can land mid-write. Hold back a trailing partial line and pick it up
  # whole next time, otherwise it is split across two chunks and matches the
  # filter in neither half — a silently dropped log line. An empty `tail -c 1`
  # means the last byte was a newline, so nothing needs holding back.
  hold=0
  if [[ -n "$(tail -c 1 "$chunk")" ]]; then
    hold=$(LC_ALL=C awk 'END { print length($0) }' "$chunk")
  fi

  if (( read_bytes > hold )); then
    if (( priming )); then
      echo "--- skipping $((read_bytes - hold)) bytes from the previous run ---" >&2
    else
      head -c "$((read_bytes - hold))" "$chunk" | grep -E "$X4GC_LOG_PATTERN" || true
    fi
    offset=$((offset + read_bytes - hold))
  fi
  priming=0

  sleep "$POLL_INTERVAL"
done
