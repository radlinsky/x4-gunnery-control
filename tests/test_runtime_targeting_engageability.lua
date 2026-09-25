-- Auto-next still consumes the old ENGAGEABLE service until P3. Protect its
-- selected membership and stale-result boundary without browser presentation.
local fix = dofile("tests/support/runtime_fixture.lua").load()
local API, C = fix.API, fix.C
fix.gcMenu.onShowMenu()
local session = API.getSession()
session.groups = {
    { key = "selected", members = {
        { componentID = 101, operational = true },
        { componentID = 102, operational = true },
        { componentID = 199, operational = false },
    } },
    { key = "unchecked", members = { { componentID = 103, operational = true } } },
}
session.checkedGroupKeys = { selected = true }
local events = {}
local originalAdd = AddUITriggeredEvent
AddUITriggeredEvent = function(_, control, params)
    events[#events + 1] = { control = control, params = params }
end
local pending = API.requestEngageability(900)
assert(pending.pending and pending.total == 2, "Auto-next denominator must contain selected operational turrets")
assert(#events == 5 and events[1].control == "engageability_begin"
    and events[2].params.weapon == 101 and events[3].params.weapon == 102
    and events[4].params.target == 900 and events[5].control == "engageability_commit",
    "Auto-next service must send selected members once before the target")
local nonce = events[1].params.nonce
fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. nonce .. ":999:2:2:2")
assert(pending.pending, "unrequested target must not complete a request")
fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. nonce .. ":900:3:3:3")
assert(pending.pending, "wrong denominator must not complete a request")
fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. nonce .. ":900:1:2:2")
assert(not pending.pending and pending.engageable == 1 and pending.total == 2,
    "correlated Auto-next result must settle")
local clock = pending.requestedAt + 3
getElapsedTime = function() return clock end
events = {}
local refreshed = API.requestEngageability(900)
assert(refreshed.pending and refreshed.engageable == nil and events[1].params.nonce ~= nonce,
    "expired evidence must be refreshed with a new nonce")
fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. nonce .. ":900:2:2:2")
assert(refreshed.pending, "late previous result must be discarded")
session.checkedGroupKeys.unchecked = true
events = {}
local changed = API.requestEngageability(900)
assert(changed.pending and changed.total == 3, "selection change must invalidate Auto-next evidence")
AddUITriggeredEvent = originalAdd
print("runtime Auto-next engageability service tests passed")
