-- tests/run.lua
-- Headless test suite for Basalt. Runs in CraftOS-PC, or in-game on a
-- computer WITHOUT the "CC: Tweaked Unicode Support" mod (the suite
-- simulates that mod itself; on a computer with it, run tests/mod-check):
--   basalt/tests/run             all suites (tests/test_*.lua)
--   basalt/tests/run test_text   one suite
-- From Windows: tests/run.ps1. CI: .github/workflows/ci.yml.
-- Results are printed and written to /basalt-test-results.txt.

local args = { ... }
local root = "/" .. fs.getDir(fs.getDir(shell.getRunningProgram()))
local RESULTS = "/basalt-test-results.txt"

local function writeResults(text)
    local out = fs.open(RESULTS, "w")
    out.write(text)
    out.close()
end

if type(unicode) == "table" then
    local msg = "This computer has the Unicode Support mod; the headless suite " ..
        "simulates it and must run without it. Run tests/mod-check instead."
    writeResults("FAILED " .. msg .. "\n")
    printError(msg)
    return
end

local function main()
    local T = assert(loadfile(fs.combine(root, "tests/harness.lua"), nil, _ENV))()
    T.root = root
    T.src = "/" .. fs.combine(root, "src")

    local only = args[1]
    local suites = {}
    for _, path in ipairs(fs.find(fs.combine(root, "tests/test_*.lua"))) do
        local name = fs.getName(path):gsub("%.lua$", "")
        if not only or only == name then
            suites[#suites + 1] = { name = name, path = "/" .. path }
        end
    end
    table.sort(suites, function(a, b) return a.name < b.name end)

    if only and #suites == 0 then
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = "no suite named " .. only
    end

    for _, suite in ipairs(suites) do
        -- Yield between suites, so a long run never hits "Too long without
        -- yielding" in-game
        os.queueEvent("basalt_test_yield")
        os.pullEvent("basalt_test_yield")

        T.print(suite.name)
        local fn, err = loadfile(suite.path, nil, _ENV)
        if not fn then
            T.failed = T.failed + 1
            T.failures[#T.failures + 1] = suite.name .. ": " .. tostring(err)
            T.print("  FAIL load: " .. tostring(err))
        else
            local ok, suiteErr = pcall(function() fn()(T) end)
            if not ok then
                T.failed = T.failed + 1
                T.failures[#T.failures + 1] = suite.name .. ": " .. tostring(suiteErr)
                T.print("  FAIL suite crashed: " .. tostring(suiteErr))
            end
        end
    end

    if T.passed + T.failed == 0 then
        T.failed = 1
        T.failures[#T.failures + 1] = "no tests ran"
    end

    local summary = string.format("%d passed, %d failed", T.passed, T.failed)
    if T.known > 0 then
        summary = summary .. string.format(", %d known bugs", T.known)
    end
    T.print("")
    T.print(summary)
    for _, failure in ipairs(T.failures) do
        T.print("FAILED " .. failure)
    end
    writeResults(table.concat(T.log, "\n") .. "\n")
    return T, summary
end

local ok, T, summary = xpcall(main, debug.traceback)
if not ok then
    -- The runner itself failed (harness or loader): say so in the results
    writeResults("runner crashed: " .. tostring(T) .. "\n")
    printError("runner crashed: " .. tostring(T))
    return
end

term.setTextColour(T.failed == 0 and colours.lime or colours.red)
print(summary)
term.setTextColour(colours.white)
for _, failure in ipairs(T.failures) do
    printError(failure)
end
