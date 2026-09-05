-- test_runtime_targeting_engageability.lua
-- Engageability batches: member streaming, stale-guard preservation,
-- nonce collision, timeout, and incomplete batch handling.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local gcMenu = fix.gcMenu
local API    = fix.API
local C      = fix.C

-- Shared clock for getElapsedTime; tests advance it explicitly.
local clock = 100
getElapsedTime = function() return clock end

-- A reusable group used across many rendering and targeting tests.
local grp27 = fix.makeGroup{
    key = "grp27", displayName = "G27",
    members = { { componentID = 27, displayName = "T1", operational = true,
                  cameraSupported = true, componentKey = "27" } },
}

-- Bring the module into a known state.
local ok_init, err_init = pcall(function() gcMenu.onShowMenu() end)
assert(ok_init, "onShowMenu() raised: " .. tostring(err_init))
local sess = API.getSession()
assert(sess ~= nil, "expected a live session after onShowMenu()")

-- ── 57. engageability batches stream members once and preserve stale guards ──────
do
    local sess57 = API.getSession()
    sess57.phase, sess57.controlMode = "console", nil
    sess57.groups = {
        { key = "selected", members = {
            { componentID = 101, operational = true },
            { componentID = 102, operational = true },
            { componentID = 199, operational = false },
        } },
        { key = "unchecked", members = { { componentID = 103, operational = true } } },
    }
    sess57.checkedGroupKeys = { selected = true }
    gcMenu.shown = true
    local savedAdd57, events57 = AddUITriggeredEvent, {}
    local savedComponentData57 = GetComponentData
    GetComponentData = function(component, ...)
        local values = {}
        for _, key in ipairs({...}) do
            if key == "macro" and tonumber(component) == 101 then
                values[#values + 1] = "turret_bor_m_railgun_02_mk1_macro"
            elseif key == "macro" then
                values[#values + 1] = "third_party_unknown_turret_macro"
            else
                values[#values + 1] = false
            end
        end
        return unpack(values)
    end
    AddUITriggeredEvent = function(screen, control, params)
        events57[#events57 + 1] = { screen = screen, control = control, params = params }
    end
    local pending57 = API.requestEngageability(900)
    assert(pending57.pending and pending57.total == 2, "57: pending denominator must be two exact selected turrets")
    local controls57, nonce57 = {}, nil
    for _, event in ipairs(events57) do
        controls57[#controls57 + 1] = event.control
        if event.control == "engageability_begin" then nonce57 = event.params.nonce end
    end
    assert(table.concat(controls57, ",") == "engageability_begin,engageability_member,engageability_member,engageability_target,engageability_commit",
        "57: engageability transport must stream selected members once before its target ids")
    assert(events57[2].params.weapon == 101 and events57[3].params.weapon == 102,
        "57: unchecked or inoperable turret leaked into exact-member request")
    assert(events57[2].params.arcknow == 1 and events57[2].params.arcmin == -10
            and events57[2].params.arcmax == 89,
        "57: official turret member must stream its generated pitch interval")
    assert(events57[3].params.arcknow == 0,
        "57: an unknown third-party turret must stream UNKNOWN, not invented limits")
    assert(events57[1].params.members == 2 and events57[1].params.targets == 1
            and events57[4].params.target == 900,
        "57: batch declarations and target correlation must carry exact counts and ids")
    sess57.phase = "target_select"
    GetPlayerContextByClass = function() return nil end
    C.GetSofttarget2 = function() return { softtargetID = 0, softtargetConnectionName = "" } end
    local firstRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. nonce57 .. ":999:2:2:2")
    assert(pending57.pending and pending57.engageable == nil
            and fix.callbackCheckpoint() == firstRepaintMark57,
        "57: a reply for an unrequested target must not complete or repaint the batch")
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. nonce57 .. ":900:1:1:2")
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete", "x4gce2c:" .. nonce57 .. ":1:1")
    assert(pending57.pending == false and pending57.engageable == 1 and pending57.known == 1
            and pending57.total == 2,
        "57: matching arc-aware packed result was not accepted")
    assert(API.engageabilityText(pending57) == "1 / 2  1 " .. ReadText(20991, 100),
        "57: unknown macro coverage must be explicit and must suppress ENGAGEABLE")
    assert(fix.callbackCheckpoint() == firstRepaintMark57 + 1,
        "57: the first accepted engageability result must schedule one deferred repaint")
    fix.drainCallbacksSince(firstRepaintMark57)
    events57 = {}
    assert(API.requestEngageability(900) == pending57 and #events57 == 0,
        "57: a result must be cached for one second")

    local savedElapsed57, clock57 = getElapsedTime, (pending57.requestedAt or 0) + 2
    getElapsedTime = function() return clock57 end
    events57 = {}
    local refreshed57 = API.requestEngageability(900)
    assert(refreshed57 == pending57 and refreshed57.pending and refreshed57.engageable == nil,
        "57: refreshing an expired completed result must clear its stale count; pending="
            .. tostring(refreshed57.pending) .. " engageable=" .. tostring(refreshed57.engageable)
            .. " requested=" .. tostring(refreshed57.requestedAt))
    assert(API.engageabilityText(refreshed57) == "… / 2",
        "57: an expired completed result must render pending, not stale ENGAGEABLE text")
    local refreshNonce57 = events57[1].params.nonce
    local refreshRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. refreshNonce57 .. ":900:0:2:2")
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete", "x4gce2c:" .. refreshNonce57 .. ":1:1")
    fix.drainCallbacksSince(refreshRepaintMark57)

    sess57.checkedGroupKeys.unchecked = true
    events57 = {}
    local changed57 = API.requestEngageability(900)
    assert(changed57.pending and changed57.total == 3 and #events57 == 6,
        "57: checkbox membership change must invalidate cache and stream the new exact denominator")
    local changedNonce57 = events57[1].params.nonce
    local denominatorRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. changedNonce57 .. ":900:2:2:2")
    assert(changed57.pending and changed57.engageable == nil
            and fix.callbackCheckpoint() == denominatorRepaintMark57,
        "57: a result whose denominator shrank below the requested membership must be rejected")
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. changedNonce57 .. ":900:2:3:3")
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete", "x4gce2c:" .. changedNonce57 .. ":1:1")
    fix.drainCallbacksSince(denominatorRepaintMark57)

    events57 = {}
    local timed57 = API.requestEngageability(901)
    local oldNonce57 = events57[1].params.nonce
    clock57 = timed57.requestedAt + 3
    events57 = {}
    assert(API.requestEngageability(901) == timed57 and events57[1].params.nonce ~= oldNonce57,
        "57: a timed-out engageability request must be replaced with a fresh nonce")
    local newNonce57 = events57[1].params.nonce
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete", "x4gce2c:" .. oldNonce57 .. ":1:1")
    assert(not table.concat(fix.getCapturedLog(), "\n"):find(
            "event=engageability_batch action=complete nonce=" .. oldNonce57, 1, true),
        "57: superseding the final target must discard its empty prior request")
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. oldNonce57 .. ":901:3:3:3")
    assert(timed57.pending and timed57.engageable == nil,
        "57: a superseded engageability response must not complete the replacement request")
    local timeoutRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. newNonce57 .. ":901:2:3:3")
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete", "x4gce2c:" .. newNonce57 .. ":1:1")
    assert(not timed57.pending and timed57.engageable == 2,
        "57: the replacement engageability response must still complete normally")
    fix.drainCallbacksSince(timeoutRepaintMark57)

    events57 = {}
    local missingComplete57 = API.requestEngageability(902)
    local missingCompleteNonce57 = events57[1].params.nonce
    local missingCompleteRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult",
        "x4gce3:" .. missingCompleteNonce57 .. ":902:2:3:3")
    clock57 = missingComplete57.requestedAt + 2
    events57 = {}
    assert(API.requestEngageability(902) == missingComplete57
            and events57[1].params.nonce ~= missingCompleteNonce57,
        "57: a completed result whose batch completion was lost must refresh after its cache TTL")
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete",
        "x4gce2c:" .. missingCompleteNonce57 .. ":1:1")
    assert(not table.concat(fix.getCapturedLog(), "\n"):find(
            "event=engageability_batch action=complete nonce=" .. missingCompleteNonce57, 1, true),
        "57: post-TTL refresh must reclaim an empty request whose batch completion was lost")
    fix.drainCallbacksSince(missingCompleteRepaintMark57)

    local batchEvents57, batchNonces57, batchTargets57 = {}, {}, {}
    events57 = batchEvents57
    local requestedTargets57 = {}
    for target = 910, 945 do requestedTargets57[#requestedTargets57 + 1] = target end
    API.requestEngageabilities(requestedTargets57)
    local activeBatch57
    for _, event in ipairs(batchEvents57) do
        if event.control == "engageability_begin" then
            activeBatch57 = event.params.nonce
            batchNonces57[#batchNonces57 + 1] = activeBatch57
            batchTargets57[activeBatch57] = {}
        elseif event.control == "engageability_target" then
            batchTargets57[activeBatch57][#batchTargets57[activeBatch57] + 1] = event.params.target
        end
    end
    assert(#batchNonces57 == 2
            and #batchTargets57[batchNonces57[1]] == 20
            and #batchTargets57[batchNonces57[2]] == 16,
        "57: 36 targets must be bounded into 20-target and 16-target batches")
    local memberEvents57 = 0
    for _, event in ipairs(batchEvents57) do
        if event.control == "engageability_member" then memberEvents57 = memberEvents57 + 1 end
    end
    assert(memberEvents57 == 6,
        "57: three selected turrets must be sent once per batch, not once per target")
    local batchLog57 = table.concat(fix.getCapturedLog(), "\n")
    assert(batchLog57:find("event=engageability_batch action=request", 1, true)
            and batchLog57:find("requested=20 selected_total=3", 1, true)
            and batchLog57:find("requested=16 selected_total=3", 1, true),
        "57: aggregate request logs must prove bounded targets and exact selected-turret totals")
    local batchRepaintMark57 = fix.callbackCheckpoint()
    local renderedBefore57 = 0
    for _, line in ipairs(fix.getCapturedLog()) do
        if line:find("event=target_browser action=rendered", 1, true) then renderedBefore57 = renderedBefore57 + 1 end
    end
    for _, nonce in ipairs(batchNonces57) do
        for _, target in ipairs(batchTargets57[nonce]) do
            fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. nonce .. ":" .. target .. ":2:3:3")
        end
        fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete",
            "x4gce2c:" .. nonce .. ":" .. #batchTargets57[nonce] .. ":" .. #batchTargets57[nonce])
    end
    batchLog57 = table.concat(fix.getCapturedLog(), "\n")
    assert(batchLog57:find("requested=20 accepted=20 completed=20 unresolved=0", 1, true)
            and batchLog57:find("requested=16 accepted=16 completed=16 unresolved=0", 1, true),
        "57: aggregate completion logs must prove all declared targets completed")
    assert(fix.callbackCheckpoint() == batchRepaintMark57 + 1,
        "57: a burst of 36 engageability replies must coalesce to one repaint callback")
    fix.drainCallbacksSince(batchRepaintMark57)
    local renderedAfter57 = 0
    for _, line in ipairs(fix.getCapturedLog()) do
        if line:find("event=target_browser action=rendered", 1, true) then renderedAfter57 = renderedAfter57 + 1 end
    end
    assert(renderedAfter57 == renderedBefore57 + 1,
        "57: a burst of engageability replies must produce one target-browser audit batch")

    sess57.phase, sess57.controlMode, sess57.targetObjectID = "engaged", "direct", nil
    events57 = {}
    API.requestEngageability(950)
    local engagedNonce57 = events57[1].params.nonce
    local engagedRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. engagedNonce57 .. ":950:2:3:3")
    fix.drainCallbacksSince(engagedRepaintMark57)
    assert(fix.callbackCheckpoint() == engagedRepaintMark57 + 1,
        "57: Direct-control engageability replies must use the same deferred repaint path")

    events57 = {}
    API.requestEngageability(951)
    local testLabNonce57 = events57[1].params.nonce
    local testLabRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. testLabNonce57 .. ":951:2:3:3")
    X4GunneryState.setLifecycle(sess57, X4GunneryState.lifecycle.reopening)
    gcMenu.shown = false
    local hiddenAuditBefore57 = #fix.getCapturedLog()
    fix.drainCallbacksSince(testLabRepaintMark57)
    assert(#fix.getCapturedLog() == hiddenAuditBefore57,
        "57: a deferred reply must not repaint after Test Lab takes ownership")

    X4GunneryState.setLifecycle(sess57, X4GunneryState.lifecycle.owned)
    gcMenu.shown = true
    events57 = {}
    API.requestEngageability(952)
    local mapNonce57 = events57[1].params.nonce
    local mapRepaintMark57 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. mapNonce57 .. ":952:2:3:3")
    X4GunneryState.setLifecycle(sess57, X4GunneryState.lifecycle.suspendedMap)
    gcMenu.shown = false
    hiddenAuditBefore57 = #fix.getCapturedLog()
    fix.drainCallbacksSince(mapRepaintMark57)
    assert(#fix.getCapturedLog() == hiddenAuditBefore57,
        "57: a deferred reply must not repaint while Map owns the view")

    X4GunneryState.setLifecycle(sess57, X4GunneryState.lifecycle.owned)
    gcMenu.shown = true
    sess57.phase, sess57.controlMode = "target_select", nil
    events57 = {}
    local incomplete57 = API.requestEngageability(953)
    local incompleteNonce57 = events57[1].params.nonce
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete",
        "x4gce2c:" .. incompleteNonce57 .. ":0:0")
    assert(incomplete57.pending and incomplete57.engageable == nil
            and table.concat(fix.getCapturedLog(), "\n"):find(
                "requested=1 accepted=0 completed=0 unresolved=1", 1, true),
        "57: an incomplete batch must remain pending and emit one aggregate unresolved count")
    getElapsedTime = savedElapsed57
    GetComponentData = savedComponentData57
    AddUITriggeredEvent = savedAdd57
end


-- ── 58. the generated Beam member reproduces the accepted prospective muzzle ──
-- The production consumer (gunnery_control.lua) derives O/P/D from the generated
-- geometry record and streams them as the engageability_member muzzle scalars.
-- This proves those generated scalars, fed through the exact MD construction
-- O + Ry(yaw) * (P + Rx(-pitch) * D), reproduce the accepted hardcoded Beam
-- prospective muzzle positions the MD literals used to encode, across poses.
do
    local function qrotate(q, v)
        local x, y, z, w = q[1], q[2], q[3], q[4]
        local vx, vy, vz = v[1], v[2], v[3]
        local tx = 2 * (y * vz - z * vy)
        local ty = 2 * (z * vx - x * vz)
        local tz = 2 * (x * vy - y * vx)
        return {
            vx + w * tx + y * tz - z * ty,
            vy + w * ty + z * tx - x * tz,
            vz + w * tz + x * ty - y * tx,
        }
    end
    local function axisRotation(axis, degrees)
        local r = math.rad(degrees) / 2
        local s = math.sin(r)
        if axis == "x" then return { s, 0, 0, math.cos(r) } end
        return { 0, s, 0, math.cos(r) }
    end
    local function vadd(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
    -- The accepted hardcoded literals the MD fallback used to carry (#74 A1).
    local function acceptedMuzzle(yaw, pitch)
        local O = vadd({ 1.877547e-6, 2.018104, -1.043081e-5 },
                       { 0, 6.145042419433594, 0 })
        local P = { -1.730653e-6, 2.926126, -16.11956 }
        local D = { -0.36177411330546533, 0.4829345992763463, 55.87084740617998 }
        local pitched = qrotate(axisRotation("x", -pitch), D)
        return vadd(O, qrotate(axisRotation("y", yaw), vadd(P, pitched)))
    end
    -- Same construction, but from whatever O/P/D the production consumer streamed.
    local function generatedMuzzle(m, yaw, pitch)
        local O = { m.mox, m.moy, m.moz }
        local P = { m.mpx, m.mpy, m.mpz }
        local D = { m.mdx, m.mdy, m.mdz }
        local pitched = qrotate(axisRotation("x", -pitch), D)
        return vadd(O, qrotate(axisRotation("y", yaw), vadd(P, pitched)))
    end

    -- Stream one engageability_member for a turret of the given macro and hand
    -- back the parameters the production consumer itself produced.
    local function streamMember(macroName, componentID, targetID)
        local sess = API.getSession()
        sess.phase, sess.controlMode = "console", nil
        sess.groups = {
            { key = "selected", members = { { componentID = componentID, operational = true } } },
        }
        sess.checkedGroupKeys = { selected = true }
        gcMenu.shown = true
        local savedAdd, member = AddUITriggeredEvent, nil
        local savedComponentData = GetComponentData
        GetComponentData = function(component, ...)
            local values = {}
            for _, key in ipairs({...}) do
                values[#values + 1] = (key == "macro") and macroName or false
            end
            return unpack(values)
        end
        AddUITriggeredEvent = function(screen, control, params)
            if control == "engageability_member" then member = params end
        end
        API.requestEngageability(targetID)
        AddUITriggeredEvent = savedAdd
        GetComponentData = savedComponentData
        return member
    end

    local member58 = streamMember("turret_par_l_beam_01_mk1_macro", 581, 800)

    assert(member58 ~= nil, "58: no engageability_member streamed for the Beam turret")
    assert(member58.muzzleknow == 1,
        "58: the generated Beam member must stream muzzleknow=1")
    for _, yaw in ipairs({ -90, 0, 90 }) do
        for _, pitch in ipairs({ -5, 30, 80 }) do
            local got = generatedMuzzle(member58, yaw, pitch)
            local want = acceptedMuzzle(yaw, pitch)
            for axis = 1, 3 do
                assert(math.abs(got[axis] - want[axis]) <= 1e-6, string.format(
                    "58: generated Beam muzzle diverges from accepted literal at "
                    .. "yaw=%g pitch=%g axis=%d (got %.17g want %.17g)",
                    yaw, pitch, axis, got[axis], want[axis]))
            end
        end
    end

    -- ── 59. the same production consumer reproduces the accepted #83 M Laser
    -- live aim poses (issue #98 A2). Poses are the never-fitted witnesses from
    -- tests/test_turret_muzzle_geometry.lua; yaw/pitch are radians there.
    local laserPoses = {
        { "center", 0, 0.747567, -0.313826, 5.19057, 2.90662 },
        { "yaw right", 0.592892, 0.736931, 1.66678, 5.14855, 2.53582 },
        { "yaw left", -0.592892, 0.736930, -2.1873, 5.14855, 2.18511 },
        { "pitch low", 0, 0.363425, -0.313826, 3.42557, 4.12367 },
        { "pitch high", 0, 1.12376, -0.313826, 6.35365, 1.15801 },
        { "right low", 0.578989, 0.357808, 2.27399, 3.39663, 3.55235 },
        { "right high", 0.636900, 1.10904, 0.778724, 6.32098, 1.08071 },
        { "left low", -0.578989, 0.357808, -2.79934, 3.39663, 3.20892 },
        { "left high", -0.636900, 1.10904, -1.28332, 6.32098, 0.707438 },
    }
    local member59 = streamMember("turret_par_m_laser_01_mk1_macro", 591, 900)
    assert(member59 ~= nil, "59: no engageability_member streamed for the M Laser turret")
    assert(member59.muzzleknow == 1,
        "59: the generated M Laser member must stream muzzleknow=1")
    for _, pose in ipairs(laserPoses) do
        local name, yaw, pitch = pose[1], math.deg(pose[2]), math.deg(pose[3])
        local got = generatedMuzzle(member59, yaw, pitch)
        local squared = 0
        for axis = 1, 3 do
            local difference = got[axis] - pose[axis + 3]
            squared = squared + difference * difference
        end
        local distance = math.sqrt(squared)
        assert(distance <= 2e-5, string.format(
            "59: streamed M Laser muzzle misses accepted pose %s by %.9g m "
            .. "(%.9g, %.9g, %.9g)", name, distance, got[1], got[2], got[3]))
    end
end


print("runtime targeting engageability tests passed")
