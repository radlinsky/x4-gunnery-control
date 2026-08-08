#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib-release.sh
source scripts/lib-release.sh
# The Test Lab zip is named after the main extension's version it was built
# against; no argument means "the current one".
version=${1:-$(content_xml_version_dotted)}
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
