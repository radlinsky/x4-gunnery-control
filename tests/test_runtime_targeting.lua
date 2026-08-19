-- test_runtime_targeting.lua
-- Target candidate selection, direct/auto targeting, cycling, POV buttons,
-- auto-next, group readback, prefer-all-turrets, and frame contracts.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local gcMenu = fix.gcMenu
local API    = fix.API
local C      = fix.C

-- Shared clock for getElapsedTime; tests advance it explicitly.
local clock = 100
getElapsedTime = function() return clock end

-- A reusable group used across many rendering and targeting tests.
local grp27 = {
    key = "grp27", kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 27, displayName = "G27", totalCount = 1, operationalCount = 1,
    mode = "attack", armed = false, members = {
        { componentID = 27, displayName = "T1", operational = true,
          cameraSupported = true, componentKey = "27" }
    }
}

-- Bring the module into a known state.
local ok_init, err_init = pcall(function() gcMenu.onShowMenu() end)
assert(ok_init, "onShowMenu() raised: " .. tostring(err_init))
local sess = API.getSession()
assert(sess ~= nil, "expected a live session after onShowMenu()")

-- ── 10. assertion 5: Esc from target_select always lands on console ──────────
-- Regression: when session.phase=="target_select" and session.directSnapshot is
-- set, the old onCloseElement branch restored phase="direct" and called
-- menu.display(), creating an infinite Esc cycle. The correct behaviour is:
--   direct --Esc--> target_select --Esc--> console
-- Two closes from direct must always terminate at console.

-- NOTE on test setup approach: the harness cannot yet drive the full ingress
-- through startDirect/engageTarget/openTargetBrowser, because those module-local
-- paths require engine state beyond the frame stub. Set up that precise state
-- through TestAPI.getSession(), then exercise the real public close callback or
-- rendered Back-button callback for the behavior under test.

-- ── 10a: target_select + direct controlMode -> onCloseElement("close") ──────
-- This is the exact bug state: player pressed Esc from the target picker while
-- an engagement was in progress (controlMode is "direct").
sess.phase = "target_select"
sess.controlMode = "direct"

gcMenu.onCloseElement("close")
local phaseAfterPickerClose = sess.phase
assert(phaseAfterPickerClose == "console",
    "BUG: closing target_select with controlMode=direct landed on phase='"
    .. tostring(phaseAfterPickerClose)
    .. "' instead of 'console'. The Esc cycle is still present.")
assert(sess.controlMode == nil,
    "closing target_select must clear controlMode (returnToConsole was not called)")

-- ── 10b: visible target-browser Back restores Direct settings ───────────────
-- Unlike onCloseElement above, the visible Back button owns its own callback.
-- A browser reopened from a Direct engagement still holds snapshots while its
-- live turret groups are in autoassist, so that callback must restore before
-- returning to the console. Drive the rendered button rather than a test API.
gcMenu.onShowMenu()
sess = API.getSession()
local browserGroup = {
    key = "browser-back-group", kind = "group", contextID = 10,
    path = "browser-back-path", group = "browser-back", componentID = 1010,
    displayName = "Browser Back Group", totalCount = 1, operationalCount = 1,
    mode = "autoassist", armed = true, members = {},
}
sess.groups = { browserGroup }
sess.phase = "target_select"
sess.controlMode = "direct"
-- committedBaseline holds the "restore on stand-up" state; this is what restoreDirect writes back.
sess.committedBaseline = { {
    shipID = sess.shipID, kind = "group", contextID = browserGroup.contextID,
    path = browserGroup.path, group = browserGroup.group,
    mode = "attack", armed = false,
} }

local modeWrites10b, armedWrites10b = {}, {}
local savedSetMode10b = C.SetTurretGroupMode2
local savedSetArmed10b = C.SetTurretGroupArmed
C.SetTurretGroupMode2 = function(ship, context, path, group, mode)
    modeWrites10b[#modeWrites10b + 1] = {
        ship = ship, context = context, path = path, group = group, mode = mode,
    }
end
C.SetTurretGroupArmed = function(ship, context, path, group, armed)
    armedWrites10b[#armedWrites10b + 1] = {
        ship = ship, context = context, path = path, group = group, armed = armed,
    }
end

gcMenu.display()
local browserBack10b = fix.buttonByText("text:20991:54")
assert(browserBack10b and browserBack10b.handlers.onClick,
    "target browser must render a clickable Back to Gunnery Control button")
browserBack10b.handlers.onClick()

assert(sess.phase == "console",
    "target-browser Back must return to the console")
assert(sess.controlMode == nil,
    "target-browser Back must clear controlMode via returnToConsole")
-- Revert is bound to leaving the chair, so backing out of the target list must
-- not put the turrets back: the player is still seated and a temporary apply
-- lasts until stand-up. This asserted the opposite until the revert rework.
assert(#modeWrites10b == 0,
    "target-browser Back must not write any turret mode; revert happens on stand up")
assert(#armedWrites10b == 0,
    "target-browser Back must not write any armed state; revert happens on stand up")

-- The same visible route is also used by the initial picker, before any Direct
-- engagement exists. It must remain a harmless return with no turret writes.
sess.phase = "target_select"
sess.controlMode = "direct"
sess.committedBaseline = {}
gcMenu.display()
local initialPickerBack10b = fix.buttonByText("text:20991:54")
assert(initialPickerBack10b and initialPickerBack10b.handlers.onClick,
    "initial target picker must render the same Back button")
initialPickerBack10b.handlers.onClick()
assert(sess.phase == "console",
    "initial target-picker Back must still return to the console")
-- Cumulative across both Back presses, and still zero: neither route writes.
assert(#modeWrites10b == 0 and #armedWrites10b == 0,
    "initial target-picker Back must not write turret state either")

C.SetTurretGroupMode2 = savedSetMode10b
C.SetTurretGroupArmed = savedSetArmed10b

-- ── 10c: bounded cycle check ────────────────────────────────────────────────
-- Directly simulate the full Esc sequence: engaged/direct -> target_select -> console.
-- This encodes the actual defect: every step from engaged must terminate at
-- console within a bounded number of close events with no revisit of engaged.
gcMenu.onShowMenu()
sess = API.getSession()
sess.phase = "engaged"
sess.controlMode = "direct"
sess.committedBaseline = { { shipID = sess.shipID, kind = "group",
    componentID = 0, contextID = 0, path = "", group = "", mode = "attack", armed = true } }
-- Simulate the picker opening (openTargetBrowser sets phase but keeps committedBaseline).
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

-- ── 12. Watch and direct frames must provide a visible back button ────────────
-- Proven live on 2026-08-04: Esc (dueToClose == "back") is never delivered to
-- frames with playerControls = true. The watch frame had standardButtons = {},
-- making it completely inescapable. The direct (compact Engage) frame already
-- had standardButtons = { back = true, close = true } and must not regress.
-- A visible back button is the only supported exit for playerControls frames.

-- 12a: engaged/auto frame must have standardButtons.back == true
gcMenu.onShowMenu()
local sess12 = API.getSession()
assert(sess12 ~= nil, "expected a live session for watch frame test")
sess12.phase = "engaged"
sess12.controlMode = "auto"
sess12.committedBaseline = {}
fix.resetLastFrameProps()
local ok12a, err12a = pcall(function() gcMenu.display() end)
assert(ok12a, "menu.display() raised during watch phase: " .. tostring(err12a))
assert(fix.getLastFrameProps() ~= nil,
    "createFrameHandle was not called during watch phase display()")
assert(fix.getLastFrameProps().standardButtons ~= nil
    and fix.getLastFrameProps().standardButtons.back == true,
    "BUG: engaged/auto frame standardButtons.back is not true — "
    .. "Esc is never delivered to playerControls frames, so without a visible "
    .. "back button the auto-engage phase is completely inescapable. "
    .. "Got standardButtons=" .. tostring(fix.getLastFrameProps().standardButtons))

-- 12a2: the engaged/auto frame must NOT opt into the mini widget system. Helper
-- documents enableDefaultInteractions as "default input handling (f.e.
-- ESC/DEL)", and that handling lives in the normal widget system. Setting
-- useMiniWidgetSystem = true is what silently dropped Esc in the camera
-- phases while ordinary frames kept it.
assert(not fix.getLastFrameProps().useMiniWidgetSystem,
    "BUG: engaged/auto frame sets useMiniWidgetSystem, which drops default ESC/DEL "
    .. "handling and makes Esc unusable in the auto-engage phase")

-- 12a4: engaged/auto must own a table. Helper only wires frame interaction when the
-- frame has one, and the watch frame was the sole table-less frame and the sole frame
-- where Esc leaked to X4 instead of closing the view.
assert(fix.getAddTableCalls() > 0,
    "BUG: engaged/auto frame created no table, so Helper never wires interaction and "
    .. "Esc leaks to X4 and opens the main menu instead of leaving the auto-engage view")

-- 12a3: engaged/auto playerControls must be true (same as old watch frame).
assert(fix.getLastFrameProps().playerControls == true,
    "BUG: engaged/auto frame playerControls is not true")

-- 12b: engaged/direct (compact Engage) frame must still have standardButtons.back == true
sess12.phase = "engaged"
sess12.controlMode = "direct"
-- Provide a minimal committedBaseline so the active= check does not crash.
sess12.committedBaseline = { { kind = "group", contextID = 0, path = "", group = "",
    shipID = sess12.shipID, mode = "attack", armed = true } }
sess12.selectedGroupKey = nil
fix.resetLastFrameProps()
local ok12b, err12b = pcall(function() gcMenu.display() end)
assert(ok12b, "menu.display() raised during direct phase: " .. tostring(err12b))
assert(fix.getLastFrameProps() ~= nil,
    "createFrameHandle was not called during direct phase display()")
assert(fix.getLastFrameProps().standardButtons ~= nil
    and fix.getLastFrameProps().standardButtons.back == true,
    "REGRESSION: engaged/direct frame standardButtons.back is not true — "
    .. "the compact Engage panel has lost its only escape route for "
    .. "playerControls frames (Esc is never delivered). "
    .. "Got standardButtons=" .. tostring(fix.getLastFrameProps().standardButtons))

-- 12b2: same mini-widget-system guard for the compact Engage frame.
assert(not fix.getLastFrameProps().useMiniWidgetSystem,
    "BUG: engaged/direct frame sets useMiniWidgetSystem, which drops default ESC/DEL "
    .. "handling and makes Esc unusable in the compact Engage panel")

-- 12b3: engaged/direct playerControls must be true.
assert(fix.getLastFrameProps().playerControls == true,
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
        sess14.committedBaseline = sess14.committedBaseline or {}
        -- re-render the engaged/direct panel; the POV label must reflect the flag
        povMenu.display()
    end)
    assert(okPov, "direct panel render raised while POV=target")
end

-- ── 15. cutscene aim buttons emit the right AddUITriggeredEvent calls ───────
-- Transport contract (live-tested 2026-08-04, three rounds): the engine
-- PREPENDS $ to every Lua string key during Lua→MD conversion, so Lua "anchor"
-- arrives in MD as the variable key $anchor (read via event.param3.$anchor).
-- Never pre-prefix $ in Lua — "["$anchor"]" becomes the invalid name $$anchor,
-- stuck as an unreadable string key. Ids must be converted via
-- ConvertStringToLuaID(tostring(id)) (vanilla pattern,
-- menu_ship_configuration.lua:1399) to arrive as real MD component objects.

local capturedEvents15 = {}
AddUITriggeredEvent = function(screen, control, params)
    capturedEvents15[#capturedEvents15 + 1] = { screen = screen, control = control, params = params }
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
sess15.committedBaseline = { { kind = "group", contextID = 0, path = "fake", group = "grp",
    shipID = sess15.shipID, mode = "attack", armed = true, componentID = 55 } }
sess15.selectedGroupKey = fakeGroup15.key
sess15.selectedMemberID = 55
sess15.cameraMemberID = 55   -- beginEngaged sets this; set it explicitly for the test

-- 15a: sendCutsceneAimStart("turret") — anchor=turret componentID (55),
-- target=softtarget (77), both as ConvertStringToLuaID-converted values under
-- PLAIN keys (the engine adds the $ prefix on the MD side).
capturedEvents15 = {}
X4GunneryControlAPI.sendCutsceneAimStart("turret")
local evStart = nil
for _, e in ipairs(capturedEvents15) do
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
capturedEvents15 = {}
X4GunneryControlAPI.sendCutsceneAimStart("target")
local evStart2 = nil
for _, e in ipairs(capturedEvents15) do
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
capturedEvents15 = {}
X4GunneryControlAPI.sendCutsceneAimStop()
local evStop = nil
for _, e in ipairs(capturedEvents15) do
    if e.screen == "X4GunneryControl" and e.control == "cutscene_aim_stop" then evStop = e; break end
end
assert(evStop ~= nil,
    "sendCutsceneAimStop() must emit AddUITriggeredEvent('X4GunneryControl','cutscene_aim_stop',...)")

-- 15d: discardSession emits cutscene_aim_stop (via the session teardown hook).
-- Use the console-close path (same as test 13a) so discardSession fires
-- synchronously rather than via a deferred callback.
sess15.phase = "console"
capturedEvents15 = {}
gcMenu.onCloseElement("close")  -- leaveChair -> endSession -> discardSession
local evStopOnDiscard = nil
for _, e in ipairs(capturedEvents15) do
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
sess16.committedBaseline = {}
fix.resetLastFrameProps()
local ok16a, err16a = pcall(function() gcMenu.display() end)
assert(ok16a, "display() raised in engaged/auto: " .. tostring(err16a))
assert(fix.getLastFrameProps() ~= nil, "createFrameHandle not called in engaged/auto")
assert(fix.getLastFrameProps().playerControls == true,
    "engaged/auto: playerControls must be true")

-- 16b: engaged/direct
sess16.phase = "engaged"
sess16.controlMode = "direct"
sess16.committedBaseline = { { kind = "group", contextID = 0, path = "", group = "",
    shipID = sess16.shipID, mode = "attack", armed = true } }
fix.resetLastFrameProps()
local ok16b, err16b = pcall(function() gcMenu.display() end)
assert(ok16b, "display() raised in engaged/direct: " .. tostring(err16b))
assert(fix.getLastFrameProps() ~= nil, "createFrameHandle not called in engaged/direct")
assert(fix.getLastFrameProps().playerControls == true,
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
sess17.committedBaseline = {}
-- Matches softtargetKey() with softtargetID=0, connection="" -> "0\031"
sess17.viewSofttargetKey = "0\031"
local mark17 = fix.callbackCheckpoint()
gcMenu.onCloseElement("back")
-- Drain the deferred callback that was just registered.
local ok17, err17 = pcall(fix.drainCallbacksSince, mark17)
assert(ok17, "deferred callback raised: " .. tostring(err17))
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
local restoreCalls19 = {}
local origSetTurretGroupMode19 = C.SetTurretGroupMode2
local origSetTurretGroupArmed19 = C.SetTurretGroupArmed
-- Intercept the C calls to count how many groups were restored.
C.SetTurretGroupMode2 = function(ship, ctx, path, group, mode)
    restoreCalls19[#restoreCalls19 + 1] = { path = tostring(path), group = tostring(group), mode = mode }
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
sess19.committedBaseline = {
    { shipID = sess19.shipID, kind = "group", contextID = 1, path = "p", group = "A",
      mode = "attack", armed = false },
    { shipID = sess19.shipID, kind = "group", contextID = 1, path = "p", group = "B",
      mode = "defend", armed = false },
}

-- Drive restoreDirect via onCloseElement console path (leaveChair -> discardSession).
sess19.phase = "console"
gcMenu.onCloseElement("close")

-- Both groups must have been restored (SetTurretGroupMode2 called twice).
assert(#restoreCalls19 == 2,
    "restoreDirect with 2-entry list must restore both groups; got "
    .. tostring(#restoreCalls19) .. " restore calls. "
    .. "A single-entry loop would strand the second group on autoassist.")
-- After restore, committedBaseline must be empty.
-- Session is nil after endSession; check via a fresh onShowMenu.
gcMenu.onShowMenu()
local sess19post = API.getSession()
assert(sess19post ~= nil, "expected session after restore test")
assert(#(sess19post.committedBaseline or {}) == 0,
    "committedBaseline must be empty after session end and restore")

-- Restore stubs.
C.SetTurretGroupMode2 = origSetTurretGroupMode19
C.SetTurretGroupArmed = origSetTurretGroupArmed19

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
sess21.committedBaseline = {}
sess21.cameraMemberID = 9
sess21.povAnchor = "turret"
sess21.povMode = "manual"
sess21.aimTargetID = nil
local ok21a, err21a = pcall(function() gcMenu.display() end)
assert(ok21a, "engaged/auto display raised: " .. tostring(err21a))
assert(fix.getLastFrameProps() ~= nil, "createFrameHandle not called in engaged/auto (step 21)")
assert(fix.getLastFrameProps().playerControls == true, "engaged/auto: playerControls must be true (step 21)")

-- 21b: direct
sess21.phase = "engaged"
sess21.controlMode = "direct"
sess21.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "front",
    shipID = sess21.shipID, mode = "attack", armed = false } }
fix.resetLastFrameProps()
local ok21b, err21b = pcall(function() gcMenu.display() end)
assert(ok21b, "engaged/direct display raised: " .. tostring(err21b))
assert(fix.getLastFrameProps() ~= nil, "createFrameHandle not called in engaged/direct (step 21)")
assert(fix.getLastFrameProps().playerControls == true, "engaged/direct: playerControls must be true (step 21)")

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
sess23.committedBaseline = {}
sess23.cameraMemberID = 20
sess23.aimTargetID = nil
sess23.povMode = "cinematic"
sess23.povAnchor = "turret"

-- Fake a target candidate: IsComponentOperational returns true by default.
C.IsComponentOperational = function(id) return id == 99 end

-- Replace GetComponentData to return a fake enemy target.
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
        elseif k == "isplayerowned" then vals[#vals + 1] = false  -- hostile, not player-owned
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
        elseif k == "isplayerowned" then vals[#vals + 1] = false  -- enemies, not player-owned
        else vals[#vals + 1] = nil
        end
    end
    return unpack(vals)
end
C.GetDistanceBetween = function(_, b) return (tostring(b) == "98") and 100 or 5000 end

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
fix.resetLastFrameProps()
clock = clock + 60
X4GunneryControlAPI.updateAimTarget()
assert(sess23.aimTargetID ~= nil, "precondition: updateAimTarget must pick a target")
assert(fix.getLastFrameProps() ~= nil,
    "acquiring an aim target in manual mode must rebuild the panel frame")

-- ── 27. engaged/direct with targetObjectID creates TWO frames ────────────────
-- The left element panel is only shown when controlMode=="direct" AND
-- session.targetObjectID is set.
gcMenu.onShowMenu()
local sess27 = API.getSession()
assert(sess27 ~= nil, "expected session for two-frame test")
sess27.groups = { grp27 }
sess27.checkedGroupKeys = { ["grp27"] = true }
sess27.phase = "engaged"
sess27.controlMode = "direct"
sess27.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess27.shipID, mode = "attack", armed = false } }
sess27.cameraMemberID = 27
sess27.targetObjectID = 500
sess27.aimTargetID = 500
local ok27, err27 = pcall(function() gcMenu.display() end)
assert(ok27, "display() raised in engaged/direct+targetObjectID: " .. tostring(err27))
assert(fix.getFrameCount() == 2,
    "engaged/direct with targetObjectID must create TWO frames; got " .. tostring(fix.getFrameCount()))
-- frame:display() registers a view keyed by layer (helper.lua onFrameHandleView
-- Created / View.registerMenu("Helper" .. layer)). Two frames sharing the
-- default layer 4 means the second silently replaces the first on screen.
local fp = fix.getFrameProps()
assert(fp[1].layer ~= fp[2].layer,
    "the two engaged/direct frames must sit on different layers; both had "
    .. tostring(fp[1].layer))

-- ── 28. engaged/auto creates ONE frame ───────────────────────────────────────
gcMenu.onShowMenu()
local sess28 = API.getSession()
assert(sess28 ~= nil, "expected session for one-frame test")
sess28.groups = { grp27 }
sess28.checkedGroupKeys = { ["grp27"] = true }
sess28.phase = "engaged"
sess28.controlMode = "auto"
sess28.committedBaseline = {}
sess28.cameraMemberID = 27
sess28.aimTargetID = nil
local ok28, err28 = pcall(function() gcMenu.display() end)
assert(ok28, "display() raised in engaged/auto: " .. tostring(err28))
assert(fix.getFrameCount() == 1,
    "engaged/auto must create ONE frame; got " .. tostring(fix.getFrameCount()))

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
        elseif k == "isplayerowned" then vals[#vals + 1] = false  -- enemy ships, not player-owned
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
sess29.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess29.shipID, mode = "attack", armed = false } }
sess29.cameraMemberID = 27
-- Candidate 98 is nearer (100m) so it will be first sorted; start at 98.
sess29.targetObjectID = 98
sess29.aimTargetID = 98
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
local function povButton(id) return fix.buttonByText("text:20991:" .. id) end
gcMenu.onShowMenu()
local sess30 = API.getSession()
sess30.groups = { grp27 }
sess30.checkedGroupKeys = { ["grp27"] = true }
sess30.phase = "engaged"
sess30.cameraMemberID = 27
sess30.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "g",
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

-- ── 31. the element panel pins whichever element is being attacked ───────────
sess30.controlMode = "direct"
sess30.povAnchor, sess30.povMode = "turret", "manual"
sess30.targetObjectID = 500
sess30.aimTargetID = 500          -- hull is the engaged element
gcMenu.display()
local function hasPinnedRow()
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if entry.row == "surface_pinned" then return true end
    end
    return false
end
assert(hasPinnedRow(), "engaged hull must render in the fixed pinned section")
sess30.aimTargetID = 501          -- a surface element, not the hull
sess30.surfaceBrowser.pendingReason = "open"
gcMenu.display()
assert(hasPinnedRow(), "engaged surface must render in the fixed pinned section")

-- ── 32. Next/Previous Target grey out with nothing to cycle to ───────────────
-- Cycling is pointless with a single candidate, and there is no candidate list
-- at all outside direct mode. The stubs from test 29 still supply 98 and 99.
-- Advance the clock so the hasMultipleTargets() 1 s TTL memo expires between
-- this display() and the one above.
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
fix.resetClearedFrames()
gcMenu.display()
assert(#fix.getClearedFrames() == 0, "nothing to clear while the element panel is shown")
sess30.phase = "target_select"
gcMenu.display()
assert(fix.getClearedFrames()[1] == 3,
    "leaving the element panel must clearFrame its layer; cleared "
    .. tostring(fix.getClearedFrames()[1]))

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
sess39.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "g",
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
        elseif k == "isplayerowned" then vals[#vals + 1] = false  -- enemy ship, not player-owned
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

-- ── 40. engaged/direct session toggles have independent defaults ────────────
gcMenu.display()
assert(#fix.getCreatedCheckBoxes() == 2,
    "the engaged/direct panel must offer Auto-next and surface auto-refresh; got "
    .. tostring(#fix.getCreatedCheckBoxes()))
assert(fix.getCreatedCheckBoxes()[1].checked == true,
    "the Auto-next Target checkbox must be checked while session.autoNextTarget is on")
assert(fix.getCreatedCheckBoxes()[2].checked == false,
    "surface auto-refresh must default unchecked")

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

-- ── 42. Direct target loss: asynchronous same-root fallback (Issue #45 Task 5) ─
-- The production path is updateAimTarget() on the 0.25 s tick. A dead surface
-- element with Auto-next on must NOT be answered with an immediate choice:
-- onDirectTargetLost() refreshes the root's surface snapshot, records the
-- ranked unfiltered same-root surfaces in session.targetFallback (page 1),
-- and issues the page-1 ENGAGEABLE query immediately. Each later tick consumes
-- the pending/accepted readings through one State.planEngageFallback decision:
-- ranked same-root surfaces in pages, then the target's hull, then ranked
-- other objects. The assertions below fail on a synchronous pick at the loss
-- tick, a deferred page-1 query, a browser fallback before the planner has
-- exhausted every stage, re-implemented enumeration/ordering logic, or a
-- request that bypasses the checked operational turret membership.
-- Distinct stub IDs keep every assertion discriminating: 600 root, 701+
-- surfaces, 98/99 hostile objects, 500 ordinary object.
do
    -- Save the stubs this block replaces; nil restores the fixture's C
    -- metatable fallbacks.
    local savedClass42 = C.IsComponentClass
    local savedNumSlots42 = C.GetNumUpgradeSlots
    local savedSlotComp42 = C.GetUpgradeSlotCurrentComponent
    local savedSlotMacro42 = C.GetUpgradeSlotCurrentMacro
    local savedSetName42 = C.GetComponentName
    local savedDist42 = C.GetDistanceBetween
    local savedCtxClass42 = C.GetContextByClass
    local savedOperational42 = C.IsComponentOperational
    local savedSoft42 = C.SetSofttarget
    local savedMacroData42 = GetMacroData
    local savedCompData42 = GetComponentData
    local savedShips42 = GetContainedShips
    local savedStations42 = GetContainedStations
    local savedSector42 = GetPlayerContextByClass
    local savedAdd42 = AddUITriggeredEvent
    -- Earlier blocks left their own AddUITriggeredEvent stubs installed; this
    -- block captures into the fixture list so the batch helpers can read it.
    AddUITriggeredEvent = function(screen, control, params)
        fix.uiTriggeredEvents[#fix.uiTriggeredEvents + 1] = {
            screen = screen, control = control, params = params,
        }
    end

    C.IsComponentClass = function(component, class)
        if class == "ship" then return true end
        return false
    end
    -- Surfaces 70x resolve to their root 600; every other component (the
    -- ship, hostile objects 98/99, ordinary object 500) resolves to itself.
    C.GetContextByClass = function(component)
        local n = tonumber(tostring(component))
        if n and n >= 700 and n <= 799 then return 600 end
        return component
    end
    C.GetDistanceBetween = function() return 1000 end
    C.GetComponentName = function(component) return "Target " .. tostring(component) end
    C.GetUpgradeSlotCurrentMacro = function() return "" end
    GetMacroData = function() return "" end
    GetPlayerContextByClass = function() return 1 end
    -- Root 600 is a plain (non-station) object carrying turret slots 701..N.
    local slotCount42 = 0
    -- Only surface scans of root 600 count: readGroups() also queries
    -- GetNumUpgradeSlots for the ship's own turret groups, which is not a
    -- surface enumeration.
    local surfaceScanCalls42 = 0
    C.GetNumUpgradeSlots = function(destructible, _, upgrade)
        if tonumber(tostring(destructible)) ~= 600 then return 0 end
        if upgrade ~= "turret" then return 0 end
        surfaceScanCalls42 = surfaceScanCalls42 + 1
        return slotCount42
    end
    C.GetUpgradeSlotCurrentComponent = function(destructible, _, slot)
        return tonumber(tostring(destructible)) == 600 and (700 + slot) or 0
    end
    local operational42 = {}
    C.IsComponentOperational = function(cid)
        return operational42[tostring(cid)] == true
    end
    -- The sector sweep that chooseAimTarget()/readTargetCandidates() run:
    -- counting these proves (or disproves) that the object sweep was
    -- consulted, and when.
    local objectSweepCalls42 = 0
    local sectorShips42 = {}
    GetContainedShips = function()
        objectSweepCalls42 = objectSweepCalls42 + 1
        return sectorShips42
    end
    GetContainedStations = function()
        objectSweepCalls42 = objectSweepCalls42 + 1
        return {}
    end
    local softtargetCalls42 = {}
    C.SetSofttarget = function(target, conn)
        softtargetCalls42[#softtargetCalls42 + 1] = target
        return true
    end
    GetComponentData = function(component, ...)
        local keys, vals = {...}, {}
        for _, k in ipairs(keys) do
            if k == "isenemy" then vals[#vals + 1] = true
            elseif k == "isknown" then vals[#vals + 1] = true
            elseif k == "isradarvisible" then vals[#vals + 1] = true
            elseif k == "maxradarrange" then vals[#vals + 1] = 40000
            elseif k == "isplayerowned" then vals[#vals + 1] = false
            else vals[#vals + 1] = false
            end
        end
        return unpack(vals)
    end

    -- ── shared helpers ────────────────────────────────────────────────────
    local function group42(key, memberID, operational)
        return { key = key, kind = "group", contextID = 5, path = "p", group = "g",
            componentID = memberID, displayName = "G" .. key, totalCount = 1,
            operationalCount = operational and 1 or 0, mode = "attack", armed = false,
            members = { { componentID = memberID, displayName = "T",
                           operational = operational, cameraSupported = true,
                           componentKey = tostring(memberID) } } }
    end
    local grp42 = group42("grp42", 27, true)

    -- A fresh engaged/direct session; the given groups are the checked ones.
    local function freshDirectSession42(groups)
        gcMenu.onShowMenu()
        local sess = API.getSession()
        assert(sess ~= nil, "expected a fresh session")
        local keys = {}
        for _, g in ipairs(groups) do keys[g.key] = true end
        sess.groups, sess.checkedGroupKeys = groups, keys
        sess.phase, sess.controlMode = "engaged", "direct"
        sess.committedBaseline = { { kind = "group", contextID = 5, path = "p",
            group = "g", shipID = sess.shipID, mode = "attack", armed = false } }
        sess.cameraMemberID = 27
        sess.povAnchor, sess.povMode = "turret", "manual"
        return sess
    end

    -- ENGAGEABLE batches emitted after uiTriggeredEvents index `mark`.
    local function batchesSince42(mark)
        local batches, current = {}, nil
        for i = mark + 1, #fix.uiTriggeredEvents do
            local e = fix.uiTriggeredEvents[i]
            if e.control == "engageability_begin" then
                current = { nonce = e.params.nonce, members = e.params.members,
                             memberIDs = {}, targets = {} }
                batches[#batches + 1] = current
            elseif current ~= nil and e.params and e.params.nonce == current.nonce then
                if e.control == "engageability_member" then
                    current.memberIDs[#current.memberIDs + 1] = e.params.weapon
                elseif e.control == "engageability_target" then
                    current.targets[#current.targets + 1] = X4GunneryState.normID(e.params.target)
                elseif e.control == "engageability_commit" then
                    current = nil
                end
            end
        end
        return batches
    end

    -- Deliver MD's reply for one batch: an EngageabilityResult per target it
    -- has a reading for ("engageable:known:total"), then the batch complete.
    local function deliver42(batch, resultsByKey)
        for _, key in ipairs(batch.targets) do
            local counts = resultsByKey[key]
            if counts then
                fix.fireEvent("X4GunneryControl.EngageabilityResult",
                    "x4gce3:" .. batch.nonce .. ":" .. key .. ":" .. counts)
            end
        end
        fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete",
            "x4gce2c:" .. batch.nonce .. ":" .. tostring(#batch.targets) .. ":"
                .. tostring(#batch.targets))
    end

    local function resetCounts42()
        slotCount42 = 0
        sectorShips42 = {}
        operational42 = {}
        surfaceScanCalls42 = 0
        objectSweepCalls42 = 0
        softtargetCalls42 = {}
    end

    local function tick42()
        clock = clock + 0.25
        API.updateAimTarget()
    end

    -- Count only engageability transport events since `mark`: an engage also
    -- emits its direct_fallback cue, which is expected, not a violation.
    local function engageabilityEventsSince42(mark)
        local n = 0
        for i = mark + 1, #fix.uiTriggeredEvents do
            if tostring(fix.uiTriggeredEvents[i].control):match("^engageability_") then
                n = n + 1
            end
        end
        return n
    end

    -- A. Task 5A: the loss tick supersedes a REAL pre-existing surface
    -- snapshot of the same root (one generation later), ranks the unfiltered
    -- alternatives of its refreshed allSurfaces, and immediately issues
    -- exactly one page-1 ENGAGEABLE batch for the checked operational
    -- turrets. It still makes no choice and runs no object sweep; the next
    -- tick consumes the pending readings without re-requesting.
    do
        resetCounts42()
        slotCount42 = 3                       -- 701/702/703 all alive at first
        operational42 = { ["600"] = true, ["701"] = true, ["702"] = true,
            ["703"] = true, ["98"] = true }
        sectorShips42 = { 98 }
        local sess = freshDirectSession42({ grp42 })
        sess.targetObjectID, sess.aimTargetID = 600, 701
        sess.surfaceTypeFilter = "engine"     -- browser filter: must not narrow the fallback
        clock = 500
        -- 1. Establish a REAL pre-existing snapshot: render the element panel
        -- the way an engaged direct-control player sees it, aiming at the
        -- live surface 701. The loss tick below must then supersede this
        -- live browser snapshot rather than create one from scratch.
        local okA, errA = pcall(function() gcMenu.display() end)
        assert(okA, "setup display raised: " .. tostring(errA))
        assert(sess.surfaceBrowser ~= nil
            and X4GunneryState.normID(sess.surfaceBrowser.rootID) == "600"
            and (sess.surfaceBrowser.generation or 0) >= 1,
            "setup: the element panel render must create a real snapshot for "
            .. "root 600; generation="
            .. tostring(sess.surfaceBrowser and sess.surfaceBrowser.generation))
        local genBefore = sess.surfaceBrowser.generation
        local oldAllSurfaces = {}
        for _, surface in ipairs(sess.surfaceBrowser.allSurfaces or {}) do
            oldAllSurfaces[#oldAllSurfaces + 1] = X4GunneryState.normID(surface.componentID)
        end
        assert(table.concat(oldAllSurfaces, ",") == "701,702,703",
            "setup: the pre-existing snapshot must hold all three operational "
            .. "surfaces; got " .. table.concat(oldAllSurfaces, ","))
        -- The user's engine filter narrows the browser's FILTERED list to
        -- nothing (all three surfaces are turrets) while its unfiltered
        -- allSurfaces keeps the turret surfaces: the fallback below must rank
        -- the allSurfaces that the filter hides from the browser.
        assert(#sess.surfaceBrowser.orderedIDs == 0,
            "setup: under the engine filter the browser's filtered orderedIDs "
            .. "must be empty while allSurfaces holds the turret surfaces; got "
            .. tostring(#sess.surfaceBrowser.orderedIDs))
        -- ENGAGEABLE traffic from that setup render (the pinned row's batch)
        -- must not satisfy the loss-tick assertions: mark only now.
        local mark = #fix.uiTriggeredEvents
        local sweepsAtMark = objectSweepCalls42
        softtargetCalls42 = {}
        -- The browser object the loss tick must refresh in place.
        local browserBefore = sess.surfaceBrowser
        -- 2. 701 dies while the browser still lists it: the pre-existing
        -- snapshot is now stale.
        operational42["701"] = false
        local lossLogStart = #fix.getCapturedLog()
        API.updateAimTarget()
        assert(sess.targetFallback ~= nil,
            "surface loss with auto-next on must start a session-scoped resolution")
        assert(tostring(sess.aimTargetID) == "701",
            "no immediate choice: the aim must stay on the lost surface; aim is "
            .. tostring(sess.aimTargetID))
        assert(tostring(sess.targetObjectID) == "600" and sess.phase == "engaged",
            "the resolution must preserve the root and stay engaged; root="
            .. tostring(sess.targetObjectID) .. " phase=" .. tostring(sess.phase))
        assert(#softtargetCalls42 == 0,
            "no re-engage may happen on the loss tick itself")
        assert(objectSweepCalls42 == sweepsAtMark,
            "the object sweep belongs to the planner's objects stage, not the loss tick; "
            .. (objectSweepCalls42 - sweepsAtMark) .. " extra call(s)")
        -- The surface snapshot for the root is the SAME browser object,
        -- advanced by exactly one generation on the loss tick...
        assert(sess.surfaceBrowser == browserBefore,
            "the loss tick must refresh the pre-existing browser object "
            .. "itself, not replace it")
        assert(sess.surfaceBrowser.generation == genBefore + 1,
            "the loss tick must advance the pre-existing snapshot by exactly "
            .. "one generation; before=" .. tostring(genBefore)
            .. " after=" .. tostring(sess.surfaceBrowser.generation))
        local sawSnapshotLog, sawFallbackStartLog = false, false
        for i = lossLogStart + 1, #fix.getCapturedLog() do
            local line = fix.getCapturedLog()[i]
            if string.find(line,
                "event=surface_snapshot action=create reason=auto_next", 1, true) then
                sawSnapshotLog = true
            end
            if string.find(line,
                "event=auto_next_fallback action=start", 1, true) then
                sawFallbackStartLog = true
            end
        end
        assert(sawSnapshotLog,
            "the loss-tick snapshot refresh must be logged with the auto_next reason")
        -- ...and its allSurfaces now reflect the changed population instead
        -- of the stale setup snapshot.
        local newAllSurfaces = {}
        for _, surface in ipairs(sess.surfaceBrowser.allSurfaces or {}) do
            newAllSurfaces[#newAllSurfaces + 1] = X4GunneryState.normID(surface.componentID)
        end
        assert(table.concat(newAllSurfaces, ",") == "702,703",
            "the refreshed snapshot must hold the unfiltered operational surfaces "
            .. "after 701 died; got " .. table.concat(newAllSurfaces, ","))
        assert(table.concat(newAllSurfaces, ",") ~= table.concat(oldAllSurfaces, ","),
            "the refreshed allSurfaces must differ from the stale setup snapshot; old="
            .. table.concat(oldAllSurfaces, ",")
            .. " new=" .. table.concat(newAllSurfaces, ","))
        -- and the fallback ranks the unfiltered same-root alternatives of
        -- exactly that snapshot (the user's engine filter would leave the
        -- browser none of them).
        local expected = X4GunneryState.surfaceAlternatives(
            sess.surfaceBrowser.allSurfaces, sess.aimTargetID, "any", "any")
        table.sort(expected, function(a, b)
            return X4GunneryState.surfaceMetadataLess(a, b, "size_first")
        end)
        local expectedIDs = {}
        for _, surface in ipairs(expected) do
            expectedIDs[#expectedIDs + 1] = X4GunneryState.normID(surface.componentID)
        end
        assert(sess.targetFallback.stage == "surfaces" and sess.targetFallback.page == 1
            and #sess.targetFallback.orderedIDs == #expectedIDs
            and table.concat(sess.targetFallback.orderedIDs, ",")
                == table.concat(expectedIDs, ","),
            "the fallback must start at surfaces page 1 ranked from the refreshed "
            .. "unfiltered allSurfaces; stage="
            .. tostring(sess.targetFallback.stage)
            .. " page=" .. tostring(sess.targetFallback.page)
            .. " ids=" .. table.concat(sess.targetFallback.orderedIDs, ",")
            .. " expected=" .. table.concat(expectedIDs, ","))
        assert(surfaceScanCalls42 >= 1,
            "the resolution must rank root 600 through the surface reader")
        assert(sawFallbackStartLog,
            "the fallback start must be logged on this loss tick")
        -- ...and page 1 is queried immediately through the checked turrets.
        local batches = batchesSince42(mark)
        assert(#batches == 1,
            "the loss tick must issue exactly one page-1 ENGAGEABLE batch; got "
            .. tostring(#batches))
        assert(#batches[1].targets <= 20,
            "a page-1 batch must hold at most 20 ranked targets; got "
            .. tostring(#batches[1].targets))
        assert(batches[1].members == 1 and #batches[1].memberIDs == 1
            and batches[1].memberIDs[1] == 27,
            "the batch must carry exactly the checked operational turret; members="
            .. tostring(batches[1].members)
            .. " members_list=" .. table.concat(batches[1].memberIDs, ","))
        assert(#batches[1].targets == 2 and batches[1].targets[1] == "702"
            and batches[1].targets[2] == "703",
            "page 1 must query the ranked same-root surfaces; targets="
            .. table.concat(batches[1].targets, ","))
        assert(#softtargetCalls42 == 0,
            "no choice may be made before a result is accepted")

        -- Next tick: the batch is still pending inside the cache window, so
        -- the planner waits without re-requesting, and still makes no choice.
        mark = #fix.uiTriggeredEvents
        tick42()
        assert(#batchesSince42(mark) == 0,
            "a still-pending page-1 batch must not be re-requested on the next tick")
        assert(#softtargetCalls42 == 0,
            "no choice may be made before a result is accepted")
    end

    -- B. An accepted positive result engages the surviving surface and ends
    -- the resolution; the root is preserved.
    do
        resetCounts42()
        slotCount42 = 2
        operational42 = { ["600"] = true, ["702"] = true, ["98"] = true }
        sectorShips42 = { 98 }
        local sess = freshDirectSession42({ grp42 })
        sess.targetObjectID, sess.aimTargetID = 600, 701
        sess.povAnchor, sess.povMode = "turret", "cinematic"
        clock = 500
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        local batches = batchesSince42(mark)
        assert(#batches == 1, "the loss tick must issue the page-1 batch")
        deliver42(batches[1], { ["702"] = "1:1:1" })
        softtargetCalls42 = {}
        tick42()
        assert(tostring(sess.aimTargetID) == "702",
            "the accepted positive surface must be engaged; aim is "
            .. tostring(sess.aimTargetID))
        assert(tostring(sess.targetObjectID) == "600",
            "same-root fallback must preserve the root object; targetObjectID is "
            .. tostring(sess.targetObjectID))
        assert(sess.phase == "engaged",
            "the resolution must stay engaged; phase is " .. tostring(sess.phase))
        assert(sess.targetFallback == nil,
            "an engaged resolution must clear the fallback state")
        assert(#softtargetCalls42 >= 1 and softtargetCalls42[#softtargetCalls42] == 702,
            "the engaged surface must become the soft target; got "
            .. tostring(softtargetCalls42[#softtargetCalls42]))
        local stops, starts = 0, 0
        for i = mark + 1, #fix.uiTriggeredEvents do
            local e = fix.uiTriggeredEvents[i]
            if e.control == "cutscene_aim_stop" then stops = stops + 1 end
            if e.control == "cutscene_aim_start" then starts = starts + 1 end
        end
        assert(stops == 1 and starts == 1,
            "a cinematic POV must be stopped and restarted around the engage; "
            .. "stops=" .. stops .. " starts=" .. starts)
        assert(fix.logContains("auto-next engaged"),
            "the auto-next engage must keep its session log line")
    end

    -- C. Pages advance only when every reading on the page is a proven zero;
    -- the next page is queried as a fresh batch and the first ranked positive
    -- on it wins. Cached page-1 readings must not be re-requested within the
    -- cache window.
    do
        resetCounts42()
        slotCount42 = 24                      -- 701 dead, 702..724 alive
        for n = 702, 724 do operational42[tostring(n)] = true end
        operational42["600"] = true
        operational42["98"] = true
        sectorShips42 = { 98 }
        local sess = freshDirectSession42({ grp42 })
        sess.targetObjectID, sess.aimTargetID = 600, 701
        clock = 500
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 20
            and batches[1].targets[1] == "702" and batches[1].targets[20] == "721",
            "page 1 must be the first 20 ranked surfaces; got "
            .. tostring(#batches) .. " batch(es), "
            .. tostring(#(batches[1] and batches[1].targets or {})) .. " target(s)")
        local zeros = {}
        for _, key in ipairs(batches[1].targets) do zeros[key] = "0:1:1" end
        deliver42(batches[1], zeros)
        mark = #fix.uiTriggeredEvents
        tick42()
        assert(sess.targetFallback ~= nil and sess.targetFallback.page == 2,
            "an all-zero page must advance to page 2; page is "
            .. tostring(sess.targetFallback and sess.targetFallback.page))
        assert(#batchesSince42(mark) == 0,
            "page 2 must not be requested on the same tick as the page advance")
        tick42()
        batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 3
            and batches[1].targets[1] == "722" and batches[1].targets[3] == "724",
            "page 2 must be a fresh batch for the remaining ranked surfaces; got "
            .. tostring(#batches) .. " batch(es), targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        local seen702 = 0
        for i = mark, #fix.uiTriggeredEvents do
            local e = fix.uiTriggeredEvents[i]
            if e.control == "engageability_target"
                and X4GunneryState.normID(e.params.target) == "702" then
                seen702 = seen702 + 1
            end
        end
        assert(seen702 == 0,
            "page-1 targets must be served from the cache, not re-requested")
        deliver42(batches[1], { ["722"] = "0:1:1", ["723"] = "0:1:1", ["724"] = "1:1:1" })
        softtargetCalls42 = {}
        tick42()
        assert(tostring(sess.aimTargetID) == "724" and tostring(sess.targetObjectID) == "600",
            "the first ranked positive on page 2 must be engaged; aim="
            .. tostring(sess.aimTargetID) .. " root=" .. tostring(sess.targetObjectID))
        assert(sess.phase == "engaged" and sess.targetFallback == nil,
            "page-2 engage must stay engaged and clear the fallback")
        assert(softtargetCalls42[#softtargetCalls42] == 724,
            "the engaged page-2 surface must become the soft target")
    end

    -- D. With no surviving same-root surface, the planner escalates to the
    -- target's hull, and a positive hull reading engages the hull itself.
    do
        resetCounts42()
        slotCount42 = 1                       -- only the dead 701 remains
        operational42 = { ["600"] = true, ["98"] = true }
        sectorShips42 = { 98 }
        local sess = freshDirectSession42({ grp42 })
        sess.targetObjectID, sess.aimTargetID = 600, 701
        clock = 500
        API.updateAimTarget()
        tick42()
        assert(sess.targetFallback.stage == "hull",
            "an empty surface stage must escalate to the hull stage; stage is "
            .. tostring(sess.targetFallback.stage))
        assert(X4GunneryState.normID(sess.targetFallback.orderedIDs[1]) == "600"
            and #sess.targetFallback.orderedIDs == 1,
            "the hull stage must query exactly the root object")
        local mark = #fix.uiTriggeredEvents
        tick42()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 1
            and batches[1].targets[1] == "600",
            "the hull stage must issue one ENGAGEABLE query for the root")
        deliver42(batches[1], { ["600"] = "1:1:1" })
        softtargetCalls42 = {}
        tick42()
        assert(tostring(sess.aimTargetID) == "600" and tostring(sess.targetObjectID) == "600",
            "a positive hull reading must engage the root hull; aim="
            .. tostring(sess.aimTargetID))
        assert(sess.phase == "engaged" and sess.targetFallback == nil,
            "the hull engage must stay engaged and clear the fallback")
        assert(softtargetCalls42[#softtargetCalls42] == 600,
            "the hull must become the soft target")
    end

    -- E. A proven-zero hull escalates to ranked other objects; the planner
    -- walks the ranking and engages the first positive, skipping proven zeros.
    do
        resetCounts42()
        slotCount42 = 1
        operational42 = { ["600"] = true, ["98"] = true, ["99"] = true }
        sectorShips42 = { 98, 99 }
        local sess = freshDirectSession42({ grp42 })
        sess.targetObjectID, sess.aimTargetID = 600, 701
        clock = 500
        API.updateAimTarget()
        tick42()
        assert(sess.targetFallback.stage == "hull", "expected hull stage")
        local mark = #fix.uiTriggeredEvents
        tick42()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and batches[1].targets[1] == "600", "expected the hull query")
        deliver42(batches[1], { ["600"] = "0:1:1" })
        tick42()
        assert(sess.targetFallback.stage == "objects",
            "a proven-zero hull must escalate to the objects stage; stage is "
            .. tostring(sess.targetFallback.stage))
        assert(objectSweepCalls42 >= 1,
            "the objects stage must rank through the sector sweep")
        mark = #fix.uiTriggeredEvents
        tick42()
        batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 2
            and batches[1].targets[1] == "98" and batches[1].targets[2] == "99",
            "the objects stage must query the ranked candidates without the lost root; "
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        deliver42(batches[1], { ["98"] = "0:1:1", ["99"] = "1:1:1" })
        softtargetCalls42 = {}
        tick42()
        assert(tostring(sess.aimTargetID) == "99" and tostring(sess.targetObjectID) == "99",
            "the first ranked positive object must be engaged, skipping the "
            .. "proven-zero 98; aim=" .. tostring(sess.aimTargetID))
        assert(sess.phase == "engaged" and sess.targetFallback == nil,
            "the object engage must stay engaged and clear the fallback")
        assert(softtargetCalls42[#softtargetCalls42] == 99,
            "the engaged object must become the soft target")
    end

    -- F. Surfaces, hull and every other object proven zero: the resolution
    -- exhausts and hands the choice back at the target browser.
    do
        resetCounts42()
        slotCount42 = 1
        operational42 = { ["600"] = true }
        sectorShips42 = {}
        local sess = freshDirectSession42({ grp42 })
        sess.targetObjectID, sess.aimTargetID = 600, 701
        sess.povAnchor, sess.povMode = "target", "cinematic"
        clock = 500
        API.updateAimTarget()
        tick42()
        assert(sess.targetFallback.stage == "hull", "expected hull stage")
        local mark = #fix.uiTriggeredEvents
        tick42()
        local batches = batchesSince42(mark)
        deliver42(batches[1], { ["600"] = "0:1:1" })
        tick42()
        assert(sess.targetFallback.stage == "objects",
            "expected objects stage after a proven-zero hull")
        assert(#sess.targetFallback.orderedIDs == 0,
            "with no other objects the objects stage must be empty")
        tick42()
        assert(sess.phase == "target_select",
            "an exhausted resolution must reopen the target browser; phase is "
            .. tostring(sess.phase))
        assert(sess.aimTargetID == nil and sess.targetObjectID == nil,
            "the browser fallback must clear the lost aim and root")
        assert(sess.povAnchor == "turret" and sess.povMode == "manual",
            "the browser fallback must reset the view to manual Turret POV; got "
            .. tostring(sess.povAnchor) .. "/" .. tostring(sess.povMode))
        assert(sess.targetFallback == nil,
            "the exhausted resolution must clear the fallback state")
        assert(#softtargetCalls42 == 0,
            "an exhausted resolution must not re-engage anything")
        assert(fix.logContains("event=auto_next_fallback action=exhausted"),
            "the exhausted resolution must be logged")
    end

    -- G. Ordinary object-level loss (aimTargetID == targetObjectID) keeps the
    -- existing synchronous object sweep: no fallback state, no surface
    -- enumeration, no ENGAGEABLE request.
    do
        resetCounts42()
        slotCount42 = 2
        operational42 = { ["98"] = true }
        sectorShips42 = { 98 }
        local sess = freshDirectSession42({ grp42 })
        sess.targetObjectID, sess.aimTargetID = 500, 500
        sess.povAnchor, sess.povMode = "turret", "cinematic"
        clock = 500
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        assert(sess.targetFallback == nil,
            "ordinary object loss must not start the surface fallback")
        assert(tostring(sess.aimTargetID) == "98" and tostring(sess.targetObjectID) == "98",
            "an ordinary dead object must fall back to the next object; aim="
            .. tostring(sess.aimTargetID))
        assert(sess.phase == "engaged",
            "the object fallback must stay engaged; phase is " .. tostring(sess.phase))
        assert(surfaceScanCalls42 == 0,
            "ordinary object-level loss must not enumerate surfaces; the surface "
            .. "reader ran " .. surfaceScanCalls42 .. " time(s)")
        assert(objectSweepCalls42 >= 1,
            "the object fallback must run the sweep to find 98")
        assert(engageabilityEventsSince42(mark) == 0,
            "ordinary object loss must not issue ENGAGEABLE requests")
        assert(softtargetCalls42[#softtargetCalls42] == 98,
            "the sweep's survivor must become the soft target")
        local stopsG, startsG = 0, 0
        for i = mark + 1, #fix.uiTriggeredEvents do
            local e = fix.uiTriggeredEvents[i]
            if e.control == "cutscene_aim_stop" then stopsG = stopsG + 1 end
            if e.control == "cutscene_aim_start" then startsG = startsG + 1 end
        end
        assert(stopsG == 1 and startsG == 1,
            "the object-loss engage must stop/restart a running cinematic; "
            .. "stops=" .. stopsG .. " starts=" .. startsG)
    end

    -- H. Auto-next off during a surface loss: straight to the browser, with
    -- neither a fallback state nor any enumeration.
    do
        resetCounts42()
        slotCount42 = 2
        operational42 = { ["702"] = true, ["98"] = true }
        sectorShips42 = { 98 }
        local sess = freshDirectSession42({ grp42 })
        sess.autoNextTarget = false
        sess.targetObjectID, sess.aimTargetID = 600, 701
        sess.povAnchor, sess.povMode = "target", "cinematic"
        clock = 500
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        assert(sess.phase == "target_select",
            "with auto-next off a dead surface must reopen the target browser; phase is "
            .. tostring(sess.phase))
        assert(sess.aimTargetID == nil and sess.targetObjectID == nil,
            "the browser fallback must clear the lost aim and root")
        assert(sess.povAnchor == "turret" and sess.povMode == "manual",
            "the browser fallback must reset the view to manual Turret POV; got "
            .. tostring(sess.povAnchor) .. "/" .. tostring(sess.povMode))
        assert(sess.targetFallback == nil,
            "auto-next off must not start the fallback resolution")
        assert(#softtargetCalls42 == 0,
            "auto-next off must not re-engage any surface or object")
        assert(surfaceScanCalls42 == 0,
            "auto-next off must not enumerate surfaces; the reader ran "
            .. surfaceScanCalls42 .. " time(s)")
        local seen702H = 0
        for i = mark + 1, #fix.uiTriggeredEvents do
            local e = fix.uiTriggeredEvents[i]
            if e.control == "engageability_target"
                and X4GunneryState.normID(e.params.target) == "702" then
                seen702H = seen702H + 1
            end
        end
        assert(seen702H == 0,
            "auto-next off must not run the surface fallback (702 was queried "
            .. seen702H .. " time(s)); browser-row queries for other objects are "
            .. "legitimate")
    end

    -- I. The resolution's ENGAGEABLE requests carry exactly the checked
    -- operational turrets: a checked group whose member is not operational
    -- contributes nothing to the batch.
    do
        resetCounts42()
        slotCount42 = 2
        operational42 = { ["600"] = true, ["702"] = true, ["98"] = true }
        sectorShips42 = { 98 }
        local groups = {
            group42("grpI_A", 27, true),
            group42("grpI_B", 28, false),
        }
        local sess = freshDirectSession42(groups)
        sess.targetObjectID, sess.aimTargetID = 600, 701
        clock = 500
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and batches[1].members == 1
            and #batches[1].memberIDs == 1 and batches[1].memberIDs[1] == 27,
            "the batch must list only the checked operational turret; members="
            .. tostring(batches[1] and batches[1].members)
            .. " members_list=" .. table.concat(
                (batches[1] and batches[1].memberIDs) or {}, ","))
        deliver42(batches[1], { ["702"] = "1:1:1" })
        tick42()
        assert(tostring(sess.aimTargetID) == "702",
            "membership filtering must not block the resolve; aim is "
            .. tostring(sess.aimTargetID))
    end

    -- J. The root dying mid-resolution aborts the fallback to the ordinary
    -- object loss: the sweep runs and the survivor is engaged.
    do
        resetCounts42()
        slotCount42 = 3                       -- 701 dead, 702/703 alive
        operational42 = { ["600"] = true, ["702"] = true, ["703"] = true, ["98"] = true }
        sectorShips42 = { 98 }
        local sess = freshDirectSession42({ grp42 })
        sess.targetObjectID, sess.aimTargetID = 600, 701
        clock = 500
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 2,
            "the loss tick must query both surviving surfaces")
        -- The whole root goes down before any result arrives.
        operational42 = { ["98"] = true }
        objectSweepCalls42 = 0
        softtargetCalls42 = {}
        tick42()
        assert(sess.targetFallback == nil,
            "a dead root must abort the fallback resolution")
        assert(objectSweepCalls42 >= 1,
            "the abort must fall through to the ordinary object sweep")
        assert(tostring(sess.aimTargetID) == "98" and tostring(sess.targetObjectID) == "98",
            "the sweep's survivor must be engaged; aim=" .. tostring(sess.aimTargetID))
        assert(sess.phase == "engaged",
            "the abort must stay engaged; phase is " .. tostring(sess.phase))
        assert(softtargetCalls42[#softtargetCalls42] == 98,
            "the survivor must become the soft target")
        assert(fix.logContains("event=auto_next_fallback action=root_lost_abort"),
            "the root-loss abort must be logged")
    end

    -- K. The planner picks a positive surface but engageTarget refuses it
    -- (the soft-target write fails): the resolution hands the choice back at
    -- the browser instead of retrying the refused engage forever.
    do
        resetCounts42()
        slotCount42 = 2
        operational42 = { ["600"] = true, ["702"] = true, ["98"] = true }
        sectorShips42 = { 98 }
        local sess = freshDirectSession42({ grp42 })
        sess.targetObjectID, sess.aimTargetID = 600, 701
        clock = 500
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        assert(sess.targetFallback ~= nil, "setup: the fallback must be running")
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 1,
            "the loss tick must issue the single-surface batch")
        deliver42(batches[1], { ["702"] = "1:1:1" })
        local savedRefuseSoft = C.SetSofttarget
        C.SetSofttarget = function(target)
            softtargetCalls42[#softtargetCalls42 + 1] = target
            return false
        end
        softtargetCalls42 = {}
        tick42()
        C.SetSofttarget = savedRefuseSoft
        assert(softtargetCalls42[#softtargetCalls42] == 702,
            "the planner's positive pick must be attempted as an engage")
        assert(sess.phase == "target_select",
            "a refused engage must fall back to the target browser; phase is "
            .. tostring(sess.phase))
        assert(sess.aimTargetID == nil and sess.targetObjectID == nil,
            "the browser fallback must clear the lost aim and root")
        assert(sess.targetFallback == nil,
            "a refused engage must clear the fallback state")
        assert(sess.povAnchor == "turret" and sess.povMode == "manual",
            "the browser fallback must reset the view to manual Turret POV")
        assert(fix.logContains("back to target selection"),
            "the browser fallback must keep its session log line")
    end

    -- L. A control-mode switch away from direct mid-resolution drops the
    -- fallback state quietly: no ENGAGEABLE query, no engage, no browser.
    do
        resetCounts42()
        slotCount42 = 2
        operational42 = { ["600"] = true, ["702"] = true, ["98"] = true }
        sectorShips42 = { 98 }
        local sess = freshDirectSession42({ grp42 })
        sess.targetObjectID, sess.aimTargetID = 600, 701
        clock = 500
        API.updateAimTarget()
        assert(sess.targetFallback ~= nil, "setup: the fallback must be running")
        sess.controlMode = nil               -- e.g. a restoreDirect transition
        local mark = #fix.uiTriggeredEvents
        tick42()
        assert(sess.targetFallback == nil,
            "a non-direct control mode must drop the pending fallback state")
        assert(tostring(sess.aimTargetID) == "701",
            "the mode switch must not choose a replacement; aim is "
            .. tostring(sess.aimTargetID))
        assert(engageabilityEventsSince42(mark) == 0,
            "a mode switch must not issue ENGAGEABLE requests")
    end

    -- M. A surface that dies after its positive ENGAGEABLE result was
    -- accepted must never be engaged: the consume tick must skip engageTarget
    -- entirely (no hull/browser fallthrough) and restart the same-root
    -- surface stage from a fresh snapshot. 703 starts NON-OPERATIONAL, so
    -- the loss snapshot holds 702 as the only surviving alternative, the
    -- loss-tick batch targets only 702, and 703 has no cached ENGAGEABLE
    -- reading when it is made operational just before the consume tick. The
    -- consume tick's stale restart must therefore issue the new page-1 batch
    -- for 703 itself, immediately (startTargetFallback's immediate page-1
    -- query): the UI-event mark recorded right before the consume tick fails
    -- if that query were deferred to a later tick.
    do
        resetCounts42()
        local mLogStart = #fix.getCapturedLog()
        slotCount42 = 3                       -- 701 (dead), 702 alive, 703 not yet operational
        operational42 = { ["600"] = true, ["702"] = true, ["98"] = true }
        sectorShips42 = { 98 }
        local sess = freshDirectSession42({ grp42 })
        sess.targetObjectID, sess.aimTargetID = 600, 701
        clock = 500
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        -- 1. The loss snapshot holds 702 as the only surviving alternative;
        -- 703 is not operational yet and cannot leak in.
        assert(#sess.surfaceBrowser.allSurfaces == 1
            and sess.surfaceBrowser.allSurfaces[1].componentID == 702,
            "the loss snapshot must hold 702 as the only surviving "
            .. "alternative; got " .. tostring(#sess.surfaceBrowser.allSurfaces))
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 1
            and batches[1].targets[1] == "702",
            "the loss tick must query only 702; targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        -- Record this snapshot's generation before the consume tick: the
        -- stale restart must advance exactly this snapshot by one generation.
        local genBeforeRestart = sess.surfaceBrowser.generation
        -- 2. The page result proves 702 positive.
        deliver42(batches[1], { ["702"] = "1:1:1" })
        -- 3. Before the consume tick, 702 dies and 703 comes back
        -- operational; the root stays alive.
        operational42["702"] = false
        operational42["703"] = true
        softtargetCalls42 = {}
        -- 4. Mark immediately before the consume tick: the restarted page-1
        -- batch for 703 must appear between this mark and the end of the
        -- consume tick itself.
        local restartMark = #fix.uiTriggeredEvents
        tick42()
        -- 5. The consume tick must NOT engage the dead surface.
        local engaged702 = false
        for _, target in ipairs(softtargetCalls42) do
            if tostring(target) == "702" then engaged702 = true end
        end
        assert(not engaged702,
            "a surface that died after its positive result must not be engaged")
        -- 6. The fallback stays active on the surfaces stage, restarted from
        -- the fresh snapshot: the snapshot advanced by exactly one
        -- generation, the refreshed allSurfaces and the fallback's
        -- orderedIDs hold exactly the newly operational 703, and the
        -- immediate page-1 query asked for it on this same tick.
        assert(sess.surfaceBrowser.generation == genBeforeRestart + 1,
            "the stale restart must advance the snapshot by exactly one "
            .. "generation; before=" .. tostring(genBeforeRestart)
            .. " after=" .. tostring(sess.surfaceBrowser.generation))
        local restartedAllSurfaces = {}
        for _, surface in ipairs(sess.surfaceBrowser.allSurfaces or {}) do
            restartedAllSurfaces[#restartedAllSurfaces + 1] = X4GunneryState.normID(surface.componentID)
        end
        assert(table.concat(restartedAllSurfaces, ",") == "703",
            "the restarted snapshot must hold exactly the newly operational "
            .. "703; got " .. table.concat(restartedAllSurfaces, ","))
        assert(sess.targetFallback ~= nil
            and sess.targetFallback.stage == "surfaces"
            and sess.targetFallback.page == 1,
            "the stale restart must keep the resolution active on surfaces "
            .. "page 1; stage="
            .. tostring(sess.targetFallback and sess.targetFallback.stage))
        assert(#sess.targetFallback.orderedIDs == 1
            and X4GunneryState.normID(sess.targetFallback.orderedIDs[1]) == "703",
            "the restarted candidates must hold exactly 703; ids="
            .. table.concat(sess.targetFallback.orderedIDs, ","))
        local restartBatches = batchesSince42(restartMark)
        assert(#restartBatches == 1 and #restartBatches[1].targets == 1
            and restartBatches[1].targets[1] == "703",
            "the consume tick itself must issue the fresh page-1 batch for "
            .. "703, which has no cached reading; batches="
            .. tostring(#restartBatches))
        assert(#softtargetCalls42 == 0,
            "the stale restart must make no target choice; soft-target calls="
            .. tostring(#softtargetCalls42))
        assert(sess.phase == "engaged" and tostring(sess.aimTargetID) == "701"
            and tostring(sess.targetObjectID) == "600",
            "the stale restart must choose nothing; aim="
            .. tostring(sess.aimTargetID) .. " root=" .. tostring(sess.targetObjectID))
        assert(objectSweepCalls42 == 0,
            "a dead surface must not escalate to the object sweep or browser; "
            .. objectSweepCalls42 .. " sweep call(s)")
        local restarts = 0
        for i = mLogStart + 1, #fix.getCapturedLog() do
            if string.find(fix.getCapturedLog()[i],
                "event=auto_next_fallback action=stale_surface_restart", 1, true)
            then restarts = restarts + 1 end
        end
        assert(restarts == 1,
            "the stale/dead surface restart must be logged exactly once")
        -- 7. The new batch's positive result makes 703 engageable.
        deliver42(restartBatches[1], { ["703"] = "1:1:1" })
        -- 8. The next consume tick engages 703.
        softtargetCalls42 = {}
        tick42()
        assert(tostring(sess.aimTargetID) == "703"
            and tostring(sess.targetObjectID) == "600",
            "the next consume tick must engage the surviving 703; aim="
            .. tostring(sess.aimTargetID))
        assert(sess.phase == "engaged" and sess.targetFallback == nil,
            "the 703 engage must stay engaged and clear the fallback")
        assert(softtargetCalls42[#softtargetCalls42] == 703,
            "the engaged 703 must become the soft target")
    end

    -- N. Issue #45 Task 5B2a: when surfaces and the hull prove zero, the
    -- objects stage keeps readTargetCandidates() ranking but must drop
    -- non-operational candidates up front. The fixture is deliberately
    -- discriminating: 98 (NON-operational), 99 and 100 (operational) each
    -- get a distinct distance, so the raw ranking 98, 99, 100 is decided by
    -- distance alone -- never by an accidental priority/name tie (the
    -- constant-distance stub would tie them and the name tiebreak alone
    -- yields 100, 98, 99). Dropping dead 98 must leave orderedIDs exactly
    -- 99, 100 in that relative order; the ENGAGEABLE batch must ride exactly
    -- 99, 100 and never 98; and with 99 positive and 100 proven zero the
    -- ranked-first positive 99 is what gets engaged.
    do
        resetCounts42()
        slotCount42 = 1                       -- only the dead 701 remains
        operational42 = { ["600"] = true, ["99"] = true, ["100"] = true }
        sectorShips42 = { 98, 99, 100 }       -- 98 is NON-operational
        -- The block-level distance stub returns one constant for every
        -- object, so override it here: distinct distances make 98, 99, 100
        -- the only possible ranking order of the sector sweep.
        local savedDistN = C.GetDistanceBetween
        C.GetDistanceBetween = function(_, component)
            local n = tonumber(tostring(component))
            if n == 98 then return 1000 end
            if n == 99 then return 2000 end
            if n == 100 then return 3000 end
            return 1000
        end
        local sess = freshDirectSession42({ grp42 })
        sess.targetObjectID, sess.aimTargetID = 600, 701
        clock = 500
        API.updateAimTarget()
        tick42()
        assert(sess.targetFallback.stage == "hull",
            "an empty surface stage must escalate to the hull stage; stage is "
            .. tostring(sess.targetFallback.stage))
        local mark = #fix.uiTriggeredEvents
        tick42()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 1
            and batches[1].targets[1] == "600",
            "the hull stage must query exactly the root 600; targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        deliver42(batches[1], { ["600"] = "0:1:1" })
        tick42()
        assert(sess.targetFallback.stage == "objects",
            "a proven-zero hull must escalate to the objects stage; stage is "
            .. tostring(sess.targetFallback.stage))
        local objectIDs = {}
        for _, v in ipairs(sess.targetFallback.orderedIDs) do
            objectIDs[#objectIDs + 1] = X4GunneryState.normID(v)
        end
        assert(table.concat(objectIDs, ",") == "99,100",
            "the objects stage must keep the readTargetCandidates() ranking "
            .. "98, 99, 100 with only the non-operational 98 dropped, so "
            .. "exactly 99, 100 survive in that relative order; ids="
            .. table.concat(objectIDs, ","))
        mark = #fix.uiTriggeredEvents
        tick42()
        batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 2
            and batches[1].targets[1] == "99" and batches[1].targets[2] == "100",
            "the objects ENGAGEABLE batch must query exactly 99, 100 and "
            .. "never the non-operational 98; targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        -- Settle the WHOLE batch: 99 proven positive, 100 proven zero.
        deliver42(batches[1], { ["99"] = "1:1:1", ["100"] = "0:1:1" })
        softtargetCalls42 = {}
        tick42()
        assert(tostring(sess.aimTargetID) == "99"
            and tostring(sess.targetObjectID) == "99",
            "the ranked-first positive 99 must be engaged; aim="
            .. tostring(sess.aimTargetID) .. " root="
            .. tostring(sess.targetObjectID))
        assert(sess.phase == "engaged" and sess.targetFallback == nil,
            "the object engage must stay engaged and clear the fallback")
        assert(softtargetCalls42[#softtargetCalls42] == 99,
            "the engaged object 99 must become the soft target")
        C.GetDistanceBetween = savedDistN
    end

    -- Restore the pre-block stubs (nil hands C back to its fallbacks).
    C.IsComponentClass = savedClass42
    C.GetNumUpgradeSlots = savedNumSlots42
    C.GetUpgradeSlotCurrentComponent = savedSlotComp42
    C.GetUpgradeSlotCurrentMacro = savedSlotMacro42
    C.GetComponentName = savedSetName42
    C.GetDistanceBetween = savedDist42
    C.GetContextByClass = savedCtxClass42
    C.IsComponentOperational = savedOperational42
    C.SetSofttarget = savedSoft42
    GetMacroData = savedMacroData42
    GetComponentData = savedCompData42
    GetContainedShips = savedShips42
    GetContainedStations = savedStations42
    GetPlayerContextByClass = savedSector42
    AddUITriggeredEvent = savedAdd42
end

-- ── 51. hasMultipleTargets memo: two quick repaints share one sweep ─────────
-- readTargetCandidates() is always fresh (no full-list cache).  Only the
-- target-count boolean used by the cycle-target buttons is memoised via
-- hasMultipleTargets(), which keeps a 1 s TTL.  Two back-to-back engaged-mode
-- display() calls within that TTL must only sweep once.  The target-browser
-- path (target_select phase) calls readTargetCandidates() directly and must
-- always sweep.  Delete the memo in hasMultipleTargets() to make this fail.

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
        elseif k == "isplayerowned" then vals[#vals + 1] = false  -- enemy ship, not player-owned
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
sess51.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess51.shipID, mode = "attack", armed = false } }
sess51.cameraMemberID = 27
sess51.targetObjectID = 98
sess51.aimTargetID = 98

-- Move the clock forward so the hasMultipleTargets memo from any prior test is stale.
clock = clock + 100
getElapsedTime = function() return clock end

-- First display() (engaged/direct): hasMultipleTargets memo is stale, must sweep.
shipScanCount51 = 0
local ok51a, err51a = pcall(function() gcMenu.display() end)
assert(ok51a, "display() raised on first call (test 51): " .. tostring(err51a))
local sweepsAfterFirst = shipScanCount51
assert(sweepsAfterFirst >= 1,
    "first display() must call GetContainedShips at least once; got " .. tostring(sweepsAfterFirst))

-- Second display() immediately (same clock): hasMultipleTargets memo is live, must not re-sweep.
-- readTargetCandidates() is always fresh but is NOT called in engaged/direct mode
-- (only hasMultipleTargets() is, for the cycle-button active state).
shipScanCount51 = 0
local ok51b, err51b = pcall(function() gcMenu.display() end)
assert(ok51b, "display() raised on second call (test 51): " .. tostring(err51b))
assert(shipScanCount51 == 0,
    "second display() within the TTL must not rescan; GetContainedShips was called "
    .. tostring(shipScanCount51) .. " time(s). hasMultipleTargets memo is not working.")

-- Target-browser path (target_select): readTargetCandidates() is always fresh,
-- must always sweep even within the TTL.
sess51.phase = "target_select"
shipScanCount51 = 0
local ok51c, err51c = pcall(function() gcMenu.display() end)
assert(ok51c, "display() raised in browser phase (test 51): " .. tostring(err51c))
assert(shipScanCount51 >= 1,
    "target-browser display() must always sweep; GetContainedShips was called "
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
    local savedFfiNew               = fix.ffiStub.new

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
                 currentmacro = "turret_bor_m_railgun_02_mk1_macro", slotsize = "",
                 total = turretsPerGroup, operational = turretsPerGroup }
    end
    C.GetNumUpgradeSlots             = function() return #slotComponents end
    C.GetUpgradeSlotCurrentComponent = function(ship, tag, slot) return slotComponents[slot] or 0 end
    C.GetUpgradeSlotGroup            = function() return { path = "p", group = "grp_front" } end
    fix.ffiStub.new                  = function() return groupBuffer end

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
    assert(front52a.members[1].macro == "turret_bor_m_railgun_02_mk1_macro"
            and rear52a.members[1].macro == "turret_bor_m_railgun_02_mk1_macro",
        "52a: every member must retain its authoritative group currentmacro for arc lookup")
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
    fix.ffiStub.new                   = savedFfiNew
end

-- ── 55 (readGroups padded IDs). readGroups: padded group IDs from two different APIs still attribute ──
-- GetUpgradeGroups2 and GetUpgradeSlotGroup are separate engine APIs. The ship
-- XML pads group= attributes with spaces, inconsistently. If one API returns
-- "grp_front " and the other returns " grp_front", the candidate key lookup
-- fails silently and the turret falls through to a "single" entry.
-- Both sides are trimmed only when building/looking up the internal candidate
-- key; entry.path/group and all engine-facing values stay byte-exact.

do
    local savedGetNumUpgradeGroups  = C.GetNumUpgradeGroups
    local savedGetUpgradeGroups2    = C.GetUpgradeGroups2
    local savedGetUpgradeGroupInfo2 = C.GetUpgradeGroupInfo2
    local savedGetNumUpgradeSlots   = C.GetNumUpgradeSlots
    local savedGetUpgradeSlotCurrentComponent = C.GetUpgradeSlotCurrentComponent
    local savedGetUpgradeSlotGroup  = C.GetUpgradeSlotGroup
    local savedFfiNew               = fix.ffiStub.new

    -- GetUpgradeGroups2 returns group id with trailing space.
    local groupBuffer55 = {}
    groupBuffer55[0] = { path = "p55", group = "grp_front_up_left ", contextid = 10 }
    fix.ffiStub.new = function() return groupBuffer55 end

    C.GetNumUpgradeGroups  = function() return 1 end
    C.GetUpgradeGroups2    = function() return 1 end
    C.GetUpgradeGroupInfo2 = function()
        return { count = 1, currentcomponent = 201, currentmacro = "", slotsize = "",
                 total = 1, operational = 1 }
    end
    C.GetNumUpgradeSlots = function() return 1 end
    C.GetUpgradeSlotCurrentComponent = function() return 201 end
    -- GetUpgradeSlotGroup returns the same group but with LEADING space instead.
    C.GetUpgradeSlotGroup = function()
        return { path = "p55", group = " grp_front_up_left" }
    end

    local groups55 = X4GunneryControlAPI.readGroups(42)

    -- Without the fix the turret falls through to a "single" entry.
    -- With the fix there is exactly one "group" entry and no "single" entry.
    local groupEntry55, singleEntry55 = nil, nil
    for _, g in ipairs(groups55) do
        if g.kind == "group" then groupEntry55 = g end
        if g.kind == "single" then singleEntry55 = g end
    end
    assert(groupEntry55 ~= nil,
        "55 BUG: padded group id mismatch between GetUpgradeGroups2 and GetUpgradeSlotGroup "
        .. "must not prevent turret attribution; expected a 'group' entry but got none")
    assert(singleEntry55 == nil,
        "55 BUG: turret fell through to a 'single' entry due to padded key mismatch; "
        .. "the candidate key lookup must trim both path and group")
    assert(#groupEntry55.members == 1,
        "55: the turret must be a member of the group entry; got "
        .. tostring(#(groupEntry55 and groupEntry55.members or {})) .. " members")
    -- The stored group field must stay byte-exact (not trimmed).
    assert(groupEntry55.group == "grp_front_up_left ",
        "55: entry.group must be the raw (untrimmed) value from the engine; got '"
        .. tostring(groupEntry55.group) .. "'")

    C.GetNumUpgradeGroups             = savedGetNumUpgradeGroups
    C.GetUpgradeGroups2               = savedGetUpgradeGroups2
    C.GetUpgradeGroupInfo2            = savedGetUpgradeGroupInfo2
    C.GetNumUpgradeSlots              = savedGetNumUpgradeSlots
    C.GetUpgradeSlotCurrentComponent  = savedGetUpgradeSlotCurrentComponent
    C.GetUpgradeSlotGroup             = savedGetUpgradeSlotGroup
    fix.ffiStub.new                   = savedFfiNew
end

-- ── 56. player-faction objects are never offered as engagement targets ─────────
-- Player-owned ships and stations must be excluded from readTargetCandidates()
-- regardless of whether they arrive via the sector sweep or as the current soft
-- target (force=true). The check lives in isEligibleEngagementTarget so force
-- cannot skip it.
do
    gcMenu.onShowMenu()
    local sess56 = API.getSession()
    assert(sess56 ~= nil, "expected session for player-faction exclusion test")
    sess56.phase = "target_select"

    GetPlayerContextByClass = function() return 1 end
    C.GetContextByClass = function(comp) return comp end
    C.GetDistanceBetween = function() return 500 end
    C.IsComponentOperational = function() return true end

    -- 200 = player-owned ship; 201 = player-owned station; 300 = hostile ship.
    -- 400 = friendly-but-not-player-owned ship (must remain selectable).
    GetContainedShips    = function() return { 200, 300, 400 } end
    GetContainedStations = function() return { 201 } end

    GetComponentData = function(component, ...)
        local keys, vals = {...}, {}
        local comp = tonumber(tostring(component)) or 0
        for _, k in ipairs(keys) do
            if k == "isplayerowned" then
                -- Only the two player-owned objects return true.
                vals[#vals + 1] = (comp == 200 or comp == 201)
            elseif k == "isenemy" then
                vals[#vals + 1] = (comp == 300)
            elseif k == "ishostile" then vals[#vals + 1] = false
            elseif k == "isfriend"  then vals[#vals + 1] = (comp == 400)
            elseif k == "isknown"   then vals[#vals + 1] = true
            elseif k == "isradarvisible" then vals[#vals + 1] = true
            elseif k == "maxradarrange"  then vals[#vals + 1] = 40000
            else vals[#vals + 1] = nil
            end
        end
        return unpack(vals)
    end

    -- 56a: player-owned ship excluded from sector sweep.
    -- 56b: player-owned station excluded from sector sweep.
    -- 56c: hostile ship still included.
    -- 56d: non-player-faction friendly still included.
    gcMenu.display()
    local rows56 = fix.getCreatedButtons()
    local function foundID(id)
        -- The target browser renders each candidate's name; the stubs return
        -- C.GetComponentName -> "0" for everything, so distinguish by checking
        -- that isEligibleEngagementTarget would have accepted it.
        -- Drive it directly through the TestAPI's readTargetCandidates path
        -- (target_select phase display calls readTargetCandidates internally).
        -- We verify the results by asking isEligibleEngagementTarget per id.
        local ok, _ = isEligibleEngagementTarget(id)
        return ok
    end

    -- Direct eligibility probe: the function is module-local but called through
    -- the tested code path above. Re-drive it via the public cycleTarget path
    -- which internally calls readTargetCandidates and builds from it.
    -- Use the TestAPI to count candidates instead.
    assert(type(X4GunneryControlAPI.readTargetCandidates) == "function"
        or type(X4GunneryControlAPI.cycleTarget) == "function",
        "readTargetCandidates or cycleTarget must be accessible for test 56")

    -- Drive via cycleTarget: set sess to direct/engaged so cycleTarget reads the list.
    local grp56 = { key = "grp56", kind = "group", contextID = 5, path = "p", group = "g",
        componentID = 27, displayName = "G56", totalCount = 1, operationalCount = 1,
        mode = "attack", armed = false, members = {
            { componentID = 27, displayName = "T1", operational = true,
              cameraSupported = true, componentKey = "27" }
        } }
    sess56.groups = { grp56 }
    sess56.checkedGroupKeys = { ["grp56"] = true }
    sess56.phase = "engaged"
    sess56.controlMode = "direct"
    sess56.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "g",
        shipID = sess56.shipID, mode = "attack", armed = false } }
    sess56.cameraMemberID = 27
    -- Start at hostile 300; cycle should find 400 (the friendly non-player), not 200/201.
    sess56.targetObjectID = 300
    sess56.aimTargetID = 300
    C.SetPlayerCameraTargetView = function() return true end
    C.SetSofttarget = function() return true end

    -- Advance clock so hasMultipleTargets memo from earlier tests is stale.
    clock = clock + 200

    -- Cycle forward; the only other candidate must be 400 (friendly non-player-owned).
    -- 200 (player ship) and 201 (player station) must not appear.
    X4GunneryControlAPI.cycleTarget(1)
    local after56 = sess56.targetObjectID
    assert(tostring(after56) ~= "200",
        "56a BUG: player-owned ship 200 appeared as a cycle target; "
        .. "isEligibleEngagementTarget must reject isplayerowned=true")
    assert(tostring(after56) ~= "201",
        "56b BUG: player-owned station 201 appeared as a cycle target; "
        .. "isEligibleEngagementTarget must reject isplayerowned=true")
    assert(tostring(after56) == "400",
        "56c/d: after cycling from hostile 300 the only remaining target must be "
        .. "friendly non-player-owned 400; got " .. tostring(after56))

    -- 56e: player-owned soft target excluded even with force=true.
    -- Set the soft target to the player-owned ship and verify it is not added.
    local savedGetSofttarget = C.GetSofttarget2
    C.GetSofttarget2 = function()
        return { softtargetID = 200, softtargetConnectionName = "" }
    end
    sess56.phase = "target_select"
    -- A forced player-owned soft target must not appear; cycle after resetting
    -- targetObjectID to something else.
    sess56.targetObjectID = 300
    sess56.aimTargetID = 300
    sess56.phase = "engaged"
    sess56.controlMode = "direct"
    clock = clock + 200
    X4GunneryControlAPI.cycleTarget(1)
    local afterSoft56 = sess56.targetObjectID
    assert(tostring(afterSoft56) ~= "200",
        "56e BUG: player-owned soft target 200 (force=true path) must be excluded; "
        .. "the isplayerowned check must fire before force can bypass visibility")
    C.GetSofttarget2 = savedGetSofttarget
end

-- ── 57. target browser exposes class/macro metadata and a top refresh ───────
do
    gcMenu.onShowMenu()
    local sess57 = API.getSession()
    sess57.phase = "target_select"
    GetPlayerContextByClass = function() return 1 end
    GetContainedShips = function() return { 570, 572, 573, 574, 575, 576 } end
    GetContainedStations = function() return { 571 } end
    C.GetContextByClass = function(comp) return comp end
    local classByComponent57 = {
        [570] = "ship_l", [573] = "ship_s", [574] = "ship_m", [575] = "ship_xl",
        [571] = "station",
    }
    C.IsComponentClass = function(component, class)
        local comp = tonumber(tostring(component))
        return classByComponent57[comp] == class
    end
    C.GetDistanceBetween = function(_, target) return tonumber(tostring(target)) == 570 and 2500 or 4000 end
    C.GetSofttarget2 = function() return { softtargetID = 570, softtargetConnectionName = "" } end
    local typeByMacro57 = {
        ship_xen_s_fighter_01_a_macro = "N",
        ship_xen_m_fighter_01_a_macro = "P",
        ship_arg_l_destroyer_01_a_macro = "Behemoth Vanguard",
        ship_arg_xl_carrier_01_a_macro = "Colossus Vanguard",
        station_arg_defence_disc_macro = "Argon Defence Platform",
    }
    GetMacroData = function(macro, field)
        return field == "name" and typeByMacro57[macro] or ""
    end
    GetComponentData = function(component, ...)
        local keys, vals, comp = {...}, {}, tonumber(tostring(component))
        for _, key in ipairs(keys) do
            if key == "isplayerowned" then vals[#vals + 1] = false
            elseif key == "isenemy" then vals[#vals + 1] = true
            elseif key == "ishostile" or key == "isfriend" then vals[#vals + 1] = false
            elseif key == "isknown" or key == "isradarvisible" then vals[#vals + 1] = true
            elseif key == "maxradarrange" then vals[#vals + 1] = 40000
            -- Live X4 9.00 returns numeric class ids (for example 91-94 for the
            -- four ship sizes), not the class-name strings used by the old
            -- test double. Classification must go through IsComponentClass.
            elseif key == "classid" then
                vals[#vals + 1] = ({ [573] = 91, [574] = 92, [570] = 93, [575] = 94, [571] = 95 })[comp] or 96
            elseif key == "macro" then
                vals[#vals + 1] = ({
                    [573] = "ship_xen_s_fighter_01_a_macro",
                    [574] = "ship_xen_m_fighter_01_a_macro",
                    [570] = "ship_arg_l_destroyer_01_a_macro",
                    [575] = "ship_arg_xl_carrier_01_a_macro",
                    [571] = "station_arg_defence_disc_macro",
                })[comp] or (comp == 572 and "unknown_object_macro" or "")
            else vals[#vals + 1] = nil end
        end
        return unpack(vals)
    end
    local candidates57 = API.readTargetCandidates()
    assert(#candidates57 == 7, "57: expected four ship sizes, station, and two fallback candidates")
    local byID57 = {}
    for _, candidate in ipairs(candidates57) do byID57[tostring(candidate.componentID)] = candidate end
    assert(byID57["570"].class == "L Ship", "57: L ship class label missing")
    assert(byID57["570"].macro == "ship_arg_l_destroyer_01_a_macro", "57: ship macro missing")
    assert(byID57["570"].typeName == "Behemoth Vanguard", "57: localized ship type missing")
    assert(byID57["573"].class == "S Ship", "57: S ship class label missing")
    assert(byID57["574"].class == "M Ship", "57: M ship class label missing")
    assert(byID57["575"].class == "XL Ship", "57: XL ship class label missing")
    assert(byID57["571"].class == ReadText(20991, 45), "57: station class label missing")
    assert(byID57["572"].class == ReadText(20991, 44), "57: unknown ship class must fall back to kind")
    assert(byID57["572"].typeName == ReadText(20991, 51), "57: unknown macro name must not expose raw macro")
    assert(byID57["576"].typeName == ReadText(20991, 51), "57: missing macro must render Unknown Object")
    C.GetSofttarget2 = function() return { softtargetID = 571, softtargetConnectionName = "" } end
    local stationCurrent57 = API.readTargetCandidates()
    local currentStation57
    for _, candidate in ipairs(stationCurrent57) do
        if tostring(candidate.componentID) == "571" then currentStation57 = candidate end
    end
    assert(currentStation57 and currentStation57.class == ReadText(20991, 45),
        "57: current soft-target station must retain localized Station class")
    C.GetSofttarget2 = function() return { softtargetID = 570, softtargetConnectionName = "" } end
    gcMenu.display()
    local rendered57 = {}
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if entry.row == "570" or entry.row == "573" or entry.row == "574" or entry.row == "575" then
            rendered57[entry.row] = rendered57[entry.row] or {}
            rendered57[entry.row][entry.column] = entry.text
        end
    end
    local expectedRendered57 = {
        ["573"] = { class = "S Ship", typeName = "N", macro = "ship_xen_s_fighter_01_a_macro" },
        ["574"] = { class = "M Ship", typeName = "P", macro = "ship_xen_m_fighter_01_a_macro" },
        ["570"] = { class = "L Ship", typeName = "Behemoth Vanguard", macro = "ship_arg_l_destroyer_01_a_macro" },
        ["575"] = { class = "XL Ship", typeName = "Colossus Vanguard", macro = "ship_arg_xl_carrier_01_a_macro" },
    }
    for component, expected in pairs(expectedRendered57) do
        assert(rendered57[component] and rendered57[component][3] == expected.class,
            "57: " .. expected.class .. " must be bound to rendered column 3")
        assert(rendered57[component][4] == expected.typeName,
            "57: " .. expected.class .. " localized type must be bound to rendered column 4")
    end
    local refreshButtons57 = {}
    for _, button in ipairs(fix.getCreatedButtons()) do
        if button.text == ReadText(20991, 15) then refreshButtons57[#refreshButtons57 + 1] = button end
    end
    assert(#refreshButtons57 >= 2, "57: target browser needs refresh controls at top and bottom")
    refreshButtons57[1].handlers.onClick()
    local refreshedButtons57 = {}
    for _, button in ipairs(fix.getCreatedButtons()) do
        if button.text == ReadText(20991, 15) then refreshedButtons57[#refreshedButtons57 + 1] = button end
    end
    refreshedButtons57[#refreshedButtons57].handlers.onClick()
    local log57 = table.concat(fix.getCapturedLog(), "\n")
    assert(log57:find("event=target_browser action=refresh location=top", 1, true),
        "57: top refresh click needs audit evidence")
    assert(log57:find("event=target_browser action=refresh location=bottom", 1, true),
        "57: bottom refresh click needs audit evidence")
    assert(log57:find("event=target_browser action=rendered candidates=7 class_values=7 type_values=7", 1, true),
        "57: rendered target metadata needs aggregate audit evidence")
    for component, expected in pairs(expectedRendered57) do
        local evidence = 'event=target_browser action=row component=' .. component
            .. ' name="0" class="' .. expected.class .. '" type="' .. expected.typeName
            .. '" macro="' .. expected.macro .. '"'
        assert(log57:find(evidence, 1, true),
            "57: rendered row audit needs exact " .. expected.class .. " component/class/macro evidence")
    end
end

-- ── 58. surface type/macro filters use live operational component macros ────
do
    local sess57 = API.getSession()
    sess57.phase, sess57.controlMode = "engaged", "direct"
    sess57.targetObjectID, sess57.aimTargetID = 600, 600
    sess57.surfaceTypeFilter, sess57.surfaceMacroFilter = "any", "any"
    C.IsComponentClass = function() return false end
    GetPlayerContextByClass = function() return nil end
    C.GetNumUpgradeSlots = function(_, _, upgrade) return upgrade == "turret" and 2 or 0 end
    C.GetUpgradeSlotCurrentComponent = function(_, _, slot) return 700 + slot end
    C.GetUpgradeSlotCurrentMacro = function(object, _, _, slot)
        if tonumber(tostring(object):match("%d+")) == 601 then return "turret_m" end
        return slot == 1 and "turret_l" or "turret_m"
    end
    C.IsComponentOperational = function() return true end
    GetComponentData = function(component, ...)
        local vals = {}
        for _, key in ipairs({...}) do
            if key == "macro" then vals[#vals + 1] = tonumber(tostring(component)) == 701 and "turret_l" or "turret_m"
            elseif key == "isplayerowned" then vals[#vals + 1] = false
            elseif key == "maxradarrange" then vals[#vals + 1] = 40000
            else vals[#vals + 1] = false end
        end
        return unpack(vals)
    end
    GetMacroData = function(macro, key)
        if key == "name" then return macro == "turret_l" and "Large Turret" or "Medium Turret" end
        return ""
    end
    gcMenu.display()
    local function rowDropdown(fixture, rowID)
        for _, dropdown in ipairs(fixture.getCreatedDropDowns()) do
            if dropdown.row == rowID then return dropdown end
        end
    end
    local dropdowns57 = fix.getCreatedDropDowns()
    assert(#dropdowns57 >= 2, "57: surface panel needs type and macro dropdowns")
    assert(rowDropdown(fix, "surface_type_filter").startOption == "any",
        "57: surface type filter must render at Any")
    assert(#rowDropdown(fix, "surface_macro_filter").options == 3,
        "57: surface equipment filter must offer Any plus both localized turret names")
    rowDropdown(fix, "surface_type_filter").handlers.onDropDownConfirmed(nil, "turret")
    assert(sess57.surfaceTypeFilter == "turret" and sess57.surfaceMacroFilter == "any",
        "57: changing type must apply it and reset macro to Any")
    gcMenu.display()
    rowDropdown(fix, "surface_macro_filter").handlers.onDropDownConfirmed(nil, "turret_l")
    assert(sess57.surfaceMacroFilter == "turret_l", "57: macro lock was not retained")
    local surfaceRefresh57
    for _, button in ipairs(fix.getCreatedButtons()) do
        if button.row == "surface_refresh" then surfaceRefresh57 = button end
    end
    assert(surfaceRefresh57, "57: top surface Refresh button missing")
    C.GetUpgradeSlotGroup = function() return { path = "", group = "" } end
    surfaceRefresh57.handlers.onClick()
    local log58 = table.concat(fix.getCapturedLog(), "\n")
    assert(log58:find("event=surface_browser action=filter kind=type value=turret equipment_reset=any target=600", 1, true),
        "57: type filter change needs audit evidence")
    assert(log58:find("event=surface_browser action=filter kind=equipment value=turret_l target=600", 1, true),
        "57: equipment filter change needs audit evidence")
    assert(log58:find("event=surface_browser action=refresh location=top target=600", 1, true),
        "57: surface Refresh needs audit evidence")
    assert(log58:find("event=surface_browser action=rendered target=600 target_name=\"0\"", 1, true)
            and log58:find("type_filter=turret equipment_filter=turret_l all=2 alternatives=1 equipment_options=2", 1, true),
        "57: filtered surface render needs exact count/filter evidence")
    local sawFilteredSurface57 = false
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if tostring(entry.row) == "701" then
            sawFilteredSurface57 = true
        end
    end
    assert(sawFilteredSurface57, "57: filtered page must bind the matching equipment row")

    GetMacroData = function() return "" end
    sess57.surfaceTypeFilter, sess57.surfaceMacroFilter = "any", "any"
    gcMenu.display()
    dropdowns57 = fix.getCreatedDropDowns()
    local fallbackEquipment = dropdowns57[#dropdowns57]
    assert(fallbackEquipment.row == "surface_macro_filter"
            and #fallbackEquipment.options == 1,
        "57: unresolved equipment names must not create indistinguishable dropdown choices")

    GetMacroData = function(macro, key)
        if key == "name" then return macro == "turret_l" and "Large Turret" or "Medium Turret" end
        return ""
    end
    C.GetNumUpgradeSlots = function(destructible, _, upgrade)
        if upgrade ~= "turret" then return 0 end
        return tonumber(tostring(destructible):match("%d+")) == 601 and 1 or 2
    end
    C.GetUpgradeSlotCurrentComponent = function(destructible, _, slot)
        return tonumber(tostring(destructible):match("%d+")) == 601 and 702 or 700 + slot
    end
    sess57.targetObjectID, sess57.surfaceTypeFilter, sess57.surfaceMacroFilter = 601, "turret", "turret_l"
    gcMenu.display()
    assert(sess57.surfaceMacroFilter == "any",
        "57: changing to a target without the selected equipment must reset to Any")

    sess57.targetObjectID, sess57.surfaceMacroFilter = 600, "turret_l"
    C.GetNumUpgradeSlots = function() return 0 end
    gcMenu.display()
    assert(sess57.surfaceMacroFilter == "any",
        "57: disappearance of the last matching component must reset to Any")
    log58 = table.concat(fix.getCapturedLog(), "\n")
    assert(log58:find("event=surface_browser action=filter_reset kind=equipment reason=unavailable previous=turret_l target=601", 1, true),
        "57: target-change equipment reset needs exact audit evidence")
    assert(log58:find("event=surface_browser action=filter_reset kind=equipment reason=unavailable previous=turret_l target=600", 1, true),
        "57: component-disappearance equipment reset needs exact audit evidence")
end

-- ── 57. engageability batches stream members once and preserve stale guards ──────
do
    local sess57 = API.getSession()
    sess57.phase, sess57.controlMode = "console", nil
    sess57.groups = {
        { key = "selected", members = {
            { componentID = 101, operational = true },
            { componentID = 102, operational = true },
            { componentID = 199, operational = false },
        } },
        { key = "unchecked", members = { { componentID = 103, operational = true } } },
    }
    sess57.checkedGroupKeys = { selected = true }
    gcMenu.shown = true
    local savedAdd57, events57 = AddUITriggeredEvent, {}
    local savedComponentData57 = GetComponentData
    GetComponentData = function(component, ...)
        local values = {}
        for _, key in ipairs({...}) do
            if key == "macro" and tonumber(component) == 101 then
                values[#values + 1] = "turret_bor_m_railgun_02_mk1_macro"
            elseif key == "macro" then
                values[#values + 1] = "third_party_unknown_turret_macro"
            else
                values[#values + 1] = false
            end
        end
        return unpack(values)
    end
    AddUITriggeredEvent = function(screen, control, params)
        events57[#events57 + 1] = { screen = screen, control = control, params = params }
    end
    local pending57 = API.requestEngageability(900)
    assert(pending57.pending and pending57.total == 2, "57: pending denominator must be two exact selected turrets")
    local controls57, nonce57 = {}, nil
    for _, event in ipairs(events57) do
        controls57[#controls57 + 1] = event.control
        if event.control == "engageability_begin" then nonce57 = event.params.nonce end
    end
    assert(table.concat(controls57, ",") == "engageability_begin,engageability_member,engageability_member,engageability_target,engageability_commit",
        "57: engageability transport must stream selected members once before its target ids")
    assert(events57[2].params.weapon == 101 and events57[3].params.weapon == 102,
        "57: unchecked or inoperable turret leaked into exact-member request")
    assert(events57[2].params.arcknow == 1 and events57[2].params.arcmin == -10
            and events57[2].params.arcmax == 89,
        "57: official turret member must stream its generated pitch interval")
    assert(events57[3].params.arcknow == 0,
        "57: an unknown third-party turret must stream UNKNOWN, not invented limits")
    assert(events57[1].params.members == 2 and events57[1].params.targets == 1
            and events57[4].params.target == 900,
        "57: batch declarations and target correlation must carry exact counts and ids")
    sess57.phase = "target_select"
    GetPlayerContextByClass = function() return nil end
    C.GetSofttarget2 = function() return { softtargetID = 0, softtargetConnectionName = "" } end
    local firstRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. nonce57 .. ":999:2:2:2")
    assert(pending57.pending and pending57.engageable == nil
            and fix.callbackCheckpoint() == firstRepaintMark57,
        "57: a reply for an unrequested target must not complete or repaint the batch")
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. nonce57 .. ":900:1:1:2")
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete", "x4gce2c:" .. nonce57 .. ":1:1")
    assert(pending57.pending == false and pending57.engageable == 1 and pending57.known == 1
            and pending57.total == 2,
        "57: matching arc-aware packed result was not accepted")
    assert(API.engageabilityText(pending57) == "1 / 2  1 " .. ReadText(20991, 100),
        "57: unknown macro coverage must be explicit and must suppress ENGAGEABLE")
    assert(fix.callbackCheckpoint() == firstRepaintMark57 + 1,
        "57: the first accepted engageability result must schedule one deferred repaint")
    fix.drainCallbacksSince(firstRepaintMark57)
    events57 = {}
    assert(API.requestEngageability(900) == pending57 and #events57 == 0,
        "57: a result must be cached for one second")

    local savedElapsed57, clock57 = getElapsedTime, (pending57.requestedAt or 0) + 2
    getElapsedTime = function() return clock57 end
    events57 = {}
    local refreshed57 = API.requestEngageability(900)
    assert(refreshed57 == pending57 and refreshed57.pending and refreshed57.engageable == nil,
        "57: refreshing an expired completed result must clear its stale count; pending="
            .. tostring(refreshed57.pending) .. " engageable=" .. tostring(refreshed57.engageable)
            .. " requested=" .. tostring(refreshed57.requestedAt))
    assert(API.engageabilityText(refreshed57) == "… / 2",
        "57: an expired completed result must render pending, not stale ENGAGEABLE text")
    local refreshNonce57 = events57[1].params.nonce
    local refreshRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. refreshNonce57 .. ":900:0:2:2")
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete", "x4gce2c:" .. refreshNonce57 .. ":1:1")
    fix.drainCallbacksSince(refreshRepaintMark57)

    sess57.checkedGroupKeys.unchecked = true
    events57 = {}
    local changed57 = API.requestEngageability(900)
    assert(changed57.pending and changed57.total == 3 and #events57 == 6,
        "57: checkbox membership change must invalidate cache and stream the new exact denominator")
    local changedNonce57 = events57[1].params.nonce
    local denominatorRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. changedNonce57 .. ":900:2:2:2")
    assert(changed57.pending and changed57.engageable == nil
            and fix.callbackCheckpoint() == denominatorRepaintMark57,
        "57: a result whose denominator shrank below the requested membership must be rejected")
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. changedNonce57 .. ":900:2:3:3")
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete", "x4gce2c:" .. changedNonce57 .. ":1:1")
    fix.drainCallbacksSince(denominatorRepaintMark57)

    events57 = {}
    local timed57 = API.requestEngageability(901)
    local oldNonce57 = events57[1].params.nonce
    clock57 = timed57.requestedAt + 3
    events57 = {}
    assert(API.requestEngageability(901) == timed57 and events57[1].params.nonce ~= oldNonce57,
        "57: a timed-out engageability request must be replaced with a fresh nonce")
    local newNonce57 = events57[1].params.nonce
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete", "x4gce2c:" .. oldNonce57 .. ":1:1")
    assert(not table.concat(fix.getCapturedLog(), "\n"):find(
            "event=engageability_batch action=complete nonce=" .. oldNonce57, 1, true),
        "57: superseding the final target must discard its empty prior request")
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. oldNonce57 .. ":901:3:3:3")
    assert(timed57.pending and timed57.engageable == nil,
        "57: a superseded engageability response must not complete the replacement request")
    local timeoutRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. newNonce57 .. ":901:2:3:3")
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete", "x4gce2c:" .. newNonce57 .. ":1:1")
    assert(not timed57.pending and timed57.engageable == 2,
        "57: the replacement engageability response must still complete normally")
    fix.drainCallbacksSince(timeoutRepaintMark57)

    events57 = {}
    local missingComplete57 = API.requestEngageability(902)
    local missingCompleteNonce57 = events57[1].params.nonce
    local missingCompleteRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult",
        "x4gce3:" .. missingCompleteNonce57 .. ":902:2:3:3")
    clock57 = missingComplete57.requestedAt + 2
    events57 = {}
    assert(API.requestEngageability(902) == missingComplete57
            and events57[1].params.nonce ~= missingCompleteNonce57,
        "57: a completed result whose batch completion was lost must refresh after its cache TTL")
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete",
        "x4gce2c:" .. missingCompleteNonce57 .. ":1:1")
    assert(not table.concat(fix.getCapturedLog(), "\n"):find(
            "event=engageability_batch action=complete nonce=" .. missingCompleteNonce57, 1, true),
        "57: post-TTL refresh must reclaim an empty request whose batch completion was lost")
    fix.drainCallbacksSince(missingCompleteRepaintMark57)

    local batchEvents57, batchNonces57, batchTargets57 = {}, {}, {}
    events57 = batchEvents57
    local requestedTargets57 = {}
    for target = 910, 945 do requestedTargets57[#requestedTargets57 + 1] = target end
    API.requestEngageabilities(requestedTargets57)
    local activeBatch57
    for _, event in ipairs(batchEvents57) do
        if event.control == "engageability_begin" then
            activeBatch57 = event.params.nonce
            batchNonces57[#batchNonces57 + 1] = activeBatch57
            batchTargets57[activeBatch57] = {}
        elseif event.control == "engageability_target" then
            batchTargets57[activeBatch57][#batchTargets57[activeBatch57] + 1] = event.params.target
        end
    end
    assert(#batchNonces57 == 2
            and #batchTargets57[batchNonces57[1]] == 20
            and #batchTargets57[batchNonces57[2]] == 16,
        "57: 36 targets must be bounded into 20-target and 16-target batches")
    local memberEvents57 = 0
    for _, event in ipairs(batchEvents57) do
        if event.control == "engageability_member" then memberEvents57 = memberEvents57 + 1 end
    end
    assert(memberEvents57 == 6,
        "57: three selected turrets must be sent once per batch, not once per target")
    local batchLog57 = table.concat(fix.getCapturedLog(), "\n")
    assert(batchLog57:find("event=engageability_batch action=request", 1, true)
            and batchLog57:find("requested=20 selected_total=3", 1, true)
            and batchLog57:find("requested=16 selected_total=3", 1, true),
        "57: aggregate request logs must prove bounded targets and exact selected-turret totals")
    local batchRepaintMark57 = fix.callbackCheckpoint()
    local renderedBefore57 = 0
    for _, line in ipairs(fix.getCapturedLog()) do
        if line:find("event=target_browser action=rendered", 1, true) then renderedBefore57 = renderedBefore57 + 1 end
    end
    for _, nonce in ipairs(batchNonces57) do
        for _, target in ipairs(batchTargets57[nonce]) do
            fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. nonce .. ":" .. target .. ":2:3:3")
        end
        fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete",
            "x4gce2c:" .. nonce .. ":" .. #batchTargets57[nonce] .. ":" .. #batchTargets57[nonce])
    end
    batchLog57 = table.concat(fix.getCapturedLog(), "\n")
    assert(batchLog57:find("requested=20 accepted=20 completed=20 unresolved=0", 1, true)
            and batchLog57:find("requested=16 accepted=16 completed=16 unresolved=0", 1, true),
        "57: aggregate completion logs must prove all declared targets completed")
    assert(fix.callbackCheckpoint() == batchRepaintMark57 + 1,
        "57: a burst of 36 engageability replies must coalesce to one repaint callback")
    fix.drainCallbacksSince(batchRepaintMark57)
    local renderedAfter57 = 0
    for _, line in ipairs(fix.getCapturedLog()) do
        if line:find("event=target_browser action=rendered", 1, true) then renderedAfter57 = renderedAfter57 + 1 end
    end
    assert(renderedAfter57 == renderedBefore57 + 1,
        "57: a burst of engageability replies must produce one target-browser audit batch")

    sess57.phase, sess57.controlMode, sess57.targetObjectID = "engaged", "direct", nil
    events57 = {}
    API.requestEngageability(950)
    local engagedNonce57 = events57[1].params.nonce
    local engagedRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. engagedNonce57 .. ":950:2:3:3")
    fix.drainCallbacksSince(engagedRepaintMark57)
    assert(fix.callbackCheckpoint() == engagedRepaintMark57 + 1,
        "57: Direct-control engageability replies must use the same deferred repaint path")

    events57 = {}
    API.requestEngageability(951)
    local testLabNonce57 = events57[1].params.nonce
    local testLabRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. testLabNonce57 .. ":951:2:3:3")
    X4GunneryState.setLifecycle(sess57, X4GunneryState.lifecycle.reopening)
    gcMenu.shown = false
    local hiddenAuditBefore57 = #fix.getCapturedLog()
    fix.drainCallbacksSince(testLabRepaintMark57)
    assert(#fix.getCapturedLog() == hiddenAuditBefore57,
        "57: a deferred reply must not repaint after Test Lab takes ownership")

    X4GunneryState.setLifecycle(sess57, X4GunneryState.lifecycle.owned)
    gcMenu.shown = true
    events57 = {}
    API.requestEngageability(952)
    local mapNonce57 = events57[1].params.nonce
    local mapRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. mapNonce57 .. ":952:2:3:3")
    X4GunneryState.setLifecycle(sess57, X4GunneryState.lifecycle.suspendedMap)
    gcMenu.shown = false
    hiddenAuditBefore57 = #fix.getCapturedLog()
    fix.drainCallbacksSince(mapRepaintMark57)
    assert(#fix.getCapturedLog() == hiddenAuditBefore57,
        "57: a deferred reply must not repaint while Map owns the view")

    X4GunneryState.setLifecycle(sess57, X4GunneryState.lifecycle.owned)
    gcMenu.shown = true
    sess57.phase, sess57.controlMode = "target_select", nil
    events57 = {}
    local incomplete57 = API.requestEngageability(953)
    local incompleteNonce57 = events57[1].params.nonce
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete",
        "x4gce2c:" .. incompleteNonce57 .. ":0:0")
    assert(incomplete57.pending and incomplete57.engageable == nil
            and table.concat(fix.getCapturedLog(), "\n"):find(
                "requested=1 accepted=0 completed=0 unresolved=1", 1, true),
        "57: an incomplete batch must remain pending and emit one aggregate unresolved count")
    getElapsedTime = savedElapsed57
    GetComponentData = savedComponentData57
    AddUITriggeredEvent = savedAdd57
end

-- ── 58. target/surface rows render and sort complete engageability results ────────
do
    local sess58 = API.getSession()
    sess58.phase, sess58.controlMode = "console", nil
    sess58.checkedGroupKeys = { selected = true }
    local savedAdd58, events58 = AddUITriggeredEvent, {}
    AddUITriggeredEvent = function(screen, control, params)
        events58[#events58 + 1] = { screen = screen, control = control, params = params }
    end
    local function seed58(target, on)
        events58 = {}
        local result = API.requestEngageability(target)
        local nonce
        for _, event in ipairs(events58) do
            if event.control == "engageability_begin" then nonce = event.params.nonce end
        end
        fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. nonce .. ":" .. target .. ":" .. on .. ":2:2")
        fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete", "x4gce2c:" .. nonce .. ":1:1")
        return result
    end
    seed58(701, 2); seed58(702, 0); seed58(703, 1); seed58(704, 0)
    seed58(801, 2); seed58(802, 0)
    AddUITriggeredEvent = savedAdd58

    sess58.phase, sess58.controlMode = "engaged", "direct"
    sess58.targetObjectID, sess58.aimTargetID = 900, 900
    sess58.surfaceTypeFilter, sess58.surfaceMacroFilter = "any", "any"
    GetPlayerContextByClass = function() return nil end
    C.IsComponentClass = function() return false end
    C.GetNumUpgradeSlots = function(_, _, upgrade)
        if upgrade == "turret" then return 4 end
        if upgrade == "shield" then return 1 end
        return 0
    end
    C.GetUpgradeSlotCurrentComponent = function(_, upgrade, slot)
        if upgrade == "turret" then return 700 + slot end
        return 703
    end
    C.IsComponentOperational = function() return true end
    C.GetComponentName = function(component)
        local names = { [701] = "Alpha", [702] = "Beta", [703] = "Shield", [704] = "Gamma", [801] = "Zulu", [802] = "Alpha" }
        return names[tonumber(tostring(component))] or "Target"
    end
    GetComponentData = function(_, ...)
        local vals = {}
        for _, key in ipairs({...}) do
            if key == "maxradarrange" then vals[#vals + 1] = 40000
            elseif key == "isplayerowned" then vals[#vals + 1] = false
            elseif key == "isenemy" then vals[#vals + 1] = true
            elseif key == "isknown" or key == "isradarvisible" then vals[#vals + 1] = true
            else vals[#vals + 1] = false end
        end
        return unpack(vals)
    end
    gcMenu.display()
    local renderedSurfaces58 = {}
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if entry.column == 4 and tonumber(tostring(entry.row)) then
            renderedSurfaces58[tostring(entry.row)] = entry.text
        end
    end
    assert(renderedSurfaces58["701"] == "2 / 2  " .. ReadText(20991, 89),
        "58: complete surface solution must render the aggregate ENGAGEABLE label")
    assert(renderedSurfaces58["702"] == "0 / 2" and renderedSurfaces58["703"] == "1 / 2",
        "58: incomplete surface solutions must render their exact binary counts")
    local surfaceButton58
    for _, button in ipairs(fix.getCreatedButtons()) do
        if button.text == ReadText(20991, 60) then surfaceButton58 = button; break end
    end
    assert(surfaceButton58, "58: surface solution rows were not rendered")
    surfaceButton58.handlers.onClick()

    sess58.phase, sess58.controlMode = "target_select", nil
    C.GetSofttarget2 = function() return { softtargetID = 801, softtargetConnectionName = "" } end
    GetPlayerContextByClass = function() return 1 end
    GetContainedShips = function() return { 801, 802 } end
    GetContainedStations = function() return {} end
    C.GetContextByClass = function(component) return component end
    C.GetDistanceBetween = function() return 1000 end
    gcMenu.display()
    local targetOrder58, targetSolutions58 = {}, {}
    for _, entry in ipairs(fix.getCreatedTexts()) do
        local row = tostring(entry.row)
        if (row == "801" or row == "802") and entry.column == 8 then
            targetOrder58[#targetOrder58 + 1] = row
            targetSolutions58[row] = entry.text
        end
    end
    assert(table.concat(targetOrder58, ",") == "801,802",
        "58: an all-on-engageability target must sort before an incomplete target")
    assert(targetSolutions58["801"] == "2 / 2  " .. ReadText(20991, 89)
            and targetSolutions58["802"] == "0 / 2",
        "58: target rows must bind the exact aggregate solution text to column 8")
    local log58 = table.concat(fix.getCapturedLog(), "\n")
    assert(log58:find('event=surface_browser action=row target=900 component=701 name="Alpha"', 1, true)
            and log58:find('macro="" position=1 engageability_state=complete engageability_engageable=2 engageability_known=2 engageability_total=2 engageability_text="2 / 2  text:20991:89"', 1, true),
        "58: surface-row audit must prove first position and the displayed complete solution")
    assert(log58:find('event=target_browser action=row component=801 name="Zulu"', 1, true)
            and log58:find('position=1 engageability_state=complete engageability_engageable=2 engageability_known=2 engageability_total=2 engageability_text="2 / 2  text:20991:89"', 1, true),
        "58: target-row audit must prove all-on-solution ordering and displayed value")
end

-- ── 59. surface browser pins health and lazily requests exact 20-row pages ──
do
    local sess59 = API.getSession()
    sess59.phase, sess59.controlMode = "engaged", "direct"
    sess59.targetObjectID, sess59.aimTargetID = 10000, 10000
    sess59.surfaceTypeFilter, sess59.surfaceMacroFilter = "any", "any"
    sess59.surfaceBrowser = X4GunneryState.newSurfaceBrowser(nil)
    sess59.groups = {
        { key = "page_group", operationalCount = 2, totalCount = 2, members = {
            { componentID = 11001, operational = true },
            { componentID = 11002, operational = true },
        } },
    }
    sess59.checkedGroupKeys = { page_group = true }
    C.IsComponentClass = function() return false end
    C.GetNumUpgradeSlots = function(_, _, upgrade) return upgrade == "turret" and 41 or 0 end
    C.GetUpgradeSlotCurrentComponent = function(_, _, slot) return 10000 + slot end
    C.GetUpgradeSlotCurrentMacro = function(_, _, _, slot)
        return slot >= 22 and "turret_test_l_laser_macro" or "turret_test_m_laser_macro"
    end
    C.IsComponentOperational = function() return true end
    C.GetComponentName = function(component) return "Surface " .. tostring(component) end
    local distanceOffset59 = 0
    C.GetDistanceBetween = function(_, component)
        return (tonumber(tostring(component)) - 10000) * 1000 + distanceOffset59
    end
    local shieldCapacity59, shieldPercent59, hullPercent59 = 0, 0, 73
    GetComponentData = function(component, ...)
        local vals = {}
        for _, key in ipairs({...}) do
            if key == "macro" then vals[#vals + 1] = "turret_m"
            elseif key == "shieldmax" then vals[#vals + 1] = shieldCapacity59
            elseif key == "shieldpercent" then vals[#vals + 1] = shieldPercent59
            elseif key == "hullpercent" then vals[#vals + 1] = hullPercent59
            elseif key == "isplayerowned" then vals[#vals + 1] = false
            elseif key == "maxradarrange" then vals[#vals + 1] = 40000
            else vals[#vals + 1] = false end
        end
        return unpack(vals)
    end
    GetMacroData = function(macro, key)
        if key == "name" then return "Medium Turret" end
        if key == "size" then return "" end
        return ""
    end
    local savedAdd59, targetEvents59, activeNonce59, nonceByTarget59 = AddUITriggeredEvent, {}, nil, {}
    AddUITriggeredEvent = function(screen, control, params)
        if control == "engageability_begin" then activeNonce59 = params.nonce end
        if control == "engageability_target" then
            local target = tostring(params.target)
            targetEvents59[#targetEvents59 + 1] = target
            nonceByTarget59[target] = activeNonce59
        end
        savedAdd59(screen, control, params)
    end
    gcMenu.display()
    assert(#targetEvents59 == 21,
        "59: initial surface render must request pinned target plus exactly 20 alternatives; got "
            .. tostring(#targetEvents59))
    local pageOneRows59 = {}
    for _, entry in ipairs(fix.getCreatedTexts()) do
        local row = tonumber(tostring(entry.row))
        if row and row >= 10001 and row <= 10041 then pageOneRows59[row] = true end
    end
    local pageOneCount59 = 0
    for _ in pairs(pageOneRows59) do pageOneCount59 = pageOneCount59 + 1 end
    assert(pageOneCount59 == 20 and pageOneRows59[10022] and pageOneRows59[10041]
            and not pageOneRows59[10001],
        "59: page one must contain 20 installed L elements ahead of nearer M elements")
    local pinnedDistance59, pinnedShield59, pinnedHull59, largeRow59
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if entry.row == "surface_pinned" and entry.column == 3 then pinnedDistance59 = entry.text end
        if entry.row == "surface_pinned" and entry.column == 5 then pinnedShield59 = entry.text end
        if entry.row == "surface_pinned_hull" and entry.column == 5 then pinnedHull59 = entry.text end
        if tostring(entry.row) == "10022" and entry.column == 1 then largeRow59 = entry.text end
    end
    assert(type(pinnedDistance59) == "function" and pinnedDistance59() == "0.0 km",
        "59: pinned distance must be function-backed and initialized with the pinned solution")
    assert(type(pinnedShield59) == "function" and type(pinnedHull59) == "function",
        "59: both pinned health rows must be function-backed for in-place element-frame updates")
    assert(pinnedShield59() == ReadText(20991, 98) .. " -"
            and pinnedHull59() == ReadText(20991, 99) .. " 73%",
        "59: zero shield capacity and hull percent must display on separate pinned rows")
    shieldCapacity59, shieldPercent59, hullPercent59 = 100, 0, 41
    assert(pinnedShield59() == ReadText(20991, 98) .. " 0%"
            and pinnedHull59() == ReadText(20991, 99) .. " 41%",
        "59: shielded component at zero must display Shield 0% above its exact hull percent")
    assert(largeRow59 == "Surface 10022",
        "59: surface rows must display only the engine-provided equipment name")
    local pinnedRepaintMark59 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult",
        "x4gce3:" .. nonceByTarget59["10000"] .. ":10000:1:2:2")
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete",
        "x4gce2c:" .. nonceByTarget59["10000"] .. ":1:1")
    assert(fix.callbackCheckpoint() == pinnedRepaintMark59 + 1,
        "59: pinned result must schedule one isolated element-frame update")
    fix.drainCallbacksSince(pinnedRepaintMark59)
    local log59 = table.concat(fix.getCapturedLog(), "\n")
    assert(log59:find("event=surface_pinned action=refresh component=10000", 1, true)
            and log59:find("engageability_engageable=1 engageability_known=2 engageability_total=2 distance=0 shield_capacity=true shield_percent=0 hull_percent=41", 1, true),
        "59: pinned refresh audit must carry exact engageability, distance, and live health values")

    targetEvents59 = {}
    local nextPage59 = fix.buttonByText(ReadText(20991, 95))
    assert(nextPage59 and nextPage59.active, "59: Next Page must be active for 41 alternatives")
    nextPage59.handlers.onClick()
    assert(#targetEvents59 == 20, "59: opening page two must request only its 20 alternatives")
    local pageTwoRows59 = {}
    for _, entry in ipairs(fix.getCreatedTexts()) do
        local row = tonumber(tostring(entry.row))
        if row and row >= 10001 and row <= 10041 then pageTwoRows59[row] = true end
    end
    assert(pageTwoRows59[10001] and pageTwoRows59[10020]
            and not pageTwoRows59[10021] and not pageTwoRows59[10022],
        "59: page two must contain the first 20 medium slots after all large slots")

    local pageTwoDistance59, mediumFallbackRow59
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if tostring(entry.row) == "10001" and entry.column == 3 then pageTwoDistance59 = entry.text end
        if tostring(entry.row) == "10001" and entry.column == 1 then mediumFallbackRow59 = entry.text end
    end
    assert(pageTwoDistance59 == "1.0 km",
        "59: alternative distance must be captured alongside that page's engageability batch")
    assert(mediumFallbackRow59 == "Surface 10001",
        "59: medium surface rows must not append redundant type or size text")

    distanceOffset59 = 5000
    targetEvents59 = {}
    local previousPage59 = fix.buttonByText(ReadText(20991, 94))
    previousPage59.handlers.onClick()
    assert(#targetEvents59 == 0, "59: returning to cached page one must issue no solution requests")
    local cachedPageDistance59
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if tostring(entry.row) == "10022" and entry.column == 3 then cachedPageDistance59 = entry.text end
    end
    assert(cachedPageDistance59 == "22.0 km",
        "59: revisiting a cached page must retain the distance captured with its engageability batch")
    local autoRefresh59
    for _, checkbox in ipairs(fix.getCreatedCheckBoxes()) do
        if checkbox.row == "surface_auto_refresh" then autoRefresh59 = checkbox end
    end
    assert(autoRefresh59 and autoRefresh59.checked == false,
        "59: ten-second refresh must be visible and unchecked by default")
    autoRefresh59.handlers.onClick()
    assert(sess59.surfaceBrowser.autoRefresh == true,
        "59: clicking ten-second refresh must enable only session browser state")
    targetEvents59, nonceByTarget59 = {}, {}
    C.GetPlayerCurrentControlGroup = function() return "gunnercontrol" end
    C.GetPlayerOccupiedShipID = function() return sess59.shipID end
    clock = clock + 10
    gcMenu.onUpdate()
    assert(#targetEvents59 == 21,
        "59: automatic refresh must recalculate pinned plus current 20-row page only; got "
            .. tostring(#targetEvents59) .. " phase=" .. tostring(sess59.phase)
            .. " next=" .. tostring(sess59.surfaceBrowser.nextAutoRefreshAt)
            .. " now=" .. tostring(clock))
    local refreshedPinnedDistance59, refreshedPageDistance59
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if entry.row == "surface_pinned" and entry.column == 3 then refreshedPinnedDistance59 = entry.text end
        if tostring(entry.row) == "10022" and entry.column == 3 then refreshedPageDistance59 = entry.text end
    end
    assert(type(refreshedPinnedDistance59) == "function" and refreshedPinnedDistance59() == "5.0 km",
        "59: pinned distance must refresh on the same one-second tick as its engageability")
    assert(refreshedPageDistance59 == "27.0 km",
        "59: automatic page refresh must recapture distance with the new 20-row solution batch")
    log59 = table.concat(fix.getCapturedLog(), "\n")
    assert(log59:find("event=surface_refresh action=fire reason=automatic root=10000 page=1", 1, true)
            and log59:find("event=surface_snapshot action=create reason=automatic root=10000", 1, true),
        "59: automatic refresh needs one firing record and one matching snapshot record")
    assert(log59:find('event=surface_page action=request generation=', 1, true)
            and log59:find('requested=20 selected_total=2 selected_signature="11001,11002"', 1, true),
        "59: page request audit must identify exact bounded membership and selected turrets")

    -- X4 keeps updating UI frames while the simulation is paused. A paused
    -- elapsed clock must not repeatedly satisfy the same pinned/automatic
    -- refresh deadline and recursively request another engageability batch.
    targetEvents59 = {}
    C.IsGamePaused = function() return true end
    clock = clock + 20
    gcMenu.onUpdate()
    assert(#targetEvents59 == 0,
        "59: paused UI updates must issue no pinned or automatic surface requests; got "
            .. tostring(#targetEvents59))
    C.IsGamePaused = function() return false end

    sess59.aimTargetID = 10001
    sess59.surfaceBrowser.pendingReason = "open"
    gcMenu.display()
    local parentHull59
    for _, button in ipairs(fix.getCreatedButtons()) do
        if button.row == "surface_parent_hull" then parentHull59 = button end
    end
    assert(parentHull59 and parentHull59.text == ReadText(20991, 58),
        "59: a pinned surface must retain a direct parent-hull action")
    AddUITriggeredEvent = savedAdd59
end

-- ── 60. station surfaces resolve size from the exact installed module slot ─
do
    local sess60 = API.getSession()
    sess60.phase, sess60.controlMode = "engaged", "direct"
    sess60.targetObjectID, sess60.aimTargetID = 12000, 12000
    sess60.surfaceTypeFilter, sess60.surfaceMacroFilter = "any", "any"
    sess60.surfaceBrowser = X4GunneryState.newSurfaceBrowser(nil)
    C.IsComponentClass = function(component, class)
        return class == "station" and tonumber(tostring(component)) == 12000
    end
    C.GetNumStationModules = function() return 1 end
    C.GetStationModules = function(result)
        result[0] = 12001
        return 1
    end
    C.GetNumUpgradeSlots = function(destructible, _, upgrade)
        if tonumber(tostring(destructible)) ~= 12001 then return 0 end
        if upgrade == "turret" then return 2 end
        if upgrade == "shield" then return 1 end
        return 0
    end
    C.GetUpgradeSlotCurrentComponent = function(_, upgrade, slot)
        if upgrade == "turret" then return 12001 + slot end
        return 12004
    end
    local installedMacroCalls60 = {}
    C.GetUpgradeSlotCurrentMacro = function(object, module, upgrade, slot)
        installedMacroCalls60[#installedMacroCalls60 + 1] = {
            object = tonumber(tostring(object)), module = tonumber(tostring(module)),
            upgrade = upgrade, slot = slot,
        }
        if upgrade == "shield" then return "shield_xen_l_standard_01_mk2_macro" end
        return slot == 1 and "turret_xen_l_laser_01_mk1_macro"
            or "turret_xen_m_laser_02_mk1_macro"
    end
    C.IsComponentOperational = function() return true end
    C.GetComponentName = function(component)
        return ({ [12002] = "XEN L Graviton Turret Mk1",
            [12003] = "XEN M Impulse Turret Mk1",
            [12004] = "XEN L Shield Generator Mk2" })[tonumber(tostring(component))] or "Station"
    end
    C.GetDistanceBetween = function() return 30000 end
    GetMacroData = function(macro, key)
        if key == "name" then return ({
            turret_xen_l_laser_01_mk1_macro = "XEN L Graviton Turret Mk1",
            turret_xen_m_laser_02_mk1_macro = "XEN M Impulse Turret Mk1",
            shield_xen_l_standard_01_mk2_macro = "XEN L Shield Generator Mk2",
        })[macro] or "" end
        return ""
    end
    GetComponentData = function(_, ...)
        local values = {}
        for _, key in ipairs({...}) do
            if key == "shieldmax" or key == "shieldpercent" then values[#values + 1] = 0
            elseif key == "hullpercent" then values[#values + 1] = 100
            else values[#values + 1] = false end
        end
        return unpack(values)
    end
    gcMenu.display()
    assert(#installedMacroCalls60 == 3,
        "60: every station surface needs one exact installed-equipment lookup")
    for _, call in ipairs(installedMacroCalls60) do
        assert(call.object == 12000 and call.module == 12001,
            "60: station equipment macro lookup must identify root station and exact module")
    end
    local stationSurfaceLabels60, stationSurfaceOrder60 = {}, {}
    for _, entry in ipairs(fix.getCreatedTexts()) do
        local row = tostring(entry.row)
        if (row == "12002" or row == "12003" or row == "12004") and entry.column == 1 then
            stationSurfaceLabels60[row] = entry.text
            stationSurfaceOrder60[#stationSurfaceOrder60 + 1] = row
        end
    end
    assert(table.concat(stationSurfaceOrder60, ",") == "12002,12004,12003",
        "60: installed sizes must sort L turret, L shield, then M turret")
    assert(stationSurfaceLabels60["12002"] == "XEN L Graviton Turret Mk1"
            and stationSurfaceLabels60["12003"] == "XEN M Impulse Turret Mk1"
            and stationSurfaceLabels60["12004"] == "XEN L Shield Generator Mk2",
        "60: station rows must contain only engine-provided equipment names")
end

print("runtime targeting tests passed")
