#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?usage: scripts/release-workshop.sh VERSION CHANGENOTE [extra WorkshopTool switches]}
changenote=${2:?usage: scripts/release-workshop.sh VERSION CHANGENOTE [extra WorkshopTool switches]}
shift 2

# ponytail: update only.  The first publish happened once, by hand, and needs a
# -preview and a legal-agreement click that no script can do for you.
id_file="release/workshop-id.txt"
if [[ ! -s "$id_file" ]]; then
  echo "$id_file is missing or empty -- this item has never been published." >&2
  echo "Run scripts/package-workshop.sh and use the printed publishx4 command." >&2
  exit 2
fi

tool=${X4GC_WORKSHOPTOOL:-/mnt/c/Program Files (x86)/Steam/steamapps/common/X Tools/WorkshopTool.exe}
if [[ ! -x "$tool" ]]; then
  echo "WorkshopTool.exe not found at: $tool" >&2
  echo "Install X Tools (steam://install/282160) or set X4GC_WORKSHOPTOOL." >&2
  exit 2
fi

./scripts/package-workshop.sh "$version" >/dev/null
stage=$(wslpath -w "$(pwd)/dist/workshop/x4_gunnery_control")

# WorkshopTool reads steam_appid.txt from its own folder, so run it from there.
# Steam must be running and logged in; the tool talks to that session.
cd "$(dirname "$tool")"
set -- update -path "$stage" -buildcat -changenote "$changenote" "$@"
printf 'WorkshopTool'; printf ' %q' "$@"; printf '\n'
[[ -n "${X4GC_DRY_RUN:-}" ]] && exit 0
exec "$tool" "$@"
