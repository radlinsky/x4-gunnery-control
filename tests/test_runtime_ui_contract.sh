#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

main=ui/gunnery_control.lua
persist=ui/gunnery_persistence.lua
testlab=testlab/x4_gunnery_control_testlab/ui/testlab.lua
md=md/x4_gunnery_control.xml

assert_md_xpath() {
  local expected=$1
  local expression=$2
  local description=$3
  local actual
  actual=$(xmllint --xpath "$expression" "$md")
  if [[ "$actual" != "$expected" ]]; then
    echo "$description: expected $expected, found $actual" >&2
    exit 1
  fi
}

if grep -q 'releaseFrameHandle' "$main" "$testlab"; then
  echo "obsolete releaseFrameHandle call found" >&2
  exit 1
fi

# The ffi.cdef block is C, not Lua. A -- comment inside it aborts the whole file
# at load, and no Lua test can see it because every test stubs ffi away.
for f in "$main" "$testlab"; do
  if awk '/ffi\.cdef *\[\[/,/^\]\]/' "$f" | grep -Eq '^[[:space:]]*--'; then
    echo "Lua -- comment inside the ffi.cdef block of $f; C needs /* */" >&2
    exit 1
  fi
done

grep -Fq 'frame:display()' "$main"
grep -Fq 'frame:display()' "$testlab"
grep -Fq 'controlGroup() == "gunnercontrol"' "$main"
if grep -Fq 'controlGroup() == "gunnertrigger"' "$main"; then
  echo "cockpit trigger tag used as runtime control group" >&2
  exit 1
fi
grep -Fq 'C.GetContextByClass(C.GetPlayerID(), "container", false)' "$main"
grep -Fq 'C.IsComponentClass(ship, "ship")' "$main"
# A frame that hides the HUD never gets it back: only the fullscreen console
# (no playerControls) may do so, and it does that by being the non-targetBrowser
# case of keepHUDVisible = targetBrowser.
if grep -Fq 'keepHUDVisible = false' "$main"; then
  echo "no frame may set keepHUDVisible = false; the HUD is not restored afterwards" >&2
  exit 1
fi
# Every frame must agree on it; a browser(true) -> console(false) sequence
# leaves the standing player with no HUD.
hud_true=$(grep -c 'keepHUDVisible = true' "$main")
if [ "$hud_true" -ne 3 ]; then
  echo "all 3 frames must set keepHUDVisible = true; found $hud_true" >&2
  exit 1
fi
grep -Fq 'showTickerPermanently = false' "$main"
grep -Fq 'State.beginTargetSelection(session, group, member)' "$main"
grep -Fq 'GetContainedShips' "$main"
grep -Fq 'readSurfaceTargets' "$main"
grep -Fq 'RegisterEvent("X4GunneryControl.EngageabilityResult", onEngageabilityResult)' "$main"
grep -Fq 'RegisterEvent("X4GunneryControl.EngageabilityBatchComplete", onEngageabilityBatchComplete)' "$main"
grep -Fq 'AddUITriggeredEvent("X4GunneryControl", "engageability_member"' "$main"
grep -Fq 'AddUITriggeredEvent("X4GunneryControl", "engageability_target"' "$main"
grep -Fq 'State.checkedGroups(session)' "$main"
assert_md_xpath "1" "count(//cue[@name='EngageabilityService'])" "engageability service cue count"
# The own-hull-aware muzzle-origin probe fires twice: once at the target root,
# then (issue #60) as the per-module fallback when a large ship/station root's
# bbox-centre aim point self-blocks the ray. Both keep the barrel offset and
# excludeself='false' so the firing ship's own hull can mask the shot.
assert_md_xpath "1" "count(//check_line_of_sight[@object='\$weapon'][@objectoffset='\$weapon.barrelposition'][@excludeself='false'][@useaimtarget='true'][@target='\$target'])" "engageability service root muzzle-origin line-of-fire check count"
assert_md_xpath "1" "count(//check_line_of_sight[@object='\$weapon'][@objectoffset='\$weapon.barrelposition'][@excludeself='false'][@useaimtarget='true'][@target='\$module'])" "engageability service module-fallback muzzle-origin line-of-fire check count"
assert_md_xpath "1" "count(//raise_lua_event[@name=\"'X4GunneryControl.EngageabilityResult'\"])" "engageability result event count"
assert_md_xpath "1" "count(//raise_lua_event[@name=\"'X4GunneryControl.EngageabilityBatchComplete'\"])" "engageability batch-complete event count"
grep -Fq "EngageabilityService.\$targetids.{\$targetindex} + ':' + \$engageable + ':' + \$known + ':' + EngageabilityService.\$expectedmembers" "$md"
grep -Fq "\$target.relativeposition.{\$weapon}.rotation.pitch" "$md"
grep -Fq "EngageabilityService.\$arcmins.{\$weaponindex} * 1deg" "$md"
grep -Fq "EngageabilityService.\$arcmaxs.{\$weaponindex} * 1deg" "$md"
# Issue #54 Task 2: the firing-range gate mirrors shipped combat-AI
# reachability — bounding-box distance, no size term
# (move.attack.object.capital.xml:656,680; md-ai.md).
# The negative is scoped to the old EngageabilityService weapon-reach
# predicate — point distance plus half the target's size, the
# asteroid-mining approach form. Unrelated point-distance calculations
# elsewhere in this MD (e.g. camera framing) stay legal.
grep -Fq "\$weapon.bboxdistanceto.{\$target} le \$weapon.maxfirerange" "$md"
if grep -Eq "\\\$weapon\.distanceto\.\{\\\$target\}[[:space:]]*\+[[:space:]]*\(?[[:space:]]*\\\$target\.size[[:space:]]*/[[:space:]]*2" "$md"; then
  echo "production MD reintroduced the point-distance (distanceto + target.size/2) firing-range predicate" >&2
  exit 1
fi
assert_md_xpath "1" "count(//check_line_of_sight[parent::do_if[contains(@value, 'bboxdistanceto')][contains(@value, 'aimpitch')]])" "arc and range rejection wrap line-of-fire check"
assert_md_xpath "1" "count(//cue[@name='EngageabilityMember']//do_if[contains(@value, '\$nonce == EngageabilityService.\$nonce')][contains(@value, 'weapons.count lt')][contains(@value, 'not EngageabilityService.\$weapons.indexof')])" "member nonce/count/duplicate guards"
assert_md_xpath "1" "count(//cue[@name='EngageabilityTarget']//do_if[contains(@value, '\$nonce == EngageabilityService.\$nonce')][contains(@value, 'targets.count lt')][contains(@value, 'not EngageabilityService.\$targets.indexof')])" "target nonce/count/duplicate guards"
grep -Fq "[@event.param3.\$targets, 20].min" "$md"
grep -Fq 'Helper.clearDataForRefresh(menu)' "$main"
grep -Fq 'State.surfaceAlternatives(allSurfaces, pinnedID,' "$main"
grep -Fq 'State.surfaceMacroOptions(allSurfaces, session.surfaceTypeFilter)' "$main"
grep -Fq 'local elemRefresh = elemTable:addRow("surface_refresh", {})' "$main"
grep -Fq 'local surfaceCrossTypePolicy = "size_first"' "$main"
grep -Fq 'State.surfacePage(ordered, browser.page, browser.pageSize)' "$main"
grep -Fq 'State.surfacePageKey(browser.generation, pageEntries)' "$main"
grep -Fq 'requestEngageability(pinnedID, "surface_pinned")' "$main"
grep -Fq 'requestEngageabilities(pageIDs, "surface_page")' "$main"
grep -Fq 'local parentHullRow = elemTable:addRow("surface_parent_hull", {})' "$main"
grep -Fq 'local autoRefreshRow = elemTable:addRow("surface_auto_refresh", {})' "$main"
grep -Fq 'browser.nextAutoRefreshAt = browser.autoRefresh and (getElapsedTime() + 10) or nil' "$main"
grep -Fq 'menu.elementFrame:update()' "$main"
grep -Fq 'returnToConsole("Watch closed")' "$main"
grep -Fq 'openTargetBrowser()' "$main"
grep -Fq 'softtargetKey() ~= previousTarget' "$main"
grep -Fq 'isEligibleEngagementTarget(current.softtargetID)' "$main"
grep -Fq 'State.turretGroupLabel(entry.group)' "$main"
grep -Fq 'State.isEngagementTargetAllowed(session and session.shipID, object)' "$main"
grep -Fq 'local activeExternalMenuName' "$main"
grep -Fq 'activeExternalMenuName = function()' "$main"
grep -Fq 'State.lifecycle.suspendingMap' "$main"
grep -Fq 'sameSession(expectedSession, expectedEpoch)' "$main"
grep -Fq 'currentSession(expectedSession, expectedEpoch)' "$main"
grep -Fq 'sessionEpoch = sessionEpoch + 1' "$main"
if grep -Eq '^[[:space:]]*Helper\.clearMenu\(menu\)' "$main"; then
  echo "raw clearMenu bypasses X4 tracked-menu cleanup" >&2
  exit 1
fi
grep -Fq 'local function sessionWatchdog()' "$main"
grep -Fq 'reopenSuspendedSession("returned to " .. tostring(mode))' "$main"
grep -Fq 'State.lifecycle.suspendedMap' "$main"
grep -Fq 'map.registerCallback("on_menu_cleanup"' "$main"
grep -Fq 'externalMenu == "MapMenu" and State.isOwned(session)' "$main"
grep -Fq 'C.SetTrackedMenuFullscreen(menu.name, false)' "$main"
grep -Fq 'bool IsGamePaused(void)' "$main"
# Phase rename: "watch"/"direct" are gone; "engaged" + controlMode replace them.
grep -Fq 'session.phase == "engaged"' "$main"
grep -Fq 'session.controlMode' "$main"
# New lifecycle entry point replaces beginWatch/beginDirect.
grep -Fq 'State.beginEngaged' "$main"
# Baseline: directSnapshots renamed to committedBaseline; staged buffer added.
grep -Fq 'committedBaseline' "$main"
grep -Fq 'session.staged' "$main"
# The adapter commits one atomic table. Its session half remains an encoded
# string because raise_lua_event returns only one scalar; the paired component
# target travels separately and is buffered before control receives an envelope.
grep -Fq 'State.encode(deps.State.saveState(session))' "$persist"
grep -Fq 'deps.emit("session_commit", payload)' "$persist"
grep -Fq 'x4gc1:&lt;nonce&gt;:&lt;generation&gt;' md/x4_gunnery_control.xml
grep -Fq "param=\"'x4gc1:' + State.\$requestNonce + ':' + State.\$generation\"" md/x4_gunnery_control.xml
grep -Fq "State.\$acceptedNonce == State.\$requestNonce" md/x4_gunnery_control.xml
grep -Fq 'deps.emit("state_request", { nonce = nonce })' "$persist"
grep -Fq 'deps.emit("state_accept", { nonce = grantedRequestNonce, generation = grantedGeneration })' "$persist"
grep -Fq 'State.decode(envelope and envelope.payload)' "$main"
# The restore resolves group contextIDs, which needs a seated player. A save
# taken while engaged reloads into the chair, so the gameLoadingDone raise is
# what normally does the work; the chair-ingress raise is the fallback that
# collects the payload if it ever lands with the player off the console.
# gameLoadingDone uses request(true) to force a new request, abandoning the dead
# pre-load one; init and chair ingress use unforced request().
if [ "$(grep -Fc 'persistence.request()' "$main")" -lt 2 ]; then
  echo 'persistence request must be raised at init and at chair ingress (unforced)' >&2
  exit 1
fi
if ! grep -Fq 'persistence.request(true)' "$main"; then
  echo 'persistence request must be raised at gameLoadingDone with force=true' >&2
  exit 1
fi
# Ensure the old single-phase strings are gone — any hit is a residual bug.
if grep -Fq 'session.phase == "watch"' "$main"; then
  echo 'residual session.phase == "watch" found in main file' >&2
  exit 1
fi
if grep -Fq 'session.phase == "direct"' "$main"; then
  echo 'residual session.phase == "direct" found in main file' >&2
  exit 1
fi
# Shape, not value: a dated build id must exist so a debug log identifies the
# build. Pinning the literal only forced a test edit on every bump.
grep -Eq 'local runtimeBuild = "[0-9]{4}-[0-9]{2}-[0-9]{2}-[^"]+"' "$main"
grep -Fq 'UI initialized; build=" .. runtimeBuild' "$main"

for removed_log in \
  'watchdog state changed' \
  'raw group id carries padding' \
  'restore engine soft target before write' \
  'notify emitted:' \
  'repainted console after restore:' \
  'registered DockedMenu redirect hook' \
  'registered MapMenu cleanup hook'; do
  if grep -Fq "$removed_log" "$main"; then
    echo "removed default telemetry remains: $removed_log" >&2
    exit 1
  fi
done

grep -Fq 'orphaned menu detected by watchdog' "$main"
grep -Fq 'engagement transition confirmed by frame creation' "$main"
grep -Fq 'standardButtons = { back = true, close = true }' "$main"
# Console group/member name cells span columns 2-4. Turret group labels carry a
# location and a name and get truncated at one eighth of the table width. The
# smoke tests cannot see this: their table stub returns a generic cell for any
# index and ignores setColSpan, so this grep is the only guard.
grep -Fq 'row[2]:setColSpan(3):createText(label' "$main"
grep -Fq 'memberRow[2]:setColSpan(3):createText("  " .. member.displayName)' "$main"
grep -Fq 'viewFrame.properties.height = controls.properties.y + controls:getVisibleHeight() + 2 * Helper.borderSize' "$main"
grep -Fq 'endSession("global movement event")' "$main"
grep -Fq 'endSession("left chair or ship")' "$main"
grep -Fq 'C.SetPlayerCameraCockpitView(true)' "$main"
if grep -Fq 'mode ~= "cockpit" and mode ~= "external"' "$main"; then
  echo "gameplan changes still discard a seated gunnery session" >&2
  exit 1
fi
grep -Fq 'Helper.closeMenu(menu, "close", false, false)' "$main"
if grep -Fq 'Helper.closeMenu(menu, "back", nil, false)' "$main"; then
  echo "camera view still uses auto-returning menu close" >&2
  exit 1
fi
grep -Fq 'Helper.closeMenuAndOpenNewMenu(docked, "X4GunneryMenu"' "$main"
grep -Fq 'local function registerUIHooks()' "$main"
grep -Fq 'if isInGunnerChair() and not menu.shown and not activeExternalMenuName()' "$main"
grep -Fq 'redirectDockedMenu()' "$main"
grep -Fq 'Helper.closeMenuAndOpenNewMenu(main, "X4GunneryTestLab"' "$testlab"

grep -Fq 'local seatLeaving = false' "$main"
grep -Fq 'if not seatLeaving then C.SetPlayerCameraCockpitView(true) end' "$main"
if grep -A20 'local function discardSession' "$main" | grep -Fq 'C.SetPlayerCameraCockpitView(true)' && \
   ! grep -A20 'local function discardSession' "$main" | grep -Fq 'if not seatLeaving then C.SetPlayerCameraCockpitView(true) end'; then
  echo "unguarded C.SetPlayerCameraCockpitView(true) found inside discardSession" >&2
  exit 1
fi
grep -Fq 'seatLeaving = true' "$main"

grep -Fq 'cutscene_aim_start' "$main"
grep -Fq 'cutscene_aim_stop' "$main"
grep -Fq 'cutscene_aim_start' "$md"
grep -Fq 'cutscene_aim_stop' "$md"
grep -Fq 'play_cutscene' "$md"
grep -Fq 'stop_cutscene' "$md"
grep -Fq 'cinematicmode' "$md"
# The destroyed-object event source is evaluated when its cue activates. Keep
# it below a null-safe gate: on fresh MD init there is no CutsceneAim.$Target.
# Start re-arms exactly one watcher after normalizing the target. Stop clears
# and cancels it. A queued event for the previous target is harmless because
# the destructive actions compare event.object with the current target.
cutscene='/mdscript/cues/cue[@name="CutsceneAim"]'
watch="$cutscene/cues/cue[@name=\"TargetWatch\"]"
start="$cutscene/cues/cue[@name=\"Start\"]"
stop="$cutscene/cues/cue[@name=\"Stop\"]"
destroyed="$watch/cues/cue[@name=\"WatchedTargetDestroyed\"]"
guard="$destroyed/actions/do_if[@value=\"CutsceneAim.\$Target? and event.object == CutsceneAim.\$Target\"]"
handle_guard="CutsceneAim.\$Handle? and CutsceneAim.\$Handle != null"
assert_md_xpath 1 "count($watch)" 'CutsceneAim must have exactly one TargetWatch'
assert_md_xpath 0 "count($cutscene/cues/cue[@name=\"TargetDestroyed\"])" \
  'TargetDestroyed must not activate as a direct CutsceneAim child'
assert_md_xpath 0 "count(//cue[@name=\"TargetDestroyed\"])" \
  'The saved TargetDestroyed cue name must not be reused after moving the watcher'
assert_md_xpath cancel "string($watch/@onfail)" 'TargetWatch must cancel when its target gate fails'
assert_md_xpath 1 "count($watch/conditions/check_value[@value=\"CutsceneAim.\$Target? and typeof CutsceneAim.\$Target == datatype.component\"])" \
  'TargetWatch must require an existing component target'
assert_md_xpath 1 "count($destroyed/conditions/event_object_destroyed[@object=\"CutsceneAim.\$Target\"])" \
  'TargetDestroyed must listen to the gated target'
assert_md_xpath 0 "count(${destroyed}[@instantiate])" \
  'TargetDestroyed must remain one-shot under its per-target parent'
assert_md_xpath reset_cue "name(($start/actions/*)[last()])" \
  'Start must finish by re-arming TargetWatch'
assert_md_xpath TargetWatch "string(($start/actions/*)[last()]/@cue)" \
  'Start must re-arm TargetWatch'
assert_md_xpath 1 "count($start/actions/play_cutscene/following-sibling::reset_cue[@cue=\"TargetWatch\"])" \
  'Start must re-arm TargetWatch after starting the cutscene'
assert_md_xpath reset_cue "name(($stop/actions/*)[last()])" \
  'Stop must finish by cancelling TargetWatch'
assert_md_xpath TargetWatch "string(($stop/actions/*)[last()]/@cue)" \
  'Stop must cancel TargetWatch'
assert_md_xpath 1 "count($stop/actions/remove_value[@name=\"CutsceneAim.\$Target\"][following-sibling::reset_cue[@cue=\"TargetWatch\"]])" \
  'Stop must clear the target before cancelling TargetWatch'
assert_md_xpath 1 "count($guard)" \
  'TargetDestroyed must reject queued events for a stale target'
assert_md_xpath 3 "count(//stop_cutscene[@cutscene=\"CutsceneAim.\$Handle\"])" \
  'CutsceneAim must retain exactly its three cutscene-stop paths'
assert_md_xpath 1 "count($start/actions/do_if[@value=\"$handle_guard\"]/stop_cutscene[@cutscene=\"CutsceneAim.\$Handle\"])" \
  'Start must declaration-check the current cutscene handle before stopping it'
assert_md_xpath 1 "count($stop/actions/do_if[@value=\"$handle_guard\"]/stop_cutscene[@cutscene=\"CutsceneAim.\$Handle\"])" \
  'Stop must declaration-check the current cutscene handle before stopping it'
assert_md_xpath 1 "count($guard/do_if[@value=\"$handle_guard\"]/stop_cutscene[@cutscene=\"CutsceneAim.\$Handle\"])" \
  'Only the current target destruction may stop the cutscene'
assert_md_xpath 1 "count($guard/remove_value[@name=\"CutsceneAim.\$Target\"])" \
  'TargetDestroyed must disarm the handled target'
assert_md_xpath 1 "count($guard/reset_cue[@cue=\"parent\"] \
  [preceding-sibling::remove_value[@name=\"CutsceneAim.\$Target\"]])" \
  'TargetDestroyed must cancel its parent watcher after handling the target'
# Notify cue: load-bearing popup that cures the dead-Esc engine bug by forcing
# View.createView/DisplayView in ego_viewhelper. show_help with a custom
# expression is the mechanism; event.param3.$text carries the Lua string.
grep -Fq "cue name=\"Notify\"" "$md"
grep -Fq 'show_help' "$md"
grep -Fq "custom=\"@event.param3.\$text\"" "$md"
# Text ids 79 (restored-settings) and 80 (disengaged) used by leaveChair.
grep -Fq '<t id="79">' t/0001.xml
grep -Fq '<t id="80">' t/0001.xml
# Transport contract (live-tested 2026-08-04, final): the engine PREPENDS $ to
# every Lua string key during Lua->MD conversion, so Lua "anchor" arrives as
# the MD variable key $anchor, read via event.param3.$anchor. Never pre-prefix
# $ in Lua (it becomes the unreadable $$anchor). Ids go through
# ConvertStringToLuaID and the reads keep the null-tolerant @ prefix. The $ is
# a literal MD sigil, not a shell expansion; double-quoted and escaped for ShellCheck.
grep -Fq "event.param3.\$anchor" md/x4_gunnery_control.xml
grep -Fq "event.param3.\$target" md/x4_gunnery_control.xml
grep -Fq 'ConvertStringToLuaID' "$main"
# Framing (live-tested 2026-08-04): anchordist=0 puts the camera inside the
# anchor's hull. Vanilla idiom (cinematiccamera.xml:2504) is a NEGATIVE
# distance of anchor.size + margin so the camera sits behind the anchor along
# the anchor->target axis with the anchor fully in frame.
grep -Fq "number=\"-CutsceneAim.\$Dist\"" md/x4_gunnery_control.xml
# Per-POV framing tune (round 5): Sit@Turret wants a close camera (~3m class),
# Sit@Target keeps size + 50m; both need a lateral/vertical offset so the
# anchor is not dead-center on the camera->target sight line.
grep -Fq "CutsceneAim.\$Pov" md/x4_gunnery_control.xml
grep -Fq "number=\"CutsceneAim.\$Dist * 0.4\"" md/x4_gunnery_control.xml
# Shoulder-cam experiment: the asset cutscenes/x4gc_shoulder_cam.xml exists but
# is deliberately UNWIRED (no MD cue, not in install/package). Sit@Turret
# perpendicular-aim clipping is deferred; see docs/goals/engage-camera-aim.md.
# Its contract checks are intentionally absent until that work resumes.
grep -Fq 'X4GC_Shoulder_Cam' cutscenes/x4gc_shoulder_cam.xml

# Steps 6-9: console checkboxes, live view, retarget, new text ids.
# Group row checkbox wired to session.checkedGroupKeys via State.toggleGroup.
grep -Fq 'createCheckBox' "$main"
grep -Fq 'State.toggleGroup' "$main"
# Camera roster drives Next/Prev and is queried to gate those buttons.
grep -Fq 'State.cameraRoster' "$main"
# Turret cycling is the only way to move through a multi-member roster.
grep -Fq 'State.cycleCamera' "$main"
# applyPov() replaces the old applyEngagePov/setEngagePov pair. It is declared
# as a forward reference and assigned after sendCutsceneAimStart/Stop.
grep -Fq 'applyPov' "$main"
# Auto-retarget: chooseAimTarget picks the nearest operational hostile.
grep -Fq 'local function chooseAimTarget' "$main"
# povMode and aimTargetID are live session fields used in the UI and retarget.
grep -Fq 'session.povMode' "$main"
grep -Fq 'session.aimTargetID' "$main"

# Auto-next Target lives on the compact direct-control panel and decides what
# happens when the engaged object dies: re-engage, or reset the view and hand
# the choice back at the target browser.
grep -Fq 'session.autoNextTarget' "$main"

# The soft target is X4's global selection. enterCamera borrows it; SetSofttarget(0)
# is not a clear (no vanilla call ever passes 0), so an empty one must be restored
# with RemoveSofttarget() or the player is left targeting their own turret.
grep -Fq 'RemoveSofttarget()' "$main"
grep -Fq 'restoreSofttarget(savedTargetID, savedConnection)' "$main"
grep -Fq 'clearOwnShipSofttarget()' "$main"
if grep -Eq 'C\.SetSofttarget\(savedTargetID' "$main"; then
  echo 'enterCamera restores the soft target directly again; route it through restoreSofttarget()' >&2
  exit 1
fi
# A UniverseID out of the FFI is boxed cdata: tostring() gives "0ULL", so
# tostring(x) == "0" is false for a null id and the guard never fires in game.
# No Lua test can catch this -- every harness stubs ids as plain numbers, where
# tostring(0) really is "0" -- so this grep is the only guard. Use isNullID().
for f in "$main" ui/gunnery_state.lua "$testlab"; do
  if grep -nE 'tostring\([^()]*\)[[:space:]]*[=~]=[[:space:]]*"0"' "$f" | grep -vq '^[0-9]*:[[:space:]]*--'; then
    echo "null-id check by tostring in $f; \"0ULL\" slips through -- use State.isNullID()" >&2
    exit 1
  fi
done
grep -Fq 'onDirectTargetLost' "$main"
grep -Fq 'autoNextRow[1]:createCheckBox' "$main"
grep -Fq 'autoNextRow[2]:createText(text(78))' "$main"
grep -Fq '<t id="78">' t/0001.xml
# GetComponentData needs a ConvertStringTo64Bit'd id; a raw UniverseID silently
# returns nil for every key, which made every relation read as Neutral. Every
# read must go through the componentData() wrapper, so the raw engine call may
# appear exactly once (inside the wrapper itself).
grep -Fq 'local function componentData' "$main"
raw_calls=$(grep -c 'GetComponentData(' "$main")
if [ "$raw_calls" -ne 1 ]; then
  echo "GetComponentData must only be called from componentData(); found $raw_calls call sites" >&2
  exit 1
fi
# NEGATIVE: per-member Watch/Engage wiring from member rows must be gone.
# Previously startAutoEngage and startTargetSelection were called from member
# row handlers; they must now only be called from the bottom action row.
if grep -n 'memberRow' "$main" | grep -Eq '(startAutoEngage|startTargetSelection)'; then
  echo "per-member Watch/Engage button wiring still exists in member rows" >&2
  exit 1
fi

# Task 2: cycleEntry and cycleTarget
grep -Fq 'State.cycleEntry' "$main"
grep -Eq '(local function cycleTarget|local [a-zA-Z_, ]*cycleTarget|cycleTarget = function)' "$main"
# Task 4: element frame for target display, unregistered when it goes away
grep -Fq 'menu.elementFrame' "$main"
grep -Fq 'Helper.clearFrame(menu, elementFrameLayer)' "$main"
# Select-all checkbox over the group column.
grep -Fq 'State.toggleAllGroups(session)' "$main"
grep -Fq 'State.allGroupsChecked(session)' "$main"
# Every frame gets a semi-transparent background so cell text stays legible.
bg_calls=$(grep -c 'setBackground("solid"' "$main")
if [ "$bg_calls" -ne 3 ]; then
  echo "all 3 frames must set a semi-transparent background; found $bg_calls" >&2
  exit 1
fi
# Teardown order: Helper.closeMenu() untracks the menu before its views are
# unregistered. Unregistering first left the engine ignoring Esc after a session
# that had opened a playerControls frame.
if grep -Eq 'Helper\.clearFrame\(menu, layer\)' "$main"; then
  echo "teardown unregisters views itself again; that must happen inside Helper.closeMenu" >&2
  exit 1
fi

# Color names resolve at runtime: one the game does not define only shows up as
# "Tried to access non-existing color" spam in the log, once per display().
# Every name below was checked against the 9.00 UI source.
known_colors=(frame_background_semitransparent row_background_unselectable
  row_title_background text_error text_inactive text_normal)
unknown=$(grep -o 'Color\["[a-z_0-9]*"\]' "$main" | sed 's/.*\["//;s/"\]//' | sort -u \
  | grep -vxF -f <(printf '%s\n' "${known_colors[@]}") || true)
if [ -n "$unknown" ]; then
  echo "unknown color(s) in $main: $unknown; verify each against the vanilla UI source" >&2
  exit 1
fi

# Task 1: target_detail must be gone
if grep -Fq 'target_detail' "$main"; then
  echo "target_detail still present in $main" >&2
  exit 1
fi

grep -Fq 'SetPlayerCameraCockpitView' "$main"

# The mode-filter rule that used to live here was inverted on 2026-08-10: the
# ship-wide override now reaches every turret whatever its mode. Its replacement,
# and the per-cue split that keeps DirectFallback scoped, live in
# tests/test_turret_targets_contract.sh, which is where every other
# set_turret_targets structural rule already was.

# Issue #48 Task 2: the console Direct-control mode selector reuses the
# vanilla Helper.turretModes option entries (labels never hardcoded), and a
# selector change routes through State.setDirectMode -- staged, no live writes.
grep -Fq 'Helper.turretModes' "$main"
grep -Fq 'State.setDirectMode(session, value)' "$main"
grep -Fq 'tableView:addRow("direct_mode", {})' "$main"
grep -Fq '<t id="101">' t/0001.xml
grep -Fq '<t id="102">' t/0001.xml
# Issue #48 Task 3: the engaged Direct-control panel carries the same selector
# (label + dropdown in the 2-column controls table) and applies the policy to
# the checked groups' live modes immediately.
grep -Fq 'controls:addRow("direct_mode", {})' "$main"
grep -Fq 'applyDirectModeLive()' "$main"

echo "runtime UI contract checks passed"
