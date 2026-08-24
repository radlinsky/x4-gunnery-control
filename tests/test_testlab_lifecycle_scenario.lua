-- test_testlab_lifecycle_scenario.lua
-- Test Lab scenario spec transport, preflight guards, creation/acknowledgement
-- lifecycle, timeout, despawn, malformed spec rejection, and shipped spec integrity.

local function loadHarness(spec, realTime)
    -- This file builds several isolated runtimes in one Lua process. require()
    -- otherwise retains the first fixture's ffi table, so later C write spies
    -- would observe a different table from gunnery_control.lua.
    package.loaded["ffi"] = nil
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    GetCurRealTime = function() return realTime or 0 end
    local handoffs, plainCloses = {}, {}
    local reentered = false

    -- testlab.lua uses clearMenu(), while the production runtime fixture models
    -- live frame rebuilds through clearDataForRefresh(). They are equivalent for
    -- this focused menu-ownership test.
    Helper.clearMenu = function(menu)
        Helper.clearDataForRefresh(menu)
        if menu then menu.frames = {} end
    end
    Helper.getMenu = function(name)
        for _, candidate in ipairs(Menus or {}) do
            if candidate.name == name then return candidate end
        end
    end
    Helper.closeMenu = function(from, reason)
        plainCloses[#plainCloses + 1] = { from = from, reason = reason }
    end
    Helper.closeMenuAndOpenNewMenu = function(from, destination, params, keepHUD)
        handoffs[#handoffs + 1] = {
            from = from, destination = destination, params = params, keepHUD = keepHUD,
        }
        -- Model a Helper implementation which reports the source close while
        -- processing the transition. The Test Lab must not request a second
        -- reopen from this re-entrant callback.
        if from and from.name == "X4GunneryTestLab" and not reentered then
            reentered = true
            from.onCloseElement("close")
        end
    end

    X4GunneryTestLabState = nil
    dofile("testlab/x4_gunnery_control_testlab/ui/testlab_state.lua")
    -- X4 loads ui.xml <file> entries in order, so the spec global is already
    -- published by the time testlab.lua runs. `spec` defaults to the shipped
    -- file so the ordinary lifecycle cases exercise the real load path.
    if spec == nil then
        dofile("testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua")
    else
        X4GunneryTestLabScenarioSpec = spec ~= "absent" and spec or nil
    end
    local ok, err = pcall(dofile, "testlab/x4_gunnery_control_testlab/ui/testlab.lua")
    assert(ok, "testlab.lua failed to load: " .. tostring(err))

    local testMenu
    for _, candidate in ipairs(Menus) do
        if candidate.name == "X4GunneryTestLab" then testMenu = candidate; break end
    end
    assert(testMenu, "X4GunneryTestLab was not registered")

    -- Keep one camera-capable group stable across the Gunnery close/reopen and
    -- model the actual directed state separately from its saved Direct snapshot.
    local groupBuffer = { [0] = { path = "p", group = "g", contextid = 5 } }
    local groupMode, groupArmed = "attack", false
    local modeWrites, armedWrites = 0, 0
    fix.ffiStub.new = function() return groupBuffer end
    fix.C.GetNumUpgradeGroups = function() return 1 end
    fix.C.GetUpgradeGroups2 = function() return 1 end
    fix.C.GetUpgradeGroupInfo2 = function()
        return {
            count = 1, currentcomponent = 27, currentmacro = "", slotsize = "",
            total = 1, operational = 1,
        }
    end
    fix.C.GetNumUpgradeSlots = function() return 1 end
    fix.C.GetUpgradeSlotCurrentComponent = function() return 27 end
    fix.C.GetUpgradeSlotGroup = function() return { path = "p", group = "g" } end
    fix.C.GetTurretGroupMode2 = function() return groupMode end
    fix.C.IsTurretGroupArmed = function() return groupArmed end
    fix.C.SetTurretGroupMode2 = function(_, _, _, _, value)
        modeWrites = modeWrites + 1
        groupMode = value
    end
    fix.C.SetTurretGroupArmed = function(_, _, _, _, value)
        armedWrites = armedWrites + 1
        groupArmed = value
    end
    fix.C.IsComponentOperational = function() return true end
    fix.C.IsPlayerCameraTargetViewPossible = function() return true end
    fix.C.GetComponentName = function() return "Test Ship" end
    GetComponentData = function(_, field)
        if field == "macro" then return "test_ship_macro" end
        if field == "isplayerowned" then return true end
        return nil
    end

    local function countHandoffs(fromName, destination)
        local count = 0
        for _, call in ipairs(handoffs) do
            if call.from and call.from.name == fromName and call.destination == destination then
                count = count + 1
            end
        end
        return count
    end

    local function openFromGunnery(spec)
        local phase = spec.phase
        fix.gcMenu.onShowMenu()
        local session = fix.API.getSession()
        assert(session, "expected a Gunnery session before opening Test Lab")
        session.checkedGroupKeys = { [X4GunneryState.groupKey(5, "p", "g")] = true }
        session.phase = phase
        if phase ~= "console" then
            session.controlMode = spec.controlMode
            session.cameraMemberID = 27
        end
        if spec.direct then
            session.committedBaseline = { {
                shipID = session.shipID, kind = "group", contextID = 5,
                path = "p", group = "g", mode = "attack", armed = false,
            } }
            -- Direct owns the group as autoassist/armed while the baseline
            -- retains the exact settings that later teardown must restore.
            groupMode, groupArmed = "autoassist", true
        end
        fix.gcMenu.display()
        local button = fix.buttonByText(ReadText(20991, 32))
        assert(button and button.handlers.onClick,
            spec.label .. " must expose the Test Lab button")
        button.handlers.onClick()
        assert(countHandoffs("X4GunneryMenu", "X4GunneryTestLab") == 1,
            "opening Test Lab must request exactly one main-to-lab handoff")
        assert(session.lifecycle == X4GunneryState.lifecycle.reopening,
            "opening Test Lab must park the session in reopening lifecycle")
        testMenu.onShowMenu()
        return session
    end

    return {
        fix = fix,
        testMenu = testMenu,
        handoffs = handoffs,
        plainCloses = plainCloses,
        countHandoffs = countHandoffs,
        openFromGunnery = openFromGunnery,
        getWrites = function() return { mode = modeWrites, armed = armedWrites } end,
    }
end

-- Scenario spec transport. The spec is replayed on every UI load as a flat
-- begin/group.../commit stream, because MD cannot be handed a nested table.
local function scenarioEvents(harness)
    local events = {}
    for _, event in ipairs(harness.fix.uiTriggeredEvents) do
        if event.screen == "X4GunneryTestLabScenario" then events[#events + 1] = event end
    end
    return events
end

-- Repair guards are acknowledged independently from HOLD FIRE. A fixture that
-- is safe but not actually registered for post-hit repair must not start a
-- destructive attribution run.
do
    local harness = loadHarness({
        id = "repair-guard-ready", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = {
            { label = "Repaired target", macro = "target_macro", faction = "xenon",
              count = 1, distance = 3000, behaviour = "wait", hostile = true,
              holdFire = true, stripDefenceUnits = true, repairGuard = true },
        },
        stations = {},
    })
    harness.openFromGunnery({ label = "console", phase = "console" })
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local requestId = scenarioEvents(harness)[1].params.requestId
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct6:" .. requestId .. ":repair-guard-ready:1:0:0:0:0:0:0:1:15:0:0:1:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1,
        "an exact repair-guard census must complete scenario setup")
    assert(harness.fix.logContains("repair_fixtures=1"),
        "READY must record the correlated repair-guard fixture count")
end

do
    local harness = loadHarness({
        id = "repair-guard-missing", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = {
            { label = "Repaired target", macro = "target_macro", faction = "xenon",
              count = 1, distance = 3000, behaviour = "wait", hostile = true,
              holdFire = true, stripDefenceUnits = true, repairGuard = true },
        },
        stations = {},
    })
    harness.openFromGunnery({ label = "console", phase = "console" })
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local requestId = scenarioEvents(harness)[1].params.requestId
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct6:" .. requestId .. ":repair-guard-missing:1:0:0:0:0:0:0:1:15:0:0:1:0")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "a missing repair guard must keep Test Lab open")
    assert(harness.fix.logContains("expected_repair_fixtures=1")
            and harness.fix.logContains("repair_fixtures=0"),
        "repair-guard failure must log expected and actual counts")
end

-- x/y bearing offsets: when set they are forwarded as scalars; when omitted
-- they default to 0.  Both cases must still produce a flat (non-nested) payload.
do
    -- With x and y explicitly set.
    local harness = loadHarness({
        id = "bearing-explicit",
        enabled = true,
        groups = {
            { macro = "ship_xen_s_fighter_01_a_macro", faction = "xenon",
              count = 1, distance = 3000, x = 1500, y = -800, behaviour = "wait" },
        },
    })
    local events = scenarioEvents(harness)
    assert(#events == 3, "bearing spec must fire begin + 1 group + commit; got " .. #events)
    assert(events[2].params.x == 1500 and events[2].params.y == -800,
        "explicit x/y must be forwarded in the group payload")
    assert(type(events[2].params.x) == "number" and type(events[2].params.y) == "number",
        "x and y must be numbers in the payload")
end
do
    -- With x and y omitted: must default to 0, not nil.
    local harness = loadHarness({
        id = "bearing-omitted",
        enabled = true,
        groups = {
            { macro = "ship_xen_s_fighter_01_a_macro", faction = "xenon",
              count = 1, distance = 3000, behaviour = "wait" },
        },
    })
    local events = scenarioEvents(harness)
    assert(#events == 3, "omitted-bearing spec must fire begin + 1 group + commit; got " .. #events)
    assert(events[2].params.x == 0 and events[2].params.y == 0,
        "omitted x/y must default to 0 in the group payload")
end

-- A remote setup is bootstrapped from an arbitrary safe gunnery ship. Creation
-- is acknowledged only after MD reports the exact spawned shooter, mixed
-- missile-turret loadout, ammunition, and absolute-placement census.
do
    local harness = loadHarness({
        id = "remote-odysseus", enabled = false,
        location = {
            sectorMacro = "Cluster_14_Sector001_macro",
            x = 500000, y = 0, z = 0,
        },
        setup = {
            remote = true,
            shipMacro = "ship_par_l_destroyer_02_a_macro",
            shipLabel = "Remote Odysseus 1",
            turretGroup = "all_missile_turrets", turretLabel = "All Missile Turrets",
            -- The harness models one operational turret; the MD census below
            -- still proves the fixture contract's full 16-turret payload.
            expectedTurrets = 1, selectAll = true,
        },
        groups = {
            { label = "Remote Odysseus", macro = "ship_par_l_destroyer_02_a_macro",
              faction = "player", count = 1, distance = 0, x = 0, y = 0, yaw = 0,
              behaviour = "wait", role = "shooter",
              loadout = "issue65_odysseus_mixed_missiles",
              expectedMissileTurrets = 16, expectedGuided = 9,
              expectedDumbfire = 7, expectedAmmo = 160 },
        },
        stations = {},
    })
    harness.openFromGunnery({ label = "arbitrary safe launcher", phase = "console" })
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local events = scenarioEvents(harness)
    assert(#events == 3, "remote Create must stream begin + shooter + commit")
    assert(events[1].params.sectorMacro == "Cluster_14_Sector001_macro"
            and events[1].params.anchorX == 500000
            and events[1].params.anchorY == 0 and events[1].params.anchorZ == 0,
        "remote begin must carry the exact flat sector anchor")
    assert(events[2].params.role == "shooter"
            and events[2].params.loadout == "issue65_odysseus_mixed_missiles"
            and events[2].params.expectedMissileTurrets == 16
            and events[2].params.expectedGuided == 9
            and events[2].params.expectedDumbfire == 7
            and events[2].params.expectedAmmo == 160,
        "remote shooter event must carry the exact flat readiness census")
    local requestId = events[1].params.requestId
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct7:" .. requestId .. ":remote-odysseus:1:0:0:0:0:0:0:0:0:0:0:0:0:1:16:9:7:160:0:0")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1,
        "an exact remote census must return to the safe launcher for teleport")
    assert(harness.fix.logContains("action=remote_ready")
            and harness.fix.logContains("missile_turrets=16")
            and harness.fix.logContains("guided=9")
            and harness.fix.logContains("dumbfire=7")
            and harness.fix.logContains("ammo=160"),
        "remote READY must log the verified shooter loadout")

    -- READY returned to the safe launcher for teleport. Reopening Test Lab
    -- there must not expose a destructive second Create while the remote
    -- fixture is waiting.
    harness.testMenu.onShowMenu()
    local createWhileWaiting = harness.fix.buttonByText(ReadText(20992, 25))
    local despawnWhileSafe = harness.fix.buttonByText(ReadText(20992, 26))
    assert(createWhileWaiting and createWhileWaiting.active == false,
        "Create must be disabled while a remote fixture waits for teleport")
    assert(despawnWhileSafe and despawnWhileSafe.active == true,
        "Despawn must remain available from the safe launcher")
    local staleSafeDespawnHandler = despawnWhileSafe.handlers.onClick
    local eventCountBeforeRejectedCreate = #scenarioEvents(harness)
    createWhileWaiting.handlers.onClick()
    assert(#scenarioEvents(harness) == eventCountBeforeRejectedCreate
            and harness.fix.logContains("reason=remote_fixture_already_active"),
        "a stale handler must reject second Create while teleport is pending")

    GetComponentData = function(_, field)
        if field == "macro" then return "ship_par_l_destroyer_02_a_macro" end
        if field == "isplayerowned" then return true end
        return nil
    end
    harness.fix.C.GetComponentName = function() return "Remote Odysseus 1" end
    harness.fix.gcMenu.onShowMenu()
    harness.fix.gcMenu.display()
    harness.fix.buttonByText(ReadText(20991, 32)).handlers.onClick()
    harness.testMenu.onShowMenu()
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 2,
        "opening Test Lab on the teleported shooter must auto-arm and return")
    assert(harness.fix.logContains("event=scenario_activate")
            and harness.fix.logContains("action=ready"),
        "post-teleport activation must log the exact group setup")

    -- Opening Test Lab after activation is legal for diagnostics, but Create
    -- must remain disabled and its handler must refuse to replace the occupied
    -- shooter. This exact operator mistake despawned the player context and
    -- crashed X4 in the 2026-08-23 live run.
    harness.testMenu.onShowMenu()
    local createAboardShooter = harness.fix.buttonByText(ReadText(20992, 25))
    local despawnAboardShooter = harness.fix.buttonByText(ReadText(20992, 26))
    assert(createAboardShooter and createAboardShooter.active == false,
        "Create must be disabled aboard the exact remote shooter")
    assert(despawnAboardShooter and despawnAboardShooter.active == false,
        "Despawn must be disabled aboard the exact remote shooter")
    eventCountBeforeRejectedCreate = #scenarioEvents(harness)
    createAboardShooter.handlers.onClick()
    assert(#scenarioEvents(harness) == eventCountBeforeRejectedCreate
            and harness.fix.logContains("ship_id="),
        "a stale handler must reject second Create aboard the remote shooter")
    despawnAboardShooter.handlers.onClick()
    staleSafeDespawnHandler()
    assert(#scenarioEvents(harness) == eventCountBeforeRejectedCreate
            and harness.fix.logContains("reason=occupied_remote_shooter"),
        "current and previously active Despawn handlers must re-check occupancy and send no event")
end

-- Issue #67 streams one exact mixed conventional shooter and two independent P
-- controls; the shooter arms BOTH equipped medium turret groups via selectAll.
-- READY v8 must carry the complete ordinary-emitter and geometry census, and
-- post-teleport activation must reject the right count with the wrong
-- multiset composition.
do
    local beam = "turret_arg_m_beam_02_mk1_macro"
    local plasma = "turret_arg_m_plasma_02_mk1_macro"
    local harness = loadHarness({
        id = "issue-67-contract", enabled = false,
        location = { sectorMacro = "Cluster_29_Sector001_macro", x = 500000, y = 0, z = 0 },
        setup = {
            remote = true, shipMacro = "ship_arg_l_destroyer_02_a_macro",
            shipLabel = "ISSUE ARC-BARREL BEHEMOTH E 1",
            turretGroup = "group_front_up_mid", turretLabel = "Front Upper Mid",
            selectAll = true, expectedTurrets = 4,
            expectedMacros = { beam, beam, plasma, plasma },
        },
        groups = {
            { label = "ISSUE ARC-BARREL BEHEMOTH E", macro = "ship_arg_l_destroyer_02_a_macro",
              faction = "player", count = 1, distance = 1, behaviour = "wait",
              role = "shooter", loadout = "issue67_behemoth_arc_barrel",
              expectedWeapons = 4, expectedTurrets = 4, expectedBeam = 2,
              expectedPlasma = 2 },
            { label = "A CLEAR IN-ARC BARREL CONTROL P", macro = "ship_xen_m_fighter_01_a_macro",
              faction = "xenon", count = 1, distance = 2201, behaviour = "wait",
              hostile = true, holdFire = true, repairGuard = true,
              geometryRole = "clear_arc" },
            { label = "C TRUE CANNOT BEAR CONTROL P", macro = "ship_xen_m_fighter_01_a_macro",
              faction = "xenon", count = 1, distance = 1801, behaviour = "wait",
              hostile = true, holdFire = true, repairGuard = true,
              geometryRole = "below_arc" },
        },
    })
    harness.openFromGunnery({ label = "safe launcher", phase = "console" })
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local events = scenarioEvents(harness)
    assert(#events == 5, "issue #67 Create must stream begin + 3 groups + commit")
    assert(events[2].params.loadout == "issue67_behemoth_arc_barrel"
            and events[2].params.expectedWeapons == 4
            and events[2].params.expectedTurrets == 4
            and events[2].params.expectedBeam == 2
            and events[2].params.expectedPlasma == 2,
        "issue #67 shooter payload must carry the exact conventional census")
    assert(events[3].params.geometryRole == "clear_arc"
            and events[4].params.geometryRole == "below_arc",
        "issue #67 P controls must carry independent geometry roles")

    -- x4gct8 field order (after the specId): ships, stations, modules,
    -- stationTurrets, stationMissileTurrets, stationShields, stationEngines,
    -- safeFixtures, safeWeapons, unsafeWeapons, defenceUnits, hostiles,
    -- repairFixtures, shooters, shooterMissileTurrets, guided, dumbfire, ammo,
    -- loadoutFailures, locationFailures, shooterWeapons, shooterTurrets,
    -- shooterBeam, shooterPlasma, preflightFailures, geometrySplits. Decoded
    -- from the MD producer and the onScenarioReady consumer. With no station:
    -- 3 ships, 0 stations, 2 safe/repair fixtures, 2 hostiles, 1 shooter with
    -- weapons=4/turrets=4/beam=2/plasma=2, and 0 geometry splits.
    local requestId = events[1].params.requestId
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct8:" .. requestId .. ":issue-67-contract:3:0:0:0:0:0:0:2:2:0:0:2:2:1:0:0:0:0:0:0:4:4:2:2:0:0")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1
            and harness.fix.logContains("geometry_splits=0")
            and harness.fix.logContains("turrets=4")
            and harness.fix.logContains("beam=2") and harness.fix.logContains("plasma=2"),
        "v8 READY must verify the exact four-turret shooter with no station")

    -- selectAll arms BOTH equipped medium groups: group_front_up_mid holds two
    -- beams (components 27,28) and group_mid_up_mid holds two plasmas (29,30),
    -- four turrets total. The flattened, sorted member multiset must equal
    -- {beam,beam,plasma,plasma}; a fourth beam breaks it.
    local groupBuffer = {
        [0] = { path = "p", group = "group_front_up_mid", contextid = 5 },
        [1] = { path = "p", group = "group_mid_up_mid", contextid = 5 },
    }
    harness.fix.ffiStub.new = function() return groupBuffer end
    harness.fix.C.GetNumUpgradeGroups = function() return 2 end
    harness.fix.C.GetUpgradeGroups2 = function() return 2 end
    harness.fix.C.GetUpgradeGroupInfo2 = function(_, _, _, _, group)
        if group == "group_mid_up_mid" then
            return { count = 2, currentcomponent = 29, currentmacro = plasma,
                slotsize = "medium", total = 2, operational = 2 }
        end
        return { count = 2, currentcomponent = 27, currentmacro = beam,
            slotsize = "medium", total = 2, operational = 2 }
    end
    harness.fix.C.GetNumUpgradeSlots = function() return 4 end
    harness.fix.C.GetUpgradeSlotCurrentComponent = function(_, _, slot)
        return 26 + slot
    end
    harness.fix.C.GetUpgradeSlotGroup = function(_, _, _, slot)
        if slot <= 2 then return { path = "p", group = "group_front_up_mid" } end
        return { path = "p", group = "group_mid_up_mid" }
    end
    local wrongComposition = true
    GetComponentData = function(component, field)
        if field == "macro" then
            local value = tonumber(component)
            if value == 27 or value == 28 then return beam end
            if value == 29 then return plasma end
            if value == 30 then return wrongComposition and beam or plasma end
            return "ship_arg_l_destroyer_02_a_macro"
        end
        if field == "isplayerowned" then return true end
        return nil
    end
    harness.fix.C.GetComponentName = function(component)
        local value = tonumber(component)
        if value == 27 or value == 28 then return "Beam" end
        if value == 29 or value == 30 then return "Plasma" end
        return "ISSUE ARC-BARREL BEHEMOTH E 1"
    end

    harness.fix.gcMenu.onShowMenu()
    harness.fix.gcMenu.display()
    harness.fix.buttonByText(ReadText(20991, 32)).handlers.onClick()
    harness.testMenu.onShowMenu()
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1,
        "three beams and one plasma must not arm the two-beam/two-plasma shooter")
    wrongComposition = false
    harness.testMenu.onShowMenu()
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 2
            and harness.fix.logContains("event=scenario_activate")
            and harness.fix.logContains("action=ready")
            and harness.fix.logContains("member_macros="),
        "the exact two-beam/two-plasma shooter must auto-arm after teleport")
end

-- Outside an occupied remote shooter, Despawn remains active and emits the
-- one cleanup event that MD owns.
do
    local harness = loadHarness({
        id = "safe-despawn", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 1, distance = 1000 } },
    })
    harness.openFromGunnery({ label = "safe local launcher", phase = "console" })
    local despawn = harness.fix.buttonByText(ReadText(20992, 26))
    assert(despawn and despawn.active == true,
        "Despawn must be active when the player does not occupy a spawned fixture")
    local before = #scenarioEvents(harness)
    despawn.handlers.onClick()
    local events = scenarioEvents(harness)
    assert(#events == before + 1 and events[#events].control == "despawn_scenario",
        "active Despawn must emit exactly one cleanup event")
end

-- A disabled spec is inert on load. The one-click action preflights the exact
-- ship/group, replaces the fixture, selects only that group, and returns to
-- Gunnery only after MD acknowledges the expected ship count.
do
    local harness = loadHarness({
        id = "parked", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 1, distance = 1000 } },
    })
    assert(#scenarioEvents(harness) == 0, "a disabled spec must fire nothing on load")

    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    local selectedKey = X4GunneryState.groupKey(5, "p", "g")
    session.staged[selectedKey] = nil
    session.checkedGroupKeys.extra = true
    session.staged.extra = { mode = "defend", preTickMode = "attack" }
    local create = harness.fix.buttonByText(ReadText(20992, 25))
    assert(create and create.handlers.onClick, "Test Lab must expose Create test scenario")
    create.handlers.onClick()
    local events = scenarioEvents(harness)
    local requestId = events[1].params.requestId
    assert(#events == 3 and events[1].params.force == true
            and type(requestId) == "string" and requestId:match("_1$"),
        "Create test scenario must force a correlated replacement even when the spec is disabled")
    assert(harness.fix.logContains("event=scenario_runtime")
            and harness.fix.logContains("load_time="),
        "each Test Lab Lua lifetime must log its auditable engine time")
    assert(harness.fix.logContains("action=requested")
            and harness.fix.logContains("request_id=" .. requestId),
        "Create test scenario must log its exact correlated request token")
    assert(session.checkedGroupKeys[selectedKey] == true and session.checkedGroupKeys.extra == true
            and session.staged.extra.mode == "defend" and session.staged.extra.preTickMode == "attack",
        "preflight must leave checked and staged state untouched before acknowledgement")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "Test Lab must wait for MD acknowledgement before returning")
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady", "x4gct1:stale_1:parked:1")
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady", "x4gct1:" .. requestId .. ":wrong-spec:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "a stale-load or wrong-spec acknowledgement must be ignored")
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady", "x4gct1:" .. requestId .. ":parked:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1,
        "a matching complete spawn acknowledgement must return to Gunnery exactly once")
    assert(harness.fix.logContains("action=ready")
            and harness.fix.logContains("request_id=" .. requestId),
        "successful acknowledgement must log the same request token")
    assert(session.checkedGroupKeys[selectedKey] == true and session.checkedGroupKeys.extra == nil,
        "successful acknowledgement must leave only the exact raw group selected")
    assert(session.staged[selectedKey] and session.staged[selectedKey].armed == false,
        "a freshly staged selected group must preserve its live disarmed state")
    local observingArmed = false
    for _, event in ipairs(harness.fix.uiTriggeredEvents) do
        if event.control == "observe_toggle" and event.params.enabled == true then
            observingArmed = true
        end
    end
    assert(observingArmed,
        "successful one-click scenario creation must arm automatic firing-solution observation")
end

-- Replacing a fixture from an engaged session leaves its parked aim id pointing
-- at the object MD just destroyed. READY must arm observation without sending
-- or automatically marking that stale target; the next distinct target resumes
-- normal capture.
do
    local harness = loadHarness({
        id = "stale-observe-target", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 1, distance = 1000 } },
    })
    local session = harness.openFromGunnery({
        label = "Direct engaged", phase = "engaged", controlMode = "direct", direct = true,
    })
    session.aimTargetID = 9001
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local requestId = scenarioEvents(harness)[1].params.requestId
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. requestId .. ":stale-observe-target:1")

    local staleState, staleMark = false, false
    for _, event in ipairs(harness.fix.uiTriggeredEvents) do
        if event.control == "observe_state" and event.params.aimtgt == 9001 then staleState = true end
        if event.control == "observe_mark" then staleMark = true end
    end
    assert(not staleState and not staleMark,
        "READY must not publish or mark the destroyed pre-replacement aim target")

    session.aimTargetID = 9002
    local callback = harness.fix.pendingCallbacks[#harness.fix.pendingCallbacks]
    assert(callback, "arming observation must schedule its next state push")
    harness.fix.runCallback(callback)
    local newState, newMark = false, false
    for _, event in ipairs(harness.fix.uiTriggeredEvents) do
        if event.control == "observe_state" and event.params.aimtgt == 9002 then newState = true end
        if event.control == "observe_mark" then newMark = true end
    end
    assert(newState and newMark,
        "a distinct post-replacement aim target must resume state and automatic capture")
end

-- Consecutive Test Lab Lua lifetimes may clear every Lua global. Engine real
-- time still advances, so their first request IDs cannot collide.
do
    local function firstRequestId(realTime)
        local harness = loadHarness({
            id = "generation", enabled = false,
            setup = {
                shipMacro = "test_ship_macro", shipLabel = "Test Ship",
                turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
            },
            groups = { { macro = "m", faction = "xenon", count = 1, distance = 1000 } },
        }, realTime)
        harness.openFromGunnery({ label = "console", phase = "console" })
        harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
        return scenarioEvents(harness)[1].params.requestId
    end
    X4GunneryTestLabRuntime = nil
    local first = firstRequestId(100.125)
    X4GunneryTestLabRuntime = nil
    local second = firstRequestId(101.250)
    assert(first ~= second and first:match("_1$") and second:match("_1$"),
        "consecutive UI lifetimes must generate distinct first-request IDs")
end

-- A preflight mismatch must not despawn the existing fixture or alter the
-- operator's selection. A partial MD acknowledgement must not return to play.
do
    local harness = loadHarness({
        id = "preflight-guards", enabled = true,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Required Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 2, distance = 1000 } },
    })
    -- Ignore the automatic load-time replay; only the button attempt matters.
    for index = #harness.fix.uiTriggeredEvents, 1, -1 do
        table.remove(harness.fix.uiTriggeredEvents, index)
    end
    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    local before = {}
    for key, value in pairs(session.checkedGroupKeys) do before[key] = value end
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    assert(#scenarioEvents(harness) == 0, "same-macro wrong-name preflight must not touch the field")
    for key, value in pairs(before) do
        assert(session.checkedGroupKeys[key] == value, "wrong-name preflight must preserve checked groups")
    end
end

do
    local harness = loadHarness({
        id = "ack-count-guard", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 2, distance = 1000 } },
    })
    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    session.checkedGroupKeys.extra = true
    session.staged.extra = { mode = "defend", preTickMode = "attack" }
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local events = scenarioEvents(harness)
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. events[1].params.requestId .. ":ack-count-guard:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "partial spawn acknowledgement must keep Test Lab open")
    assert(harness.fix.logContains("action=failed"),
        "partial spawn acknowledgement must emit a machine-readable failure")
    assert(session.checkedGroupKeys.extra == true and session.staged.extra.mode == "defend",
        "partial acknowledgement must preserve checked and staged state")
end

do
    local now = 0
    local harness = loadHarness({
        id = "ack-timeout", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 1, distance = 1000 } },
    })
    getElapsedTime = function() return now end
    harness.openFromGunnery({ label = "console", phase = "console" })
    local session = harness.fix.API.getSession()
    session.checkedGroupKeys.extra = true
    session.staged.extra = { mode = "defend", preTickMode = "attack" }
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    now = 11
    harness.testMenu.onUpdate()
    assert(harness.fix.logContains("action=timeout"),
        "missing spawn acknowledgement must produce a bounded timeout")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "spawn timeout must keep Test Lab open for its failure message")
    assert(session.checkedGroupKeys.extra == true and session.staged.extra.mode == "defend",
        "spawn timeout must preserve checked and staged state")
end

-- A loadout change during MD creation invalidates the result before checkbox
-- mutation, even when MD created the requested ship count.
do
    local harness = loadHarness({
        id = "loadout-changed", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 1, distance = 1000 } },
    })
    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    session.checkedGroupKeys.extra = true
    session.staged.extra = { mode = "defend", preTickMode = "attack" }
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local events = scenarioEvents(harness)
    harness.fix.C.IsComponentOperational = function() return false end
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. events[1].params.requestId .. ":loadout-changed:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "changed loadout must keep Test Lab open")
    assert(session.checkedGroupKeys.extra == true and session.staged.extra.mode == "defend",
        "changed loadout must preserve checked and staged state")
end

-- Despawn is disabled while pending, and even a directly invoked stale handler
-- must leave both the fixture request and its acknowledgement correlation intact.
do
    local harness = loadHarness({
        id = "pending-despawn", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 1, distance = 1000 } },
    })
    harness.openFromGunnery({ label = "console", phase = "console" })
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local events = scenarioEvents(harness)
    local despawn = harness.fix.buttonByText(ReadText(20992, 26))
    assert(despawn.active == false, "Despawn must be disabled while creation is pending")
    local eventCountBeforeRejectedDespawn = #scenarioEvents(harness)
    despawn.handlers.onClick()
    assert(#scenarioEvents(harness) == eventCountBeforeRejectedDespawn
            and harness.fix.logContains("reason=creation_pending"),
        "a stale pending Despawn handler must send no cleanup event")
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. events[1].params.requestId .. ":pending-despawn:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1,
        "rejected pending Despawn must preserve the matching READY handoff")
end

-- Malformed specs are caught, logged, and never raise. Test Lab must still open
-- and still offer despawn, because a broken spec is the moment cleanup matters.
-- `reason` is the substring the rejection must name, in the SANITIZED form the
-- log actually carries (log() replaces every non-word character with "_"), so a validator that
-- silently swallows the failure (and reports the spec as merely absent) fails
-- here rather than looking like a pass.
local malformed = {
    { label = "not a table", spec = 42, reason = "spec_is_not_a_table" },
    { label = "missing id", spec = { enabled = true, groups = {} }, reason = "spec.id_must_be" },
    { label = "non-boolean enabled", spec = { id = "x", enabled = "yes", groups = {} }, reason = "spec.enabled_must_be" },
    { label = "empty groups", spec = { id = "x", enabled = true, groups = {} }, reason = "spec.groups_is_empty" },
    { label = "group missing macro", spec = { id = "x", enabled = true,
        groups = { { faction = "xenon", count = 1, distance = 100 } } }, reason = "groups_1_.macro" },
    { label = "bad behaviour", spec = { id = "x", enabled = true,
        groups = { { macro = "m", faction = "xenon", count = 1, distance = 100, behaviour = "loiter" } } },
        reason = "groups_1_.behaviour" },
    { label = "absent global", spec = "absent" },
}
for _, case in ipairs(malformed) do
    local ok, harness = pcall(loadHarness, case.spec)
    assert(ok, "a malformed spec (" .. case.label .. ") must not raise: " .. tostring(harness))
    assert(#scenarioEvents(harness) == 0,
        "a malformed spec (" .. case.label .. ") must spawn nothing")
    harness.openFromGunnery({ label = "console", phase = "console" })
    assert(harness.fix.buttonByText(ReadText(20992, 26)) ~= nil,
        "Test Lab must still offer despawn with a malformed spec (" .. case.label .. ")")

    -- Forcing must not rescue a spec that could not be understood.
    local rerun = harness.fix.buttonByText(ReadText(20992, 25))
    assert(rerun and rerun.handlers.onClick, "the re-run button must exist with a malformed spec")
    rerun.handlers.onClick()
    assert(#scenarioEvents(harness) == 0,
        "forcing a malformed spec (" .. case.label .. ") must still spawn nothing")

    if case.reason then
        local named = false
        for _, line in ipairs(harness.fix.getCapturedLog()) do
            if string.find(line, "action=rejected", 1, true) and string.find(line, case.reason) then
                named = true
            end
        end
        assert(named, "rejecting " .. case.label .. " must log a reason naming " .. case.reason)
    end
end

-- The shipped spec file must itself stay loadable and inert, so that an
-- unrelated Reload UI never spawns whatever the last test left behind.
do
    local shipped = dofile("testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua")
    assert(type(shipped) == "table", "the shipped spec must return a table")
    assert(shipped.enabled == false,
        "the spec committed to the repository must be disabled; enable it only for a live run")
    assert(shipped.id == "issue-67-arc-barrel-diagnostic-r1"
            and shipped.setup.shipMacro == "ship_arg_l_destroyer_02_a_macro"
            and shipped.setup.turretGroup == "group_front_up_mid"
            and shipped.setup.selectAll == true
            and shipped.setup.expectedTurrets == 4,
        "the shipped issue #67 fixture must retain its exact Behemoth E setup")
    assert(#shipped.setup.expectedMacros == 4
            and shipped.setup.expectedMacros[1] == "turret_arg_m_beam_02_mk1_macro"
            and shipped.setup.expectedMacros[2] == "turret_arg_m_beam_02_mk1_macro"
            and shipped.setup.expectedMacros[3] == "turret_arg_m_plasma_02_mk1_macro"
            and shipped.setup.expectedMacros[4] == "turret_arg_m_plasma_02_mk1_macro",
        "the shipped issue #67 fixture must have two-beam/two-plasma per-group loadout")
    assert(#shipped.groups == 3 and shipped.stations == nil
            and shipped.groups[2].geometryRole == "clear_arc"
            and shipped.groups[3].geometryRole == "below_arc",
        "the shipped issue #67 fixture must retain both ship geometry roles and have no stations")
end

-- The shipped spec must be ACCEPTED by validateSpec/loadSpec, not merely well
-- formed. validateSpec carries a hardcoded shooter-census guard; if it drifts
-- from the shipped spec (as it did when the greyed-out Create button shipped),
-- loadSpec returns an error, scenarioSpecLabel() renders "invalid (...)", and
-- Create is disabled in game. This offline guard is the one that catches that
-- drift: loadHarness() with no argument loads the real shipped spec file.
do
    local harness = loadHarness()
    harness.openFromGunnery({ label = "shipped-spec launcher", phase = "console" })
    harness.testMenu.onShowMenu()
    local specLabelText
    for _, entry in ipairs(harness.fix.getCreatedTexts()) do
        if type(entry.text) == "string" and entry.text:find(ReadText(20992, 27), 1, true) then
            specLabelText = entry.text
        end
    end
    assert(specLabelText, "Test Lab must render the shipped spec label row")
    assert(not specLabelText:find("invalid (", 1, true),
        "the shipped spec must be accepted by validateSpec; label was: " .. specLabelText)
    assert(specLabelText:find("issue-67-arc-barrel-diagnostic-r1", 1, true),
        "the accepted shipped spec label must name the shipped id; label was: " .. specLabelText)
    for _, line in ipairs(harness.fix.getCapturedLog()) do
        assert(not (line:find("action=rejected", 1, true)
                and line:find("inconsistent_shooter_census", 1, true)),
            "loadSpec rejected the shipped spec on its census guard: " .. line)
    end
end

print("testlab lifecycle scenario tests passed")
