-- Pure state machine for the developer companion. No X4 calls live here.
X4GunneryTestLabState = X4GunneryTestLabState or {}
local State = X4GunneryTestLabState

function State.newSweep(ship)
    local queue, groupQueue, seen = {}, {}, {}
    for _, group in ipairs(ship.groups or {}) do
        for _, member in ipairs(group.members) do
            queue[#queue + 1] = { group = group, member = member }
        end
        if group.mutable and not seen[group.key] then groupQueue[#groupQueue + 1] = group; seen[group.key] = true end
    end
    local phase = #queue > 0 and "ready" or (#groupQueue > 0 and "groups" or "complete")
    return { ship = ship, queue = queue, groupQueue = groupQueue, index = 1, groupIndex = 1, results = {}, phase = phase, retries = 0, summaryLogged = false }
end

function State.current(sweep)
    return sweep and sweep.queue[sweep.index]
end

function State.targetsEqual(before, after)
    return tostring((before or {}).id or "0") == tostring((after or {}).id or "0")
        and ((before or {}).connection or "") == ((after or {}).connection or "")
end

function State.recordVerdict(sweep, verdict, reason, technical)
    local item = State.current(sweep)
    if not item then return false end
    if verdict == "retry" then sweep.retries = sweep.retries + 1; sweep.phase = "ready"; return true end
    sweep.results[#sweep.results + 1] = { kind = "turret", item = item, verdict = verdict, reason = reason or "", technical = technical }
    sweep.index = sweep.index + 1
    sweep.phase = sweep.index > #sweep.queue and "groups" or "ready"
    return true
end

function State.recordGroup(sweep, group, result)
    sweep.results[#sweep.results + 1] = { kind = "group", group = group, technical = result.pass and "pass" or "fail", reason = result.reason or "" }
    sweep.groupIndex = sweep.groupIndex + 1
    if sweep.groupIndex > #sweep.groupQueue then sweep.phase = "complete" end
end

function State.summary(sweep)
    local counts = { queued = #(sweep and sweep.queue or {}), inspected = 0, technicalPass = 0, visualPass = 0, visualFail = 0, skipped = 0, retries = sweep and sweep.retries or 0, groupChecks = 0, groupPass = 0, groupFail = 0 }
    for _, result in ipairs(sweep and sweep.results or {}) do
        if result.kind == "turret" then
            counts.inspected = counts.inspected + 1
            if result.technical == "pass" then counts.technicalPass = counts.technicalPass + 1 end
            if result.verdict == "pass" then counts.visualPass = counts.visualPass + 1 elseif result.verdict == "fail" then counts.visualFail = counts.visualFail + 1 elseif result.verdict == "skip" then counts.skipped = counts.skipped + 1 end
        else
            counts.groupChecks = counts.groupChecks + 1
            if result.technical == "pass" then counts.groupPass = counts.groupPass + 1 else counts.groupFail = counts.groupFail + 1 end
        end
    end
    return counts
end

return X4GunneryTestLabState
