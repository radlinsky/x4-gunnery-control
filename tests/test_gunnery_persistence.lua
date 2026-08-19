-- Pure transport tests for the Lua <-> MD persistence adapter.
local State = dofile("ui/gunnery_state.lua")
local Persistence = dofile("ui/gunnery_persistence.lua")

local events, handlers = {}, {}
local envelopes = {}
local adapter = Persistence.new({
    State = State,
    emit = function(control, payload) events[#events + 1] = { control = control, payload = payload } end,
    register = function(name, handler)
        handlers[name] = handlers[name] or {}
        handlers[name][#handlers[name] + 1] = handler
    end,
    toLuaID = function(value) return "lua:" .. value end,
    onEnvelope = function(value) envelopes[#envelopes + 1] = value end,
})

local function fire(name, value)
    for _, handler in ipairs(handlers[name] or {}) do handler(name, value) end
end

local session = State.newSession(42, "gunnercontrol")
session.shipName = "Persistence Test"
session.aimTargetID = 99
assert(adapter.commit(session))
assert(events[#events].control == "session_commit")
assert(events[#events].payload.hasTarget == true)
assert(events[#events].payload.target == "lua:99")
assert(type(events[#events].payload.payload) == "string")

session.aimTargetID = nil
adapter.commit(session)
assert(events[#events].payload.hasTarget == false)
assert(events[#events].payload.target == nil, "no-target commit must omit a stale target")

assert(adapter.request())
assert(not adapter.request(), "a pending request must coalesce")
assert(events[#events].control == "state_request")
local requestA = events[#events].payload.nonce
assert(type(requestA) == "string" and requestA:match("^[1-9][0-9]*$"), "request nonce must be decimal")
fire("X4GunneryControl.RestoreGrant", "x4gc1:" .. requestA .. ":7")
assert(handlers["X4GunneryControl.RestoreTarget.7"] and handlers["X4GunneryControl.RestoreSession.7"],
    "grant must register both response handlers before accepting")
assert(events[#events].control == "state_accept")
assert(events[#events].payload.generation == 7)
assert(events[#events].payload.nonce == requestA)
fire("X4GunneryControl.RestoreSession.7", "encoded")
assert(#envelopes == 0, "session-first response waits for target")
fire("X4GunneryControl.RestoreTarget.7", 123)
assert(#envelopes == 1 and envelopes[1].payload == "encoded" and envelopes[1].target == 123)
fire("X4GunneryControl.RestoreTarget.7", 456)
assert(#envelopes == 1, "duplicate responses must be ignored")

assert(adapter.request())
local requestB = events[#events].payload.nonce
fire("X4GunneryControl.RestoreGrant", "x4gc1:" .. requestB .. ":8")
fire("X4GunneryControl.RestoreTarget.8", 0)
fire("X4GunneryControl.RestoreSession.8", "")
assert(#envelopes == 2 and envelopes[2].target == 0 and envelopes[2].payload == "",
    "empty state completes the request so a later chair ingress can request again")

assert(adapter.request())
local requestC = events[#events].payload.nonce
fire("X4GunneryControl.RestoreGrant", "x4gc1:" .. requestC .. ":9")
adapter.clear()
fire("X4GunneryControl.RestoreTarget.9", 22)
fire("X4GunneryControl.RestoreSession.9", "late")
assert(#envelopes == 2, "clear invalidates pending replies")
assert(events[#events].control == "session_end")

-- The scalar envelope is intentionally strict: no bare number, wrong prefix,
-- zero fields, leading-zero ambiguity, or extra fields can bind a request.
for _, invalid in ipairs({ 12, "12", "x4gc1:0:12", "x4gc1:01:12", "x4gc1:12:0", "x4gc1:12:13:14", "x4gc1:12:2147483648" }) do
    assert(adapter.request())
    local eventCount = #events
    fire("X4GunneryControl.RestoreGrant", invalid)
    assert(#events == eventCount and not adapter.request(),
        "invalid grant must leave the valid request pending: " .. tostring(invalid))
    adapter.clear()
end

-- Exact stale-grant regression using a fresh adapter: A clears before *any*
-- grant arrives, B starts, then the delayed never-accepted A grant arrives
-- first.  Only B may install handlers, accept, and complete.
local raceEvents, raceHandlers, raceEnvelopes = {}, {}, {}
local raceAdapter = Persistence.new({
    State = State,
    emit = function(control, payload) raceEvents[#raceEvents + 1] = { control = control, payload = payload } end,
    register = function(name, handler)
        raceHandlers[name] = raceHandlers[name] or {}
        raceHandlers[name][#raceHandlers[name] + 1] = handler
    end,
    toLuaID = function(value) return "lua:" .. value end,
    onEnvelope = function(value) raceEnvelopes[#raceEnvelopes + 1] = value end,
})
local function fireRace(name, value)
    for _, handler in ipairs(raceHandlers[name] or {}) do handler(name, value) end
end

assert(raceAdapter.request())
local raceA = raceEvents[#raceEvents].payload.nonce
raceAdapter.clear()
assert(raceEvents[#raceEvents].control == "session_end", "A must clear before any grant")
assert(raceAdapter.request())
local raceB = raceEvents[#raceEvents].payload.nonce
local pendingEventCount = #raceEvents
fireRace("X4GunneryControl.RestoreGrant", "not-a-grant")
fireRace("X4GunneryControl.RestoreGrant", "x4gc1:" .. raceA .. ":91")
assert(#raceEvents == pendingEventCount and not raceHandlers["X4GunneryControl.RestoreTarget.91"],
    "invalid and stale-A grants must not cancel B or install A response handlers")
fireRace("X4GunneryControl.RestoreGrant", "x4gc1:" .. raceB .. ":10")
assert(raceEvents[#raceEvents].control == "state_accept" and raceEvents[#raceEvents].payload.nonce == raceB,
    "only B's matching nonce may be accepted")
local acceptedEventCount = #raceEvents
fireRace("X4GunneryControl.RestoreGrant", "x4gc1:" .. raceB .. ":10")
assert(#raceEvents == acceptedEventCount, "duplicate grants must be ignored after acceptance")
fireRace("X4GunneryControl.RestoreSession.10", "encoded-b")
fireRace("X4GunneryControl.RestoreTarget.10", 0)
assert(#raceEnvelopes == 1 and raceEnvelopes[1].payload == "encoded-b" and raceEnvelopes[1].target == 0,
    "B completes when its reversed-order reply pair arrives")
assert(raceAdapter.request(), "B completion must release the adapter for another restore")
raceAdapter.clear()

-- Forced re-request (savegame-load path): a new adapter receives a request,
-- gets no grant (simulating the pre-load dead request), then a forced
-- request(true) abandons the dead one and starts a fresh one.
local forceEvents, forceHandlers, forceEnvelopes = {}, {}, {}
local forceAdapter = Persistence.new({
    State = State,
    emit = function(control, payload) forceEvents[#forceEvents + 1] = { control = control, payload = payload } end,
    register = function(name, handler)
        forceHandlers[name] = forceHandlers[name] or {}
        forceHandlers[name][#forceHandlers[name] + 1] = handler
    end,
    toLuaID = function(value) return "lua:" .. value end,
    onEnvelope = function(value) forceEnvelopes[#forceEnvelopes + 1] = value end,
})
local function fireForce(name, value)
    for _, handler in ipairs(forceHandlers[name] or {}) do handler(name, value) end
end

-- first request goes outstanding, no grant arrives (dead request)
assert(forceAdapter.request(), "initial request must succeed")
local deadNonce = forceEvents[#forceEvents].payload.nonce
assert(not forceAdapter.request(), "unforced request while outstanding must coalesce")

-- forced re-request: must abandon the dead request and emit a new state_request
local eventCountBeforeForce = #forceEvents
assert(forceAdapter.request(true), "forced request must succeed even when outstanding")
assert(#forceEvents == eventCountBeforeForce + 1, "forced request must emit exactly one new event")
assert(forceEvents[#forceEvents].control == "state_request", "forced request must emit state_request")
local newNonce = forceEvents[#forceEvents].payload.nonce
assert(newNonce ~= deadNonce, "forced request must emit a different nonce")

-- no session_end must have been emitted at any point (reset(), not clear())
for _, ev in ipairs(forceEvents) do
    assert(ev.control ~= "session_end", "forced re-request must not emit session_end (must use reset not clear)")
end

-- a late grant carrying the abandoned nonce must be ignored entirely
local eventCountBeforeStale = #forceEvents
fireForce("X4GunneryControl.RestoreGrant", "x4gc1:" .. deadNonce .. ":20")
assert(#forceEvents == eventCountBeforeStale, "stale grant for abandoned nonce must not emit state_accept")
assert(not forceHandlers["X4GunneryControl.RestoreTarget.20"],
    "stale grant must not install RestoreTarget handler")
assert(not forceHandlers["X4GunneryControl.RestoreSession.20"],
    "stale grant must not install RestoreSession handler")
assert(not forceAdapter.request(), "adapter must still be outstanding after stale grant was ignored")

-- a grant for the new nonce must be accepted and its reply pair must complete
fireForce("X4GunneryControl.RestoreGrant", "x4gc1:" .. newNonce .. ":21")
assert(forceEvents[#forceEvents].control == "state_accept", "new nonce grant must emit state_accept")
assert(forceEvents[#forceEvents].payload.nonce == newNonce, "state_accept must carry the new nonce")
assert(forceEvents[#forceEvents].payload.generation == 21, "state_accept must carry the granted generation")
assert(forceHandlers["X4GunneryControl.RestoreTarget.21"],
    "new nonce grant must install RestoreTarget handler")
assert(forceHandlers["X4GunneryControl.RestoreSession.21"],
    "new nonce grant must install RestoreSession handler")
fireForce("X4GunneryControl.RestoreTarget.21", 77)
assert(#forceEnvelopes == 0, "target-first response still waits for session")
fireForce("X4GunneryControl.RestoreSession.21", "restored")
assert(#forceEnvelopes == 1 and forceEnvelopes[1].payload == "restored" and forceEnvelopes[1].target == 77,
    "reply pair for new nonce must complete the envelope")

-- final session_end guard: still none after the whole forced sequence
for _, ev in ipairs(forceEvents) do
    assert(ev.control ~= "session_end", "session_end must never appear in the forced re-request sequence")
end

print("persistence adapter tests passed")
