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
    -- Trim leading/trailing whitespace: vanilla XML pads group= attributes
    -- inconsistently (e.g. "group_front_up_left " or "  group_front_down_mid ").
    -- Only this entry point trims; engine-facing values stay byte-exact.
    local trimmed = string.match(identifier, "^%s*(.-)%s*$")
    if trimmed == nil or trimmed == "" then return nil end
    local name = string.lower(trimmed)
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
        -- Trim each token so any residual whitespace from interior padding
        -- cannot prevent the direction lookup from matching.
        token = string.match(token, "^%s*(.-)%s*$") or token
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

-- Returns true when v represents "no component": nil, plain 0, or the
-- LuaJIT cdata form "0ULL" / "0ull" that the FFI hands back for unset
-- UniverseID fields. All three mean the same thing at runtime; guards that
-- only test tostring(v) == "0" silently miss the cdata form.
function State.isNullID(v) return v == nil or normID(v) == "0" end

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
        -- Direct-control only: the ship-wide "prefer my target" override. Off
        -- until the player explicitly asks for it, and always cleared before
        -- the session ends. It reaches every turret on the ship rather than
        -- just the checked groups, which is why it is an explicit action with
        -- its own button and not a default.
        preferAllTurrets = false,
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
                if normID(member.componentID) == normID(session.selectedMemberID) and member.operational then
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

-- === Session persistence ===
--
-- Two paths lose the Lua session and must rebuild it from a value parked in an
-- MD cue variable: a save/load, and a UI hot-reload. Two engine facts set the
-- format, both live-confirmed 2026-08-08:
--
--   * MD -> Lua via raise_lua_event delivers ONE scalar. A table arrives as
--     nil, which is why restore has never worked. The payload is one string.
--   * contextID is reassigned on load (the same ship read 441090 before a save
--     and 2080707 after), so nothing addressed by contextID survives. path and
--     group names are stable and are what restore matches on.
--
-- A reload is the easy half of the same problem -- contextID is stable within a
-- session -- so serialising only the stable identifiers serves both, and just
-- the save/load case notices the re-resolution.

-- Vanilla turret group ids carry surrounding whitespace and positional words,
-- so there is no delimiter an arbitrary group id provably cannot contain.
-- Escape the four structural characters rather than betting on one.
local function escape(value)
    return (tostring(value):gsub("[%%;,=]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function unescape(value)
    return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

-- records: a list of flat maps. Records join with ";", fields with ",", and
-- key to value with "=". Not a general serialiser: flat string maps only.
function State.encode(records)
    local out = {}
    for _, record in ipairs(records or {}) do
        local fields = {}
        for key, value in pairs(record) do
            fields[#fields + 1] = escape(key) .. "=" .. escape(value)
        end
        -- pairs() order is undefined; sort so one table always encodes to one
        -- string and the round-trip test can assert on it.
        table.sort(fields)
        out[#out + 1] = table.concat(fields, ",")
    end
    return table.concat(out, ";")
end

function State.decode(encoded)
    local records = {}
    if type(encoded) ~= "string" or encoded == "" then return records end
    for chunk in (encoded .. ";"):gmatch("(.-);") do
        local record = {}
        for field in (chunk .. ","):gmatch("(.-),") do
            local key, value = field:match("^(.-)=(.*)$")
            if key then record[unescape(key)] = unescape(value) end
        end
        records[#records + 1] = record
    end
    return records
end

local function flag(value) return value and "1" or "0" end

-- Everything needed to put the player back where they were. Values are all
-- strings: this round-trips through MD, which has no Lua types.
function State.saveState(session)
    if not session then return {} end
    local records = { {
        t = "session",
        phase = session.phase or "console",
        controlMode = session.controlMode or "",
        povAnchor = session.povAnchor or "turret",
        povMode = session.povMode or "manual",
        autoNextTarget = flag(session.autoNextTarget ~= false),
        preferAllTurrets = flag(session.preferAllTurrets),
        shipID = tostring(session.shipID),
        -- Which ship this payload belongs to. shipID cannot answer that after a
        -- load, because a load reassigns it; the name survives.
        shipName = tostring(session.shipName or ""),
        -- The engine does not hand the soft target back: probed 2026-08-08, it
        -- read 0 immediately after a reload taken while a target was engaged.
        -- So the target travels in the payload instead of being re-read.
        aimTargetID = tostring(session.aimTargetID or ""),
        targetObjectID = tostring(session.targetObjectID or ""),
        -- ponytail: a componentID, so it resolves across a reload but not
        -- across a load. restoreState's caller falls back to the first
        -- operational member when it does not match anything live.
        cameraMemberID = tostring(session.cameraMemberID or ""),
    } }
    for _, snap in ipairs(State.snapshotsForSave(session.directSnapshots)) do
        local record = { t = "snapshot" }
        for key, value in pairs(snap) do
            record[key] = (type(value) == "boolean") and flag(value) or tostring(value)
        end
        records[#records + 1] = record
    end
    -- Checked groups travel as path+group only. group.key embeds contextID,
    -- which is precisely the value that does not survive a load.
    for _, group in ipairs(State.checkedGroups(session)) do
        records[#records + 1] = {
            t = "checked", path = group.path or "", group = group.group or "",
        }
    end
    return records
end

local function nameKey(path, group)
    -- "\0" cannot appear in an engine-supplied identifier, and this key never
    -- leaves this file, so it needs no escaping.
    return (path or "") .. "\0" .. (group or "")
end

-- Rebuilds `session` from decode()'s output. liveGroups is the freshly read
-- group list: every group is located by path+group and takes its contextID and
-- key from the live entry, never from the payload. Returns true when a session
-- record was present and belongs to this ship.
function State.restoreState(session, records, liveGroups)
    if not session or not records then return false end
    local head
    for _, record in ipairs(records) do
        if record.t == "session" then head = record; break end
    end
    if not head then return false end
    -- Groups are matched by name, and turret group names are the same on every
    -- ship of a class. Without a ship check, a payload left over from ship A
    -- would write A's saved modes onto whichever ship the player loads into.
    -- ponytail: two identically named ships would fool this. Nothing cheaper is
    -- stable across a load; reach for the idcode if it ever matters.
    local ourName = tostring(session.shipName or "")
    if head.shipName and head.shipName ~= "" and ourName ~= "" and head.shipName ~= ourName then
        return false
    end
    -- A UI reload keeps every id; a save/load reassigns them all. Same shipID
    -- means the same session, so componentIDs still address what they addressed
    -- when the payload was written. Different means every bare componentID in
    -- here now points at something arbitrary and must be dropped, not used.
    local idsHeld = head.shipID == tostring(session.shipID)
    local byName = {}
    for _, group in ipairs(liveGroups or {}) do
        byName[nameKey(group.path, group.group)] = group
    end
    local restored = false
    session.checkedGroupKeys = session.checkedGroupKeys or {}
    local snapshots = {}
    for _, record in ipairs(records) do
        if record.t == "session" then
            session.phase = record.phase or "console"
            session.controlMode = (record.controlMode ~= "" and record.controlMode) or nil
            session.povAnchor = record.povAnchor or "turret"
            session.povMode = record.povMode or "manual"
            session.autoNextTarget = record.autoNextTarget ~= "0"
            session.preferAllTurrets = record.preferAllTurrets == "1"
            if idsHeld then
                session.aimTargetID = (record.aimTargetID ~= "" and record.aimTargetID) or nil
                session.targetObjectID = (record.targetObjectID ~= "" and record.targetObjectID) or nil
                session.cameraMemberID = (record.cameraMemberID ~= "" and record.cameraMemberID) or nil
            end
            restored = true
        elseif record.t == "checked" then
            local live = byName[nameKey(record.path, record.group)]
            if live then session.checkedGroupKeys[live.key] = true end
        elseif record.t == "snapshot" then
            if record.kind == "single" then
                -- A single-turret snapshot is addressed only by componentID, so
                -- it is restorable across a reload and meaningless across a
                -- load. Dropping it loses one turret's original mode; keeping it
                -- would write that mode onto whatever inherited the id.
                if idsHeld then
                    snapshots[#snapshots + 1] = {
                        kind = "single", shipID = tostring(session.shipID),
                        componentID = record.componentID,
                        mode = record.mode, armed = record.armed == "1",
                    }
                end
            else
                local live = byName[nameKey(record.path, record.group)]
                if live then
                    -- The live shipID, not the payload's: a load reassigns it,
                    -- and restoreDirect refuses to write back any snapshot whose
                    -- shipID does not match the session's.
                    snapshots[#snapshots + 1] = {
                        kind = record.kind, shipID = tostring(session.shipID),
                        contextID = live.contextID, path = live.path,
                        group = live.group,
                        mode = record.mode, armed = record.armed == "1",
                    }
                end
            end
        end
    end
    session.directSnapshots = snapshots
    return restored
end

-- Mode and armed commands address a group by contextID+path+group, which
-- GetUpgradeGroups2 always reports exactly, so the only thing that can make a
-- group unwritable is having no operational turret left in it.
function State.canMutate(group)
    return group and (group.operationalCount or 0) > 0
end

function State.statusLabel(group)
    if not group or (group.operationalCount or 0) == 0 then return "destroyed" end
    if group.operationalCount < group.totalCount then return "damaged" end
    return "operational"
end

return X4GunneryState
