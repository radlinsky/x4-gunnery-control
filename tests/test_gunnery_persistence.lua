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
fire("X4GunneryControl.RestoreGrant", 7)
assert(handlers["X4GunneryControl.RestoreTarget.7"] and handlers["X4GunneryControl.RestoreSession.7"],
    "grant must register both response handlers before accepting")
assert(events[#events].control == "state_accept")
assert(events[#events].payload.generation == 7)
fire("X4GunneryControl.RestoreSession.7", "encoded")
assert(#envelopes == 0, "session-first response waits for target")
fire("X4GunneryControl.RestoreTarget.7", 123)
assert(#envelopes == 1 and envelopes[1].payload == "encoded" and envelopes[1].target == 123)
fire("X4GunneryControl.RestoreTarget.7", 456)
assert(#envelopes == 1, "duplicate responses must be ignored")

assert(adapter.request())
fire("X4GunneryControl.RestoreGrant", 8)
fire("X4GunneryControl.RestoreTarget.8", 0)
fire("X4GunneryControl.RestoreSession.8", "")
assert(#envelopes == 2 and envelopes[2].target == 0 and envelopes[2].payload == "",
    "empty state completes the request so a later chair ingress can request again")

assert(adapter.request())
fire("X4GunneryControl.RestoreGrant", 9)
adapter.clear()
fire("X4GunneryControl.RestoreTarget.9", 22)
fire("X4GunneryControl.RestoreSession.9", "late")
assert(#envelopes == 2, "clear invalidates pending replies")
assert(events[#events].control == "session_end")

assert(adapter.request())
-- Handler registrations remain after a request ends, so prove an old dynamic
-- grant or reply cannot satisfy the newer request.
fire("X4GunneryControl.RestoreGrant", 9)
assert(events[#events].control == "state_request", "stale grant must not be accepted")
fire("X4GunneryControl.RestoreGrant", 10)
fire("X4GunneryControl.RestoreTarget.9", 22)
fire("X4GunneryControl.RestoreSession.9", "stale")
assert(#envelopes == 2, "old-generation replies must be ignored after a newer grant")
fire("X4GunneryControl.RestoreTarget.10", 0)
fire("X4GunneryControl.RestoreSession.10", "")
assert(#envelopes == 3 and envelopes[3].generation == 10)

-- A malformed lease is not allowed to pin the adapter forever: discard that
-- request and permit a clean retry. MD only grants positive integer leases.
assert(adapter.request())
fire("X4GunneryControl.RestoreGrant", "not-a-generation")
assert(adapter.request(), "an invalid grant resets the outstanding request")
adapter.clear()

print("persistence adapter tests passed")
