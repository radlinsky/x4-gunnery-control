-- TEMPORARY issue #184 A8: delete with the A8 diagnostic during A9 cleanup.
-- The Test Lab port of the frozen search must ask exactly the positions the
-- accepted Python search asks, finish with the same points, and never spend a
-- 41st sample.

local traces = dofile("tests/fixtures/issue184_a8_traces.lua")
local fix = dofile("tests/support/runtime_fixture.lua").load()
X4GunneryTestLabState = nil
dofile("testlab/x4_gunnery_control_testlab/ui/testlab_state.lua")
X4GunneryTestLabScenarioSpec = nil
dofile("testlab/x4_gunnery_control_testlab/ui/testlab.lua")
local testMenu
for _, candidate in ipairs(Menus) do
    if candidate.name == "X4GunneryTestLab" then testMenu = candidate end
end
local search = assert(testMenu and testMenu.a8Search, "testlab.lua must expose the A8 search")

local function near(a, b, tol, what)
    for k = 1, 3 do
        assert(math.abs(a[k] - b[k]) <= tol * math.max(1, math.abs(b[k])),
            what .. string.format(": %.17g vs %.17g", a[k], b[k]))
    end
end

-- The same sample sequence, stop reason and (refined) points as Python.
for _, case in ipairs(traces) do
    local kinds = {}
    local result = search(case.C, case.H, function(n, p, kind)
        local want = assert(case.asks[n], case.name .. ": Lua asked more samples than Python")
        near(p, want.p, 1e-9, case.name .. " sample " .. n .. " position")
        kinds[kind] = (kinds[kind] or 0) + 1
        return want.d
    end)
    assert(result.samples == case.samples and result.samples == #case.asks,
        case.name .. ": " .. result.samples .. " samples, Python used " .. case.samples)
    assert(result.stop == case.stop, case.name .. ": stop " .. tostring(result.stop))
    assert(#result.points == #case.points and #result.refined == #case.refined, case.name .. ": point count")
    for i, point in ipairs(case.points) do
        near(result.points[i].c, point.c, 1e-9, case.name .. " point " .. i)
        near(result.refined[i].c, case.refined[i].c, 1e-9, case.name .. " refined " .. i)
        assert(math.abs(result.refined[i].r - case.refined[i].r) <= 1e-9 * math.max(1, case.refined[i].r),
            case.name .. " refined radius " .. i)
    end
    assert(#result.found == #case.found, case.name .. ": confirmation history")
    for i, entry in ipairs(case.found) do
        assert(result.found[i][1] == entry[1] and result.found[i][2] == entry[2], case.name .. ": confirmed at")
    end
    assert(kinds.start == 8, case.name .. ": the 8 corners start every search")
end

-- The 40-sample cap is shared by every kind of sample. Random many-point
-- targets under X4's nearest-point rule drive confirmation-heavy searches;
-- some spend exactly 40 samples and none may spend a 41st.
do
    local seed, most = 1, 0
    local function rnd()
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed / 2147483648
    end
    for _ = 1, 60 do
        local points = {}
        for i = 1, 2 + math.floor(rnd() * 20) do
            points[i] = { (rnd() * 2 - 1) * 100, (rnd() * 2 - 1) * 50, (rnd() * 2 - 1) * 200 }
        end
        local asked = 0
        local result = search({ 0, 0, 0 }, { 100, 50, 200 }, function(n, p)
            asked = n
            local best, bestDistance
            for _, q in ipairs(points) do
                local distance = (q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2 + (q[3] - p[3]) ^ 2
                if not bestDistance or distance < bestDistance then best, bestDistance = q, distance end
            end
            local v = { best[1] - p[1], best[2] - p[2], best[3] - p[3] }
            local length = math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
            return { v[1] / length, v[2] / length, v[3] / length }
        end)
        assert(asked <= 40 and result.samples == asked, "the A8 search must never ask a 41st sample")
        most = math.max(most, asked)
    end
    assert(most == 40, "confirmation samples must share the 40-sample budget")
end

-- With no A8 session running, a stray A8 answer is ignored and sends nothing.
-- The correlated live driver is tested through Create/READY in
-- test_testlab_lifecycle_scenario.lua.
local before = #fix.uiTriggeredEvents
fix.fireEvent("X4GunneryTestLab.A8Probe", "x4gca8p:stale_1_1:1:0:0:1000000000")
assert(#fix.uiTriggeredEvents == before and fix.logContains("event=a8_ignored"),
    "A8 answers without an A8 session must be ignored")
print("test_testlab_issue184_a8.lua: ok")
