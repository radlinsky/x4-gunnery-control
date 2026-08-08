#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

skill=.agents/skills/research-x4-modding
scripts="$skill/scripts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
dollar='$'

grep -Fxq 'name: research-x4-modding' "$skill/SKILL.md"
grep -Eq '^description: .+' "$skill/SKILL.md"
if rg -n 'TODO' "$skill"; then
  echo 'skill still contains TODO markers' >&2
  exit 1
fi
for classification in documented-public shipped-source third-party-technique inference live-tested; do
  grep -Fq "\`$classification\`" "$skill/SKILL.md"
done
grep -Fq 'X4: 9.00' "$skill/references/ui-lua-menu-camera.md"
grep -Fq 'gunnercontrol' "$skill/references/ui-lua-menu-camera.md"
grep -Fq 'GetContainedShips' "$skill/references/ui-lua-menu-camera.md"
grep -Fq 'mayattack' "$skill/references/md-ai.md"
grep -Fq 'XTools_1.11.zip!Readme.txt' "$skill/references/tooling.md"
grep -Fq 'documented-public' "$skill/references/tooling.md"
grep -Fq 'SKILL_DIR=.agents/skills/research-x4-modding' "$skill/SKILL.md"
grep -Fq 'search-x4.sh" --dry-run -- PATTERN' "$skill/SKILL.md"
skill_invocation="${dollar}research-x4-modding"
grep -Fq "$skill_invocation" AGENTS.md
grep -Fq 'improve the skill' AGENTS.md
grep -Fq 'Iterate on these' AGENTS.md

for script in discover-x4-roots.sh search-x4.sh index-lua-ffi.sh prepare-xsd-cache.sh extract-selected-xrcat.sh; do
  "$scripts/$script" --help >/dev/null
done

mkdir -p "$tmp/game" "$tmp/extracted/ui" "$tmp/extensions/example" "$tmp/schema/md" "$tmp/schema/libraries"
: >"$tmp/game/08.cat"
printf 'ffi.cdef[[\nbool ExampleAPI(int value);\n]]\n' >"$tmp/extracted/ui/example.lua"
printf 'ffi.cdef[[\nbool ExampleXplAPI(int value);\n]]\n' >"$tmp/extracted/ui/example.xpl"
printf 'extension needle\n' >"$tmp/extensions/example/source.lua"
printf '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"><xs:include schemaLocation="../libraries/md.xsd"/></xs:schema>\n' >"$tmp/schema/md/md.xsd"
printf '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"><xs:include schemaLocation="common.xsd"/></xs:schema>\n' >"$tmp/schema/libraries/md.xsd"
printf '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"/>\n' >"$tmp/schema/libraries/common.xsd"

roots=$("$scripts/discover-x4-roots.sh" --x4-root "$tmp/game" --extracted-root "$tmp/extracted")
grep -Fqx "x4_root=$tmp/game" <<<"$roots"
grep -Fqx "extracted_root=$tmp/extracted" <<<"$roots"

search_dry=$("$scripts/search-x4.sh" --extracted "$tmp/extracted" --extensions "$tmp/extensions" --dry-run -- needle)
grep -Fqx 'pattern=needle' <<<"$search_dry"
grep -Fqx "root=$tmp/extracted" <<<"$search_dry"
"$scripts/search-x4.sh" --extracted "$tmp/extracted" --extensions "$tmp/extensions" -- needle >/dev/null
search_glob=$("$scripts/search-x4.sh" --extracted "$tmp/extracted" --extensions "$tmp/extensions" -- needle -g '*.lua')
grep -Fq "$tmp/extensions/example/source.lua" <<<"$search_glob"

index_dry=$("$scripts/index-lua-ffi.sh" --source "$tmp/extracted" --dry-run)
grep -Fqx "source=$tmp/extracted" <<<"$index_dry"
ffi_index=$("$scripts/index-lua-ffi.sh" --source "$tmp/extracted")
grep -Fqx "$tmp/extracted/ui/example.lua:2:bool ExampleAPI(int value);" <<<"$ffi_index"
grep -Fqx "$tmp/extracted/ui/example.xpl:2:bool ExampleXplAPI(int value);" <<<"$ffi_index"
"$scripts/index-lua-ffi.sh" --source "$tmp/extracted" --output "$tmp/ffi-index.txt"
grep -Fq 'ExampleAPI' "$tmp/ffi-index.txt"
if "$scripts/index-lua-ffi.sh" --source "$tmp/extracted" --output "$tmp/ffi-index.txt" >/dev/null 2>&1; then
  echo 'FFI index overwrote an existing explicit output' >&2
  exit 1
fi

schema_dry=$("$scripts/prepare-xsd-cache.sh" --source "$tmp/schema" --cache-root "$tmp/cache" --dry-run)
grep -Fqx "destination=$tmp/cache/schema" <<<"$schema_dry"
grep -Fqx 'copy=md/md.xsd' <<<"$schema_dry"
grep -Fqx 'copy=libraries/md.xsd' <<<"$schema_dry"
grep -Fqx 'copy=libraries/common.xsd' <<<"$schema_dry"
relative_schema=$(realpath --relative-to="$PWD" "$tmp/schema")
"$scripts/prepare-xsd-cache.sh" --source "$relative_schema" --cache-root "$tmp/cache"
test -f "$tmp/cache/schema/md/md.xsd"
test -f "$tmp/cache/schema/libraries/common.xsd"
if "$scripts/prepare-xsd-cache.sh" --source "$tmp/schema" --cache-root "$tmp/cache" >/dev/null 2>&1; then
  echo 'schema cache overwrote an existing destination' >&2
  exit 1
fi

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s@" >"%sX4GC_FAKE_ARGS"\n' "$dollar" "$dollar" >"$tmp/fake-xrcat"
chmod +x "$tmp/fake-xrcat"

if "$scripts/extract-selected-xrcat.sh" --tool "$tmp/fake-xrcat" --input "$tmp/game/08.cat" --output "$tmp/no-include" >/dev/null 2>&1; then
  echo 'XRCat wrapper accepted missing include' >&2
  exit 1
fi
mkdir "$tmp/existing-output"
if "$scripts/extract-selected-xrcat.sh" --tool "$tmp/fake-xrcat" --input "$tmp/game/08.cat" --output "$tmp/existing-output" --include '^ui/' >/dev/null 2>&1; then
  echo 'XRCat wrapper accepted an existing output' >&2
  exit 1
fi
if "$scripts/extract-selected-xrcat.sh" --tool "$tmp/fake-xrcat" --input "$tmp/game/08.cat" --output "$tmp/output.cat" --include '^ui/' >/dev/null 2>&1; then
  echo 'XRCat wrapper accepted catalog output' >&2
  exit 1
fi
if "$scripts/extract-selected-xrcat.sh" --tool "$tmp/fake-xrcat" --input "$tmp/game/08.cat" --output / --include '^ui/' >/dev/null 2>&1; then
  echo 'XRCat wrapper accepted broad root output' >&2
  exit 1
fi
if "$scripts/extract-selected-xrcat.sh" --tool "$tmp/fake-xrcat" --append --input "$tmp/game/08.cat" --output "$tmp/append-output" --include '^ui/' >/dev/null 2>&1; then
  echo 'XRCat wrapper accepted append mode' >&2
  exit 1
fi
repo_unsafe="$PWD/research-extract-unsafe-fixture"
if "$scripts/extract-selected-xrcat.sh" --tool "$tmp/fake-xrcat" --input "$tmp/game/08.cat" --output "$repo_unsafe" --include '^ui/' >/dev/null 2>&1; then
  echo 'XRCat wrapper accepted a tracked repository output' >&2
  exit 1
fi
if X4GC_X4_ROOT="$tmp/game" "$scripts/extract-selected-xrcat.sh" --tool "$tmp/fake-xrcat" --input "$tmp/game/08.cat" --output "$tmp/game/extract" --include '^ui/' >/dev/null 2>&1; then
  echo 'XRCat wrapper accepted X4 installation output' >&2
  exit 1
fi

mkdir "$tmp/zip-source"
cp "$tmp/fake-xrcat" "$tmp/zip-source/XRCatTool.exe"
printf 'verified fixture\n' >"$tmp/zip-source/Readme.txt"
zip -j -q "$tmp/tool.zip" "$tmp/zip-source/XRCatTool.exe" "$tmp/zip-source/Readme.txt"

dry_tool_cache="$tmp/dry-tool-cache"
dry_command=$("$scripts/extract-selected-xrcat.sh" --tool-zip "$tmp/tool.zip" --tool-cache "$dry_tool_cache" --input "$tmp/game/08.cat" --output "$tmp/dry-output" --include '^ui/' --exclude '^assets/' --dry-run)
grep -Fq 'prepare_command=unzip ' <<<"$dry_command"
grep -Fq 'command=' <<<"$dry_command"
test ! -e "$dry_tool_cache"

X4GC_FAKE_ARGS="$tmp/direct-args" "$scripts/extract-selected-xrcat.sh" --tool "$tmp/fake-xrcat" --input "$tmp/game/08.cat" --output "$tmp/direct-output" --include '^ui/' --include '.*\.lua$' --exclude '^assets/'
test -d "$tmp/direct-output"
mapfile -t direct_args <"$tmp/direct-args"
expected=(-in "$tmp/game/08.cat" -out "$tmp/direct-output" -include '^ui/' '.*\.lua$' -exclude '^assets/')
[[ ${direct_args[*]} == "${expected[*]}" ]]

X4GC_FAKE_ARGS="$tmp/zip-args" "$scripts/extract-selected-xrcat.sh" --tool-zip "$tmp/tool.zip" --tool-cache "$tmp/tool-cache" --input "$tmp/game/08.cat" --output "$tmp/zip-output" --include '^md/'
test -d "$tmp/zip-output"
test -f "$tmp/tool-cache/XRCatTool.exe"
test -f "$tmp/tool-cache/Readme.txt"
test -x "$tmp/tool-cache/XRCatTool.exe"
grep -Fqx -- '-include' "$tmp/zip-args"
grep -Fqx '^md/' "$tmp/zip-args"

if git ls-files | rg -q '(^|/)(\.x4-research-cache/|[^/]+\.(cat|dat)$)'; then
  echo 'cache, catalog, or data artifact is tracked' >&2
  exit 1
fi

echo 'research X4 skill checks passed'
