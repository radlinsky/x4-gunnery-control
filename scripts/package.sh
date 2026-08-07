#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib-release.sh
source scripts/lib-release.sh
version=${1:?usage: scripts/package.sh VERSION}
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.[0-9][0-9]$ ]]; then
  echo "version must be MAJOR.MINOR with a two-digit minor (for example 0.20)" >&2
  exit 2
fi
arg_int=$(x4_version_int "$version")
xml_int=$(content_xml_version)
if [[ "$arg_int" != "$xml_int" ]]; then
  echo "version mismatch: argument $version -> $arg_int but content.xml version=\"$xml_int\"" >&2
  exit 2
fi
./scripts/validate.sh
stage="dist/x4_gunnery_control"
rm -rf "$stage"
mkdir -p "$stage"
copy_extension_files "$stage"
mkdir -p dist
archive="dist/x4_gunnery_control-v${version}.zip"
rm -f "$archive"
(cd dist && zip -qr "$(basename "$archive")" x4_gunnery_control)
echo "$archive"
