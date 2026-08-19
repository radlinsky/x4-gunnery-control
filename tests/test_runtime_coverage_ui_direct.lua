-- test_runtime_coverage_ui_direct.lua
-- Issue #48 Task 3: Direct-control policy selector on the engaged panel,
-- and the auto-engage panel which must not carry that selector.

-- Issue #48 Task 3: the Direct-control engaged panel carries the same
-- selector as the console, and changing it while engaged applies the policy
-- to the checked groups' live modes immediately, without touching target,
-- camera, Auto-next, checkbox membership or the committed baseline.
do
    local fixE = dofile("tests/support/runtime_fixture.lua").load()
    local key = X4GunneryState.groupKey(5, "p", "g")
    local grp = fixE.makeGroup()
    fixE.gcMenu.onShowMenu()
    local sess = fixE.API.getSession()
    sess.groups = { grp }
    sess.cameraMemberID = 27
    X4GunneryState.seedBaseline(sess, { grp })
    X4GunneryState.toggleGroup(sess, key, grp.armed)
    sess.phase, sess.controlMode = "engaged", "direct"
    sess.aimTargetID = 77
    sess.autoNextTarget = true

    -- This fixture's module instance binds its own C table (the fixture clears
    -- the require cache on every load), so overrides on fixE.C are visible to
    -- the production code exactly as the fixture contract documents.
    local liveModes, liveArmed = {}, {}
    local savedSetMode, savedSetArmed = rawget(fixE.C, "SetTurretGroupMode2"), rawget(fixE.C, "SetTurretGroupArmed")
    fixE.C.SetTurretGroupMode2 = function(_, _, _, _, mode) liveModes[#liveModes + 1] = mode end
    fixE.C.SetTurretGroupArmed = function(_, _, _, _, armed) liveArmed[#liveArmed + 1] = armed end
    local function eventsSince(mark)
        local fallback, watch = false, false
        for i = mark + 1, #fixE.uiTriggeredEvents do
            local control = fixE.uiTriggeredEvents[i].control
            if control == "direct_fallback" then fallback = true end
            if control == "direct_watch" then watch = true end
        end
        return fallback, watch
    end
    local function latestRow(fixture, rowID)
        local found
        for _, dd in ipairs(fixture.getCreatedDropDowns()) do
            if dd.row == rowID then found = dd end
        end
        return found
    end

    fixE.gcMenu.display()

    -- The selector renders with the same options, label and help as the
    -- console's, and starts at the session policy.
    local sel = latestRow(fixE, "direct_mode")
    assert(sel, "engaged panel must render the direct_mode selector dropdown")
    local selIDs = {}
    for _, option in ipairs(sel.options) do selIDs[#selIDs + 1] = option.id end
    assert(#selIDs == 2 and selIDs[1] == "attackenemies" and selIDs[2] == "autoassist",
        "engaged selector must offer exactly the two Direct-control modes in vanilla order")
    local vanillaText = {}
    for _, entry in ipairs(Helper.turretModes) do vanillaText[entry.id] = entry.text end
    assert(sel.options[1].text == vanillaText.attackenemies
        and sel.options[2].text == vanillaText.autoassist,
        "engaged selector options must reuse the vanilla Helper option texts")
    for i, option in ipairs(sel.options) do
        assert(type(option.displayremoveoption) == "boolean",
            "engaged selector option " .. i .. " (" .. tostring(option.id) .. ") must carry a "
            .. "boolean displayremoveoption for X4's createDropDown")
    end
    assert(sel.startOption == "attackenemies" and sess.directMode == "attackenemies",
        "engaged selector must start at session.directMode")
    local selLabel
    for _, entry in ipairs(fixE.getCreatedTexts()) do
        if entry.row == "direct_mode" and entry.column == 1 then selLabel = entry.text end
    end
    assert(selLabel == ReadText(20991, 101),
        "engaged selector label must come from localization id 101")
    assert(sel.mouseOverText == ReadText(20991, 102),
        "engaged selector help must come from localization id 102")

    -- Switch to autoassist while engaged: the checked group's live mode is
    -- written, no fallback list is installed, the watch is untouched, and the
    -- session keeps its target, camera, Auto-next, checkbox and baseline.
    local mark = #fixE.uiTriggeredEvents
    sel.handlers.onDropDownConfirmed(nil, "autoassist")
    assert(#liveModes == 1 and liveModes[1] == "autoassist",
        "engaged selector change must write the checked group's live mode: "
        .. table.concat(liveModes, ","))
    assert(#liveArmed == 0, "a policy switch must not touch armed state")
    local sawFallback, sawWatch = eventsSince(mark)
    assert(not sawFallback and not sawWatch,
        "switching to autoassist must not install a fallback list or re-arm the watch")
    assert(sess.directMode == "autoassist", "selector change must set session.directMode")
    assert(sess.aimTargetID == 77, "policy switch must not move the engaged target")
    assert(sess.cameraMemberID == 27, "policy switch must not move the camera")
    assert(sess.autoNextTarget == true, "policy switch must not touch Auto-next")
    assert(sess.checkedGroupKeys[key] == true, "policy switch must not touch checkbox membership")
    assert(sess.committedBaseline[1].mode == "attack",
        "policy switch must not touch the committed baseline")
    assert(sess.phase == "engaged" and sess.controlMode == "direct",
        "policy switch must not change the session phase")
    assert(sess.staged[key].mode == "autoassist",
        "the checked row's staged mode must follow the new policy")
    assert(grp.mode == "autoassist",
        "the live-mode bookkeeping must track the applied mode")

    -- Repaint: the selector now starts at the new policy.
    fixE.gcMenu.display()
    assert(latestRow(fixE, "direct_mode").startOption == "autoassist",
        "the selector must repaint at the new policy")

    -- Switch back to attackenemies: the live mode is written again and the
    -- preferred-target/fallback list is re-installed for the current target.
    mark = #fixE.uiTriggeredEvents
    latestRow(fixE, "direct_mode").handlers.onDropDownConfirmed(nil, "attackenemies")
    assert(#liveModes == 2 and liveModes[2] == "attackenemies",
        "switching back must re-mode the checked group once: " .. table.concat(liveModes, ","))
    sawFallback, sawWatch = eventsSince(mark)
    assert(sawFallback and sawWatch,
        "switching back to attackenemies must re-install the fallback list and keep the watch")
    assert(sess.directMode == "attackenemies", "selector must end at attackenemies")

    -- Re-confirming the current policy is a no-op: no live writes, no events.
    mark = #fixE.uiTriggeredEvents
    latestRow(fixE, "direct_mode").handlers.onDropDownConfirmed(nil, "attackenemies")
    assert(#liveModes == 2, "re-confirming the current policy must not write the live mode")
    sawFallback, sawWatch = eventsSince(mark)
    assert(not sawFallback and not sawWatch,
        "re-confirming the current policy must not re-issue MD events")

    fixE.C.SetTurretGroupMode2, fixE.C.SetTurretGroupArmed = savedSetMode, savedSetArmed
end

-- The auto-engage panel is not a Direct-control panel: no selector there.
do
    local fixA = dofile("tests/support/runtime_fixture.lua").load()
    local key = X4GunneryState.groupKey(5, "p", "g")
    local grp = fixA.makeGroup()
    fixA.gcMenu.onShowMenu()
    local sessA = fixA.API.getSession()
    sessA.groups = { grp }
    sessA.cameraMemberID = 27
    X4GunneryState.seedBaseline(sessA, { grp })
    X4GunneryState.toggleGroup(sessA, key, grp.armed)
    sessA.phase, sessA.controlMode = "engaged", "auto"
    fixA.gcMenu.display()
    local foundSelector
    for _, dd in ipairs(fixA.getCreatedDropDowns()) do
        if dd.row == "direct_mode" then foundSelector = dd end
    end
    assert(foundSelector == nil,
        "the auto-engage panel must not render the Direct-control selector")
end

print("runtime coverage ui direct tests passed")
