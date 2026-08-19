local State = dofile("ui/gunnery_state.lua")
local function eq(a, b, label) assert(a == b, (label or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- Session persistence: encode/decode/saveState/restoreState.
--
-- The hostile group id below is deliberate. Vanilla pads group attributes with
-- whitespace, and the payload's own structural characters (; , = %) must not be
-- able to escape their field, or one odd group id silently corrupts the whole
-- restore.
do
    local nasty = "  group_front_up_left ;weird,=key%stuff "

    -- Round trip through the string transport, hostile id included.
    local encoded = State.encode({
        { t = "session", phase = "engaged" },
        { t = "checked", path = "../", group = nasty },
    })
    assert(not encoded:find("[;,=]%s*weird"), "raw delimiters must not survive escaping")
    local decoded = State.decode(encoded)
    eq(#decoded, 2, "round trip must return both records")
    eq(decoded[1].phase, "engaged", "session field must survive the round trip")
    eq(decoded[2].group, nasty, "a group id containing ; , = and % must survive byte-exact")
    eq(#State.decode(""), 0, "an empty payload decodes to no records")
    eq(#State.decode(nil), 0, "a nil payload decodes to no records")

    -- restoreState must match on path+group and take contextID from the live
    -- group list, because a load reassigns every contextID.
    local session = State.newSession("443760", "gunnercontrol")
    session.groups = {
        { key = "group:NEW:../:" .. nasty, contextID = "NEW", path = "../", group = nasty,
          kind = "group", componentID = "C1", mode = "attackenemies", armed = true,
          operationalCount = 1, totalCount = 1 },
        { key = "group:NEW:../:other", contextID = "NEW", path = "../", group = "other",
          kind = "group", componentID = "C2", mode = "attack", armed = false,
          operationalCount = 1, totalCount = 1 },
    }
    session.checkedGroupKeys[session.groups[1].key] = true
    -- committedBaseline replaces directSnapshots as the persistent revert target
    session.committedBaseline = {
        { kind = "group", shipID = "443760", contextID = "OLD", path = "../",
          group = nasty, mode = "attackenemies", armed = true },
    }
    session.phase, session.controlMode = "engaged", "direct"
    session.aimTargetID = "999"

    local reloaded = State.newSession("443760", "gunnercontrol")
    local ok = State.restoreState(reloaded, State.decode(State.encode(State.saveState(session))),
        session.groups)
    assert(ok, "restoreState must report that a session record was found")
    eq(reloaded.phase, "engaged", "phase must be restored")
    eq(reloaded.controlMode, "direct", "controlMode must be restored")
    eq(reloaded.aimTargetID, "999", "the target must be restored, since the engine drops it")
    eq(reloaded.checkedGroupKeys["group:NEW:../:" .. nasty], true,
        "a checked group must be re-keyed onto the live contextID")
    eq(#reloaded.committedBaseline, 1, "the committedBaseline must be restored")
    eq(reloaded.committedBaseline[1].contextID, "NEW",
        "the baseline entry must take the LIVE contextID, never the saved one")
    eq(reloaded.committedBaseline[1].mode, "attackenemies", "baseline mode must survive")
    eq(reloaded.committedBaseline[1].armed, true, "baseline armed must survive as a boolean")

    -- A group that no longer exists must be dropped, not written back.
    local orphaned = State.newSession("443760", "gunnercontrol")
    State.restoreState(orphaned, State.decode(State.encode(State.saveState(session))), {})
    eq(#orphaned.committedBaseline, 0, "a baseline entry with no live group must be dropped")
    eq(next(orphaned.checkedGroupKeys), nil, "a checked group with no live group must be dropped")

    -- Regression: a restored session must preserve the independently saved
    -- checkbox state. Reached by committing a ticked group (which writes
    -- TICK_MODE into committedBaseline) and then unticking it (which leaves
    -- the baseline alone) before saving: the payload then carries a baseline
    -- of attackenemies and an EMPTY checked set. Restore must keep it unchecked
    -- and display the unticked fallback, while retaining the baseline so
    -- standing up can still revert the committed mode.
    local committed = State.newSession("443760", "gunnercontrol")
    committed.groups = session.groups
    committed.committedBaseline = {
        { kind = "group", shipID = "443760", contextID = "OLD", path = "../",
          group = nasty, mode = State.TICK_MODE, armed = true },
    }
    assert(next(committed.checkedGroupKeys) == nil, "fixture must save with nothing checked")
    local rebound = State.newSession("443760", "gunnercontrol")
    State.restoreState(rebound, State.decode(State.encode(State.saveState(committed))), session.groups)
    eq(rebound.checkedGroupKeys["group:NEW:../:" .. nasty], nil,
        "an explicitly unticked group must remain unchecked after restore")
    eq(rebound.staged["group:NEW:../:" .. nasty].mode, State.UNTICK_FALLBACK,
        "an unticked TICK_MODE baseline must restore its Defend fallback")
    eq(rebound.committedBaseline[1].mode, State.TICK_MODE,
        "the committed TICK_MODE baseline must remain available for revert")

    -- Regression: a normal direct engagement saves the original baseline and
    -- the checked group separately. Restore must rebuild the checked group's
    -- current staged mode as TICK_MODE rather than showing the baseline mode
    -- in the dropdown while the checkbox says it is directed.
    local directSaved = State.newSession("443760", "gunnercontrol")
    directSaved.groups = session.groups
    local directKey = session.groups[1].key
    directSaved.checkedGroupKeys[directKey] = true
    directSaved.committedBaseline = {
        { kind = "group", shipID = "443760", contextID = "OLD", path = "../",
          group = nasty, mode = "defend", armed = true },
    }
    local directBack = State.newSession("443760", "gunnercontrol")
    State.restoreState(directBack, State.decode(State.encode(State.saveState(directSaved))), session.groups)
    local directRestoredKey = "group:NEW:../:" .. nasty
    eq(directBack.checkedGroupKeys[directRestoredKey], true,
        "a checked direct group must remain checked after restore")
    eq(directBack.staged[directRestoredKey].mode, State.TICK_MODE,
        "a checked direct group must restore its temporary attackenemies mode")

    -- The legacy single-snapshot fallback in snapshotsForSave still works.
    local legacy = State.newSession("443760", "gunnercontrol")
    legacy.phase, legacy.controlMode = "engaged", "direct"
    legacy.committedBaseline = { kind = "single", shipID = "443760",
        componentID = "555", mode = "defend", armed = false }
    local legacyBack = State.newSession("443760", "gunnercontrol")
    State.restoreState(legacyBack, State.decode(State.encode(State.saveState(legacy))), {})
    eq(#legacyBack.committedBaseline, 1, "a legacy single baseline must still round trip")
    eq(legacyBack.committedBaseline[1].componentID, "555", "the legacy componentID must survive")
    eq(legacyBack.committedBaseline[1].armed, false, "legacy armed=false must survive")
end

-- The save/load half: a load reassigns every id, so the same payload has to be
-- read differently from a UI reload. Group names still match; nothing addressed
-- by a bare componentID does.
do
    local saved = State.newSession("441090", "gunnercontrol")
    saved.shipName = "Behemoth"
    saved.phase, saved.controlMode = "engaged", "direct"
    saved.aimTargetID, saved.cameraMemberID = "700", "701"
    saved.groups = { { key = "group:OLD:../:aft", contextID = "OLD", path = "../", group = "aft" } }
    saved.checkedGroupKeys[saved.groups[1].key] = true
    saved.committedBaseline = {
        { kind = "group", shipID = "441090", contextID = "OLD", path = "../",
          group = "aft", mode = "attackenemies", armed = true },
        { kind = "single", shipID = "441090", componentID = "800",
          mode = "defend", armed = true },
    }
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:2080707:../:aft", contextID = "2080707",
        path = "../", group = "aft" } }

    -- Same ship, new ids: the group baseline entry survives, the componentID-addressed
    -- values do not, because those ids now belong to arbitrary components.
    local loaded = State.newSession("2080707", "gunnercontrol")
    loaded.shipName = "Behemoth"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "a payload for this ship must restore after a load")
    eq(loaded.phase, "engaged", "phase must survive a load")
    eq(loaded.aimTargetID, nil, "a reassigned target id must be dropped, not re-pointed")
    eq(loaded.cameraMemberID, nil, "a reassigned camera member id must be dropped")
    eq(#loaded.committedBaseline, 1, "only the name-addressed baseline entry survives a load")
    eq(loaded.committedBaseline[1].contextID, "2080707", "the baseline entry takes the live contextID")
    -- restoreDirect uses committedBaseline shipID to match session ship; must be live.
    eq(loaded.committedBaseline[1].shipID, "2080707", "the baseline entry takes the live shipID")

    -- A different ship with the same group names must not be touched: this is
    -- the whole reason the name is in the payload.
    local other = State.newSession("2080707", "gunnercontrol")
    other.shipName = "Odysseus"
    eq(State.restoreState(other, State.decode(payload), liveGroups), false,
        "a payload from another ship must be refused")
    eq(#other.committedBaseline, 0, "a refused payload must write no baseline entries")
    eq(next(other.checkedGroupKeys), nil, "a refused payload must check no groups")
end

-- The POV turret. cameraMemberID is a componentID, so a load reassigns it; the
-- turret's group name and its position in that group do not change.
do
    local function shipWithTurrets(shipID, contextID, turretIDs)
        local session = State.newSession(shipID, "gunnercontrol")
        session.shipName = "Behemoth"
        local members = {}
        for _, componentID in ipairs(turretIDs) do
            members[#members + 1] = { componentID = componentID, operational = true,
                cameraSupported = true }
        end
        session.groups = { { key = "group:" .. contextID .. ":../:aft", contextID = contextID,
            path = "../", group = "aft", members = members } }
        session.checkedGroupKeys[session.groups[1].key] = true
        session.phase, session.controlMode = "engaged", "direct"
        return session
    end

    local saved = shipWithTurrets("441090", "OLD", { "801", "802", "803" })
    saved.cameraMemberID = "802"  -- the middle turret, not the first
    local payload = State.encode(State.saveState(saved))

    -- A reload keeps the ids; the same barrel must come back either way.
    local reloaded = shipWithTurrets("441090", "OLD", { "801", "802", "803" })
    State.restoreState(reloaded, State.decode(payload), saved.groups)
    eq(reloaded.cameraMemberID, "802", "a reload must return to the same turret")

    -- A load reassigns every turret id. Position within the group is what
    -- carries over, so the POV must land on the second turret again and not on
    -- whichever one happens to be listed first.
    local loaded = shipWithTurrets("2080707", "NEW", { "901", "902", "903" })
    State.restoreState(loaded, State.decode(payload), loaded.groups)
    eq(loaded.cameraMemberID, "902", "a load must return to the same turret position")

    -- firstCameraMember must hand back the member table, not the (key, id) pair
    -- firstOperationalMember returns: enterCamera reads cameraSupported off it.
    local member = State.firstCameraMember(loaded.groups)
    eq(type(member), "table", "firstCameraMember must return a member table")
    eq(member.componentID, "901", "firstCameraMember must return the first usable turret")
    eq(State.firstCameraMember({ { members = {
        { componentID = "1", operational = true, cameraSupported = false },
        { componentID = "2", operational = false, cameraSupported = true },
    } } }), nil, "a turret that cannot host the camera is not a candidate")
end

-- Reviewer branch matrix: these deliberately small cases document the edges
-- that are easy to lose in a persistence refactor.  The contract is named
-- cases plus executable-line coverage, rather than a misleading branch %.
do
    -- nil session/records and a payload without a session record are refusals.
    assert(not State.restoreState(nil, {}, {}), "matrix: nil session is refused")
    assert(not State.restoreState(State.newSession(1, "g"), nil, {}), "matrix: nil records are refused")
    assert(not State.restoreState(State.newSession(1, "g"), { { t = "checked" } }, {}),
        "matrix: no session record is refused")

    -- A complete session record is the persistence schema. Older released
    -- payloads can omit the whole stable-camera-location triplet, but no
    -- released writer omitted the phase, control, POV, flag, or ID fields.
    local function sessionRecord(values)
        local record = {
            t = "session", phase = "console", controlMode = "",
            povAnchor = "turret", povMode = "manual",
            autoNextTarget = "1",
            shipID = "old", shipName = "", aimTargetID = "", cameraMemberID = "",
            camPath = "", camGroup = "", camIndex = "",
        }
        for key, value in pairs(values or {}) do record[key] = value end
        return record
    end

    -- Every empty/nonempty saved/live ship-name pairing except two differing
    -- nonempty names is permitted. IDs still decide reload versus save/load.
    local function restoreWithNames(savedName, liveName)
        local candidate = State.newSession("new", "g")
        candidate.shipName = liveName
        return State.restoreState(candidate, {
            sessionRecord({ shipName = savedName }),
        }, {})
    end
    assert(restoreWithNames("", ""), "matrix: empty/empty ship names permit restore")
    assert(restoreWithNames("saved", ""), "matrix: saved-only ship name permits restore")
    assert(restoreWithNames("", "live"), "matrix: live-only ship name permits restore")
    assert(restoreWithNames("same", "same"), "matrix: matching ship names permit restore")
    assert(not restoreWithNames("saved", "other"), "matrix: differing ship names refuse restore")

    -- The first two emitted persistence formats had no shipName or stable
    -- camera location (and carried a now-unused targetObjectID). These are
    -- known complete legacy records, so their explicitly absent fields remain
    -- compatible without accepting a partially-present modern triplet.
    local legacyRecord = sessionRecord({ targetObjectID = "legacy-root" })
    legacyRecord.shipName = nil
    legacyRecord.camPath, legacyRecord.camGroup, legacyRecord.camIndex = nil, nil, nil
    assert(State.restoreState(State.newSession("new", "g"), { legacyRecord }, {}),
        "matrix: complete first-format session remains restorable")

    -- A positive camera index is valid persisted state even when that member
    -- has since disappeared. Restore accepts it without inventing a member so
    -- the runtime can use its safe no-camera fallback and clear MD state.
    local staleCamera = State.newSession("same", "g")
    staleCamera.shipName = "ship"
    local nonCameraGroups = { { key = "g", path = "p", group = "g", members = {
        { componentID = "dead", operational = false, cameraSupported = true },
        { componentID = "unsupported", operational = true, cameraSupported = false },
    } } }
    assert(State.restoreState(staleCamera, {
        sessionRecord({ shipID = "same", shipName = "ship", camPath = "p", camGroup = "g", camIndex = "9" }),
    }, nonCameraGroups), "matrix: missing saved camera member still restores the session")
    assert(staleCamera.cameraMemberID == nil, "matrix: missing saved camera member is not invented")
    assert(State.firstCameraMember(nonCameraGroups) == nil,
        "matrix: non-operational or unsupported restored members cannot host a camera")

    -- Malformed escapes and records never raise or manufacture saved state.
    local malformedEscapes = State.decode("t=session,shipName=bad%ZZ;not-a-field")
    assert(#malformedEscapes == 2, "matrix: malformed escape/record is tolerated")
    assert(not State.restoreState(State.newSession(1, "g"), State.decode("not-a-field"), {}),
        "matrix: malformed record cannot become a session")

    -- Parseable truncation and out-of-domain values are refusals, before a
    -- candidate is changed. This is the pure counterpart of the runtime
    -- Direct-baseline regression below.
    local unchanged = State.newSession("same", "g")
    local originalBaseline = { { shipID = "same", kind = "group", contextID = "c",
        path = "p", group = "g", mode = "defend", armed = true } }
    unchanged.phase, unchanged.controlMode = "engaged", "direct"
    unchanged.checkedGroupKeys = { live = true }
    unchanged.committedBaseline = originalBaseline
    local function assertRefused(records, label)
        assert(not State.restoreState(unchanged, records, {}), label)
        eq(unchanged.phase, "engaged", label .. ": phase is unchanged")
        eq(unchanged.controlMode, "direct", label .. ": control mode is unchanged")
        assert(unchanged.checkedGroupKeys.live, label .. ": checks are unchanged")
        assert(unchanged.committedBaseline == originalBaseline, label .. ": baseline is unchanged")
    end
    assertRefused({ { t = "session" } }, "matrix: truncated session is refused")
    for _, bad in ipairs({
        { phase = "broken" }, { controlMode = "auto" }, { povAnchor = "bridge" },
        { povMode = "orbit" }, { autoNextTarget = "true" },
        { camPath = "p", camGroup = "g", camIndex = "1.5" },
        { camPath = "p", camGroup = "", camIndex = "1" },
    }) do
        assertRefused({ sessionRecord(bad) }, "matrix: invalid session enum/form is refused")
    end
    assertRefused({ sessionRecord({ shipID = "same", phase = "engaged", controlMode = "direct" }), {
        t = "snapshot", kind = "group", shipID = "same", contextID = "c", path = "p", group = "g", mode = "attack",
    } }, "matrix: malformed snapshot is refused")
    assertRefused({ sessionRecord(), {
        t = "snapshot", kind = "group", shipID = "old", contextID = "c", path = "p", group = "g", mode = "attack", armed = "1",
    } }, "matrix: console snapshot is refused")
    assertRefused({ sessionRecord(), { t = "unknown" } }, "matrix: unknown record type is refused")

    -- A Direct session intentionally keeps its baseline while target
    -- selection is open. Legacy "snapshot" records still restore as committedBaseline
    -- to support payloads written before the rename.
    local targetSelect = State.newSession("same", "g")
    assert(State.restoreState(targetSelect, {
        sessionRecord({ shipID = "same", phase = "target_select", controlMode = "direct" }),
        { t = "snapshot", kind = "group", shipID = "same", contextID = "c", path = "p", group = "g", mode = "attack", armed = "1" },
    }, { { key = "live", contextID = "live", path = "p", group = "g" } }),
        "matrix: target-select Direct (legacy snapshot) restores")
    eq(#targetSelect.committedBaseline, 1, "matrix: legacy snapshot promoted to committedBaseline")

    -- A changed-ID load drops a component-addressed single baseline entry, while
    -- duplicate records do not make restore fail or add phantom entries.
    local changedIDs = State.newSession("new", "g")
    local changedHead = sessionRecord({ phase = "engaged", controlMode = "direct" })
    assert(not State.restoreState(changedIDs, {
        changedHead,
        { t = "baseline", kind = "single", componentID = "old-turret", mode = "defend", armed = "1" },
    }, {}), "matrix: malformed changed-ID baseline is refused")
    assert(State.restoreState(changedIDs, {
        changedHead,
        { t = "baseline", kind = "single", shipID = "old", componentID = "old-turret", mode = "defend", armed = "1" },
    }, {}), "matrix: changed-ID session restores")
    eq(#changedIDs.committedBaseline, 0, "matrix: changed-ID single baseline entry is dropped")
    local duplicates = State.newSession("same", "g")
    local duplicate = sessionRecord({ shipID = "same" })
    assert(State.restoreState(duplicates, {
        duplicate, sessionRecord({ shipID = "same" }),
    }, {}), "matrix: duplicate session records are tolerated")
    eq(#duplicates.committedBaseline, 0, "matrix: duplicate/malformed records do not manufacture baseline state")

    -- Force the no-match/closing-loop paths that normal happy-path selections
    -- skip, while preserving their public return values.
    eq(State.turretGroupLabel("group_left"), "Left", "matrix: directional slot assignment")
    assert(State.firstOperationalMember({ { members = { { componentID = 1, operational = false } } } }) == nil,
        "matrix: no operational member")
    assert(State.firstCameraMember({ { members = { { componentID = 1, operational = true, cameraSupported = false } } } }) == nil,
        "matrix: no supported camera member")
    assert(State.findMemberLocation({ groups = { { members = { { componentID = 1 } } } } }, 2) == nil,
        "matrix: missing member location")
    local retained = State.newSession(1, "g")
    retained.selectedGroupKey, retained.selectedMemberID = "g", 2
    State.retainSelection(retained, { { key = "g", members = { { componentID = 1, operational = false } } } })
    assert(retained.selectedMemberID == nil, "matrix: unsupported retained selection falls back to none")
    local checkedMatrix = State.newSession(1, "g")
    checkedMatrix.groups = {
        { key = "checked", operationalCount = 1, members = { { componentID = 1, operational = true } } },
        { key = "unchecked", operationalCount = 1, members = { { componentID = 2, operational = false } } },
        { key = "destroyed", operationalCount = 0, members = { { componentID = 3, operational = false } } },
    }
    State.toggleGroup(checkedMatrix, "checked")
    assert(not State.allGroupsChecked(checkedMatrix), "matrix: unchecked mutable group prevents all-checked")
    eq(#State.checkedGroups(checkedMatrix), 1, "matrix: checked group list excludes unchecked groups")
    eq(#State.cameraRoster(checkedMatrix), 1, "matrix: camera roster filters non-operational and unchecked members")
    eq(State.statusLabel(nil), "destroyed", "matrix: nil group status")
    eq(State.statusLabel({ operationalCount = 1, totalCount = 2 }), "damaged", "matrix: damaged status")
    eq(State.statusLabel({ operationalCount = 2, totalCount = 2 }), "operational", "matrix: operational status")
end

print("gunnery_state serialization tests passed")
