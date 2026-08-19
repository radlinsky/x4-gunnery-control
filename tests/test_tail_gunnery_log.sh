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

# --- tests: no-argument auto-discovery via find_log_file ---
# These tests stub cmd.exe and wslpath via PATH injection so the script
# can run on Linux CI without a real Windows environment.
#
# We cannot source tail-gunnery-log.sh directly (it would start the tailer
# loop), so each test drives a small subshell that defines only find_log_file
# using the same body the main script uses, then calls it.

stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir" "$fixture" "$output_file" "$output_file2" "$output_file3" "$output_file4" "$wait_log"' EXIT

# Helper: write a stub script that prints a fixed value and make it executable.
write_stub() {
  local name=$1 body=$2
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$stub_dir/$name"
  chmod +x "$stub_dir/$name"
}

# Helper: call find_log_file from the real script in a short-lived subshell.
# Extracts and evals only the function definition so the tailer loop never runs.
run_find_log_file() {
  local fn_body
  fn_body=$(awk '/^find_log_file\(\)/,/^\}/' scripts/tail-gunnery-log.sh)
  PATH="$stub_dir:$PATH" bash -c "
    set -euo pipefail
    $fn_body
    find_log_file
  " 2>/dev/null || true
}

# --- discovery test 1: USERPROFILE path ---
x4_base_up=$(mktemp -d)
trap 'rm -rf "$stub_dir" "$x4_base_up" "$fixture" "$output_file" "$output_file2" "$output_file3" "$output_file4" "$wait_log"' EXIT

mkdir -p "$x4_base_up/Documents/Egosoft/X4/123456"
printf '%s\n' '[X4GC] discovery_up event' > "$x4_base_up/Documents/Egosoft/X4/123456/debug.log"

write_stub "cmd.exe" "printf '%s\r\n' 'C:/FakeUser'"
write_stub "wslpath" "echo \"$x4_base_up\""

discovered=$(run_find_log_file)

if [[ "$discovered" != "$x4_base_up/Documents/Egosoft/X4/123456/debug.log" ]]; then
  echo "FAIL: USERPROFILE discovery: expected $x4_base_up/Documents/Egosoft/X4/123456/debug.log, got: ${discovered:-<nothing>}" >&2
  exit 1
fi
echo "discovery USERPROFILE test passed"

# --- discovery test 2: OneDrive fallback path ---
x4_base_od=$(mktemp -d)
trap 'rm -rf "$stub_dir" "$x4_base_up" "$x4_base_od" "$fixture" "$output_file" "$output_file2" "$output_file3" "$output_file4" "$wait_log"' EXIT

mkdir -p "$x4_base_od/Documents/Egosoft/X4/789012"
printf '%s\n' '[X4GC] discovery_od event' > "$x4_base_od/Documents/Egosoft/X4/789012/debug.log"

# cmd.exe stub: distinguish USERPROFILE vs OneDrive by argument content.
write_stub "cmd.exe" "
case \"\$*\" in
  *USERPROFILE*) printf '%s\r\n' 'C:/NoSuchUser' ;;
  *OneDrive*)    printf '%s\r\n' 'C:/FakeOneDrive' ;;
esac"
write_stub "wslpath" "
case \"\$1\" in
  C:/NoSuchUser)   echo /no/such/user ;;
  C:/FakeOneDrive) echo \"$x4_base_od\" ;;
  *) echo \"\$1\" ;;
esac"

discovered=$(run_find_log_file)

if [[ "$discovered" != "$x4_base_od/Documents/Egosoft/X4/789012/debug.log" ]]; then
  echo "FAIL: OneDrive discovery: expected $x4_base_od/Documents/Egosoft/X4/789012/debug.log, got: ${discovered:-<nothing>}" >&2
  exit 1
fi
echo "discovery OneDrive fallback test passed"

# --- discovery test 3: multiple numeric dirs; newest by mtime, NOT largest id ---
# Account 9999 has a higher id but older mtime.  Account 1001 has the newest
# mtime and must win; choosing by sort -rn (largest id) would pick 9999 instead.
x4_base_mtime=$(mktemp -d)
trap 'rm -rf "$stub_dir" "$x4_base_up" "$x4_base_od" "$x4_base_mtime" "$fixture" "$output_file" "$output_file2" "$output_file3" "$output_file4" "$wait_log"' EXIT

mkdir -p "$x4_base_mtime/Documents/Egosoft/X4/9999" "$x4_base_mtime/Documents/Egosoft/X4/1001"
printf '%s\n' '[X4GC] old account' > "$x4_base_mtime/Documents/Egosoft/X4/9999/debug.log"
touch -t 200001010000 "$x4_base_mtime/Documents/Egosoft/X4/9999"
touch -t 203001010000 "$x4_base_mtime/Documents/Egosoft/X4/1001"
printf '%s\n' '[X4GC] new account' > "$x4_base_mtime/Documents/Egosoft/X4/1001/debug.log"

write_stub "cmd.exe" "printf '%s\r\n' 'C:/FakeUser2'"
write_stub "wslpath" "echo \"$x4_base_mtime\""

discovered=$(run_find_log_file)

if [[ "$discovered" != "$x4_base_mtime/Documents/Egosoft/X4/1001/debug.log" ]]; then
  echo "FAIL: mtime discovery: expected $x4_base_mtime/Documents/Egosoft/X4/1001/debug.log (newest mtime), got: ${discovered:-<nothing>}" >&2
  echo "  (If this picked 9999 it is the sort -rn regression: largest id, not newest mtime)" >&2
  exit 1
fi
echo "discovery newest-by-mtime test passed"

echo "tail gunnery log checks passed"
