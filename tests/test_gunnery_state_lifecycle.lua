local State = dofile("ui/gunnery_state.lua")
local function eq(a, b, label) assert(a == b, (label or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- seedBaseline: seeds committedBaseline and staged from live groups
do
    local sb = State.newSession(77, "g")
    local grpGroup = { key = "group:C1:path:name", kind = "group", componentID = 10,
        contextID = "C1", path = "path", group = "name", mode = "attack", armed = true,
        operationalCount = 1, totalCount = 1 }
    local grpSingle = { key = "single:20", kind = "single", componentID = 20,
        contextID = nil, path = nil, group = nil, mode = "defend", armed = false,
        operationalCount = 1, totalCount = 1 }
    State.seedBaseline(sb, { grpGroup, grpSingle })
    eq(#sb.committedBaseline, 2, "seedBaseline: two entries in committedBaseline")
    eq(sb.committedBaseline[1].shipID, 77, "seedBaseline: shipID from session")
    eq(sb.committedBaseline[1].kind, "group", "seedBaseline: kind from group")
    eq(sb.committedBaseline[1].mode, "attack", "seedBaseline: mode from group")
    eq(sb.committedBaseline[1].armed, true, "seedBaseline: armed from group")
    eq(sb.committedBaseline[2].kind, "single", "seedBaseline: single kind")
    eq(sb.committedBaseline[2].armed, false, "seedBaseline: single armed false")
    -- staged is keyed by group.key
    local expectedKey = State.groupKey("C1", "path", "name")
    assert(sb.staged[expectedKey] ~= nil, "seedBaseline: staged has group entry")
    eq(sb.staged[expectedKey].mode, "attack", "seedBaseline: staged mode matches group")
    eq(sb.staged[expectedKey].armed, true, "seedBaseline: staged armed matches group")
    local singleKey = State.singleKey(20)
    assert(sb.staged[singleKey] ~= nil, "seedBaseline: staged has single entry")
    eq(sb.staged[singleKey].mode, "defend", "seedBaseline: single staged mode")
    -- Neither seeded group is in TICK_MODE, so neither comes up ticked.
    assert(next(sb.checkedGroupKeys) == nil,
        "seedBaseline: a group not in TICK_MODE must not be ticked")
    -- nil groups: no error
    State.seedBaseline(sb, nil)
    eq(#sb.committedBaseline, 0, "seedBaseline nil groups: clears committedBaseline")
end

-- seedBaseline ticks groups the ship is already flying in TICK_MODE. Reported
-- live 2026-08-10: a committed "Attack all enemies" change survived standing up
-- but its checkbox did not, and ticking the group by hand then recorded
-- TICK_MODE as its own preTickMode, so the checkbox stopped changing the mode
-- in either direction.
do
    local sb = State.newSession(77, "g")
    local already = { key = "group:C1:p:already", kind = "group", componentID = 10,
        contextID = "C1", path = "p", group = "already", mode = State.TICK_MODE,
        armed = true, operationalCount = 1, totalCount = 1 }
    local other = { key = "group:C1:p:other", kind = "group", componentID = 11,
        contextID = "C1", path = "p", group = "other", mode = "defend",
        armed = true, operationalCount = 1, totalCount = 1 }
    State.seedBaseline(sb, { already, other })
    local alreadyKey = State.groupKey("C1", "p", "already")
    local otherKey = State.groupKey("C1", "p", "other")
    assert(sb.checkedGroupKeys[alreadyKey] == true,
        "seedBaseline: a group already in TICK_MODE must come up ticked")
    assert(sb.checkedGroupKeys[otherKey] == nil,
        "seedBaseline: a group in another mode must come up unticked")
    assert(sb.staged[alreadyKey].preTickMode == nil,
        "seedBaseline: a seeded tick has no earlier mode to record")
    -- Unticking it falls to UNTICK_FALLBACK rather than restoring TICK_MODE.
    State.toggleGroup(sb, alreadyKey, already.armed)
    eq(sb.checkedGroupKeys[alreadyKey], nil, "seeded tick: untick clears the checkbox")
    eq(sb.staged[alreadyKey].mode, State.UNTICK_FALLBACK,
        "seeded tick: untick falls back rather than restoring TICK_MODE")
    -- And ticking it again is a real round trip, not a no-op.
    State.toggleGroup(sb, alreadyKey, already.armed)
    eq(sb.staged[alreadyKey].mode, State.TICK_MODE, "seeded tick: re-tick sets TICK_MODE")
    eq(sb.staged[alreadyKey].preTickMode, State.UNTICK_FALLBACK,
        "seeded tick: re-tick records the displaced fallback mode")
end

-- applyTick must never record TICK_MODE as preTickMode: untick would then
-- "restore" the mode the group already has and the checkbox would look dead.
do
    local sb = State.newSession(77, "g")
    local key = State.groupKey("C1", "p", "g")
    sb.staged = { [key] = { mode = State.TICK_MODE, armed = true } }
    sb.committedBaseline = {}
    State.toggleGroup(sb, key, true)
    eq(sb.checkedGroupKeys[key], true, "tick on an already-TICK_MODE group checks it")
    assert(sb.staged[key].preTickMode ~= State.TICK_MODE,
        "preTickMode must never be TICK_MODE itself")
    State.toggleGroup(sb, key, true)
    eq(sb.staged[key].mode, State.UNTICK_FALLBACK,
        "untick must fall back, not restore TICK_MODE")
end

-- baselineStagedKey is the single derivation shared by seedBaseline and every
-- reader. Regression: seedBaseline once keyed staged by group.key while the
-- readers derived the key from the entry's locator fields. For a group whose key
-- was not literally the derived form the two never met, so isStagedDirty was
-- stuck true and commitStagedToBaseline silently updated nothing.
do
    eq(State.baselineStagedKey({ kind = "group", contextID = 5, path = "p", group = "g" }),
        State.groupKey(5, "p", "g"), "baselineStagedKey: group entries use groupKey")
    eq(State.baselineStagedKey({ kind = "single", componentID = 42 }),
        State.singleKey(42), "baselineStagedKey: single entries use singleKey")

    -- A group whose .key disagrees with its locator fields must still round trip.
    local odd = State.newSession(1, "g")
    local oddGroup = { key = "an-opaque-key", kind = "group", componentID = 7,
        contextID = 5, path = "p", group = "g", mode = "attack", armed = true,
        operationalCount = 1, totalCount = 1 }
    State.seedBaseline(odd, { oddGroup })
    assert(not State.isStagedDirty(odd),
        "a freshly seeded session must be clean whatever the group's key looks like")
    State.stageMode(odd, State.baselineStagedKey(odd.committedBaseline[1]), "defend", true)
    assert(State.isStagedDirty(odd), "staging a change must mark the session dirty")
    State.commitStagedToBaseline(odd)
    eq(odd.committedBaseline[1].mode, "defend", "commit must reach the baseline entry")
    assert(not State.isStagedDirty(odd), "commit must clear the dirty flag")
end

-- stageMode and stageArmed: edit staged without touching ship
do
    local ss = State.newSession(1, "g")
    ss.staged = { ["key1"] = { mode = "attack", armed = true } }
    State.stageMode(ss, "key1", "defend")
    eq(ss.staged["key1"].mode, "defend", "stageMode: updates existing entry mode")
    eq(ss.staged["key1"].armed, true, "stageMode: armed unchanged")
    State.stageArmed(ss, "key1", false)
    eq(ss.staged["key1"].armed, false, "stageArmed: updates existing entry armed")
    eq(ss.staged["key1"].mode, "defend", "stageArmed: mode unchanged")
    -- stageMode on a missing key takes armed from the caller's live-group value.
    -- A group can appear after seedBaseline (refresh() discovers it, or a legacy
    -- payload rebuilt staged empty); defaulting armed to false there would disarm
    -- a group the player never touched as soon as the change is committed.
    State.stageMode(ss, "newkey", "patrol", true)
    eq(ss.staged["newkey"].mode, "patrol", "stageMode: new key created")
    eq(ss.staged["newkey"].armed, true, "stageMode: new key armed comes from the live group, not false")
    State.stageMode(ss, "unarmedkey", "patrol", false)
    eq(ss.staged["unarmedkey"].armed, false, "stageMode: a genuinely unarmed live group stays unarmed")
    -- stageArmed on a missing key takes mode from the caller's live-group value.
    -- "" is not a valid weapon mode, so it must never be manufactured here.
    State.stageArmed(ss, "anotherkey", true, "attack")
    eq(ss.staged["anotherkey"].armed, true, "stageArmed: new key created")
    eq(ss.staged["anotherkey"].mode, "attack", "stageArmed: new key mode comes from the live group, not \"\"")
    -- nil session/staged: no error
    State.stageMode(nil, "k", "m", false)
    State.stageArmed(nil, "k", true, "attack")
    local noStaged = State.newSession(1, "g"); noStaged.staged = nil
    State.stageMode(noStaged, "k", "m", false)
    State.stageArmed(noStaged, "k", true, "attack")
end

-- Regression: staging a mode on a group that seedBaseline never saw must not
-- clobber its armed state. This is the live hazard -- a turret group discovered
-- by a later refresh() has no staged entry, and committing a mode change for it
-- used to silently disarm it.
do
    local late = State.newSession(1, "g")
    local seeded = { key = "group:C:p:seeded", kind = "group", componentID = 1,
        contextID = "C", path = "p", group = "seeded", mode = "attack", armed = true,
        operationalCount = 1, totalCount = 1 }
    State.seedBaseline(late, { seeded })
    -- A second group turns up after the seed: live, armed, and absent from staged.
    local discovered = { key = "group:C:p:discovered", kind = "group", componentID = 2,
        contextID = "C", path = "p", group = "discovered", mode = "attack", armed = true,
        operationalCount = 1, totalCount = 1 }
    assert(late.staged[discovered.key] == nil, "regression setup: discovered group is absent from staged")
    -- The console passes the live group's armed flag through, as menu.display does.
    State.stageMode(late, discovered.key, "defend", discovered.armed)
    eq(late.staged[discovered.key].mode, "defend", "late group: staged mode is the requested one")
    eq(late.staged[discovered.key].armed, true,
        "late group: armed is preserved from the live group, not clobbered to false")
    -- And the same in the other direction: arming a late group keeps its real mode.
    local discovered2 = { key = "group:C:p:discovered2", mode = "attack", armed = false }
    State.stageArmed(late, discovered2.key, true, discovered2.mode)
    eq(late.staged[discovered2.key].mode, "attack",
        "late group: mode is preserved from the live group, not replaced by \"\"")
end

-- isStagedDirty: true when staged differs from committedBaseline
do
    local grp = { key = "group:C:p:g", kind = "group", componentID = 5,
        contextID = "C", path = "p", group = "g", mode = "attack", armed = true,
        operationalCount = 1, totalCount = 1 }
    local sd = State.newSession(1, "g")
    State.seedBaseline(sd, { grp })
    assert(not State.isStagedDirty(sd), "isStagedDirty: clean after seeding")
    State.stageMode(sd, State.groupKey("C", "p", "g"), "defend")
    assert(State.isStagedDirty(sd), "isStagedDirty: dirty after stageMode change")
    -- revert staged to match baseline
    State.stageMode(sd, State.groupKey("C", "p", "g"), "attack")
    assert(not State.isStagedDirty(sd), "isStagedDirty: clean after reverting staged")
    -- stageArmed change
    State.stageArmed(sd, State.groupKey("C", "p", "g"), false)
    assert(State.isStagedDirty(sd), "isStagedDirty: dirty after stageArmed change")
    -- nil session: false
    assert(not State.isStagedDirty(nil), "isStagedDirty: nil session is not dirty")
    -- no staged: false
    local noStaged = State.newSession(1, "g"); noStaged.staged = nil
    assert(not State.isStagedDirty(noStaged), "isStagedDirty: nil staged is not dirty")
    -- single-kind baseline entry
    local grpS = { key = "single:9", kind = "single", componentID = 9,
        mode = "defend", armed = false, operationalCount = 1, totalCount = 1 }
    local sdS = State.newSession(1, "g")
    State.seedBaseline(sdS, { grpS })
    assert(not State.isStagedDirty(sdS), "isStagedDirty: single-kind clean after seeding")
    State.stageArmed(sdS, State.singleKey(9), true)
    assert(State.isStagedDirty(sdS), "isStagedDirty: single-kind dirty after change")
end

-- commitStagedToBaseline: advances committedBaseline to match staged
do
    local grp = { key = "group:C:p:g", kind = "group", componentID = 5,
        contextID = "C", path = "p", group = "g", mode = "attack", armed = true,
        operationalCount = 1, totalCount = 1 }
    local sc = State.newSession(1, "g")
    State.seedBaseline(sc, { grp })
    State.stageMode(sc, State.groupKey("C", "p", "g"), "defend")
    State.stageArmed(sc, State.groupKey("C", "p", "g"), false)
    assert(State.isStagedDirty(sc), "commitStagedToBaseline precondition: is dirty")
    State.commitStagedToBaseline(sc)
    assert(not State.isStagedDirty(sc), "commitStagedToBaseline: no longer dirty after commit")
    eq(sc.committedBaseline[1].mode, "defend", "commitStagedToBaseline: baseline mode updated")
    eq(sc.committedBaseline[1].armed, false, "commitStagedToBaseline: baseline armed updated")
    -- single-kind entry: covers the singleKey branch
    local grpS2 = { key = "single:77", kind = "single", componentID = 77,
        mode = "attack", armed = true, operationalCount = 1, totalCount = 1 }
    local scS = State.newSession(1, "g")
    State.seedBaseline(scS, { grpS2 })
    State.stageMode(scS, State.singleKey(77), "defend")
    State.commitStagedToBaseline(scS)
    eq(scS.committedBaseline[1].mode, "defend", "commitStagedToBaseline: single-kind mode updated")
    -- nil session: no error
    State.commitStagedToBaseline(nil)
    local noStaged = State.newSession(1, "g"); noStaged.staged = nil
    State.commitStagedToBaseline(noStaged)
end

-- restoreState with t="baseline" records (new format): staged is rebuilt from baseline
do
    local bsSession = State.newSession("111", "gunnercontrol")
    bsSession.shipName = "Colossus"
    bsSession.phase = "console"
    bsSession.committedBaseline = {
        { kind = "group", shipID = "111", contextID = "CTX", path = "p", group = "g",
          mode = "defend", armed = false },
    }
    local bsLive = { { key = "group:NEWCTX:p:g", contextID = "NEWCTX", path = "p", group = "g" } }
    local bsBack = State.newSession("111", "gunnercontrol")
    bsBack.shipName = "Colossus"
    local bsOk = State.restoreState(bsBack,
        State.decode(State.encode(State.saveState(bsSession))), bsLive)
    assert(bsOk, "baseline round-trip: restore succeeds")
    eq(#bsBack.committedBaseline, 1, "baseline round-trip: one entry restored")
    eq(bsBack.committedBaseline[1].mode, "defend", "baseline round-trip: mode preserved")
    -- staged is rebuilt from restored baseline
    local bsKey = State.groupKey("NEWCTX", "p", "g")
    assert(bsBack.staged[bsKey] ~= nil, "baseline round-trip: staged rebuilt from baseline")
    eq(bsBack.staged[bsKey].mode, "defend", "baseline round-trip: staged mode from baseline")
    eq(bsBack.staged[bsKey].armed, false, "baseline round-trip: staged armed from baseline")
end

-- legacy t="snapshot" fallback: when no baseline records present, snapshots populate committedBaseline
do
    local lf = State.newSession("222", "gunnercontrol")
    lf.shipName = "Nemesis"
    -- simulate a legacy payload with only snapshot records (no baseline records)
    local legacyRecords = {
        { t = "session", phase = "engaged", controlMode = "direct",
          povAnchor = "turret", povMode = "manual",
          autoNextTarget = "1",
          shipID = "222", shipName = "Nemesis", aimTargetID = "", cameraMemberID = "" },
        { t = "snapshot", kind = "group", shipID = "222", contextID = "CTX",
          path = "p", group = "g", mode = "attack", armed = "1" },
    }
    local lfLive = { { key = "group:CTX2:p:g", contextID = "CTX2", path = "p", group = "g" } }
    local lfBack = State.newSession("222", "gunnercontrol")
    lfBack.shipName = "Nemesis"
    assert(State.restoreState(lfBack, legacyRecords, lfLive), "legacy snapshot fallback: restore ok")
    eq(#lfBack.committedBaseline, 1, "legacy snapshot fallback: snapshot promoted to committedBaseline")
    eq(lfBack.committedBaseline[1].mode, "attack", "legacy snapshot fallback: mode preserved")
    eq(lfBack.committedBaseline[1].armed, true, "legacy snapshot fallback: armed preserved")

    -- legacy single-kind snapshot with idsHeld (same shipID): must be promoted
    local lfSingleRecords = {
        { t = "session", phase = "engaged", controlMode = "direct",
          povAnchor = "turret", povMode = "manual",
          autoNextTarget = "1",
          shipID = "333", shipName = "Minotaur", aimTargetID = "", cameraMemberID = "" },
        { t = "snapshot", kind = "single", shipID = "333", componentID = "77",
          mode = "defend", armed = "0" },
    }
    local lfSingle = State.newSession("333", "gunnercontrol")
    lfSingle.shipName = "Minotaur"
    assert(State.restoreState(lfSingle, lfSingleRecords, {}), "legacy single snapshot idsHeld: restore ok")
    eq(#lfSingle.committedBaseline, 1, "legacy single snapshot idsHeld: promoted to committedBaseline")
    eq(lfSingle.committedBaseline[1].componentID, "77", "legacy single snapshot idsHeld: componentID preserved")
    eq(lfSingle.committedBaseline[1].armed, false, "legacy single snapshot idsHeld: armed=0 parsed as false")
end

-- Step 4: checkbox bound to TICK_MODE via stageMode and toggleGroup.
-- Covers the two stageMode checkbox-sync branches (lines 497-498, 500-506).

-- stageMode → tick: setting mode to TICK_MODE auto-ticks the group and records
-- preTickMode so an untick can restore the original mode.
do
    local sm = State.newSession(1, "g")
    sm.staged = { k = { mode = "defend", armed = true } }
    -- Setting to TICK_MODE on a non-TICK_MODE entry: ticks the group.
    State.stageMode(sm, "k", State.TICK_MODE, true)
    assert(sm.checkedGroupKeys["k"] == true, "stageMode→tick: checkedGroupKeys set")
    eq(sm.staged["k"].mode, State.TICK_MODE, "stageMode→tick: mode is TICK_MODE")
    eq(sm.staged["k"].preTickMode, "defend", "stageMode→tick: preTickMode records displaced mode")
    -- Setting to TICK_MODE again (already ticked): idempotent, preTickMode unchanged.
    State.stageMode(sm, "k", State.TICK_MODE, true)
    eq(sm.staged["k"].preTickMode, "defend", "stageMode→tick twice: preTickMode not overwritten")
end

-- stageMode → untick: setting mode away from TICK_MODE auto-unticks the group
-- and clears preTickMode, leaving the entry in the caller's chosen mode.
do
    local su = State.newSession(1, "g")
    su.staged = { k = { mode = State.TICK_MODE, armed = false } }
    su.checkedGroupKeys["k"] = true
    -- Setting away from TICK_MODE: unticks the group.
    State.stageMode(su, "k", "defend", false)
    assert(su.checkedGroupKeys["k"] == nil, "stageMode→untick: checkedGroupKeys cleared")
    eq(su.staged["k"].mode, "defend", "stageMode→untick: mode is the caller's choice")
    assert(su.staged["k"].preTickMode == nil, "stageMode→untick: preTickMode cleared")
    -- Confirm stageMode→untick on a group with a preTickMode in place: the
    -- caller's value wins, not preTickMode.
    su.staged["k2"] = { mode = State.TICK_MODE, armed = true, preTickMode = "missiledefence" }
    su.checkedGroupKeys["k2"] = true
    State.stageMode(su, "k2", "attack", true)
    eq(su.staged["k2"].mode, "attack", "stageMode→untick with preTickMode: caller's mode wins")
    assert(su.staged["k2"].preTickMode == nil, "stageMode→untick with preTickMode: preTickMode cleared")
end

-- toggleGroup tick: auto-sets staged mode to TICK_MODE, records preTickMode.
-- toggleGroup untick: restores preTickMode (or UNTICK_FALLBACK when none set).
do
    local tg = State.newSession(1, "g")
    tg.staged = { k = { mode = "defend", armed = true } }
    -- Tick.
    local ticked = State.toggleGroup(tg, "k", true)
    assert(ticked == true, "toggleGroup: first toggle returns true")
    assert(tg.checkedGroupKeys["k"] == true, "toggleGroup tick: key present")
    eq(tg.staged["k"].mode, State.TICK_MODE, "toggleGroup tick: mode set to TICK_MODE")
    eq(tg.staged["k"].preTickMode, "defend", "toggleGroup tick: preTickMode recorded")
    -- Untick (restores preTickMode).
    local unticked = State.toggleGroup(tg, "k", true)
    assert(unticked == false, "toggleGroup: second toggle returns false")
    assert(tg.checkedGroupKeys["k"] == nil, "toggleGroup untick: key cleared")
    eq(tg.staged["k"].mode, "defend", "toggleGroup untick: preTickMode restored")
    assert(tg.staged["k"].preTickMode == nil, "toggleGroup untick: preTickMode cleared")
    -- Untick from ticked-at-sit-down (no preTickMode): falls back to UNTICK_FALLBACK.
    tg.staged["k2"] = { mode = State.TICK_MODE, armed = true }  -- no preTickMode
    tg.checkedGroupKeys["k2"] = true
    State.toggleGroup(tg, "k2", true)
    eq(tg.staged["k2"].mode, State.UNTICK_FALLBACK,
        "toggleGroup untick without preTickMode: falls back to UNTICK_FALLBACK")
end

-- toggleAllGroups applies tick/untick side-effects to every group.
do
    local ta = State.newSession(1, "g")
    ta.groups = {
        { key = "m1", operationalCount = 1, totalCount = 1, armed = false },
        { key = "m2", operationalCount = 1, totalCount = 1, armed = true },
    }
    ta.staged = {
        m1 = { mode = "defend",  armed = false },
        m2 = { mode = "attack",  armed = true  },
    }
    -- Check all: both groups tick to TICK_MODE.
    State.toggleAllGroups(ta)
    eq(ta.staged["m1"].mode, State.TICK_MODE, "toggleAllGroups tick: m1 mode set")
    eq(ta.staged["m2"].mode, State.TICK_MODE, "toggleAllGroups tick: m2 mode set")
    eq(ta.staged["m1"].preTickMode, "defend",  "toggleAllGroups tick: m1 preTickMode saved")
    eq(ta.staged["m2"].preTickMode, "attack",  "toggleAllGroups tick: m2 preTickMode saved")
    -- Uncheck all: both groups untick restoring preTickMode.
    State.toggleAllGroups(ta)
    eq(ta.staged["m1"].mode, "defend",  "toggleAllGroups untick: m1 mode restored")
    eq(ta.staged["m2"].mode, "attack",  "toggleAllGroups untick: m2 mode restored")
    assert(ta.staged["m1"].preTickMode == nil, "toggleAllGroups untick: m1 preTickMode cleared")
    assert(ta.staged["m2"].preTickMode == nil, "toggleAllGroups untick: m2 preTickMode cleared")
    -- Partial select → fill up: only the previously-unchecked group ticks.
    ta.staged = { m1 = { mode = "defend", armed = false }, m2 = { mode = "attack", armed = true } }
    State.toggleGroup(ta, "m1", false)  -- check only m1
    State.toggleAllGroups(ta)  -- fills in m2
    assert(ta.checkedGroupKeys["m2"] == true, "toggleAllGroups partial→fill: m2 now checked")
    eq(ta.staged["m2"].mode, State.TICK_MODE, "toggleAllGroups partial→fill: m2 ticked to TICK_MODE")
    eq(ta.staged["m1"].preTickMode, "defend", "toggleAllGroups partial→fill: m1 preTickMode unchanged")
end

-- directedMode is a removed field: Direct-control now always uses attackenemies
-- (live-verified 2026-08-10), so nothing writes or reads it. A save taken by an
-- older build still carries the key, and validSessionRecord only checks known
-- keys rather than rejecting unknown ones, so such a payload must still restore.
-- Asserted rather than assumed: silently refusing an old save would strand a
-- player mid-engagement with no session to come back to.
do
    local live = {}
    local legacyRec = {
        { t = "session", phase = "engaged", controlMode = "direct",
          povAnchor = "turret", povMode = "manual",
          autoNextTarget = "1",
          shipID = "100", shipName = "Colossus", aimTargetID = "", cameraMemberID = "",
          directedMode = "autoassist" },
    }
    local restored = State.newSession("100", "gunnercontrol")
    restored.shipName = "Colossus"
    assert(State.restoreState(restored, legacyRec, live),
        "legacy payload carrying directedMode: restore accepted")
    assert(restored.directedMode == nil,
        "legacy directedMode must be ignored, not carried onto the live session")
    -- The field is no longer emitted at all.
    local dm = State.newSession("100", "gunnercontrol")
    dm.shipName = "Colossus"
    dm.phase, dm.controlMode = "engaged", "direct"
    assert(State.saveState(dm)[1].directedMode == nil,
        "saveState must not emit directedMode")
end

-- Direct-control policy: State.isDirectedMode.
assert(State.isDirectedMode("attackenemies"), "isDirectedMode: attackenemies is direct")
assert(State.isDirectedMode("autoassist"),   "isDirectedMode: autoassist is direct")
assert(not State.isDirectedMode("defend"),   "isDirectedMode: defend is ordinary")
assert(not State.isDirectedMode("attack"),   "isDirectedMode: attack is ordinary")
assert(not State.isDirectedMode(nil),        "isDirectedMode: nil is not direct")

-- Fresh session defaults directMode to "attackenemies".
do
    local s = State.newSession(1, "g")
    eq(s.directMode, "attackenemies", "newSession: default directMode is attackenemies")
end

-- seedBaseline: groups in either Direct-control mode come up checked and are
-- staged in the session's current (default) policy, not their original mode.
do
    local sb = State.newSession(77, "g")
    local atkGrp = { key = "group:C1:p:atk", kind = "group", componentID = 10,
        contextID = "C1", path = "p", group = "atk",
        mode = State.TICK_MODE, armed = true, operationalCount = 1, totalCount = 1 }
    local autoGrp = { key = "group:C1:p:auto", kind = "group", componentID = 11,
        contextID = "C1", path = "p", group = "auto",
        mode = "autoassist", armed = true, operationalCount = 1, totalCount = 1 }
    local ordGrp = { key = "group:C1:p:ord", kind = "group", componentID = 12,
        contextID = "C1", path = "p", group = "ord",
        mode = "defend", armed = false, operationalCount = 1, totalCount = 1 }
    State.seedBaseline(sb, { atkGrp, autoGrp, ordGrp })
    local atkKey   = State.groupKey("C1", "p", "atk")
    local autoKey  = State.groupKey("C1", "p", "auto")
    local ordKey   = State.groupKey("C1", "p", "ord")
    assert(sb.checkedGroupKeys[atkKey] == true,  "seedBaseline: attackenemies group is checked")
    assert(sb.checkedGroupKeys[autoKey] == true, "seedBaseline: autoassist group is checked")
    assert(sb.checkedGroupKeys[ordKey] == nil,   "seedBaseline: ordinary group is unchecked")
    -- Both direct groups are staged in the default policy (attackenemies).
    eq(sb.staged[atkKey].mode, State.TICK_MODE,  "seedBaseline: attackenemies staged in policy")
    eq(sb.staged[autoKey].mode, State.TICK_MODE, "seedBaseline: autoassist normalized to policy")
    eq(sb.staged[ordKey].mode, "defend",         "seedBaseline: ordinary stays ordinary")
    -- No preTickMode on seeded direct groups.
    assert(sb.staged[atkKey].preTickMode == nil,  "seedBaseline: no preTickMode for attackenemies seed")
    assert(sb.staged[autoKey].preTickMode == nil, "seedBaseline: no preTickMode for autoassist seed")
end

-- Ordinary tick/untick restoration.
do
    local s = State.newSession(1, "g")
    s.staged = { k = { mode = "defend", armed = true } }
    State.toggleGroup(s, "k", true)
    assert(s.checkedGroupKeys["k"] == true, "ordinary tick: checks the group")
    eq(s.staged["k"].mode, State.TICK_MODE, "ordinary tick: stages current policy")
    eq(s.staged["k"].preTickMode, "defend", "ordinary tick: records displaced ordinary mode")
    State.toggleGroup(s, "k", true)
    assert(s.checkedGroupKeys["k"] == nil,  "ordinary untick: clears the checkbox")
    eq(s.staged["k"].mode, "defend",       "ordinary untick: restores original mode")
    assert(s.staged["k"].preTickMode == nil, "ordinary untick: clears preTickMode")
end

-- Direct-mode-origin tick/untick falls back to defend.
do
    local s = State.newSession(1, "g")
    -- Group already in attackenemies (the default policy) but unchecked.
    -- applyTick should NOT record the directed mode as preTickMode.
    s.staged = { k = { mode = State.TICK_MODE, armed = true } }
    assert(s.checkedGroupKeys["k"] == nil, "setup: group is unchecked")
    State.toggleGroup(s, "k", true)  -- tick
    assert(s.checkedGroupKeys["k"] == true, "direct tick: group is checked")
    assert(s.staged["k"].preTickMode ~= State.TICK_MODE,
        "direct tick: preTickMode is not the directed mode")
    assert(s.staged["k"].preTickMode == nil,
        "direct tick: preTickMode is nil so untick falls back")
    State.toggleGroup(s, "k", true)  -- untick
    eq(s.staged["k"].mode, State.UNTICK_FALLBACK,
        "direct tick then untick: falls back to defend")
end

-- Policy change: attackenemies -> autoassist -> attackenemies while checked.
do
    local s = State.newSession(1, "g")
    s.staged = { k1 = { mode = "defend", armed = true } }
    assert(s.checkedGroupKeys["k1"] == nil, "policy setup: group is unchecked")
    State.toggleGroup(s, "k1", true)  -- tick into attackenemies
    eq(s.staged["k1"].mode, State.TICK_MODE, "policy: initial tick uses attackenemies")
    eq(s.directMode, "attackenemies", "policy: default is attackenemies")
    -- Switch to autoassist.
    local ok = State.setDirectMode(s, "autoassist")
    assert(ok, "policy: autoassist accepted")
    eq(s.directMode, "autoassist",   "policy: directMode changed")
    eq(s.staged["k1"].mode, "autoassist", "policy: checked group re-staged to new mode")
    -- Switch back to attackenemies.
    ok = State.setDirectMode(s, "attackenemies")
    assert(ok, "policy: attackenemies accepted")
    eq(s.directMode, "attackenemies", "policy: directMode changed back")
    eq(s.staged["k1"].mode, State.TICK_MODE, "policy: checked group re-staged back")
end

print("gunnery_state lifecycle tests passed")
