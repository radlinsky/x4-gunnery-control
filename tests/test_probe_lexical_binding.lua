-- Executable Lua 5.1 regression for the PR3 probe lexical-binding defect.
--
-- Reproduces the exact forward-declaration / callback / later-local pattern
-- that was pushed at 04dc7bc, then proves the corrected form actually calls
-- the intended handler.
--
-- Run: lua5.1 tests/test_probe_lexical_binding.lua

local passed = 0
local failed = 0

local function check(name, cond)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name)
    end
end

-- ---------------------------------------------------------------------------
-- Shape 1: THE BUG — forward decl + local redeclaration shadows the closure.
-- The closure captures the outer local (nil); the inner 'local function'
-- creates a NEW binding that the closure never sees. Invoking the callback
-- would throw "attempt to call a nil value".
-- ---------------------------------------------------------------------------
do
    local handler  -- forward decl, nil
    local function maker()
        return function(_, value)
            handler("captured", value)  -- closes over OUTER 'handler' — still nil!
        end
    end
    local function handler(a, b)
        -- NEW local; shadows the outer one. Closure above does NOT see this.
    end
    local cb = maker()
    -- The closure's captured 'handler' is the outer variable, which is nil.
    -- We prove this by checking that calling the callback would error.
    local ok, err = pcall(function() cb("dummy", "payload") end)
    check("bug_shape: shadowed handler leaves closure invoking nil (pcall errors)",
          not ok and tostring(err):find("nil value"))
end

-- ---------------------------------------------------------------------------
-- Shape 2: THE FIX — forward decl + bare assignment (no 'local' on redef).
-- The closure captures the outer local; the bare assignment updates that
-- SAME variable, so the closure invokes the intended handler at runtime.
-- ---------------------------------------------------------------------------
do
    local handler  -- forward decl
    local function maker()
        return function(_, value)
            handler("captured", value)  -- closes over OUTER 'handler'
        end
    end
    handler = function(a, b)
        -- Bare assignment: updates the SAME outer local. Closure sees it.
        handler.called_with = a .. ":" .. b
    end
    local cb = maker()
    local called = false
    local captured_arg
    handler = function(a, b)
        called = true
        captured_arg = a .. ":" .. b
    end
    local ok, _ = pcall(function() cb("dummy", "payload") end)
    check("fix_shape: closure invokes assigned handler (pcall succeeds)", ok)
    check("fix_shape: handler receives correct args",
          called and captured_arg == "captured:payload")
end

-- ---------------------------------------------------------------------------
-- Shape 3: ALTERNATE VALID — complete local function defined BEFORE maker.
-- No forward decl needed; the closure captures the already-bound local.
-- ---------------------------------------------------------------------------
do
    local function handler(a, b)
        handler.called_with = a .. ":" .. b
    end
    local function maker()
        return function(_, value)
            handler("captured", value)  -- closes over the local function
        end
    end
    local cb = maker()
    local called = false
    local captured_arg
    handler = function(a, b)
        called = true
        captured_arg = a .. ":" .. b
    end
    local ok, _ = pcall(function() cb("dummy", "payload") end)
    check("alternate_shape: handler-first layout works (pcall succeeds)", ok)
    check("alternate_shape: handler receives correct args",
          called and captured_arg == "captured:payload")
end

-- ---------------------------------------------------------------------------
print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
