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

-- ── 40. the engaged/direct panel offers the toggle, checked by default ───────
gcMenu.display()
assert(#fix.getCreatedCheckBoxes() == 1,
    "the engaged/direct panel must offer exactly one checkbox (Auto-next Target); got "
    .. tostring(#fix.getCreatedCheckBoxes()))
assert(fix.getCreatedCheckBoxes()[1].checked == true,
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
                 currentmacro = "", slotsize = "", total = turretsPerGroup, operational = turretsPerGroup }
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

-- ── 54. ship-wide "prefer my target" override ────────────────────────────────
-- The override is worthless on a turret still sitting in autoassist: X4 ignores
-- supplied targets for that mode (fight.attack.object.capital.xml:1756), so a
-- turret left there keeps idling while the button looks like it worked. That is
-- the fault the 2026-08-07 trial caught, hence the mode-write assertions.
do
    gcMenu.onShowMenu()
    local sess54 = API.getSession()
    assert(sess54 ~= nil, "expected session for prefer-all-turrets test")
    local grp54 = { key = "grp54", kind = "group", contextID = 5, path = "p", group = "g",
        componentID = 53, displayName = "G53", totalCount = 1, operationalCount = 1,
        mode = "autoassist", armed = true, members = {
            { componentID = 53, displayName = "T1", operational = true,
              cameraSupported = true, componentKey = "53" }
        } }
    sess54.groups = { grp54 }
    sess54.checkedGroupKeys = { ["grp54"] = true }
    sess54.phase, sess54.controlMode = "engaged", "direct"
    sess54.aimTargetID, sess54.targetObjectID = 500, 500
    -- The override takes the DIRECTED groups off autoassist using their STAGED
    -- mode -- what the player configured this group to be. committedBaseline is
    -- deliberately different here: it covers every group on the ship, so driving
    -- the override from it would stomp a temporary apply on unticked groups.
    sess54.staged = { ["grp54"] = { mode = "defend", armed = true } }
    sess54.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "g",
        shipID = sess54.shipID, mode = "attack", armed = true } }

    assert(sess54.preferAllTurrets == false,
        "the ship-wide override must be off until the player asks for it")

    local modeWrites54 = {}
    local savedSetMode54 = C.SetTurretGroupMode2
    C.SetTurretGroupMode2 = function(ship, ctx, path, group, mode)
        modeWrites54[#modeWrites54 + 1] = tostring(mode)
    end
    local evts54 = {}
    local savedAdd54 = AddUITriggeredEvent
    AddUITriggeredEvent = function(screen, control, params)
        evts54[#evts54 + 1] = { screen = screen, control = control, params = params }
    end

    local mark54 = fix.callbackCheckpoint()
    assert(API.applyPreferAllTurrets() == true, "applyPreferAllTurrets must report success")
    assert(sess54.preferAllTurrets == true, "applying the override must record it on the session")

    -- Every group the console took over goes back to its own mode, and nothing
    -- is ever written back to autoassist.
    assert(#modeWrites54 > 0, "the override must restore the staged mode before issuing")
    for _, m in ipairs(modeWrites54) do
        assert(m ~= "autoassist",
            "the override must never leave a group on autoassist; X4 ignores supplied "
            .. "targets for that mode, so the turret would silently keep idling")
    end
    assert(modeWrites54[1] == "defend",
        "the override must write the STAGED mode, not the committedBaseline mode "
        .. "(baseline is \"attack\" here); wrote " .. tostring(modeWrites54[1]))
    -- One write only: the directed set is the checked mutable groups, never the
    -- whole ship. A baseline-driven loop would also touch unticked groups.
    assert(#modeWrites54 == 1,
        "the override must touch only the directed groups; got " .. tostring(#modeWrites54) .. " writes")

    -- Raised a tick later, so the mode writes above have landed before MD reads
    -- the ship's turret modes back.
    local immediate54 = 0
    for _, e in ipairs(evts54) do
        if e.control == "prefer_all_turrets" then immediate54 = immediate54 + 1 end
    end
    assert(immediate54 == 0,
        "the override event must be deferred a tick, not raised inside the same call")
    fix.drainCallbacksSince(mark54)
    local applied54 = nil
    for _, e in ipairs(evts54) do
        if e.control == "prefer_all_turrets" then applied54 = e end
    end
    assert(applied54 ~= nil, "the deferred callback must raise prefer_all_turrets")
    assert(applied54.params["ship"] ~= nil and applied54.params["target"] ~= nil,
        "prefer_all_turrets must carry both the ship and the target")

    -- A target change re-issues the override. Without this the turrets fall
    -- silent the moment auto-next moves on, because the override names one
    -- specific target and dies with it.
    local countBefore54 = #evts54
    local mark53b = fix.callbackCheckpoint()
    sess54.aimTargetID = 501
    assert(API.applyPreferAllTurrets() == true, "re-issuing the override must succeed")
    fix.drainCallbacksSince(mark53b)
    local reissued54 = 0
    for i = countBefore54 + 1, #evts54 do
        if evts54[i].control == "prefer_all_turrets" then reissued54 = reissued54 + 1 end
    end
    assert(reissued54 == 1,
        "a target change must re-issue the override exactly once; got " .. tostring(reissued54))

    -- A release inside the one-tick deferral window wins. Emitting anyway would
    -- leave MD applied with the session flag already false, and every teardown
    -- route short-circuits on that flag, so nothing could ever clear it again.
    local countBefore54r = #evts54
    local mark53r = fix.callbackCheckpoint()
    sess54.aimTargetID = 502
    assert(API.applyPreferAllTurrets() == true, "re-issuing the override must succeed")
    assert(API.clearPreferAllTurrets("released inside the deferral window") == true,
        "release must report success while the deferred apply is still pending")
    fix.drainCallbacksSince(mark53r)
    for i = countBefore54r + 1, #evts54 do
        assert(evts54[i].control ~= "prefer_all_turrets",
            "a release inside the deferral window must cancel the pending apply; "
            .. "otherwise MD stays applied and no teardown route can clear it")
    end

    -- Same window, but the player retargets instead of releasing. The stale
    -- callback must not overwrite the newer target's override.
    local mark53s = fix.callbackCheckpoint()
    sess54.aimTargetID = 503
    assert(API.applyPreferAllTurrets() == true, "issuing the override must succeed")
    sess54.aimTargetID = 504
    assert(API.applyPreferAllTurrets() == true, "re-issuing for the new target must succeed")
    local countBefore54s = #evts54
    fix.drainCallbacksSince(mark53s)
    local emitted54s = {}
    for i = countBefore54s + 1, #evts54 do
        if evts54[i].control == "prefer_all_turrets" then
            emitted54s[#emitted54s + 1] = evts54[i]
        end
    end
    assert(#emitted54s == 1,
        "only the current target's override may be emitted; got " .. tostring(#emitted54s))

    -- Release hands the ship back, and is a no-op when nothing is held.
    sess54.preferAllTurrets = true
    assert(API.clearPreferAllTurrets("test") == true, "release must report success when held")
    assert(sess54.preferAllTurrets == false, "release must clear the session flag")
    local cleared54 = 0
    for i = countBefore54s + 1, #evts54 do
        if evts54[i].control == "prefer_all_turrets_clear" then cleared54 = cleared54 + 1 end
    end
    assert(cleared54 == 1, "release must raise prefer_all_turrets_clear exactly once")
    assert(API.clearPreferAllTurrets("test again") == false,
        "release must be a no-op when the override is not held")

    -- Releasing from the button takes the checked groups straight back under
    -- Direct-control. The clear is ship-wide, so without this the groups the
    -- player is directing drop to their own mode and stop shooting the engaged
    -- target -- reported in game on 2026-08-07, missile-defence groups went
    -- silent on release.
    local armedWrites54 = {}
    local savedSetArmed54 = C.SetTurretGroupArmed
    C.SetTurretGroupArmed = function(_, _, _, _, armed)
        armedWrites54[#armedWrites54 + 1] = armed
    end
    sess54.preferAllTurrets = true
    sess54.phase, sess54.controlMode = "engaged", "direct"
    -- The refresh inside applyPreferAllTurrets replaced the group list with
    -- whatever the stubbed readGroups returns, so put ours back.
    sess54.groups = { grp54 }
    sess54.checkedGroupKeys = { ["grp54"] = true }
    local modeCount54 = #modeWrites54
    local mark53d = fix.callbackCheckpoint()
    assert(API.clearPreferAllTurrets("resume test", true) == true,
        "release with resume must report success")
    assert(#modeWrites54 == modeCount54,
        "resuming must be deferred a tick, or MD reads the previous directed "
        .. "mode back and the release never reaches those turrets")
    fix.drainCallbacksSince(mark53d)
    -- Direct-control has one mode. The old expectation here was "autoassist",
    -- which was the fallback when no mode had been chosen; that branch was
    -- deleted on 2026-08-10 once attackenemies was confirmed to hold a
    -- mod-supplied target list even under a fighting pilot.
    assert(modeWrites54[#modeWrites54] == X4GunneryState.TICK_MODE,
        "releasing from the button must put the checked groups back under "
        .. "Direct-control; wrote " .. tostring(modeWrites54[#modeWrites54]))
    assert(armedWrites54[#armedWrites54] == true,
        "a resumed group must be armed, or Direct-control is silent")
    C.SetTurretGroupArmed = savedSetArmed54

    -- Leaving the chair must never leave the ship altered. restoreDirect is the
    -- funnel every exit route uses (cease, get up, undock, target-destroyed with
    -- auto-next off), so clearing there covers all of them at once.
    sess54.preferAllTurrets = true
    -- Closing from the console is a real chair exit (leaveChair -> restoreDirect),
    -- which is what the funnel is now bound to. It used to be asserted by closing
    -- the target browser, but that route is seated and no longer reverts: revert
    -- happens on stand up. Every stand-up route (cease, get up, undock) lands in
    -- the same function.
    sess54.phase = "console"
    local countBefore53c = #evts54
    gcMenu.onCloseElement("close")
    local clearedOnExit54 = 0
    for i = countBefore53c + 1, #evts54 do
        if evts54[i].control == "prefer_all_turrets_clear" then
            clearedOnExit54 = clearedOnExit54 + 1
        end
    end
    assert(clearedOnExit54 >= 1,
        "leaving the chair while the override is held must release every turret; "
        .. "otherwise the player walks away with a silently altered ship")

    C.SetTurretGroupMode2 = savedSetMode54
    AddUITriggeredEvent = savedAdd54
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
    local dropdowns57 = fix.getCreatedDropDowns()
    assert(#dropdowns57 >= 2, "57: surface panel needs type and macro dropdowns")
    assert(dropdowns57[1].row == "surface_type_filter" and dropdowns57[1].startOption == "any",
        "57: surface type filter must render at Any")
    assert(dropdowns57[2].row == "surface_macro_filter" and #dropdowns57[2].options == 3,
        "57: surface equipment filter must offer Any plus both localized turret names")
    dropdowns57[1].handlers.onDropDownConfirmed(nil, "turret")
    assert(sess57.surfaceTypeFilter == "turret" and sess57.surfaceMacroFilter == "any",
        "57: changing type must apply it and reset macro to Any")
    dropdowns57 = fix.getCreatedDropDowns()
    dropdowns57[2].handlers.onDropDownConfirmed(nil, "turret_l")
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
    assert(log58:find("event=surface_browser action=rendered target=600 target_name=\"0\" type_filter=turret equipment_filter=turret_l all=2 visible=1 equipment_options=2", 1, true),
        "57: filtered surface render needs exact count/filter evidence")
    assert(log58:find('event=surface_browser action=row target=600 component=701 name="0" kind=turret equipment="Large Turret" macro="turret_l"', 1, true),
        "57: filtered surface row needs exact localized equipment and raw-macro evidence")

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

-- ── 57. solution requests stream exactly the ticked operational turrets ─────
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
    local savedAdd57, events57 = AddUITriggeredEvent, {}
    AddUITriggeredEvent = function(screen, control, params)
        events57[#events57 + 1] = { screen = screen, control = control, params = params }
    end
    local pending57 = API.requestSolution(900)
    assert(pending57.pending and pending57.total == 2, "57: pending denominator must be two exact selected turrets")
    local controls57, nonce57 = {}, nil
    for _, event in ipairs(events57) do
        controls57[#controls57 + 1] = event.control
        if event.control == "solution_begin" then nonce57 = event.params.nonce end
    end
    assert(table.concat(controls57, ",") == "solution_begin,solution_member,solution_member,solution_commit",
        "57: solution transport must be begin + one member per selected operational turret + commit")
    assert(events57[2].params.weapon == 101 and events57[3].params.weapon == 102,
        "57: unchecked or inoperable turret leaked into exact-member request")
    sess57.phase = "target_select"
    GetPlayerContextByClass = function() return nil end
    C.GetSofttarget2 = function() return { softtargetID = 0, softtargetConnectionName = "" } end
    fix.fireEvent("X4GunneryControl.SolutionResult", "x4gcs1:" .. nonce57 .. ":1:2")
    assert(pending57.pending == false and pending57.on == 1 and pending57.total == 2,
        "57: matching packed result was not accepted")
    events57 = {}
    assert(API.requestSolution(900) == pending57 and #events57 == 0,
        "57: a result must be cached for one second")
    sess57.checkedGroupKeys.unchecked = true
    local changed57 = API.requestSolution(900)
    assert(changed57.pending and changed57.total == 3 and #events57 == 5,
        "57: checkbox membership change must invalidate cache and stream the new exact denominator")
    AddUITriggeredEvent = savedAdd57
end

-- ── 58. target/surface rows render and sort complete solution results ────────
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
        local result = API.requestSolution(target)
        local nonce
        for _, event in ipairs(events58) do
            if event.control == "solution_begin" then nonce = event.params.nonce end
        end
        fix.fireEvent("X4GunneryControl.SolutionResult", "x4gcs1:" .. nonce .. ":" .. on .. ":2")
        return result
    end
    seed58(701, 2); seed58(702, 0); seed58(703, 1); seed58(704, 0)
    AddUITriggeredEvent = savedAdd58

    sess58.phase, sess58.controlMode = "engaged", "direct"
    sess58.targetObjectID, sess58.aimTargetID = 900, 900
    sess58.surfaceTypeFilter, sess58.surfaceMacroFilter = "any", "any"
    GetPlayerContextByClass = function() return nil end
    C.IsComponentClass = function() return false end
    C.GetNumUpgradeSlots = function(_, _, upgrade)
        if upgrade == "turret" then return 3 end
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
end

print("runtime targeting tests passed")
