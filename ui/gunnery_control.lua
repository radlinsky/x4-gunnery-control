-- X4 Gunnery Control. Uses public UI Lua FFI functions present in X4 9.00.
-- Runtime camera centering is intentionally treated as an in-game release gate.
local ffi = require("ffi")
local C = ffi.C
local State = X4GunneryState
local Persistence = X4GunneryPersistence
local TurretArcLimits = X4GunneryTurretArcLimits or {}

ffi.cdef[[
typedef uint64_t UniverseID;
typedef struct { UniverseID softtargetID; const char* softtargetConnectionName; uint32_t messageID; } SofttargetDetails2;
typedef struct { UniverseID contextid; const char* path; const char* group; } UpgradeGroup2;
typedef struct { const char* path; const char* group; } UpgradeGroup;
typedef struct { UniverseID currentcomponent; const char* currentmacro; const char* slotsize; uint32_t count; uint32_t operational; uint32_t total; } UpgradeGroupInfo;
const char* GetPlayerCurrentControlGroup(void); UniverseID GetPlayerOccupiedShipID(void);
UniverseID GetPlayerID(void); UniverseID GetContextByClass(UniverseID componentid, const char* classname, bool includeself);
bool IsComponentClass(UniverseID componentid, const char* classname);
size_t GetNumUpgradeSlots(UniverseID destructibleid, const char* macroname, const char* upgradetypename);
UniverseID GetUpgradeSlotCurrentComponent(UniverseID destructibleid, const char* upgradetypename, size_t slot);
const char* GetUpgradeSlotCurrentMacro(UniverseID objectid, UniverseID moduleid, const char* upgradetypename, size_t slot);
UpgradeGroup GetUpgradeSlotGroup(UniverseID destructibleid, const char* macroname, const char* upgradetypename, size_t slot);
uint32_t GetNumUpgradeGroups(UniverseID destructibleid, const char* macroname);
uint32_t GetUpgradeGroups2(UpgradeGroup2* result, uint32_t resultlen, UniverseID destructibleid, const char* macroname);
UpgradeGroupInfo GetUpgradeGroupInfo2(UniverseID destructibleid, const char* macroname, UniverseID contextid, const char* path, const char* group, const char* upgradetypename);
const char* GetTurretGroupMode2(UniverseID defensibleid, UniverseID contextid, const char* path, const char* group);
void SetTurretGroupMode2(UniverseID defensibleid, UniverseID contextid, const char* path, const char* group, const char* mode);
bool IsTurretGroupArmed(UniverseID defensibleid, UniverseID contextid, const char* path, const char* group);
void SetTurretGroupArmed(UniverseID defensibleid, UniverseID contextid, const char* path, const char* group, bool arm);
const char* GetWeaponMode(UniverseID weaponid); void SetWeaponMode(UniverseID weaponid, const char* mode);
bool IsWeaponArmed(UniverseID weaponid); void SetWeaponArmed(UniverseID weaponid, bool arm);
const char* GetComponentName(UniverseID componentid); SofttargetDetails2 GetSofttarget2(void);
bool IsPlayerCameraTargetViewPossible(UniverseID targetid, bool force); void SetPlayerCameraTargetView(UniverseID targetid, bool force);
UniverseID GetExternalTargetViewComponent(void); void SetPlayerCameraCockpitView(bool force); bool GetUp(void);
bool IsHUDActive(void); bool IsFullscreenCutsceneActive(void);
bool IsFullscreenMenuDisplayed(bool anymenu, const char* menuname);
bool IsGamePaused(void); void SetTrackedMenuFullscreen(const char* menu, bool fullscreen);
bool SetSofttarget(UniverseID componentid, const char*const connectionname);
bool IsComponentOperational(UniverseID componentid);
float GetDistanceBetween(UniverseID component1id, UniverseID component2id);
uint32_t GetNumStationModules(UniverseID stationid, bool includeconstructions, bool includewrecks);
uint32_t GetStationModules(UniverseID* result, uint32_t resultlen, UniverseID stationid, bool includeconstructions, bool includewrecks);
]]

local menu = { name = "X4GunneryMenu", uixID = "x4_gunnery_control" }
local runtimeBuild = "2026-08-13-turret-arcs-2"
-- The upper-left element panel's own frame layer; every frame registers a view
-- named "Helper" .. layer, so it must differ from the default 4 used elsewhere.
local elementFrameLayer = 3
local session, redirectPending, nextRefresh = nil, false, 0
local persistence
local testLabCallbacks
local testCameraFailures = {}
-- Declared before enterCamera: a successful turret gate applies the caller's
-- final POV only after X4 has accepted the temporary turret placement.
local applyPov
local dockedHookRegistered, mapHookRegistered, hookAttempts = false, false, 0
local resumePending, endingSession = false, false
-- Defined next to leaveChair, but every teardown route needs it.
local clearOwnShipSofttarget
local seatLeaving = false
local sessionEpoch = 0
local engageabilitySerial, engageabilityCache, engageabilityRequests = 0, {}, {}
local engageabilityRepaintSerial, engageabilityRepaintPending = 0, nil
local surfacePinnedUpdatePending = false
local reopenSuspendedSession
local activeExternalMenuName
local cameraMismatchLogged = false
local mapReopenFailureLogged = false
local containedShipsFailureLogged, containedStationsFailureLogged = false, false
local cutsceneNoTurretFailureLogged = false

local function text(id) return ReadText(20991, id) end
local function str(pointer) return pointer ~= nil and ffi.string(pointer) or "" end
-- Internal keys and log output only. Vanilla XML pads group attributes, but
-- whatever the engine hands back has to go straight back to the engine.
local function trim(value) return value:match("^%s*(.-)%s*$") or value end
local function id(value) return ConvertStringTo64Bit(tostring(value)) end
-- GetComponentData needs a ConvertStringTo64Bit'd id (vanilla passes
-- `convertedComponent` / `object64` everywhere). A raw UniverseID silently
-- returns nil for every key rather than erroring, which is why relations all
-- read as Neutral before this wrapper existed. Every call routes through here.
local function componentData(component, ...) return GetComponentData(id(component), ...) end
local function controlGroup() return str(C.GetPlayerCurrentControlGroup()) end
local function log(message) DebugError("[X4GC] " .. message) end
-- Raw FFI ids stringify with a ULL suffix and id()-converted ones do not, so a
-- bare tostring comparison judges the same component to be two different ones.
local function sameID(a, b) return State.normID(a) == State.normID(b) end
-- "0ULL" (the FFI form of an unset UniverseID) and "0" and nil all mean the
-- same thing: no component. Guards that only test tostring(v) == "0" silently
-- miss the cdata form and let zero ids through as if they were real targets.
-- Comparing a raw cdata id against the number 0 (`softtargetID ~= 0`) is safe --
-- LuaJIT compares boxed uint64 numerically -- and several sites below still do
-- that. Only the tostring form breaks, so reach for isNullID() whenever the
-- value may be nil or may have been through id()/normID().
local isNullID = State.isNullID
local function sameSession(expected, epoch)
    return session == expected and sessionEpoch == epoch
end
local function currentSession(expected, epoch)
    return sameSession(expected, epoch) and State.isOwned(session)
end
local function softtargetKey()
    local target = C.GetSofttarget2()
    return tostring(target.softtargetID) .. "\31" .. str(target.softtargetConnectionName)
end

local function playerShip()
    local ship = C.GetPlayerOccupiedShipID()
    if ship == 0 then
        -- Secondary bridge posts can clear GetPlayerOccupiedShipID() even while
        -- the player remains aboard. DockedMenu uses the player's enclosing
        -- container in this situation, so mirror that resolution here.
        ship = C.GetContextByClass(C.GetPlayerID(), "container", false)
        if ship == 0 or not C.IsComponentClass(ship, "ship") then return 0 end
    end
    return id(ship)
end

-- State.newSession is pure Lua and cannot read the ship's name. It is recorded
-- because it is the only identifier of the ship that survives a save/load: every
-- id is reassigned, so a restore has nothing else to check the payload against.
local function newSession(ship)
    engageabilityCache, engageabilityRequests = {}, {}
    engageabilityRepaintPending = nil
    surfacePinnedUpdatePending = false
    local session = State.newSession(ship, "gunnercontrol")
    session.shipName = str(C.GetComponentName(ship))
    return session
end

local function roundedPercent(value)
    value = tonumber(value) or 0
    return math.floor(value + 0.5)
end

local function surfaceHealth(component)
    local shieldmax, shieldpercent, hullpercent = componentData(component,
        "shieldmax", "shieldpercent", "hullpercent")
    return (tonumber(shieldmax) or 0) > 0, roundedPercent(shieldpercent), roundedPercent(hullpercent)
end

local function surfaceShieldText(component)
    local shielded, shieldpercent = surfaceHealth(component)
    return shielded
        and (text(98) .. " " .. tostring(shieldpercent) .. "%")
        or (text(98) .. " -")
end

local function surfaceHullText(component)
    local _, _, hullpercent = surfaceHealth(component)
    return text(99) .. " " .. tostring(hullpercent) .. "%"
end

local function surfaceDistance(component)
    if not session or State.isNullID(component) then return -1 end
    return tonumber(C.GetDistanceBetween(session.shipID, id(component))) or -1
end

local function surfaceDistanceText(distance)
    distance = tonumber(distance)
    if not distance or distance < 0 then return "-" end
    return string.format("%.1f km", distance / 1000)
end

local function surfaceEquipmentSize(macro)
    if macro == "" then return "unknown", "unavailable" end
    local metadataSize = State.normalizeSurfaceSize(GetMacroData(macro, "size"))
    if metadataSize ~= "unknown" then return metadataSize, "macro_metadata" end
    -- X4 9.00 returns no `size` metadata for installed turret/shield macros.
    -- Stock equipment identifiers carry their size as a delimited token (for
    -- example turret_xen_l_laser... and shield_xen_m_standard...). Unlike the
    -- localized visible name, this identifier is stable across languages.
    local identifier = string.lower(macro)
    local tokens = { { "xl", "XL" }, { "xs", "XS" }, { "l", "L" },
        { "m", "M" }, { "s", "S" } }
    for _, entry in ipairs(tokens) do
        if string.find(identifier, "_" .. entry[1] .. "_", 1, true) then
            return entry[2], "macro_identifier"
        end
    end
    return "unknown", "unavailable"
end

local function isInGunnerChair()
    -- Bridge assets mark the cockpit trigger with "gunnertrigger", but the
    -- chair/terminal connection exposed by GetPlayerCurrentControlGroup() is
    -- "gunnercontrol".
    return controlGroup() == "gunnercontrol" and playerShip() ~= 0
end

-- Every registered View entry, as id/owning-menu-name. A view that outlives its
-- menu keeps the engine in menu-input mode, which would explain Esc doing
-- nothing after get-up until another menu opens and closes. View is a global
-- from ego_viewhelper; guard it so a load-order surprise logs instead of raising.
local function viewSummary()
    local list = View and View.menus
    if not list then return "<unavailable>" end
    local parts = {}
    for _, entry in ipairs(list) do
        parts[#parts + 1] = tostring(entry.id) .. "/" .. tostring(entry.name)
    end
    return #parts .. (#parts > 0 and ("[" .. table.concat(parts, ",") .. "]") or "")
end

-- The engine's own "is a fullscreen menu up" test (helptext.lua:536). A menu
-- that stays tracked after ours is gone would take the Esc that should open the
-- game menu, which is the reported symptom. Named per candidate because the fix
-- differs: DockedMenu is closed by our redirect, ours by the get-up teardown.
local function trackedMenuSummary()
    return "any=" .. tostring(C.IsFullscreenMenuDisplayed(true, ""))
        .. "/docked=" .. tostring(C.IsFullscreenMenuDisplayed(false, "DockedMenu"))
        .. "/own=" .. tostring(C.IsFullscreenMenuDisplayed(false, menu.name))
end

local function logSession(event)
    local current = session
    local lifecycle = current and current.lifecycle or "none"
    local phase = current and current.phase or "none"
    log(event .. "; lifecycle=" .. lifecycle .. "; phase=" .. phase
        .. "; shown=" .. tostring(menu.shown and true or false)
        .. "; control=" .. (controlGroup() ~= "" and controlGroup() or "<none>")
        .. "; occupied=" .. tostring(C.GetPlayerOccupiedShipID())
        .. "; resolved=" .. tostring(playerShip())
        .. "; camera=" .. tostring(C.GetExternalTargetViewComponent())
        .. "; paused=" .. tostring(C.IsGamePaused())
        -- hud= on every state line, not just after exit: we still do not know
        -- whether it is already false while seated or flips during teardown.
        .. "; hud=" .. tostring(C.IsHUDActive())
        .. "; views=" .. viewSummary()
        .. "; fsmenu=" .. trackedMenuSummary()
        .. "; epoch=" .. tostring(sessionEpoch)
        .. "; extmenu=" .. (activeExternalMenuName and activeExternalMenuName() or "<none>"))
end

local function transitionLifecycle(nextLifecycle, reason, quiet)
    if not session then return end
    local previous = session.lifecycle or "none"
    State.setLifecycle(session, nextLifecycle)
    if not quiet then
        logSession("lifecycle " .. previous .. " -> " .. nextLifecycle .. ": " .. reason)
    end
end

local function ownedByPlayer(ship)
    -- Ownership is intentionally conservative. The player must be seated in the
    -- vessel they are controlling; this excludes station/remote contexts.
    return ship ~= 0 and componentData(ship, "isplayerowned")
end

local function memberName(componentID, ordinal)
    local name = str(C.GetComponentName(componentID))
    return name ~= "" and name or (text(29) .. " " .. tostring(ordinal))
end

local function readGroups(ship)
    local groups, candidates = {}, {}
    local count = tonumber(C.GetNumUpgradeGroups(ship, ""))
    local buffer = ffi.new("UpgradeGroup2[?]", count)
    count = tonumber(C.GetUpgradeGroups2(buffer, count, ship, ""))
    for i = 0, count - 1 do
        local path, group = str(buffer[i].path), str(buffer[i].group)
        if path ~= ".." or group ~= "" then
            local info = C.GetUpgradeGroupInfo2(ship, "", buffer[i].contextid, path, group, "turret")
            if tonumber(info.count) > 0 then
                local key = State.groupKey(buffer[i].contextid, path, group)
                local entry = {
                    key = key, kind = "group", contextID = buffer[i].contextid, path = path, group = group,
                    componentID = info.currentcomponent, macro = str(info.currentmacro), slotSize = str(info.slotsize),
                    totalCount = tonumber(info.total), operationalCount = tonumber(info.operational), members = {},
                    mode = str(C.GetTurretGroupMode2(ship, buffer[i].contextid, path, group)),
                    armed = C.IsTurretGroupArmed(ship, buffer[i].contextid, path, group),
                }
                groups[#groups + 1] = entry
                -- Candidate key is internal-only: trim path and group so that
                -- inconsistent XML padding between GetUpgradeGroups2 and
                -- GetUpgradeSlotGroup (two separate APIs) does not silently break
                -- turret-to-group attribution. The entry's own path/group fields
                -- and every engine call that follows stay byte-exact as received.
                local candidateKey = trim(path) .. "\31" .. trim(group)
                candidates[candidateKey] = candidates[candidateKey] or {}
                candidates[candidateKey][#candidates[candidateKey] + 1] = entry
            end
        end
    end
    local slots = tonumber(C.GetNumUpgradeSlots(ship, "", "turret"))
    for slot = 1, slots do
        local component = C.GetUpgradeSlotCurrentComponent(ship, "turret", slot)
        if component ~= 0 then
            local slotGroup, path, name = C.GetUpgradeSlotGroup(ship, "", "turret", slot), "", ""
            path, name = str(slotGroup.path), str(slotGroup.group)
            local possible = candidates[trim(path) .. "\31" .. trim(name)] or {}
            local entry = possible[1]
            if #possible > 1 then
                -- The slot API returns no context ID, so same-named groups on
                -- different contexts cannot be told apart here. This only picks
                -- which group a turret is listed under; group commands address
                -- contextID+path+group and are always exact. Every shipped ship
                -- macro uses path ".." with unique group names, so this branch
                -- is defensive.
                -- ponytail: representative-component match, first candidate
                -- otherwise. Worst case is a member row under the wrong group
                -- name, never a write to the wrong group.
                for _, candidate in ipairs(possible) do
                    if sameID(candidate.componentID, component) then entry = candidate; break end
                end
            end
            if not entry then
                entry = { key = State.singleKey(component), kind = "single", componentID = component, totalCount = 1,
                    operationalCount = 0, members = {}, mode = str(C.GetWeaponMode(component)), armed = C.IsWeaponArmed(component),
                    displayName = memberName(component, slot) }
                groups[#groups + 1] = entry
            end
            entry.members[#entry.members + 1] = { componentID = component, componentKey = State.memberKey(component),
                macro = entry.macro or "", displayName = memberName(component, #entry.members + 1),
                operational = C.IsComponentOperational(component), cameraSupported = C.IsPlayerCameraTargetViewPossible(component, true) }
            if entry.kind == "single" and entry.members[#entry.members].operational then entry.operationalCount = 1 end
        end
    end
    local labelCounts = {}
    for index, entry in ipairs(groups) do
        if entry.kind == "group" then
            local position = State.turretGroupLabel(entry.group)
            local equipment = (entry.macro ~= "" and GetMacroData(entry.macro, "shortname")) or ""
            local base = position or (text(4) .. " " .. tostring(index))
            if equipment ~= "" then base = base .. ": " .. equipment end
            labelCounts[base] = (labelCounts[base] or 0) + 1
            entry.displayName = base .. (labelCounts[base] > 1 and (" · " .. tostring(labelCounts[base])) or "")
        end
    end
    table.sort(groups, function(a, b)
        if a.displayName ~= b.displayName then return a.displayName < b.displayName end
        return a.key < b.key
    end)
    return groups
end

local function currentGroup(key)
    for _, group in ipairs(session and session.groups or {}) do if group.key == key then return group end end
end

-- Returns the member table for session.cameraMemberID, scanning session.groups.
-- nil when the member is gone or cameraMemberID is not set.
local function cameraMember()
    if not session or not session.cameraMemberID then return nil end
    for _, group in ipairs(session.groups or {}) do
        for _, member in ipairs(group.members or {}) do
            if sameID(member.componentID, session.cameraMemberID) then return member, group end
        end
    end
    return nil
end

local function selectedGroupAndMember()
    local group = currentGroup(session and session.selectedGroupKey)
    if not group then return nil, nil end
    for _, member in ipairs(group.members) do
        if sameID(member.componentID, session.selectedMemberID) then return group, member end
    end
    return group, nil
end

local function setMode(group, mode)
    if group.kind == "group" then C.SetTurretGroupMode2(session.shipID, group.contextID, group.path, group.group, mode)
    else C.SetWeaponMode(group.componentID, mode) end
end
local function setArmed(group, armed)
    if group.kind == "group" then C.SetTurretGroupArmed(session.shipID, group.contextID, group.path, group.group, armed)
    else C.SetWeaponArmed(group.componentID, armed) end
end

-- The adapter parks one atomic MD table: an encoded session string and an
-- explicit target-presence flag/component. The string remains scalar because
-- raise_lua_event cannot return a Lua table, while the component survives ID
-- remapping across save/load.
local function persistSession()
    if session and persistence then persistence.commit(session) end
end
local function clearSnapshot()
    if persistence then persistence.clear() end
end

local function findSnapshotGroup(snapshot)
    for _, group in ipairs(session and session.groups or {}) do
        if snapshot.kind == "single" and group.kind == "single" and sameID(group.componentID, snapshot.componentID) then return group end
        if snapshot.kind == "group" and group.kind == "group" and sameID(group.contextID, snapshot.contextID)
            and group.path == snapshot.path and group.group == snapshot.group then return group end
    end
end

local function matchesSnapshot(group, snapshot)
    if snapshot.kind == "single" then
        return group.kind == "single" and sameID(group.componentID, snapshot.componentID)
    end
    return group.kind == "group" and sameID(group.contextID, snapshot.contextID)
        and group.path == snapshot.path and group.group == snapshot.group
end

-- A group is "directed" when the session is actively engaged in direct mode
-- and the group is checked. In console phase controlMode is nil, so this is
-- always false when the console rows are shown.
local function isDirectedGroup(group)
    if not group or not session then return false end
    if session.controlMode ~= "direct" then return false end
    return session.checkedGroupKeys and session.checkedGroupKeys[group.key] == true
end

-- Vanilla 9.00 ships the turret-mode option list as Helper.turretModes
-- (ui/addons/ego_detailmonitorhelper/helper.lua): one entry per engine mode,
-- with the game-localized option text (ReadText(1001, ...)). The Direct-control
-- selector and the constrained row dropdowns copy those entries, so their
-- labels can never drift from the vanilla turret-mode dropdown.
--
-- X4's createDropDown aborts the whole frame on an option without a boolean
-- displayremoveoption (live 9.00: "Invalid dropdown descriptor. Given
-- displayremoveoption is missing or not a bool."), which is why vanilla's own
-- getTurretModes passes a full table copy of each entry, field for field. Our
-- copies must keep the same descriptor fields, not just id/text/icon.
local function copyTurretModeOption(entry)
    return { id = entry.id, text = entry.text, icon = entry.icon or "",
             displayremoveoption = entry.displayremoveoption, forall = entry.forall }
end

local function vanillaModeOption(modeID)
    for _, entry in ipairs(Helper.turretModes or {}) do
        if entry.id == modeID then
            return copyTurretModeOption(entry)
        end
    end
    return nil
end

-- The Direct-control engine modes vanilla ships, in vanilla order, with the
-- vanilla-localized option texts. Both the console selector and the
-- engaged-panel selector copy these entries, so the two selectors and the
-- vanilla turret-mode dropdown can never drift apart in their labels.
local function directModeOptions()
    local options = {}
    for _, entry in ipairs(Helper.turretModes or {}) do
        if State.isDirectedMode(entry.id) then
            options[#options + 1] = copyTurretModeOption(entry)
        end
    end
    return options
end

-- Forward-declared: restoreDirect's deferred repaint calls refresh(), which is defined below it.
local refresh

-- Give the directed groups a fallback target list for this target. The MD
-- DirectFallback cue uses weaponmode="weaponmode.attackenemies" as its turret
-- selector, so the list only reaches turrets in attackenemies: it is emitted
-- only when the session's Direct-control policy resolves to attackenemies
-- (State.TICK_MODE). Under the autoassist policy the checked groups follow the
-- player's soft target, and a script fallback list neither reaches them nor
-- constrains them, so installing one would be a claim the engine does not
-- make. Fire and forget: MD refuses a payload it cannot resolve, and the worst
-- case of a lost event is a turret that holds fire until the next target change
-- rather than rolling to a fallback, so there is nothing here worth a retry.
-- The fallback is re-sent on every target change because the MD cue names a
-- specific target and dies with it. Live-verified 2026-08-10: attackenemies
-- honours the supplied list even when the pilot is actively fighting
-- (aicommandraw="attackobject"); the old autoassist branch for fighting pilots
-- is now removed.
local function emitDirectFallback(shipID, targetID)
    if isNullID(shipID) or isNullID(targetID) then return false end
    if not session then return false end
    local payload = {
        ["ship"]   = ConvertStringToLuaID(tostring(shipID)),
        ["target"] = ConvertStringToLuaID(tostring(targetID)),
    }
    if State.resolveDirectMode(session) == State.TICK_MODE then
        AddUITriggeredEvent("X4GunneryControl", "direct_fallback", payload)
    end
    -- Arm the ownership-change listener on this specific target. The watch is
    -- policy-independent: autoassist needs the ownership-change cease just as
    -- attackenemies does. Each engage resets the MD DirectWatch.OwnerWatch cue,
    -- so only one target is watched at a time and the prior listener is
    -- cancelled automatically. The listener signals X4GunneryControl.DirectTargetLost
    -- when the target's owner changes to a faction the ship can no longer
    -- attack (surrender, capture). Same payload as direct_fallback: ship+target,
    -- same transport contract.
    -- ponytail: reuses the existing payload table; no second allocation needed.
    AddUITriggeredEvent("X4GunneryControl", "direct_watch", payload)
    return true
end

-- Apply the session's Direct-control policy to the live engine state of every
-- checked mutable group. Called only from the engaged panel's selector: the
-- console's selector is staged-only (Task 2), and the engage path writes the
-- resolved mode itself. A group already in its resolved mode is not written
-- again. Only modes change here -- armed state, the engaged target, the
-- camera, Auto-next, checkbox membership and the committed baseline are all
-- untouched. Under attackenemies the preferred-target/fallback list is
-- re-installed after the mode write, so the MD cue's attackenemies selector
-- reaches the re-moded turrets.
local function applyDirectModeLive()
    for _, group in ipairs(State.checkedGroups(session)) do
        if State.canMutate(group) then
            local mode = State.resolveDirectMode(session, group.key)
            if group.mode ~= mode then
                setMode(group, mode)
                group.mode = mode
            end
        end
    end
    if State.resolveDirectMode(session) == State.TICK_MODE then
        emitDirectFallback(session.shipID, session.aimTargetID)
    end
end

local function restoreDirect(reason)
    if not session then return end
    -- Also before the early return, and for the same reason a level up: the
    -- parked session outlives the baseline. An Auto-engage session still has a
    -- baseline, but its temporary apply writes staged (not direct mode changes),
    -- so restoring it here is correct for both modes.
    clearSnapshot()
    local baseline = State.releaseDirect(session)
    if #baseline == 0 then return end
    local restored, missing = 0, 0
    for _, snapshot in ipairs(baseline) do
        local group = findSnapshotGroup(snapshot)
        if group and sameID(snapshot.shipID, session.shipID) then
            setMode(group, snapshot.mode); setArmed(group, snapshot.armed)
            restored = restored + 1
        else
            -- One destroyed turret group must not prevent restoring the others.
            missing = missing + 1
        end
    end
    if restored > 0 then log("restored directed settings for " .. tostring(restored) .. " group(s): " .. reason) end
    if missing > 0 then log("could not resolve " .. tostring(missing) .. " directed group(s) during restore: " .. reason) end
    -- baseline is closed over; committedBaseline stays on the session so any
    -- subsequent stand-up can also revert, but the deferred check uses this
    -- local copy to avoid re-reading after a session swap.
    local expectedSession, expectedEpoch = session, sessionEpoch
    -- Deferred rather than immediate: the engine's mode read-back lags the
    -- write, so a same-frame refresh() would re-cache the pre-restore value.
    Helper.addDelayedOneTimeCallbackOnUpdate(function()
        if not currentSession(expectedSession, expectedEpoch) then return end
        refresh()
        local mismatches = 0
        for _, snapshot in ipairs(baseline) do
            local found = findSnapshotGroup(snapshot)
            local modeMismatch = found and found.mode ~= snapshot.mode
            local armedMismatch = found and found.armed ~= snapshot.armed
            if not found or modeMismatch or armedMismatch then
                mismatches = mismatches + 1
            end
        end
        if mismatches > 0 then
            log("post-restore readback mismatch for " .. tostring(mismatches) .. " group(s): " .. reason)
        end
        if session.phase ~= "console" then return end
        menu.display()
    end, false, getElapsedTime() + 0.5)
end

local function returnToConsole(reason)
    if not session then return end
    C.SetPlayerCameraCockpitView(true)
    State.returnToConsole(session)
    menu.display()
end

-- This is safe both while a Helper menu is shown and after X4 has already
-- removed its frame. Keep it separate from endSession(), which additionally
-- asks Helper to close the tracked menu.
local function discardSession(reason)
    if not session then return end
    cameraMismatchLogged = false
    mapReopenFailureLogged = false
    containedShipsFailureLogged, containedStationsFailureLogged = false, false
    cutsceneNoTurretFailureLogged = false
    -- Read controlMode BEFORE restoreDirect may clear it. The notify emission
    -- below (when seatLeaving is true) depends on whether this session held an
    -- active direct engagement, not just on the reason code. This read sits in
    -- discardSession rather than leaveChair so the playerGetUp/playerUndock
    -- route (endForMovement -> endSession) is also covered.
    local hadDirectControl = session.controlMode == "direct"
    sessionEpoch = sessionEpoch + 1
    engageabilityCache, engageabilityRequests = {}, {}
    engageabilityRepaintPending = nil
    resumePending = false
    transitionLifecycle("ending", reason)
    clearOwnShipSofttarget()
    restoreDirect(reason)
    AddUITriggeredEvent("X4GunneryControl", "cutscene_aim_stop", {})
    if not seatLeaving then C.SetPlayerCameraCockpitView(true) end
    session = nil
    logSession("session discarded: " .. reason)
    -- ponytail: this popup is a real user-facing feature AND is load-bearing.
    -- X4 engine bug (confirmed by three in-game trials): calling
    -- SetPlayerCameraTargetView from a turret seat leaves the Esc key dead
    -- after the player gets up. SetPlayerCameraCockpitView does not undo it;
    -- every readable engine flag (views, fsmenu, softtarget, HUD, cutscene,
    -- external view, conversation, direct input, player controls) is
    -- byte-identical while broken and while working. The only observed cure is
    -- a subsequent menu that calls CreateView/DisplayView — i.e.
    -- View.createView() in ego_viewhelper/viewhelper.lua:38, which runs only
    -- when View.frames is empty. Our teardown only reaches View.hideView(), so
    -- it never creates again and never cures itself. The show_help action in
    -- the Notify MD cue forces View.createView/DisplayView, which resets the
    -- engine's input context.
    -- Known ceiling: if the player has hints/help texts disabled in game
    -- options the popup may not display and the Esc bug would return. The real
    -- upgrade path is a direct engine call to reset the input context if one is
    -- ever found among the undeclared exports. Do NOT make this popup
    -- conditional or suppress it without re-testing Esc after a camera session.
    -- Ordering is load-bearing too: View.registerMenu only reaches createView()
    -- when View.frames is empty (viewhelper.lua:110-166), and our own frame is
    -- still registered here. This works only because MD handles the event a
    -- tick later, after leaveChair's deferred Helper.closeMenu. No unit test
    -- can catch a regression here — the Lua tests stub the view layer.
    -- See .agents/skills/research-x4-modding/references/ui-lua-menu-camera.md.
    -- Guard: only emit when the player is actually leaving the seat. The
    -- "stale session before chair redirect" call site in the gameplanchange
    -- handler does NOT set seatLeaving, so it stays silent (the player has just
    -- sat down there; a popup would be wrong).
    if seatLeaving then
        local notifyMsg = hadDirectControl and text(79) or text(80)
        AddUITriggeredEvent("X4GunneryControl", "notify", { ["text"] = notifyMsg })
    end
end

-- Helper.closeMenu() untracks the menu and only then lets clearMenu()
-- unregister its views (helper.lua:1908-1947). We used to unregister first, as
-- a guess at the missing-HUD bug; it never helped, and hiding the view while
-- the menu was still tracked is the one thing this teardown did that no vanilla
-- menu does. The views= field of the state lines confirms nothing is left
-- registered afterwards. Deliberately no fallback pass: if clearMenu() ever
-- does skip a frame, views= will say so in the log.
local function endSession(reason)
    if endingSession then return end
    if not session and not menu.shown then return end
    endingSession = true
    discardSession(reason)
    menu.elementFrame = nil
    -- Use the full helper even after another menu hid this frame: clearMenu()
    -- alone does not remove X4's tracked-menu record.
    Helper.closeMenu(menu, "close", false, false)
    endingSession = false
end

-- Helper's automatic onHide path invokes menu.cleanup() and then clearMenu()
-- without consulting menu.onCloseElement(). Treat any such unplanned loss of
-- ownership as a safety event, never as an active gunnery session.
function menu.cleanup()
    menu.frame = nil
    local externalMenu = activeExternalMenuName and activeExternalMenuName()
    if session and not endingSession and externalMenu == "MapMenu" and State.isOwned(session) then
        -- Helper's automatic onHide route bypasses onCloseElement(). Map is the
        -- only external menu for which we have a verified cleanup callback, so
        -- preserve the session here before Helper clears menu.shown.
        transitionLifecycle(State.lifecycle.suspendedMap, "automatic MapMenu frame hide")
        session.autoHideAt = nil
    elseif session and not endingSession and not State.isMapSuspended(session) then
        -- Do not destroy immediately: X4 may still be finishing a same-tick
        -- view replacement. The global watchdog confirms that ownership did
        -- not return before restoring the directed group.
        session.autoHideAt = GetCurRealTime()
    end
end

-- The soft target is X4's global selection, not ours: enterCamera borrows it to
-- force the camera onto a turret and puts it back a tick later. No vanilla call
-- ever passes 0 to SetSofttarget -- RemoveSofttarget() is the engine's clear
-- (targetsystem.lua:1747,2097,2130, and TestAPI.verifyTestGroup below) -- so
-- restoring an empty selection with 0 left it on one of our own turrets, which
-- is a state vanilla never produces: buttonExternal refuses to target-view the
-- player's own ship at all (menu_interactmenu.lua:2231).
local function restoreSofttarget(previousID, previousConnection)
    if isNullID(previousID) then
        RemoveSofttarget()
    else
        C.SetSofttarget(previousID, previousConnection)
    end
end

-- Belt for the restore above, whose callback is epoch-guarded: a session that
-- ends in the 0.05 s between the borrow and the restore never puts the
-- selection back at all, and the player is left soft-targeting their own hull.
clearOwnShipSofttarget = function()
    if not session then return end
    local current = C.GetSofttarget2().softtargetID
    if isNullID(current) then return end
    local root = C.GetContextByClass(id(current), "container", true)
    if sameID(root ~= 0 and root or id(current), session.shipID) then
        RemoveSofttarget()
    end
end

local function leaveChair(reason)
    -- discardSession (called below) handles restoreDirect and clearOwnShipSofttarget.
    -- Stop the cutscene before standing up: discardSession() emits the same
    -- event, but MD handles it a tick later, i.e. after GetUp() has already
    -- changed the camera.
    AddUITriggeredEvent("X4GunneryControl", "cutscene_aim_stop", {})
    C.SetPlayerCameraCockpitView(true)
    seatLeaving = true
    if not C.GetUp() then
        seatLeaving = false
        log("could not get up from gunnery chair")
        if session then menu.display() end
        return false
    end
    -- Close on a later tick, the way vanilla does: DockedMenu's Get Up button
    -- only calls GetUp() and closes from the playerGetUp event
    -- (menu_docked.lua:283,1442). Closing synchronously unregisters our
    -- keepHUDVisible=false view in the middle of the engine's get-up
    -- transition, which is the remaining suspect for the standing player having
    -- no HUD. The playerGetUp handler usually gets here first; this callback is
    -- the fallback for bridge assets that never deliver the event.
    -- Tear the session down now; only the frame teardown is deferred.
    -- discardSession emits the notify (seatLeaving=true) covering both this
    -- path and the playerGetUp/playerUndock route (endForMovement).
    discardSession(reason)
    Helper.addDelayedOneTimeCallbackOnUpdate(function()
        -- Not endSession(): the session is already gone, and its
        -- "nothing to do" guard would skip the frame teardown entirely.
        menu.elementFrame = nil
        Helper.closeMenu(menu, "close", false, false)
        seatLeaving = false
    end, false, getElapsedTime() + 0.05)
    return true
end

local targetRoot, isEligibleEngagementTarget, cycleTarget

-- X4 resolves an own-turret target view to the turret's container on small
-- ships (verified on a Katana, an M corvette): the readback is the ship, not the
-- turret we asked for. The camera is still where we pointed it, so treat the
-- container as a match. Capital ships resolve to the turret component itself.
local function cameraFocusMatches(componentID)
    local focus = C.GetExternalTargetViewComponent()
    return focus ~= 0
        and (sameID(focus, componentID) or sameID(focus, targetRoot(componentID)))
end

local function enterCamera(member, options)
    if not member or member.operational == false or not member.cameraSupported then return false end
    local expectedSession, expectedEpoch = session, sessionEpoch
    local function stillCurrent()
        return currentSession(expectedSession, expectedEpoch)
            and session.cameraMemberID ~= nil and sameID(session.cameraMemberID, member.componentID)
    end
    local function finish()
        if not stillCurrent() then return end
        if options and options.onReady then
            options.onReady(member)
        elseif session.phase == "engaged" then
            -- Validate temporary turret focus before applying Target POV or a
            -- cinematic. Doing it in the opposite order lets the delayed gate
            -- overwrite the caller's intended final view.
            applyPov()
        end
    end
    C.SetPlayerCameraTargetView(member.componentID, true)
    -- X4 resolves this asynchronously. Some bridges only accept a selected
    -- surface element, so retry once with a temporary soft target and restore it.
    local savedTarget = C.GetSofttarget2()
    local savedTargetID, savedConnection = savedTarget.softtargetID, str(savedTarget.softtargetConnectionName)
    Helper.addDelayedOneTimeCallbackOnUpdate(function()
        if not stillCurrent() then return end
        if cameraFocusMatches(member.componentID) then
            finish()
            return
        end
        C.SetSofttarget(member.componentID, "")
        C.SetPlayerCameraTargetView(member.componentID, true)
        Helper.addDelayedOneTimeCallbackOnUpdate(function()
            if not currentSession(expectedSession, expectedEpoch) then return end
            restoreSofttarget(savedTargetID, savedConnection)
            if not cameraFocusMatches(member.componentID) then
                log("camera gate failed for turret " .. tostring(member.componentID))
                if options and options.onFailure then
                    options.onFailure(member)
                    return
                end
                restoreDirect("camera gate failure")
                if isInGunnerChair() then returnToConsole("camera gate failure") end
                return
            end
            finish()
        end, false, getElapsedTime() + 0.05)
    end, false, getElapsedTime() + 0.05)
    return true
end

local function startAutoEngage(groups)
    restoreDirect("auto-engage")
    -- Temporary commit: write staged to the ship for all groups before engaging.
    -- committedBaseline is not updated; stand-up reverts to the baseline.
    for _, group in ipairs(session.groups or {}) do
        local s = session.staged and session.staged[group.key]
        if s and State.canMutate(group) then
            -- A checked group's staged mode is the session's Direct-control
            -- policy, but Auto-engage has no Direct-control target selection,
            -- so it must not arm that policy live: every checked group goes
            -- live in the plain attackenemies engine mode (State.TICK_MODE),
            -- whatever session.directMode currently is. The staged entry is
            -- left untouched -- policy mode and preTickMode included -- so a
            -- later Direct-control engage re-resolves session.directMode
            -- exactly as before.
            local checked = session.checkedGroupKeys
                and session.checkedGroupKeys[group.key] == true
            local mode = checked and State.TICK_MODE or s.mode
            setMode(group, mode); setArmed(group, s.armed)
        end
    end
    State.beginEngaged(session, groups, "auto")
    local member = cameraMember()
    if not member then State.returnToConsole(session); return false end
    if not enterCamera(member) then State.returnToConsole(session); return false end
    -- Auto-engage was never parked, so a save/load or a UI reload during it
    -- dropped the player back at the console. It overrides no turret modes and
    -- so needs no safety record, but the camera, the checked groups and the
    -- phase are worth just as much here as in Direct control, and the payload
    -- already carries controlMode.
    persistSession()
    -- Finish the button callback before replacing the blurred console frame.
    -- Rebuilding a view during the click dispatch can leave the old frame
    -- visible until a second click on some X4/UI Extensions combinations.
    local expectedSession, expectedEpoch = session, sessionEpoch
    Helper.addDelayedOneTimeCallbackOnUpdate(function()
        if currentSession(expectedSession, expectedEpoch)
            and session.phase == "engaged" and session.controlMode == "auto" then
            menu.display()
        end
    end, false, getElapsedTime() + 0.01)
    return true
end

local function startTargetSelection(groups)
    -- Refuse when no checked group can be mutated.
    local anyMutable = false
    for _, g in ipairs(groups or {}) do if State.canMutate(g) then anyMutable = true; break end end
    if not anyMutable then return false end
    -- Use the first mutable group's first operational member for selectedGroupKey/Member.
    local group, member
    for _, g in ipairs(groups or {}) do
        if State.canMutate(g) then
            group = g
            for _, m in ipairs(g.members or {}) do
                if m.operational then member = m; break end
            end
            break
        end
    end
    if not member then return false end
    restoreDirect("new engagement")
    State.beginTargetSelection(session, group, member)
    -- Losing the camera must not cost the player target selection: log it and
    -- keep the browser open instead of bouncing back to the console.
    local cameraOptions = { onFailure = function() log("target selection continues without a camera") end }
    if not enterCamera(member, cameraOptions) then State.returnToConsole(session); return false end
    local expectedSession, expectedEpoch = session, sessionEpoch
    Helper.addDelayedOneTimeCallbackOnUpdate(function()
        if currentSession(expectedSession, expectedEpoch) and session.phase == "target_select" then menu.display() end
    end, false, getElapsedTime() + 0.01)
    return true
end

local function openTargetBrowser()
    if not session or session.controlMode ~= "direct" then return false end
    session.phase = "target_select"
    menu.display()
    return true
end

local function engageTarget(targetID)
    if targetID == nil then return false end
    local target = id(targetID)
    if target == 0 or not isEligibleEngagementTarget(target) then
        log("refused ineligible engagement target (own ship or player-owned) " .. tostring(targetID))
        return false
    end
    if not C.SetSofttarget(target, "") then
        log("could not set selected engagement target " .. tostring(targetID))
        return false
    end
    local member = cameraMember()
    if not member then return false end
    if not enterCamera(member) then return false end
    if session.controlMode == "direct" then
        -- Re-engagement: re-point the soft target and set phase back to engaged.
        -- committedBaseline and staged are already in place.
        session.phase, session.controlMode = "engaged", "direct"
    else
        -- First engagement: write staged to the ship (temporary commit point),
        -- then arm only the checked mutable groups in the session's resolved
        -- Direct-control mode.
        -- committedBaseline is NOT updated here — that is reserved for the
        -- "Update turret behavior" commit.
        local orderable = {}
        for _, group in ipairs(State.checkedGroups(session)) do
            if State.canMutate(group) then orderable[#orderable + 1] = group end
        end
        State.beginEngaged(session, orderable, "direct")
        -- Apply the whole staged config to the ship (temp apply, all groups).
        -- The bookkeeping below is what makes the arm step's skip correct: it
        -- records what the engine now actually has.
        for _, group in ipairs(session.groups or {}) do
            local s = session.staged and session.staged[group.key]
            if s and State.canMutate(group) then
                setMode(group, s.mode); setArmed(group, s.armed)
                group.mode, group.armed = s.mode, s.armed
            end
        end
        -- Arm the directed (checked) groups in the session's Direct-control
        -- mode. Live-verified 2026-08-10: attackenemies honours the supplied
        -- fallback list even when the pilot is actively fighting.
        for _, group in ipairs(orderable) do
            local mode = State.resolveDirectMode(session, group.key)
            if group.mode ~= mode then setMode(group, mode); group.mode = mode end
            if group.armed ~= true then setArmed(group, true); group.armed = true end
        end
    end
    -- Record the chosen element and its root object. aimTargetID may be a
    -- surface element; targetObjectID is always the ship/station root so that
    -- cycleTarget and the element panel can identify the engaged object.
    session.aimTargetID = target
    session.targetObjectID = targetRoot(target)
    if session.surfaceBrowser then
        session.surfaceBrowser.pendingReason = "open"
    end
    -- Hand the directed groups a fallback list for this target. The MD
    -- DirectFallback cue uses weaponmode.attackenemies as its selector and
    -- reaches the directed groups. A turret with no firing solution on the
    -- preferred target rolls to the next best hostile rather than tracking in
    -- silence (Tests B/C/D, 2026-08-09; live confirmed 2026-08-10).
    emitDirectFallback(session.shipID, target)
    -- A target click and the replacement compact frame occur on separate UI
    -- ticks. Keep this explicit so an auto-hide or failed frame creation can
    -- restore the snapshot rather than leaving autoassist armed invisibly.
    session.engagePending = true
    session.engagePendingSince = GetCurRealTime()
    -- Persist AFTER aimTargetID/targetObjectID are set, not alongside the
    -- snapshot: the engine drops the soft target across a reload, so a payload
    -- written before this point would come back without a target.
    persistSession()
    local expectedSession, expectedEpoch = session, sessionEpoch
    Helper.addDelayedOneTimeCallbackOnUpdate(function()
        if currentSession(expectedSession, expectedEpoch)
            and session.phase == "engaged" and session.controlMode == "direct" then
            menu.display()
        end
    end, false, getElapsedTime() + 0.01)
    return true
end

-- Forward-declared above restoreDirect; see the contract comment there.
refresh = function()
    if not session then return end
    State.retainSelection(session, readGroups(session.shipID))
end

-- "Update turret behavior" commit. Writes the staged config to every mutable
-- group and advances committedBaseline so a later stand-up reverts to this new
-- state rather than to what the ship looked like at sit-down. Only the main
-- console renders this button; engaged panels omit it.
local function commitStagedTurretBehavior()
    if not session then return end
    local written = 0
    for _, group in ipairs(session.groups or {}) do
        local s = session.staged and session.staged[group.key]
        if s and State.canMutate(group) then
            setMode(group, s.mode); setArmed(group, s.armed)
            written = written + 1
        end
    end
    -- The only permanent write the console makes. Worth a line: everything else
    -- reverts on stand up, so this is the one action whose effect outlives the
    -- session and the one to look for when a setting unexpectedly persisted.
    log("committed turret behavior for " .. tostring(written) .. " group(s)")
    State.commitStagedToBaseline(session)
    persistSession()
    menu.display()
end

local function relationLabel(component)
    local isenemy, ishostile, isfriend = componentData(component, "isenemy", "ishostile", "isfriend")
    if isenemy then return text(39), 1 end
    if ishostile then return text(40), 2 end
    if isfriend then return text(41), 4 end
    return text(42), 3
end

local function targetClassLabel(component, kind)
    local object = id(component)
    if C.IsComponentClass(object, "ship_s") then return "S Ship" end
    if C.IsComponentClass(object, "ship_m") then return "M Ship" end
    if C.IsComponentClass(object, "ship_l") then return "L Ship" end
    if C.IsComponentClass(object, "ship_xl") then return "XL Ship" end
    if C.IsComponentClass(object, "station") then return text(45) end
    return kind
end

local function targetTypeLabel(macro)
    if macro == "" then return text(51) end
    local name = tostring(GetMacroData(macro, "name") or "")
    return name ~= "" and name or text(51)
end

local function checkedOperationalTurrets()
    local members, seen = {}, {}
    for _, group in ipairs(State.checkedGroups(session)) do
        for _, member in ipairs(group.members or {}) do
            local key = State.normID(member.componentID)
            if member.operational and not seen[key] then
                seen[key] = true
                members[#members + 1] = member
            end
        end
    end
    table.sort(members, function(a, b)
        return State.normID(a.componentID) < State.normID(b.componentID)
    end)
    return members
end

-- Lua owns exact checkbox membership and MD owns the raycast. Flat scalar
-- events avoid relying on unproven nested-table transport: selected turret ids
-- are streamed once, followed by at most 20 target ids for the batch.
local engageabilityBatchSize = 20
local function requestEngageabilities(targets, purpose)
    local results = {}
    if not session then return results end
    local members, signatureParts = checkedOperationalTurrets(), {}
    for _, member in ipairs(members) do
        signatureParts[#signatureParts + 1] = State.normID(member.componentID)
    end
    local signature = table.concat(signatureParts, ",")
    local now, pending, seen = getElapsedTime(), {}, {}
    -- Normally MD follows the final result immediately with batch completion.
    -- If only that aggregate event is lost, retain the empty request briefly so
    -- a late completion can still be audited, then reclaim it before the next
    -- completed-result cache refresh.
    for nonce, request in pairs(engageabilityRequests) do
        if request.resultsCompleteAt and now - request.resultsCompleteAt >= 1 then
            engageabilityRequests[nonce] = nil
        end
    end
    for position, target in ipairs(targets or {}) do
        if not State.isNullID(target) then
            local targetKey = State.normID(target)
            local key = tostring(sessionEpoch) .. ":" .. targetKey
            local cached = engageabilityCache[key]
            if cached and cached.signature == signature then
                if cached.pending and now - cached.requestedAt < 2 then
                    results[position] = cached
                elseif not cached.pending and now - cached.requestedAt < 1 then
                    results[position] = cached
                end
            end
            if not results[position] then
                if #members == 0 then
                    cached = { engageable = 0, total = 0, signature = signature, requestedAt = now }
                    engageabilityCache[key] = cached
                else
                    -- Supersede only this target in an older batch. The older
                    -- request remains alive for its other correlated targets.
                    if cached and cached.pendingNonce then
                        local previousNonce = cached.pendingNonce
                        local previous = engageabilityRequests[previousNonce]
                        if previous then
                            previous.targets[targetKey] = nil
                            if next(previous.targets) == nil then engageabilityRequests[previousNonce] = nil end
                        end
                    end
                    cached = cached and cached.signature == signature and cached or {}
                    cached.signature, cached.requestedAt, cached.pending, cached.total,
                        cached.engageable, cached.known = signature, now, true, #members, nil, nil
                    engageabilityCache[key] = cached
                    if not seen[targetKey] then
                        seen[targetKey] = true
                        pending[#pending + 1] = { target = target, targetKey = targetKey, key = key, cached = cached }
                    end
                end
                results[position] = cached
            end
        end
    end

    for first = 1, #pending, engageabilityBatchSize do
        local last = math.min(first + engageabilityBatchSize - 1, #pending)
        engageabilitySerial = engageabilitySerial + 1
        local nonce = tostring(sessionEpoch) .. "_" .. tostring(engageabilitySerial)
        local request = {
            epoch = sessionEpoch, signature = signature, selectedTotal = #members,
            targets = {}, requested = last - first + 1, purpose = purpose,
        }
        engageabilityRequests[nonce] = request
        AddUITriggeredEvent("X4GunneryControl", "engageability_begin", {
            nonce = nonce, members = #members, targets = request.requested,
        })
        for _, member in ipairs(members) do
            -- GetUpgradeGroupInfo2.currentmacro is the authoritative installed
            -- equipment macro. Live surface components can return an empty
            -- The component-data macro field can be blank for installed surface
            -- components, so use that fallback only for ungrouped
            -- singleton weapons whose group metadata has no macro.
            local macro = tostring(member.macro or "")
            if macro == "" then macro = tostring(componentData(member.componentID, "macro") or "") end
            local arc = TurretArcLimits[macro]
            AddUITriggeredEvent("X4GunneryControl", "engageability_member", {
                nonce = nonce, weapon = id(member.componentID), arcknow = arc and 1 or 0,
                arcmin = arc and arc[1] or 0, arcmax = arc and arc[2] or 0 })
        end
        for index = first, last do
            local entry = pending[index]
            entry.cached.pendingNonce = nonce
            request.targets[entry.targetKey] = entry.key
            AddUITriggeredEvent("X4GunneryControl", "engageability_target", {
                nonce = nonce, target = id(entry.target),
            })
        end
        AddUITriggeredEvent("X4GunneryControl", "engageability_commit", { nonce = nonce })
        log("event=engageability_batch action=request nonce=" .. nonce
            .. " requested=" .. tostring(request.requested)
            .. " selected_total=" .. tostring(#members)
            .. " selected_signature=" .. string.format("%q", signature))
    end
    return results
end

local function requestEngageability(target, purpose)
    return requestEngageabilities({ target }, purpose)[1]
end

local function engageabilityText(result)
    if not result then return "-" end
    if result.pending and result.engageable == nil then return "… / " .. tostring(result.total) end
    local label = tostring(result.engageable or 0) .. " / " .. tostring(result.total or 0)
    local unknown = math.max(0, (result.total or 0) - (result.known or 0))
    if unknown > 0 then return label .. "  " .. tostring(unknown) .. " " .. text(100) end
    if (result.total or 0) > 0 and result.engageable == result.total then return label .. "  " .. text(89) end
    return label
end

local function engageabilityAudit(result)
    if not result then return "unavailable", "-", 0, 0 end
    if result.pending then return "pending", "-", 0, result.total or 0 end
    return "complete", result.engageable or 0, result.known or 0, result.total or 0
end

-- A target/surface render can issue dozens of independent MD requests. Their
-- replies commonly arrive in the same UI tick; rebuilding the complete menu
-- for every reply makes enumeration and audit logging quadratic in row count.
-- One tokenized callback repaints the whole accepted batch. A token survives
-- stale callbacks safely when session teardown resets the pending marker.
local function scheduleEngageabilityRepaint(purpose)
        if purpose == "surface_pinned" then
        if surfacePinnedUpdatePending then return end
        surfacePinnedUpdatePending = true
        local expectedSession, expectedEpoch = session, sessionEpoch
        Helper.addDelayedOneTimeCallbackOnUpdate(function()
            surfacePinnedUpdatePending = false
            if not currentSession(expectedSession, expectedEpoch) or not menu.shown then return end
            if session.phase == "engaged" and session.controlMode == "direct" and menu.elementFrame then
                local browser = session.surfaceBrowser
                local pinnedID = session.aimTargetID or session.targetObjectID
                local result = browser and browser.pinnedResult
                local state, engageable, known, total = engageabilityAudit(result)
                local shielded, shieldpercent, hullpercent = surfaceHealth(pinnedID)
                log("event=surface_pinned action=refresh component=" .. tostring(pinnedID)
                    .. " engageability_state=" .. state .. " engageability_engageable=" .. tostring(engageable)
                    .. " engageability_known=" .. tostring(known)
                    .. " engageability_total=" .. tostring(total)
                    .. " distance=" .. tostring(browser and browser.pinnedDistance or -1)
                    .. " shield_capacity=" .. tostring(shielded)
                    .. " shield_percent=" .. tostring(shieldpercent)
                    .. " hull_percent=" .. tostring(hullpercent))
                menu.elementFrame:update()
            end
        end, false, getElapsedTime() + 0.01)
        return
    end
    if engageabilityRepaintPending then return end
    engageabilityRepaintSerial = engageabilityRepaintSerial + 1
    local token = engageabilityRepaintSerial
    engageabilityRepaintPending = token
    local expectedSession, expectedEpoch = session, sessionEpoch
    Helper.addDelayedOneTimeCallbackOnUpdate(function()
        if engageabilityRepaintPending ~= token then return end
        engageabilityRepaintPending = nil
        if not currentSession(expectedSession, expectedEpoch) or not menu.shown then return end
        if session.phase == "target_select"
                or (session.phase == "engaged" and session.controlMode == "direct") then
            menu.display()
        end
    end, false, getElapsedTime() + 0.01)
end

local function onEngageabilityResult(_, param)
    local nonce, targetKey, engageable, known, total = tostring(param or ""):match(
        "^x4gce3:([^:]+):([^:]+):(%d+):(%d+):(%d+)$")
    local request = nonce and engageabilityRequests[nonce]
    if not request or not session or request.epoch ~= sessionEpoch then return end
    engageable, known, total = tonumber(engageable), tonumber(known), tonumber(total)
    if total ~= request.selectedTotal or known > total or engageable > known then return end
    targetKey = State.normID(targetKey)
    local key = request.targets[targetKey]
    local cached = key and engageabilityCache[key]
    if not cached or cached.signature ~= request.signature or cached.pendingNonce ~= nonce then return end
    cached.engageable, cached.known, cached.total, cached.pending, cached.pendingNonce, cached.receivedAt =
        engageable, known, total, false, nil, getElapsedTime()
    request.targets[targetKey] = nil
    if next(request.targets) == nil then request.resultsCompleteAt = cached.receivedAt end
    if session.phase == "target_select" or (session.phase == "engaged" and session.controlMode == "direct") then
        scheduleEngageabilityRepaint(request.purpose)
    end
end


local function onEngageabilityBatchComplete(_, param)
    local nonce, accepted, completed = tostring(param or ""):match("^x4gce2c:([^:]+):(%d+):(%d+)$")
    local request = nonce and engageabilityRequests[nonce]
    if not request or not session or request.epoch ~= sessionEpoch then return end
    local unresolved = 0
    for _, key in pairs(request.targets) do
        local cached = engageabilityCache[key]
        if cached and cached.signature == request.signature and cached.pendingNonce == nonce then
            cached.pendingNonce = nil
            unresolved = unresolved + 1
        end
    end
    engageabilityRequests[nonce] = nil
    log("event=engageability_batch action=complete nonce=" .. nonce
        .. " requested=" .. tostring(request.requested)
        .. " accepted=" .. tostring(accepted)
        .. " completed=" .. tostring(completed)
        .. " unresolved=" .. tostring(unresolved))
end

targetRoot = function(component)
    local root = C.GetContextByClass(id(component), "container", true)
    return root ~= 0 and root or id(component)
end

isEligibleEngagementTarget = function(component)
    local object = targetRoot(component)
    -- Player-faction-owned ships and stations must never appear as targets.
    -- This check sits here rather than in State so it can call componentData,
    -- and because force=true in add() only bypasses visibility/range — not
    -- this function — so a player-owned soft target is excluded too.
    if componentData(object, "isplayerowned") then return false, object end
    return State.isEngagementTargetAllowed(session and session.shipID, object), object
end

local function readTargetCandidates()
    local candidates, seen = {}, {}
    local sector = GetPlayerContextByClass("sector")
    local radarRange = tonumber(componentData(session.shipID, "maxradarrange")) or 40000
    if radarRange <= 0 then radarRange = 40000 end

    local function add(component, kind, force)
        local eligible, object = isEligibleEngagementTarget(component)
        local key = tostring(object)
        if not eligible or seen[key] then return end
        local known, radarVisible = componentData(object, "isknown", "isradarvisible")
        if (known == false or radarVisible == false) and not force then return end
        local distance = tonumber(C.GetDistanceBetween(session.shipID, object)) or -1
        if not force and distance >= 0 and distance > radarRange then return end
        local relation, priority = relationLabel(object)
        local macro = tostring(componentData(object, "macro") or "")
        seen[key] = true
        candidates[#candidates + 1] = {
            componentID = object, name = str(C.GetComponentName(object)), kind = kind,
            class = targetClassLabel(object, kind), macro = macro, typeName = targetTypeLabel(macro),
            relation = relation, priority = priority, distance = distance,
        }
    end

    local current = C.GetSofttarget2()
    if current.softtargetID ~= 0 then add(current.softtargetID, text(43), true) end
    if sector then
        local okShips, ships = pcall(GetContainedShips, sector, true)
        if okShips then
            containedShipsFailureLogged = false
            for _, ship in ipairs(ships or {}) do add(ship, text(44), false) end
        elseif not containedShipsFailureLogged then
            containedShipsFailureLogged = true
            log("GetContainedShips failed: " .. tostring(ships))
        end
        local okStations, stations = pcall(GetContainedStations, sector, true, false)
        if okStations then
            containedStationsFailureLogged = false
            for _, station in ipairs(stations or {}) do add(station, text(45), false) end
        elseif not containedStationsFailureLogged then
            containedStationsFailureLogged = true
            log("GetContainedStations failed: " .. tostring(stations))
        end
    end
    table.sort(candidates, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        if a.distance ~= b.distance then
            if a.distance < 0 then return false end
            if b.distance < 0 then return true end
            return a.distance < b.distance
        end
        return a.name < b.name
    end)
    return candidates
end

-- Is there anything to cycle to? The only reader of a memoised sweep, and the
-- reason readTargetCandidates() itself stays always-fresh: every other caller
-- (browser, cycleTarget, chooseAimTarget) wants live data. A 1 s TTL lets the
-- four 0.25 s repaints that draw the cycle-target buttons share one sector
-- sweep. An empty result is memoised too: a sector full of ineligible objects
-- is the most expensive sweep there is, and repeating it per repaint is exactly
-- the cost this exists to avoid. Auto-invalidates when sessionEpoch changes.
local targetCandidatesTime = -math.huge
local targetCandidatesEpoch = -1
local targetCandidatesCount = 0
local function hasMultipleTargets()
    local now = getElapsedTime()
    if targetCandidatesEpoch == sessionEpoch and now - targetCandidatesTime < 1 then
        return targetCandidatesCount > 1
    end
    targetCandidatesTime = now
    targetCandidatesEpoch = sessionEpoch
    targetCandidatesCount = #readTargetCandidates()
    return targetCandidatesCount > 1
end

cycleTarget = function(delta)
    if not session or session.controlMode ~= "direct" then return false end
    local entry = State.cycleEntry(readTargetCandidates(), session.targetObjectID, delta)
    if not entry then return false end
    return engageTarget(entry.componentID)
end

local function readSurfaceTargets(container)
    local surfaces, seen = {}, {}
    local types = {
        { upgrade = "turret", label = text(46) },
        { upgrade = "shield", label = text(47) },
        { upgrade = "engine", label = text(48) },
    }
    local destructibles = { id(container) }
    if C.IsComponentClass(id(container), "station") then
        local count = tonumber(C.GetNumStationModules(id(container), false, false))
        if count > 0 then
            local modules = ffi.new("UniverseID[?]", count)
            count = tonumber(C.GetStationModules(modules, count, id(container), false, false))
            for i = 0, count - 1 do destructibles[#destructibles + 1] = modules[i] end
        end
    end
    for _, destructible in ipairs(destructibles) do
        for _, surfaceType in ipairs(types) do
            local count = tonumber(C.GetNumUpgradeSlots(destructible, "", surfaceType.upgrade))
            for slot = 1, count do
                local component = C.GetUpgradeSlotCurrentComponent(destructible, surfaceType.upgrade, slot)
                local key = tostring(component)
                if component ~= 0 and not seen[key] and C.IsComponentOperational(component) then
                    seen[key] = true
                    local name = str(C.GetComponentName(component))
                    local module = sameID(destructible, container) and 0 or id(destructible)
                    -- Read the equipment installed in this exact slot. The
                    -- component-data macro was empty on the live Xenon fixture,
                    -- while GetSlotSize described the physical connection and
                    -- could disagree with the equipment actually installed in
                    -- it. Vanilla station configuration uses this API for the
                    -- current equipment macro, whose macro metadata owns the
                    -- equipment's actual size.
                    local macro = str(C.GetUpgradeSlotCurrentMacro(id(container), module,
                        surfaceType.upgrade, slot))
                    if macro == "" then macro = tostring(componentData(component, "macro") or "") end
                    local macroLabel = macro ~= "" and tostring(GetMacroData(macro, "name") or "") or ""
                    local size, sizeSource = surfaceEquipmentSize(macro)
                    surfaces[#surfaces + 1] = {
                        componentID = component, kind = surfaceType.label, kindKey = surfaceType.upgrade,
                        macro = macro, macroLabel = macroLabel ~= "" and macroLabel or text(51),
                        macroLabelResolved = macroLabel ~= "",
                        name = name ~= "" and name or (surfaceType.label .. " " .. tostring(slot)),
                        size = size, sizeSource = sizeSource,
                        distance = surfaceDistance(component),
                    }
                end
            end
        end
    end
    table.sort(surfaces, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.name < b.name
    end)
    return surfaces
end

local surfaceCrossTypePolicy = "size_first"
local function surfaceFilterSignature()
    return tostring(session.surfaceTypeFilter) .. "\31" .. tostring(session.surfaceMacroFilter)
end

local function rebuildSurfaceSnapshot(reason)
    local root = session.targetObjectID
    local browser = session.surfaceBrowser
    if not browser or not sameID(browser.rootID, root) then
        browser = State.newSurfaceBrowser(root)
        session.surfaceBrowser = browser
        reason = reason or "open"
    end
    if not reason and browser.filterSignature ~= surfaceFilterSignature() then reason = "filter" end
    if not reason and browser.allSurfaces then return browser end

    local allSurfaces = readSurfaceTargets(id(root))
    local pinnedID = session.aimTargetID or root
    local alternatives = State.surfaceAlternatives(allSurfaces, pinnedID,
        session.surfaceTypeFilter, session.surfaceMacroFilter)
    table.sort(alternatives, function(a, b)
        return State.surfaceMetadataLess(a, b, surfaceCrossTypePolicy)
    end)
    browser.generation = (browser.generation or 0) + 1
    browser.filterSignature = surfaceFilterSignature()
    browser.allSurfaces, browser.orderedIDs, browser.metadataByID = allSurfaces, {}, {}
    for _, surface in ipairs(allSurfaces) do
        browser.metadataByID[State.normID(surface.componentID)] = surface
    end
    for _, surface in ipairs(alternatives) do
        browser.orderedIDs[#browser.orderedIDs + 1] = State.normID(surface.componentID)
    end
    browser.pageResults, browser.pinnedResult = {}, nil
    browser.page = math.max(1, tonumber(browser.page) or 1)
    local _, normalizedPage, pageCount = State.surfacePage(browser.orderedIDs, browser.page, browser.pageSize)
    browser.page = normalizedPage
    if browser.autoRefresh then browser.nextAutoRefreshAt = getElapsedTime() + 10 end
    log("event=surface_snapshot action=create reason=" .. tostring(reason or "open")
        .. " root=" .. tostring(root)
        .. " generation=" .. tostring(browser.generation)
        .. " type_filter=" .. tostring(session.surfaceTypeFilter)
        .. " equipment_filter=" .. tostring(session.surfaceMacroFilter)
        .. " enumerated=" .. tostring(#allSurfaces)
        .. " eligible=" .. tostring(#browser.orderedIDs)
        .. " pages=" .. tostring(pageCount)
        .. " page=" .. tostring(browser.page))
    return browser
end

local function surfaceMetadata(browser, componentID)
    return browser and browser.metadataByID[State.normID(componentID)]
end

-- Narrow developer hook. Nothing calls or displays this API unless the separate
-- test-lab extension explicitly registers itself after declaring a dependency.
X4GunneryControlAPI = X4GunneryControlAPI or {}
local TestAPI = X4GunneryControlAPI

function TestAPI.registerTestLab(callbacks)
    testLabCallbacks = callbacks
end

-- Exposes the live session reference for unit tests that cannot reach the
-- module-local through public entry points. Do not use in production logic.
function TestAPI.getSession()
    return session
end
function TestAPI.getSessionEpoch()
    return sessionEpoch
end

local function copyCurrentShipSweep(groups)
    if not session or not isInGunnerChair() then return nil, "not seated in gunnery control" end
    local ship = session.shipID
    local result = { id = tostring(ship), name = str(C.GetComponentName(ship)), macro = componentData(ship, "macro"), groups = {} }
    for _, group in ipairs(groups or {}) do
        local copy = { key = group.key, kind = group.kind, name = group.displayName, macro = group.macro or "", contextID = tostring(group.contextID or ""), path = group.path or "", group = group.group or "", componentID = tostring(group.componentID or ""), mutable = State.canMutate(group), armed = group.armed == true, members = {} }
        for _, member in ipairs(group.members) do
            if member.operational then
                copy.members[#copy.members + 1] = { id = tostring(member.componentID), name = member.displayName, macro = componentData(member.componentID, "macro"), cameraSupported = member.cameraSupported }
            end
        end
        table.sort(copy.members, function(a, b) return a.id < b.id end)
        result.groups[#result.groups + 1] = copy
    end
    table.sort(result.groups, function(a, b) return a.key < b.key end)
    return result
end

function TestAPI.getCurrentShipSweep()
    if not session or not isInGunnerChair() then return nil, "not seated in gunnery control" end
    refresh()
    return copyCurrentShipSweep(session.groups)
end

-- Fresh hardware view for scenario preflight/revalidation. Unlike refresh(),
-- this must not reconcile or otherwise mutate the parked Gunnery session.
function TestAPI.getCurrentShipSweepReadOnly()
    if not session or not isInGunnerChair() then return nil, "not seated in gunnery control" end
    return copyCurrentShipSweep(readGroups(session.shipID))
end

function TestAPI.isDirectControlActive()
    return session ~= nil and session.controlMode == "direct"
        and (session.phase == "engaged" or session.phase == "target_select")
end

function TestAPI.focusTestTurret(memberID)
    if not session or not isInGunnerChair() then return false, "not seated in gunnery control" end
    local component = id(memberID)
    if not C.IsComponentOperational(component) or not C.IsPlayerCameraTargetViewPossible(component, true) then return false, "camera unsupported or turret unavailable" end
    testCameraFailures[tostring(component)] = nil
    return enterCamera({ componentID = component, cameraSupported = true }, { onFailure = function(member) testCameraFailures[tostring(member.componentID)] = true end })
end

-- Test-only entry point for asserting that the delayed gate completes before
-- the requested session POV is applied.
function TestAPI.enterCamera(member, options) return enterCamera(member, options) end
function TestAPI.engageTarget(targetID) return engageTarget(targetID) end

function TestAPI.getCameraFocus()
    return tostring(C.GetExternalTargetViewComponent())
end

function TestAPI.getTestSofttarget()
    local target = C.GetSofttarget2()
    local targetID, connection = target.softtargetID, str(target.softtargetConnectionName)
    if targetID == 0 then return { id = "0", connection = "", name = "", macro = "" } end
    return { id = tostring(targetID), connection = connection, name = str(C.GetComponentName(targetID)), macro = componentData(targetID, "macro") }
end

-- Test Lab's automatic geometry snapshot is measured in unpaused engagement
-- time. Keep the engine pause query behind the existing developer bridge so
-- the companion extension does not need to duplicate this module's FFI.
function TestAPI.isGamePaused()
    return C.IsGamePaused()
end

function TestAPI.testCameraFailed(memberID)
    return testCameraFailures[tostring(memberID)] == true
end

function TestAPI.returnTestCamera()
    C.SetPlayerCameraCockpitView(true)
end

-- ponytail: these are live-test prototype buttons — wrap-up or delete once the
-- cutscene aim experiment concludes.
local function sendCutsceneAimStop()
    AddUITriggeredEvent("X4GunneryControl", "cutscene_aim_stop", {})
end

local function sendCutsceneAimStart(pov)
    -- Cleared on every start, including the retarget restart, so the gap
    -- between stop and start is never read as "the player left the cinematic".
    if session then session.cinematicSeen = nil end
    if not session or session.phase ~= "engaged" then
        return
    end
    local turretID = session.cameraMemberID
    -- Prefer session.aimTargetID (set by updateAimTarget / engageTarget) so
    -- step 8 auto-retarget works correctly; fall back to the current soft target.
    local targetID = session.aimTargetID
    if isNullID(targetID) then
        local softtarget = C.GetSofttarget2()
        targetID = softtarget.softtargetID
    end
    if isNullID(turretID) then
        if not cutsceneNoTurretFailureLogged then
            cutsceneNoTurretFailureLogged = true
            log("cutscene aim could not start: no turret resolved")
        end
        return
    end
    if isNullID(targetID) then
        return
    end
    local anchorID, tgtID
    if pov == "target" then
        -- Sit the camera at the softtarget, look at the turret.
        anchorID = targetID
        tgtID = turretID
    else
        -- Default "turret" POV: sit at turret, look at softtarget.
        anchorID = turretID
        tgtID = targetID
    end
    -- Transport contract (live-tested 2026-08-04, final): the engine PREPENDS
    -- $ to every Lua string key during Lua->MD conversion, so plain "anchor"
    -- arrives in MD as the variable key $anchor (read via event.param3.$anchor).
    -- Never pre-prefix $ here — "$anchor" becomes the invalid name $$anchor,
    -- stuck as an unreadable string key. Component ids must be converted via
    -- ConvertStringToLuaID(tostring(id)) — the vanilla pattern in
    -- menu_ship_configuration.lua:1399 — to arrive as MD component objects.
    AddUITriggeredEvent("X4GunneryControl", "cutscene_aim_start", {
        ["anchor"] = ConvertStringToLuaID(tostring(anchorID)),
        ["target"] = ConvertStringToLuaID(tostring(tgtID)),
        ["pov"] = pov,
    })
    cutsceneNoTurretFailureLogged = false
end

function TestAPI.sendCutsceneAimStart(pov) sendCutsceneAimStart(pov) end
function TestAPI.sendCutsceneAimStop() sendCutsceneAimStop() end

-- Single POV applicator. Sets the camera according to session.povAnchor and
-- session.povMode. For "manual" emits cutscene_aim_stop (harmless when idle —
-- the MD cue is guarded), then calls SetPlayerCameraTargetView on the anchor
-- component. For "cinematic" calls sendCutsceneAimStart(povAnchor).
-- Call after updating session.povAnchor / session.povMode.
applyPov = function()
    if not session or session.phase ~= "engaged" then return false end
    local anchor = session.povAnchor or "turret"
    local mode   = session.povMode   or "manual"
    if mode == "cinematic" then
        -- sendCutsceneAimStart reads turret from cameraMemberID and target from
        -- session.aimTargetID (falling back to soft target).
        sendCutsceneAimStart(anchor)
        return true
    end
    -- manual: stop any running cutscene, then point the camera at the anchor.
    sendCutsceneAimStop()
    local componentID
    if anchor == "target" then
        componentID = session.aimTargetID or C.GetSofttarget2().softtargetID
    else
        componentID = session.cameraMemberID
    end
    if isNullID(componentID) then return false end
    -- A restored session carries these as strings rather than ids: the payload is
    -- text, and the target recovered from MD arrives as a plain Lua number. The
    -- FFI call accepts neither and raises "bad argument #1", which is why Target
    -- POV did nothing after a load while the very same component worked once it
    -- had been picked by hand. Normalised here, since every anchor funnels
    -- through this one call.
    componentID = id(componentID)
    local ok, err = pcall(function() C.SetPlayerCameraTargetView(componentID, true) end)
    if ok and anchor == "turret" then session.cameraMemberID = componentID end
    if not ok then log("could not apply " .. anchor .. " POV: " .. tostring(err)) end
    return ok
end

function TestAPI.verifyTestGroup(groupKey)
    if not session or not isInGunnerChair() then return { pass = false, reason = "not seated in gunnery control" } end
    refresh()
    local group = currentGroup(groupKey)
    if not State.canMutate(group) then return { pass = false, reason = "group unavailable" } end
    local snapshot = { mode = group.mode, armed = group.armed }
    local target = C.GetSofttarget2()
    local targetID, targetConnection = target.softtargetID, str(target.softtargetConnectionName)
    -- Clear the current soft target while the group is armed. This test never
    -- issues a fire command and immediately restores target and settings.
    RemoveSofttarget()
    if C.GetSofttarget2().softtargetID ~= 0 then
        C.SetSofttarget(targetID, targetConnection)
        return { pass = false, applied = false, restored = true, reason = "target_clear_failed", mode = snapshot.mode, armed = snapshot.armed }
    end
    local applied, restored, restoreOK = false, false, false
    local reason = ""
    local ok, err = pcall(function()
        setMode(group, "autoassist"); setArmed(group, true); refresh()
        local active = currentGroup(groupKey)
        applied = active and active.mode == "autoassist" and active.armed
    end)
    if not ok then reason = "apply_exception:" .. tostring(err) elseif not applied then reason = "apply_mismatch" end
    local restoreCallOK, restoreErr = pcall(function()
        refresh(); local active = currentGroup(groupKey)
        if active then setMode(active, snapshot.mode); setArmed(active, snapshot.armed) end
        refresh(); active = currentGroup(groupKey)
        restored = active and active.mode == snapshot.mode and active.armed == snapshot.armed
    end)
    restoreOK = restoreCallOK
    if not restoreCallOK then reason = "restore_exception:" .. tostring(restoreErr) elseif not restored then reason = "restore_mismatch" end
    C.SetSofttarget(targetID, targetConnection)
    return { pass = ok and applied and restoreOK and restored, applied = applied, restored = restored, reason = reason, mode = snapshot.mode, armed = snapshot.armed }
end

-- Returns the first entry of readTargetCandidates() that is still operational.
-- readTargetCandidates() already sorts enemy -> hostile -> nearest, so entry 1
-- is the best available target. Returns nil when nothing qualifies.
local function chooseAimTarget()
    if not session then return nil end
    local candidates = readTargetCandidates()
    for _, c in ipairs(candidates) do
        if C.IsComponentOperational(id(c.componentID)) then
            return c.componentID
        end
    end
    return nil
end

-- Direct-control lost the object it was engaging. Setting aimTargetID alone
-- would move only the camera and leave every checked group armed against a
-- wreck, so follow with engageTarget(), which repoints the soft target,
-- targetObjectID and camera together. With Auto-next Target off -- or on with
-- nothing left to shoot -- reset the view and hand the choice back to the
-- player at the target browser.
local function onDirectTargetLost()
    local nextTarget = (session.autoNextTarget ~= false) and chooseAimTarget() or nil
    if nextTarget and engageTarget(nextTarget) then
        if (session.povMode or "manual") == "cinematic" then
            -- A running cutscene cannot be re-aimed; same stop/restart cut the
            -- auto-engage retarget path takes.
            sendCutsceneAimStop()
            sendCutsceneAimStart(session.povAnchor or "turret")
        end
        logSession("engaged target lost; auto-next engaged " .. tostring(nextTarget))
        return
    end
    -- applyPov() only acts while the phase is still "engaged", so reset the view
    -- before openTargetBrowser() moves the phase on.
    session.aimTargetID, session.targetObjectID = nil, nil
    session.povAnchor, session.povMode = "turret", "manual"
    applyPov()
    openTargetBrowser()
    persistSession()
    logSession("engaged target lost; back to target selection")
end

-- Fired by MD (X4GunneryControl.DirectTargetLost) when the engaged target's
-- owner changes to a faction the ship can no longer attack (surrender, capture).
-- Distinct from onDirectTargetLost: the target still exists and the player may
-- choose to keep tracking it -- we only need to give the directed turrets a
-- fresh hostile list that excludes the now-friendly ship so they roll to the
-- next hostile instead of holding fire on one they cannot engage.
-- MD guards the raise: DirectWatch.OwnerChanged fires only when
-- not ship.mayattack.{target}, mirroring capital.xml:1070.
local function onDirectTargetOwnerChanged(_, param)
    -- Silently drop stale events: a listener from a prior engagement may
    -- arrive after session end or after a retarget.
    if not session or not State.isOwned(session) then return end
    if session.phase ~= "engaged" or session.controlMode ~= "direct" then return end
    -- Verify this event is for the session's current engaged target. A stale
    -- listener from a previous engage (before reset_cue cancelled it) could
    -- carry a different target id. sameID normalises both the FFI uint64 form
    -- and the Lua-number form that raise_lua_event delivers.
    if not sameID(param, session.targetObjectID) then return end
    -- Re-issue the directed fallback. DirectFallback's find_ship uses
    -- relation=kill, so the now-owned target is absent from the result. The
    -- new do_else branch in DirectFallback issues a wide call with no preferred
    -- target, letting turrets roll freely to the next hostile.
    log("directed target ownership changed; re-issuing fallback")
    emitDirectFallback(session.shipID, id(session.targetObjectID))
end

-- Called from menu.onUpdate() on the 0.25 s refresh tick while phase=="engaged".
-- Updates session.aimTargetID and restarts the cinematic when the target changes.
local nextAimScan = 0
local function updateAimTarget()
    if not session or session.phase ~= "engaged" then return end
    local prev = session.aimTargetID
    local now = getElapsedTime()
    local hadTarget = not isNullID(prev)
    if hadTarget and not C.IsComponentOperational(id(prev)) and session.controlMode == "direct" then
        return onDirectTargetLost()
    end
    if not isNullID(prev) and C.IsComponentOperational(id(prev)) then
        -- Direct-control keeps the ordered target even when it drifts out of
        -- range. Auto-engage may switch to something better, but each scan is a
        -- whole-sector sweep (readTargetCandidates enumerates every ship and
        -- station), so it runs on a 5 s cadence rather than the 4 Hz refresh.
        if session.controlMode == "direct" then return end
        if now < nextAimScan then return end
    end
    nextAimScan = now + 5
    local resolved = chooseAimTarget()
    if resolved == nil then
        if session.controlMode == "auto" and not isNullID(prev) then
            -- Auto mode remains engaged and continues scanning.  Persist the
            -- explicit no-target state so an old MD component cannot revive.
            session.aimTargetID, session.targetObjectID = nil, nil
            session.povAnchor, session.povMode = "turret", "manual"
            applyPov()
            persistSession()
            log("auto target lost; scanning without a target")
        end
        return
    end
    if sameID(resolved, prev) then return end
    session.aimTargetID = resolved
    session.targetObjectID = targetRoot(resolved)
    if session.controlMode == "auto" then persistSession() end
    if (session.povMode or "manual") == "cinematic" then
        -- A running cutscene cannot be re-aimed, so retargeting is a stop and a
        -- restart; the player sees a brief camera cut.
        sendCutsceneAimStop()
        sendCutsceneAimStart(session.povAnchor or "turret")
    else
        if (session.povAnchor or "turret") == "target" then applyPov() end
        -- Button `active` states are baked in when the frame is built, so the
        -- panel must be rebuilt for the Target POV buttons to stop being greyed
        -- once a target exists. refresh() only re-reads data, it does not paint.
        menu.display()
    end
end

-- Opening the Test Lab closes this menu, and menu.cleanup() treats an unplanned
-- close as an orphaned session: it queues autoHideAt, the watchdog restores the
-- directed group, and the reopen discards the session at chair ingress. That
-- destroys an engaged session the moment the player reaches for a reload button.
-- Reuse the Map suspend/resume route instead — it is the one path already proven
-- to hand a live session across an external menu, and its `resuming` branch in
-- onShowMenu is also what re-enters the turret camera on the way back.
-- The Test Lab's operator Close and Abort paths explicitly reopen this menu;
-- player-context and load teardown suppress that handoff because this session
-- is ending independently. Keep those companion exits paired with this parked
-- ownership contract or resumePending would have no menu to consume it.
local function openTestLab()
    if session then
        -- The reload buttons live behind this menu, and a reload wipes all Lua
        -- state. Park the session now so there is something to come back to,
        -- whatever phase the player reloads from.
        persistSession()
        transitionLifecycle(State.lifecycle.reopening, "Test Lab opened")
        resumePending = true
    end
    testLabCallbacks.open()
end

function TestAPI.updateAimTarget() updateAimTarget() end
function TestAPI.cycleTarget(delta) return cycleTarget(delta) end
function TestAPI.readGroups(ship) return readGroups(ship) end
function TestAPI.readTargetCandidates() return readTargetCandidates() end
function TestAPI.requestEngageability(target) return requestEngageability(target) end
function TestAPI.requestEngageabilities(targets) return requestEngageabilities(targets) end
function TestAPI.engageabilityText(result) return engageabilityText(result) end

function menu.onShowMenu()
    -- Helper tracks every menu; vanilla floating/interact menus explicitly
    -- mark themselves non-fullscreen so they do not behave like a full map
    -- menu. This is a runtime behavior gate and must remain live-tested.
    C.SetTrackedMenuFullscreen(menu.name, false)
    if not isInGunnerChair() then
        endSession("menu opened after leaving chair")
        return
    end
    local ship = playerShip()
    local resuming = resumePending and session and session.lifecycle == State.lifecycle.reopening
    local mapSuspendResume = not resuming and session and sameID(session.shipID, ship)
        and State.isMapSuspended(session)
    resumePending = false
    if not session then
        session = newSession(ship)
        resuming = false
        -- The partner of the not-seated guard in onRestoreEnvelope: if the restore
        -- raised at gameLoadingDone ever arrives with the player off the chair,
        -- this is what collects the payload afterwards. Cheap either way -- MD
        -- only keeps a payload for a session that did not end cleanly, so a
        -- normal ingress receives an empty state response, which is silent by
        -- design because it is the common no-save path.
        if persistence then persistence.request() end
    elseif not sameID(session.shipID, ship) or (not resuming and not mapSuspendResume) then
        -- A fresh chair interaction must never inherit a hidden direct
        -- snapshot. Only the explicit Map callback below may resume a session,
        -- or a map-suspended session for the same ship (DockedMenu beat the
        -- reopen path: the player never left the chair).
        discardSession("stale session at chair ingress")
        resuming = false
        mapSuspendResume = false
        session = newSession(ship)
    else
        transitionLifecycle(State.lifecycle.owned, "Map resume shown")
    end
    -- A displayed menu proves this reopen episode succeeded. Only this genuine
    -- handover (or a fresh session) clears the failure latch; retry attempts do
    -- not, so a broken Map handoff cannot fill the log at watchdog cadence.
    mapReopenFailureLogged = false
    -- The lifecycle transition above is intentionally before camera setup:
    -- delayed camera work must see an owned session. A map-suspend resume
    -- already made that transition, so only a fresh ingress needs this one.
    if not resuming and not mapSuspendResume then
        transitionLifecycle(State.lifecycle.owned, "fresh console shown")
    end
    refresh()
    -- Seed committedBaseline and staged from the ship's live modes at sit-down.
    -- A restored session already carries its baseline from the payload; only a
    -- fresh (or discarded-and-replaced) session needs seeding. Map resumes and
    -- Test Lab reopens carry the existing session through without re-seeding.
    if not resuming and not mapSuspendResume
        and #(session.committedBaseline or {}) == 0 then
        State.seedBaseline(session, session.groups)
    end
    if resuming and session.phase ~= "console" then
        local member = cameraMember()
        if not member or not enterCamera(member) then
            State.returnToConsole(session)
            log("could not restore suspended gunnery camera; returning to console")
        end
    end
    -- Both resume routes (Test Lab reopen and Map suspend) re-enter the engaged
    -- view without re-applying the engine soft target. Only the MD restore path
    -- ever set repointTargetID, so a plain close-and-reopen lost the target
    -- reticule while a Reload UI (which goes through the restore path) kept it.
    -- Hand the aim target to the watchdog here so the same refusal/retry policy
    -- in attemptRepoint applies. Auto mode deliberately never sets a soft target,
    -- so the mode guard is required: dropping it would create a reticule Auto
    -- never otherwise shows.
    if (resuming or mapSuspendResume) and session.phase == "engaged"
        and session.controlMode == "direct" and not isNullID(session.aimTargetID) then
        session.repointTargetID = session.aimTargetID
    end
    menu.display()
end

function menu.display()
    -- Rebuild the current frame without untracking the menu. Helper.clearMenu()
    -- tears down menu.shown and its update/close ownership; vanilla menus use
    -- clearDataForRefresh() when replacing a live frame on the same layer.
    Helper.clearDataForRefresh(menu)
    -- The element panel is rebuilt below only in direct mode. clearDataForRefresh
    -- leaves menu.frames alone, so a leftover panel stays registered as its own
    -- view ("Helper" .. layer) and keeps rendering over the next phase until the
    -- whole menu closes — unregister it explicitly.
    if menu.elementFrame then
        Helper.clearFrame(menu, elementFrameLayer)
        menu.elementFrame = nil
    end
    -- Every call path into display() holds a live session: callers either guard
    -- with `if session then` or return early when it is nil. Stated once here so
    -- nothing below has to repeat the check.
    if not session then return end
    if session.phase == "engaged" then
        -- One compact upper-right panel for both controlModes (step 7).
        -- Frame properties match the old direct panel exactly so the contract
        -- test grep for viewFrame.properties.height still passes.
        local width = Helper.scaleX(460)
        session.viewSofttargetKey = softtargetKey()
        local viewFrame = Helper.createFrameHandle(menu, {
            x = Helper.viewWidth - width - Helper.scaleX(32),
            y = Helper.scaleY(32),
            width = width, standardButtons = { back = true, close = true },
            exclusiveInteractions = false, closeOnUnhandledClick = false,
            playerControls = true, startAnimation = false, blurBackground = false,
            -- useMiniWidgetSystem must stay unset — see earlier comment.
            enableDefaultInteractions = true,
            -- Every frame of this menu must agree on keepHUDVisible. The HUD is
            -- not restored when the value differs between frames that replace
            -- each other on the same layer: the logged browser (true) -> console
            -- (false) -> exit sequence leaves the standing player with no HUD,
            -- while console-only exits restore it.
            keepHUDVisible = true, keepCrosshairVisible = false,
            showTickerPermanently = false,
        })
        menu.frame = viewFrame
        viewFrame:setBackground("solid", { color = Color["frame_background_semitransparent"] })
        local controls = viewFrame:addTable(2, {
            tabOrder = 1, x = Helper.borderSize, y = Helper.borderSize,
            width = width - 2 * Helper.borderSize,
        })
        -- Header row: current turret name + its group name.
        local cm, cmGroup = cameraMember()
        local headerText = (cm and cm.displayName or text(29))
            .. (cmGroup and (": " .. cmGroup.displayName) or "")
        local headerRow = controls:addRow(false, { bgColor = Color["row_title_background"] })
        headerRow[1]:setColSpan(2):createText(headerText, { halign = "center" })
        -- Six buttons in three rows of two (step 7).
        local hasSoftTarget = (C.GetSofttarget2().softtargetID ~= 0)
            or not isNullID(session.aimTargetID)
        local roster = State.cameraRoster(session)
        local canCycle = #roster > 1
        -- Grey out the button for the view currently on screen. Defaults match
        -- applyPov() so a nil field cannot grey the wrong one.
        local function isCurrentPov(anchor, mode)
            return (session.povAnchor or "turret") == anchor
               and (session.povMode or "manual") == mode
        end
        local pRow1 = controls:addRow("pov_manual", {})
        -- Turret POV manual (id 63)
        pRow1[1]:createButton({ active = not isCurrentPov("turret", "manual") }):setText(text(63))
        pRow1[1].handlers.onClick = function()
            session.povAnchor, session.povMode = "turret", "manual"
            applyPov(); persistSession(); menu.display()
        end
        -- Target POV manual (id 64): inactive when no target
        pRow1[2]:createButton({ active = not isCurrentPov("target", "manual") and hasSoftTarget }):setText(text(64))
        pRow1[2].handlers.onClick = function()
            session.povAnchor, session.povMode = "target", "manual"
            applyPov(); persistSession(); menu.display()
        end
        local pRow2 = controls:addRow("pov_cinematic", {})
        -- Turret POV cinematic (id 65)
        pRow2[1]:createButton({ active = not isCurrentPov("turret", "cinematic") }):setText(text(65))
        pRow2[1].handlers.onClick = function()
            session.povAnchor, session.povMode = "turret", "cinematic"
            applyPov(); persistSession(); menu.display()
        end
        -- Target POV cinematic (id 66): inactive when no target
        pRow2[2]:createButton({ active = not isCurrentPov("target", "cinematic") and hasSoftTarget }):setText(text(66))
        pRow2[2].handlers.onClick = function()
            session.povAnchor, session.povMode = "target", "cinematic"
            applyPov(); persistSession(); menu.display()
        end
        local pRow3 = controls:addRow("cycle_turret", {})
        -- Previous Turret (id 72): left side, cycles towards the previous camera entry.
        pRow3[1]:createButton({ active = canCycle }):setText(text(72))
        pRow3[1].handlers.onClick = function()
            State.cycleCamera(session, -1)
            enterCamera(cameraMember()); persistSession(); menu.display()
        end
        -- Next Turret (id 71): right side, cycles towards the next camera entry.
        pRow3[2]:createButton({ active = canCycle }):setText(text(71))
        pRow3[2].handlers.onClick = function()
            State.cycleCamera(session, 1)
            enterCamera(cameraMember()); persistSession(); menu.display()
        end
        -- Direct-only: re-target, cease, and next/prev target buttons.
        if session.controlMode == "direct" then
            local directRow = controls:addRow("direct_actions", {})
            directRow[1]:createButton({}):setText(text(33))
            directRow[1].handlers.onClick = openTargetBrowser
            -- Same words as the console's own button (id 14), because it is now
            -- the same action: this stands the player up. It read "Cease
            -- Engagement" while it dropped back to the console, which it no
            -- longer does.
            directRow[2]:createButton({}):setText(text(14))
            -- Cease Engagement now stands the player up rather than dropping
            -- back to the console. Revert is bound to leaving the chair, so this
            -- is the only seated action that can still restore the turrets --
            -- and it reverts by definition rather than as a special case. A
            -- seated player who wants to stand the guns down unticks and presses
            -- "Update turret behavior" instead.
            directRow[2].handlers.onClick = function()
                leaveChair("compact cease button")
            end
            local canCycleTarget = hasMultipleTargets()
            local pRow4 = controls:addRow("cycle_target", {})
            -- Previous Target (id 76): left side, cycles towards the previous target.
            pRow4[1]:createButton({ active = canCycleTarget }):setText(text(76))
            pRow4[1].handlers.onClick = function() cycleTarget(-1) end
            -- Next Target (id 75): right side, cycles towards the next target.
            pRow4[2]:createButton({ active = canCycleTarget }):setText(text(75))
            pRow4[2].handlers.onClick = function() cycleTarget(1) end
            -- Auto-next Target (id 78): what happens when the engaged target dies.
            local autoNextRow = controls:addRow("auto_next", {})
            autoNextRow[1]:createCheckBox(session.autoNextTarget ~= false,
                { width = Helper.standardTextHeight, height = Helper.standardTextHeight })
            autoNextRow[1].handlers.onClick = function()
                session.autoNextTarget = (session.autoNextTarget == false)
                persistSession()
                menu.display()
            end
            autoNextRow[2]:createText(text(78))
            -- Direct-control turret mode selector (Task 3): same options, label
            -- and help as the console's. The session is engaged, so a change
            -- applies the policy to the checked groups' live modes immediately
            -- instead of only re-staging.
            local directModeRow = controls:addRow("direct_mode", {})
            directModeRow[1]:createText(text(101))
            directModeRow[2]:createDropDown(directModeOptions(),
                { startOption = session.directMode, mouseOverText = text(102) })
            directModeRow[2].handlers.onDropDownConfirmed = function(_, value)
                log("event=direct_mode action=select location=engaged value=" .. tostring(value))
                if not session then return end
                if State.setDirectMode(session, value) then
                    applyDirectModeLive()
                    persistSession()
                end
                menu.display()
            end
        end

        if testLabCallbacks and testLabCallbacks.open then
            local testLabRow = controls:addRow("testlab", {})
            testLabRow[1]:setColSpan(2):createButton({}):setText(text(32))
            testLabRow[1].handlers.onClick = openTestLab
        end
        -- Auto-size frame height like the old direct panel (contract grep).
        viewFrame.properties.height = controls.properties.y + controls:getVisibleHeight() + 2 * Helper.borderSize
        viewFrame:display()
        -- Element panel: top-left, only for direct mode with an engaged object.
        if session.controlMode == "direct" and session.targetObjectID then
            local elemWidth = Helper.scaleX(680)
            local elemFrame = Helper.createFrameHandle(menu, {
                -- Every frame registers its view as "Helper" .. layer, so a
                -- second frame on the default layer 4 would replace the panel
                -- above instead of appearing beside it (vanilla gives each of
                -- Map's frames its own layer: menu_map.lua:1052-1055).
                layer = elementFrameLayer,
                x = Helper.scaleX(32), y = Helper.scaleY(32),
                width = elemWidth,
                exclusiveInteractions = false, closeOnUnhandledClick = false,
                playerControls = true, startAnimation = false, blurBackground = false,
                enableDefaultInteractions = true,
                keepHUDVisible = true, keepCrosshairVisible = false,
                showTickerPermanently = false,
            })
            menu.elementFrame = elemFrame
            elemFrame:setBackground("solid", { color = Color["frame_background_semitransparent"] })
            local elemTable = elemFrame:addTable(5, {
                tabOrder = 2, x = Helper.borderSize, y = Helper.borderSize,
                width = elemWidth - 2 * Helper.borderSize,
            })
            -- Header: target name (falls back to text(51) when empty).
            local tgtName = str(C.GetComponentName(id(session.targetObjectID)))
            local elemHeader = elemTable:addRow(false, { bgColor = Color["row_title_background"] })
            elemHeader[1]:setColSpan(5):createText(tgtName ~= "" and tgtName or text(51), { halign = "center" })
            local elemRefresh = elemTable:addRow("surface_refresh", {})
            elemRefresh[1]:setColSpan(5):createButton({}):setText(text(15))
            elemRefresh[1].handlers.onClick = function()
                log("event=surface_browser action=refresh location=top target=" .. tostring(session.targetObjectID))
                session.surfaceBrowser.pendingReason = "manual"
                refresh(); menu.display()
            end
            local pendingReason = session.surfaceBrowser and session.surfaceBrowser.pendingReason
            if session.surfaceBrowser then session.surfaceBrowser.pendingReason = nil end
            local browser = rebuildSurfaceSnapshot(pendingReason)
            local allSurfaces = browser.allSurfaces
            local autoRefreshRow = elemTable:addRow("surface_auto_refresh", {})
            autoRefreshRow[1]:createCheckBox(browser.autoRefresh == true,
                { width = Helper.standardTextHeight, height = Helper.standardTextHeight })
            autoRefreshRow[1].handlers.onClick = function()
                browser.autoRefresh = not browser.autoRefresh
                browser.nextAutoRefreshAt = browser.autoRefresh and (getElapsedTime() + 10) or nil
                log("event=surface_refresh action=toggle automatic=" .. tostring(browser.autoRefresh)
                    .. " root=" .. tostring(session.targetObjectID))
                menu.display()
            end
            autoRefreshRow[2]:setColSpan(4):createText(text(97))
            local typeOptions = {
                { id = "any", text = text(86), icon = "", displayremoveoption = false },
                { id = "turret", text = text(46), icon = "", displayremoveoption = false },
                { id = "shield", text = text(47), icon = "", displayremoveoption = false },
                { id = "engine", text = text(48), icon = "", displayremoveoption = false },
            }
            local filterType = elemTable:addRow("surface_type_filter", {})
            filterType[1]:createText(text(87))
            filterType[2]:setColSpan(4):createDropDown(typeOptions, { startOption = session.surfaceTypeFilter })
            filterType[2].handlers.onDropDownConfirmed = function(_, value)
                log("event=surface_browser action=filter kind=type value=" .. tostring(value)
                    .. " equipment_reset=any target=" .. tostring(session.targetObjectID))
                session.surfaceTypeFilter, session.surfaceMacroFilter = value, "any"
                browser.page, browser.pendingReason = 1, "filter"
                menu.display()
            end
            local availableMacroOptions = State.surfaceMacroOptions(allSurfaces, session.surfaceTypeFilter)
            local previousMacroFilter = session.surfaceMacroFilter
            local reconciledMacroFilter, filterReset = State.reconcileSurfaceMacroFilter(
                availableMacroOptions, previousMacroFilter)
            session.surfaceMacroFilter = reconciledMacroFilter
            if filterReset then
                log("event=surface_browser action=filter_reset kind=equipment reason=unavailable previous="
                    .. tostring(previousMacroFilter) .. " target=" .. tostring(session.targetObjectID))
                browser.page = 1
                browser = rebuildSurfaceSnapshot("filter")
                allSurfaces = browser.allSurfaces
            end
            local macroOptions = { { id = "any", text = text(86), icon = "", displayremoveoption = false } }
            for _, option in ipairs(availableMacroOptions) do
                option.icon, option.displayremoveoption = "", false
                macroOptions[#macroOptions + 1] = option
            end
            log("event=surface_browser action=rendered target=" .. tostring(session.targetObjectID)
                .. " target_name=" .. string.format("%q", tgtName)
                .. " generation=" .. tostring(browser.generation)
                .. " type_filter=" .. tostring(session.surfaceTypeFilter)
                .. " equipment_filter=" .. tostring(session.surfaceMacroFilter)
                .. " all=" .. tostring(#allSurfaces)
                .. " alternatives=" .. tostring(#browser.orderedIDs)
                .. " equipment_options=" .. tostring(#macroOptions - 1))
            local filterMacro = elemTable:addRow("surface_macro_filter", {})
            filterMacro[1]:createText(text(88))
            filterMacro[2]:setColSpan(4):createDropDown(macroOptions, { startOption = session.surfaceMacroFilter })
            filterMacro[2].handlers.onDropDownConfirmed = function(_, value)
                log("event=surface_browser action=filter kind=equipment value=" .. tostring(value)
                    .. " target=" .. tostring(session.targetObjectID))
                session.surfaceMacroFilter = value
                browser.page, browser.pendingReason = 1, "filter"
                menu.display()
            end
            -- The current hull/surface stays pinned regardless of filters and
            -- refreshes independently from the frozen alternative pages.
            local pinnedID = session.aimTargetID or session.targetObjectID
            local pinnedSurface = surfaceMetadata(browser, pinnedID)
            if not browser.pinnedResult then
                browser.pinnedDistance = surfaceDistance(pinnedID)
                browser.pinnedResult = requestEngageability(pinnedID, "surface_pinned")
            end
            local pinnedName = pinnedSurface and pinnedSurface.name or tgtName
            local pinnedKind = pinnedSurface and pinnedSurface.kind or text(92)
            local pinnedTitle = elemTable:addRow("surface_pinned_title", { bgColor = Color["row_title_background"] })
            pinnedTitle[1]:setColSpan(5):createText(text(91) .. ": " .. (pinnedName ~= "" and pinnedName or text(51)))
            local surfaceHeader = elemTable:addRow("surface_header", { bgColor = Color["row_background_unselectable"] })
            surfaceHeader[1]:setColSpan(2):createText(text(59))
            surfaceHeader[3]:createText(text(50))
            surfaceHeader[4]:createText(text(89))
            local pinnedRow = elemTable:addRow("surface_pinned", {})
            pinnedRow[1]:setColSpan(2):createText(pinnedKind)
            pinnedRow[3]:createText(function() return surfaceDistanceText(browser.pinnedDistance) end)
            pinnedRow[4]:createText(function() return engageabilityText(browser.pinnedResult) end)
            pinnedRow[5]:createText(function() return surfaceShieldText(pinnedID) end)
            local pinnedHullRow = elemTable:addRow("surface_pinned_hull", {})
            pinnedHullRow[5]:createText(function() return surfaceHullText(pinnedID) end)
            if not sameID(pinnedID, session.targetObjectID) then
                local parentHullRow = elemTable:addRow("surface_parent_hull", {})
                parentHullRow[1]:setColSpan(4):createText(text(57))
                parentHullRow[5]:createButton({}):setText(text(58))
                parentHullRow[5].handlers.onClick = function() engageTarget(session.targetObjectID) end
            end

            local ordered = {}
            for _, componentID in ipairs(browser.orderedIDs) do
                ordered[#ordered + 1] = surfaceMetadata(browser, componentID)
            end
            local pageEntries, page, pageCount, firstIndex, lastIndex =
                State.surfacePage(ordered, browser.page, browser.pageSize)
            browser.page = page
            local pageKey = State.surfacePageKey(browser.generation, pageEntries)
            local pageCache = browser.pageResults[pageKey]
            if not pageCache then
                local pageIDs = {}
                for _, surface in ipairs(pageEntries) do pageIDs[#pageIDs + 1] = surface.componentID end
                local pageMembers, signatureParts = checkedOperationalTurrets(), {}
                for _, member in ipairs(pageMembers) do
                    signatureParts[#signatureParts + 1] = State.normID(member.componentID)
                end
                pageCache = {
                    results = requestEngageabilities(pageIDs, "surface_page"), audited = false,
                    distances = {},
                    selectedTotal = #pageMembers, selectedSignature = table.concat(signatureParts, ","),
                }
                for position, surface in ipairs(pageEntries) do
                    pageCache.distances[position] = surfaceDistance(surface.componentID)
                end
                browser.pageResults[pageKey] = pageCache
                log("event=surface_page action=request generation=" .. tostring(browser.generation)
                    .. " page=" .. tostring(page) .. " first=" .. tostring(firstIndex)
                    .. " last=" .. tostring(lastIndex) .. " requested=" .. tostring(#pageIDs)
                    .. " selected_total=" .. tostring(pageCache.selectedTotal)
                    .. " selected_signature=" .. string.format("%q", pageCache.selectedSignature))
            end
            local pageControls = elemTable:addRow("surface_page_controls", {})
            pageControls[1]:createButton({ active = page > 1 }):setText(text(94))
            pageControls[1].handlers.onClick = function()
                browser.page = page - 1
                log("event=surface_page action=navigate direction=previous page=" .. tostring(browser.page))
                menu.display()
            end
            pageControls[2]:setColSpan(3):createText(text(96) .. " " .. tostring(page) .. " / " .. tostring(pageCount), { halign = "center" })
            pageControls[5]:createButton({ active = page < pageCount }):setText(text(95))
            pageControls[5].handlers.onClick = function()
                browser.page = page + 1
                log("event=surface_page action=navigate direction=next page=" .. tostring(browser.page))
                menu.display()
            end
            if #pageEntries > 0 then
                local complete = true
                for position, surface in ipairs(pageEntries) do
                    local result = pageCache.results[position]
                    if not result or result.pending then complete = false end
                    if complete and not pageCache.audited then
                        local engageabilityState, engageabilityEngageable, engageabilityKnown, engageabilityTotal = engageabilityAudit(result)
                        log(string.format("event=surface_browser action=row target=%s component=%s name=%q kind=%s macro=%q size=%s size_source=%s distance=%s snapshot_distance=%s position=%d page=%d pinned=false engageability_state=%s engageability_engageable=%s engageability_known=%s engageability_total=%s engageability_text=%q",
                            tostring(session.targetObjectID), tostring(surface.componentID), surface.name,
                            surface.kindKey, surface.macro, surface.size, surface.sizeSource,
                            tostring(pageCache.distances[position]),
                            tostring(surface.distance), position, page,
                            engageabilityState, tostring(engageabilityEngageable), tostring(engageabilityKnown),
                            tostring(engageabilityTotal), engageabilityText(result)))
                    end
                    local surfRow = elemTable:addRow(tostring(surface.componentID), {})
                    surfRow[1]:setColSpan(2):createText(surface.name)
                    surfRow[3]:createText(surfaceDistanceText(pageCache.distances[position]))
                    surfRow[4]:createText(engageabilityText(result))
                    surfRow[5]:createButton({}):setText(text(60))
                    surfRow[5].handlers.onClick = function() engageTarget(surface.componentID) end
                end
                if complete and not pageCache.audited then
                    pageCache.audited = true
                    log("event=surface_page action=complete generation=" .. tostring(browser.generation)
                        .. " page=" .. tostring(page) .. " requested=" .. tostring(#pageEntries)
                        .. " accepted=" .. tostring(#pageEntries) .. " completed=" .. tostring(#pageEntries)
                        .. " selected_total=" .. tostring(pageCache.selectedTotal)
                        .. " selected_signature=" .. string.format("%q", pageCache.selectedSignature))
                end
            else
                local noSurfRow = elemTable:addRow(false, {})
                noSurfRow[1]:setColSpan(5):createText(text(61))
            end
            elemFrame.properties.height = elemTable.properties.y + elemTable:getVisibleHeight() + 2 * Helper.borderSize
            elemFrame:display()
        end
        return
    end

    local targetBrowser = session.phase == "target_select"
    local frameWidth = Helper.scaleX(targetBrowser and 760 or 1100)
    local frameHeight = Helper.scaleY(targetBrowser and 620 or 700)
    local frame = Helper.createFrameHandle(menu, {
        width = frameWidth, height = frameHeight,
        x = targetBrowser and (Helper.viewWidth - frameWidth - Helper.scaleX(32)) or 0,
        y = targetBrowser and Helper.scaleY(32) or 0,
        standardButtons = { close = true },
        blurBackground = not targetBrowser,
        playerControls = targetBrowser,
        keepHUDVisible = true,
        showTickerPermanently = false,
    })
    menu.frame = frame
    -- A solid semi-transparent frame background keeps every cell's text legible
    -- over the live view (vanilla pattern, e.g. menu_docked.lua:341).
    frame:setBackground("solid", { color = Color["frame_background_semitransparent"] })
    -- Inset the table so column 1 (the checkboxes) is not flush with the screen
    -- edge; the console frame starts at x = 0.
    local tablePad = Helper.scaleX(20)
    local tableWidth = frameWidth - 2 * tablePad

    if session.phase == "target_select" then
        local tableView = frame:addTable(12, { tabOrder = 1, x = tablePad, width = tableWidth })
        local title = tableView:addRow(false, { bgColor = Color["row_title_background"] })
        title[1]:setColSpan(12):createText(text(33), Helper.headerRowCenteredProperties)
        local topActions = tableView:addRow("target_refresh_top", {})
        topActions[1]:setColSpan(12):createButton({}):setText(text(15))
        topActions[1].handlers.onClick = function()
            log("event=target_browser action=refresh location=top")
            refresh(); menu.display()
        end
        local explanation = tableView:addRow(false, {})
        explanation[1]:setColSpan(12):createText(text(34), { wordwrap = true })
        local current = C.GetSofttarget2()
        if current.softtargetID ~= 0 and isEligibleEngagementTarget(current.softtargetID) then
            local row = tableView:addRow("current", { bgColor = Color["row_background_unselectable"] })
            row[1]:setColSpan(9):createText(text(35) .. ": " .. str(C.GetComponentName(current.softtargetID)))
            row[10]:setColSpan(3):createButton({}):setText(text(36))
            row[10].handlers.onClick = function() engageTarget(current.softtargetID) end
        end
        local header = tableView:addRow(false, { bgColor = Color["row_background_unselectable"] })
        header[1]:setColSpan(2):createText(text(37)); header[3]:createText(text(84))
        header[4]:setColSpan(2):createText(text(38)); header[6]:createText(text(49))
        header[7]:createText(text(50)); header[8]:setColSpan(2):createText(text(90)); header[10]:setColSpan(3):createText("")
        local candidates = readTargetCandidates()
        local classValues, typeValues = 0, 0
        local candidateIDs = {}
        for _, candidate in ipairs(candidates) do candidateIDs[#candidateIDs + 1] = candidate.componentID end
        local candidateEngageabilities = requestEngageabilities(candidateIDs)
        for index, candidate in ipairs(candidates) do candidate.engageability = candidateEngageabilities[index] end
        table.sort(candidates, function(a, b)
            local aEngageable = a.engageability and a.engageability.total > 0 and a.engageability.engageable == a.engageability.total or false
            local bEngageable = b.engageability and b.engageability.total > 0 and b.engageability.engageable == b.engageability.total or false
            if aEngageable ~= bEngageable then return aEngageable end
            if a.priority ~= b.priority then return a.priority < b.priority end
            if a.distance ~= b.distance then
                if a.distance < 0 then return false end
                if b.distance < 0 then return true end
                return a.distance < b.distance
            end
            return a.name < b.name
        end)
        for _, candidate in ipairs(candidates) do
            if candidate.class and candidate.class ~= "" then classValues = classValues + 1 end
            if candidate.typeName and candidate.typeName ~= "" then typeValues = typeValues + 1 end
        end
        log("event=target_browser action=rendered candidates=" .. tostring(#candidates)
            .. " class_values=" .. tostring(classValues)
            .. " type_values=" .. tostring(typeValues))
        for position, candidate in ipairs(candidates) do
            local engageabilityState, engageabilityEngageable, engageabilityKnown, engageabilityTotal = engageabilityAudit(candidate.engageability)
            log(string.format("event=target_browser action=row component=%s name=%q class=%q type=%q macro=%q position=%d engageability_state=%s engageability_engageable=%s engageability_known=%s engageability_total=%s engageability_text=%q",
                tostring(candidate.componentID), candidate.name, candidate.class, candidate.typeName,
                candidate.macro, position, engageabilityState, tostring(engageabilityEngageable), tostring(engageabilityKnown),
                tostring(engageabilityTotal), engageabilityText(candidate.engageability)))
            local row = tableView:addRow(tostring(candidate.componentID), {})
            row[1]:setColSpan(2):createText(candidate.name ~= "" and candidate.name or text(51))
            row[3]:createText(candidate.class); row[4]:setColSpan(2):createText(candidate.typeName)
            row[6]:createText(candidate.relation)
            row[7]:createText(candidate.distance >= 0 and string.format("%.1f km", candidate.distance / 1000) or "-")
            row[8]:setColSpan(2):createText(engageabilityText(candidate.engageability))
            row[10]:setColSpan(3):createButton({}):setText(text(52))
            row[10].handlers.onClick = function() engageTarget(candidate.componentID) end
        end
        if #candidates == 0 then
            local row = tableView:addRow(false, {})
            row[1]:setColSpan(12):createText(text(53), { color = Color["text_error"] })
        end
        local actions = tableView:addRow("actions", {})
        actions[1]:setColSpan(3):createButton({}):setText(text(15))
        actions[1].handlers.onClick = function()
            log("event=target_browser action=refresh location=bottom")
            refresh(); menu.display()
        end
        if testLabCallbacks and testLabCallbacks.open then
            actions[4]:setColSpan(2):createButton({}):setText(text(32))
            actions[4].handlers.onClick = openTestLab
        end
        actions[6]:setColSpan(7):createButton({}):setText(text(54))
        -- No revert: the player is still seated, and a temporary apply now lasts
        -- until they stand up. Backing out of the target list is a navigation
        -- step, not a decision to put the turrets back.
        actions[6].handlers.onClick = function()
            returnToConsole("target browser back button")
        end
        frame:display()
        return
    end

    -- Console: 8-column table.
    -- Columns: [1] checkbox [2] group name+status [3] count [4] mode [5] armed
    --          [6..7] spacer [8] (unused — held for column width balance)
    local tableView = frame:addTable(8, { tabOrder = 1, x = tablePad, width = tableWidth })
    local title = tableView:addRow(false, { bgColor = Color["row_title_background"] })
    title[1]:setColSpan(8):createText(text(1), Helper.headerRowCenteredProperties)
    local target = C.GetSofttarget2()
    local targetName = target.softtargetID ~= 0 and str(C.GetComponentName(target.softtargetID)) or text(3)
    local targetRow = tableView:addRow(false, {})
    targetRow[1]:setColSpan(8):createText(text(2) .. ": " .. targetName)
    -- Help line: one sentence explaining the new two-button flow (id 74).
    local helpRow = tableView:addRow(false, {})
    helpRow[1]:setColSpan(8):createText(text(74), { color = Color["text_inactive"] })
    if not ownedByPlayer(session.shipID) then
        local row = tableView:addRow(false, {}); row[1]:setColSpan(8):createText(text(17), { color = Color["text_error"] })
    elseif #session.groups == 0 then
        local row = tableView:addRow(false, {}); row[1]:setColSpan(8):createText(text(18), { color = Color["text_error"] })
    else
        -- Direct-control turret mode selector. Offers exactly the
        -- Direct-control engine modes vanilla ships, with the vanilla-localized
        -- labels, and starts at the session's current policy. Staged/UI-only:
        -- State.setDirectMode re-stages the checked rows; nothing reaches the
        -- turrets before a commit. The engaged panel renders the same selector
        -- and applies it live (see applyDirectModeLive).
        local selectorOptions = directModeOptions()
        local directModeRow = tableView:addRow("direct_mode", {})
        directModeRow[1]:setColSpan(3):createText(text(101), { halign = "right" })
        directModeRow[4]:setColSpan(4):createDropDown(selectorOptions,
            { startOption = session.directMode, mouseOverText = text(102) })
        directModeRow[8]:createText("")
        directModeRow[4].handlers.onDropDownConfirmed = function(_, value)
            log("event=direct_mode action=select value=" .. tostring(value))
            State.setDirectMode(session, value)
            menu.display()
        end
        -- Header: col 1 = (checkbox label), 2-4 = group name, 5 = count, 6 = mode,
        -- 7 = armed, 8 = empty. The name spans three columns because turret group
        -- labels carry both a location and a name and were being truncated at 1/8
        -- of the table width; columns 6-8 were dead filler. The action row below
        -- still uses all 8 columns, so the column count itself must stay 8.
        -- Select-all checkbox, in the same column as the per-group ones.
        local selectAll = tableView:addRow("select_all", {})
        selectAll[1]:createCheckBox(State.allGroupsChecked(session),
            { width = Helper.standardTextHeight, height = Helper.standardTextHeight })
        selectAll[1].handlers.onClick = function() State.toggleAllGroups(session); menu.display() end
        selectAll[2]:setColSpan(7):createText(text(77))
        local header = tableView:addRow(false, { bgColor = Color["row_background_unselectable"] })
        header[1]:createText(""); header[2]:setColSpan(3):createText(text(4)); header[5]:createText(text(8))
        header[6]:createText(text(5)); header[7]:createText(text(6)); header[8]:createText("")
        for _, group in ipairs(session.groups) do
            local active = State.canMutate(group)
            local directed = isDirectedGroup(group)
            local checked = session.checkedGroupKeys[group.key] == true
            -- Staged values: what the console shows and edits. Falls back to the
            -- ship's live state if staged is somehow missing (e.g. legacy load).
            local s = session.staged and session.staged[group.key]
                or { mode = group.mode, armed = group.armed }
            local row = tableView:addRow(group.key, {})
            -- Checkbox: disabled when group cannot be mutated.
            row[1]:createCheckBox(checked, { width = Helper.standardTextHeight, height = Helper.standardTextHeight, active = active })
            -- Pass s.armed so toggleGroup can seed a staged entry from the live
            -- armed state when none exists yet, matching the stageMode contract.
            row[1].handlers.onClick = function() State.toggleGroup(session, group.key, s.armed); menu.display() end
            local label = group.displayName .. (directed and (": " .. text(30)) or "")
            row[2]:setColSpan(3):createText(label, { color = active and Color["text_normal"] or Color["text_error"] })
            row[5]:createText(tostring(group.operationalCount) .. " / " .. tostring(group.totalCount))
            -- Mode and armed edit the staged config, not the ship directly.
            local stagedMode = s.mode
            -- Constrained mode list: every ordinary vanilla mode plus the
            -- session's current Direct-control policy, and never the other
            -- Direct-control mode. The shipped Helper dropdown has no supported
            -- per-option disabled state, so the conflicting mode is omitted
            -- rather than greyed out.
            local rowModes = {}
            for _, entry in ipairs(Helper.getTurretModes(group.componentID, nil, "x4gc_mode_" .. group.key)) do
                if not (State.isDirectedMode(entry.id) and entry.id ~= session.directMode) then
                    rowModes[#rowModes + 1] = entry
                end
            end
            -- The current Direct-control mode must stay selectable even if the
            -- engine-compatibility filter dropped it: a checked row displays
            -- that mode, and the startOption must exist in the list.
            local offersCurrentDirectMode = false
            for _, entry in ipairs(rowModes) do
                if entry.id == session.directMode then offersCurrentDirectMode = true; break end
            end
            if not offersCurrentDirectMode then
                local directOption = vanillaModeOption(session.directMode)
                if directOption then rowModes[#rowModes + 1] = directOption end
            end
            row[6]:createDropDown(rowModes, { startOption = function() return stagedMode end, active = active })
            row[6].handlers.onDropDownConfirmed = function(_, value)
                -- Pass the other field through so a group with no staged entry
                -- yet is created from its live state, never from a constant.
                State.stageMode(session, group.key, value, s.armed); menu.display()
            end
            local stagedArmed = s.armed
            row[7]:createButton({ active = active }):setText(stagedArmed and text(6) or text(7))
            row[7].handlers.onClick = function()
                State.stageArmed(session, group.key, not stagedArmed, s.mode); menu.display()
            end
            row[8]:createText("")
            -- Member rows: name + operational status only; no per-row action buttons.
            for _, member in ipairs(group.members) do
                local memberRow = tableView:addRow(member.componentKey, { bgColor = Color["row_background_unselectable"] })
                memberRow[1]:createText("")
                memberRow[2]:setColSpan(3):createText("  " .. member.displayName)
                memberRow[5]:createText(member.operational and text(8) or text(10))
                memberRow[6]:setColSpan(3):createText("")
            end
        end
        -- "Select at least one turret group." when nothing is checked (id 70).
        local anyChecked = next(session.checkedGroupKeys) ~= nil
        if not anyChecked then
            local hint = tableView:addRow(false, {})
            hint[1]:setColSpan(8):createText(text(70), { color = Color["text_inactive"] })
        end
    end
    -- Gate Auto-engage and Direct-control on at least one checked mutable group.
    local anyMutableChecked = false
    for _, g in ipairs(State.checkedGroups(session)) do
        if State.canMutate(g) then anyMutableChecked = true; break end
    end
    local actions = tableView:addRow("actions", {})
    if testLabCallbacks and testLabCallbacks.open then
        -- 8 cols: [1-2] Auto-engage [3-4] Direct-control [5-6] Refresh [7] TestLab [8] GetUp
        actions[1]:setColSpan(2):createButton({ active = anyMutableChecked }):setText(text(68))
        actions[1].handlers.onClick = function() startAutoEngage(State.checkedGroups(session)) end
        actions[3]:setColSpan(2):createButton({ active = anyMutableChecked }):setText(text(69))
        actions[3].handlers.onClick = function() startTargetSelection(State.checkedGroups(session)) end
        actions[5]:setColSpan(2):createButton({}):setText(text(15))
        actions[5].handlers.onClick = function() refresh(); menu.display() end
        actions[7]:createButton({}):setText(text(32))
        actions[7].handlers.onClick = openTestLab
        actions[8]:createButton({}):setText(text(14)); actions[8].handlers.onClick = function() leaveChair("get up button") end
    else
        -- 8 cols: [1-2] Auto-engage [3-4] Direct-control [5-6] Refresh [7-8] GetUp
        actions[1]:setColSpan(2):createButton({ active = anyMutableChecked }):setText(text(68))
        actions[1].handlers.onClick = function() startAutoEngage(State.checkedGroups(session)) end
        actions[3]:setColSpan(2):createButton({ active = anyMutableChecked }):setText(text(69))
        actions[3].handlers.onClick = function() startTargetSelection(State.checkedGroups(session)) end
        actions[5]:setColSpan(2):createButton({}):setText(text(15))
        actions[5].handlers.onClick = function() refresh(); menu.display() end
        actions[7]:setColSpan(2):createButton({}):setText(text(14)); actions[7].handlers.onClick = function() leaveChair("get up button") end
    end
    -- "Update turret behavior" (id 83): permanent commit. Writes staged to the
    -- ship AND advances committedBaseline. Greyed while staged == committedBaseline;
    -- compares against the baseline, not the ship's live state, so it stays
    -- accurate during a temporary apply. Console-only; engaged panels omit it.
    local updateRow = tableView:addRow("update_turrets", {})
    local canUpdate = State.isStagedDirty(session)
    updateRow[1]:setColSpan(8):createButton({ active = canUpdate }):setText(text(83))
    updateRow[1].handlers.onClick = commitStagedTurretBehavior
    frame:display()
end

function menu.viewCreated()
    -- Helper invokes this only after X4 created the replacement frame. It is
    -- the nearest available confirmation that an Engage transition obtained
    -- visible input ownership.
    if session and State.isOwned(session) then
        session.autoHideAt = nil
    end
    if session and State.isOwned(session) and session.phase == "engaged" and session.controlMode == "direct" and session.engagePending then
        session.engagePending, session.engagePendingSince = nil, nil
        logSession("engagement transition confirmed by frame creation")
    end
end

function menu.onUpdate()
    if not session then return end
    if not isInGunnerChair() or not sameID(playerShip(), session.shipID) then
        endSession("left chair or ship")
        return
    end
    local now = getElapsedTime()
    -- X4 can continue delivering UI updates while simulation time is paused.
    -- Do not let those updates turn a frozen elapsed-time deadline into a
    -- recursive pinned-engageability request/repaint loop.
    if not C.IsGamePaused()
            and session.phase == "engaged" and session.controlMode == "direct"
            and session.targetObjectID and session.surfaceBrowser then
        local browser = session.surfaceBrowser
        if not browser.pinnedRefreshAt or now >= browser.pinnedRefreshAt then
            browser.pinnedRefreshAt = now + 1
            local pinnedID = session.aimTargetID or session.targetObjectID
            browser.pinnedDistance = surfaceDistance(pinnedID)
            browser.pinnedResult = requestEngageability(pinnedID, "surface_pinned")
        end
        if browser.autoRefresh and browser.nextAutoRefreshAt and now >= browser.nextAutoRefreshAt then
            browser.nextAutoRefreshAt = now + 10
            browser.pendingReason = "automatic"
            log("event=surface_refresh action=fire reason=automatic root=" .. tostring(session.targetObjectID)
                .. " page=" .. tostring(browser.page))
            menu.display()
        end
    end
    if now > nextRefresh then
        nextRefresh = now + 0.25; refresh()
        -- Auto-retarget runs on the same tick as the data refresh.
        if session.phase == "engaged" then updateAimTarget() end
        -- The player's first Esc during a cinematic goes to the cutscene, not to
        -- our frame, so the engine ends it behind our back. Notice that and
        -- return to the default view here; otherwise the panel keeps claiming
        -- the cinematic is current and the player needs a second Esc to repaint
        -- it and a third to actually go back.
        if session.phase == "engaged" and (session.povMode or "manual") == "cinematic" then
            if C.IsFullscreenCutsceneActive() then
                session.cinematicSeen = true
            elseif session.cinematicSeen then
                session.cinematicSeen = nil
                session.povAnchor, session.povMode = "turret", "manual"
                applyPov()
                menu.display()
            end
        end
        -- Only while the camera is meant to be ON the turret. Target POV points
        -- it at the target and cinematic hands it to a cutscene, so in either of
        -- those the focus differing from the turret is the intended state, not a
        -- gate failure. Target POV was broken by a type error until now, which is
        -- the only reason this never showed: with it fixed, the check fired every
        -- refresh and put ~1900 lines into one log.
        if session.phase == "engaged" and session.cameraMemberID ~= nil
            and (session.povAnchor or "turret") == "turret"
            and (session.povMode or "manual") == "manual" then
            -- A mismatch is one failure per session, not a 4 Hz telemetry
            -- stream. focus==0 is "no camera attached yet", not a mismatch.
            if C.GetExternalTargetViewComponent() ~= 0
                and not cameraFocusMatches(session.cameraMemberID)
                and not cameraMismatchLogged then
                cameraMismatchLogged = true
                log("camera focus differs from selected turret; runtime camera gate failed")
            end
        end
    end
    if menu.frame then menu.frame:update() end
    if menu.elementFrame then menu.elementFrame:update() end
end

activeExternalMenuName = function()
    for _, candidate in ipairs(Menus or {}) do
        if candidate ~= menu and candidate.name ~= "TopLevelMenu" and candidate.shown and not candidate.minimized then
            return candidate.name
        end
    end
end

function menu.onCloseElement(dueToClose)
    local externalMenu = activeExternalMenuName()
    if session and externalMenu then
        if externalMenu == "MapMenu" then
            -- Map is the one external menu with a verified UI Extensions
            -- cleanup callback. Preserve only this explicit, epoch-guarded
            -- resume route; guessing at all other menu lifecycles caused
            -- orphaned gunnery input frames.
            transitionLifecycle(State.lifecycle.suspendingMap, "MapMenu opened")
            Helper.closeMenu(menu, "close", false, false)
            if session then transitionLifecycle(State.lifecycle.suspendedMap, "MapMenu owns the view") end
        else
            logSession("unsupported external menu replaces Gunnery Control: " .. externalMenu)
            endSession("unsupported external menu " .. externalMenu)
        end
        return
    end
    if session and not State.isOwned(session) then return end
    if session and session.phase == "engaged" then
        -- Target brackets call CloseMenusUponMouseClick() as they change the
        -- soft target. Re-register the transparent/compact frame for that
        -- automatic close; an ordinary Esc follows the mode-specific path.
        if (session.povMode or "manual") == "cinematic" then
            -- Esc leaves the cinematic; the cutscene must be stopped here or it
            -- keeps running (duration 999999) with cinematicmode's HUD-off state
            -- latched, invisible under the panels, until the session ends.
            -- Back to the default view, not just out of cinematic mode: one Esc
            -- should land on Turret POV manual whichever anchor was on screen.
            session.povAnchor, session.povMode = "turret", "manual"
            applyPov()
            menu.display()
            return
        end
        local expectedSession, expectedEpoch = session, sessionEpoch
        local controlMode, previousTarget = session.controlMode, session.viewSofttargetKey
        Helper.addDelayedOneTimeCallbackOnUpdate(function()
            if not currentSession(expectedSession, expectedEpoch) or session.phase ~= "engaged" then return end
            local targetClick = dueToClose == "auto" or softtargetKey() ~= previousTarget
            if targetClick then
                menu.display()
            elseif session.controlMode == "direct" and dueToClose ~= "close" then
                openTargetBrowser()
            elseif session.controlMode == "direct" then
                endSession("Engage compact panel closed")
            else
                returnToConsole("Watch closed")
            end
        end, false, getElapsedTime() + 0.02)
        return
    end
    if session and session.phase == "target_select" then
        -- Same as the Back button: still seated, so nothing is put back yet.
        returnToConsole("target browser closed")
        return
    end
    if session then
        leaveChair("console closed")
    else
        Helper.closeMenu(menu, dueToClose, false, false)
    end
end

local function redirectDockedMenu()
    local observedGroup = controlGroup()
    local ship = playerShip()
    if redirectPending or observedGroup ~= "gunnercontrol" or ship == 0 then return end
    redirectPending = true
    -- Deferring avoids opening two menus in the same DockedMenu render pass.
    Helper.addDelayedOneTimeCallbackOnUpdate(function()
        redirectPending = false
        if isInGunnerChair() then
            local docked = Helper.getMenu("DockedMenu")
            if docked then
                -- Open the replacement before closing DockedMenu and suppress
                -- its automatic vanilla-menu fallback. Calling closeMenu()
                -- directly races TopLevelMenu against this custom menu.
                Helper.closeMenuAndOpenNewMenu(docked, "X4GunneryMenu", { 0, 0 }, true)
            else
                log("could not redirect: DockedMenu is unavailable")
            end
        end
    end, false, getElapsedTime() + 0.05)
end

-- Both UI hooks exist only because kuertee UI Extensions adds registerCallback
-- to the vanilla menu objects. That dependency is declared optional="true" on
-- purpose -- UI Extensions ships under a different extension id on Nexus and on
-- the Workshop, so a hard dependency would disable this mod for whichever half
-- of players installed the other one -- which means we can be loaded without it.
-- A host menu that exists but has no registerCallback is UI Extensions missing,
-- not a startup race, and that deserves a message the player can act on.
local function hookTimeoutMessage(docked)
    if docked and not docked.registerCallback then
        return "kuertee UI Extensions is not loaded (DockedMenu has no registerCallback)."
            .. " The console still opens from the gameplanchange fallback, but it will not"
            .. " reopen after closing the Map. Install UI Extensions."
    end
    return "UI hook registration timed out"
end

local function registerUIHooks()
    hookAttempts = hookAttempts + 1
    if not dockedHookRegistered then
        local docked = Helper.getMenu("DockedMenu")
        if docked and docked.registerCallback then
            docked.registerCallback("display_on_after_main_interactions", redirectDockedMenu, menu.uixID)
            dockedHookRegistered = true
        end
    end
    if not mapHookRegistered then
        local map = Helper.getMenu("MapMenu")
        if map and map.registerCallback then
            -- Kuertee UI Extensions exposes this Map-only lifecycle callback.
            -- It is deliberately not generalized to arbitrary menus.
            map.registerCallback("on_menu_cleanup", function()
                local expectedSession, expectedEpoch = session, sessionEpoch
                if not expectedSession or expectedSession.lifecycle ~= State.lifecycle.suspendedMap then return end
                Helper.addDelayedOneTimeCallbackOnUpdate(function()
                    if sameSession(expectedSession, expectedEpoch) and session.lifecycle == State.lifecycle.suspendedMap then
                        reopenSuspendedSession("MapMenu callback")
                    end
                end, false, getElapsedTime() + 0.02)
            end, menu.uixID)
            mapHookRegistered = true
        end
    end
    if not dockedHookRegistered or not mapHookRegistered then
        if hookAttempts == 1 then log("UI host menus unavailable during init; retrying hook registration") end
        if hookAttempts < 40 then
            Helper.addDelayedOneTimeCallbackOnUpdate(registerUIHooks, false, getElapsedTime() + 0.25)
        else
            log(hookTimeoutMessage(Helper.getMenu("DockedMenu")))
        end
    end
end

reopenSuspendedSession = function(reason)
    if resumePending or not session or session.lifecycle ~= State.lifecycle.suspendedMap or menu.shown or activeExternalMenuName() then return end
    if not isInGunnerChair() or not sameID(playerShip(), session.shipID) then
        endSession("suspended session no longer seated")
        return
    end
    resumePending = true
    local expectedSession, expectedEpoch = session, sessionEpoch
    transitionLifecycle(State.lifecycle.reopening, "Map cleanup: " .. reason, true)
    OpenMenu("X4GunneryMenu", { 0, 0 }, nil)
    Helper.addDelayedOneTimeCallbackOnUpdate(function()
        if sameSession(expectedSession, expectedEpoch) and resumePending and not menu.shown then
            resumePending = false
            transitionLifecycle(State.lifecycle.suspendedMap, "Map reopen did not display; retrying", true)
            if not mapReopenFailureLogged then
                mapReopenFailureLogged = true
                log("Map reopen did not display; retrying")
            end
        end
    end, false, getElapsedTime() + 0.50)
end

-- Re-points the engine soft target at a restored target. A normal success is
-- intentionally silent. A false return is a refusal and must not be retried;
-- an exception gets one retry because reload-time FFI calls can be transient.
local function attemptRepoint()
    local targetID = session.repointTargetID
    session.repointTargetID = nil
    local callOK, setOK = pcall(function() return C.SetSofttarget(targetID, "") end)
    if callOK then
        if not setOK then log("re-point target refused; abandoning") end
        return
    end
    local retryCallOK, retrySetOK = pcall(function() return C.SetSofttarget(targetID, "") end)
    if not retryCallOK then
        log("re-point target raised twice; abandoning")
    elseif not retrySetOK then
        log("re-point retry refused; abandoning")
    end
end

TestAPI.attemptRepoint = attemptRepoint

local function sessionWatchdog()
    if session then
        -- Giving a pilot a fly-there order means opening the Map, and writing
        -- the soft target under the player while they are picking things on it
        -- would fight them for their own selection.
        if session.repointTargetID and session.phase == "engaged"
            and not State.isMapSuspended(session) then
            attemptRepoint()
        end
        if session.lifecycle == State.lifecycle.suspendedMap and not menu.shown and not activeExternalMenuName() then
            reopenSuspendedSession("MapMenu cleanup")
        elseif session.lifecycle == State.lifecycle.owned and not menu.shown
            and session.autoHideAt and GetCurRealTime() - session.autoHideAt > 0.05 then
            -- A Helper auto-hide bypassed onCloseElement. Do not leave an armed
            -- snapshot or a stale table that blocks a later chair redirect.
            discardSession("orphaned menu detected by watchdog")
        elseif session.lifecycle == State.lifecycle.owned and session.controlMode == "direct"
            and session.engagePending
            and session.engagePendingSince and GetCurRealTime() - session.engagePendingSince > 2 then
            -- Auto-engage never sets snapshots, so timeout only applies to direct.
            restoreDirect("Engage frame confirmation timed out")
            State.returnToConsole(session)
            session.engagePending, session.engagePendingSince = nil, nil
            logSession("engagement transition timed out; restored console")
            if menu.shown then menu.display() end
        end
    end
    Helper.addDelayedOneTimeCallbackOnUpdate(sessionWatchdog, false, getElapsedTime() + 0.20)
end

TestAPI.runSessionWatchdog = sessionWatchdog

local function init()
    Menus = Menus or {}; table.insert(Menus, menu)
    if Helper then Helper.registerMenu(menu) end
    registerUIHooks()
    local function endForMovement()
        -- The player is already out of the seat here, so seatLeaving suppresses
        -- discardSession's cockpit-camera restore, which would otherwise lock input.
        seatLeaving = true
        endSession("global movement event")
        seatLeaving = false
    end
    -- Exposed for unit tests only: lets tests drive the playerGetUp/playerUndock
    -- route without a live RegisterEvent delivery.
    TestAPI.endForMovement = endForMovement
    -- Exposed for unit tests only: lets tests drive the startAutoEngage failure
    -- path to verify State.returnToConsole is used (controlMode must be nil after).
    TestAPI.startAutoEngage = startAutoEngage
    -- Exposed for unit tests only: lets tests drive the camera gate that
    -- Direct-control goes through (issue #11).
    TestAPI.startTargetSelection = startTargetSelection
    -- Exposed for unit tests only: the missing-UI-Extensions diagnosis, without
    -- having to drive registerUIHooks through all 40 retries.
    TestAPI.hookTimeoutMessage = hookTimeoutMessage
    RegisterEvent("playerGetUp", endForMovement)
    RegisterEvent("playerUndock", endForMovement)
    -- Ownership-change replacement for vanilla's cease_fire. MD fires this when
    -- the engaged target's owner changes to a faction the ship can no longer
    -- attack (capital.xml:1070 condition). The handler re-issues emitDirectFallback
    -- so directed turrets roll to the next hostile instead of holding fire.
    -- The handler's own guards silently drop events for stale sessions.
    RegisterEvent("X4GunneryControl.DirectTargetLost", onDirectTargetOwnerChanged)
    RegisterEvent("X4GunneryControl.EngageabilityResult", onEngageabilityResult)
    RegisterEvent("X4GunneryControl.EngageabilityBatchComplete", onEngageabilityBatchComplete)
    registerForEvent("gameplanchange", getElement("Scene.UIContract"), function(_, mode)
        -- Vanilla opens DockedMenu from this event when entering any secondary
        -- control post. This is an independent fallback if UIX loads its menu
        -- object after this extension's first registration attempt.
        if isInGunnerChair() and not menu.shown and not activeExternalMenuName()
            and (not session or not State.isMapSuspended(session)) then
            if session then discardSession("stale session before chair redirect") end
            redirectDockedMenu()
        elseif session and session.lifecycle == State.lifecycle.suspendedMap and State.isReturnablePlayerView(mode) then
            Helper.addDelayedOneTimeCallbackOnUpdate(function()
                reopenSuspendedSession("returned to " .. tostring(mode))
            end, false, getElapsedTime() + 0.05)
        end
    end)
    -- The adapter releases only a matching target/session pair. Build a
    -- candidate first: a refused, malformed or not-seated payload must leave
    -- every part of the live session (including delayed callbacks) untouched.
    local function onRestoreEnvelope(envelope)
        local records = State.decode(envelope and envelope.payload)
        if #records == 0 then
            return
        end
        -- Groups are addressed by contextID+path+group, and only a live ship can
        -- supply a current contextID, so seated is the one state in which any of
        -- this resolves. A guard, not a path: a save taken while engaged records
        -- the player seated, so the load puts them back in the chair and this
        -- has never been observed to fire across the 2026-08-08 runs. Nothing is
        -- lost if it ever does -- MD still holds the payload and chair ingress
        -- asks again -- but do not treat the deferral as a tested route.
        if not isInGunnerChair() then
            log("restore deferred; player is not in a gunner chair")
            return
        end
        local candidate = newSession(playerShip())
        candidate.groups = readGroups(candidate.shipID)
        local ok = State.restoreState(candidate, records, candidate.groups)
        if not ok then
            log("restore refused; payload is not for this ship")
            return
        end
        -- A load leaves restoreState with no target: the id it saved now belongs
        -- to some other object. MD held the same target as a component and the
        -- engine remapped it, so this is the one route that survives a load.
        -- Everything above arrives as text or as a plain number: the payload is
        -- a string and MD hands the target back as a Lua number. The FFI calls
        -- take neither and raise "bad argument #1" -- which is what made Target
        -- POV do nothing after a load. Converted here, at the one place a
        -- session is built from foreign data, rather than at each of the eight
        -- consumers that would each have to remember.
        if not State.isNullID(envelope.target) then candidate.aimTargetID = envelope.target end
        candidate.aimTargetID = candidate.aimTargetID and id(candidate.aimTargetID) or nil
        candidate.cameraMemberID = candidate.cameraMemberID and id(candidate.cameraMemberID) or nil
        -- Validation is complete. From here this is the existing successful
        -- restore continuation, now operating on the accepted live candidate.
        sessionEpoch = sessionEpoch + 1
        session = candidate
        log("restore accepted; phase=" .. tostring(session.phase))
        if session.phase ~= "engaged" then
            -- Target selection can be entered from Direct-control. Its
            -- snapshots remain live while the browser is open, so a restore
            -- that deliberately returns to the console must release them and
            -- clear MD first; otherwise the old directed-mode override is
            -- stranded with no session left able to restore it.
            if session.controlMode == "direct" then
                restoreDirect("restored target selection")
            end
            returnToConsole("restored non-engaged session")
            return
        end
        local target = id(session.aimTargetID)
        -- Derived rather than carried: targetObjectID is only ever the root of
        -- aimTargetID, so persisting it separately would be a second id to keep
        -- in step with the first for nothing.
        session.targetObjectID = target ~= 0 and targetRoot(target) or nil
        -- firstOperationalMember hands back a (key, componentID) pair for
        -- selection bookkeeping, not a member table, so enterCamera saw no
        -- cameraSupported flag and this fallback failed every time it was
        -- reached -- which is precisely the load case.
        local member = cameraMember()
        if not member or member.operational == false or not member.cameraSupported then
            member = State.firstCameraMember(State.checkedGroups(session))
        end
        if member then session.cameraMemberID = member.componentID end
        if not member or not enterCamera(member) then
            log("restore has no camera member; returning to console")
            -- Direct restores own snapshots; Auto has none, so this makes no
            -- turret writes there while clearing MD state in both modes.
            restoreDirect("restore has no camera member")
            returnToConsole("restore has no camera member")
            return
        end
        if target ~= 0 then
            -- Handed to the watchdog rather than to a delayed callback of its
            -- own. Two builds scheduled one from inside this event handler and
            -- neither ever fired -- "re-point scheduled" with no attempt after
            -- it. Why is still unknown: a probe on 2026-08-08 armed a canary
            -- here exactly the way those builds armed the re-point, and it fired
            -- both across a UI reload and across a savegame load, so the
            -- scheduling mechanism itself is sound and the clock does not rewind
            -- at load. Whatever killed those builds was something else. The
            -- watchdog is used because it is measured to run, not because the
            -- alternative is understood.
            session.repointTargetID = target
        end
        if menu.shown then
            -- The chair-ingress request route: the menu is already up and owns
            -- this session, so there is no handover to arrange. Setting
            -- resumePending here would leave it set with nothing to consume it.
            transitionLifecycle(State.lifecycle.owned, "restored into the open menu")
            menu.display()
        else
            -- The load/reload route: the DockedMenu redirect opens the menu a
            -- tick later, and onShowMenu discards any session it did not create
            -- itself ("stale session at chair ingress"). Hand it over through
            -- the same resume route the Map and Test Lab paths use, or the
            -- restore is undone milliseconds after it succeeds.
            transitionLifecycle(State.lifecycle.reopening, "restored session awaiting its menu")
            resumePending = true
        end
    end
    persistence = Persistence.new({
        State = State,
        emit = function(control, payload) AddUITriggeredEvent("X4GunneryControl", control, payload) end,
        register = RegisterEvent,
        toLuaID = ConvertStringToLuaID,
        log = log,
        onEnvelope = onRestoreEnvelope,
    })
    TestAPI.onRestoreEnvelope = onRestoreEnvelope
    TestAPI.persistence = function() return persistence end
    persistence.request()
    registerForEvent("gameLoadingDone", getElement("Scene.UIContract"), function()
        registerUIHooks()
        persistence.request(true)
    end)
    sessionWatchdog()
    log("UI initialized; build=" .. runtimeBuild)
end
init()
