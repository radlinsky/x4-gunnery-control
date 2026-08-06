-- Pure session/view-model helpers. This file deliberately has no X4 FFI calls so
-- it can be checked with stock Lua 5.1.
X4GunneryState = X4GunneryState or {}
local State = X4GunneryState

function State.singleKey(componentID)
    return "single:" .. tostring(componentID)
end

function State.groupKey(contextID, path, group)
    return table.concat({ "group", tostring(contextID), path or "", group or "" }, ":")
end

function State.memberKey(componentID)
    return "member:" .. tostring(componentID)
end

-- Convert the directional names used by vanilla turret groups into a concise
-- label. Unknown identifiers intentionally remain unlabeled: guessing at an
-- opaque group name is less useful than displaying its original value.
function State.turretGroupLabel(identifier)
    if type(identifier) ~= "string" then return nil end
    local name = string.lower(identifier)
    if not string.match(name, "^group_") then return nil end

    local directions = {
        front = { slot = "depth", label = "Front" },
        back = { slot = "depth", label = "Rear" },
        rear = { slot = "depth", label = "Rear" },
        mid = { slot = "center", label = "Center" },
        middle = { slot = "center", label = "Center" },
        center = { slot = "center", label = "Center" },
        up = { slot = "vertical", label = "Upper" },
        upper = { slot = "vertical", label = "Upper" },
        top = { slot = "vertical", label = "Upper" },
        bottom = { slot = "vertical", label = "Lower" },
        lower = { slot = "vertical", label = "Lower" },
        down = { slot = "vertical", label = "Lower" },
        left = { slot = "lateral", label = "Left" },
        right = { slot = "lateral", label = "Right" },
        inside = { slot = "radial", label = "Inner" },
        outside = { slot = "radial", label = "Outer" },
    }
    local slots = {}
    for token in string.gmatch(name, "[^_]+") do
        local word, suffix = string.match(token, "^(%a+)(%d*)$")
        local direction = word and directions[word]
        if direction and not slots[direction.slot] then
            slots[direction.slot] = direction.label .. (suffix ~= "" and " " .. suffix or "")
        end
    end

    local result = {}
    for _, slot in ipairs({ "depth", "center", "vertical", "lateral", "radial" }) do
        if slots[slot] then result[#result + 1] = slots[slot] end
    end
    return #result > 0 and table.concat(result, " ") or nil
end

-- Strip trailing C integer-literal suffixes (ULL, LL, ull, ll, etc.) so that
-- IDs arriving via FFI ("463766ULL") and via the project's id() helper
-- ("463766") compare equal. Works on strings and numbers; returns a string.
-- X4 IDs do not stringify consistently: values routed through the runtime's
-- id() conversion print as 463766 while raw FFI values print as 463766ULL, so
-- a bare tostring comparison judged the same ship to be two different objects.
-- Parenthesised so gsub's second return value (the substitution count) cannot
-- leak to a caller that expands multiple results.
local function normID(v)
    return (tostring(v):gsub("[Uu]?[Ll][Ll]$", ""))
end
-- Exported because the runtime's sameID() compares across the same boundary:
-- targetRoot() hands back a raw FFI id, id() hands back a converted one.
State.normID = normID

-- A surface element belongs to the ship/station returned by targetRoot(). The
-- occupied ship and its own surfaces must never appear as engagement targets;
-- other player-owned objects remain selectable so the UI reflects what X4 can
-- target, even though normal turret AI may refuse to fire on them.
function State.isEngagementTargetAllowed(shipID, targetRootID)
    if shipID == nil or targetRootID == nil then return false end
    if normID(targetRootID) == "0" then return false end
    return normID(shipID) ~= normID(targetRootID)
end

function State.isReturnablePlayerView(mode)
    return mode == "cockpit" or mode == "external" or mode == "firstperson" or mode == "externalfirstperson"
end

-- Lifecycle is deliberately independent from the visible Gunnery Control
-- phase. X4 can remove a Helper frame when another menu opens; retaining a
-- phase alone must never be interpreted as retaining input/view ownership.
State.lifecycle = {
    owned = "owned",
    suspendingMap = "suspending_map",
    suspendedMap = "suspended_map",
    reopening = "reopening",
}

function State.setLifecycle(session, lifecycle)
    if session then session.lifecycle = lifecycle end
end

function State.isOwned(session)
    return session ~= nil and session.lifecycle == State.lifecycle.owned
end

function State.isMapSuspended(session)
    return session ~= nil and (session.lifecycle == State.lifecycle.suspendingMap
        or session.lifecycle == State.lifecycle.suspendedMap
        or session.lifecycle == State.lifecycle.reopening)
end

function State.newSession(shipID, controlGroup)
    return {
        active = true, shipID = shipID, controlGroup = controlGroup,
        lifecycle = State.lifecycle.owned,
        phase = "console", groups = {}, expanded = {},
        checkedGroupKeys = {}, controlMode = nil,
        povAnchor = "turret", povMode = "manual",
        cameraIndex = 1, aimTargetID = nil,
        -- Direct-control only: take the turrets to the next target when the
        -- engaged one dies. Off sends the player back to the target browser.
        autoNextTarget = true,
        directSnapshots = {},
        selectedGroupKey = nil, selectedMemberID = nil, cameraMemberID = nil,
        targetObjectID = nil, targetCandidates = {},
    }
end

function State.beginTargetSelection(session, group, member)
    session.phase = "target_select"
    session.selectedGroupKey, session.selectedMemberID = group.key, member.componentID
    session.cameraMemberID, session.targetObjectID = member.componentID, nil
end

-- Finds the entry in `entries` whose .componentID matches `currentID` by
-- tostring() comparison, steps by `delta` (circular), and returns the next
-- entry. When currentID is nil or absent, returns entries[1]. Returns nil for
-- an empty list.
function State.cycleEntry(entries, currentID, delta)
    if #entries == 0 then return nil end
    if currentID == nil then return entries[1] end
    local idx = nil
    for i, e in ipairs(entries) do
        if normID(e.componentID) == normID(currentID) then idx = i; break end
    end
    if idx == nil then return entries[1] end
    idx = ((idx - 1 + delta) % #entries) + 1
    return entries[idx]
end

function State.firstOperationalMember(groups)
    for _, group in ipairs(groups or {}) do
        for _, member in ipairs(group.members or {}) do
            if member.operational then return group.key, member.componentID end
        end
    end
end

function State.retainSelection(session, groups)
    session.groups = groups or {}
    -- Prune checked keys whose group no longer exists (turrets can be destroyed).
    local existing = {}
    for _, group in ipairs(session.groups) do existing[group.key] = true end
    for key in pairs(session.checkedGroupKeys or {}) do
        if not existing[key] then session.checkedGroupKeys[key] = nil end
    end
    local selectedGroup, selectedMember
    for _, group in ipairs(session.groups) do
        if group.key == session.selectedGroupKey then
            selectedGroup = group
            for _, member in ipairs(group.members) do
                if member.componentID == session.selectedMemberID and member.operational then
                    selectedMember = member
                    break
                end
            end
        end
    end
    if not selectedMember then
        local groupKey, memberID = State.firstOperationalMember(session.groups)
        session.selectedGroupKey, session.selectedMemberID = groupKey, memberID
    end
end

function State.toggleGroup(session, groupKey)
    if session.checkedGroupKeys[groupKey] then
        session.checkedGroupKeys[groupKey] = nil
        return false
    else
        session.checkedGroupKeys[groupKey] = true
        return true
    end
end

-- True when every mutable group is checked (and there is at least one).
function State.allGroupsChecked(session)
    local any = false
    for _, group in ipairs(session.groups or {}) do
        if State.canMutate(group) then
            if not session.checkedGroupKeys[group.key] then return false end
            any = true
        end
    end
    return any
end

-- Select-all checkbox: check every mutable group, or clear the selection when
-- they are already all checked. Returns the new checked state.
function State.toggleAllGroups(session)
    if State.allGroupsChecked(session) then
        session.checkedGroupKeys = {}
        return false
    end
    for _, group in ipairs(session.groups or {}) do
        if State.canMutate(group) then session.checkedGroupKeys[group.key] = true end
    end
    return true
end

function State.checkedGroups(session)
    local result = {}
    for _, group in ipairs(session.groups or {}) do
        if session.checkedGroupKeys[group.key] then
            result[#result + 1] = group
        end
    end
    return result
end

-- Returns every operational member of every checked group, in session.groups
-- order then group.members order. Each entry is the member table plus groupKey.
function State.cameraRoster(session)
    local result = {}
    for _, group in ipairs(session.groups or {}) do
        if session.checkedGroupKeys[group.key] then
            for _, member in ipairs(group.members or {}) do
                if member.operational then
                    -- Shallow-copy member so we can attach groupKey without
                    -- mutating the source table.
                    local entry = {}
                    for k, v in pairs(member) do entry[k] = v end
                    entry.groupKey = group.key
                    result[#result + 1] = entry
                end
            end
        end
    end
    return result
end

-- Moves cameraIndex by delta over cameraRoster (circular). Clamps a stale
-- index before moving. Sets session.cameraMemberID. Returns the member or nil.
function State.cycleCamera(session, delta)
    local roster = State.cameraRoster(session)
    if #roster == 0 then
        session.cameraMemberID = nil
        return nil
    end
    -- Clamp stale index into valid range before applying delta.
    local idx = session.cameraIndex or 1
    if idx < 1 or idx > #roster then idx = 1 end
    idx = ((idx - 1 + delta) % #roster) + 1
    session.cameraIndex = idx
    local m = roster[idx]
    session.cameraMemberID = m.componentID
    return m
end

-- Replaces beginWatch and beginDirect. Sets phase to "engaged" and
-- controlMode. For "auto" produces no snapshots; for "direct" builds one
-- snapshot per group and stores the list in session.directSnapshots.
function State.beginEngaged(session, groups, controlMode)
    session.phase = "engaged"
    session.controlMode = controlMode
    session.cameraIndex = 1
    -- The camera always enters on the turret in manual mode; record that so the
    -- panel greys the button matching the view actually shown, even when an
    -- earlier visit left povAnchor on "target".
    session.povAnchor, session.povMode = "turret", "manual"
    -- Set cameraMemberID to the first roster member (nil if none).
    local roster = State.cameraRoster(session)
    session.cameraMemberID = roster[1] and roster[1].componentID or nil
    if controlMode == "direct" then
        local snaps = {}
        for _, group in ipairs(groups or {}) do
            snaps[#snaps + 1] = {
                shipID = session.shipID, kind = group.kind,
                componentID = group.componentID, contextID = group.contextID,
                path = group.path, group = group.group,
                mode = group.mode, armed = group.armed,
            }
        end
        session.directSnapshots = snaps
        return snaps
    else
        session.directSnapshots = {}
        return session.directSnapshots
    end
end

function State.returnToConsole(session)
    session.phase = "console"
    session.controlMode = nil
    session.povMode = "manual"
    session.cameraMemberID, session.targetObjectID = nil, nil
end

-- Returns session.directSnapshots (possibly empty), resets it to {}, and if
-- phase is "engaged" sets phase back to "console". Never returns nil.
function State.releaseDirect(session)
    local snaps = session.directSnapshots or {}
    session.directSnapshots = {}
    if session.phase == "engaged" then session.phase = "console" end
    return snaps
end

-- Mission Director values must not retain LuaJIT cdata references. Copy only
-- the identifiers used to locate the overridden group after a save/load.
function State.snapshotForSave(snapshot)
    if not snapshot then return nil end
    local result = {
        shipID = tostring(snapshot.shipID), kind = snapshot.kind,
        mode = snapshot.mode or "", armed = snapshot.armed and true or false,
    }
    if snapshot.kind == "single" then
        result.componentID = tostring(snapshot.componentID)
    else
        result.contextID = tostring(snapshot.contextID)
        result.path = snapshot.path or ""
        result.group = snapshot.group or ""
    end
    return result
end

-- Maps snapshotForSave over a list. Accepts a legacy single snapshot (table
-- with .shipID and no [1]) and returns a one-element list, for saves made
-- before this rework.
function State.snapshotsForSave(list)
    -- Legacy: a single snapshot has .shipID but no numeric index.
    if list and list.shipID ~= nil and list[1] == nil then
        return { State.snapshotForSave(list) }
    end
    local result = {}
    for _, snap in ipairs(list or {}) do
        result[#result + 1] = State.snapshotForSave(snap)
    end
    return result
end

function State.canMutate(group)
    return group and not group.ambiguous and (group.operationalCount or 0) > 0
end

function State.statusLabel(group)
    if not group or (group.operationalCount or 0) == 0 then return "destroyed" end
    if group.operationalCount < group.totalCount then return "damaged" end
    return "operational"
end

return X4GunneryState
