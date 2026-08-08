#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib-release.sh
source scripts/lib-release.sh

version=${1:?usage: scripts/package-workshop.sh VERSION}
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

if [[ -z "${X4GC_SKIP_VALIDATE:-}" ]]; then
  ./scripts/validate.sh
else
  # The escape hatch exists only for tests/test_package_workshop.sh, which
  # validate.sh itself runs — without it the two would recurse. Say so loudly:
  # publishing an unvalidated build to the Workshop is not recoverable quietly.
  echo "WARNING: X4GC_SKIP_VALIDATE set; staging WITHOUT running validate.sh." >&2
fi

# ponytail: staging exists because WorkshopTool mutates the folder it is given —
# on a successful publish it rewrites the id attribute in content.xml with a
# numeric Workshop-specific id, and update reads that id back.  Pointing
# WorkshopTool at the repo directly would overwrite our tracked content.xml.
stage="dist/workshop/x4_gunnery_control"
rm -rf "$stage"
mkdir -p "$stage"
copy_extension_files "$stage"

# --- preview image ---
# Steam accepts JPG or PNG, so take whichever is present rather than forcing a
# conversion; ours is a PNG screenshot.  It is NOT copied into the stage: -preview
# takes any path, and anything inside the stage is packed into the shipped
# catalog, where half a megabyte of screenshot has no business being.
preview=""
for cand in release/preview.jpg release/preview.png; do
  [[ -f "$cand" ]] && { preview="$(pwd)/$cand"; break; }
done
if [[ -z "$preview" ]]; then
  echo "WARNING: no release/preview.jpg or release/preview.png found." >&2
  echo "  The Steam Workshop requires a preview image (JPG or PNG, 640x360 or larger)." >&2
  echo "  Place the image at release/preview.png and re-run, or supply it manually before publishing." >&2
fi

# --- optional Workshop id substitution in the STAGED content.xml only ---
id_file="release/workshop-id.txt"
staged_content="$stage/content.xml"
if [[ -f "$id_file" ]]; then
  workshop_id=$(tr -d '[:space:]' < "$id_file")
  if [[ -n "$workshop_id" ]]; then
    # Replace the id="..." attribute on the <content ...> line in the staged copy
    # only. The repo's content.xml is never touched. The /<content /  address is
    # load-bearing: without it sed also rewrites the id of every <dependency>,
    # which would make the Workshop build depend on itself and silently drop the
    # kuertee UI Extensions dependency.
    sed -i "/<content /s/ id=\"[^\"]*\"/ id=\"$workshop_id\"/" "$staged_content"
  fi
fi

# --- rewrite the kuertee dependency to its Workshop counterpart ---
# WorkshopTool refuses to publish an extension whose content.xml depends on
# anything that is not itself a Workshop item:
#   "ERROR: There are dependencies on non-Workshop extensions"
# and it refuses even for optional="true" dependencies.  Our dependency names
# kuertee's Nexus id, so the staged copy has to name the Workshop
# repackage of the same mod instead -- uploaded by Valador8869/UncommonDLL with
# kuertee's permission, https://steamcommunity.com/workshop/filedetails/?id=3477279743
#
# Workshop-installed extensions carry the id form ws_<workshopid>, not the bare
# number: every Workshop-sourced extension in a real install shows it
# (ws_2042901274 SirNukes Mod Support APIs, ws_3715253556 Options Helper), and
# other mods declare their dependencies that way.
#
# The version attribute is dropped deliberately.  The repackage sets its own
# version integer, which is not ours to predict, and demanding a wrong one would
# block loading for every subscriber.  version is optional on <dependency>;
# kuertee's own mods ship dependency elements without it.
#
# optional="true" mirrors the repo content.xml: a subscriber who installed UI
# Extensions from Nexus instead of the Workshop has the mod but not this id, and
# a hard dependency would disable us for them.  kuertee's own recommendation.
sed -i '/<dependency id="kuerteeUIExtensionsAndHUD"/c\  <dependency id="ws_3477279743" optional="true" name="kuertee UI Extensions and HUD"/>' "$staged_content"
if grep -q 'kuerteeUIExtensionsAndHUD"' "$staged_content"; then
  echo "the kuertee dependency was not rewritten; WorkshopTool would reject this build" >&2
  exit 1
fi

# --- summary ---
staged_abs="$(pwd)/$stage"
# WorkshopTool is a Windows executable, so under WSL the Linux path it would be
# handed is meaningless. Print the Windows form when we can produce one.
if command -v wslpath >/dev/null 2>&1; then
  staged_abs="$(wslpath -w "$staged_abs")"
  [[ -n "$preview" ]] && preview="$(wslpath -w "$preview")"
fi
echo ""
echo "Workshop staging ready: $staged_abs"
echo ""
echo "To publish a new item (first time):"
echo "  WorkshopTool publishx4 -path \"$staged_abs\" -preview \"${preview:-<path to preview image>}\" -buildcat"
echo ""
echo "To update an existing item (after publishing once):"
echo "  WorkshopTool update -path \"$staged_abs\" -buildcat -changenote \"Describe your changes here\""
