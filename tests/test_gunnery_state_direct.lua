local State = dofile("ui/gunnery_state.lua")
local function eq(a, b, label) assert(a == b, (label or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- Policy change preserves ordinary preTickMode on checked groups.
do
    local s = State.newSession(1, "g")
    s.staged = { k = { mode = "defend", armed = true, preTickMode = "attack" } }
    s.checkedGroupKeys["k"] = true
    State.setDirectMode(s, "autoassist")
    assert(s.staged["k"].preTickMode == "attack",
        "policy change: preserves existing preTickMode on checked group")
end

-- toggleAllGroups obeys current policy and preserves valid preTickMode.
do
    local s = State.newSession(1, "g")
    s.groups = {
        { key = "m1", operationalCount = 1, totalCount = 1, armed = false },
        { key = "m2", operationalCount = 1, totalCount = 1, armed = true },
    }
    s.staged = {
        m1 = { mode = "defend", armed = false },
        m2 = { mode = "attack", armed = true, preTickMode = "patrol" },
    }
    -- Select all: newly-ticked group uses current policy; already-checked keeps preTickMode.
    State.toggleGroup(s, "m2", true)  -- check m2 first
    eq(State.toggleAllGroups(s), true, "toggleAll: partial -> select all")
    eq(s.staged["m1"].mode, State.TICK_MODE, "toggleAll: new tick uses current policy")
    eq(s.staged["m2"].preTickMode, "patrol", "toggleAll: existing preTickMode preserved")
    -- Deselect all.
    eq(State.toggleAllGroups(s), false, "toggleAll: select all -> deselect all")
    assert(next(s.checkedGroupKeys) == nil, "toggleAll: all unchecked")
end

-- Explicit ordinary stageMode removes membership.
do
    local s = State.newSession(1, "g")
    s.staged = { k = { mode = State.TICK_MODE, armed = true } }
    s.checkedGroupKeys["k"] = true
    State.stageMode(s, "k", "defend", true)
    assert(s.checkedGroupKeys["k"] == nil, "stageMode ordinary: unchecked on ordinary mode")
    eq(s.staged["k"].mode, "defend",      "stageMode ordinary: stages explicit mode")
    assert(s.staged["k"].preTickMode == nil, "stageMode ordinary: clears preTickMode")
end

-- Choosing the OTHER Direct-control engine mode via stageMode is a no-op for
-- membership and staged mode.
do
    local s = State.newSession(1, "g")
    s.directMode = "attackenemies"
    s.staged = { k = { mode = State.TICK_MODE, armed = true } }
    s.checkedGroupKeys["k"] = true
    -- Try to switch to autoassist via stageMode.
    State.stageMode(s, "k", "autoassist", true)
    assert(s.checkedGroupKeys["k"] == true,  "other-direct stageMode: membership unchanged")
    eq(s.staged["k"].mode, State.TICK_MODE, "other-direct stageMode: staged mode unchanged")
    -- Unchecked group in ordinary mode: other-direct is also a no-op.
    s.checkedGroupKeys = {}
    s.staged = { k2 = { mode = "defend", armed = false } }
    State.stageMode(s, "k2", "autoassist", false)
    assert(s.checkedGroupKeys["k2"] == nil,  "other-direct stageMode unchecked: no check")
    eq(s.staged["k2"].mode, "defend",       "other-direct stageMode unchecked: mode unchanged")
end

-- checkpoint then untick -> defend (preTickMode cleared by commit).
do
    local s = State.newSession(1, "g")
    s.groups = { { key = "g1", operationalCount = 1, totalCount = 1 } }
    s.staged = { g1 = { mode = "defend", armed = true, preTickMode = "attack" } }
    s.checkedGroupKeys["g1"] = true
    State.commitStagedToBaseline(s)
    assert(s.staged["g1"].preTickMode == nil,
        "checkpoint: clears preTickMode on checked group")
    State.toggleGroup(s, "g1", true)
    eq(s.staged["g1"].mode, State.UNTICK_FALLBACK,
        "checkpoint then untick: falls back to defend")
end

-- save/load before checkpoint preserves a valid ordinary preTickMode.
do
    local saved = State.newSession("400", "gunnercontrol")
    saved.shipName = "Titan"
    saved.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    saved.checkedGroupKeys["group:OLD:p:g"] = true
    saved.staged = { ["group:OLD:p:g"] = { mode = State.TICK_MODE, armed = true, preTickMode = "attack" } }
    saved.committedBaseline = {
        { kind = "group", shipID = "400", contextID = "OLD", path = "p", group = "g",
          mode = "defend", armed = true },
    }
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("400", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "save/load before checkpoint: restore succeeds")
    eq(loaded.directMode, "attackenemies", "save/load before cp: default policy restored")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "save/load before checkpoint: checked group remains checked")
    eq(loaded.staged[loadKey].mode, State.TICK_MODE,
        "save/load before checkpoint: staged in policy mode")
    eq(loaded.staged[loadKey].preTickMode, "attack",
        "save/load before checkpoint: persisted ordinary preTickMode survives")
end

-- save/load after checkpoint does not restore old preTickMode.
do
    local saved = State.newSession("401", "gunnercontrol")
    saved.shipName = "Titan"
    saved.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = State.TICK_MODE, armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    saved.checkedGroupKeys["group:OLD:p:g"] = true
    saved.staged = { ["group:OLD:p:g"] = { mode = State.TICK_MODE, armed = true } }
    saved.committedBaseline = {
        { kind = "group", shipID = "401", contextID = "OLD", path = "p", group = "g",
          mode = State.TICK_MODE, armed = true },
    }
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("401", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "save/load after checkpoint: restore succeeds")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "save/load after checkpoint: checked group remains checked")
    eq(loaded.staged[loadKey].mode, State.TICK_MODE,
        "save/load after checkpoint: staged in policy mode")
    assert(loaded.staged[loadKey].preTickMode == nil,
        "save/load after checkpoint: preTickMode NOT restored (baseline was directed)")
end

-- active save/load restores autoassist policy.
do
    local saved = State.newSession("402", "gunnercontrol")
    saved.shipName = "Titan"
    saved.directMode = "autoassist"
    saved.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    saved.checkedGroupKeys["group:OLD:p:g"] = true
    saved.staged = { ["group:OLD:p:g"] = { mode = "autoassist", armed = true, preTickMode = "attack" } }
    saved.committedBaseline = {
        { kind = "group", shipID = "402", contextID = "OLD", path = "p", group = "g",
          mode = "defend", armed = true },
    }
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("402", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "active save/load autoassist: restore succeeds")
    eq(loaded.directMode, "autoassist",
        "active save/load: autoassist policy restored")
    local loadKey = "group:NEW:p:g"
    eq(loaded.staged[loadKey].mode, "autoassist",
        "active save/load: checked group staged in restored policy")
    eq(loaded.staged[loadKey].preTickMode, "attack",
        "active save/load: persisted ordinary preTickMode survives autoassist policy")
end

-- legacy payload without directMode defaults to attackenemies.
do
    local legacyRecords = {
        { t = "session", phase = "engaged", controlMode = "direct",
          povAnchor = "turret", povMode = "manual",
          autoNextTarget = "1",
          shipID = "403", shipName = "Titan", aimTargetID = "", cameraMemberID = "" },
        { t = "baseline", kind = "group", shipID = "403", contextID = "OLD",
          path = "p", group = "g", mode = "defend", armed = "1" },
        { t = "checked", path = "p", group = "g" },
    }
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("403", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, legacyRecords, liveGroups),
        "legacy payload without policy: restore succeeds")
    eq(loaded.directMode, "attackenemies",
        "legacy payload: defaults to attackenemies")
end

-- setDirectMode rejects invalid values.
do
    local s = State.newSession(1, "g")
    assert(not State.setDirectMode(s, "defend"),   "setDirectMode: reject ordinary mode")
    assert(not State.setDirectMode(s, "attack"),  "setDirectMode: reject unknown mode")
    assert(not State.setDirectMode(s, ""),         "setDirectMode: reject empty string")
    assert(not State.setDirectMode(s, nil),        "setDirectMode: reject nil")
    eq(s.directMode, "attackenemies", "setDirectMode: policy unchanged on rejection")
end

-- setDirectMode is a no-op when the mode is already active.
do
    local s = State.newSession(1, "g")
    assert(not State.setDirectMode(s, "attackenemies"),
        "setDirectMode: no-op when already attackenemies")
end

-- Exact preTick round trip via normal stageMode/toggleGroup path.
-- baseline=defend, player stages ordinary mode=attack, then ticks the group,
-- then save/load must preserve that exact preTickMode so untick restores it.
do
    local rt = State.newSession("500", "gunnercontrol")
    rt.shipName = "Titan"
    rt.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    State.seedBaseline(rt, rt.groups)
    eq(rt.staged["group:OLD:p:g"].mode, "defend", "round-trip setup: baseline seeded")
    -- Stage an ordinary mode via the normal dropdown path; group stays unchecked.
    State.stageMode(rt, "group:OLD:p:g", "attack", true)
    eq(rt.staged["group:OLD:p:g"].mode, "attack", "round-trip setup: ordinary mode staged")
    assert(rt.checkedGroupKeys["group:OLD:p:g"] == nil,
        "round-trip setup: group is still unchecked after staging ordinary mode")
    -- Tick the group: applyTick records the current staged mode as preTickMode.
    State.toggleGroup(rt, "group:OLD:p:g", true)
    eq(rt.staged["group:OLD:p:g"].mode, State.TICK_MODE,
        "round-trip setup: ticked into policy mode")
    eq(rt.staged["group:OLD:p:g"].preTickMode, "attack",
        "round-trip setup: preTickMode records the displaced ordinary mode")
    assert(rt.checkedGroupKeys["group:OLD:p:g"] == true,
        "round-trip setup: group is now checked")
    -- Save and load.
    local payload = State.encode(State.saveState(rt))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("500", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "round-trip: restore succeeds")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "round-trip: checked group remains checked after save/load")
    eq(loaded.staged[loadKey].mode, State.TICK_MODE,
        "round-trip: staged in policy mode after restore")
    eq(loaded.staged[loadKey].preTickMode, "attack",
        "round-trip: persisted preTickMode survives save/load")
    -- Untick restores the exact saved ordinary mode.
    State.toggleGroup(loaded, loadKey, true)
    eq(loaded.staged[loadKey].mode, "attack",
        "round-trip: untick restores the exact persisted preTickMode")
    assert(loaded.checkedGroupKeys[loadKey] == nil,
        "round-trip: checkbox cleared after untick")
end

-- After checkpoint: commit clears preTickMode; subsequent save/load must not
-- resurrect it. Untick falls back to defend.
do
    local postCp = State.newSession("501", "gunnercontrol")
    postCp.shipName = "Titan"
    postCp.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    State.seedBaseline(postCp, postCp.groups)
    State.stageMode(postCp, "group:OLD:p:g", "attack", true)
    State.toggleGroup(postCp, "group:OLD:p:g", true)
    eq(postCp.staged["group:OLD:p:g"].preTickMode, "attack",
        "post-checkpoint setup: preTickMode set before commit")
    -- Commit (checkpoint): this clears preTickMode on checked groups.
    State.commitStagedToBaseline(postCp)
    assert(postCp.staged["group:OLD:p:g"].preTickMode == nil,
        "post-checkpoint setup: commit cleared preTickMode")
    -- Save and load after checkpoint.
    local payload = State.encode(State.saveState(postCp))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("501", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "post-checkpoint: restore succeeds")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "post-checkpoint: checked group remains checked after save/load")
    eq(loaded.staged[loadKey].mode, State.TICK_MODE,
        "post-checkpoint: staged in policy mode")
    assert(loaded.staged[loadKey].preTickMode == nil,
        "post-checkpoint: preTickMode NOT resurrected after commit+save/load")
    -- Untick falls back to defend (no persisted preTickMode to restore).
    State.toggleGroup(loaded, loadKey, true)
    eq(loaded.staged[loadKey].mode, State.UNTICK_FALLBACK,
        "post-checkpoint: untick falls back to defend, old attack history is not restored")
end

-- Legacy payload without preTick records still restores safely using the
-- existing baseline-derived fallback behaviour.
do
    local legacyPt = { t = "session", phase = "engaged", controlMode = "direct",
        povAnchor = "turret", povMode = "manual", autoNextTarget = "1",
        shipID = "502", shipName = "Titan", aimTargetID = "", cameraMemberID = "" }
    local legacyRecords = {
        legacyPt,
        { t = "baseline", kind = "group", shipID = "502", contextID = "OLD",
          path = "p", group = "g", mode = "defend", armed = "1" },
        { t = "checked", path = "p", group = "g" },
    }
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("502", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, legacyRecords, liveGroups),
        "legacy without preTick: restore succeeds")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "legacy without preTick: checked group remains checked")
    eq(loaded.staged[loadKey].mode, State.TICK_MODE,
        "legacy without preTick: staged in default policy mode")
    -- With no persisted preTickMode the safe fallback is UNTICK_FALLBACK;
    -- untick falls back to defend rather than resurrecting a stale mode.
    assert(loaded.staged[loadKey].preTickMode == nil,
        "legacy without preTick: no preTickMode; untick falls back to defend")
end

-- Issue #48 Task 4: Direct-control persistence, checkpoint, teardown,
-- and legacy compatibility. The cases above prove the transport pieces;
-- these round trips each prove one whole required behaviour end to end,
-- asserting every element that must survive together.

-- Active Direct save/load under attackenemies restores checked membership,
-- the policy, the committed baseline (not the temporary Direct state), and a
-- valid ordinary preTickMode; a later untick returns the ordinary mode.
do
    local saved = State.newSession("600", "gunnercontrol")
    saved.shipName = "Behemoth"
    saved.phase, saved.controlMode = "engaged", "direct"
    saved.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    State.seedBaseline(saved, saved.groups)
    State.stageMode(saved, "group:OLD:p:g", "attack", true)
    State.toggleGroup(saved, "group:OLD:p:g", true)
    eq(saved.staged["group:OLD:p:g"].preTickMode, "attack", "task4 active setup: ordinary preTickMode recorded")
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("600", "gunnercontrol")
    loaded.shipName = "Behemoth"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "task4 active attackenemies: restore succeeds")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "task4 active attackenemies: checked membership restored")
    eq(loaded.directMode, "attackenemies", "task4 active attackenemies: policy restored")
    eq(#loaded.committedBaseline, 1, "task4 active attackenemies: committed baseline restored")
    eq(loaded.committedBaseline[1].mode, "defend",
        "task4 active attackenemies: committed baseline keeps the pre-engage mode, not the temporary Direct state")
    eq(loaded.committedBaseline[1].armed, true, "task4 active attackenemies: committed baseline armed restored")
    eq(loaded.staged[loadKey].mode, State.TICK_MODE, "task4 active attackenemies: checked group staged in the policy")
    eq(loaded.staged[loadKey].preTickMode, "attack", "task4 active attackenemies: valid ordinary preTickMode restored")
    State.toggleGroup(loaded, loadKey, true)
    eq(loaded.staged[loadKey].mode, "attack",
        "task4 active attackenemies: untick after restore returns the ordinary mode")
    assert(loaded.checkedGroupKeys[loadKey] == nil, "task4 active attackenemies: untick clears membership")
end

-- The same active save/load round trip under the autoassist policy: the
-- restored session must stage the checked group in autoassist, keep the
-- committed baseline intact, and let a later untick restore the ordinary mode.
do
    local saved = State.newSession("601", "gunnercontrol")
    saved.shipName = "Behemoth"
    saved.directMode = "autoassist"
    saved.phase, saved.controlMode = "engaged", "direct"
    saved.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    State.seedBaseline(saved, saved.groups)
    State.stageMode(saved, "group:OLD:p:g", "attack", true)
    State.toggleGroup(saved, "group:OLD:p:g", true)
    eq(saved.staged["group:OLD:p:g"].mode, "autoassist", "task4 active autoassist setup: tick stages the policy")
    eq(saved.staged["group:OLD:p:g"].preTickMode, "attack", "task4 active autoassist setup: ordinary preTickMode recorded")
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("601", "gunnercontrol")
    loaded.shipName = "Behemoth"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "task4 active autoassist: restore succeeds")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "task4 active autoassist: checked membership restored")
    eq(loaded.directMode, "autoassist", "task4 active autoassist: policy restored")
    eq(#loaded.committedBaseline, 1, "task4 active autoassist: committed baseline restored")
    eq(loaded.committedBaseline[1].mode, "defend",
        "task4 active autoassist: committed baseline keeps the pre-engage mode, not the temporary Direct state")
    eq(loaded.committedBaseline[1].armed, true, "task4 active autoassist: committed baseline armed restored")
    eq(loaded.staged[loadKey].mode, "autoassist", "task4 active autoassist: checked group staged in the restored policy")
    eq(loaded.staged[loadKey].preTickMode, "attack", "task4 active autoassist: valid ordinary preTickMode restored")
    State.toggleGroup(loaded, loadKey, true)
    eq(loaded.staged[loadKey].mode, "attack",
        "task4 active autoassist: untick after restore returns the ordinary mode")
    assert(loaded.checkedGroupKeys[loadKey] == nil, "task4 active autoassist: untick clears membership")
end

-- "Update turret behavior" is one action with two observable effects that a
-- single scenario must prove together: committedBaseline advances to the
-- staged Direct state AND the checked group's preTickMode is cleared, so a
-- later untick uses the Defend fallback instead of resurrecting the displaced
-- ordinary mode.
do
    local s = State.newSession("602", "gunnercontrol")
    s.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    State.seedBaseline(s, s.groups)
    State.stageMode(s, "group:OLD:p:g", "attack", true)
    State.toggleGroup(s, "group:OLD:p:g", true)
    eq(s.staged["group:OLD:p:g"].preTickMode, "attack", "task4 checkpoint setup: preTickMode before the commit")
    State.commitStagedToBaseline(s)
    eq(s.committedBaseline[1].mode, State.TICK_MODE,
        "task4 checkpoint: committedBaseline advances to the staged Direct mode")
    eq(s.committedBaseline[1].armed, true, "task4 checkpoint: committedBaseline advances armed with the staged state")
    assert(s.staged["group:OLD:p:g"].preTickMode == nil, "task4 checkpoint: preTickMode cleared on the checked group")
    assert(not State.isStagedDirty(s), "task4 checkpoint: session is clean after the commit")
    State.toggleGroup(s, "group:OLD:p:g", true)
    eq(s.staged["group:OLD:p:g"].mode, State.UNTICK_FALLBACK,
        "task4 checkpoint: untick after the commit uses the Defend fallback")
end

-- A save/load taken after the checkpoint must not resurrect the cleared
-- preTickMode, and a later untick uses Defend -- under the autoassist policy
-- as well, so the fallback is proven policy-independent.
do
    local saved = State.newSession("603", "gunnercontrol")
    saved.shipName = "Behemoth"
    saved.directMode = "autoassist"
    saved.phase, saved.controlMode = "engaged", "direct"
    saved.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    State.seedBaseline(saved, saved.groups)
    State.stageMode(saved, "group:OLD:p:g", "attack", true)
    State.toggleGroup(saved, "group:OLD:p:g", true)
    State.commitStagedToBaseline(saved)
    assert(saved.staged["group:OLD:p:g"].preTickMode == nil,
        "task4 post-cp autoassist setup: the commit cleared preTickMode")
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("603", "gunnercontrol")
    loaded.shipName = "Behemoth"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "task4 post-cp autoassist: restore succeeds")
    local loadKey = "group:NEW:p:g"
    eq(loaded.directMode, "autoassist", "task4 post-cp autoassist: policy restored")
    assert(loaded.checkedGroupKeys[loadKey] == true, "task4 post-cp autoassist: checked membership restored")
    eq(loaded.committedBaseline[1].mode, "autoassist",
        "task4 post-cp autoassist: the committed Direct mode is now the baseline")
    assert(loaded.staged[loadKey].preTickMode == nil,
        "task4 post-cp autoassist: the checkpointed preTickMode is not resurrected")
    State.toggleGroup(loaded, loadKey, true)
    eq(loaded.staged[loadKey].mode, State.UNTICK_FALLBACK,
        "task4 post-cp autoassist: untick after the checkpoint uses Defend")
end

-- Resolver seam: tick/restaging uses the resolver rather than blindly copying
-- session.directMode. A focused test substitutes a pure resolver to return
-- different effective modes for two checked group keys and proves membership
-- remains unchanged while each staged mode follows its resolved result.
do
    local rs = State.newSession(1, "g")
    rs.staged = {
        k1 = { mode = "defend", armed = true },
        k2 = { mode = "attack",  armed = false },
    }
    -- Save the original resolver.
    local origResolveDirectMode = State.resolveDirectMode
    -- Substitute a resolver that returns different effective modes per key.
    function State.resolveDirectMode(_, groupKey)
        if groupKey == "k1" then return "autoassist"
        elseif groupKey == "k2" then return "attackenemies"
        else return State.TICK_MODE end
    end
    -- Tick both groups via toggleGroup: applyTick must call the resolver.
    State.toggleGroup(rs, "k1", true)
    State.toggleGroup(rs, "k2", true)
    assert(rs.checkedGroupKeys["k1"] == true,  "resolver: k1 checked")
    assert(rs.checkedGroupKeys["k2"] == true,  "resolver: k2 checked")
    eq(rs.staged["k1"].mode, "autoassist", "resolver: k1 staged in its resolved mode")
    eq(rs.staged["k2"].mode, "attackenemies", "resolver: k2 staged in its resolved mode")
    -- setDirectMode must also resolve each group independently.
    State.setDirectMode(rs, "autoassist")
    assert(rs.checkedGroupKeys["k1"] == true,  "resolver: k1 still checked after policy change")
    assert(rs.checkedGroupKeys["k2"] == true,  "resolver: k2 still checked after policy change")
    eq(rs.staged["k1"].mode, "autoassist", "resolver: k1 re-staged to its resolved mode")
    eq(rs.staged["k2"].mode, "attackenemies", "resolver: k2 re-staged to its resolved mode")
    -- Restore original resolver.
    State.resolveDirectMode = origResolveDirectMode
end


print("gunnery_state direct tests passed")
