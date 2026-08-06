local State = dofile("testlab/x4_gunnery_control_testlab/ui/testlab_state.lua")
local function eq(a, b, label) assert(a == b, (label or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local ship = { groups = {
    { key = "camera-only", mutable = false, members = { { id = "1" } } },
    { key = "mutable", mutable = true, members = { { id = "2" }, { id = "3" } } },
} }
local sweep = State.newSweep(ship)
eq(#sweep.queue, 3, "all physical turrets are swept")
eq(#sweep.groupQueue, 1, "only mutable group is Engage-tested")
eq(State.current(sweep).member.id, "1", "queue order is deterministic")
State.recordVerdict(sweep, "retry", "", "pass"); eq(sweep.index, 1, "retry does not advance"); eq(sweep.retries, 1, "retry count")
State.recordVerdict(sweep, "pass", "", "pass"); eq(sweep.index, 2, "pass advances")
State.recordVerdict(sweep, "skip", "manual", "fail"); State.recordVerdict(sweep, "fail", "", "pass")
eq(sweep.phase, "groups", "turret completion starts group checks")
State.recordGroup(sweep, sweep.groupQueue[1], { pass = true })
eq(sweep.phase, "complete", "group completion finishes sweep")
local summary = State.summary(sweep)
eq(summary.queued, 3, "summary queue count"); eq(summary.visualPass, 1, "summary visual pass")
eq(summary.visualFail, 1, "summary visual fail"); eq(summary.skipped, 1, "summary skip")
eq(summary.groupPass, 1, "summary group pass")
eq(State.newSweep({ groups = {} }).phase, "complete", "empty sweep completes safely")
eq(State.newSweep({ groups = { { key = "g", mutable = true, members = {} } } }).phase, "groups", "group-only sweep enters group checks")
assert(State.targetsEqual({ id = "3", connection = "engine" }, { id = 3, connection = "engine" }), "target identity is normalized")
assert(not State.targetsEqual({ id = "3", connection = "engine" }, { id = "3", connection = "turret" }), "surface connection is part of identity")
print("testlab_state tests passed")
