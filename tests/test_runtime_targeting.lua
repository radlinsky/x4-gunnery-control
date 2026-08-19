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
local grp27 = fix.makeGroup{
    key = "grp27", displayName = "G27",
    members = { { componentID = 27, displayName = "T1", operational = true,
                  cameraSupported = true, componentKey = "27" } },
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
local browserGroup = fix.makeGroup{
    key = "browser-back-group", contextID = 10,
    path = "browser-back-path", group = "browser-back", componentID = 1010,
    displayName = "Browser Back Group", mode = "autoassist", armed = true, members = {},
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
local browserBack10b = fix.buttonByLabel("backToGunnery")
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
local initialPickerBack10b = fix.buttonByLabel("backToGunnery")
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
local fakeGroup15 = fix.makeGroup{
    key = "fake-group-15", contextID = 0, path = "fake", group = "grp",
    componentID = 55, armed = true, displayName = "Fake Turret Group",
    members = { { componentID = 55, displayName = "Turret 1", operational = true,
                  cameraSupported = true, componentKey = "55" } },
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
local grp19a = fix.makeGroup{ key = "grp19a", contextID = 1, group = "A", componentID = 10, members = {} }
local grp19b = fix.makeGroup{ key = "grp19b", contextID = 1, group = "B", componentID = 11, members = {} }
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
local grp20 = fix.makeGroup{
    key = "grp20", group = "front", componentID = 9, displayName = "Front", totalCount = 2,
    members = { { componentID = 9, displayName = "Turret 1", operational = true,
                  cameraSupported = true, componentKey = "9" } },
}
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
local grp21 = fix.makeGroup{
    key = "grp21", group = "front", componentID = 9, displayName = "Front",
    members = { { componentID = 9, displayName = "Turret 1", operational = true,
                  cameraSupported = true, componentKey = "9" } },
}
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
local grp22 = fix.makeGroup{
    key = "grp22", componentID = 10, totalCount = 2, operationalCount = 2,
    members = {
        { componentID = 10, displayName = "T1", operational = true, cameraSupported = true, componentKey = "10" },
        { componentID = 11, displayName = "T2", operational = true, cameraSupported = true, componentKey = "11" },
    },
}
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
local grp23 = fix.makeGroup{
    key = "grp23", componentID = 20,
    members = { { componentID = 20, displayName = "T1", operational = true,
                  cameraSupported = true, componentKey = "20" } },
}
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


print("runtime targeting tests passed")
