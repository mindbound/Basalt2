-- Debug module: on-screen log overlay, toggled with a key (default F12).
--
--   basalt.use("debug")
--   basalt.debug("value:", x)   -- log; also dbg.log(...)
--
-- Standalone module: builds its overlay out of ordinary elements on the
-- main frame and watches for its toggle key via a scheduled coroutine.
-- Log lines are shown as written: a "{...}" line is never compiled as a
-- reactive expression, whatever basalt.setReactiveStrings says.

local require = ...
local basalt = require("main")
local reactive = require("core/reactive")

local dbg = {}

local HEIGHT = 8
local lines = {}
local MAX_LINES = 40
local overlay, header, rowLabels
local toggleKey = keys.f12

local function refresh()
    if not overlay or not overlay.visible then return end
    local rows = HEIGHT - 1
    local offset = math.max(0, #lines - rows)
    for i = 1, rows do
        -- logged values are data (often from outside the program)
        rowLabels[i].text = reactive.literal(lines[offset + i] or "")
    end
end

local function ensureOverlay()
    if overlay then return end
    local main = basalt.getMainFrame()
    overlay = main:addFrame({
        x = 1,
        -- functions, not "{...}" strings: those are stored as written while
        -- basalt.setReactiveStrings(false) is in effect
        y = function(self)
            return rawget(self, "parent").height - (HEIGHT - 1)
        end,
        width = function(self) return rawget(self, "parent").width end,
        height = HEIGHT,
        z = 1000,
        visible = false,
        background = colors.black,
        name = "basalt_debug_overlay",
    })
    header = overlay:addLabel({
        x = 2, y = 1,
        text = "Basalt Debug",
        foreground = colors.orange,
    })
    rowLabels = {}
    for i = 1, HEIGHT - 1 do
        rowLabels[i] = overlay:addLabel({
            x = 2, y = i + 1, text = "",
            foreground = colors.lime,
        })
    end
end

--- Logs a message to the overlay (arguments are tostring-ed and joined).
--- Appends a line to the debug overlay log.
---@param ... any Values converted with tostring
function dbg.log(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    lines[#lines + 1] = table.concat(parts, " ")
    if #lines > MAX_LINES then
        table.remove(lines, 1)
    end
    refresh()
end

--- Shows/hides the overlay (nil toggles).
--- Explicitly shows or hides the debug overlay.
---@param state? boolean Visibility; omitted toggles the overlay
function dbg.show(state)
    ensureOverlay()
    if state == nil then state = not overlay.visible end
    overlay.visible = state
    refresh()
end

--- Changes the toggle key (a keys.* constant).
--- Changes the keyboard key used to toggle the overlay.
---@param key number ComputerCraft key code
function dbg.setToggleKey(key)
    toggleKey = key
end

--- Returns the lazily created overlay frame.
---@return Frame overlay
function dbg.getOverlay()
    ensureOverlay()
    return overlay
end

--- Clears all captured debug lines.
---@return nil
function dbg.clear()
    lines = {}
    refresh()
end

ensureOverlay()

-- watch for the toggle key; scheduled coroutines receive all events.
-- Ctrl+T under basalt.run({ onTerminate }) must not end the watcher.
basalt.schedule(function()
    while true do
        ---@diagnostic disable-next-line: undefined-field
        local _, key = os.pullEvent("key")
        if key == toggleKey then
            dbg.show()
        end
    end
end, { ignoreTerminate = true })

-- convenience: basalt.debug(...)
basalt.debug = dbg.log

return dbg
