-- Color engine for Basalt: more than 16 colors on a 16-color terminal.
--
-- Every color that can appear on screen is an entry in a global registry
-- (index 0-255). Indices 0-15 are the native CC colors; palette.rgb()
-- registers custom colors above that. The render buffer stores registry
-- indices as raw bytes. At flush time a per-terminal Mapper assigns the 16
-- hardware palette slots to whatever registry colors are actually visible:
--  * native colors always keep their own slot,
--  * custom colors take over the slots of native colors that are NOT
--    currently on screen (via term.setPaletteColour),
--  * anything beyond 16 simultaneous colors falls back to the nearest
--    currently-assigned color.
-- Slot assignments are sticky between frames to avoid palette flicker.
-- The first time a slot of a terminal is overridden, the terminal's own
-- color for it is saved; giving the slot back (restore, or a native color
-- needing it) writes that color back, so a palette the user or another
-- program set survives a Basalt app. A slot that shows one of Basalt's own
-- custom colors (a window created while Basalt held slots of its parent
-- copies them) saves the color that was behind it instead.

---@alias PaletteRGB [number, number, number]
---@alias PaletteTranslationMap table<string, string>
---@alias PaletteColorByteMap table<number, string>
---@alias PaletteUsedColors table<integer, boolean>

---@class PaletteTerminal
---@field setPaletteColour? fun(color: number, r: number, g: number, b: number)
---@field setPaletteColor? fun(color: number, r: number, g: number, b: number)
---@field getPaletteColour? fun(color: number): number, number, number
---@field getPaletteColor? fun(color: number): number, number, number

local palette = {}

local floor = math.floor
local char = string.char

-- Native CC:Tweaked palette
local NATIVE_HEX = {
    [0] = 0xF0F0F0, 0xF2B233, 0xE57FD8, 0x99B2F2,
    0xDEDE6C, 0x7FCC19, 0xF2B2CC, 0x4C4C4C,
    0x999999, 0x4C99B2, 0xB266E5, 0x3366CC,
    0x7F664C, 0x57A64E, 0xCC4C4C, 0x111111,
}

---@type table<integer, PaletteRGB>
local reg = {}       -- registry index -> {r, g, b} (floats 0-1)
local regCount = 16  -- next free registry index
---@type PaletteColorByteMap
local charOf = {}    -- public color value -> 1-byte string (registry index)
---@type table<integer, number>
local dedupe = {}    -- rgb24 -> existing handle

---@param n integer Packed 24-bit RGB value
---@return number r
---@return number g
---@return number b
local function hexToRGB(n)
    return floor(n / 65536) / 255, floor(n / 256) % 256 / 255, (n % 256) / 255
end

for i = 0, 15 do
    reg[i] = { hexToRGB(NATIVE_HEX[i]) }
    charOf[2 ^ i] = char(i)
    dedupe[NATIVE_HEX[i]] = 2 ^ i
end

palette.charOf = charOf

--- Resolves a registry byte/index or public color handle to RGB floats.
---@param value string|number Registry byte, registry index, or colors.* handle
---@return number r
---@return number g
---@return number b
function palette.getRGB(value)
    local index
    if type(value) == "string" then
        index = value:byte()
    elseif charOf[value] then
        index = charOf[value]:byte()
    else
        index = value
    end
    local rgb = reg[index]
    if not rgb then error("Basalt: unknown registry color " .. tostring(value), 2) end
    return rgb[1], rgb[2], rgb[3]
end

---@param v number Color component
---@return number clamped
local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

---@param r number|string Red component, packed RGB value, or hex string
---@param g? number Green component
---@param b? number Blue component
---@return number red
---@return number green
---@return number blue
local function parse(r, g, b)
    if type(r) == "string" then
        local hex = r:gsub("#", "")
        if hex:match("^%x%x%x$") then -- #RGB shorthand
            hex = hex:gsub("%x", "%0%0")
        elseif hex:match("^%x%x%x%x%x%x%x%x$") then -- #AARRGGBB: ignore alpha
            hex = hex:sub(3)
        elseif not hex:match("^%x%x%x%x%x%x$") then
            error("Basalt: invalid color string '" .. r
                .. "' (expected #RGB, #RRGGBB or #AARRGGBB)", 3)
        end
        return hexToRGB(tonumber(hex, 16))
    end
    if g == nil then
        if r < 0 or r > 0xFFFFFF or r % 1 ~= 0 then
            error("Basalt: invalid color number "
                .. tostring(r) .. " (expected 0x000000-0xFFFFFF)", 3)
        end
        return hexToRGB(r)
    end
    if b == nil then
        error("Basalt: blue component is required when green is provided", 3)
    end
    if r > 1 or g > 1 or b > 1 then
        r, g, b = r / 255, g / 255, b / 255
    end
    return clamp01(r), clamp01(g), clamp01(b)
end

--- Registers or resolves an RGB color for use by the render buffer.
---@param r number|string Red component or #RRGGBB string
---@param g number Green component
---@param b number Blue component
---@return number color
---@overload fun(hex: string): number
---@overload fun(rgb24: number): number
function palette.rgb(r, g, b)
    local rr, gg, bb = parse(r, g, b)
    local key = floor(rr * 255 + 0.5) * 65536 + floor(gg * 255 + 0.5) * 256 + floor(bb * 255 + 0.5)
    local known = dedupe[key]
    if known then return known end

    if regCount > 255 then
        local best, bestDistance = 0, math.huge
        for index = 0, 255 do
            local rgb = reg[index]
            local distance = (rr - rgb[1]) ^ 2 + (gg - rgb[2]) ^ 2 + (bb - rgb[3]) ^ 2
            if distance < bestDistance then best, bestDistance = index, distance end
        end
        local fallback = best < 16 and 2 ^ best or 0x10000 + best
        dedupe[key] = fallback
        return fallback
    end
    local idx = regCount
    regCount = regCount + 1
    reg[idx] = { rr, gg, bb }

    local handle = 0x10000 + idx
    charOf[handle] = char(idx)
    dedupe[key] = handle
    return handle
end

--- Returns whether custom palette colors are currently registered.
---@return boolean hasCustomColors
function palette.hasVirtual()
    return regCount > 16
end

---@type table<integer, string>
local HEXC = {}
for i = 0, 15 do HEXC[i] = ("%x"):format(i) end

-- Translation used when only native colors exist (byte -> blit hex char).
---@type PaletteTranslationMap
local identity = {}
for i = 0, 15 do identity[char(i)] = HEXC[i] end
palette.identityMap = identity

---@type PaletteTranslationMap
local HEX2BYTE = {}
for i = 0, 15 do
    HEX2BYTE[HEXC[i]] = char(i)
    HEX2BYTE[HEXC[i]:upper()] = char(i)
end
palette.hexToByte = HEX2BYTE

--- Builds a blit-hex -> registry-byte translation for a hosted CC window.
--- Returns nil when the window palette is untouched (identity is cheaper).
---@param win PaletteTerminal CC window or compatible terminal
---@return PaletteTranslationMap|nil translate
function palette.windowTranslation(win)
    local getPal = win.getPaletteColour or win.getPaletteColor
    if not getPal then return nil end
    local translate
    for i = 0, 15 do
        local ok, r, g, b = pcall(getPal, 2 ^ i)
        if ok and type(r) == "number" and type(g) == "number"
            and type(b) == "number" then
            local nr, ng, nb = palette.getRGB(2 ^ i)
            if math.abs(r - nr) + math.abs(g - ng) + math.abs(b - nb) > 0.004 then
                if not translate then
                    translate = {}
                    for k, v in pairs(HEX2BYTE) do translate[k] = v end
                end
                local byte = charOf[palette.rgb(r, g, b)]
                translate[HEXC[i]] = byte
                translate[HEXC[i]:upper()] = byte
            end
        end
    end
    return translate
end

----------------------------------------------------------------------------
-- Mapper: per-terminal palette slot allocator
----------------------------------------------------------------------------

---@class Mapper
---@field term PaletteTerminal Terminal controlled by this mapper
---@field key any Identity of the physical terminal (see terminalKey)
---@field overridden table<integer, integer> Registry index loaded into each overridden slot
---@field prevSlot table<integer, integer> Previous hardware slot per registry index
---@field prevMap PaletteTranslationMap Previous byte-to-blit translation
local Mapper = {}
Mapper.__index = Mapper

---@class PaletteSavedSlots
---@field rgb table<integer, PaletteRGB> Terminal color of each slot before Basalt overrode it
---@field holders table<integer, integer> Number of mappers overriding each slot

-- Pre-Basalt slot colors per terminal. Shared by every mapper on the same
-- terminal (several frames, or a frame rebound with setTerm), so a slot is
-- saved once, while it still holds the terminal's own color, and written
-- back only when the last mapper overriding it lets go.
---@type table<any, PaletteSavedSlots>
local savedSlots = setmetatable({}, { __mode = "k" })

-- The pre-Basalt color behind each custom color Basalt has loaded into a
-- slot, on any terminal: behind[slot][registry index] = rgb. A CC window
-- copies its parent's palette when it is created, so a window created
-- while Basalt holds slots of its parent starts with Basalt's colors (and
-- a visible window writes its palette through to the parent). Kept after
-- the slot is given back, since the window keeps its copy. Not per
-- terminal: a window and its parent have different keys, and a window
-- cannot name its parent. Two terminals with different own colors behind
-- the same custom color in the same slot share the last one saved.
---@type table<integer, table<integer, PaletteRGB>>
local behind = {}
for i = 0, 15 do behind[i] = {} end

--- Identity of the screen behind a terminal object. Every peripheral.wrap()
--- of a monitor is a new table, so monitors are keyed by peripheral name.
---@param t PaletteTerminal Terminal-like object
---@return any key
local function terminalKey(t)
    ---@diagnostic disable-next-line: undefined-field
    if t.setTextScale and peripheral and peripheral.getName then
        local ok, name = pcall(peripheral.getName, t)
        if ok and type(name) == "string" then return "peripheral:" .. name end
    end
    return t
end

--- Reads one palette slot of a terminal; CC's default when it can't be read.
---@param t PaletteTerminal Terminal-like object
---@param slot integer Palette slot 0-15
---@return PaletteRGB rgb
local function readSlot(t, slot)
    local getPal = t.getPaletteColour or t.getPaletteColor
    if getPal then
        local ok, r, g, b = pcall(getPal, 2 ^ slot)
        if ok and type(r) == "number" and type(g) == "number"
            and type(b) == "number" then
            return { r, g, b }
        end
    end
    local n = reg[slot]
    return { n[1], n[2], n[3] }
end

--- The terminal's own color for a slot that no mapper on it holds: what
--- the slot shows, or, when that is a custom color Basalt loaded into the
--- slot (a window copies its parent's palette, Basalt's colors included),
--- the color behind it.
---@param t PaletteTerminal Terminal-like object
---@param slot integer Palette slot 0-15
---@return PaletteRGB rgb
local function ownColor(t, slot)
    local shown = readSlot(t, slot)
    -- the closest custom color within about one 8-bit step
    local found, bestD = nil, 3 * 0.003 * 0.003
    for i, rgb in pairs(behind[slot]) do
        local c = reg[i]
        local dr, dg, db = c[1] - shown[1], c[2] - shown[2], c[3] - shown[3]
        local d = dr * dr + dg * dg + db * db
        if d < bestD then found, bestD = rgb, d end
    end
    if found then return { found[1], found[2], found[3] } end
    return shown
end

--- Writes a palette slot, taking it over for this mapper first if needed.
---@param self Mapper
---@param setPal fun(color: number, r: number, g: number, b: number)
---@param slot integer Palette slot 0-15
---@param idx integer Registry index to load into the slot
local function override(self, setPal, slot, idx)
    local first = self.overridden[slot] == nil
    local rec = savedSlots[self.key]
    -- read before writing; nobody else holds the slot, so it still shows
    -- the terminal's own color (or Basalt's, in a window's copy)
    local original = first and not (rec and rec.rgb[slot])
        and ownColor(self.term, slot)
    local c = reg[idx]
    setPal(2 ^ slot, c[1], c[2], c[3])
    if first then
        if not rec then
            rec = { rgb = {}, holders = {} }
            savedSlots[self.key] = rec
        end
        if original then rec.rgb[slot] = original end
        rec.holders[slot] = (rec.holders[slot] or 0) + 1
    end
    behind[slot][idx] = rec and rec.rgb[slot] or behind[slot][idx]
    self.overridden[slot] = idx
end

--- Lets go of an overridden slot. The saved color is written back when no
--- other mapper on the terminal still overrides the slot, or always when
--- this mapper needs the slot's own color on screen.
---@param self Mapper
---@param setPal? fun(color: number, r: number, g: number, b: number)
---@param slot integer Palette slot 0-15
---@param always boolean Write the saved color even if the slot is shared
local function release(self, setPal, slot, always)
    local key = self.key
    local rec = savedSlots[key]
    local holders = rec and rec.holders[slot] or 1
    local rgb = rec and rec.rgb[slot] or reg[slot]
    if setPal and (always or holders <= 1) then
        setPal(2 ^ slot, rgb[1], rgb[2], rgb[3])
    end
    self.overridden[slot] = nil
    if not rec then return end
    if holders > 1 then
        rec.holders[slot] = holders - 1
    else
        rec.holders[slot], rec.rgb[slot] = nil, nil
        if next(rec.holders) == nil then savedSlots[key] = nil end
    end
end

--- Creates a palette mapper for one terminal.
---@param t PaletteTerminal Terminal-like object
---@return Mapper mapper
function palette.newMapper(t)
    return setmetatable({
        term = t,
        key = terminalKey(t),
        overridden = {},
        prevSlot = {},
        prevMap = {},
    }, Mapper)
end

---@param a PaletteRGB First color
---@param b PaletteRGB Second color
---@return number distance
local function dist(a, b)
    local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
    return dr * dr + dg * dg + db * db
end

--- Assigns hardware palette slots for the colors used by this frame.
---@param used PaletteUsedColors Registry indices used by this frame
---@return PaletteTranslationMap map Registry byte to terminal blit character
---@return boolean changed
function Mapper:build(used)
    local t = self.term
    local setPal = t.setPaletteColour or t.setPaletteColor
    local map = {}
    local occupant = {}

    for i = 0, 15 do
        map[char(i)] = HEXC[i]
        if used[i] then
            occupant[i] = i
            if setPal and self.overridden[i] then
                -- the native color needs its slot: give it the terminal's
                -- own color back
                release(self, setPal, i, true)
            end
        end
    end

    local virt = {}
    for idx in pairs(used) do
        if idx > 15 then virt[#virt + 1] = idx end
    end

    if #virt > 0 then
        table.sort(virt)
        local leftovers = {}

        if setPal then
            local function assign(idx, slot)
                occupant[slot] = idx
                self.prevSlot[idx] = slot
                if self.overridden[slot] ~= idx then
                    override(self, setPal, slot, idx)
                end
                map[char(idx)] = HEXC[slot]
            end

            local pending = {}
            for _, idx in ipairs(virt) do
                local s = self.prevSlot[idx]
                if s and occupant[s] == nil then
                    assign(idx, s)
                else
                    pending[#pending + 1] = idx
                end
            end

            local nextSlot = 0
            for _, idx in ipairs(pending) do
                local slot
                while nextSlot <= 15 do
                    if occupant[nextSlot] == nil then
                        slot = nextSlot
                        break
                    end
                    nextSlot = nextSlot + 1
                end
                if slot then
                    assign(idx, slot)
                else
                    leftovers[#leftovers + 1] = idx
                end
            end
        else
            leftovers = virt
        end

        for _, idx in ipairs(leftovers) do
            local c = reg[idx]
            local best, bestD = 15, math.huge
            for s = 0, 15 do
                local occ = occupant[s]
                local shown = occ and reg[occ] or (not setPal and reg[s] or nil)
                if shown then
                    local d = dist(c, shown)
                    if d < bestD then best, bestD = s, d end
                end
            end
            map[char(idx)] = HEXC[best]
        end
    end

    local changed = false
    local prev = self.prevMap
    for k, v in pairs(map) do
        if prev[k] ~= nil and prev[k] ~= v then
            changed = true
            break
        end
    end
    self.prevMap = map
    return map, changed
end

--- Gives every palette slot this mapper overrode back to the terminal:
--- each slot gets the color it had before Basalt took it over (unless
--- another mapper on the same terminal still uses the slot).
function Mapper:restore()
    local t = self.term
    local setPal = t.setPaletteColour or t.setPaletteColor
    for slot in pairs(self.overridden) do
        release(self, setPal, slot, false)
    end
    self.overridden, self.prevSlot, self.prevMap = {}, {}, {}
end

return palette
