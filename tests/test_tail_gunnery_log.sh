#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fixture=$(mktemp)
trap 'rm -f "$fixture"' EXIT

# Use a very short poll interval so the test completes quickly.
export TAIL_GUNNERY_POLL_INTERVAL=0.1

# --- helpers ---

run_one_poll() {
  # Run the script for exactly one poll cycle then stop.
  # We do this by wrapping in a timeout and capturing output.
  timeout 2 scripts/tail-gunnery-log.sh "$fixture" 2>/dev/null || true
}

# --- test: growing file produces no duplicate and no dropped lines ---

printf '%s\n' \
  '[X4GC] first event' \
  'unrelated line' \
  '[X4GC TEST] turret_result ship=1' > "$fixture"

# Run one full grow-then-extend cycle by driving the script manually.
# Strategy: start the tail in the background, append to the file, collect output.

output_file=$(mktemp)
trap 'rm -f "$fixture" "$output_file"' EXIT

# Start tail in background; it will poll every 0.1 s.
timeout 2 scripts/tail-gunnery-log.sh "$fixture" >"$output_file" 2>/dev/null &
tail_pid=$!

sleep 0.2

# Append a new matching line.
printf '%s\n' '[X4GC] second event' >> "$fixture"

sleep 0.2

kill "$tail_pid" 2>/dev/null || true
wait "$tail_pid" 2>/dev/null || true

output=$(<"$output_file")

# What was already in the file belongs to the previous X4 run: the log is
# truncated on launch and this window opens around that moment. Replaying it
# presents a finished session as if it were live, which sent a developer chasing
# an error that had already been fixed. Only what arrives after startup is live.
if grep -Fq '[X4GC] first event' <<< "$output"; then
  echo "FAIL: pre-existing content was replayed instead of skipped" >&2
  exit 1
fi
if grep -Fq '[X4GC TEST] turret_result ship=1' <<< "$output"; then
  echo "FAIL: pre-existing content was replayed instead of skipped" >&2
  exit 1
fi
grep -Fq '[X4GC] second event' <<< "$output"

# No duplicates: each matching line should appear exactly once.
second_count=$(grep -Fc '[X4GC] second event' <<< "$output")
if (( second_count != 1 )); then
  echo "FAIL: '[X4GC] second event' appeared $second_count times (expected 1)" >&2
  exit 1
fi

# Unrelated lines must be filtered out.
if grep -Fq 'unrelated line' <<< "$output"; then
  echo "FAIL: unrelated line was not filtered" >&2
  exit 1
fi

echo "grow test passed"

# --- test: truncation resets the counter ---

# Write initial content and drain one poll.
printf '%s\n' '[X4GC] before truncation' > "$fixture"

output_file2=$(mktemp)
trap 'rm -f "$fixture" "$output_file" "$output_file2"' EXIT

timeout 3 scripts/tail-gunnery-log.sh "$fixture" >"$output_file2" 2>/dev/null &
tail_pid2=$!

sleep 0.2

# Truncate (simulate new X4 launch) and write fresh content.
printf '%s\n' '[X4GC] after truncation' > "$fixture"

sleep 0.2

kill "$tail_pid2" 2>/dev/null || true
wait "$tail_pid2" 2>/dev/null || true

output2=$(<"$output_file2")

# This is the real launch sequence: the tailer starts while the previous run's
# log is still on disk, skips it, and X4 then truncates. Everything from the new
# run must appear, starting at its first line -- skipping history must not turn
# into skipping the run being launched.
if grep -Fq '[X4GC] before truncation' <<< "$output2"; then
  echo "FAIL: content from before the truncation was replayed" >&2
  exit 1
fi
grep -Fq '[X4GC] after truncation' <<< "$output2"

echo "truncation reset test passed"

# --- test: a line written in two pieces is emitted once, whole ---
# X4 is mid-write when a poll lands. A split line must not be dropped (neither
# half matches the filter) nor emitted twice.

printf '%s\n' '[X4GC] header for split test' > "$fixture"

output_file3=$(mktemp)
trap 'rm -f "$fixture" "$output_file" "$output_file2" "$output_file3"' EXIT

timeout 3 scripts/tail-gunnery-log.sh "$fixture" >"$output_file3" 2>/dev/null &
tail_pid3=$!

sleep 0.2

# First half, deliberately with no trailing newline.
printf '%s' '[X4GC] split ' >> "$fixture"
sleep 0.3
# Second half completes the line.
printf '%s\n' 'across polls' >> "$fixture"
sleep 0.3

kill "$tail_pid3" 2>/dev/null || true
wait "$tail_pid3" 2>/dev/null || true

output3=$(<"$output_file3")

split_count=$(grep -Fc '[X4GC] split across polls' <<< "$output3" || true)
if (( split_count != 1 )); then
  echo "FAIL: split line appeared $split_count times (expected 1)" >&2
  echo "--- captured output ---" >&2
  cat "$output_file3" >&2
  exit 1
fi

echo "split line test passed"

# --- test: wait for log file to appear ---
# The tail is started before the file exists; it should wait and then pick up
# lines once the file is created. Uses a short timeout so failure is fast.

wait_log=$(mktemp -u)   # path only — do not create the file yet
output_file4=$(mktemp)
trap 'rm -f "$fixture" "$output_file" "$output_file2" "$output_file3" "$output_file4" "$wait_log"' EXIT

TAIL_GUNNERY_WAIT_TIMEOUT=5 timeout 4 scripts/tail-gunnery-log.sh "$wait_log" >"$output_file4" 2>/dev/null &
tail_pid4=$!

sleep 0.3

# Now create the file with a matching line.
printf '%s\n' '[X4GC] appeared after wait' > "$wait_log"

sleep 0.4

kill "$tail_pid4" 2>/dev/null || true
wait "$tail_pid4" 2>/dev/null || true

output4=$(<"$output_file4")
if ! grep -Fq '[X4GC] appeared after wait' <<< "$output4"; then
  echo "FAIL: wait-for-file: line written after file creation was not captured" >&2
  exit 1
fi

echo "wait-for-file test passed"
echo "tail gunnery log checks passed"
