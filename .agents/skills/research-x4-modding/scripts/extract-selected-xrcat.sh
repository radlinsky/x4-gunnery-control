#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: extract-selected-xrcat.sh (--tool EXE | --tool-zip ZIP --tool-cache DIR)
       --input CATALOG [--input CATALOG ...] --output NEW_DIRECTORY
       --include REGEX [--include REGEX ...] [--exclude REGEX ...]
       [--expected-sha256 HASH] [--dry-run]

Run source-verified XRCatTool v1.11 selected-file extraction. Inputs must be
existing .cat files and later inputs override earlier ones. The output must be a
new directory, never an X4 installation or catalog. At least one include regex
is required; excludes are optional. --tool-zip extracts only XRCatTool.exe and
Readme.txt into an explicit new/reusable tool-cache directory. --dry-run prints
the exact escaped command and performs no extraction or tool execution. Paths
inside this repository must be under its ignored .x4-research-cache directory.
The ZIP must match the recorded v1.11 SHA-256 unless --expected-sha256 supplies
another independently verified hash (primarily for mirrors and test fixtures).
EOF
}

tool=
tool_zip=
tool_cache=
output=
dry_run=false
expected_sha256=4ec0db79670edba7d1568ef04eb1666d712fc1b4bd7222e723d67011c59f15ec
declare -a inputs=()
declare -a includes=()
declare -a excludes=()

while (($#)); do
  case "$1" in
    --tool) tool=${2:?missing executable}; shift 2 ;;
    --tool-zip) tool_zip=${2:?missing zip}; shift 2 ;;
    --tool-cache) tool_cache=${2:?missing cache directory}; shift 2 ;;
    --input) inputs+=("${2:?missing catalog}"); shift 2 ;;
    --output) output=${2:?missing output directory}; shift 2 ;;
    --include) includes+=("${2:?missing regex}"); shift 2 ;;
    --exclude) excludes+=("${2:?missing regex}"); shift 2 ;;
    --expected-sha256) expected_sha256=${2:?missing SHA-256}; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --append|--diff) echo "unsupported unsafe XRCatTool option: $1" >&2; exit 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -n "$tool" && -n "$tool_zip" ]] || [[ -z "$tool" && -z "$tool_zip" ]]; then
  echo 'provide exactly one of --tool or --tool-zip' >&2; exit 2
fi
if [[ -n "$tool_zip" && -z "$tool_cache" ]]; then echo '--tool-zip requires --tool-cache' >&2; exit 2; fi
if [[ -n "$tool" && -n "$tool_cache" ]]; then echo '--tool-cache is only valid with --tool-zip' >&2; exit 2; fi
if [[ -z "$output" || ${#inputs[@]} -eq 0 || ${#includes[@]} -eq 0 ]]; then
  echo 'require --output, at least one --input, and at least one --include' >&2; exit 2
fi
if [[ ! "$expected_sha256" =~ ^[0-9a-fA-F]{64}$ ]]; then echo 'expected SHA-256 must contain 64 hexadecimal characters' >&2; exit 2; fi
expected_sha256=${expected_sha256,,}

for input in "${inputs[@]}"; do
  case "$input" in *.cat|*.CAT) ;; *) echo "input is not a .cat file: $input" >&2; exit 2;; esac
  [[ -f "$input" ]] || { echo "missing input catalog: $input" >&2; exit 2; }
done
case "$output" in /|.) echo 'refusing broad output target' >&2; exit 2;; *.cat|*.CAT) echo 'output must be a directory, not a catalog' >&2; exit 2;; esac
[[ ! -e "$output" ]] || { echo "refusing existing output: $output" >&2; exit 2; }

is_within() {
  local child parent
  child=$(realpath -m -- "$1")
  parent=$(realpath -m -- "$2")
  [[ "$child" == "$parent" || "$child" == "$parent"/* ]]
}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(realpath -e -- "$script_dir/../../../..")
repo_cache="$repo_dir/.x4-research-cache"
refuse_tracked_repo_target() {
  local candidate=$1
  if is_within "$candidate" "$repo_dir" && ! is_within "$candidate" "$repo_cache"; then
    echo "refusing tracked repository target outside .x4-research-cache: $candidate" >&2
    exit 2
  fi
}
refuse_tracked_repo_target "$output"
for x4_root in "${X4GC_X4_ROOT:-}" '/mnt/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations' '/mnt/c/GOG Games/X4 Foundations'; do
  [[ -n "$x4_root" && -d "$x4_root" ]] || continue
  if is_within "$output" "$x4_root"; then echo "refusing X4 installation output: $output" >&2; exit 2; fi
done

if [[ -n "$tool" ]]; then
  [[ -f "$tool" ]] || { echo "missing tool: $tool" >&2; exit 2; }
else
  [[ -f "$tool_zip" ]] || { echo "missing tool zip: $tool_zip" >&2; exit 2; }
  actual_sha256=$(sha256sum -- "$tool_zip" | awk '{print $1}')
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "tool zip SHA-256 mismatch: expected $expected_sha256, got $actual_sha256" >&2
    exit 2
  fi
  case "$tool_cache" in /|.) echo 'refusing broad tool cache target' >&2; exit 2;; esac
  refuse_tracked_repo_target "$tool_cache"
  if [[ -e "$tool_cache" ]]; then
    [[ -f "$tool_cache/XRCatTool.exe" && -f "$tool_cache/Readme.txt" \
      && -f "$tool_cache/.source-zip.sha256" && -f "$tool_cache/.files.sha256" ]] || {
      echo "tool cache exists but is incomplete: $tool_cache" >&2; exit 2
    }
    [[ $(<"$tool_cache/.source-zip.sha256") == "$expected_sha256" ]] || {
      echo "tool cache source hash does not match expected ZIP: $tool_cache" >&2; exit 2
    }
    (cd "$tool_cache" && sha256sum -c --status .files.sha256) || {
      echo "tool cache content hash check failed: $tool_cache" >&2; exit 2
    }
  fi
  tool="$tool_cache/XRCatTool.exe"
fi

is_wsl=false
if [[ -r /proc/version ]] && grep -qi microsoft /proc/version && [[ "$tool" == *.exe ]] && command -v wslpath >/dev/null; then is_wsl=true; fi
path_for_tool() {
  if "$is_wsl"; then wslpath -w -- "$1"; else printf '%s\n' "$1"; fi
}

declare -a command=("$tool" -in)
for input in "${inputs[@]}"; do command+=("$(path_for_tool "$input")"); done
command+=(-out "$(path_for_tool "$output")" -include "${includes[@]}")
if ((${#excludes[@]})); then command+=(-exclude "${excludes[@]}"); fi
print_command() { printf 'command='; printf '%q ' "${command[@]}"; printf '\n'; }

if "$dry_run"; then
  if [[ -n "$tool_zip" && ! -e "$tool_cache" ]]; then
    printf 'prepare_command='; printf '%q ' unzip -j "$tool_zip" XRCatTool.exe Readme.txt -d "$tool_cache"; printf '\n'
  fi
  print_command
  exit 0
fi

if [[ -n "$tool_zip" && ! -e "$tool_cache" ]]; then
  unzip -Z1 "$tool_zip" | grep -Fxq 'XRCatTool.exe'
  unzip -Z1 "$tool_zip" | grep -Fxq 'Readme.txt'
  mkdir -p -- "$tool_cache"
  unzip -q -j -- "$tool_zip" XRCatTool.exe Readme.txt -d "$tool_cache"
  printf '%s\n' "$expected_sha256" >"$tool_cache/.source-zip.sha256"
  (cd "$tool_cache" && sha256sum XRCatTool.exe Readme.txt >.files.sha256)
fi

if [[ -n "$tool_zip" ]]; then
  # Windows-created ZIPs do not reliably preserve a POSIX executable bit.
  # Change only the ignored tool-cache copy, never the archive or game files.
  chmod u+x -- "$tool"
elif [[ ! -x "$tool" ]]; then
  echo "explicit tool is not executable: $tool" >&2
  exit 2
fi

# XRCatTool 1.11 distinguishes folder output from catalog output by checking
# the path. Create the validated new directory only after all safety checks.
mkdir -p -- "$output"
"${command[@]}" || {
  status=$?
  # Remove only our still-empty directory. Preserve partial output for review.
  rmdir -- "$output" 2>/dev/null || true
  exit "$status"
}
