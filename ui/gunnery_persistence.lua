-- Session persistence transport.  This module intentionally knows nothing
-- about the game runtime: it only encodes state and coordinates MD events.
X4GunneryPersistence = X4GunneryPersistence or {}
local Persistence = X4GunneryPersistence

function Persistence.new(deps)
    assert(deps and deps.State and deps.emit and deps.register and deps.toLuaID,
        "X4GunneryPersistence.new requires State, emit, register and toLuaID")

    local outstanding, generation, targetSeen, sessionSeen = false, nil, false, false
    local lastGeneration = 0
    local targetValue, sessionValue = nil, nil

    local function reset()
        outstanding, generation, targetSeen, sessionSeen = false, nil, false, false
        targetValue, sessionValue = nil, nil
    end

    local function complete()
        if not outstanding or not targetSeen or not sessionSeen then return end
        local envelope = { generation = generation, target = targetValue, payload = sessionValue }
        reset()
        deps.onEnvelope(envelope)
    end

    local function receiveTarget(expected, _, value)
        if not outstanding or generation ~= expected or targetSeen then return end
        targetSeen = true
        -- MD deliberately sends 0 when no component survived, rather than
        -- omitting this half of the protocol.
        targetValue = value
        complete()
    end

    local function receiveSession(expected, _, value)
        if not outstanding or generation ~= expected or sessionSeen then return end
        sessionSeen = true
        sessionValue = type(value) == "string" and value or ""
        complete()
    end

    local api = {}

    function api.commit(session)
        if not session then return false end
        local target = session.aimTargetID
        local hasTarget = target ~= nil and not deps.State.isNullID(target)
        local payload = {
            payload = deps.State.encode(deps.State.saveState(session)),
            hasTarget = hasTarget,
        }
        if hasTarget then payload.target = deps.toLuaID(deps.State.normID(target)) end
        deps.emit("session_commit", payload)
        return true
    end

    function api.clear()
        reset()
        deps.emit("session_end", {})
    end

    function api.request()
        if outstanding then return false end
        outstanding = true
        generation, targetSeen, sessionSeen = nil, false, false
        targetValue, sessionValue = nil, nil
        deps.emit("state_request", {})
        return true
    end

    deps.register("X4GunneryControl.RestoreGrant", function(_, value)
        if not outstanding or generation ~= nil then return end
        local nextGeneration = tonumber(value)
        if not nextGeneration or nextGeneration <= 0 or nextGeneration ~= math.floor(nextGeneration) then
            reset()
            return
        end
        -- A dynamic event from a cleared/superseded request can arrive after a
        -- newer request has begun. Keep waiting for the newer grant; do not let
        -- an old lease install handlers for its replies.
        if nextGeneration <= lastGeneration then return end
        generation = nextGeneration
        lastGeneration = nextGeneration
        local grantedGeneration = nextGeneration
        -- These handlers must exist before state_accept: MD can raise both
        -- replies immediately, and raise_lua_event carries one scalar only.
        deps.register("X4GunneryControl.RestoreTarget." .. tostring(grantedGeneration),
            function(name, value) receiveTarget(grantedGeneration, name, value) end)
        deps.register("X4GunneryControl.RestoreSession." .. tostring(grantedGeneration),
            function(name, value) receiveSession(grantedGeneration, name, value) end)
        deps.emit("state_accept", { generation = grantedGeneration })
    end)

    return api
end

return X4GunneryPersistence
