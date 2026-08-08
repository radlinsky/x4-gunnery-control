-- Collect executable-line coverage for one stock Lua 5.1 test process.
--
-- Usage:
--   lua5.1 tests/support/coverage_runner.lua OUT TARGET... -- TEST
--
-- The shell checker supplies the executable-line denominator from luac5.1;
-- this runner only records lines the Lua debug hook actually executed.
local output = assert(arg[1], "missing coverage output path")
local targets, separator = {}, nil
for index = 2, #arg do
    if arg[index] == "--" then separator = index; break end
    targets[arg[index]] = true
end
assert(separator and arg[separator + 1] and not arg[separator + 2],
    "usage: coverage_runner.lua OUT TARGET... -- TEST")

local function targetFor(source)
    source = source or ""
    if source:sub(1, 1) == "@" then source = source:sub(2) end
    source = source:gsub("\\", "/")
    if targets[source] then return source end
    for target in pairs(targets) do
        if #source > #target and source:sub(-#target - 1) == "/" .. target then
            return target
        end
    end
end

local covered = {}
local function hook()
    -- A count hook sees instructions attributed to a closing `end` as well as
    -- ordinary source-line transitions. A line hook alone cannot observe those
    -- Lua 5.1 bytecode lines, despite luac correctly listing them as executable.
    local info = debug.getinfo(2, "Sl")
    local target = info and targetFor(info.source)
    if target and info.currentline and info.currentline > 0 then
        covered[target .. ":" .. tostring(info.currentline)] = true
    end
end

local previousHook, previousMask, previousCount = debug.gethook()
debug.sethook(hook, "", 1)
local ok, err = pcall(dofile, arg[separator + 1])
debug.sethook(previousHook, previousMask, previousCount)

local handle = assert(io.open(output, "a"))
for location in pairs(covered) do handle:write(location, "\n") end
handle:close()
if not ok then error(err, 0) end
