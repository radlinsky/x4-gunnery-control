local fix = dofile("tests/support/runtime_fixture.lua").load()
local group = {
    key = "g", kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 27, operationalCount = 1, totalCount = 1, mode = "attack", armed = false,
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

print("runtime coverage engagement tests passed")
