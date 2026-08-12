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
        -- Revert target on stand-up: what modes and armed states the ship's
        -- turrets return to when the player leaves the chair. Seeded from the
        -- ship's actual state at sit-down, updated only by an explicit
        -- "Update turret behavior" commit.
        committedBaseline = {},
        -- Pending config: what the console rows show and edit. Seeded alongside
        -- committedBaseline at sit-down; diverges as the player makes changes.
        -- Nothing reaches the turrets until a commit point.
        staged = {},
        selectedGroupKey = nil, selectedMemberID = nil, cameraMemberID = nil,
        targetObjectID = nil, targetCandidates = {},
        surfaceTypeFilter = "any", surfaceMacroFilter = "any",
    }
end

function State.surfaceMacroOptions(surfaces, typeFilter)
    local options, seen = {}, {}
    for _, surface in ipairs(surfaces or {}) do
        if (typeFilter == "any" or surface.kindKey == typeFilter)
                and surface.macro and surface.macro ~= ""
                and surface.macroLabelResolved ~= false and not seen[surface.macro] then
            seen[surface.macro] = true
            options[#options + 1] = { id = surface.macro, text = surface.macroLabel or surface.macro }
        end
    end
    table.sort(options, function(a, b)
        if a.text ~= b.text then return a.text < b.text end
        return a.id < b.id
    end)
    return options
end

function State.reconcileSurfaceMacroFilter(options, current)
    if current == nil or current == "any" then return "any", false end
    for _, option in ipairs(options or {}) do
        if option.id == current then return current, false end
    end
    return "any", true
end

function State.filterSurfaceTargets(surfaces, typeFilter, macroFilter)
    local filtered = {}
    for _, surface in ipairs(surfaces or {}) do
        if (typeFilter == "any" or surface.kindKey == typeFilter)
                and (macroFilter == "any" or surface.macro == macroFilter) then
            filtered[#filtered + 1] = surface
        end
    end
    return filtered
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

-- The member table itself, not the (key, componentID) pair above. Camera entry
-- reads the entry's own cameraSupported flag, so it needs the table.
function State.firstCameraMember(groups)
    for _, group in ipairs(groups or {}) do
        for _, member in ipairs(group.members or {}) do
            if member.operational and member.cameraSupported then return member end
        end
    end
end

-- Where a turret sits, as group name plus position within that group. Both
-- survive a save/load; the componentID that normally addresses it does not.
function State.findMemberLocation(session, componentID)
    if not componentID then return nil end
    for _, group in ipairs(session and session.groups or {}) do
        for index, member in ipairs(group.members or {}) do
            if State.normID(member.componentID) == State.normID(componentID) then
                return group, index
            end
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

-- The mode string that the dropdown yields for "Attack all enemies"
-- (Helper.turretModes[2].id in ego_detailmonitorhelper/helper.lua:12714).
-- Lua uses the bare id; MD uses the weaponmode.attackenemies prefix.
-- This is the mode ticking assigns and the binding tests against.
State.TICK_MODE = "attackenemies"

-- When a group that was seeded ticked at sit-down (the ship was already in
-- attackenemies from a previously committed session — correct and intended) is
-- unticked it has no preTickMode to restore. "defend" is the deliberate fallback:
-- it keeps the group protecting the ship rather than aggressive or silent.
State.UNTICK_FALLBACK = "defend"

-- Apply tick side-effects on a staged entry: set mode to TICK_MODE and
-- record the displaced mode in preTickMode so an untick can restore it.
-- Mutates staged[groupKey] in-place; creates the entry if needed.
-- defaultArmed is the group's live armed state, used only when the entry
-- must be created from scratch (same contract as stageMode).
local function applyTick(session, groupKey, defaultArmed)
    local s = session.staged and session.staged[groupKey]
    if s then
        -- preTickMode must never be TICK_MODE itself, or untick "restores" the
        -- mode the group already has and the checkbox looks dead. Two ways in:
        -- a double-tick, and a group whose live mode was already TICK_MODE when
        -- it was ticked. Guard the value, not just the first write.
        if not s.preTickMode and s.mode ~= State.TICK_MODE then s.preTickMode = s.mode end
        s.mode = State.TICK_MODE
    else
        -- No staged entry yet: invent one from defaults. preTickMode is nil
        -- so untick falls back to UNTICK_FALLBACK.
        if session.staged then
            session.staged[groupKey] = { mode = State.TICK_MODE, armed = defaultArmed }
        end
    end
end

-- Apply untick side-effects: restore preTickMode or fall back to UNTICK_FALLBACK.
-- The fallback comment is by State.UNTICK_FALLBACK above.
local function applyUntick(session, groupKey)
    local s = session.staged and session.staged[groupKey]
    if s then
        s.mode = s.preTickMode or State.UNTICK_FALLBACK
        s.preTickMode = nil
    end
    -- No staged entry: nothing to restore. The group's live mode is unchanged.
end

-- Toggle the checked state for one group, applying mode side-effects to staged.
-- Ticking sets staged.mode = TICK_MODE and records the displaced mode in
-- staged.preTickMode. Unticking restores preTickMode (or UNTICK_FALLBACK when
-- the group was seeded ticked without a prior manual tick — e.g. the ship was
-- already in attackenemies from a previously committed session).
-- defaultArmed is the group's live armed state, forwarded to applyTick only
-- when a staged entry must be created from scratch.
function State.toggleGroup(session, groupKey, defaultArmed)
    if session.checkedGroupKeys[groupKey] then
        session.checkedGroupKeys[groupKey] = nil
        applyUntick(session, groupKey)
        return false
    else
        session.checkedGroupKeys[groupKey] = true
        applyTick(session, groupKey, defaultArmed)
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

-- Select-all checkbox: check every mutable group (applying tick side-effects to
-- staged), or clear the selection when they are already all checked (applying
-- untick side-effects). Returns the new checked state.
function State.toggleAllGroups(session)
    if State.allGroupsChecked(session) then
        -- Untick every currently checked group so preTickMode is restored.
        for key in pairs(session.checkedGroupKeys or {}) do
            applyUntick(session, key)
        end
        session.checkedGroupKeys = {}
        return false
    end
    for _, group in ipairs(session.groups or {}) do
        if State.canMutate(group) and not session.checkedGroupKeys[group.key] then
            -- Only tick groups that are not already checked: already-checked
            -- ones keep their existing preTickMode.
            session.checkedGroupKeys[group.key] = true
            applyTick(session, group.key, group.armed)
        end
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
    -- cameraMemberID is what the camera actually shows; cameraIndex is a cache
    -- of its position that several paths (restore, beginTargetSelection,
    -- cinematic anchoring) do not update, so re-derive it here rather than
    -- trusting it. Falls back to the cached index when the member is gone.
    local idx = session.cameraIndex or 1
    if session.cameraMemberID then
        local want = normID(session.cameraMemberID)
        for i, m in ipairs(roster) do
            if normID(m.componentID) == want then idx = i break end
        end
    end
    -- Clamp stale index into valid range before applying delta.
    if idx < 1 or idx > #roster then idx = 1 end
    idx = ((idx - 1 + delta) % #roster) + 1
    session.cameraIndex = idx
    local m = roster[idx]
    session.cameraMemberID = m.componentID
    return m
end

-- Replaces beginWatch and beginDirect. Sets phase to "engaged" and
-- controlMode. committedBaseline is seeded at sit-down (seedBaseline) and is
-- not modified here; it is the revert target regardless of controlMode.
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
    return session.committedBaseline or {}
end

function State.returnToConsole(session)
    session.phase = "console"
    session.controlMode = nil
    session.povMode = "manual"
    session.cameraMemberID, session.targetObjectID = nil, nil
end

-- Returns session.committedBaseline (never empties it), and if phase is
-- "engaged" sets phase back to "console". committedBaseline persists for the
-- session lifetime; the caller reads it to write modes back to the ship.
-- Never returns nil.
function State.releaseDirect(session)
    if session.phase == "engaged" then session.phase = "console" end
    return session.committedBaseline or {}
end

-- Seed committedBaseline and staged from the ship's actual modes at sit-down.
-- committedBaseline is what reverts on stand-up; staged is what the console
-- edits. Both start identical; they diverge as the player makes changes without
-- committing. Called once per session from onShowMenu, never from refresh().
-- The staged key for a baseline entry. staged is keyed by the live group.key, so
-- every reader has to derive the same string from a baseline entry's locator
-- fields. Deriving it in more than one place is how seeding and committing drift
-- apart: a group whose key is not literally the derived form then reads as
-- permanently dirty while the commit silently updates nothing. One helper, used
-- by the seed side and every reader, makes that impossible.
function State.baselineStagedKey(entry)
    if entry.kind == "single" then return State.singleKey(entry.componentID) end
    return State.groupKey(entry.contextID, entry.path, entry.group)
end

function State.seedBaseline(session, groups)
    local baseline = {}
    local staged = {}
    for _, group in ipairs(groups or {}) do
        local entry = {
            shipID = session.shipID, kind = group.kind,
            componentID = group.componentID, contextID = group.contextID,
            path = group.path, group = group.group,
            mode = group.mode, armed = group.armed,
        }
        baseline[#baseline + 1] = entry
        -- Key by what the readers will derive, not by group.key. These agree for
        -- a group read off the ship, but a caller-supplied group.key need not
        -- match, and a mismatch is silent in both directions.
        local stagedKey = State.baselineStagedKey(entry)
        staged[stagedKey] = { mode = group.mode, armed = group.armed }
        -- The checkbox is bound to the mode in both directions, so a group the
        -- ship is already flying in TICK_MODE must come up ticked -- otherwise a
        -- committed change survives standing up but its checkbox does not, and
        -- ticking it then records TICK_MODE as its own preTickMode and the
        -- checkbox stops doing anything at all. No preTickMode is stored: there
        -- is no earlier mode to go back to, so untick falls to UNTICK_FALLBACK.
        if group.mode == State.TICK_MODE then
            session.checkedGroupKeys[stagedKey] = true
        end
    end
    session.committedBaseline = baseline
    session.staged = staged
end

-- Update the staged mode for one group and sync the checkbox. The ship is not
-- touched. The checkbox is bound to TICK_MODE: setting the mode to TICK_MODE
-- ticks the group; setting it to anything else unticks it.
--
-- defaultArmed is the group's LIVE armed state, passed by the caller. A group
-- can exist without a staged entry (a refresh() that discovers a turret group
-- after sit-down, or a legacy payload whose staged was rebuilt empty), and
-- inventing armed = false there would disarm a group the player never touched
-- the moment the change is committed.
function State.stageMode(session, groupKey, mode, defaultArmed)
    if not session or not session.staged then return end
    local s = session.staged[groupKey]
    -- Capture the old mode before writing so the checkbox-sync can use it as
    -- preTickMode. Once s.mode is overwritten the information is gone.
    local oldMode = s and s.mode
    local wasAttackEnemies = oldMode == State.TICK_MODE
    local isAttackEnemies  = mode == State.TICK_MODE
    if s then s.mode = mode
    else session.staged[groupKey] = { mode = mode, armed = defaultArmed } end
    -- Sync the checkbox. When the player picks a mode from the dropdown the
    -- checkbox follows: attackenemies ticks it, any other mode unticks it.
    if not wasAttackEnemies and isAttackEnemies then
        -- Tick: record the displaced mode in preTickMode so untick can restore it.
        -- Only set preTickMode when not already set, so a second tick doesn't
        -- overwrite it with TICK_MODE itself.
        session.checkedGroupKeys[groupKey] = true
        local entry = session.staged[groupKey]
        if entry and not entry.preTickMode then entry.preTickMode = oldMode end
    elseif wasAttackEnemies and not isAttackEnemies then
        -- Untick: the caller chose a specific mode via the dropdown; honour it
        -- directly rather than going through preTickMode (which would restore
        -- the mode as of the last tick, which may differ from what was just picked).
        session.checkedGroupKeys[groupKey] = nil
        local entry = session.staged[groupKey]
        if entry then entry.mode = mode; entry.preTickMode = nil end
    end
end

-- Update the staged armed state for one group. The ship is not touched.
-- defaultMode is the group's LIVE mode, passed by the caller, for the same
-- reason as above: "" is not a valid weapon mode, so a manufactured entry must
-- carry what the turret is actually set to rather than an empty string.
function State.stageArmed(session, groupKey, armed, defaultMode)
    if not session or not session.staged then return end
    local s = session.staged[groupKey]
    if s then s.armed = armed
    else session.staged[groupKey] = { mode = defaultMode, armed = armed } end
end

-- Returns true when staged differs from committedBaseline for any group.
-- Compares mode and armed for each baseline entry against the matching staged
-- entry, so it stays accurate while a temporary apply is active on the ship.
function State.isStagedDirty(session)
    if not session then return false end
    local staged = session.staged
    if not staged then return false end
    for _, entry in ipairs(session.committedBaseline or {}) do
        local s = staged[State.baselineStagedKey(entry)]
        if not s or s.mode ~= entry.mode or s.armed ~= entry.armed then return true end
    end
    return false
end

-- Advance committedBaseline to match staged (permanent commit). Called when
-- the player presses "Update turret behavior"; the caller writes staged to the
-- ship before calling this.
function State.commitStagedToBaseline(session)
    if not session then return end
    local staged = session.staged
    if not staged then return end
    for _, entry in ipairs(session.committedBaseline or {}) do
        local s = staged[State.baselineStagedKey(entry)]
        if s then entry.mode = s.mode; entry.armed = s.armed end
    end
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
    local camGroup, camIndex = State.findMemberLocation(session, session.cameraMemberID)
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
        -- So the target travels in the payload instead of being re-read. Only
        -- good across a reload; a load reassigns the id, and the restore takes
        -- the target from MD's component reference instead. targetObjectID is
        -- not carried at all -- it is always the root of aimTargetID, so the
        -- restore derives it rather than keeping a second id in step.
        aimTargetID = tostring(session.aimTargetID or ""),
        -- Only usable across a reload; a load reassigns it. The three fields
        -- below say the same thing in terms that do survive a load -- which
        -- turret of which group -- so the POV comes back to the same barrel
        -- rather than to whichever turret happens to be listed first.
        cameraMemberID = tostring(session.cameraMemberID or ""),
        camPath = camGroup and camGroup.path or "",
        camGroup = camGroup and camGroup.group or "",
        camIndex = tostring(camIndex or ""),
    } }
    -- committedBaseline travels as "baseline" records so restoreState can write
    -- modes back on stand-up even after a savegame load. Without it a load after
    -- a temporary apply strands the ship in temp modes with nothing to revert to.
    for _, snap in ipairs(State.snapshotsForSave(session.committedBaseline)) do
        local record = { t = "baseline" }
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

local function isString(value)
    return type(value) == "string"
end

local function hasStringFields(record, fields)
    for _, field in ipairs(fields) do
        if not isString(record[field]) then return false end
    end
    return true
end

local function validFlag(value)
    return value == "0" or value == "1"
end

local function validCameraLocation(record)
    local fields = { "camPath", "camGroup", "camIndex" }
    local present = 0
    for _, field in ipairs(fields) do
        if record[field] ~= nil then present = present + 1 end
    end
    -- The first persistence format pre-dated the stable camera location. It
    -- omitted the whole triplet, so retain that known compatibility shape; a
    -- partly-present triplet is corruption, not a legacy payload.
    if present == 0 then return true end
    if present ~= #fields or not hasStringFields(record, fields) then return false end
    if record.camIndex == "" then
        return record.camPath == "" and record.camGroup == ""
    end
    return record.camPath ~= "" and record.camGroup ~= ""
        and record.camIndex:match("^[1-9][0-9]*$") ~= nil
end

local function validSessionRecord(record)
    local required = {
        "phase", "controlMode", "povAnchor", "povMode", "autoNextTarget",
        "preferAllTurrets", "shipID", "aimTargetID", "cameraMemberID",
    }
    if record.t ~= "session" or not hasStringFields(record, required)
        or record.shipID == "" then
        return false
    end
    if record.phase ~= "console" and record.phase ~= "target_select"
        and record.phase ~= "engaged" then
        return false
    end
    if record.phase == "engaged" then
        if record.controlMode ~= "auto" and record.controlMode ~= "direct" then return false end
    elseif record.phase == "target_select" then
        -- A Direct session keeps its snapshots while the target browser is
        -- open, so it can return to the same override or release it on close.
        -- This is a current saveState shape, not a permissive legacy default.
        if record.controlMode ~= "" and record.controlMode ~= "direct" then return false end
    elseif record.controlMode ~= "" then
        return false
    end
    if record.povAnchor ~= "turret" and record.povAnchor ~= "target" then return false end
    if record.povMode ~= "manual" and record.povMode ~= "cinematic" then return false end
    if not validFlag(record.autoNextTarget) or not validFlag(record.preferAllTurrets) then return false end
    if record.shipName ~= nil and not isString(record.shipName) then return false end
    -- targetObjectID was emitted by the first two persistence revisions. It is
    -- intentionally ignored now (the target root is derived), but remains a
    -- valid optional legacy field rather than making an old save unrestorable.
    if record.targetObjectID ~= nil and not isString(record.targetObjectID) then return false end
    -- directedMode: legacy field, no longer written or acted on; ignored if present.
    return validCameraLocation(record)
end

local function validSnapshotLike(record, sessionRecord, expectedT)
    if record.t ~= expectedT or (record.kind ~= "group" and record.kind ~= "single")
        or not hasStringFields(record, { "shipID", "mode", "armed" })
        or record.shipID == "" or record.shipID ~= sessionRecord.shipID
        or not validFlag(record.armed) then
        return false
    end
    if record.kind == "single" then
        return isString(record.componentID) and record.componentID ~= ""
    end
    return hasStringFields(record, { "contextID", "path", "group" })
end

local function validSnapshotRecord(record, sessionRecord)
    return validSnapshotLike(record, sessionRecord, "snapshot")
end

local function validBaselineRecord(record, sessionRecord)
    return validSnapshotLike(record, sessionRecord, "baseline")
end

local function validCheckedRecord(record)
    return record.t == "checked" and hasStringFields(record, { "path", "group" })
end

-- Validate the entire decoded transport before restoreState changes even a
-- throwaway candidate. `decode` is deliberately permissive so it can carry
-- escaped vanilla identifiers; restore is not. A parseable truncation such as
-- `t=session` must never replace a live Direct session and strand its
-- snapshots. Multiple complete records are tolerated; the first session record
-- is authoritative, matching the identity check that has always used it.
local function validatedSessionRecord(records)
    if type(records) ~= "table" then return nil end
    local head
    for _, record in ipairs(records) do
        if type(record) ~= "table" then return nil end
        if record.t == "session" then
            if not validSessionRecord(record) then return nil end
            if not head then head = record end
        elseif record.t == "snapshot" then
            -- Its session identity is checked after the head is found below.
            -- Legacy record type kept for payloads written before the rename.
        elseif record.t == "baseline" then
            -- Its session identity is checked after the head is found below.
        elseif record.t == "checked" then
            if not validCheckedRecord(record) then return nil end
        else
            return nil
        end
    end
    if not head then return nil end
    for _, record in ipairs(records) do
        if record.t == "snapshot" and not validSnapshotRecord(record, head) then return nil end
        if record.t == "baseline" and not validBaselineRecord(record, head) then return nil end
    end
    -- Legacy: only a Direct session can own snapshot records. Baseline records
    -- are valid in any session (they are always present after sit-down seeding).
    for _, record in ipairs(records) do
        if record.t == "snapshot" and (head.controlMode ~= "direct"
            or (head.phase ~= "engaged" and head.phase ~= "target_select")) then
            return nil
        end
    end
    return head
end

-- Rebuilds `session` from decode()'s output. liveGroups is the freshly read
-- group list: every group is located by path+group and takes its contextID and
-- key from the live entry, never from the payload. Returns true when a session
-- record was present and belongs to this ship.
function State.restoreState(session, records, liveGroups)
    if type(session) ~= "table" then return false end
    local head = validatedSessionRecord(records)
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
    local checkedGroupKeys = {}
    local snapshots = {}
    local baseline = {}
    for _, record in ipairs(records) do
        if record.t == "checked" then
            local live = byName[nameKey(record.path, record.group)]
            if live then checkedGroupKeys[live.key] = true end
        elseif record.t == "snapshot" then
            -- Legacy record type (payloads written before the baseline rename).
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
        elseif record.t == "baseline" then
            -- committedBaseline: matched by name, same rules as snapshots for
            -- contextID resolution. Single-turret entries survive only a reload.
            if record.kind == "single" then
                if idsHeld then
                    baseline[#baseline + 1] = {
                        kind = "single", shipID = tostring(session.shipID),
                        componentID = record.componentID,
                        mode = record.mode, armed = record.armed == "1",
                    }
                end
            else
                local live = byName[nameKey(record.path, record.group)]
                if live then
                    baseline[#baseline + 1] = {
                        kind = record.kind, shipID = tostring(session.shipID),
                        contextID = live.contextID, path = live.path,
                        group = live.group,
                        mode = record.mode, armed = record.armed == "1",
                    }
                end
            end
        end
    end
    -- Rebuild staged from restored baseline so the console shows the committed
    -- config immediately, before the player makes any new changes.
    local restoredStaged = {}
    for _, entry in ipairs(baseline) do
        local stagedKey = State.baselineStagedKey(entry)
        -- A checked group is under Direct-control, whose temporary mode is
        -- always TICK_MODE. The checked and baseline records are independent:
        -- baseline is the stand-up revert target, while checked describes the
        -- current engagement. An unchecked group whose committed baseline is
        -- TICK_MODE is the tick->commit->untick case: keep the checkbox clear,
        -- display the normal unticked fallback, and retain TICK_MODE in the
        -- baseline so standing up can still restore the committed mode.
        local isChecked = checkedGroupKeys[stagedKey] == true
        local stagedMode = isChecked and State.TICK_MODE
            or (entry.mode == State.TICK_MODE and State.UNTICK_FALLBACK or entry.mode)
        restoredStaged[stagedKey] = { mode = stagedMode, armed = entry.armed }
    end
    -- Last, so it wins over the componentID read in the loop: group name plus
    -- position is the only form of "which turret" that outlives a load.
    local camLive = byName[nameKey(head.camPath, head.camGroup)]
    local camIndex = tonumber(head.camIndex or "")
    local camMember = camLive and camIndex and (camLive.members or {})[camIndex]
    -- All validation and reconstruction is complete. Only now may this mutate
    -- the caller's candidate; on any refusal above, it is byte-for-byte the
    -- object that onRestoreEnvelope created before it considered a swap.
    session.phase = head.phase
    session.controlMode = (head.controlMode ~= "" and head.controlMode) or nil
    session.povAnchor = head.povAnchor
    session.povMode = head.povMode
    session.autoNextTarget = head.autoNextTarget == "1"
    session.preferAllTurrets = head.preferAllTurrets == "1"
    session.checkedGroupKeys = checkedGroupKeys
    if idsHeld then
        session.aimTargetID = (head.aimTargetID ~= "" and head.aimTargetID) or nil
        session.cameraMemberID = (head.cameraMemberID ~= "" and head.cameraMemberID) or nil
    end
    if camMember then session.cameraMemberID = camMember.componentID end
    -- committedBaseline restored from "baseline" records; staged rebuilt from it.
    -- Legacy "snapshot" records (payloads written before the rename) populate
    -- committedBaseline when no baseline records are present, preserving the
    -- revert-on-stand-up guarantee across an upgrade from an older save.
    if #baseline > 0 then
        session.committedBaseline = baseline
    elseif #snapshots > 0 then
        session.committedBaseline = snapshots
    end
    if #restoredStaged > 0 or next(restoredStaged) ~= nil then
        session.staged = restoredStaged
    end
    return true
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
