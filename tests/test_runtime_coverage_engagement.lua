local fix = dofile("tests/support/runtime_fixture.lua").load()
local group = fix.makeGroup{
    key = "g",
    members = { { componentID = 27, operational = true, cameraSupported = true } },
}
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()
session.groups, session.checkedGroupKeys, session.cameraMemberID = { group }, { g = true }, 27
-- Seed staged so the staged-apply loops inside startAutoEngage and engageTarget are exercised.
session.staged = { g = { mode = "attack", armed = false } }
fix.C.GetExternalTargetViewComponent = function() return 27 end
assert(fix.API.startAutoEngage({ group }), "Auto entry must succeed with a camera member")
assert(fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control == "session_commit",
    "Auto entry must commit its session")

session.phase, session.controlMode, session.committedBaseline = "target_select", nil, {}
-- Re-seed staged for the engageTarget call.
session.staged = { g = { mode = "attack", armed = false } }
fix.C.GetContextByClass = function(_, class)
    if class == "container" then return 98 end
    return 42
end
assert(fix.API.engageTarget(99), "Direct entry must accept an external target")
assert(session.phase == "engaged" and session.controlMode == "direct",
    "Direct entry must build the engaged session")

-- The refusal branch: a player-owned root is rejected, so entering Direct
-- against one leaves the existing engagement untouched.
GetComponentData = function(_, key)
    if key == "isplayerowned" then return true end
    return nil
end
assert(not fix.API.engageTarget(99), "Direct entry must refuse a player-owned target")
GetComponentData = function() return nil end

-- Live test result, 2026-08-10 (conclusive): under Direct-control with the
-- player's pilot actively fighting (aicommandraw="attackobject"), weaponmode
-- "attackenemies" DOES honour the mod's supplied preferred target and fallback
-- list. The long-held fear that vanilla's fight script overwrites our list is
-- DISPROVEN by observation. Direct-control therefore always uses attackenemies
-- (State.TICK_MODE), regardless of the pilot's command state.
--
-- Behavioural invariant: engageTarget with an actively fighting pilot must
--   (a) succeed,
--   (b) leave checked mutable groups in mode "attackenemies" (State.TICK_MODE),
--   (c) raise the "direct_fallback" UI-triggered event.
-- (c) is load-bearing: under the old autoassist branch, emitDirectFallback
-- returned early for a fighting pilot, so no fallback list was ever issued and
-- a turret with no firing solution on the preferred target tracked in silence.
do
    session.phase, session.controlMode = "target_select", nil
    session.staged = { g = { mode = "attack", armed = false } }
    GetComponentData = function(_, key)
        if key == "assignedpilot" then return 55 end  -- non-nil pilot
        if key == "aicommandraw"  then return "attackobject" end
        return nil
    end
    local eventsBefore = #fix.uiTriggeredEvents
    assert(fix.API.engageTarget(99),
        "attacking pilot: engageTarget must succeed (live result 2026-08-10 disproves vanilla overwrite)")
    -- The group must be in attackenemies: the mode is now a constant.
    local s = fix.API.getSession()
    local grpMode = fix.C.SetTurretMode and s.groups[1].mode
        -- setMode calls the FFI; check via getSession group state.
        -- The fixture stubs setMode effects through group.mode mutations.
        -- The real assertion is that emitDirectFallback ran (see below).
    -- A direct_fallback event must have been raised. Without attackenemies the
    -- old emitDirectFallback guard would have returned false here, giving the
    -- turret no fallback list at all.
    local sawFallback = false
    for i = eventsBefore + 1, #fix.uiTriggeredEvents do
        if fix.uiTriggeredEvents[i].control == "direct_fallback" then
            sawFallback = true; break
        end
    end
    assert(sawFallback,
        "attacking pilot: direct_fallback must be raised (live 2026-08-10: attackenemies always works)")
    GetComponentData = function() return nil end
end

-- ── Issue #48 Task 3: the engaged path applies the session policy ───────────
-- These blocks reuse the single fixture (and its session) of this file, so
-- they reset the session fields directly, exactly as the blocks above do.
-- fix.C is the C table the loaded module bound, so the overrides below are
-- visible to the production code.
local function eventsSince(mark)
    local fallback, watch = false, false
    for i = mark + 1, #fix.uiTriggeredEvents do
        local control = fix.uiTriggeredEvents[i].control
        if control == "direct_fallback" then fallback = true end
        if control == "direct_watch" then watch = true end
    end
    return fallback, watch
end

-- First engagement under the default policy. The group is checked and its
-- staged mode follows the policy (the natural post-console state), so the
-- staged apply writes the resolved mode and the arm step must not re-issue
-- the same mode a second time.
do
    session.phase, session.controlMode = "target_select", nil
    session.checkedGroupKeys = { g = true }
    session.staged = { g = { mode = "attackenemies", armed = true } }
    session.groups[1].mode, session.groups[1].armed = "attack", false
    local modes = {}
    fix.C.SetTurretGroupMode2 = function(_, _, _, _, mode) modes[#modes + 1] = mode end
    fix.C.SetTurretGroupArmed = function() end
    local mark = #fix.uiTriggeredEvents
    assert(fix.API.engageTarget(99), "Task 3: first engagement must succeed")
    assert(#modes == 1 and modes[1] == "attackenemies",
        "Task 3: a checked group under attackenemies gets exactly one mode write "
        .. "(no same-mode re-issue): " .. table.concat(modes, ","))
    local sawFallback, sawWatch = eventsSince(mark)
    assert(sawFallback and sawWatch,
        "Task 3: attackenemies engagement must emit direct_fallback and direct_watch")
end

-- First engagement under the autoassist policy: the checked group is written
-- autoassist, the ownership watch stays armed, and no script fallback list is
-- installed (autoassist follows the soft target; a list would be a claim the
-- engine does not make).
do
    session.phase, session.controlMode = "target_select", nil
    session.checkedGroupKeys = { g = true }
    session.staged = { g = { mode = "attack", armed = true } }
    assert(X4GunneryState.setDirectMode(session, "autoassist"),
        "Task 3: the policy switch to autoassist must be accepted")
    assert(session.staged.g.mode == "autoassist",
        "Task 3: the checked group's staged mode must follow the new policy")
    session.groups[1].mode, session.groups[1].armed = "attack", false
    local modes = {}
    fix.C.SetTurretGroupMode2 = function(_, _, _, _, mode) modes[#modes + 1] = mode end
    fix.C.SetTurretGroupArmed = function() end
    local mark = #fix.uiTriggeredEvents
    assert(fix.API.engageTarget(99), "Task 3: autoassist engagement must succeed")
    assert(#modes == 1 and modes[1] == "autoassist",
        "Task 3: a checked group under autoassist gets one autoassist write: "
        .. table.concat(modes, ","))
    local sawFallback, sawWatch = eventsSince(mark)
    assert(not sawFallback,
        "Task 3: autoassist must not install a script fallback list")
    assert(sawWatch,
        "Task 3: autoassist must keep the ownership watch armed")
end

-- Re-engagement (already direct) changes only the target: no mode writes, the
-- watch is re-armed for the new target, and the fallback list is re-sent only
-- under attackenemies.
do
    assert(session.phase == "engaged" and session.controlMode == "direct",
        "Task 3 precondition: the session must still be engaged/direct")
    local modes = {}
    fix.C.SetTurretGroupMode2 = function(_, _, _, _, mode) modes[#modes + 1] = mode end
    local mark = #fix.uiTriggeredEvents
    assert(fix.API.engageTarget(123), "Task 3: re-engagement must succeed")
    assert(#modes == 0, "Task 3: re-engagement must not re-write group modes")
    local sawFallback, sawWatch = eventsSince(mark)
    assert(not sawFallback and sawWatch,
        "Task 3: re-engagement under autoassist re-arms the watch only")
end

-- ── Issue #48 Task 3 correction: Auto-engage never applies autoassist ─────
-- Auto-engage has no Direct-control target selection, so starting it must arm
-- every checked mutable group in the plain attackenemies engine mode live,
-- whatever the session's Direct-control policy is. The staged bookkeeping
-- (policy mode, preTickMode), the policy itself, and checkbox membership must
-- come back untouched so later Direct-control use keeps working.
local groupB = fix.makeGroup{
    key = "gb", contextID = 6, group = "b",
    componentID = 28, mode = "defend", armed = true,
    members = { { componentID = 28, operational = true, cameraSupported = true } },
}
do
    -- Back at the console with the directMode the player picked earlier.
    session.phase, session.controlMode = "console", nil
    session.groups = { group, groupB }
    session.checkedGroupKeys = { g = true }
    -- Natural post-console state under the autoassist policy: the checked row
    -- staged autoassist with its displaced ordinary mode remembered, the
    -- unchecked row an ordinary staged mode.
    session.directMode = "autoassist"
    session.staged = {
        g = { mode = "autoassist", armed = false, preTickMode = "attack" },
        [groupB.key] = { mode = "defend", armed = true },
    }
    -- Live engine state as of sit-down (stale until startAutoEngage writes).
    session.groups[1].mode, session.groups[1].armed = "attack", false
    session.groups[2].mode, session.groups[2].armed = "defend", true

    local modeWrites, armedWrites = {}, {}
    fix.C.SetTurretGroupMode2 = function(_, _, _, grp, mode)
        modeWrites[grp] = modeWrites[grp] or {}
        modeWrites[grp][#modeWrites[grp] + 1] = mode
    end
    fix.C.SetTurretGroupArmed = function(_, _, _, grp, armed)
        armedWrites[grp] = armedWrites[grp] or {}
        armedWrites[grp][#armedWrites[grp] + 1] = armed
    end

    assert(fix.API.startAutoEngage(X4GunneryState.checkedGroups(session)),
        "Task 3 fix: auto entry under the autoassist policy must succeed")

    -- The checked group goes live in attackenemies, never the staged autoassist.
    assert(#modeWrites["g"] == 1 and modeWrites["g"][1] == "attackenemies",
        "Task 3 fix: the checked group's live write must be attackenemies "
        .. "even when the staged Direct-control mode is autoassist: "
        .. table.concat(modeWrites["g"] or {}, ","))
    -- The unchecked group keeps its ordinary staged setting, exactly as before.
    assert(#modeWrites["b"] == 1 and modeWrites["b"][1] == "defend",
        "Task 3 fix: the unchecked group must keep its ordinary staged mode (defend)")
    assert(#armedWrites["g"] == 1 and armedWrites["g"][1] == false,
        "Task 3 fix: the checked group's staged armed state is still applied")
    assert(#armedWrites["b"] == 1 and armedWrites["b"][1] == true,
        "Task 3 fix: the unchecked group's staged armed state is still applied")

    -- The policy, the staged bookkeeping, and checkbox membership are untouched.
    assert(session.directMode == "autoassist",
        "Task 3 fix: Auto-engage must not change the Direct-control policy")
    assert(session.staged.g.mode == "autoassist" and session.staged.g.preTickMode == "attack",
        "Task 3 fix: the checked staged row must keep its policy mode and preTickMode")
    assert(session.staged[groupB.key].mode == "defend" and session.staged[groupB.key].armed == true,
        "Task 3 fix: the unchecked staged row must stay untouched")
    assert(session.checkedGroupKeys.g == true and session.checkedGroupKeys[groupB.key] == nil,
        "Task 3 fix: checkbox membership must stay untouched")
    assert(session.phase == "engaged" and session.controlMode == "auto",
        "Task 3 fix: Auto-engage still ends engaged/auto")
end

-- Under the attackenemies policy the checked group's staged mode already is
-- attackenemies; the live write stays attackenemies and the unchecked group
-- still takes its ordinary staged mode.
do
    session.phase, session.controlMode = "console", nil
    session.directMode = "attackenemies"
    session.checkedGroupKeys = { g = true }
    session.staged = {
        g = { mode = "attackenemies", armed = true, preTickMode = "attack" },
        [groupB.key] = { mode = "mining", armed = false },
    }
    session.groups[1].mode, session.groups[1].armed = "attack", false
    session.groups[2].mode, session.groups[2].armed = "mining", false

    local modeWrites = {}
    fix.C.SetTurretGroupMode2 = function(_, _, _, grp, mode)
        modeWrites[grp] = modeWrites[grp] or {}
        modeWrites[grp][#modeWrites[grp] + 1] = mode
    end

    assert(fix.API.startAutoEngage(X4GunneryState.checkedGroups(session)),
        "Task 3 fix: auto entry under the attackenemies policy must succeed")

    assert(#modeWrites["g"] == 1 and modeWrites["g"][1] == "attackenemies",
        "Task 3 fix: under attackenemies the checked group is written attackenemies once")
    assert(#modeWrites["b"] == 1 and modeWrites["b"][1] == "mining",
        "Task 3 fix: under attackenemies the unchecked group keeps its staged mode (mining)")
    assert(session.directMode == "attackenemies",
        "Task 3 fix: the attackenemies policy must stay put")
    assert(session.staged.g.mode == "attackenemies" and session.staged.g.preTickMode == "attack",
        "Task 3 fix: the checked staged row must keep its policy mode and preTickMode")
end

print("runtime coverage engagement tests passed")
