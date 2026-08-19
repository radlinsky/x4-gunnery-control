-- tests/support/runtime_fixture.lua
--
-- Shared stub environment for the gunnery_control runtime tests.
--
-- Usage (from a top-level tests/*.lua file):
--
--   local fix = dofile("tests/support/runtime_fixture.lua")
--   fix.load()          -- sets up all globals, loads gunnery_control.lua
--   local gcMenu = fix.gcMenu
--   local API    = fix.API
--
-- Every call to fix.load() gives a completely fresh environment — new stubs,
-- new global state, new module load — so test files are independent of each
-- other even when validate.sh runs them in the same process order.
--
-- ── fixture API ─────────────────────────────────────────────────────────────
-- fix.load()                 — (re-)initialise stubs and reload gunnery_control
-- fix.gcMenu                 — the registered X4GunneryMenu object
-- fix.API                    — X4GunneryControlAPI (module test handle)
-- fix.capturedLog            — list of strings passed to DebugError
-- fix.logContains(pattern)   — returns true if capturedLog has a plain match
-- fix.pendingCallbacks       — list of fns enqueued by addDelayedOneTimeCallback
-- fix.callbackCheckpoint()   — mark the current callback queue
-- fix.drainCallbacksSince(mark)
--                           — run only callbacks added after mark and their
--                             descendants, once each, in time order
-- fix.lastFrameProps         — props table of the most-recently-created frame
-- fix.addTableCalls          — addTable call count on the most-recent frame
-- fix.frameCount             — createFrameHandle calls since last clearDataForRefresh
-- fix.frameProps             — { [1]=props, ... } for the current refresh
-- fix.allFrames              — { {props,background}, ... } — every frame ever
-- fix.createdButtons         — { {active,text}, ... } since last clearDataForRefresh
-- fix.createdCheckBoxes      — { {checked,handlers}, ... } since last clearDataForRefresh
-- fix.clearedFrames          — layers passed to Helper.clearFrame since last reset
-- fix.teardownTrace          — ordering trace: "clear<n>" | "close" entries
-- fix.closeMenuCalls         — count of Helper.closeMenu invocations
-- fix.buttonByText(label)    — find a created button by its label
-- fix.C                      — the C metatable stub (mutate to override calls)
-- fix.ffiStub                — the ffi stub (mutate ffiStub.new to override)
-- fix.clock                  — shared time value; assign to advance getElapsedTime
-- fix.fireEvent(name,payload) — fire a RegisterEvent handler recorded during load
-- fix.registeredEvents       — handlers indexed by RegisterEvent name
-- fix.registeredEventCalls   — ordered {name,handler} RegisterEvent captures
-- fix.uiTriggeredEvents      — ordered {screen,control,params} UI-event captures
--
-- ── RegisterEvent / fireEvent ────────────────────────────────────────────────
-- The production code calls RegisterEvent(name, handler) during init. The old
-- stub threw the handler away, meaning onRestoreTarget and similar were never
-- callable from tests. The new stub records every registration keyed by name so
-- tests can fire arbitrary events:
--
--   fix.load()
--   fix.fireEvent("playerGetUp", nil)     -- calls the registered handler
--
-- Multiple registrations for the same name accumulate; fireEvent calls all of
-- them in registration order.
--
-- ── checkpoint-scoped callback scheduler ─────────────────────────────────────
-- addDelayedOneTimeCallbackOnUpdate(fn, _, time) queues {fn, time}. Callbacks
-- with no explicit time get time 0 (run immediately on the next drain). The
-- production code chains camera-gate retries and display() refreshes. Tests mark
-- the queue before the action under test and drain only that action's callbacks
-- and descendants. This deliberately leaves the init watchdog and other earlier
-- recurring work queued, which prevents a test helper from becoming a
-- drain-to-empty loop.
--
-- This is a superset of the old simple list: existing tests that push callbacks
-- and then call them by index still work because pendingCallbacks remains a
-- plain array (entries are added in order, new entries appended).

local M = {}

-- Repo root is the cwd when validate.sh or lua5.1 tests/test_*.lua runs from
-- the project root.  Adjust package.path so require("ffi") can be preloaded
-- without searching the filesystem.  We do not add anything to package.path
-- here because the tests dofile() every Lua file they need by explicit path.
-- The only thing that must be in package.path is the ability to resolve
-- require("ffi") — but that is handled via package.preload below, so
-- package.path is left untouched.

function M.load()
    -- ── 1. fake ffi ─────────────────────────────────────────────────────────
    local ffiStub = {}
    ffiStub.cdef   = function() end
    ffiStub.string = function(p) return tostring(p) end
    ffiStub.new    = function(spec, count) return {} end

    local C = setmetatable({
        -- Explicit stubs for everything reachable from load path, init, and
        -- logSession.  The __index fallback returns a numeric-safe zero stub.
        GetPlayerCurrentControlGroup    = function() return "gunnercontrol" end,
        GetPlayerOccupiedShipID         = function() return 0 end,
        GetPlayerID                     = function() return 1 end,
        GetContextByClass               = function(...) return 42 end,
        IsComponentClass                = function(...) return true end,
        GetExternalTargetViewComponent  = function() return 7 end,
        IsGamePaused                    = function() return false end,
        GetSofttarget2                  = function()
            return { softtargetID = 0, softtargetConnectionName = "" }
        end,
        GetUp                           = function() return true end,
        -- Everything else returns 0 (safe for numeric contexts).
    }, { __index = function(t, k) return function(...) return 0 end end })

    ffiStub.C = C
    package.preload["ffi"] = function() return ffiStub end
    -- Require caches the first fixture's ffi stub process-wide, which would
    -- bind every later module instance to the FIRST fixture's C table and make
    -- fix.C overrides invisible to production code (the fixture contract says
    -- every load is a fresh environment). Drop the cache entry so this load's
    -- require("ffi") returns THIS fixture's stub.
    package.loaded["ffi"] = nil

    -- ── 2. captured log ─────────────────────────────────────────────────────
    local capturedLog = {}
    DebugError = function(msg) capturedLog[#capturedLog + 1] = tostring(msg) end

    local function logContains(pattern)
        for _, line in ipairs(capturedLog) do
            if string.find(line, pattern, 1, true) then return true end
        end
        return false
    end

    -- ── 3. callback scheduler ────────────────────────────────────────────────
    -- addDelayedOneTimeCallbackOnUpdate(fn, _, time) in production schedules
    -- fn to run after `time` seconds. Tests use a queue checkpoint before the
    -- action under test, then drain only the callbacks attributable to it.
    --
    -- pendingCallbacks stays a plain sequential array so direct indexed
    -- inspection keeps working. Each entry is stored as-is (the fn), because
    -- that is what the original tests expected. Scheduling metadata is kept in
    -- a parallel private table so checkpoint draining cannot disturb the public
    -- array layout.
    local pendingCallbacks = {}
    local callbackRecords = {}   -- parallel array: scheduling metadata
    local callbackSequence = 0
    local activeDrain = nil

    local function callbackCheckpoint()
        return callbackSequence
    end

    -- Drain callbacks scheduled after `mark`, including only descendants that
    -- were scheduled by those callbacks. Entries remain in pendingCallbacks so
    -- index-based inspection stays possible, but each record is invoked once.
    -- In particular, the watchdog scheduled during init predates a test mark
    -- and remains queued rather than recursively scheduling itself forever.
    local DRAIN_CAP = 500
    local function drainCallbacksSince(mark)
        assert(type(mark) == "number", "drainCallbacksSince requires a callback checkpoint")
        local iterations = 0
        local oldDrain = activeDrain
        activeDrain = { mark = mark, eligible = false }
        while true do
            local candidate
            for _, record in ipairs(callbackRecords) do
                if not record.ran and (record.sequence > mark or record.descendant) then
                    if not candidate
                        or record.time < candidate.time
                        or (record.time == candidate.time and record.sequence < candidate.sequence) then
                        candidate = record
                    end
                end
            end
            if not candidate then break end
            iterations = iterations + 1
            assert(iterations <= DRAIN_CAP,
                "drainCallbacksSince: hit the " .. DRAIN_CAP .. "-iteration safety cap; "
                .. "a callback is scheduling callbacks in an infinite chain. "
                .. "Increase DRAIN_CAP if your chain is legitimately longer, "
                .. "or fix the production code that is looping.")
            candidate.ran = true
            activeDrain.eligible = true
            candidate.fn()
            activeDrain.eligible = false
        end
        activeDrain = oldDrain
    end

    -- Used only for the one init-smoke watchdog call. It records the execution
    -- so a later checkpoint drain cannot accidentally invoke it a second time.
    local function runCallback(fn)
        for _, record in ipairs(callbackRecords) do
            if record.fn == fn and not record.ran then
                record.ran = true
                break
            end
        end
        return fn()
    end

    -- ── 4. frame / UI bookkeeping ────────────────────────────────────────────
    -- These locals are captured by the Helper stubs below and exposed on the
    -- module table so test files can read (and reset) them.
    local lastFrameProps    = nil
    local addTableCalls     = 0
    local frameCount        = 0
    local frameProps        = {}
    -- Every frame ever created, never reset, as { props, background }.
    -- The HUD-restore contract spans the whole session, so it must survive
    -- clearDataForRefresh.
    local allFrames         = {}
    local createdButtons    = {}
    local createdTexts      = {}
    local createdCheckBoxes = {}
    local createdDropDowns  = {}
    local clearedFrames     = {}
    local closeMenuCalls    = 0
    -- Teardown calls in order: "clear<layer>" / "close". Ordering is the whole
    -- point: helper.lua untracks the menu before unregistering its views.
    local teardownTrace     = {}

    -- Expose the mutable bookkeeping on the module so test code can do
    --   fix.clearedFrames = {}  (reset)  or  #fix.pendingCallbacks  (read).
    -- We use a helper to keep the field references in sync after load().
    -- (These are set at the end of load() once all locals are defined.)

    local function buttonByText(label)
        for _, b in ipairs(createdButtons) do
            if b.text == label then return b end
        end
    end

    -- ── 5. RegisterEvent stub (records + allows fireEvent) ───────────────────
    -- The original stub was `RegisterEvent = function() end`, which threw every
    -- registered handler away.  This stub records them so tests can fire events
    -- through fix.fireEvent(name, payload).
    local registeredEvents = {}   -- { [name] = { handler, ... } }
    local registeredEventCalls = {}
    local registeredUIEvents = {}
    RegisterEvent = function(name, handler)
        if not registeredEvents[name] then registeredEvents[name] = {} end
        registeredEvents[name][#registeredEvents[name] + 1] = handler
        registeredEventCalls[#registeredEventCalls + 1] = { name = name, handler = handler }
    end

    local function fireEvent(name, payload)
        local handlers = registeredEvents[name]
        if not handlers then return end
        for _, h in ipairs(handlers) do h(name, payload) end
    end

    local function fireUIEvent(name, payload)
        for _, handler in ipairs(registeredUIEvents[name] or {}) do handler(name, payload) end
    end

    -- ── 6. Helper stub ───────────────────────────────────────────────────────
    local Helper = {
        registerMenu            = function() end,
        clearDataForRefresh     = function()
            frameCount        = 0
            frameProps        = {}
            createdButtons    = {}
            createdTexts      = {}
            createdCheckBoxes = {}
            createdDropDowns  = {}
        end,
        -- Layers passed to Helper.clearFrame since the test last reset the list.
        clearFrame              = function(m, layer)
            clearedFrames[#clearedFrames + 1] = layer
            teardownTrace[#teardownTrace + 1] = "clear" .. tostring(layer)
            if m and m.frames then m.frames[layer] = nil end
        end,
        createFrameHandle       = function(menu, props)
            lastFrameProps = props
            addTableCalls  = 0
            frameCount     = frameCount + 1
            frameProps[frameCount] = props
            local record = { props = props, background = false }
            allFrames[#allFrames + 1] = record
            local frame
            frame = {
                display    = function() end,
                update     = function() end,
                setBackground = function(self)
                    record.background = true
                    return self
                end,
                properties = setmetatable({}, {
                    __newindex = function(t, k, v) rawset(t, k, v) end,
                    __index    = function() return 0 end,
                }),
                addTable   = function()
                    addTableCalls = addTableCalls + 1
                    return {
                        addRow = function(_, rowID)
                            local row = {}
                            return setmetatable(row, {
                                -- Cache each cell. Production assigns handlers
                                -- after createButton(), and retaining that same
                                -- cell lets runtime tests exercise the actual
                                -- click callback instead of a copied closure.
                                __index = function(t, column)
                                    local cell = { handlers = {} }
                                    cell.setColSpan = function() return cell end
                                    cell.createText = function(_, label)
                                        createdTexts[#createdTexts + 1] = {
                                            row = rowID, column = column, text = label,
                                        }
                                    end
                                    cell.createButton = function(_, bprops)
                                        local entry = {
                                            active = (bprops or {}).active,
                                            handlers = cell.handlers,
                                            row = rowID,
                                            column = column,
                                        }
                                        createdButtons[#createdButtons + 1] = entry
                                        return {
                                            setText = function(_, label)
                                                entry.text = label
                                            end,
                                        }
                                    end
                                    cell.createCheckBox = function(_, checked)
                                        createdCheckBoxes[#createdCheckBoxes + 1] = {
                                            checked = checked,
                                            handlers = cell.handlers,
                                            row = rowID,
                                            column = column,
                                        }
                                    end
                                    cell.createDropDown = function(_, options, props)
                                        createdDropDowns[#createdDropDowns + 1] = {
                                            handlers = cell.handlers,
                                            row = rowID,
                                            column = column,
                                            options = options,
                                            startOption = (props or {}).startOption,
                                            mouseOverText = (props or {}).mouseOverText,
                                        }
                                    end
                                    rawset(t, column, cell)
                                    return cell
                                end,
                            })
                        end,
                        getVisibleHeight = function() return 0 end,
                        properties       = setmetatable({}, {
                            __index = function() return 0 end,
                        }),
                    }
                end,
            }
            -- helper.lua keys menu.frames by layer; unregisterOwnFrames() walks it.
            menu.frames = menu.frames or {}
            -- helper.lua defaults an omitted layer to Helper.defaultFrameLayer (4).
            menu.frames[props.layer or 4] = frame
            return frame
        end,
        -- Counts Helper.closeMenu calls; the get-up path must defer that one tick.
        closeMenu               = function(m)
            closeMenuCalls = closeMenuCalls + 1
            teardownTrace[#teardownTrace + 1] = "close"
            -- helper.lua's clearMenu() ends with menu.frames = {}.
            if m then m.frames = {} end
        end,
        getMenu                 = function() return nil end,
        closeMenuAndOpenNewMenu = function() end,
        scaleX                  = function(x) return x end,
        scaleY                  = function(y) return y end,
        viewWidth               = 1920,
        viewHeight              = 1080,
        borderSize              = 4,
        headerRowCenteredProperties = {},
        addDelayedOneTimeCallbackOnUpdate = function(fn, _, time)
            callbackSequence = callbackSequence + 1
            pendingCallbacks[#pendingCallbacks + 1] = fn
            callbackRecords[#callbackRecords + 1] = {
                fn = fn,
                time = time or 0,
                sequence = callbackSequence,
                descendant = activeDrain and activeDrain.eligible or false,
                ran = false,
            }
        end,
    }
    _G.Helper = Helper

    -- ── 7. other required globals ────────────────────────────────────────────
    Menus               = {}
    ReadText            = function(page, id)
        return "text:" .. tostring(page) .. ":" .. tostring(id)
    end
    -- Realistic vanilla dropdown surface: the shipped 9.00 Helper defines
    -- Helper.turretModes (one entry per engine mode, with the game-localized
    -- option text) and Helper.getTurretModes(turret, forall, helpoverlayprefix)
    -- filters that list by engine compatibility. Mirror both so the option-list
    -- tests consume the same shapes production does. (ui/addons/
    -- ego_detailmonitorhelper/helper.lua)
    Helper.turretModes = {
        { id = "defend",          text = ReadText(1001, 8613), icon = "", displayremoveoption = false, forall = true },
        { id = "attackenemies",   text = ReadText(1001, 8614), icon = "", displayremoveoption = false, forall = true },
        { id = "attackcapital",   text = ReadText(1001, 8634), icon = "", displayremoveoption = false, forall = true },
        { id = "prefercapital",   text = ReadText(1001, 8637), icon = "", displayremoveoption = false, forall = true },
        { id = "attackfighters",  text = ReadText(1001, 8635), icon = "", displayremoveoption = false, forall = true },
        { id = "preferfighters",  text = ReadText(1001, 8638), icon = "", displayremoveoption = false, forall = true },
        { id = "missiledefence",  text = ReadText(1001, 8636), icon = "", displayremoveoption = false, forall = true },
        { id = "prefermissiles",  text = ReadText(1001, 8639), icon = "", displayremoveoption = false, forall = true },
        { id = "autoassist",      text = ReadText(1001, 8617), icon = "", displayremoveoption = false, forall = true },
        { id = "mining",          text = ReadText(1001, 8616), icon = "", displayremoveoption = false, forall = true },
        { id = "towing",          text = ReadText(1001, 8633), icon = "", displayremoveoption = false, forall = false },
    }
    Helper.getTurretModes = function(turret, forall, helpoverlayprefix, counter)
        local options = {}
        for _, entry in ipairs(Helper.turretModes) do
            if (not forall) or (forall == entry.forall) then
                if (turret == nil) or C.IsWeaponModeCompatible(turret, "", entry.id) then
                    local copy = {
                        id = entry.id, text = entry.text, icon = entry.icon,
                        displayremoveoption = entry.displayremoveoption, forall = entry.forall,
                    }
                    if helpoverlayprefix then
                        copy.helpOverlayID = helpoverlayprefix .. entry.id .. (counter or "")
                        copy.helpOverlayText = " "
                        copy.helpOverlayHighlightOnly = true
                    end
                    options[#options + 1] = copy
                end
            end
        end
        return options
    end
    -- RegisterEvent is set above (section 5).
    registerForEvent    = function(name, _, handler)
        registeredUIEvents[name] = registeredUIEvents[name] or {}
        registeredUIEvents[name][#registeredUIEvents[name] + 1] = handler
    end
    getElement          = function() return {} end
    local uiTriggeredEvents = {}
    AddUITriggeredEvent = function(screen, control, params)
        uiTriggeredEvents[#uiTriggeredEvents + 1] = {
            screen = screen, control = control, params = params,
        }
    end
    ConvertStringTo64Bit   = function(v) return tonumber(v) or 0 end
    ConvertStringToLuaID   = function(v) return tonumber(v) or 0 end
    GetCurRealTime         = function() return 0 end
    getElapsedTime         = function() return 0 end
    Color                  = setmetatable({}, { __index = function() return {} end })
    Font                   = setmetatable({}, { __index = function() return "" end })
    SetSofttarget          = function() return true end
    OpenMenu               = function() end
    GetComponentData       = function() return nil end
    GetMacroData           = function() return "" end
    GetPlayerContextByClass = function() return nil end
    GetContainedShips      = function() return {} end
    GetContainedStations   = function() return {} end
    RemoveSofttarget       = function() end

    -- X4GunneryState must be set before gunnery_control.lua loads
    -- (line 5: local State = X4GunneryState).
    dofile("ui/turret_arc_limits.lua")
    X4GunneryState = dofile("ui/gunnery_state.lua")
    X4GunneryPersistence = dofile("ui/gunnery_persistence.lua")
    -- The control module deliberately reuses this table in game across a UI
    -- reload. A fixture load promises a fresh environment instead, so discard
    -- the previous test's closures before loading the next module instance.
    X4GunneryControlAPI = nil

    -- ── 8. load the module ───────────────────────────────────────────────────
    -- init() is called at the bottom of the file, so this exercises the full
    -- startup path including logSession calls.
    local ok, err = pcall(dofile, "ui/gunnery_control.lua")
    assert(ok, "gunnery_control.lua failed to load: " .. tostring(err))

    -- ── 9. locate the registered menu ───────────────────────────────────────
    local gcMenu
    for _, m in ipairs(Menus) do
        if m.name == "X4GunneryMenu" then gcMenu = m; break end
    end
    assert(gcMenu, "X4GunneryMenu was not registered in Menus after init()")

    local API = X4GunneryControlAPI

    -- ── 10. expose everything on the module table ────────────────────────────
    -- Use a shared `clock` number so test files can write  fix.clock = x  and
    -- then swap getElapsedTime to read it.
    local clock = 0

    -- Expose the mutable locals via getter/setter pairs on the table so that
    -- test code can both read and reset them.  For tables we expose the
    -- reference directly; the test reassigns fix.clearedFrames = {} etc.
    --
    -- Note: because Lua closes over the *variable*, not the value, reading
    -- fix.lastFrameProps always gives the current value of the local.  But the
    -- test cannot *write* to the local through a simple table field.  We work
    -- around this with a metatable that intercepts writes for the mutable scalars.
    local exposed = {
        gcMenu            = gcMenu,
        API               = API,
        C                 = C,
        ffiStub           = ffiStub,
        logContains       = logContains,
        buttonByText      = buttonByText,
        fireEvent         = fireEvent,
        fireUIEvent       = fireUIEvent,
        callbackCheckpoint = callbackCheckpoint,
        drainCallbacksSince = drainCallbacksSince,
        runCallback       = runCallback,
        -- tables (reference — mutations visible both ways)
        pendingCallbacks  = pendingCallbacks,
        registeredEvents  = registeredEvents,
        registeredEventCalls = registeredEventCalls,
        registeredUIEvents = registeredUIEvents,
        uiTriggeredEvents = uiTriggeredEvents,
        allFrames         = allFrames,
        -- scalars that tests only READ (not write) can be proxied via __index
        -- clock is a special case: tests write to it, so we keep it as a plain field
        clock             = clock,
    }

    -- For the mutable scalar bookkeeping (lastFrameProps, addTableCalls, etc.),
    -- we expose them through __index/__newindex on the module so that reading
    -- fix.lastFrameProps returns the local's current value, and writing
    -- fix.clearedFrames = {} resets the *local* so the Helper closures see it.
    --
    -- However, Lua closures cannot reassign upvalues from outside (no upvalue
    -- write across module boundaries).  The practical solution: expose a
    -- `reset` function for each mutable table, and expose the scalars purely
    -- for reading (test code already does not write to lastFrameProps etc.).
    exposed.resetClearedFrames   = function() clearedFrames = {} end
    exposed.resetTeardownTrace   = function() teardownTrace = {} end
    exposed.resetCloseMenuCalls  = function() closeMenuCalls = 0 end
    exposed.resetLastFrameProps  = function() lastFrameProps = nil end

    -- Scalar readers (functions, not values, so they always return current data).
    exposed.getLastFrameProps    = function() return lastFrameProps end
    exposed.getAddTableCalls     = function() return addTableCalls end
    exposed.getFrameCount        = function() return frameCount end
    exposed.getFrameProps        = function() return frameProps end
    exposed.getCreatedButtons    = function() return createdButtons end
    exposed.getCreatedTexts      = function() return createdTexts end
    exposed.getCreatedCheckBoxes = function() return createdCheckBoxes end
    exposed.getCreatedDropDowns  = function() return createdDropDowns end
    exposed.getClearedFrames     = function() return clearedFrames end
    exposed.getTeardownTrace     = function() return teardownTrace end
    exposed.getCloseMenuCalls    = function() return closeMenuCalls end
    exposed.getCapturedLog       = function() return capturedLog end
    exposed.resetUITriggeredEvents = function()
        for i = #uiTriggeredEvents, 1, -1 do uiTriggeredEvents[i] = nil end
    end

    return exposed
end

return M
