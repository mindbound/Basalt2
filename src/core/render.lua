-- Render buffer for Basalt.
--
-- Holds the screen as three string arrays (text / fg / bg). Colors are stored
-- as raw bytes (registry indices from core/palette), which is what allows
-- more than 16 colors in the buffer. On flush, only lines that actually
-- differ from what the terminal currently shows are blitted, and color bytes
-- are translated to blit hex chars through the palette mapper.
--
-- Positions are screen cells (see core/text). Each text row holds exactly
-- `width` cells and each fg/bg row exactly `width` bytes, one per cell. On
-- plain CC: Tweaked a cell is a byte; with the Unicode Support mod a text
-- cell can be a multi-byte UTF-8 character, so text is measured with
-- text.width, cut with text.sub and normalized before it goes into a row.

local require = ...
local palette = require("core/palette")
local textutil = require("core/text")

local rep, sub, byte = string.rep, string.sub, string.byte
local floor = math.floor
local charOf = palette.charOf
local width, cellSub, normalize = textutil.width, textutil.sub, textutil.normalize
local byteLen, byteCells, cellsOf = textutil.byteLen, textutil.isByteCells, textutil.cells
local isUtf8 = textutil.isUtf8

--- The text argument of a draw call: a string, or a number as a string.
---@param s any
---@return string
local function textArg(s)
    local t = type(s)
    if t == "string" then return s end
    if t == "number" then return tostring(s) end
    error("Basalt: text must be a string, got " .. t, 3)
end

--- With the Unicode mod, a colour plane cut to the text's cell count, so a
--- plane longer than its text (window.getLine rows whose cells merged, or
--- planes sized with #) can't make a row longer than the screen.
---@param plane? string
---@param n integer Cells of the text
---@return string?
local function fitPlane(plane, n)
    if plane and byteLen(plane) > n then
        return sub(plane, 1, n)
    end
    return plane
end

---@alias RenderLineBuffer string[]
---@alias RenderMosaic [string, string, string]
---@alias RenderPixelRows string[]
---@alias RenderPixelPalette table<integer, string>

---@type table<integer, string>
local mosaicChars = {}
---@type table<string, RenderMosaic>
local mosaicCache = {}
for mask = 0, 31 do mosaicChars[mask] = string.char(128 + mask) end

---@class RenderTerminal : PaletteTerminal
---@field getSize fun(): integer, integer
---@field setCursorPos fun(x: number, y: number)
---@field setCursorBlink fun(blink: boolean)
---@field setTextColor fun(color: number)
---@field blit fun(text: string, foreground: string, background: string)

--- Render buffer for Basalt.
---@class Render
---@field term RenderTerminal Terminal receiving flushed output
---@field mapper Mapper Palette mapper associated with the terminal
---@field width integer Buffer width
---@field height integer Buffer height
---@field text RenderLineBuffer Text plane
---@field fg RenderLineBuffer Foreground registry-byte plane
---@field bg RenderLineBuffer Background registry-byte plane
---@field prevText RenderLineBuffer Previously flushed text plane
---@field prevFg RenderLineBuffer Previously flushed foreground plane
---@field prevBg RenderLineBuffer Previously flushed background plane
---@field dirty boolean Whether the buffer or cursor state changed
---@field ox number Current horizontal translation
---@field oy number Current vertical translation
---@field cx1 number Current left clipping edge
---@field cy1 number Current top clipping edge
---@field cx2 number Current right clipping edge
---@field cy2 number Current bottom clipping edge
---@field stack number[] Saved origins and clipping rectangles
---@field stackN integer Number of values currently stored in `stack`
---@field cursorX? number Requested terminal cursor x coordinate
---@field cursorY? number Requested terminal cursor y coordinate
---@field cursorBlink? boolean Requested terminal cursor blink state
---@field cursorColor? number Requested public cursor color
---@field released? boolean Set by basalt.cleanup (the terminal was handed back); the next flush clears it
local Render = {}
Render.__index = Render

--- Creates a retained terminal render buffer.
---@param t RenderTerminal Terminal-like target
---@return Render buffer
function Render.new(t)
    local self = setmetatable({}, Render)
    self.term = t
    self.mapper = palette.newMapper(t)
    self:resize(t.getSize())
    return self
end

--- Resizes and clears the retained buffer.
---@param w integer Width
---@param h integer Height
---@return self
function Render:resize(w, h)
    self.width, self.height = w, h
    self.text, self.fg, self.bg = {}, {}, {}
    self.prevText, self.prevFg, self.prevBg = {}, {}, {}
    local blankT = rep(" ", w)
    local blankF = rep("\0", w)
    local blankB = rep(string.char(15), w)
    for y = 1, h do
        self.text[y], self.fg[y], self.bg[y] = blankT, blankF, blankB
    end
    self.dirty = true
    self.stack = {}
    return self:resetClip()
end

--- Resets the origin and the clipping rectangle to the whole buffer. A
--- render pass that ended with an error leaves them where it stopped.
---@return self
function Render:resetClip()
    self.ox, self.oy = 0, 0
    self.cx1, self.cy1, self.cx2, self.cy2 = 1, 1, self.width, self.height
    self.stackN = 0
    return self
end

--- Forgets what the terminal shows: the next flush writes every line, and
--- every palette slot it assigns, again (another program may have drawn
--- on the terminal or changed its palette). The buffer is kept.
---@return self
function Render:invalidate()
    self.prevText, self.prevFg, self.prevBg = {}, {}, {}
    self.mapper:invalidate()
    self.dirty = true
    return self
end

--- Pushes a child region: translates the origin to (x, y) in the current
--- space and intersects the clip rect with the w*h area.
---@param x number Child x position
---@param y number Child y position
---@param w number Child width
---@param h number Child height
---@return self
function Render:push(x, y, w, h)
    local n, s = self.stackN, self.stack
    s[n + 1], s[n + 2], s[n + 3] = self.ox, self.oy, self.cx1
    s[n + 4], s[n + 5], s[n + 6] = self.cy1, self.cx2, self.cy2
    self.stackN = n + 6

    local ox, oy = self.ox + x - 1, self.oy + y - 1
    self.ox, self.oy = ox, oy
    if ox + 1 > self.cx1 then self.cx1 = ox + 1 end
    if oy + 1 > self.cy1 then self.cy1 = oy + 1 end
    if ox + w < self.cx2 then self.cx2 = ox + w end
    if oy + h < self.cy2 then self.cy2 = oy + h end
    return self
end

--- Restores the previous origin and clipping rectangle.
---@return self
function Render:pop()
    local n, s = self.stackN, self.stack
    self.ox, self.oy, self.cx1 = s[n - 5], s[n - 4], s[n - 3]
    self.cy1, self.cx2, self.cy2 = s[n - 2], s[n - 1], s[n]
    self.stackN = n - 6
    return self
end

--- Replaces n bytes of a colour plane row at byte x (one byte per cell).
---@param line string Original plane row
---@param x number One-based replacement position
---@param str string Replacement span
---@param n integer Its length in bytes
---@return string line
local function splicePlane(line, x, str, n)
    return sub(line, 1, x - 1) .. str .. sub(line, x + n)
end

--- Replaces n cells of a text row at cell x with str (normalized, n cells).
---@param line string Original text row
---@param x number One-based replacement position (cell)
---@param str string Replacement span
---@param n integer Its width in cells
---@return string line
local function spliceText(line, x, str, n)
    if not isUtf8() or (byteCells(line) and byteCells(str)) then
        return sub(line, 1, x - 1) .. str .. sub(line, x + n)
    end
    local first, last = textutil.span(line, x, x + n - 1)
    return sub(line, 1, first - 1) .. str .. sub(line, last + 1)
end

---@param source string Source plane
---@param underneath string Existing plane underneath the source
---@param mask? string Explicit visibility mask
---@return string merged
local function mergeTransparent(source, underneath, mask)
    local out = {}
    for i = 1, byteLen(source) do
        local marker = mask and byte(mask, i) or byte(source, i)
        out[i] = marker == 0 and sub(underneath, i, i) or sub(source, i, i)
    end
    return table.concat(out)
end

--- mergeTransparent for the text plane, cell by cell: a source cell that is
--- NUL (or masked out) shows the cell underneath.
---@param source string Source text (normalized)
---@param underneath string Existing text underneath the source
---@param mask? string Explicit visibility mask (one byte per cell)
---@return string merged
local function mergeTransparentText(source, underneath, mask)
    if not isUtf8() or (byteCells(source) and byteCells(underneath)) then
        return mergeTransparent(source, underneath, mask)
    end
    local src, under, out = cellsOf(source), cellsOf(underneath), {}
    for i = 1, #src do
        local marker = mask and byte(mask, i) or byte(src[i], 1)
        out[i] = marker == 0 and (under[i] or " ") or src[i]
    end
    return table.concat(out)
end

---@param value string Registry byte to approximate
---@param a string First candidate registry byte
---@param b string Second candidate registry byte
---@return 0|1 candidate Zero for `a`, one for `b`
local function nearestOf(value, a, b)
    local vr, vg, vb = palette.getRGB(value)
    local ar, ag, ab = palette.getRGB(a)
    local br, bg, bb = palette.getRGB(b)
    local da = (vr - ar) ^ 2 + (vg - ag) ^ 2 + (vb - ab) ^ 2
    local db = (vr - br) ^ 2 + (vg - bg) ^ 2 + (vb - bb) ^ 2
    return da <= db and 0 or 1
end

---@param c1 string Top-left registry byte
---@param c2 string Top-right registry byte
---@param c3 string Middle-left registry byte
---@param c4 string Middle-right registry byte
---@param c5 string Bottom-left registry byte
---@param c6 string Bottom-right registry byte
---@return string character
---@return string foreground
---@return string background
local function compileMosaic(c1, c2, c3, c4, c5, c6)
    local key = c1 .. c2 .. c3 .. c4 .. c5 .. c6
    local cached = mosaicCache[key]
    if cached then return cached[1], cached[2], cached[3] end
    local values, counts, order = { c1, c2, c3, c4, c5, c6 }, {}, {}
    for i = 1, 6 do
        local value = values[i]
        if counts[value] then counts[value] = counts[value] + 1
        else counts[value], order[#order + 1] = 1, value end
    end
    local a, b
    for _, value in ipairs(order) do
        if not a or counts[value] > counts[a] then b, a = a, value
        elseif not b or counts[value] > counts[b] then b = value end
    end
    if not b then
        cached = { " ", a, a }
        mosaicCache[key] = cached
        return cached[1], cached[2], cached[3]
    end
    local bits = {}
    for i = 1, 6 do
        bits[i] = values[i] == a and 0
            or (values[i] == b and 1 or nearestOf(values[i], a, b))
    end
    local pivot, mask = bits[6], 0
    if bits[1] ~= pivot then mask = mask + 1 end
    if bits[2] ~= pivot then mask = mask + 2 end
    if bits[3] ~= pivot then mask = mask + 4 end
    if bits[4] ~= pivot then mask = mask + 8 end
    if bits[5] ~= pivot then mask = mask + 16 end
    local fg, bg
    if pivot == 0 then fg, bg = b, a else fg, bg = a, b end
    cached = { mosaicChars[mask], fg, bg }
    mosaicCache[key] = cached
    return cached[1], cached[2], cached[3]
end

--- Core write. fgChar/bgChar are single-byte strings or nil (keep existing).
---@param x number X position
---@param y number Y position
---@param str string Text to write
---@param fgChar? string Encoded foreground bytes
---@param bgChar? string Encoded background bytes
---@return self
function Render:write(x, y, str, fgChar, bgChar)
    local ay = y + self.oy
    if ay < self.cy1 or ay > self.cy2 then return self end

    str = textArg(str)
    local utf8 = isUtf8()
    if utf8 then str = normalize(str) end
    local cut = utf8 and cellSub or sub
    local ax = x + self.ox
    local s, e = ax, ax + (utf8 and width(str) or byteLen(str)) - 1
    local x1, x2 = self.cx1, self.cx2
    if s < x1 then
        str = cut(str, x1 - s + 1)
        s = x1
    end
    if e > x2 then
        str = cut(str, 1, x2 - s + 1)
        e = x2
    end
    if s > e then return self end

    -- The text replaces as many cells as it has (s and e may be fractional)
    if utf8 then
        self.text[ay] = spliceText(self.text[ay], s, str, width(str))
    else
        self.text[ay] = splicePlane(self.text[ay], s, str, byteLen(str))
    end
    if fgChar then
        local span = rep(fgChar, e - s + 1)
        self.fg[ay] = splicePlane(self.fg[ay], s, span, byteLen(span))
    end
    if bgChar then
        local span = rep(bgChar, e - s + 1)
        self.bg[ay] = splicePlane(self.bg[ay], s, span, byteLen(span))
    end
    self.dirty = true
    return self
end

---@param color? number|false Public color value; false keeps the existing color
---@return string? byte Encoded registry byte
local function colorChar(color)
    if not color then return nil end
    local c = charOf[color]
    if not c then
        error("Basalt: unknown color value " .. tostring(color)
            .. " (use colors.* or basalt.rgb)", 3)
    end
    return c
end

--- Writes text with optional fg/bg colors (public color values, nil = keep).
---@param x number X position
---@param y number Y position
---@param str string Text to write
---@param fg? number|false Foreground color; false keeps the existing color
---@param bg? number|false Background color; false keeps the existing color
---@return self
function Render:blit(x, y, str, fg, bg)
    return self:write(x, y, str, colorChar(fg), colorChar(bg))
end

--- Writes a row whose cells may each use a different public color value.
--- This is the efficient path for custom-painted editors and charts: it
--- performs one clipped line splice instead of one splice per cell.
---@param x number X position
---@param y number Y position
---@param str string Text to write
---@param foregrounds number[] Foreground color for each character
---@param backgrounds number[] Background color for each character
---@return self
function Render:colorBlit(x, y, str, foregrounds, backgrounds)
    str = textArg(str)
    local fg, bg = {}, {}
    for i = 1, width(str) do
        fg[i] = colorChar(foregrounds[i])
        bg[i] = colorChar(backgrounds[i])
    end
    return self:rawBlit(x, y, str, table.concat(fg), table.concat(bg))
end

--- Writes plain text, keeping the colors underneath.
--- (named drawText because .text is the buffer's line array)
---@param x number X position
---@param y number Y position
---@param str string Text to write
---@return self
function Render:drawText(x, y, str)
    return self:write(x, y, str)
end

--- Writes a pre-encoded span: fgStr/bgStr are byte strings (registry
--- indices) with the same length as str, or nil to keep existing colors.
---@param x number X position
---@param y number Y position
---@param str string Text to write
---@param fgStr? string Encoded foreground bytes
---@param bgStr? string Encoded background bytes
---@return self
function Render:rawBlit(x, y, str, fgStr, bgStr)
    local ay = y + self.oy
    if ay < self.cy1 or ay > self.cy2 then return self end
    str = textArg(str)
    local utf8 = isUtf8()
    local w
    if utf8 then
        str = normalize(str)
        w = width(str)
        fgStr, bgStr = fitPlane(fgStr, w), fitPlane(bgStr, w)
    else
        w = byteLen(str)
    end
    local ax = x + self.ox
    local s, e = ax, ax + w - 1
    local x1, x2 = self.cx1, self.cx2
    local cutFront = s < x1 and (x1 - s) or 0
    local cutBack = e > x2 and (e - x2) or 0
    if cutFront > 0 or cutBack > 0 then
        s = s + cutFront
        e = e - cutBack
        if s > e then return self end
        str = (utf8 and cellSub or sub)(str, 1 + cutFront, w - cutBack)
        if fgStr then fgStr = sub(fgStr, 1 + cutFront, byteLen(fgStr) - cutBack) end
        if bgStr then bgStr = sub(bgStr, 1 + cutFront, byteLen(bgStr) - cutBack) end
    end
    if utf8 then
        self.text[ay] = spliceText(self.text[ay], s, str, width(str))
    else
        self.text[ay] = splicePlane(self.text[ay], s, str, byteLen(str))
    end
    if fgStr then self.fg[ay] = splicePlane(self.fg[ay], s, fgStr, byteLen(fgStr)) end
    if bgStr then self.bg[ay] = splicePlane(self.bg[ay], s, bgStr, byteLen(bgStr)) end
    self.dirty = true
    return self
end

--- Writes byte planes with independent transparency. Without explicit masks,
-- NUL in the corresponding source plane means unchanged. Color masks are
-- needed when registry byte zero (native white) is a visible source color.
---@param x number X position
---@param y number Y position
---@param str string Text plane
---@param fgStr? string Encoded foreground plane
---@param bgStr? string Encoded background plane
---@param textMask? string Text visibility mask
---@param fgMask? string Foreground visibility mask
---@param bgMask? string Background visibility mask
---@return self
function Render:maskedBlit(x, y, str, fgStr, bgStr, textMask, fgMask, bgMask)
    local ay, ax = y + self.oy, x + self.ox
    if ay < self.cy1 or ay > self.cy2 then return self end
    str = textArg(str)
    local utf8 = isUtf8()
    local w
    if utf8 then
        str = normalize(str)
        w = width(str)
        fgStr, bgStr = fitPlane(fgStr, w), fitPlane(bgStr, w)
        textMask, fgMask, bgMask = fitPlane(textMask, w), fitPlane(fgMask, w), fitPlane(bgMask, w)
    else
        w = byteLen(str)
    end
    local s, e = ax, ax + w - 1
    local cutFront = s < self.cx1 and self.cx1 - s or 0
    local cutBack = e > self.cx2 and e - self.cx2 or 0
    local function cut(plane)
        return plane and sub(plane, 1 + cutFront, byteLen(plane) - cutBack)
    end
    if cutFront > 0 or cutBack > 0 then
        s, e = s + cutFront, e - cutBack
        if s > e then return self end
        str = (utf8 and cellSub or sub)(str, 1 + cutFront, w - cutBack)
        fgStr, bgStr = cut(fgStr), cut(bgStr)
        textMask, fgMask, bgMask = cut(textMask), cut(fgMask), cut(bgMask)
    end
    if utf8 then
        local oldText = cellSub(self.text[ay], s, e)
        local merged = mergeTransparentText(str, oldText, textMask)
        self.text[ay] = spliceText(self.text[ay], s, merged, width(str))
    else
        local merged = mergeTransparent(str, sub(self.text[ay], s, e), textMask)
        self.text[ay] = splicePlane(self.text[ay], s, merged, byteLen(merged))
    end
    if fgStr then
        local merged = mergeTransparent(fgStr, sub(self.fg[ay], s, e), fgMask)
        self.fg[ay] = splicePlane(self.fg[ay], s, merged, byteLen(merged))
    end
    if bgStr then
        local merged = mergeTransparent(bgStr, sub(self.bg[ay], s, e), bgMask)
        self.bg[ay] = splicePlane(self.bg[ay], s, merged, byteLen(merged))
    end
    self.dirty = true
    return self
end

--- Draws palette-indexed 2x3 virtual pixels. Transparent source pixels sample
-- the current background, so FLIMG sprites blend with previously drawn UI.
---@param x number X position in terminal cells
---@param y number Y position in terminal cells
---@param pixelWidth integer Source width in virtual pixels
---@param pixelHeight integer Source height in virtual pixels
---@param rows RenderPixelRows Palette-index rows; byte zero is transparent
---@param paletteBytes RenderPixelPalette Palette index to registry byte
---@return self
function Render:drawPixels(x, y, pixelWidth, pixelHeight, rows, paletteBytes)
    local cellWidth, cellHeight = math.ceil(pixelWidth / 2), math.ceil(pixelHeight / 3)
    for cellY = 1, cellHeight do
        local text, fg, bg, mask, rowHasPixels = {}, {}, {}, {}, false
        -- With the Unicode mod, the text row underneath, split into cells
        -- once per row (it only changes at the maskedBlit after this loop)
        local underRow
        for cellX = 1, cellWidth do
            local absoluteX, absoluteY = x + cellX - 1 + self.ox, y + cellY - 1 + self.oy
            local visible = absoluteX >= self.cx1 and absoluteX <= self.cx2
                and absoluteY >= self.cy1 and absoluteY <= self.cy2
            local values, any = {}, false
            if visible then
                local underneath, underBg = {}, sub(self.bg[absoluteY], absoluteX, absoluteX)
                local underCode
                if isUtf8() then
                    underRow = underRow or cellsOf(self.text[absoluteY])
                    local underCell = underRow[absoluteX] or " "
                    underCode = byteLen(underCell) == 1 and byte(underCell) or nil
                else
                    underCode = byte(self.text[absoluteY], absoluteX)
                end
                if underCode and underCode >= 128 and underCode <= 159 then
                    local underFg, underMask = sub(self.fg[absoluteY], absoluteX, absoluteX), underCode - 128
                    local weights = { 1, 2, 4, 8, 16 }
                    for slot = 1, 5 do
                        underneath[slot] = floor(underMask / weights[slot]) % 2 == 1 and underFg or underBg
                    end
                    underneath[6] = underBg
                else
                    for slot = 1, 6 do underneath[slot] = underBg end
                end
                for py = 1, 3 do
                    local sourceY = (cellY - 1) * 3 + py
                    for px = 1, 2 do
                        local sourceX = (cellX - 1) * 2 + px
                        local slot = (py - 1) * 2 + px
                        local index = sourceY <= pixelHeight and sourceX <= pixelWidth
                            and rows[sourceY]:byte(sourceX) or 0
                        if index ~= 0 then
                            values[slot], any = paletteBytes[index], true
                            if not values[slot] then error("Basalt: FLIMG palette index " .. index .. " is missing", 2) end
                        else values[slot] = underneath[slot] end
                    end
                end
            end
            if any then
                text[cellX], fg[cellX], bg[cellX] = compileMosaic(
                    values[1], values[2], values[3], values[4], values[5], values[6])
                mask[cellX], rowHasPixels = "\1", true
            else
                text[cellX], fg[cellX], bg[cellX] = "\0", "\0", "\0"
                mask[cellX] = "\0"
            end
        end
        if rowHasPixels then
            local visibleMask = table.concat(mask)
            self:maskedBlit(x, y + cellY - 1,
                table.concat(text), table.concat(fg), table.concat(bg),
                visibleMask, visibleMask, visibleMask)
        end
    end
    return self
end

---@type table<string, string>
local HEXBYTE = {}
for i = 0, 15 do
    HEXBYTE[("%x"):format(i)] = string.char(i)
    HEXBYTE[("%X"):format(i)] = string.char(i)
end

--- Writes a blit triple with hex color strings ("0"-"f"), e.g. straight
--- from window.getLine() — used to embed foreign terminal content.
---@param x number X position
---@param y number Y position
---@param str string Text to write
---@param fgHex? string Foreground blit string
---@param bgHex? string Background blit string
---@return self
function Render:drawBlit(x, y, str, fgHex, bgHex)
    return self:rawBlit(x, y, str,
        fgHex and (fgHex:gsub(".", HEXBYTE)),
        bgHex and (bgHex:gsub(".", HEXBYTE)))
end

--- Fills a w*h area with a character and optional colors.
---@param x number X position
---@param y number Y position
---@param w number Width
---@param h number Height
---@param ch string Fill character
---@param fg? number|false Foreground color; false keeps the existing color
---@param bg? number|false Background color; false keeps the existing color
---@return self
function Render:fill(x, y, w, h, ch, fg, bg)
    local row = rep(ch, w)
    local f, b = colorChar(fg), colorChar(bg)
    for dy = 0, h - 1 do
        self:write(x, y + dy, row, f, b)
    end
    return self
end

--- Stores the cursor state to present during the next flush.
---@param x number Cursor x
---@param y number Cursor y
---@param blink boolean Blink state
---@param color? number Cursor color
---@return self
function Render:setCursor(x, y, blink, color)
    self.cursorX, self.cursorY, self.cursorBlink = x, y, blink
    self.cursorColor = color
    self.dirty = true
    return self
end

---@param line string Registry-byte plane
---@param used PaletteUsedColors Destination set of registry indices
local function scanLine(line, used)
    for i = 1, byteLen(line) do
        used[line:byte(i)] = true
    end
end

--- Diffs the buffer against the terminal state and blits changed lines only.
---@return self
function Render:flush()
    if not self.dirty then return self end
    local t = self.term
    self.released = nil

    local map, force
    if palette.hasVirtual() then
        local used = {}
        for y = 1, self.height do
            scanLine(self.fg[y], used)
            scanLine(self.bg[y], used)
        end
        map, force = self.mapper:build(used)
    else
        map, force = palette.identityMap, false
    end

    local prevT, prevF, prevB = self.prevText, self.prevFg, self.prevBg
    for y = 1, self.height do
        local tx, f, b = self.text[y], self.fg[y], self.bg[y]
        if force or tx ~= prevT[y] or f ~= prevF[y] or b ~= prevB[y] then
            t.setCursorPos(1, y)
            t.blit(tx, (f:gsub(".", map)), (b:gsub(".", map)))
            prevT[y], prevF[y], prevB[y] = tx, f, b
        end
    end

    if self.cursorBlink then
        local ch = self.cursorColor and charOf[self.cursorColor]
        local hex = ch and map[ch]
        if hex then t.setTextColor(2 ^ tonumber(hex, 16)) end
        t.setCursorPos(self.cursorX, self.cursorY)
        t.setCursorBlink(true)
    else
        t.setCursorBlink(false)
    end

    self.dirty = false
    return self
end

return Render
