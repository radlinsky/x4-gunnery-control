-- Session persistence transport.  This module intentionally knows nothing
-- about the game runtime: it only encodes state and coordinates MD events.
X4GunneryPersistence = X4GunneryPersistence or {}
local Persistence = X4GunneryPersistence

function Persistence.new(deps)
    assert(deps and deps.State and deps.emit and deps.register and deps.toLuaID,
        "X4GunneryPersistence.new requires State, emit, register and toLuaID")

    local outstanding, nonce, generation, targetSeen, sessionSeen = false, nil, nil, false, false
    local lastGeneration = 0
    local targetValue, sessionValue = nil, nil

    local function reset()
        outstanding, nonce, generation, targetSeen, sessionSeen = false, nil, nil, false, false
        targetValue, sessionValue = nil, nil
    end

    -- A grant has only one scalar slot.  `x4gc1:<nonce>:<generation>` keeps
    -- the client request identity and MD-owned lease separate without relying
    -- on a Lua table surviving the MD -> Lua event boundary.  Nonces are
    -- decimal and module-scoped so a UI reload that preserves this global does
    -- not immediately reuse a request identity.
    local function allocateNonce()
        local nextNonce = (Persistence._nextClientNonce or 0) + 1
        if nextNonce > 2147483647 then nextNonce = 1 end
        Persistence._nextClientNonce = nextNonce
        return tostring(nextNonce)
    end

    local function parseGrant(value)
        if type(value) ~= "string" then return nil end
        local grantedNonce, grantedGeneration = string.match(value, "^x4gc1:([1-9][0-9]*):([1-9][0-9]*)$")
        if not grantedNonce or not grantedGeneration then return nil end
        local numericGeneration = tonumber(grantedGeneration)
        if not numericGeneration or numericGeneration ~= math.floor(numericGeneration)
            or numericGeneration > 2147483647 then return nil end
        return grantedNonce, numericGeneration
    end

    local function complete()
        if not outstanding or not targetSeen or not sessionSeen then return end
        local envelope = { generation = generation, target = targetValue, payload = sessionValue }
        reset()
        deps.onEnvelope(envelope)
    end

    local function receiveTarget(expectedNonce, expectedGeneration, _, value)
        if not outstanding or nonce ~= expectedNonce or generation ~= expectedGeneration or targetSeen then return end
        targetSeen = true
        -- MD deliberately sends 0 when no component survived, rather than
        -- omitting this half of the protocol.
        targetValue = value
        complete()
    end

    local function receiveSession(expectedNonce, expectedGeneration, _, value)
        if not outstanding or nonce ~= expectedNonce or generation ~= expectedGeneration or sessionSeen then return end
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

    function api.request(force)
        if outstanding then
            -- a forced re-request is for when the world changed underneath the
            -- request (a savegame load), so the in-flight request can never be
            -- granted.  reset() rather than clear(): clear() emits session_end,
            -- which makes MD delete State.$active and would destroy the very
            -- payload we are trying to restore.
            if not force then return false end
            reset()
        end
        outstanding = true
        nonce, generation, targetSeen, sessionSeen = allocateNonce(), nil, false, false
        targetValue, sessionValue = nil, nil
        deps.emit("state_request", { nonce = nonce })
        return true
    end

    deps.register("X4GunneryControl.RestoreGrant", function(_, value)
        if not outstanding or generation ~= nil then return end
        local grantedNonce, nextGeneration = parseGrant(value)
        -- Malformed or unrelated static events must not cancel the legitimate
        -- request still waiting for its own grant.
        if not grantedNonce then return end
        -- A delayed grant for a cleared request can carry a generation that
        -- this client has never accepted.  The nonce, rather than generation
        -- ordering, is what prevents it from claiming the newer request.
        if grantedNonce ~= nonce then return end
        if nextGeneration <= lastGeneration then return end
        generation = nextGeneration
        lastGeneration = nextGeneration
        local grantedGeneration = nextGeneration
        local grantedRequestNonce = grantedNonce
        -- These handlers must exist before state_accept: MD can raise both
        -- replies immediately, and raise_lua_event carries one scalar only.
        deps.register("X4GunneryControl.RestoreTarget." .. tostring(grantedGeneration),
            function(name, value) receiveTarget(grantedRequestNonce, grantedGeneration, name, value) end)
        deps.register("X4GunneryControl.RestoreSession." .. tostring(grantedGeneration),
            function(name, value) receiveSession(grantedRequestNonce, grantedGeneration, name, value) end)
        deps.emit("state_accept", { nonce = grantedRequestNonce, generation = grantedGeneration })
    end)

    return api
end

return X4GunneryPersistence
