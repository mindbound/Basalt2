-- Reactive expressions: "{parent.width - 12}" compiles to a dynamic value.
--
-- A string assigned to a property is compiled when it starts with "{" and
-- ends with "}" (except rawString properties such as Input.text). The
-- expression is Lua code with access to self, parent and every named
-- element, so text that comes from outside the program (files, network,
-- chat, AI output) must not be compiled: turn compiling off for a Basalt
-- instance with basalt.setReactiveStrings(false), or wrap one value in
-- basalt.literal(str) to store it as written.

local require = ...
local palette = require("core/palette")

---@alias ReactiveResolver fun(element?: Element): any

---@class ReactiveHelpers
---@field colors table CC color constants
---@field math table Lua math library
---@field rgb fun(r: number|string, g?: number, b?: number): number RGB color helper
---@field tostring fun(value: any): string
---@field tonumber fun(value: any, base?: integer): number|nil
---@field clamp fun(value: number, minimum: number, maximum: number): number
---@field round fun(value: number): integer
---@field floor fun(value: number): integer
---@field ceil fun(value: number): integer
---@field abs fun(value: number): number
---@field min fun(value: number, ...: number): number
---@field max fun(value: number, ...: number): number

---@class ReactiveEnvironment : ReactiveHelpers
---@field self Element Expression owner
---@field parent? Container Current parent
---@field [string] any Named elements are resolved dynamically

---@class ReactiveLiteral
---@field value string The string, stored as written

local reactive = {}

-- Module state is per Basalt instance: every loaded Basalt has its own
-- module cache (see init.lua).
local enabled = true

-- Recognized by the __basaltLiteral flag, so a marker made by another
-- Basalt instance works too.
local LiteralMeta = {
    __basaltLiteral = true,
    __tostring = function(marker) return marker.value end,
}

---@type ReactiveHelpers
local helpers = {
    colors = colors,
    math = math,
    rgb = palette.rgb,
    tostring = tostring,
    tonumber = tonumber,
    clamp = function(v, lo, hi) return math.min(math.max(v, lo), hi) end,
    round = function(v) return math.floor(v + 0.5) end,
    floor = math.floor,
    ceil = math.ceil,
    abs = math.abs,
    min = math.min,
    max = math.max,
}

--- Turns compiling of "{...}" strings on property assignment on or off.
--- Off, such strings are stored as written. XML layouts stay reactive.
---@param on boolean True compiles (the default), false stores as written
function reactive.setEnabled(on)
    enabled = on and true or false
end

--- Returns whether "{...}" strings are compiled on property assignment.
---@return boolean enabled
function reactive.isEnabled()
    return enabled
end

--- Tests whether a value has the form of a reactive expression: a string
--- that starts with "{" and ends with "}".
---@param value any Candidate value
---@return boolean expression
function reactive.isExpression(value)
    return type(value) == "string" and value:sub(1, 1) == "{"
        and value:sub(-1) == "}"
end

--- Marks a string to be stored as written by a property assignment, even
--- when reactive strings are on (the property holds the plain string).
--- Values that are not strings are returned unchanged (only strings are
--- ever compiled).
---@param value any Usually a string from outside the program
---@return ReactiveLiteral|any marker The marker, or value itself
function reactive.literal(value)
    if type(value) ~= "string" then return value end
    return setmetatable({ value = value }, LiteralMeta)
end

--- Tests whether a value is a marker made by reactive.literal.
---@param value any Candidate value
---@return boolean literal
function reactive.isLiteral(value)
    local mt = type(value) == "table" and getmetatable(value)
    return mt and mt.__basaltLiteral == true or false
end

--- Returns the string inside a reactive.literal marker, or value unchanged.
---@param value any Candidate value
---@return any value
function reactive.unwrap(value)
    local mt = type(value) == "table" and getmetatable(value)
    if mt and mt.__basaltLiteral == true then return value.value end
    return value
end

--- Compiles a {property/path/expression} string into a dynamic property
--- value. This always compiles, whatever reactive.setEnabled says.
---@param str string Braced reactive expression
---@param element Element Expression owner
---@return ReactiveResolver resolver
function reactive.compile(str, element)
    local expr = str:sub(2, -2)

    ---@type ReactiveEnvironment
    local env = setmetatable({}, {
        __index = function(_, key)
            if key == "self" then return element end
            if key == "parent" then return rawget(element, "parent") end
            local h = helpers[key]
            if h ~= nil then return h end
            local root = element:getRoot()
            if root.find then return root:find(key) end
            return nil
        end,
    })

    local fn, err = load("return " .. expr, "reactive" .. str, "t", env)
    if not fn then
        error("Basalt: invalid reactive expression " .. str
            .. ": " .. tostring(err), 3)
    end
    return fn
end

return reactive
