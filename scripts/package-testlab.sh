#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=${1:?usage: scripts/package-testlab.sh VERSION}
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.[0-9][0-9]$ ]]; then
  echo "version must be MAJOR.MINOR with a two-digit minor (for example 0.20)" >&2
  exit 2
fi
./scripts/validate.sh
stage="dist/x4_gunnery_control_testlab"
rm -rf "$stage"
mkdir -p "$stage"
cp -R testlab/x4_gunnery_control_testlab/. "$stage/"
cp TESTING.md LICENSE "$stage/"
mkdir -p dist
archive="dist/x4_gunnery_control_testlab-v${version}.zip"
rm -f "$archive"
(cd dist && zip -qr "$(basename "$archive")" x4_gunnery_control_testlab)
echo "$archive"
