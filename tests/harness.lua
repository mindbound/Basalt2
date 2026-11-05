-- tests/harness.lua
-- A tiny test framework for Basalt's headless test suite (see tests/run.lua).

local T = { passed = 0, failed = 0, known = 0, failures = {}, log = {} }

-- Set by tests/run.lua: the repository root and the source tree
T.root = nil
T.src = nil

function T.print(msg)
    T.log[#T.log + 1] = msg
end

--- Runs one named test; a failure is recorded and the suite goes on.
---@param name string Test name
---@param fn function Test body
function T.test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        T.passed = T.passed + 1
        T.print("  ok   " .. name)
    else
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = name .. ": " .. tostring(err)
        T.print("  FAIL " .. name .. ": " .. tostring(err))
    end
end

--- A test for a known bug that is not fixed yet: its failure is reported
--- but does not fail the run. When it starts passing, the run says so, and
--- the test should become a T.test.
---@param name string Test name
---@param note string What the bug is
---@param fn function Test body (asserts the correct behaviour)
function T.knownBug(name, note, fn)
    local ok = pcall(fn)
    if ok then
        T.passed = T.passed + 1
        T.print("  ok   " .. name .. " (known bug now passes: make it a T.test)")
    else
        T.known = T.known + 1
        T.print("  bug  " .. name .. ": " .. note)
    end
end

local function show(value)
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end

function T.eq(actual, expected, msg)
    if actual ~= expected then
        error((msg and (msg .. ": ") or "") .. "expected " .. show(expected)
            .. ", got " .. show(actual), 2)
    end
end

function T.ok(value, msg)
    if not value then
        error(msg or "expected a truthy value", 2)
    end
    return value
end

function T.contains(str, part, msg)
    if type(str) ~= "string" or not str:find(part, 1, true) then
        error((msg and (msg .. ": ") or "") .. "expected " .. show(str)
            .. " to contain " .. show(part), 2)
    end
end

--- Expects fn to raise; optionally checks that the message contains part.
function T.raises(fn, part)
    local ok, err = pcall(fn)
    if ok then error("expected an error", 2) end
    if part then T.contains(tostring(err), part, "error message") end
    return err
end

--- Loads a fresh Basalt from the source tree. Every call gives a separate
--- instance with its own module cache, so suites never share state.
---@return table basalt
function T.loadBasalt()
    local initPath = T.src .. "/init.lua"
    return assert(loadfile(initPath, nil, _ENV))("basalt", initPath)
end

--- A hidden window on the current terminal.
---@param width? integer Window width (default 51)
---@param height? integer Window height (default 19)
---@return table window
function T.window(width, height)
    return window.create(term.current(), 1, 1, width or 51, height or 19, false)
end

--- A fresh Basalt with a root frame on a hidden window.
---@param width? integer Window width (default 51)
---@param height? integer Window height (default 19)
---@return table basalt, table frame, table window
function T.frame(width, height)
    local basalt = T.loadBasalt()
    local win = T.window(width, height)
    local frame = basalt.createFrame(win)
    return basalt, frame, win
end

--- A mouse click at terminal coordinates: mouse_click, then mouse_up.
---@param basalt table Basalt instance
---@param x integer Terminal x
---@param y integer Terminal y
---@param button? integer Mouse button (default 1)
function T.click(basalt, x, y, button)
    basalt.update("mouse_click", button or 1, x, y)
    basalt.update("mouse_up", button or 1, x, y)
end

--- Types a string: one char event per byte.
---@param basalt table Basalt instance
---@param str string Text to type
function T.type(basalt, str)
    for ch in str:gmatch(".") do basalt.update("char", ch) end
end

local function cellColour(win, x, y, plane)
    local line = select(plane, win.getLine(y))
    return 2 ^ tonumber(line:sub(x, x), 16)
end

--- The foreground colour (a colors.* value) of one window cell.
function T.fg(win, x, y)
    return cellColour(win, x, y, 2)
end

--- The background colour (a colors.* value) of one window cell.
function T.bg(win, x, y)
    return cellColour(win, x, y, 3)
end

--- Pumps real events (timers etc.) into basalt.update until cond() is
--- true or timeout seconds of wall time pass. Returns cond()'s last value.
---@param basalt table Basalt instance
---@param cond fun(): any Condition
---@param timeout? number Seconds (default 5)
---@return any
function T.waitFor(basalt, cond, timeout)
    local deadline = os.epoch("utc") + (timeout or 5) * 1000
    while not cond() and os.epoch("utc") < deadline do
        os.startTimer(0.05)
        local ev = table.pack(os.pullEventRaw())
        if ev[1] ~= "terminate" then
            basalt.update(table.unpack(ev, 1, ev.n))
        end
    end
    return cond()
end

--- Runs fn(escapeCode) with keys.escape available. CraftOS-PC's legacy
--- keys API has no escape entry (code 1 is unnamed); CC:Tweaked has
--- keys.escape = 256. A stand-in is installed for the call and removed.
---@param fn fun(escape: integer)
function T.withEscape(fn)
    if keys.escape then return fn(keys.escape) end
    keys.escape = 1
    local ok, err = pcall(fn, 1)
    keys.escape = nil
    if not ok then error(err, 0) end
end

T.tmpDir = "/basalt-test-tmp"

--- A scratch file path under T.tmpDir; writes content when given.
---@param name string File name
---@param content? string File content
---@return string path
function T.tmpFile(name, content)
    local path = "/" .. fs.combine(T.tmpDir, name)
    if not fs.exists(T.tmpDir) then fs.makeDir(T.tmpDir) end
    if content then
        local h = fs.open(path, "w")
        h.write(content)
        h.close()
    end
    return path
end

--- Removes the scratch directory.
function T.cleanTmp()
    if fs.exists(T.tmpDir) then fs.delete(T.tmpDir) end
end

--- The text on a window's screen, one row per line, trailing spaces removed.
---@param win table Window
---@return string
function T.screen(win)
    local _, h = win.getSize()
    local rows = {}
    for y = 1, h do
        rows[y] = (win.getLine(y)):gsub("%s+$", "")
    end
    return table.concat(rows, "\n")
end

--- One row of a window's screen (trailing spaces removed).
function T.row(win, y)
    return ((win.getLine(y)):gsub("%s+$", ""))
end

return T
