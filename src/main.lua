local require = ...
if type(require) ~= "function" then
    local name, path = ...
    local initPath = fs.combine(fs.getDir(path or "basalt/main.lua"), "init.lua")
    return assert(loadfile(initPath, nil, _ENV))(name, initPath)
end
local errors = require("core/errors")
local palette = require("core/palette")
local reactive = require("core/reactive")
local state = require("core/state")
local layout = require("core/layout")
local Container = require("core/container")
local BaseFrame = require("core/baseframe")

Container.register("Label", require("elements/Label"))
Container.register("Canvas", require("elements/Canvas"))
Container.register("Button", require("elements/Button"))
Container.register("Frame", require("elements/Frame"))
Container.register("Input", require("elements/Input"))
Container.register("Checkbox", require("elements/Checkbox"))
Container.register("Switch", require("elements/Switch"))
Container.register("ProgressBar", require("elements/ProgressBar"))
Container.register("Slider", require("elements/Slider"))
Container.register("Collection", require("elements/Collection"))
Container.register("List", require("elements/List"))
Container.register("Dropdown", require("elements/Dropdown"))
Container.register("Flex", require("elements/Flex"))
Container.register("Row", require("elements/Row"))
Container.register("Column", require("elements/Column"))
Container.register("TextBox", require("elements/TextBox"))
Container.register("Menu", require("elements/Menu"))
Container.register("TabControl", require("elements/TabControl"))
Container.register("Tree", require("elements/Tree"))
Container.register("Table", require("elements/Table"))
Container.register("Program", require("elements/Program"))
Container.register("ComboBox", require("elements/ComboBox"))
Container.register("ContextMenu", require("elements/ContextMenu"))
Container.register("Dialog", require("elements/Dialog"))
Container.register("Toast", require("elements/Toast"))

---@class BasaltRunOptions
---@field onTerminate? fun() Called on Ctrl+T instead of ending the loop

---@class BasaltScheduleOptions
---@field ignoreTerminate? boolean True: the terminate event never reaches the coroutine

---@class basalt
---@field VERSION string Current Basalt version
---@field traceback boolean Whether error screens include the Lua traceback
---@field errors table Error parsing and display utilities
---@field rgb fun(value: string|number, g?: number, b?: number): number RGB color helper
---@field state fun(initialValue: any): Signal Creates writable reactive state
---@field signal fun(initialValue: any): Signal Alias for `state`
---@field computed fun(fn: fun(): any): Computed Creates a computed reactive value
---@field isState fun(value: any): boolean Tests whether a value is reactive state
---@field auto fun(): LayoutValue Creates an intrinsic-size layout value
---@field fill fun(weight?: number): LayoutValue Creates a weighted fill layout value
---@field percent fun(amount: number): LayoutValue Creates a fractional parent-size value
---@field debug? fun(...: any) Logger installed by `basalt.use("debug")`
---@field text table Screen-cell text helpers (width, sub, wrap, ...); UTF-8 aware with the Unicode Support mod
local basalt = {}
basalt.VERSION = "2.5.0-dev"
basalt.traceback = true
basalt.errors = errors

--- Text helpers that measure and cut in screen cells. Use them instead of
--- `#` and string.sub for text you draw: with the "CC: Tweaked Unicode
--- Support" mod a cell can be a multi-byte UTF-8 character (see core/text).
basalt.text = require("core/text")

--- Registers a custom RGB color; returns a handle usable like a colors.*
--- value. Accepts "#RRGGBB", "#RGB", "#AARRGGBB", 0xRRGGBB or r,g,b.
basalt.rgb = palette.rgb

--- Creates writable application state. Signals can be assigned directly to
--- element properties and automatically invalidate their dependent UI trees.
basalt.state = state.create
basalt.signal = state.create

--- Creates a lazily evaluated value that tracks any signals read inside it.
basalt.computed = state.computed
basalt.isState = state.is

--- Responsive layout values for element width/height properties.
basalt.auto = layout.auto
basalt.fill = layout.fill
basalt.percent = layout.percent

--- Turns reactive strings on or off for this Basalt instance (default: on).
--- On, a string that starts with "{" and ends with "}" is compiled as a Lua
--- expression when it is assigned to a property (except rawString
--- properties such as Input.text and TextBox.text); the expression can use
--- self, parent, every named element, math, colors and rgb. Text from
--- outside the program (files, network, chat, AI output) must never be
--- compiled: a string like '{"a":1}' fails to compile and "{self:destroy()}"
--- runs. Off, every assigned string is stored as written; values compiled
--- before stay dynamic. XML layouts (the xml module) are written by the
--- app author, so their "{...}" values stay reactive. theme.apply values
--- are assigned like any other value and follow this switch. In both
--- modes, text that Basalt shows from method arguments is never compiled:
--- Dialog titles and messages, Toast messages, debug log lines and
--- collection items (List, Dropdown, Table, Tree, Menu) are shown as
--- written (earlier versions compiled a "{...}" Dialog title or Toast
--- message). To keep reactive strings on and store one value as written,
--- use basalt.literal.
---@param enabled boolean false stores "{...}" strings as written
---@usage basalt.setReactiveStrings(false)
function basalt.setReactiveStrings(enabled)
    if type(enabled) ~= "boolean" then
        error("Basalt: setReactiveStrings expects a boolean", 2)
    end
    reactive.setEnabled(enabled)
end

--- Returns whether reactive strings are on (see basalt.setReactiveStrings).
---@return boolean enabled
function basalt.getReactiveStrings()
    return reactive.isEnabled()
end

--- Marks one string to be stored as written even while reactive strings
--- are on. The marker works wherever a property value is given: plain
--- assignment, setters (setText), props tables (addLabel({ text = ... })),
--- state styles, theme values and values of signals (basalt.state); the
--- property then holds the plain string. Values that are not strings are
--- returned unchanged. Text given to element methods needs no marker:
--- Dialog titles and messages (alert, confirm, prompt), Toast messages
--- (show, success, ...), debug log lines (basalt.debug) and List,
--- Dropdown and Menu items are always shown as written, and a marker
--- given there shows its string too.
---@param value any Text from outside the program
---@return ReactiveLiteral|any marker A literal marker, or value when it is not a string
---@usage label.text = basalt.literal(response)
function basalt.literal(value)
    return reactive.literal(value)
end

--- Loads an optional module from modules/ (e.g. "debug", "animation",
--- "theme", "xml") and returns its API. Modules extend Basalt from the
--- outside; the core has no knowledge of them.
---@param moduleName string The module name
---@return table api The module's API table
---@usage local theme = basalt.use("theme")
function basalt.use(moduleName)
    return require("modules/" .. moduleName)
end

local frames = {}
local mainFrame = nil
local running = false
local schedules = {}
-- options.onTerminate of the active basalt.run(); nil without one
local onTerminate = nil

--- Creates a root frame bound to a terminal (default: current term).
--- For monitors, pass the wrapped peripheral; touch events are routed
--- automatically. monitorName only needs to be given if auto-detection fails.
---@param t? table The terminal to bind to (default: current term)
---@param monitorName? string The name of the monitor peripheral
---@return BaseFrame frame
function basalt.createFrame(t, monitorName)
    t = t or term.current()
    local f = BaseFrame.new()
    f:setTerm(t)
    if monitorName == nil and t.setTextScale and peripheral then
        local ok, name = pcall(peripheral.getName, t)
        if ok then monitorName = name end
    end
    rawset(f, "monitor", monitorName)
    frames[#frames + 1] = f
    if not mainFrame then mainFrame = f end
    return f
end

--- Returns the first frame created by basalt.createFrame(), creating one if needed.
---@return BaseFrame frame
function basalt.getMainFrame()
    return mainFrame or basalt.createFrame()
end

--- Runs a function in a coroutine driven by the event loop; blocking calls
--- like sleep() are allowed inside. While basalt.run({ onTerminate = fn })
--- runs, Ctrl+T reaches every scheduled coroutine, whatever event it waits
--- for, and ends one that waits in sleep(), os.pullEvent or an http call
--- (see basalt.run). options.ignoreTerminate = true keeps the terminate
--- event away from the coroutine, for background work that Ctrl+T must not
--- end (a clock, a poller).
---@param fn function The function to run
---@param options? BasaltScheduleOptions Coroutine options
---@return thread co The coroutine handle
---@usage basalt.schedule(function() sleep(1) label.text = "later" end)
function basalt.schedule(fn, options)
    if options ~= nil and type(options) ~= "table" then
        error("Basalt: schedule options must be a table", 2)
    end
    local co = coroutine.create(fn)
    local ok, filter = coroutine.resume(co)
    if not ok then
        error(errors.wrap(filter, debug.traceback(co)), 0)
    end
    schedules[#schedules + 1] = {
        co = co,
        filter = filter,
        ignoreTerminate = options ~= nil and options.ignoreTerminate == true,
    }
    return co
end

---@param err any
---@return boolean terminated
local function isTerminationError(err)
    -- os.pullEvent raises "Terminated" when it gets the terminate event
    local message = tostring(err)
    return message == "Terminated" or message:match(": Terminated$") ~= nil
end

local function resumeSchedules(event, ...)
    local terminate = event == "terminate"
    -- with run's onTerminate, terminate reaches every coroutine whatever
    -- its filter (as with the parallel API), and one it ends goes quietly
    local cancel = terminate and onTerminate ~= nil
    for i = #schedules, 1, -1 do
        local s = schedules[i]
        if coroutine.status(s.co) == "suspended"
            and not (terminate and s.ignoreTerminate)
            and (s.filter == nil or s.filter == event or cancel) then
            local ok, filter = coroutine.resume(s.co, event, ...)
            if ok then
                s.filter = filter
            elseif not (cancel and isTerminationError(filter)) then
                -- capture the coroutine's stack before it is lost
                error(errors.wrap(filter, debug.traceback(s.co)), 0)
            end
        end
        if coroutine.status(s.co) == "dead" then
            table.remove(schedules, i)
        end
    end
end

local MOUSE = {
    mouse_click = true,
    mouse_up = true,
    mouse_drag = true,
    mouse_scroll = true,
    mouse_move = true,
}
local KEY = { key = true, key_up = true, char = true, paste = true }

-- Ctrl+T is keyboard input: the main frame's focused element can take it
-- with handleTerminate() (see Element:handleTerminate; Program does while
-- it runs a program).
---@return boolean taken
local function focusedTakesTerminate()
    local focused = mainFrame and mainFrame:getFocused()
    if focused and focused ~= mainFrame then
        return focused:handleTerminate() == true
    end
    return false
end

local function dispatch(event, a, b, c, ...)
    if event == "terminate" then
        for i = 1, #frames do
            frames[i]:handleEvent(event, a, b, c, ...)
        end
        if focusedTakesTerminate() then return end
        resumeSchedules(event, a, b, c, ...)
        if onTerminate then onTerminate() end
        return
    elseif event == "mouse_move" and type(a) == "string" then
        for i = 1, #frames do
            local f = frames[i]
            if rawget(f, "monitor") == a then
                f:handleEvent(event, b, c)
            end
        end
    elseif MOUSE[event] or KEY[event] then
        if mainFrame then mainFrame:handleEvent(event, a, b, c, ...) end
    elseif event == "monitor_touch" or event == "monitor_resize" then
        for i = 1, #frames do
            local f = frames[i]
            if rawget(f, "monitor") == a then
                if event == "monitor_touch" then
                    f:handleEvent("mouse_click", 1, b, c)
                    f:handleEvent("mouse_up", 1, b, c)
                else
                    f:handleEvent("term_resize")
                end
            end
        end
    else
        for i = 1, #frames do
            frames[i]:handleEvent(event, a, b, c, ...)
        end
    end
    resumeSchedules(event, a, b, c, ...)
end

local function draw()
    for i = 1, #frames do
        frames[i]:draw()
    end
end

--- Feeds a single event through Basalt manually (alternative to run()).
--- "terminate" ends nothing here: the frames get it, a focused element can
--- take it (see Element:handleTerminate; a Program running a program
--- passes it to that program), and otherwise the scheduled coroutines that
--- wait for any event (or for "terminate") get it; one of them that ends
--- with "Terminated" raises like any other error. While
--- basalt.run({ onTerminate = fn }) runs, it acts exactly like Ctrl+T.
---@param event string The event name (e.g. "mouse_click", "key", "term_resize")
---@param ... any Additional event arguments
function basalt.update(event, ...)
    if event then dispatch(event, ...) end
    draw()
end

--- Stops the active basalt.run() event loop after the current event.
function basalt.stop()
    running = false
end

local function cleanup()
    for i = 1, #frames do
        frames[i]:cleanup()
    end
end

-- A terminal may change size while no loop runs (between two
-- basalt.run() calls): window.reposition queues no term_resize, and
-- read() or sleep() between the runs drop the event. A frame whose render
-- buffer no longer matches its terminal is resized and laid out again.
local function syncFrameSizes()
    for i = 1, #frames do
        local f = frames[i]
        local r = rawget(f, "_render")
        local w, h = rawget(f, "term").getSize()
        if w ~= r.width or h ~= r.height then
            f:handleEvent("term_resize")
        end
    end
end

--- Starts the event loop; returns when basalt.stop() is called, on Ctrl+T
--- (the terminate event) or on error (after showing the error screen).
--- Frames take their terminal's current size when the loop starts, also
--- when it changed while no loop ran.
---
--- With options.onTerminate, Ctrl+T does not end the loop, so an app can
--- use it to cancel work. The event goes to the frames like any other
--- event. If the focused element takes it (see Element:handleTerminate; a
--- Program running a program does), nothing else sees it, as multishell
--- gives Ctrl+T to the focused tab only. Otherwise every scheduled
--- coroutine gets it, whatever event it waits for (as with the parallel
--- API): one in sleep(), os.pullEvent or an http call ends with
--- "Terminated" and is removed quietly, and options from basalt.schedule
--- can keep it away (ignoreTerminate). Basalt's own scheduled work
--- (animations, Toast auto-hide, Image:play, the debug overlay key) keeps
--- running. Then onTerminate() runs. The loop goes on until
--- basalt.stop(). Errors in onTerminate show the error screen.
---@param options? BasaltRunOptions Event-loop options
---@usage basalt.run({ onTerminate = function() status.text = "Cancelled" end })
function basalt.run(options)
    if running then error("Basalt is already running", 2) end
    if options ~= nil and type(options) ~= "table" then
        error("Basalt: run options must be a table", 2)
    end
    local handler = options and options.onTerminate
    if handler ~= nil and type(handler) ~= "function" then
        error("Basalt: run option onTerminate must be a function", 2)
    end
    running = true
    onTerminate = handler

    local ok, err = xpcall(function()
        syncFrameSizes()
        draw()
        while running do
            ---@diagnostic disable-next-line: undefined-field
            local ev = table.pack(os.pullEventRaw())
            if ev[1] == "terminate" and not onTerminate then
                running = false
            else
                dispatch(table.unpack(ev, 1, ev.n))
                draw()
            end
        end
    end, function(e)
        if type(e) == "table" and e.__basaltError then return e end
        return errors.wrap(e, debug.traceback(nil, 2))
    end)

    running = false
    onTerminate = nil
    cleanup()
    if not ok then
        ---@cast err BasaltWrappedError
        errors.show(err.err, err.trace, basalt.traceback)
    end
end

return basalt
