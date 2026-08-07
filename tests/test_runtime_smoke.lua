-- Smoke test: actually execute ui/gunnery_control.lua under stubs.
-- Verifies that load + init() succeed and that sessionWatchdog -> logSession
-- runs without the "attempt to concatenate a function value" class of bug.

-- ── 1. fake ffi ─────────────────────────────────────────────────────────────
local ffiStub = {}
ffiStub.cdef = function() end
ffiStub.string = function(p) return tostring(p) end
ffiStub.new = function(spec, count) return {} end

local C = setmetatable({
    -- Explicit stubs for everything reachable from load path, init, and logSession.
    GetPlayerCurrentControlGroup = function() return "gunnercontrol" end,
    GetPlayerOccupiedShipID      = function() return 0 end,
    GetPlayerID                  = function() return 1 end,
    GetContextByClass            = function(...) return 42 end,
    IsComponentClass             = function(...) return true end,
    GetExternalTargetViewComponent = function() return 7 end,
    IsGamePaused                 = function() return false end,
    GetSofttarget2               = function()
        return { softtargetID = 0, softtargetConnectionName = "" }
    end,
    GetUp                        = function() return true end,
    -- Everything else returns 0 (safe for numeric contexts).
}, { __index = function(t, k) return function(...) return 0 end end })

ffiStub.C = C
package.preload["ffi"] = function() return ffiStub end

-- ── 2. captured log ─────────────────────────────────────────────────────────
local capturedLog = {}
DebugError = function(msg) capturedLog[#capturedLog + 1] = tostring(msg) end

-- Helper to search captured log lines.
local function logContains(pattern)
    for _, line in ipairs(capturedLog) do
        if string.find(line, pattern, 1, true) then return true end
    end
    return false
end

-- ── 3. delayed callbacks (record, never run immediately) ─────────────────────
-- sessionWatchdog re-registers itself via addDelayedOneTimeCallbackOnUpdate.
-- If we ran it immediately we would recurse forever. Record instead.
local pendingCallbacks = {}
-- Tracks the properties table passed to the most recent createFrameHandle call.
local lastFrameProps = nil
-- Counts addTable calls on the most recently created frame.
local addTableCalls = 0
-- Counts total createFrameHandle calls since the last clearDataForRefresh, and
-- keeps every props table so tests can compare frames against each other.
local frameCount = 0
local frameProps = {}
-- Every frame ever created, never reset, as { props = <props>, background = <bool> }.
-- The HUD-restore contract is a property of the whole menu across phases, not of
-- one display() call, so it needs a list that survives clearDataForRefresh.
local allFrames = {}
-- Every button created since the last clearDataForRefresh, as
-- { active = <flag>, text = <label> }. Greying is where the user-visible bugs
-- have been, so the tests need to see it.
local createdButtons = {}
-- Every checkbox created since the last clearDataForRefresh, as { checked = <bool> }.
local createdCheckBoxes = {}
clearedFrames = {}
closeMenuCalls = 0
-- Teardown calls in order, as "clear<layer>" / "close". Ordering is the whole
-- point: helper.lua untracks the menu and only then unregisters its views.
teardownTrace = {}
local function buttonByText(label)
    for _, b in ipairs(createdButtons) do if b.text == label then return b end end
end
local Helper = {
    registerMenu              = function() end,
    clearDataForRefresh       = function() frameCount = 0; frameProps = {}; createdButtons = {}; createdCheckBoxes = {} end,
    -- Layers passed to Helper.clearFrame since the test last reset the list.
    clearFrame                = function(m, layer)
        clearedFrames[#clearedFrames + 1] = layer
        teardownTrace[#teardownTrace + 1] = "clear" .. tostring(layer)
        if m and m.frames then m.frames[layer] = nil end
    end,
    createFrameHandle         = function(menu, props)
        lastFrameProps = props
        addTableCalls = 0
        frameCount = frameCount + 1
        frameProps[frameCount] = props
        local record = { props = props, background = false }
        allFrames[#allFrames + 1] = record
        local frame
        frame = { display = function() end, update = function() end, setBackground = function(self) record.background = true; return self end, properties = setmetatable({}, { __newindex = function(t, k, v) rawset(t, k, v) end, __index = function() return 0 end }), addTable = function() addTableCalls = addTableCalls + 1 return { addRow = function() return setmetatable({}, { __index = function() return { setColSpan = function(t) return t end, createText = function() end, createButton = function(_, props) local entry = { active = (props or {}).active }; createdButtons[#createdButtons + 1] = entry; return { setText = function(_, label) entry.text = label end } end, createCheckBox = function(_, checked) createdCheckBoxes[#createdCheckBoxes + 1] = { checked = checked } end, createDropDown = function() end, handlers = {} } end }) end, getVisibleHeight = function() return 0 end, properties = setmetatable({}, { __index = function() return 0 end }) } end }
        -- helper.lua keys menu.frames by layer; unregisterOwnFrames() walks it.
        menu.frames = menu.frames or {}
        -- helper.lua defaults an omitted layer to Helper.defaultFrameLayer (4).
        menu.frames[props.layer or 4] = frame
        return frame
    end,
    -- Counts Helper.closeMenu calls; the get-up path must defer that one tick.
    closeMenu                 = function(m)
        closeMenuCalls = closeMenuCalls + 1
        teardownTrace[#teardownTrace + 1] = "close"
        -- helper.lua's clearMenu() ends with menu.frames = {}.
        if m then m.frames = {} end
    end,
    getMenu                   = function() return nil end,
    closeMenuAndOpenNewMenu   = function() end,
    getTurretModes            = function() return {} end,
    scaleX                    = function(x) return x end,
    scaleY                    = function(y) return y end,
    viewWidth                 = 1920,
    viewHeight                = 1080,
    borderSize                = 4,
    headerRowCenteredProperties = {},
    addDelayedOneTimeCallbackOnUpdate = function(fn, ...)
        pendingCallbacks[#pendingCallbacks + 1] = fn
    end,
}
_G.Helper = Helper

-- ── 4. other required globals ────────────────────────────────────────────────
Menus            = {}
ReadText         = function(page, id) return "text:" .. tostring(page) .. ":" .. tostring(id) end
RegisterEvent    = function() end
registerForEvent = function() end
getElement       = function() return {} end
AddUITriggeredEvent    = function() end
ConvertStringTo64Bit   = function(v) return tonumber(v) or 0 end
GetCurRealTime         = function() return 0 end
getElapsedTime         = function() return 0 end
Color                  = setmetatable({}, { __index = function() return {} end })
Font                   = setmetatable({}, { __index = function() return "" end })
SetSofttarget          = function() return true end
OpenMenu               = function() end
GetComponentData       = function() return nil end
GetMacroData           = function() return "" end
GetPlayerContextByClass = function() return nil end
GetContainedShips      = function() return {} end
GetContainedStations   = function() return {} end
RemoveSofttarget       = function() end

-- X4GunneryState must be set before gunnery_control.lua loads (line 5: local State = X4GunneryState).
X4GunneryState = dofile("ui/gunnery_state.lua")

-- ── 5. load the module ───────────────────────────────────────────────────────
-- init() is called at the bottom of the file, so this exercises the full
-- startup path including logSession calls.
local ok, err = pcall(dofile, "ui/gunnery_control.lua")
assert(ok, "gunnery_control.lua failed to load: " .. tostring(err))

-- ── 6. assertion 1: init messages ───────────────────────────────────────────
assert(logContains("[X4GC] initializing UI"),
    "expected '[X4GC] initializing UI' in captured log; got:\n" .. table.concat(capturedLog, "\n"))
assert(logContains("[X4GC] UI initialized"),
    "expected '[X4GC] UI initialized' in captured log; got:\n" .. table.concat(capturedLog, "\n"))

-- ── 7. assertion 2: drive sessionWatchdog -> logSession ─────────────────────
-- init() ends with sessionWatchdog(), which calls
-- Helper.addDelayedOneTimeCallbackOnUpdate(sessionWatchdog, ...).
-- That means pendingCallbacks[1] IS sessionWatchdog.
-- We invoke it exactly once; it will attempt to re-register itself (fine,
-- we just accumulate another entry) and, because no session exists yet on the
-- first tick, it logs nothing extra and exits. We need a session to exist so
-- that the signature changes from nil to something, triggering logSession.
--
-- Simulate the simplest path: create a session directly in the module's
-- shared state table, then fire the watchdog once.
--
-- The module doesn't export `session`, but X4GunneryControlAPI is global.
-- The easiest way to get logSession called is to call menu.onShowMenu() via
-- the Menus table that was populated by init(). However that requires a full
-- Helper.registerMenu frame path.
--
-- Better: sessionWatchdog calls logSession when the signature changes.
-- A fresh session (via menu.onShowMenu stub path) would work, but
-- onShowMenu calls menu.display() which needs a working frame.
-- Instead, we note that the first pendingCallback IS sessionWatchdog.
-- On first call with session==nil it does nothing and re-registers.
-- We must set session before calling it.
--
-- Access is indirect: we can grab the Menus entry for "X4GunneryMenu" and
-- call onShowMenu. But display() would recurse into Helper.createFrameHandle
-- which we have stubbed. Let's try that path.

local gcMenu
for _, m in ipairs(Menus) do
    if m.name == "X4GunneryMenu" then gcMenu = m; break end
end
assert(gcMenu, "X4GunneryMenu was not registered in Menus after init()")

-- onShowMenu creates a session and calls logSession("session created from chair ingress")
-- then calls menu.display() which hits Helper.createFrameHandle (stubbed).
local logBefore = #capturedLog
local ok2, err2 = pcall(function() gcMenu.onShowMenu() end)
assert(ok2, "menu.onShowMenu() raised: " .. tostring(err2))

-- After onShowMenu, pendingCallbacks grew. The LAST registered callback is
-- sessionWatchdog (re-registered by the init() call to sessionWatchdog()).
-- Find the most recently added callback and fire it; the session now has
-- a state signature, so logSession("watchdog state changed") will be emitted.
assert(#pendingCallbacks > 0, "no delayed callbacks were registered")
local watchdog = pendingCallbacks[#pendingCallbacks]
local ok3, err3 = pcall(watchdog)
assert(ok3, "sessionWatchdog() raised: " .. tostring(err3))

-- ── 8. assertion 3: logSession output contains required fields ───────────────
local found = nil
for _, line in ipairs(capturedLog) do
    if string.find(line, "lifecycle=", 1, true)
        and string.find(line, "phase=", 1, true)
        and string.find(line, "epoch=", 1, true)
        and string.find(line, "extmenu=", 1, true) then
        found = line
        break
    end
end
assert(found,
    "expected a logSession line with lifecycle=, phase=, epoch=, extmenu= but none found.\nLog:\n"
    .. table.concat(capturedLog, "\n"))

-- ── 9. assertion 4: extmenu= is not a raw function/table reference ───────────
-- A regression where activeExternalMenuName (the function) is concatenated
-- directly produces something like "function: 0x55a1b2c3" or raises an error.
-- We check the captured log lines for any suspicious extmenu= value.
local function extractExtmenu(line)
    local v = string.match(line, "extmenu=([^;]*)")
    return v
end

for _, line in ipairs(capturedLog) do
    if string.find(line, "extmenu=", 1, true) then
        local val = extractExtmenu(line)
        assert(val ~= nil, "extmenu field present but could not be extracted from: " .. line)
        assert(not string.find(val, "^function:"),
            "extmenu= contains a raw function reference; the bug is present. Line: " .. line)
        assert(not string.find(val, "^table:"),
            "extmenu= contains a raw table reference. Line: " .. line)
    end
end

-- ── 10. assertion 5: Esc from target_select always lands on console ──────────
-- Regression: when session.phase=="target_select" and session.directSnapshot is
-- set, the old onCloseElement branch restored phase="direct" and called
-- menu.display(), creating an infinite Esc cycle. The correct behaviour is:
--   direct --Esc--> target_select --Esc--> console
-- Two closes from direct must always terminate at console.

-- We need a live session to drive. onShowMenu() already created one above;
-- use the same session reference via X4GunneryControlAPI.getSession() which
-- exposes the module-local for test purposes only.
--
-- NOTE on test setup approach: driving this through real public entry points is
-- not feasible in this harness. The only public paths that set directSnapshot
-- (startDirect/engageTarget) and that set phase=target_select while retaining
-- a snapshot (openTargetBrowser) are module-locals invoked through UI button
-- onClick handlers. Executing them requires a fully rendered Helper frame, which
-- in turn requires arithmetic on frame properties (e.g. controls.properties.y)
-- that the stub does not populate. Setting session fields directly via
-- TestAPI.getSession() is the only tractable approach without a full frame stub;
-- we document this explicitly here.
local API = X4GunneryControlAPI
assert(type(API.getSession) == "function",
    "X4GunneryControlAPI.getSession must be defined; add it to gunnery_control.lua")
local sess = API.getSession()
assert(sess ~= nil, "expected a live session after onShowMenu()")

-- ── 10a: target_select + directSnapshots -> onCloseElement("close") ─────────
-- This is the exact bug state: player pressed Esc from the target picker while
-- an engagement was in progress (directSnapshots is non-empty).
local fakeSnapshot = { shipID = sess.shipID, kind = "group",
    componentID = 0, contextID = 0, path = "", group = "", mode = "attack", armed = true }
sess.phase = "target_select"
-- List form: directSnapshots is always a table.
sess.directSnapshots = { fakeSnapshot }

gcMenu.onCloseElement("close")
local phaseAfterPickerClose = sess.phase
assert(phaseAfterPickerClose == "console",
    "BUG: closing target_select with directSnapshots set landed on phase='"
    .. tostring(phaseAfterPickerClose)
    .. "' instead of 'console'. The Esc cycle is still present.")
assert(#(sess.directSnapshots or {}) == 0,
    "directSnapshots must be released when target_select closes to console")

-- ── 10c: bounded cycle check ────────────────────────────────────────────────
-- Directly simulate the full Esc sequence: engaged/direct -> target_select -> console.
-- This encodes the actual defect: every step from engaged must terminate at
-- console within a bounded number of close events with no revisit of engaged.
sess.phase = "engaged"
sess.controlMode = "direct"
sess.directSnapshots = { { shipID = sess.shipID, kind = "group",
    componentID = 0, contextID = 0, path = "", group = "", mode = "attack", armed = true } }
-- Simulate the picker opening (openTargetBrowser sets phase but keeps snapshots).
sess.phase = "target_select"

local stepsToConsole = 0
local visitedEngaged = false
for i = 1, 10 do
    if sess.phase == "console" then break end
    if sess.phase == "engaged" then visitedEngaged = true end
    if sess.phase == "target_select" then
        gcMenu.onCloseElement("close")
        stepsToConsole = stepsToConsole + 1
    else
        break
    end
end
assert(sess.phase == "console",
    "Esc cycle did not terminate at console within 10 close events; final phase: "
    .. tostring(sess.phase))
assert(not visitedEngaged,
    "Esc cycle re-entered engaged phase during target_select -> console transition")
assert(stepsToConsole <= 2,
    "Esc cycle took " .. stepsToConsole .. " closes to reach console (expected <= 2)")

-- ── 11. map-suspended session resume (Change 1) ─────────────────────────────
-- Confirmed-live bug: closing the Map while seated resets the session to
-- console because DockedMenu re-opens ~70 ms after the MapMenu cleanup
-- callback, before the `reopening` lifecycle transition can complete.
-- The fix: a map-suspended session for the *same* ship must be treated as
-- resumable in onShowMenu(), keeping its phase and not recreating the session.

-- 11a: same ship — session must survive with its phase intact.
-- Reset to a known good state first.
local sess11 = API.getSession()
assert(sess11 ~= nil, "expected a live session for map-suspend resume test")
sess11.shipID    = 42                              -- matches playerShip() stub (id(42)=42)
sess11.phase     = "target_select"
sess11.lifecycle = X4GunneryState.lifecycle.suspendedMap
local preResumeSess = sess11

gcMenu.onShowMenu()

local postResumeSess = API.getSession()
assert(postResumeSess == preResumeSess,
    "BUG (same ship): map-suspended session was discarded and recreated; "
    .. "expected same session object after onShowMenu()")
assert(postResumeSess.phase == "target_select",
    "BUG (same ship): phase was reset to '"
    .. tostring(postResumeSess.phase)
    .. "' instead of 'target_select' after map-suspend resume")
assert(postResumeSess.lifecycle == X4GunneryState.lifecycle.owned,
    "BUG (same ship): lifecycle should be 'owned' after resume, got '"
    .. tostring(postResumeSess.lifecycle) .. "'")
assert(logContains("session resumed from map suspend"),
    "expected 'session resumed from map suspend' in log after map-suspend resume")

-- 11b: different ship — session must still be discarded and recreated.
-- The ship-identity guard must not be weakened by the fix.
local sess11b = API.getSession()
assert(sess11b ~= nil, "expected a live session for different-ship guard test")
sess11b.shipID    = 99                             -- differs from playerShip()=42
sess11b.phase     = "target_select"
sess11b.lifecycle = X4GunneryState.lifecycle.suspendedMap
local preDiscardSess = sess11b

gcMenu.onShowMenu()

local postDiscardSess = API.getSession()
assert(postDiscardSess ~= preDiscardSess,
    "BUG (different ship): map-suspended session for wrong ship was NOT discarded; "
    .. "the ship-identity guard is broken")
assert(postDiscardSess.phase == "console",
    "BUG (different ship): recreated session should start at console, got '"
    .. tostring(postDiscardSess.phase) .. "'")
assert(postDiscardSess.lifecycle == X4GunneryState.lifecycle.owned,
    "BUG (different ship): recreated session lifecycle should be 'owned', got '"
    .. tostring(postDiscardSess.lifecycle) .. "'")

-- ── 12. Watch and direct frames must provide a visible back button ────────────
-- Proven live on 2026-08-04: Esc (dueToClose == "back") is never delivered to
-- frames with playerControls = true. The watch frame had standardButtons = {},
-- making it completely inescapable. The direct (compact Engage) frame already
-- had standardButtons = { back = true, close = true } and must not regress.
-- A visible back button is the only supported exit for playerControls frames.

-- 12a: engaged/auto frame must have standardButtons.back == true
local sess12 = API.getSession()
assert(sess12 ~= nil, "expected a live session for watch frame test")
sess12.phase = "engaged"
sess12.controlMode = "auto"
sess12.directSnapshots = {}
lastFrameProps = nil
local ok12a, err12a = pcall(function() gcMenu.display() end)
assert(ok12a, "menu.display() raised during watch phase: " .. tostring(err12a))
assert(lastFrameProps ~= nil,
    "createFrameHandle was not called during watch phase display()")
assert(lastFrameProps.standardButtons ~= nil
    and lastFrameProps.standardButtons.back == true,
    "BUG: engaged/auto frame standardButtons.back is not true — "
    .. "Esc is never delivered to playerControls frames, so without a visible "
    .. "back button the auto-engage phase is completely inescapable. "
    .. "Got standardButtons=" .. tostring(lastFrameProps.standardButtons))

-- 12a2: the engaged/auto frame must NOT opt into the mini widget system. Helper
-- documents enableDefaultInteractions as "default input handling (f.e.
-- ESC/DEL)", and that handling lives in the normal widget system. Setting
-- useMiniWidgetSystem = true is what silently dropped Esc in the camera
-- phases while ordinary frames kept it.
assert(not lastFrameProps.useMiniWidgetSystem,
    "BUG: engaged/auto frame sets useMiniWidgetSystem, which drops default ESC/DEL "
    .. "handling and makes Esc unusable in the auto-engage phase")

-- 12a4: engaged/auto must own a table. Helper only wires frame interaction when the
-- frame has one, and the watch frame was the sole table-less frame and the sole frame
-- where Esc leaked to X4 instead of closing the view.
assert(addTableCalls > 0,
    "BUG: engaged/auto frame created no table, so Helper never wires interaction and "
    .. "Esc leaks to X4 and opens the main menu instead of leaving the auto-engage view")

-- 12a3: engaged/auto playerControls must be true (same as old watch frame).
assert(lastFrameProps.playerControls == true,
    "BUG: engaged/auto frame playerControls is not true")

-- 12b: engaged/direct (compact Engage) frame must still have standardButtons.back == true
sess12.phase = "engaged"
sess12.controlMode = "direct"
-- Provide minimal directSnapshots so the active= check does not crash.
sess12.directSnapshots = { { kind = "group", contextID = 0, path = "", group = "",
    shipID = sess12.shipID, mode = "attack", armed = true } }
sess12.selectedGroupKey = nil
lastFrameProps = nil
local ok12b, err12b = pcall(function() gcMenu.display() end)
assert(ok12b, "menu.display() raised during direct phase: " .. tostring(err12b))
assert(lastFrameProps ~= nil,
    "createFrameHandle was not called during direct phase display()")
assert(lastFrameProps.standardButtons ~= nil
    and lastFrameProps.standardButtons.back == true,
    "REGRESSION: engaged/direct frame standardButtons.back is not true — "
    .. "the compact Engage panel has lost its only escape route for "
    .. "playerControls frames (Esc is never delivered). "
    .. "Got standardButtons=" .. tostring(lastFrameProps.standardButtons))

-- 12b2: same mini-widget-system guard for the compact Engage frame.
assert(not lastFrameProps.useMiniWidgetSystem,
    "BUG: engaged/direct frame sets useMiniWidgetSystem, which drops default ESC/DEL "
    .. "handling and makes Esc unusable in the compact Engage panel")

-- 12b3: engaged/direct playerControls must be true.
assert(lastFrameProps.playerControls == true,
    "BUG: engaged/direct frame playerControls is not true")

-- ── 14: Engage POV toggle flips turret <-> target and is guarded ───────────
-- The camera call is pcall-guarded so a runtime failure logs instead of taking
-- the session down. Drive the toggle through onCloseElement-independent state.
local sess14 = _G.X4GunneryControlAPI.getSession()
if sess14 then
    sess14.phase = "engaged"
    sess14.controlMode = "direct"
    sess14.engagePov = nil
    C.SetPlayerCameraTargetView = function() error("simulated camera failure") end
    -- applyEngagePov is internal; exercise it through the public toggle by
    -- reaching the menu the same way earlier cases do.
    local povMenu
    for _, m in ipairs(Menus) do if m.name == "X4GunneryMenu" then povMenu = m end end
    -- Toggling is wired to a button; simulate one flip by setting the flag and
    -- confirming the applied-POV log line appears without raising.
    local okPov = pcall(function()
        sess14.engagePov = "target"
        sess14.directSnapshots = sess14.directSnapshots or {}
        -- re-render the engaged/direct panel; the POV label must reflect the flag
        povMenu.display()
    end)
    assert(okPov, "direct panel render raised while POV=target")
end

-- ── 15: cutscene aim buttons emit the right AddUITriggeredEvent calls ───────
-- Transport contract (live-tested 2026-08-04, three rounds): the engine
-- PREPENDS $ to every Lua string key during Lua→MD conversion, so Lua "anchor"
-- arrives in MD as the variable key $anchor (read via event.param3.$anchor).
-- Never pre-prefix $ in Lua — "["$anchor"]" becomes the invalid name $$anchor,
-- stuck as an unreadable string key. Ids must be converted via
-- ConvertStringToLuaID(tostring(id)) (vanilla pattern,
-- menu_ship_configuration.lua:1399) to arrive as real MD component objects.

local capturedEvents = {}
AddUITriggeredEvent = function(screen, control, params)
    capturedEvents[#capturedEvents + 1] = { screen = screen, control = control, params = params }
end

-- Marker stub: proves each id was routed through ConvertStringToLuaID.
ConvertStringToLuaID = function(s) return "luaid:" .. tostring(s) end

-- Give GetSofttarget2 a non-zero return so guard checks pass.
C.GetSofttarget2 = function()
    return { softtargetID = 77, softtargetConnectionName = "conn" }
end

-- Restore a fresh owned session in direct phase with a directSnapshot and a
-- fake group so selectedGroupAndMember() can resolve a non-zero turretID.
gcMenu.onShowMenu()
local sess15 = API.getSession()
assert(sess15 ~= nil, "expected session for cutscene aim test")
-- Inject a fake group with a member (componentID=55) so the turret guard passes.
local fakeGroup15 = {
    key = "fake-group-15", kind = "group", contextID = 0, path = "fake", group = "grp",
    componentID = 55, mode = "attack", armed = true, members = {
        { componentID = 55, displayName = "Turret 1", operational = true, cameraSupported = true,
          componentKey = "55" }
    }, displayName = "Fake Turret Group"
}
sess15.groups = { fakeGroup15 }
sess15.phase = "engaged"
sess15.controlMode = "direct"
sess15.directSnapshots = { { kind = "group", contextID = 0, path = "fake", group = "grp",
    shipID = sess15.shipID, mode = "attack", armed = true, componentID = 55 } }
sess15.selectedGroupKey = fakeGroup15.key
sess15.selectedMemberID = 55
sess15.cameraMemberID = 55   -- beginEngaged sets this; set it explicitly for the test

-- 15a: sendCutsceneAimStart("turret") — anchor=turret componentID (55),
-- target=softtarget (77), both as ConvertStringToLuaID-converted values under
-- PLAIN keys (the engine adds the $ prefix on the MD side).
capturedEvents = {}
X4GunneryControlAPI.sendCutsceneAimStart("turret")
local evStart = nil
for _, e in ipairs(capturedEvents) do
    if e.screen == "X4GunneryControl" and e.control == "cutscene_aim_start" then evStart = e; break end
end
assert(evStart ~= nil,
    "sendCutsceneAimStart('turret') must emit AddUITriggeredEvent('X4GunneryControl','cutscene_aim_start',...)")
assert(type(evStart.params) == "table",
    "cutscene_aim_start params must be a table")
assert(evStart.params["anchor"] == "luaid:55",
    "cutscene_aim_start params['anchor'] must be ConvertStringToLuaID(tostring(turretID)); got: "
    .. tostring(evStart.params["anchor"]))
assert(evStart.params["target"] == "luaid:77",
    "cutscene_aim_start params['target'] must be ConvertStringToLuaID(tostring(softtargetID)); got: "
    .. tostring(evStart.params["target"]))
assert(evStart.params["pov"] == "turret",
    "cutscene_aim_start params['pov'] must be 'turret'; got: " .. tostring(evStart.params["pov"]))
assert(evStart.params["$anchor"] == nil and evStart.params["$target"] == nil
    and evStart.params["$pov"] == nil,
    "cutscene_aim_start must not carry $-prefixed keys: the engine prepends $ "
    .. "during Lua->MD conversion, so '$anchor' would become the unreadable $$anchor")

-- 15b: sendCutsceneAimStart("target") — anchor/target swapped: camera sits at
-- the softtarget (77) looking at the turret (55).
capturedEvents = {}
X4GunneryControlAPI.sendCutsceneAimStart("target")
local evStart2 = nil
for _, e in ipairs(capturedEvents) do
    if e.screen == "X4GunneryControl" and e.control == "cutscene_aim_start" then evStart2 = e; break end
end
assert(evStart2 ~= nil,
    "sendCutsceneAimStart('target') must emit cutscene_aim_start")
assert(evStart2.params["anchor"] == "luaid:77",
    "cutscene_aim_start (pov=target) params['anchor'] must be the softtarget; got: "
    .. tostring(evStart2.params["anchor"]))
assert(evStart2.params["target"] == "luaid:55",
    "cutscene_aim_start (pov=target) params['target'] must be the turret; got: "
    .. tostring(evStart2.params["target"]))
assert(evStart2.params["pov"] == "target",
    "cutscene_aim_start params['pov'] must be 'target'; got: " .. tostring(evStart2.params["pov"]))

-- 15c: sendCutsceneAimStop() emits cutscene_aim_stop
capturedEvents = {}
X4GunneryControlAPI.sendCutsceneAimStop()
local evStop = nil
for _, e in ipairs(capturedEvents) do
    if e.screen == "X4GunneryControl" and e.control == "cutscene_aim_stop" then evStop = e; break end
end
assert(evStop ~= nil,
    "sendCutsceneAimStop() must emit AddUITriggeredEvent('X4GunneryControl','cutscene_aim_stop',...)")

-- 15d: discardSession emits cutscene_aim_stop (via the session teardown hook).
-- Use the console-close path (same as test 13a) so discardSession fires
-- synchronously rather than via a deferred callback.
sess15.phase = "console"
capturedEvents = {}
gcMenu.onCloseElement("close")  -- leaveChair -> endSession -> discardSession
local evStopOnDiscard = nil
for _, e in ipairs(capturedEvents) do
    if e.screen == "X4GunneryControl" and e.control == "cutscene_aim_stop" then evStopOnDiscard = e; break end
end
assert(evStopOnDiscard ~= nil,
    "discardSession must emit cutscene_aim_stop; "
    .. "check that discardSession calls AddUITriggeredEvent('X4GunneryControl','cutscene_aim_stop',{})")

-- ── 16. engaged/auto and engaged/direct render frames with playerControls ────
-- Both controlMode paths must create a playerControls=true frame; they differ
-- in layout (auto gets the sparse watch table, direct gets the compact panel).
gcMenu.onShowMenu()
local sess16 = API.getSession()
assert(sess16 ~= nil, "expected session for engaged frame tests")

-- 16a: engaged/auto
sess16.phase = "engaged"
sess16.controlMode = "auto"
sess16.directSnapshots = {}
lastFrameProps = nil
local ok16a, err16a = pcall(function() gcMenu.display() end)
assert(ok16a, "display() raised in engaged/auto: " .. tostring(err16a))
assert(lastFrameProps ~= nil, "createFrameHandle not called in engaged/auto")
assert(lastFrameProps.playerControls == true,
    "engaged/auto: playerControls must be true")

-- 16b: engaged/direct
sess16.phase = "engaged"
sess16.controlMode = "direct"
sess16.directSnapshots = { { kind = "group", contextID = 0, path = "", group = "",
    shipID = sess16.shipID, mode = "attack", armed = true } }
lastFrameProps = nil
local ok16b, err16b = pcall(function() gcMenu.display() end)
assert(ok16b, "display() raised in engaged/direct: " .. tostring(err16b))
assert(lastFrameProps ~= nil, "createFrameHandle not called in engaged/direct")
assert(lastFrameProps.playerControls == true,
    "engaged/direct: playerControls must be true")

-- ── 17. onCloseElement: engaged/auto -> console (deferred callback) ───────────
-- onCloseElement defers its work; drain the most recent pending callback.
-- Reset softtarget so viewSofttargetKey matches and the close is not treated
-- as a target-bracket click (which would just call display() again).
C.GetSofttarget2 = function()
    return { softtargetID = 0, softtargetConnectionName = "" }
end
gcMenu.onShowMenu()
local sess17 = API.getSession()
assert(sess17 ~= nil, "expected session for onCloseElement engaged tests")
sess17.phase = "engaged"
sess17.controlMode = "auto"
sess17.directSnapshots = {}
-- Matches softtargetKey() with softtargetID=0, connection="" -> "0\031"
sess17.viewSofttargetKey = "0\031"
local before17 = #pendingCallbacks
gcMenu.onCloseElement("back")
-- Drain the deferred callback that was just registered.
for i = before17 + 1, #pendingCallbacks do
    local ok17, err17 = pcall(pendingCallbacks[i])
    assert(ok17, "deferred callback raised: " .. tostring(err17))
end
assert(sess17.phase == "console",
    "engaged/auto onCloseElement('back') must reach console; got: " .. tostring(sess17.phase))

-- ── 18. viewCreated clears engagePending for direct but NOT for auto ──────────
-- For auto-engage, engagePending comes from the old startWatch path which is
-- now gone; auto never sets it. For direct, engagePending is set by engageTarget
-- and cleared on frame confirmation. The guard is controlMode == "direct".
gcMenu.onShowMenu()
local sess18 = API.getSession()
assert(sess18 ~= nil, "expected session for viewCreated test")

-- 18a: direct clears engagePending
sess18.phase = "engaged"
sess18.controlMode = "direct"
sess18.engagePending = true
sess18.engagePendingSince = 0
gcMenu.viewCreated()
assert(sess18.engagePending == nil,
    "viewCreated must clear engagePending in engaged/direct")

-- 18b: auto does NOT clear engagePending (it should never be set, but guard
-- must not over-clear on an unrelated phase).
sess18.phase = "engaged"
sess18.controlMode = "auto"
sess18.engagePending = true   -- artificially set to test the guard
gcMenu.viewCreated()
assert(sess18.engagePending == true,
    "viewCreated must NOT clear engagePending in engaged/auto")

-- ── 19. restoreDirect with two-entry snapshot list restores both ──────────────
-- Key safety regression: a single-entry loop would silently drop snapshots[2]
-- and leave the second group permanently on autoassist after a session end.
local restoreCalls = {}
local origSetTurretGroupMode = C.SetTurretGroupMode2
local origSetTurretGroupArmed = C.SetTurretGroupArmed
-- Intercept the C calls to count how many groups were restored.
C.SetTurretGroupMode2 = function(ship, ctx, path, group, mode)
    restoreCalls[#restoreCalls + 1] = { path = tostring(path), group = tostring(group), mode = mode }
end
C.SetTurretGroupArmed = function(ship, ctx, path, group, arm) end

gcMenu.onShowMenu()
local sess19 = API.getSession()
assert(sess19 ~= nil, "expected session for two-entry restoreDirect test")
-- Build two distinct groups in the session so findSnapshotGroup can resolve both.
local grp19a = { key = "grp19a", kind = "group", contextID = 1, path = "p", group = "A",
    componentID = 10, members = {}, totalCount = 1, operationalCount = 1 }
local grp19b = { key = "grp19b", kind = "group", contextID = 1, path = "p", group = "B",
    componentID = 11, members = {}, totalCount = 1, operationalCount = 1 }
sess19.groups = { grp19a, grp19b }
sess19.directSnapshots = {
    { shipID = sess19.shipID, kind = "group", contextID = 1, path = "p", group = "A",
      mode = "attack", armed = false },
    { shipID = sess19.shipID, kind = "group", contextID = 1, path = "p", group = "B",
      mode = "defend", armed = false },
}

-- Drive restoreDirect via onCloseElement console path (leaveChair -> discardSession).
sess19.phase = "console"
gcMenu.onCloseElement("close")

-- Both groups must have been restored (SetTurretGroupMode2 called twice).
assert(#restoreCalls == 2,
    "restoreDirect with 2-entry list must restore both groups; got "
    .. tostring(#restoreCalls) .. " restore calls. "
    .. "A single-entry loop would strand the second group on autoassist.")
-- After restore, directSnapshots must be empty.
-- Session is nil after endSession; check via a fresh onShowMenu.
gcMenu.onShowMenu()
local sess19post = API.getSession()
assert(sess19post ~= nil, "expected session after restore test")
assert(#(sess19post.directSnapshots or {}) == 0,
    "directSnapshots must be empty after session end and restore")

-- Restore stubs.
C.SetTurretGroupMode2 = origSetTurretGroupMode
C.SetTurretGroupArmed = origSetTurretGroupArmed

-- ── 20. console renders with a checked group without error ───────────────────
-- Verifies the checkbox column in the console group row does not crash.
gcMenu.onShowMenu()
local sess20 = API.getSession()
assert(sess20 ~= nil, "expected session for console checkbox test")
-- Build a group and check it.
local grp20 = { key = "grp20", kind = "group", contextID = 5, path = "p", group = "front",
    componentID = 9, displayName = "Front", totalCount = 2, operationalCount = 1,
    mode = "attack", armed = false, members = {
        { componentID = 9, displayName = "Turret 1", operational = true,
          cameraSupported = true, componentKey = "9" }
    } }
sess20.groups = { grp20 }
sess20.checkedGroupKeys = { ["grp20"] = true }
sess20.phase = "console"
local ok20, err20 = pcall(function() gcMenu.display() end)
assert(ok20, "console with checked group raised: " .. tostring(err20))

-- ── 21. engaged panel renders for both control modes ──────────────────────────
-- 21a: auto
gcMenu.onShowMenu()
local sess21 = API.getSession()
assert(sess21 ~= nil)
local grp21 = { key = "grp21", kind = "group", contextID = 5, path = "p", group = "front",
    componentID = 9, displayName = "Front", totalCount = 1, operationalCount = 1,
    mode = "attack", armed = false, members = {
        { componentID = 9, displayName = "Turret 1", operational = true,
          cameraSupported = true, componentKey = "9" }
    } }
sess21.groups = { grp21 }
sess21.checkedGroupKeys = { ["grp21"] = true }
sess21.phase = "engaged"
sess21.controlMode = "auto"
sess21.directSnapshots = {}
sess21.cameraMemberID = 9
sess21.povAnchor = "turret"
sess21.povMode = "manual"
sess21.aimTargetID = nil
local ok21a, err21a = pcall(function() gcMenu.display() end)
assert(ok21a, "engaged/auto display raised: " .. tostring(err21a))
assert(lastFrameProps ~= nil, "createFrameHandle not called in engaged/auto (step 21)")
assert(lastFrameProps.playerControls == true, "engaged/auto: playerControls must be true (step 21)")

-- 21b: direct
sess21.phase = "engaged"
sess21.controlMode = "direct"
sess21.directSnapshots = { { kind = "group", contextID = 5, path = "p", group = "front",
    shipID = sess21.shipID, mode = "attack", armed = false } }
lastFrameProps = nil
local ok21b, err21b = pcall(function() gcMenu.display() end)
assert(ok21b, "engaged/direct display raised: " .. tostring(err21b))
assert(lastFrameProps ~= nil, "createFrameHandle not called in engaged/direct (step 21)")
assert(lastFrameProps.playerControls == true, "engaged/direct: playerControls must be true (step 21)")

-- ── 22. cycleCamera changes cameraMemberID and wraps ─────────────────────────
gcMenu.onShowMenu()
local sess22 = API.getSession()
assert(sess22 ~= nil)
local grp22 = { key = "grp22", kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 10, displayName = "G", totalCount = 2, operationalCount = 2,
    mode = "attack", armed = false, members = {
        { componentID = 10, displayName = "T1", operational = true, cameraSupported = true, componentKey = "10" },
        { componentID = 11, displayName = "T2", operational = true, cameraSupported = true, componentKey = "11" },
    } }
sess22.groups = { grp22 }
sess22.checkedGroupKeys = { ["grp22"] = true }
sess22.cameraIndex = 1
sess22.cameraMemberID = 10
X4GunneryState.cycleCamera(sess22, 1)
assert(sess22.cameraMemberID == 11,
    "cycleCamera(+1) must advance to member 2; got " .. tostring(sess22.cameraMemberID))
-- Wrap: cycling again from the last member returns to the first.
X4GunneryState.cycleCamera(sess22, 1)
assert(sess22.cameraMemberID == 10,
    "cycleCamera wraps: expected 10, got " .. tostring(sess22.cameraMemberID))

-- ── 23. updateAimTarget picks a target and retargets in cinematic mode ────────
-- updateAimTarget is internal; drive it via the module's TestAPI.
gcMenu.onShowMenu()
local sess23 = API.getSession()
assert(sess23 ~= nil)
local grp23 = { key = "grp23", kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 20, displayName = "G", totalCount = 1, operationalCount = 1,
    mode = "attack", armed = false, members = {
        { componentID = 20, displayName = "T1", operational = true, cameraSupported = true, componentKey = "20" }
    } }
sess23.groups = { grp23 }
sess23.checkedGroupKeys = { ["grp23"] = true }
sess23.phase = "engaged"
sess23.controlMode = "auto"
sess23.directSnapshots = {}
sess23.cameraMemberID = 20
sess23.aimTargetID = nil
sess23.povMode = "cinematic"
sess23.povAnchor = "turret"

-- Fake a target candidate: IsComponentOperational returns true by default.
C.IsComponentOperational = function(id) return id == 99 end

-- Replace GetContainedShips to return a fake enemy target.
GetComponentData = function(component, ...)
    local keys = {...}
    local vals = {}
    for _, k in ipairs(keys) do
        if k == "isenemy" then vals[#vals + 1] = (component == 99)
        elseif k == "ishostile" then vals[#vals + 1] = false
        elseif k == "isfriend" then vals[#vals + 1] = false
        elseif k == "isknown" then vals[#vals + 1] = true
        elseif k == "isradarvisible" then vals[#vals + 1] = true
        elseif k == "maxradarrange" then vals[#vals + 1] = 40000
        elseif k == "isplayerowned" then vals[#vals + 1] = true
        else vals[#vals + 1] = nil
        end
    end
    return unpack(vals)
end
-- ship != target root so isEngagementTargetAllowed passes
C.GetContextByClass = function(comp, cls, self_) return comp end
GetContainedShips = function() return { 99 } end
GetContainedStations = function() return {} end
C.GetDistanceBetween = function() return 1000 end
GetPlayerContextByClass = function() return 1 end

-- Captured events for cinematic restart check.
local capturedEvts23 = {}
AddUITriggeredEvent = function(screen, control, params)
    capturedEvts23[#capturedEvts23 + 1] = { screen = screen, control = control, params = params }
end

assert(type(X4GunneryControlAPI.updateAimTarget) == "function",
    "X4GunneryControlAPI.updateAimTarget must be exposed")
X4GunneryControlAPI.updateAimTarget()

-- Should have chosen target 99 and, since it changed from nil and povMode=cinematic,
-- emitted cutscene_aim_stop then cutscene_aim_start.
assert(sess23.aimTargetID ~= nil,
    "updateAimTarget must choose a candidate; aimTargetID is nil")
local seenStop, seenStart = false, false
for _, e in ipairs(capturedEvts23) do
    if e.screen == "X4GunneryControl" then
        if e.control == "cutscene_aim_stop" then seenStop = true end
        if e.control == "cutscene_aim_start" then seenStart = true end
    end
end
assert(seenStop, "updateAimTarget in cinematic mode must emit cutscene_aim_stop on retarget")
assert(seenStart, "updateAimTarget in cinematic mode must emit cutscene_aim_start on retarget")

-- ── 24. updateAimTarget with no candidates does not crash and emits nothing ────
local capturedEvts24 = {}
AddUITriggeredEvent = function(screen, control, params)
    capturedEvts24[#capturedEvts24 + 1] = { screen = screen, control = control, params = params }
end
GetContainedShips = function() return {} end
sess23.aimTargetID = nil
local ok24, err24 = pcall(function() X4GunneryControlAPI.updateAimTarget() end)
assert(ok24, "updateAimTarget with no candidates raised: " .. tostring(err24))
local cutsceneEvts24 = 0
for _, e in ipairs(capturedEvts24) do
    if e.screen == "X4GunneryControl" and
       (e.control == "cutscene_aim_start" or e.control == "cutscene_aim_stop") then
        cutsceneEvts24 = cutsceneEvts24 + 1
    end
end
assert(cutsceneEvts24 == 0,
    "updateAimTarget with nil result must not emit cutscene events; got " .. cutsceneEvts24)

-- ── 25. auto re-scans on a 5 s cadence; direct holds its target ───────────────
-- Two live candidates. In auto mode the better one (98, nearer) must not be
-- adopted within 5 s of the last scan, and must be adopted once 5 s have
-- passed. In direct mode the ordered target is held however much time passes,
-- but a dead one is replaced at once.
GetContainedShips = function() return { 98, 99 } end
C.IsComponentOperational = function(id) return id == 98 or id == 99 end
GetComponentData = function(component, ...)
    local keys, vals = {...}, {}
    for _, k in ipairs(keys) do
        if k == "isenemy" then vals[#vals + 1] = true
        elseif k == "ishostile" then vals[#vals + 1] = false
        elseif k == "isfriend" then vals[#vals + 1] = false
        elseif k == "isknown" then vals[#vals + 1] = true
        elseif k == "isradarvisible" then vals[#vals + 1] = true
        elseif k == "maxradarrange" then vals[#vals + 1] = 40000
        elseif k == "isplayerowned" then vals[#vals + 1] = true
        else vals[#vals + 1] = nil
        end
    end
    return unpack(vals)
end
C.GetDistanceBetween = function(_, b) return (tostring(b) == "98") and 100 or 5000 end

local clock = 100
getElapsedTime = function() return clock end
sess23.povMode = "manual"
sess23.povAnchor = "turret"

sess23.controlMode = "auto"
sess23.aimTargetID = 99
X4GunneryControlAPI.updateAimTarget()   -- arms the 5 s window
sess23.aimTargetID = 99
clock = clock + 1
X4GunneryControlAPI.updateAimTarget()
assert(tostring(sess23.aimTargetID) == "99",
    "auto must not re-scan within 5 s; aimTargetID became " .. tostring(sess23.aimTargetID))
clock = clock + 10
X4GunneryControlAPI.updateAimTarget()
assert(tostring(sess23.aimTargetID) == "98",
    "auto must adopt the better target after 5 s; got " .. tostring(sess23.aimTargetID))

sess23.controlMode = "direct"
sess23.aimTargetID = 99
clock = clock + 600
X4GunneryControlAPI.updateAimTarget()
assert(tostring(sess23.aimTargetID) == "99",
    "direct must hold its target regardless of elapsed time; got " .. tostring(sess23.aimTargetID))
-- What direct does when its target *dies* is the Auto-next Target contract;
-- tests 39 and 41 own it.

-- ── 26. a changed aim target repaints the manual panel ───────────────────────
-- Button `active` states are fixed when the frame is built, so acquiring the
-- first target must rebuild the frame or "Target POV" stays greyed forever.
sess23.controlMode = "auto"
sess23.povMode, sess23.povAnchor = "manual", "turret"
sess23.aimTargetID = nil
C.IsComponentOperational = function(id) return id == 98 or id == 99 end
lastFrameProps = nil
clock = clock + 60
X4GunneryControlAPI.updateAimTarget()
assert(sess23.aimTargetID ~= nil, "precondition: updateAimTarget must pick a target")
assert(lastFrameProps ~= nil,
    "acquiring an aim target in manual mode must rebuild the panel frame")

-- ── 27. engaged/direct with targetObjectID creates TWO frames ────────────────
-- The left element panel is only shown when controlMode=="direct" AND
-- session.targetObjectID is set.
gcMenu.onShowMenu()
local sess27 = API.getSession()
assert(sess27 ~= nil, "expected session for two-frame test")
local grp27 = { key = "grp27", kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 27, displayName = "G27", totalCount = 1, operationalCount = 1,
    mode = "attack", armed = false, members = {
        { componentID = 27, displayName = "T1", operational = true,
          cameraSupported = true, componentKey = "27" }
    } }
sess27.groups = { grp27 }
sess27.checkedGroupKeys = { ["grp27"] = true }
sess27.phase = "engaged"
sess27.controlMode = "direct"
sess27.directSnapshots = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess27.shipID, mode = "attack", armed = false } }
sess27.cameraMemberID = 27
sess27.targetObjectID = 500
sess27.aimTargetID = 500
local ok27, err27 = pcall(function() gcMenu.display() end)
assert(ok27, "display() raised in engaged/direct+targetObjectID: " .. tostring(err27))
assert(frameCount == 2,
    "engaged/direct with targetObjectID must create TWO frames; got " .. tostring(frameCount))
-- frame:display() registers a view keyed by layer (helper.lua onFrameHandleView
-- Created / View.registerMenu("Helper" .. layer)). Two frames sharing the
-- default layer 4 means the second silently replaces the first on screen.
assert(frameProps[1].layer ~= frameProps[2].layer,
    "the two engaged/direct frames must sit on different layers; both had "
    .. tostring(frameProps[1].layer))

-- ── 28. engaged/auto creates ONE frame ───────────────────────────────────────
gcMenu.onShowMenu()
local sess28 = API.getSession()
assert(sess28 ~= nil, "expected session for one-frame test")
sess28.groups = { grp27 }
sess28.checkedGroupKeys = { ["grp27"] = true }
sess28.phase = "engaged"
sess28.controlMode = "auto"
sess28.directSnapshots = {}
sess28.cameraMemberID = 27
sess28.aimTargetID = nil
local ok28, err28 = pcall(function() gcMenu.display() end)
assert(ok28, "display() raised in engaged/auto: " .. tostring(err28))
assert(frameCount == 1,
    "engaged/auto must create ONE frame; got " .. tostring(frameCount))

-- ── 29. cycleTarget exposed via TestAPI and changes targetObjectID ────────────
-- Restore the camera stub that test 14 replaced with an error-thrower.
C.SetPlayerCameraTargetView = function() return true end
gcMenu.onShowMenu()
local sess29 = API.getSession()
assert(sess29 ~= nil, "expected session for cycleTarget test")
assert(type(X4GunneryControlAPI.cycleTarget) == "function",
    "X4GunneryControlAPI.cycleTarget must be exposed")
-- Set up a direct session with two candidates accessible via GetContainedShips.
-- GetContainedShips returns 98 and 99, both operational (restored from test 25).
C.IsComponentOperational = function(id) return id == 98 or id == 99 end
GetContainedShips = function() return { 98, 99 } end
GetContainedStations = function() return {} end
GetPlayerContextByClass = function() return 1 end
C.GetContextByClass = function(comp, cls, self_) return comp end
C.GetDistanceBetween = function(_, b) return (tostring(b) == "98") and 100 or 5000 end
GetComponentData = function(component, ...)
    local keys, vals = {...}, {}
    for _, k in ipairs(keys) do
        if k == "isenemy" then vals[#vals + 1] = true
        elseif k == "ishostile" then vals[#vals + 1] = false
        elseif k == "isfriend" then vals[#vals + 1] = false
        elseif k == "isknown" then vals[#vals + 1] = true
        elseif k == "isradarvisible" then vals[#vals + 1] = true
        elseif k == "maxradarrange" then vals[#vals + 1] = 40000
        elseif k == "isplayerowned" then vals[#vals + 1] = true
        else vals[#vals + 1] = nil
        end
    end
    return unpack(vals)
end
local grp29 = { key = "grp29", kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 27, displayName = "G29", totalCount = 1, operationalCount = 1,
    mode = "attack", armed = false, members = {
        { componentID = 27, displayName = "T1", operational = true,
          cameraSupported = true, componentKey = "27" }
    } }
sess29.groups = { grp29 }
sess29.checkedGroupKeys = { ["grp29"] = true }
sess29.phase = "engaged"
sess29.controlMode = "direct"
sess29.directSnapshots = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess29.shipID, mode = "attack", armed = false } }
sess29.cameraMemberID = 27
-- Candidate 98 is nearer (100m) so it will be first sorted; start at 98.
sess29.targetObjectID = 98
sess29.aimTargetID = 98
sess29.targetCandidates = {}
-- cycleTarget(1) should move to the second candidate (99).
X4GunneryControlAPI.cycleTarget(1)
local newTarget = API.getSession().targetObjectID
assert(newTarget ~= nil,
    "cycleTarget(1) must set targetObjectID; got nil")
assert(tostring(newTarget) ~= tostring(98),
    "cycleTarget(1) from 98 must change targetObjectID; still " .. tostring(newTarget))

-- ── 30. the panel greys the button for the view already on screen ────────────
-- Regression: entering engaged with a stale povAnchor greyed "Target POV
-- manual" while the camera was actually on the turret.
local function povButton(id) return buttonByText("text:20991:" .. id) end
gcMenu.onShowMenu()
local sess30 = API.getSession()
sess30.groups = { grp27 }
sess30.checkedGroupKeys = { ["grp27"] = true }
sess30.phase = "engaged"
sess30.cameraMemberID = 27
sess30.directSnapshots = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess30.shipID, mode = "attack", armed = false } }
sess30.controlMode = "auto"
sess30.povAnchor, sess30.povMode = "turret", "manual"
sess30.aimTargetID = 500
gcMenu.display()
assert(povButton(63) and povButton(63).active == false,
    "Turret POV manual must be greyed while it is the current view")
assert(povButton(65) and povButton(65).active == true,
    "Turret POV cinematic must be clickable while the view is manual")
assert(povButton(64) and povButton(64).active == true,
    "Target POV manual must be clickable when an aim target exists")

sess30.povAnchor, sess30.povMode = "target", "cinematic"
gcMenu.display()
assert(povButton(66) and povButton(66).active == false,
    "Target POV cinematic must be greyed while it is the current view")
assert(povButton(63) and povButton(63).active == true,
    "Turret POV manual must be clickable while the view is target cinematic")

-- ── 31. the element panel greys whichever element is being attacked ──────────
sess30.controlMode = "direct"
sess30.povAnchor, sess30.povMode = "turret", "manual"
sess30.targetObjectID = 500
sess30.aimTargetID = 500          -- hull is the engaged element
gcMenu.display()
assert(povButton(58) and povButton(58).active == false,
    "Hull must be greyed when the hull is the engaged element")
sess30.aimTargetID = 501          -- a surface element, not the hull
gcMenu.display()
assert(povButton(58) and povButton(58).active == true,
    "Hull must be clickable when something else is the engaged element")

-- ── 32. Next/Previous Target grey out with nothing to cycle to ───────────────
-- Cycling is pointless with a single candidate, and there is no candidate list
-- at all outside direct mode. The stubs from test 29 still supply 98 and 99.
-- Advance the clock so the readTargetCandidates() 1 s TTL cache (added with the
-- target-candidate-cache fix) expires between this display() and the one above.
clock = clock + 2
GetContainedShips = function() return { 98 } end
gcMenu.display()
assert(povButton(75) and povButton(75).active == false,
    "Next Target must be greyed with only one candidate")
assert(povButton(76) and povButton(76).active == false,
    "Previous Target must be greyed with only one candidate")

clock = clock + 2
GetContainedShips = function() return { 98, 99 } end
gcMenu.display()
assert(povButton(75) and povButton(75).active == true,
    "Next Target must be clickable with two candidates")
assert(povButton(76) and povButton(76).active == true,
    "Previous Target must be clickable with two candidates")

sess30.controlMode = "auto"
gcMenu.display()
assert(povButton(75) == nil and povButton(76) == nil,
    "Auto-engage must not offer the target cycling buttons at all")

-- ── 33. leaving direct mode unregisters the element panel's frame ────────────
-- clearDataForRefresh() does not touch menu.frames, so a frame left over from a
-- previous display() stays registered as its own view ("Helper" .. layer) and
-- keeps rendering. Only Helper.clearFrame() unregisters it.
sess30.controlMode = "direct"
sess30.targetObjectID = 500
clearedFrames = {}
gcMenu.display()
assert(#clearedFrames == 0, "nothing to clear while the element panel is shown")
sess30.phase = "target_select"
gcMenu.display()
assert(clearedFrames[1] == 3,
    "leaving the element panel must clearFrame its layer; cleared "
    .. tostring(clearedFrames[1]))

-- ── 34. Esc out of a cinematic returns to the manual panel ──────────────────
-- The cutscene runs with duration 999999 and cinematicmode's HUD-off state; if
-- Esc falls through to the ordinary close path it keeps running invisibly under
-- the panels until the session ends.
gcMenu.onShowMenu()
local sess34 = API.getSession()
assert(sess34 ~= nil, "expected session for cinematic Esc test")
sess34.groups = { grp27 }
sess34.checkedGroupKeys = { ["grp27"] = true }
sess34.phase = "engaged"
sess34.controlMode = "direct"
sess34.cameraMemberID = 27
sess34.povAnchor, sess34.povMode = "target", "cinematic"
gcMenu.onCloseElement("back")
assert(sess34.povMode == "manual",
    "Esc from a cinematic must return to the manual POV; povMode=" .. tostring(sess34.povMode))
assert(sess34.povAnchor == "turret",
    "Esc from a cinematic must return to the default turret anchor; povAnchor=" .. tostring(sess34.povAnchor))
assert(sess34.phase == "engaged",
    "Esc from a cinematic must stay in the engaged phase; phase=" .. tostring(sess34.phase))

-- ── 35. the engine ending the cutscene syncs the panel back ─────────────────
-- The player's first Esc during a cinematic goes to the cutscene, not to our
-- frame. Without this the panel still believes the cinematic is current: one
-- more Esc to repaint it, a third to actually go back a menu.
gcMenu.onShowMenu()
local sess35 = API.getSession()
assert(sess35 ~= nil, "expected session for cutscene sync test")
sess35.groups = { grp27 }
sess35.checkedGroupKeys = { ["grp27"] = true }
sess35.phase = "engaged"
sess35.controlMode = "auto"
sess35.cameraMemberID = 27
sess35.povAnchor, sess35.povMode = "target", "cinematic"
C.IsFullscreenCutsceneActive = function() return true end
clock = clock + 10
gcMenu.onUpdate()
assert(sess35.povMode == "cinematic",
    "a running cutscene must leave the cinematic POV alone")
C.IsFullscreenCutsceneActive = function() return false end
clock = clock + 10
gcMenu.onUpdate()
assert(sess35.povMode == "manual" and sess35.povAnchor == "turret",
    "an externally ended cutscene must return to Turret POV manual; got "
    .. tostring(sess35.povAnchor) .. "/" .. tostring(sess35.povMode))

-- A cinematic that has not been seen running yet must not be cancelled: the
-- retarget restart briefly leaves no cutscene active.
sess35.povAnchor, sess35.povMode = "target", "cinematic"
C.IsFullscreenCutsceneActive = function() return true end
clock = clock + 10
gcMenu.onUpdate()                                     -- observes it running
X4GunneryControlAPI.sendCutsceneAimStart("turret")    -- retarget restart
C.IsFullscreenCutsceneActive = function() return false end
clock = clock + 10
gcMenu.onUpdate()
assert(sess35.povMode == "cinematic",
    "the gap between a cutscene stop and its restart must not cancel the cinematic")

-- Helper to drain and return all pending callbacks accumulated after a given
-- index, so tests can examine just the ones triggered by a specific path.
local function callbacksAfter(index)
    local result = {}
    for i = index + 1, #pendingCallbacks do
        result[#result + 1] = pendingCallbacks[i]
    end
    return result
end

-- ── 36. get-up discards the session now but closes the frames a tick later ───
-- Vanilla closes from the playerGetUp event rather than inside its Get Up
-- handler (menu_docked.lua:283,1442); closing synchronously unregisters our
-- view in the middle of the engine's get-up transition.
gcMenu.onShowMenu()
local sess36 = API.getSession()
assert(sess36 ~= nil, "expected session for teardown ordering test")
sess36.phase = "console"
local before36 = #pendingCallbacks
closeMenuCalls = 0
gcMenu.onCloseElement("close")
assert(API.getSession() == nil, "get-up must discard the session immediately")
assert(closeMenuCalls == 0,
    "get-up must not close the frames in the same call as GetUp(); closeMenu ran "
    .. tostring(closeMenuCalls) .. " time(s)")
local deferred36 = callbacksAfter(before36)
for _, fn in ipairs(deferred36) do fn() end
assert(closeMenuCalls == 1,
    "the deferred callback must close the menu exactly once; got " .. tostring(closeMenuCalls))

-- ── 37. teardown must not unregister our views before closing the menu ───────
-- helper.lua's closeMenu() untracks the menu first (C.RemoveTrackedMenu) and
-- only then lets clearMenu() unregister the views (helper.lua:1908-1947).
-- Unregistering first hid the view while the menu was still tracked, and after
-- a session that opened a playerControls frame the engine then stopped
-- delivering Esc to the game menu until another menu opened and closed.
gcMenu.onShowMenu()
local sess37 = API.getSession()
assert(sess37 ~= nil, "expected session for teardown order test")
sess37.groups = { grp27 }
sess37.checkedGroupKeys = { ["grp27"] = true }
sess37.phase = "engaged"
sess37.controlMode = "direct"
sess37.directSnapshots = {}
sess37.cameraMemberID = 27
sess37.targetObjectID = 500
gcMenu.display()
assert(frameCount == 2, "precondition: two frames must be registered")
teardownTrace = {}
local before37 = #pendingCallbacks
gcMenu.onCloseElement("close")
for _, fn in ipairs(callbacksAfter(before37)) do fn() end
assert(teardownTrace[1] == "close",
    "get-up must close the menu before touching its views; trace was "
    .. table.concat(teardownTrace, ","))

-- ── 38. every frame agrees on keepHUDVisible and paints a background ─────────
-- X4 exposes no HUD setter: a frame that replaces another on the same layer
-- with a different keepHUDVisible leaves the standing player with no HUD, and
-- nothing can turn it back on. The value must be true on every frame the menu
-- ever builds, in every phase. The background is what keeps cell text legible
-- over the live view.
assert(#allFrames >= 3, "expected several frames across the phases exercised above")
for i, record in ipairs(allFrames) do
    assert(record.props.keepHUDVisible == true,
        "frame #" .. i .. " (layer " .. tostring(record.props.layer) .. ") must set "
        .. "keepHUDVisible = true; got " .. tostring(record.props.keepHUDVisible))
    assert(record.background,
        "frame #" .. i .. " (layer " .. tostring(record.props.layer)
        .. ") must call setBackground so its cell text stays readable")
end

-- ── 39. Auto-next Target on: a dead target takes the turrets along ───────────
-- The old behaviour moved only session.aimTargetID, so the camera followed the
-- next ship while the groups stayed armed against a wreck: the soft target and
-- session.targetObjectID both still named the dead one. Re-engaging is what
-- moves all three together, so assert on targetObjectID, not just the aim.
gcMenu.onShowMenu()
local sess39 = API.getSession()
assert(sess39 ~= nil, "expected session for auto-next test")
assert(sess39.autoNextTarget == true, "Auto-next Target must default to on")
sess39.groups = { grp27 }
sess39.checkedGroupKeys = { ["grp27"] = true }
sess39.phase = "engaged"
sess39.controlMode = "direct"
sess39.directSnapshots = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess39.shipID, mode = "attack", armed = false } }
sess39.cameraMemberID = 27
sess39.targetObjectID = 500
sess39.aimTargetID = 500
sess39.povAnchor, sess39.povMode = "turret", "manual"

GetPlayerContextByClass = function() return 1 end
GetContainedShips = function() return { 98 } end
GetContainedStations = function() return {} end
C.GetContextByClass = function(comp) return comp end
C.GetDistanceBetween = function() return 1000 end
C.SetSofttarget = function() return true end
C.SetPlayerCameraTargetView = function() return true end
GetComponentData = function(component, ...)
    local keys, vals = {...}, {}
    for _, k in ipairs(keys) do
        if k == "isenemy" then vals[#vals + 1] = true
        elseif k == "isknown" then vals[#vals + 1] = true
        elseif k == "isradarvisible" then vals[#vals + 1] = true
        elseif k == "maxradarrange" then vals[#vals + 1] = 40000
        elseif k == "isplayerowned" then vals[#vals + 1] = true
        else vals[#vals + 1] = false
        end
    end
    return unpack(vals)
end
-- The engaged target 500 is destroyed; 98 is the only survivor.
C.IsComponentOperational = function(cid) return tostring(cid) == "98" end
X4GunneryControlAPI.updateAimTarget()
assert(tostring(sess39.aimTargetID) == "98",
    "auto-next must move the aim to the survivor; got " .. tostring(sess39.aimTargetID))
assert(tostring(sess39.targetObjectID) == "98",
    "auto-next must re-engage rather than only move the camera; targetObjectID stayed "
    .. tostring(sess39.targetObjectID))
assert(sess39.phase == "engaged",
    "auto-next must stay engaged; phase became " .. tostring(sess39.phase))

-- ── 40. the engaged/direct panel offers the toggle, checked by default ───────
gcMenu.display()
assert(#createdCheckBoxes == 1,
    "the engaged/direct panel must offer exactly one checkbox (Auto-next Target); got "
    .. tostring(#createdCheckBoxes))
assert(createdCheckBoxes[1].checked == true,
    "the Auto-next Target checkbox must be checked while session.autoNextTarget is on")

-- ── 41. Auto-next Target off: a dead target returns to the picker ────────────
-- Reset the view first: one Esc's worth of state, so whatever cinematic was on
-- screen is gone and the player lands back on the manual Turret POV before the
-- target browser reopens.
sess39.autoNextTarget = false
sess39.phase = "engaged"
sess39.aimTargetID = 500
sess39.targetObjectID = 500
sess39.povAnchor, sess39.povMode = "target", "cinematic"
X4GunneryControlAPI.updateAimTarget()
assert(sess39.phase == "target_select",
    "with auto-next off a dead target must reopen the target browser; phase is "
    .. tostring(sess39.phase))
assert(sess39.povAnchor == "turret" and sess39.povMode == "manual",
    "with auto-next off the view must reset to manual Turret POV; got "
    .. tostring(sess39.povAnchor) .. "/" .. tostring(sess39.povMode))

-- ── 42. a soft target that was empty is restored by clearing, not by zero ────
-- No vanilla call ever passes 0 to SetSofttarget; RemoveSofttarget() is the
-- engine's clear (targetsystem.lua:1747,2097,2130, and our own Test Lab path).
-- Passing 0 leaves the soft target on the turret enterCamera borrowed, i.e. on
-- a component of the player's own ship, which is a state vanilla never creates.
local removeSofttargetCalls = 0
local softtargetSets = {}
RemoveSofttarget = function() removeSofttargetCalls = removeSofttargetCalls + 1 end
C.SetSofttarget = function(cid) softtargetSets[#softtargetSets + 1] = tostring(cid); return true end
-- Nothing targeted before the session, which is the ordinary case.
C.GetSofttarget2 = function() return { softtargetID = 0, softtargetConnectionName = "" } end
gcMenu.onShowMenu()
local sess42 = API.getSession()
assert(sess42 ~= nil, "expected session for softtarget restore test")
sess42.groups = { grp27 }
sess42.checkedGroupKeys = { ["grp27"] = true }
sess42.phase = "engaged"
sess42.controlMode = "direct"
sess42.directSnapshots = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess42.shipID, mode = "attack", armed = false } }
sess42.cameraMemberID = 27
sess42.autoNextTarget = true
C.IsComponentOperational = function() return true end
-- enterCamera's camera gate retries while the focus does not match the turret,
-- which is the path that borrows and then restores the soft target.
C.GetExternalTargetViewComponent = function() return 7 end
local before42 = #pendingCallbacks
X4GunneryControlAPI.cycleTarget(1)
for _ = 1, 3 do
    for _, fn in ipairs(callbacksAfter(before42)) do fn() end
end
assert(removeSofttargetCalls > 0,
    "restoring an empty soft target must call RemoveSofttarget()")
for _, cid in ipairs(softtargetSets) do
    assert(cid ~= "0",
        "SetSofttarget(0) is not a documented clear; use RemoveSofttarget()")
end

-- ── 43. get-up never leaves the soft target on the player's own ship ─────────
-- enterCamera borrows the soft target to force the camera onto a turret. If a
-- borrowed one survives the session the player stands up still soft-targeting
-- their own turret.
gcMenu.onShowMenu()
local sess43 = API.getSession()
assert(sess43 ~= nil, "expected session for softtarget teardown test")
sess43.phase = "console"
-- Soft target 27 resolves to the session's own ship.
C.GetSofttarget2 = function() return { softtargetID = 27, softtargetConnectionName = "" } end
C.GetContextByClass = function() return sess43.shipID end
removeSofttargetCalls = 0
gcMenu.onCloseElement("close")
assert(removeSofttargetCalls > 0,
    "get-up must clear a soft target that points at the player's own ship")

-- ── 44. leaveChair emits a notify UI event; text depends on direct snapshots ──
-- X4 engine bug: SetPlayerCameraTargetView from a turret seat leaves Esc dead
-- after the player gets up. The only observed cure is a menu that calls
-- CreateView/DisplayView (View.createView in ego_viewhelper). The helptext
-- popup emitted here is a real user-facing feature AND is the confirmed cure
-- mechanism: show_help forces that path in MD. Do NOT make this popup
-- conditional or suppress it without re-testing Esc after a camera session.
--
-- 44a: direct snapshots were held -> restored-settings text (text id 79).
-- 44b: no direct snapshots         -> disengaged text (text id 80).

C.GetSofttarget2 = function() return { softtargetID = 0, softtargetConnectionName = "" } end
C.GetContextByClass = function(...) return 42 end

-- 44a: session WITH direct snapshots.
capturedEvents = {}
gcMenu.onShowMenu()
local sess44a = API.getSession()
assert(sess44a ~= nil, "expected session for notify test (44a)")
sess44a.phase = "console"
sess44a.directSnapshots = { { kind = "group", contextID = 0, path = "fake", group = "grp",
    shipID = sess44a.shipID, mode = "attack", armed = true, componentID = 55 } }
AddUITriggeredEvent = function(screen, control, params)
    capturedEvents[#capturedEvents + 1] = { screen = screen, control = control, params = params }
end
gcMenu.onCloseElement("close")
local notifyEvA = nil
for _, e in ipairs(capturedEvents) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then notifyEvA = e; break end
end
assert(notifyEvA ~= nil,
    "leaveChair must emit AddUITriggeredEvent('X4GunneryControl','notify',...) when direct snapshots were held")
assert(type(notifyEvA.params) == "table",
    "notify event params must be a table")
assert(notifyEvA.params["text"] == ReadText(20991, 79),
    "notify text with direct snapshots must be ReadText(20991, 79) (restored-settings); got: "
    .. tostring(notifyEvA.params["text"]))

-- 44b: session WITHOUT direct snapshots.
capturedEvents = {}
gcMenu.onShowMenu()
local sess44b = API.getSession()
assert(sess44b ~= nil, "expected session for notify test (44b)")
sess44b.phase = "console"
-- directSnapshots is empty by default from onShowMenu.
gcMenu.onCloseElement("close")
local notifyEvB = nil
for _, e in ipairs(capturedEvents) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then notifyEvB = e; break end
end
assert(notifyEvB ~= nil,
    "leaveChair must emit AddUITriggeredEvent('X4GunneryControl','notify',...) when no direct snapshots were held")
assert(notifyEvB.params["text"] == ReadText(20991, 80),
    "notify text without direct snapshots must be ReadText(20991, 80) (disengaged); got: "
    .. tostring(notifyEvB.params["text"]))

-- ── 45. playerGetUp route emits the notify exactly once ─────────────────────
-- endForMovement (registered on playerGetUp/playerUndock) sets seatLeaving=true,
-- calls endSession -> discardSession, then clears seatLeaving. discardSession
-- must emit the notify under that seatLeaving=true guard.
-- Mutation check: verify notify is emitted (would fail if seatLeaving guard
-- were inverted or if the emission were accidentally removed from discardSession).
capturedEvents = {}
gcMenu.onShowMenu()
local sess45 = API.getSession()
assert(sess45 ~= nil, "expected session for playerGetUp notify test (45)")
sess45.phase = "console"
sess45.directSnapshots = {}
AddUITriggeredEvent = function(screen, control, params)
    capturedEvents[#capturedEvents + 1] = { screen = screen, control = control, params = params }
end
assert(type(X4GunneryControlAPI.endForMovement) == "function",
    "X4GunneryControlAPI.endForMovement must be exposed for testing")
X4GunneryControlAPI.endForMovement()
local notifyEvts45 = {}
for _, e in ipairs(capturedEvents) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then
        notifyEvts45[#notifyEvts45 + 1] = e
    end
end
assert(#notifyEvts45 == 1,
    "playerGetUp route must emit exactly one notify event; got " .. tostring(#notifyEvts45))
assert(notifyEvts45[1].params["text"] == ReadText(20991, 80),
    "playerGetUp with no direct snapshots must use disengaged text (80); got: "
    .. tostring(notifyEvts45[1].params["text"]))

-- ── 46. playerUndock route emits the notify too ──────────────────────────────
-- Same endForMovement handler is registered for both events, so this verifies
-- the shared path covers undock as well.
-- Mutation check: assert exactly one notify (would catch accidental double-emit
-- if the emission were also left in leaveChair, which the playerGetUp path
-- does NOT go through).
capturedEvents = {}
gcMenu.onShowMenu()
local sess46 = API.getSession()
assert(sess46 ~= nil, "expected session for playerUndock notify test (46)")
sess46.phase = "console"
sess46.directSnapshots = {}
X4GunneryControlAPI.endForMovement()   -- same handler; reuse the same exposure
local notifyEvts46 = {}
for _, e in ipairs(capturedEvents) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then
        notifyEvts46[#notifyEvts46 + 1] = e
    end
end
assert(#notifyEvts46 == 1,
    "playerUndock route must emit exactly one notify event; got " .. tostring(#notifyEvts46))

-- ── 47. stale-session discardSession (seatLeaving=false) emits NO notify ─────
-- The "stale session before chair redirect" call in the gameplanchange handler
-- calls discardSession without ever setting seatLeaving=true. The player has
-- just sat down; a popup would be wrong and confusing.
-- Mutation check: this is the NEGATIVE case. If the seatLeaving guard were
-- removed from discardSession the assert below would catch it.
capturedEvents = {}
gcMenu.onShowMenu()
local sess47 = API.getSession()
assert(sess47 ~= nil, "expected session for stale-session no-notify test (47)")
sess47.phase = "console"
-- Reach discardSession with seatLeaving=false by using a fresh onShowMenu,
-- which recreates the session (triggering "stale session at chair ingress" ->
-- discardSession without touching seatLeaving).
-- First set up a map-suspended session to ensure a discard path that bypasses
-- leaveChair: use X4GunneryState.lifecycle.owned with autoHideAt set so the
-- watchdog would call discardSession, but to be deterministic call via
-- onShowMenu (which discards a stale session with seatLeaving still false).
-- Simplest approach: set the session to a state that onShowMenu will discard
-- (different ship), confirming the "stale session before chair redirect" path.
sess47.shipID = 9999   -- force mismatch so onShowMenu discards it
gcMenu.onShowMenu()
local notifyEvts47 = {}
for _, e in ipairs(capturedEvents) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then
        notifyEvts47[#notifyEvts47 + 1] = e
    end
end
assert(#notifyEvts47 == 0,
    "discardSession with seatLeaving=false must NOT emit notify; got "
    .. tostring(#notifyEvts47) .. " notify event(s). "
    .. "The seatLeaving guard in discardSession is broken or missing.")

-- ── 48. exactly one notify per teardown; double teardown does not double-emit ─
-- leaveChair calls C.GetUp(), which in-game also fires playerGetUp, so
-- endForMovement runs again for the same session. The session/epoch guards make
-- the second call a no-op (session is already nil after discardSession). Assert
-- that explicitly: endForMovement called immediately after an already-discarded
-- session emits zero notify events.
capturedEvents = {}
gcMenu.onShowMenu()
local sess48 = API.getSession()
assert(sess48 ~= nil, "expected session for double-teardown test (48)")
sess48.phase = "console"
sess48.directSnapshots = {}
-- First teardown via endForMovement (simulates playerGetUp route).
X4GunneryControlAPI.endForMovement()
local firstPassEvts = {}
for _, e in ipairs(capturedEvents) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then
        firstPassEvts[#firstPassEvts + 1] = e
    end
end
assert(#firstPassEvts == 1,
    "first endForMovement call must emit exactly one notify; got " .. tostring(#firstPassEvts))
-- Second teardown with no session (simulates the in-game double-fire of playerGetUp).
capturedEvents = {}
X4GunneryControlAPI.endForMovement()
local secondPassEvts = {}
for _, e in ipairs(capturedEvents) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then
        secondPassEvts[#secondPassEvts + 1] = e
    end
end
assert(#secondPassEvts == 0,
    "second endForMovement after session is already nil must emit zero notify events; "
    .. "the epoch/session guard is broken. Got " .. tostring(#secondPassEvts))

-- ── 49. RestoreSession handler: both plain-key and $-prefixed payloads restore ──
-- The engine PREPENDS $ to every Lua string key during Lua->MD conversion
-- (live-tested 2026-08-04). After a save/load, State.$active may come back from
-- raise_lua_event with keys like "$shipID" instead of "shipID". The handler must
-- restore turret groups regardless of which form arrives.
--
-- The handler is exposed via X4GunneryControlAPI.onRestoreSession for test use.

assert(type(X4GunneryControlAPI.onRestoreSession) == "function",
    "X4GunneryControlAPI.onRestoreSession must be exposed; add TestAPI.onRestoreSession in gunnery_control.lua")

-- Helper: build a "group" snapshot with a specific key prefix form.
local function makeSnap49(prefix, shipID, path, group)
    local p = prefix or ""
    return {
        [p .. "shipID"]    = tostring(shipID),
        [p .. "kind"]      = "group",
        [p .. "mode"]      = "defend",
        [p .. "armed"]     = false,
        [p .. "contextID"] = "1",
        [p .. "path"]      = path,
        [p .. "group"]     = group,
    }
end

-- Helper: run one RestoreSession handler invocation and capture what was parsed.
-- Returns (newSessionShipID, capturedDirectSnapshots).
local function runRestore49(payload)
    local newSessionShipID = nil
    local capturedSnapshots = nil
    local origNewSession = X4GunneryState.newSession
    X4GunneryState.newSession = function(ship, reason)
        newSessionShipID = ship
        return origNewSession(ship, reason)
    end
    local origRelease = X4GunneryState.releaseDirect
    X4GunneryState.releaseDirect = function(sess)
        capturedSnapshots = sess.directSnapshots
        return origRelease(sess)
    end
    X4GunneryControlAPI.onRestoreSession(nil, payload)
    X4GunneryState.newSession = origNewSession
    X4GunneryState.releaseDirect = origRelease
    return newSessionShipID, capturedSnapshots
end

-- 49a: plain-key list payload (the form the handler always produced before this fix).
local plainPayload49 = {
    makeSnap49("", 42, "p49", "A"),
    makeSnap49("", 42, "p49", "B"),
}
local shipA, snapsA = runRestore49(plainPayload49)
assert(shipA ~= nil,
    "RestoreSession with plain-key list must call State.newSession; shipID was nil")
assert(tostring(shipA) == "42",
    "RestoreSession plain-key: wrong shipID; expected '42', got " .. tostring(shipA))
assert(snapsA ~= nil and #snapsA == 2,
    "RestoreSession plain-key: expected 2 normalised snapshots in directSnapshots; got "
    .. tostring(snapsA and #snapsA))
assert(snapsA[1].kind == "group",
    "RestoreSession plain-key: snapshot[1].kind must be 'group'; got "
    .. tostring(snapsA[1].kind))
assert(snapsA[1].path == "p49",
    "RestoreSession plain-key: snapshot[1].path must be 'p49'; got "
    .. tostring(snapsA[1].path))

-- 49b: $-prefixed list payload (the form that arrives if MD->Lua keeps the $ prefix).
local prefixedPayload49 = {
    makeSnap49("$", 42, "p49", "A"),
    makeSnap49("$", 42, "p49", "B"),
}
local shipB, snapsB = runRestore49(prefixedPayload49)
assert(shipB ~= nil,
    "RestoreSession with $-prefixed list must call State.newSession; shipID was nil. "
    .. "The handler is not reading $-prefixed keys from the MD payload.")
assert(tostring(shipB) == "42",
    "RestoreSession $-prefixed: wrong shipID; expected '42', got " .. tostring(shipB))
assert(snapsB ~= nil and #snapsB == 2,
    "RestoreSession $-prefixed: expected 2 normalised snapshots; got "
    .. tostring(snapsB and #snapsB))
assert(snapsB[1].kind == "group",
    "RestoreSession $-prefixed: snapshot[1].kind must be 'group'; got "
    .. tostring(snapsB[1].kind))
assert(snapsB[1].path == "p49",
    "RestoreSession $-prefixed: snapshot[1].path must be 'p49'; got "
    .. tostring(snapsB[1].path))

-- 49c: legacy single-snapshot plain-key form (shipID present, no [1]).
local legacyPlain49 = makeSnap49("", 42, "p49", "A")
local shipC, snapsC = runRestore49(legacyPlain49)
assert(shipC ~= nil,
    "RestoreSession legacy plain-key single snapshot must call State.newSession")
assert(snapsC ~= nil and #snapsC == 1,
    "RestoreSession legacy plain-key: expected 1 snapshot; got "
    .. tostring(snapsC and #snapsC))
assert(snapsC[1].path == "p49",
    "RestoreSession legacy plain-key: snapshot[1].path must be 'p49'; got "
    .. tostring(snapsC[1].path))

-- 49d: legacy single-snapshot $-prefixed form.
local legacyPrefixed49 = makeSnap49("$", 42, "p49", "A")
local shipD, snapsD = runRestore49(legacyPrefixed49)
assert(shipD ~= nil,
    "RestoreSession legacy $-prefixed single snapshot must call State.newSession. "
    .. "The handler is not reading the $shipID key from the legacy form.")
assert(snapsD ~= nil and #snapsD == 1,
    "RestoreSession legacy $-prefixed: expected 1 snapshot; got "
    .. tostring(snapsD and #snapsD))
assert(snapsD[1].path == "p49",
    "RestoreSession legacy $-prefixed: snapshot[1].path must be 'p49'; got "
    .. tostring(snapsD[1].path))

-- 49e: diagnostic log line is emitted.
assert(logContains("RestoreSession:"),
    "RestoreSession handler must emit a diagnostic log line containing 'RestoreSession:'")

-- ── 50. startAutoEngage failure path clears controlMode ──────────────────────
-- Regression: beginEngaged sets session.controlMode = "auto" before trying to
-- enter the camera. When no operational camera member exists, the old code did
-- `session.phase = "console"; return false`, leaving controlMode stuck on "auto"
-- while phase said "console". returnToConsole() must be used instead so phase,
-- controlMode, povMode, cameraMemberID, and targetObjectID are all cleared together.
gcMenu.onShowMenu()
local sess50 = API.getSession()
assert(sess50 ~= nil, "expected session for startAutoEngage failure test (50)")
-- Build a group with NO operational members so cameraMember() returns nil and
-- startAutoEngage hits its first failure exit.
local grp50 = {
    key = "grp50", kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 30, displayName = "Empty Group", totalCount = 1, operationalCount = 0,
    mode = "attack", armed = false, members = {
        { componentID = 30, displayName = "T1", operational = false,
          cameraSupported = false, componentKey = "30" }
    }
}
sess50.groups = { grp50 }
sess50.checkedGroupKeys = { ["grp50"] = true }
sess50.phase = "console"
sess50.controlMode = nil
-- Same arguments the console Auto-Engage button passes. startAutoEngage is
-- module-local; TestAPI exposes it, like TestAPI.endForMovement above.
local engaged50 = API.startAutoEngage(X4GunneryState.checkedGroups(sess50))
assert(engaged50 == false,
    "startAutoEngage with no operational camera member must return false; got "
    .. tostring(engaged50))
-- After the failure, phase must be "console" and controlMode must be nil.
assert(sess50.phase == "console",
    "startAutoEngage failure path must leave phase='console'; got '"
    .. tostring(sess50.phase) .. "'")
assert(sess50.controlMode == nil,
    "BUG: startAutoEngage failure path left controlMode='"
    .. tostring(sess50.controlMode)
    .. "'; State.returnToConsole must be used instead of raw phase assignment")

-- ── 51. readTargetCandidates cache: two quick repaints share one sweep ─────────
-- The cache must serve the second display() call from session.targetCandidates
-- without calling GetContainedShips a second time. The browser/force path must
-- always bypass the cache and call GetContainedShips.

local shipScanCount51 = 0
GetContainedShips = function() shipScanCount51 = shipScanCount51 + 1; return { 98 } end
GetContainedStations = function() return {} end
GetPlayerContextByClass = function() return 1 end
C.GetContextByClass = function(comp, cls, self_) return comp end
C.IsComponentOperational = function() return true end
C.GetDistanceBetween = function() return 1000 end
GetComponentData = function(component, ...)
    local keys, vals = {...}, {}
    for _, k in ipairs(keys) do
        if k == "isenemy" then vals[#vals + 1] = true
        elseif k == "ishostile" then vals[#vals + 1] = false
        elseif k == "isfriend" then vals[#vals + 1] = false
        elseif k == "isknown" then vals[#vals + 1] = true
        elseif k == "isradarvisible" then vals[#vals + 1] = true
        elseif k == "maxradarrange" then vals[#vals + 1] = 40000
        elseif k == "isplayerowned" then vals[#vals + 1] = true
        else vals[#vals + 1] = nil
        end
    end
    return unpack(vals)
end

gcMenu.onShowMenu()
local sess51 = API.getSession()
assert(sess51 ~= nil, "expected session for cache test (51)")

-- Set up a direct/engaged session with two snapshots so the compact panel renders.
local grp51 = { key = "grp51", kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 27, displayName = "G51", totalCount = 1, operationalCount = 1,
    mode = "attack", armed = false, members = {
        { componentID = 27, displayName = "T1", operational = true,
          cameraSupported = true, componentKey = "27" }
    } }
sess51.groups = { grp51 }
sess51.checkedGroupKeys = { ["grp51"] = true }
sess51.phase = "engaged"
sess51.controlMode = "direct"
sess51.directSnapshots = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess51.shipID, mode = "attack", armed = false } }
sess51.cameraMemberID = 27
sess51.targetObjectID = 98
sess51.aimTargetID = 98
sess51.targetCandidates = {}   -- start empty so first call always sweeps

-- Move the clock forward so the cache from any prior test is stale.
clock = clock + 100
getElapsedTime = function() return clock end

-- First display(): must sweep (cache is empty / time-expired).
shipScanCount51 = 0
local ok51a, err51a = pcall(function() gcMenu.display() end)
assert(ok51a, "display() raised on first call (test 51): " .. tostring(err51a))
local sweepsAfterFirst = shipScanCount51
assert(sweepsAfterFirst >= 1,
    "first display() must call GetContainedShips at least once; got " .. tostring(sweepsAfterFirst))

-- Second display() immediately (same clock): must reuse cache, no new sweep.
shipScanCount51 = 0
local ok51b, err51b = pcall(function() gcMenu.display() end)
assert(ok51b, "display() raised on second call (test 51): " .. tostring(err51b))
assert(shipScanCount51 == 0,
    "second display() within the TTL must not rescan; GetContainedShips was called "
    .. tostring(shipScanCount51) .. " time(s). Cache is not working.")

-- Target-browser path (force=true): must always sweep even within the TTL.
-- Simulate the browser by switching to target_select phase (what openTargetBrowser does).
-- We reach the forced path by calling the browser display branch directly:
-- set phase to target_select and call display().
sess51.phase = "target_select"
shipScanCount51 = 0
local ok51c, err51c = pcall(function() gcMenu.display() end)
assert(ok51c, "display() raised in browser phase (test 51): " .. tostring(err51c))
assert(shipScanCount51 >= 1,
    "target-browser display() must always sweep (force=true); GetContainedShips was called "
    .. tostring(shipScanCount51) .. " time(s)")

-- ── 52. readGroups: duplicate path+group names must stay controllable ─────
-- Two groups sharing path+group but with different contextIDs. The slot API
-- returns no contextID, so slot->group attribution is a guess -- but mode and
-- armed commands address contextID+path+group directly and are always exact.
-- So a duplicate name must never make a group read-only.
--
-- The 2-turrets-per-group shape is the one that matters: only one slot per
-- group carries the group's representative componentID, so any scheme that
-- keys off "did this slot match" fails on the other slots.

do
    local savedGetNumUpgradeGroups  = C.GetNumUpgradeGroups
    local savedGetUpgradeGroups2    = C.GetUpgradeGroups2
    local savedGetUpgradeGroupInfo2 = C.GetUpgradeGroupInfo2
    local savedGetNumUpgradeSlots   = C.GetNumUpgradeSlots
    local savedGetUpgradeSlotCurrentComponent = C.GetUpgradeSlotCurrentComponent
    local savedGetUpgradeSlotGroup  = C.GetUpgradeSlotGroup
    local savedFfiNew               = ffiStub.new

    -- ffi.new must hand back a 0-based buffer of UpgradeGroup2-shaped entries.
    local groupBuffer = {}
    groupBuffer[0] = { path = "p", group = "grp_front", contextid = 10 }
    groupBuffer[1] = { path = "p", group = "grp_front", contextid = 20 }
    local turretsPerGroup, slotComponents = 2, {}

    C.GetNumUpgradeGroups  = function() return 2 end
    C.GetUpgradeGroups2    = function() return 2 end
    C.GetUpgradeGroupInfo2 = function(ship, macro, ctxid)
        -- Each group reports ONE representative component: 101 for ctx 10,
        -- 102 for ctx 20. The group's other turrets are not reported here.
        return { count = turretsPerGroup, currentcomponent = (tostring(ctxid) == "10") and 101 or 102,
                 currentmacro = "", slotsize = "", total = turretsPerGroup, operational = turretsPerGroup }
    end
    C.GetNumUpgradeSlots             = function() return #slotComponents end
    C.GetUpgradeSlotCurrentComponent = function(ship, tag, slot) return slotComponents[slot] or 0 end
    C.GetUpgradeSlotGroup            = function() return { path = "p", group = "grp_front" } end
    ffiStub.new                      = function() return groupBuffer end

    local function groupByContext(groups, ctx)
        for _, g in ipairs(groups) do
            if g.kind == "group" and tostring(g.contextID) == ctx then return g end
        end
    end
    local function hasMember(group, componentID)
        for _, m in ipairs(group.members or {}) do
            if tostring(m.componentID) == tostring(componentID) then return true end
        end
        return false
    end

    -- 52a: two turrets per group. Slots 1/3 carry the representatives (101,
    --      102); slots 2/4 carry non-representative turrets (103, 104) that
    --      match no group's componentID.
    turretsPerGroup = 2
    slotComponents = { 101, 103, 102, 104 }
    local groups52a = X4GunneryControlAPI.readGroups(42)
    local front52a, rear52a = groupByContext(groups52a, "10"), groupByContext(groups52a, "20")
    assert(front52a and rear52a,
        "52a: expected group entries for contextID 10 and 20")
    assert(X4GunneryState.canMutate(front52a) and X4GunneryState.canMutate(rear52a),
        "52a BUG: a duplicate path+group name must not make a group read-only. "
        .. "Mode/armed commands address contextID+path+group, which is exact. Got canMutate "
        .. tostring(X4GunneryState.canMutate(front52a)) .. "/" .. tostring(X4GunneryState.canMutate(rear52a)))
    assert(front52a.ambiguous == nil and rear52a.ambiguous == nil,
        "52a: readGroups must not set an ambiguous flag any more")
    assert(hasMember(front52a, 101),
        "52a: the slot carrying group 10's representative component (101) must be listed under group 10")
    assert(hasMember(rear52a, 102),
        "52a: the slot carrying group 20's representative component (102) must be listed under group 20")
    local members52a = #front52a.members + #rear52a.members
    assert(members52a == #slotComponents,
        "52a: every turret slot must appear exactly once across the groups; expected "
        .. tostring(#slotComponents) .. " members, got " .. tostring(members52a))

    -- 52b: one turret per group -- the common case, and the only shape the
    --      previous fix handled. Both groups still resolve and stay mutable.
    turretsPerGroup = 1
    slotComponents = { 101, 102 }
    local groups52b = X4GunneryControlAPI.readGroups(42)
    local front52b, rear52b = groupByContext(groups52b, "10"), groupByContext(groups52b, "20")
    assert(front52b and rear52b, "52b: expected group entries for contextID 10 and 20")
    assert(X4GunneryState.canMutate(front52b) and X4GunneryState.canMutate(rear52b),
        "52b: single-turret duplicate-named groups must be mutable")
    assert(hasMember(front52b, 101) and hasMember(rear52b, 102),
        "52b: each representative component must land in its own group")

    C.GetNumUpgradeGroups             = savedGetNumUpgradeGroups
    C.GetUpgradeGroups2               = savedGetUpgradeGroups2
    C.GetUpgradeGroupInfo2            = savedGetUpgradeGroupInfo2
    C.GetNumUpgradeSlots              = savedGetNumUpgradeSlots
    C.GetUpgradeSlotCurrentComponent  = savedGetUpgradeSlotCurrentComponent
    C.GetUpgradeSlotGroup             = savedGetUpgradeSlotGroup
    ffiStub.new                       = savedFfiNew
end

-- ── 53. ship-wide "prefer my target" override ────────────────────────────────
-- The override is worthless on a turret still sitting in autoassist: X4 ignores
-- supplied targets for that mode (fight.attack.object.capital.xml:1756), so a
-- turret left there keeps idling while the button looks like it worked. That is
-- the fault the 2026-08-07 trial caught, hence the mode-write assertions.
do
    gcMenu.onShowMenu()
    local sess53 = API.getSession()
    assert(sess53 ~= nil, "expected session for prefer-all-turrets test")
    local grp53 = { key = "grp53", kind = "group", contextID = 5, path = "p", group = "g",
        componentID = 53, displayName = "G53", totalCount = 1, operationalCount = 1,
        mode = "autoassist", armed = true, members = {
            { componentID = 53, displayName = "T1", operational = true,
              cameraSupported = true, componentKey = "53" }
        } }
    sess53.groups = { grp53 }
    sess53.checkedGroupKeys = { ["grp53"] = true }
    sess53.phase, sess53.controlMode = "engaged", "direct"
    sess53.aimTargetID, sess53.targetObjectID = 500, 500
    -- The pre-engagement mode the console must put the group back into.
    sess53.directSnapshots = { { kind = "group", contextID = 5, path = "p", group = "g",
        shipID = sess53.shipID, mode = "defend", armed = true } }

    assert(sess53.preferAllTurrets == false,
        "the ship-wide override must be off until the player asks for it")

    local modeWrites53 = {}
    local savedSetMode53 = C.SetTurretGroupMode2
    C.SetTurretGroupMode2 = function(ship, ctx, path, group, mode)
        modeWrites53[#modeWrites53 + 1] = tostring(mode)
    end
    local evts53 = {}
    local savedAdd53 = AddUITriggeredEvent
    AddUITriggeredEvent = function(screen, control, params)
        evts53[#evts53 + 1] = { screen = screen, control = control, params = params }
    end

    local before53 = #pendingCallbacks
    assert(API.applyPreferAllTurrets() == true, "applyPreferAllTurrets must report success")
    assert(sess53.preferAllTurrets == true, "applying the override must record it on the session")

    -- Every group the console took over goes back to its own mode, and nothing
    -- is ever written back to autoassist.
    assert(#modeWrites53 > 0, "the override must restore the snapshot mode before issuing")
    for _, m in ipairs(modeWrites53) do
        assert(m ~= "autoassist",
            "the override must never leave a group on autoassist; X4 ignores supplied "
            .. "targets for that mode, so the turret would silently keep idling")
    end
    assert(modeWrites53[1] == "defend",
        "the override must restore the pre-engagement mode; wrote " .. tostring(modeWrites53[1]))

    -- Raised a tick later, so the mode writes above have landed before MD reads
    -- the ship's turret modes back.
    local immediate53 = 0
    for _, e in ipairs(evts53) do
        if e.control == "prefer_all_turrets" then immediate53 = immediate53 + 1 end
    end
    assert(immediate53 == 0,
        "the override event must be deferred a tick, not raised inside the same call")
    for i = before53 + 1, #pendingCallbacks do pcall(pendingCallbacks[i]) end
    local applied53 = nil
    for _, e in ipairs(evts53) do
        if e.control == "prefer_all_turrets" then applied53 = e end
    end
    assert(applied53 ~= nil, "the deferred callback must raise prefer_all_turrets")
    assert(applied53.params["ship"] ~= nil and applied53.params["target"] ~= nil,
        "prefer_all_turrets must carry both the ship and the target")

    -- A target change re-issues the override. Without this the turrets fall
    -- silent the moment auto-next moves on, because the override names one
    -- specific target and dies with it.
    local countBefore53 = #evts53
    local before53b = #pendingCallbacks
    sess53.aimTargetID = 501
    assert(API.applyPreferAllTurrets() == true, "re-issuing the override must succeed")
    for i = before53b + 1, #pendingCallbacks do pcall(pendingCallbacks[i]) end
    local reissued53 = 0
    for i = countBefore53 + 1, #evts53 do
        if evts53[i].control == "prefer_all_turrets" then reissued53 = reissued53 + 1 end
    end
    assert(reissued53 == 1,
        "a target change must re-issue the override exactly once; got " .. tostring(reissued53))

    -- Release hands the ship back, and is a no-op when nothing is held.
    assert(API.clearPreferAllTurrets("test") == true, "release must report success when held")
    assert(sess53.preferAllTurrets == false, "release must clear the session flag")
    local cleared53 = 0
    for _, e in ipairs(evts53) do
        if e.control == "prefer_all_turrets_clear" then cleared53 = cleared53 + 1 end
    end
    assert(cleared53 == 1, "release must raise prefer_all_turrets_clear exactly once")
    assert(API.clearPreferAllTurrets("test again") == false,
        "release must be a no-op when the override is not held")

    -- Leaving the chair must never leave the ship altered. restoreDirect is the
    -- funnel every exit route uses (cease, get up, undock, target-destroyed with
    -- auto-next off), so clearing there covers all of them at once.
    sess53.preferAllTurrets = true
    -- Closing the target browser is the one exit route that reaches
    -- restoreDirect synchronously, which makes it the cheapest way to assert
    -- the funnel itself releases. Every other route (cease, get up, undock)
    -- reaches the same function.
    sess53.phase = "target_select"
    local countBefore53c = #evts53
    gcMenu.onCloseElement("close")
    local clearedOnExit53 = 0
    for i = countBefore53c + 1, #evts53 do
        if evts53[i].control == "prefer_all_turrets_clear" then
            clearedOnExit53 = clearedOnExit53 + 1
        end
    end
    assert(clearedOnExit53 >= 1,
        "leaving the chair while the override is held must release every turret; "
        .. "otherwise the player walks away with a silently altered ship")

    C.SetTurretGroupMode2 = savedSetMode53
    AddUITriggeredEvent = savedAdd53
end

print("runtime smoke tests passed")
