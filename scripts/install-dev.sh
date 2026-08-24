#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib-release.sh
source scripts/lib-release.sh
game=${1:?usage: scripts/install-dev.sh /path/to/X4\ Foundations}
if [[ ! -d "$game/extensions" || ( ! -f "$game/X4.exe" && ! -f "$game/X4" ) ]]; then
  echo "Not an X4 installation: $game" >&2
  exit 2
fi
target="$game/extensions/x4_gunnery_control"
# target is an explicitly constructed subdirectory under a validated X4 installation;
# the extension root ($game/extensions) must never be removed — only $target is wiped.
rm -rf "$target"
mkdir -p "$target"
copy_extension_files "$target"
echo "Installed loose development files to $target"

# Test Lab is a developer-only extension; only lay it down when explicitly asked
# (X4GC_INSTALL_TESTLAB set, propagated from launch-x4-test-lab-dev.bat via WSLENV).
if [[ -n "${X4GC_INSTALL_TESTLAB:-}" ]]; then
  testlab="$game/extensions/x4_gunnery_control_testlab"
  rm -rf "$testlab"
  mkdir -p "$testlab"
  cp -R testlab/x4_gunnery_control_testlab/. "$testlab/"
  # The committed spec stays enabled=false so the offline suite passes; a dev
  # install is always for a live run, so enable only the installed copy.
  spec="$testlab/ui/scenario_spec.lua"
  sed -i 's/^    enabled = false,/    enabled = true,/' "$spec"
  grep -q '^    enabled = true,' "$spec" || { echo "Failed to enable installed Test Lab spec" >&2; exit 3; }
  echo "Installed loose Test Lab files to $testlab (spec enabled)"
fi
