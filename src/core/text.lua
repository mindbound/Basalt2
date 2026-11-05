-- Shared text helpers: measuring and cutting text in screen cells, word
-- wrapping (Label, Dialog, Toast, ...), and input conversion.
--
-- A "cell" is one character on the terminal. On plain CC: Tweaked every byte
-- is a cell. With the "CC: Tweaked Unicode Support" mod installed (it adds a
-- global `unicode` table), the terminal decodes UTF-8: a well-formed UTF-8
-- sequence is one cell and every other byte is one cell. That mod also makes
-- `#` and string.len count characters, while string.sub, find and byte stay
-- byte-based. So Basalt never uses `#` on text: it measures with
-- text.width, cuts with text.sub, and counts bytes with text.byteLen.
--
-- Text that is drawn goes through text.normalize first. With the mod, a
-- byte that could start a UTF-8 sequence but doesn't (a CC-charset letter
-- such as "\233" for é) could otherwise merge with the bytes after it into
-- a different character, and a screen row would end up with fewer cells
-- than its colour planes. Without the mod every function here behaves like
-- the plain string function it replaces.

---@alias TextLines string[]

local textutil = {}

local find, sub, byte, char, rep = string.find, string.sub, string.byte, string.char, string.rep
local floor, concat = math.floor, table.concat

--- Whether the terminal decodes UTF-8. Detected when Basalt loads.
local utf8Mode = type(unicode) == "table" and type(unicode.len) == "function"

--- True when the "CC: Tweaked Unicode Support" mod is active, so cells are
--- UTF-8 characters rather than bytes.
---@return boolean
function textutil.isUtf8()
    return utf8Mode
end

--- Overrides the detected mode (for tests, or to force byte cells).
---@param enabled boolean
function textutil.setUtf8(enabled)
    utf8Mode = enabled and true or false
end

--- Byte length of s. (`#` counts characters under the Unicode mod, and
--- rawlen is unreliable in some emulators; find is byte-based everywhere.)
---@param s string
---@return integer
local function byteLen(s)
    local _, last = find(s, "$")
    return last
end
textutil.byteLen = byteLen

--- True when s has no bytes >= 0x80; then a cell is a byte in any mode.
---@param s string
---@return boolean
local function isPlain(s)
    return not find(s, "[\128-\255]")
end
textutil.isPlain = isPlain

--- True when s has no byte 0xC2-0xF4, so no byte can start a multi-byte
--- cell: every byte is one cell in any mode.
local function isByteCells(s)
    return not find(s, "[\194-\244]")
end
textutil.isByteCells = isByteCells

--- Byte length of the cell that starts at byte i: the length of a
--- well-formed UTF-8 sequence there, else 1. These are the mod's rules:
--- C0, C1 and F5-FF never start a sequence, no overlong forms, no
--- surrogates, nothing above U+10FFFF.
---@param s string
---@param i integer
---@param n integer Byte length of s
---@return integer
local function cellLen(s, i, n)
    local b = byte(s, i)
    local len
    if b < 0xC2 then return 1
    elseif b <= 0xDF then len = 2
    elseif b <= 0xEF then len = 3
    elseif b <= 0xF4 then len = 4
    else return 1 end
    if i + len - 1 > n then return 1 end
    local second = byte(s, i + 1)
    if second < 0x80 or second > 0xBF
        or (b == 0xE0 and second < 0xA0) or (b == 0xED and second > 0x9F)
        or (b == 0xF0 and second < 0x90) or (b == 0xF4 and second > 0x8F) then
        return 1
    end
    for j = i + 2, i + len - 1 do
        local c = byte(s, j)
        if c < 0x80 or c > 0xBF then return 1 end
    end
    return len
end

--- Byte offsets where the cells of s start, and the byte length of s.
---@param s string
---@return integer[] starts, integer n
local function cellStarts(s)
    local starts, count, i, n = {}, 0, 1, byteLen(s)
    while i <= n do
        count = count + 1
        starts[count] = i
        i = i + cellLen(s, i, n)
    end
    return starts, n
end

local function str(s)
    if type(s) == "string" then return s end
    return tostring(s)
end

--- Width of s in cells.
---@param s string|number
---@return integer
function textutil.width(s)
    s = str(s)
    if not utf8Mode or isByteCells(s) then
        return byteLen(s)
    end
    local count, i, n = 0, 1, byteLen(s)
    while i <= n do
        count = count + 1
        i = i + cellLen(s, i, n)
    end
    return count
end

--- Byte range of cells i..j of s (string.sub's rules for i and j). Returns
--- the first byte and the last byte; an empty range has last < first.
---@param s string
---@param i? integer First cell (default 1; negative counts from the end)
---@param j? integer Last cell (default -1)
---@return integer first, integer last
function textutil.span(s, i, j)
    -- Whole numbers, truncated toward zero like string.sub does
    i, j = i or 1, j or -1
    i = i >= 0 and floor(i) or -floor(-i)
    j = j >= 0 and floor(j) or -floor(-j)
    local starts, n, count
    if not utf8Mode or isByteCells(s) then
        n = byteLen(s)
        count = n
    elseif i >= 0 and j >= 0 then
        -- Positive cells: jump from lead byte to lead byte (bytes in
        -- between are one cell each) and stop once cell max(i, j+1) is found
        if i < 1 then i = 1 end
        local b = j + 1 > i and j + 1 or i
        n = byteLen(s)
        local pos, c, fa = 1, 1, nil
        while true do
            local lead = find(s, "[\194-\244]", pos)
            local stop = lead and (c + lead - pos)
            if not fa and (not lead or i <= stop) then
                fa = pos + (i - c)
                if fa > n + 1 then fa = n + 1 end
            end
            if fa and (not lead or b <= stop) then
                local fb = pos + (b - c)
                if fb > n + 1 then fb = n + 1 end
                if j < i then return fa, fa - 1 end
                return fa, fb - 1
            end
            pos, c = lead + cellLen(s, lead, n), stop + 1
        end
    else
        starts, n = cellStarts(s)
        count = #starts
    end
    if i < 0 then i = count + i + 1 end
    if j < 0 then j = count + j + 1 end
    if i < 1 then i = 1 end
    if j > count then j = count end
    if i > j then
        local at = starts and (starts[i] or n + 1) or math.min(i, n + 1)
        return at, at - 1
    end
    if not starts then return i, j end
    return starts[i], (starts[j + 1] or (n + 1)) - 1
end

--- Substring by cells, with string.sub's rules for i and j.
---@param s string|number
---@param i? integer First cell (default 1; negative counts from the end)
---@param j? integer Last cell (default -1)
---@return string
function textutil.sub(s, i, j)
    s = str(s)
    if not utf8Mode or isByteCells(s) then
        return sub(s, i or 1, j or -1)
    end
    local first, last = textutil.span(s, i, j)
    return sub(s, first, last)
end

--- Byte index where cell `cell` starts; past the end it counts on from
--- byteLen + 1 as if the string went on in single-byte cells, and before
--- cell 1 it returns `cell` unchanged.
---@param s string
---@param cell integer One-based cell index
---@return integer
function textutil.offset(s, cell)
    cell = floor(cell)
    if cell < 1 or not utf8Mode or isByteCells(s) then
        return cell
    end
    local starts, n = cellStarts(s)
    if cell <= #starts then
        return starts[cell]
    end
    return n + 1 + (cell - #starts - 1)
end

--- The cells of s, in order.
---@param s string|number
---@return string[]
function textutil.cells(s)
    s = str(s)
    local out = {}
    if not utf8Mode or isByteCells(s) then
        for i = 1, byteLen(s) do out[i] = sub(s, i, i) end
        return out
    end
    local i, n = 1, byteLen(s)
    while i <= n do
        local len = cellLen(s, i, n)
        out[#out + 1] = sub(s, i, i + len - 1)
        i = i + len
    end
    return out
end

-- UTF-8 encoding of a CC-charset byte 0x80-0xFF read as U+0080-U+00FF
local function latin1(b)
    return char(0xC0 + floor(b / 64), 0x80 + b % 64)
end

--- The form of s that is safe to draw next to other text: with the Unicode
--- mod, a byte 0xC2-0xF4 that does not start a valid sequence becomes its
--- UTF-8 encoding (the mod draws U+00C2-U+00F4 like the CC glyph). Joining
--- normalized strings never merges cells, so the width of a joined string
--- is the sum of the widths. Identity without the mod.
---@param s string|number
---@return string
function textutil.normalize(s)
    s = str(s)
    if not utf8Mode or isByteCells(s) then
        return s
    end
    local out, i, n, runStart = nil, 1, byteLen(s), 1
    while i <= n do
        local b = byte(s, i)
        local len = cellLen(s, i, n)
        if len == 1 and b >= 0xC2 and b <= 0xF4 then
            out = out or {}
            out[#out + 1] = sub(s, runStart, i - 1)
            out[#out + 1] = latin1(b)
            runStart = i + 1
        end
        i = i + len
    end
    if not out then return s end
    out[#out + 1] = sub(s, runStart)
    return concat(out)
end

--- s with cells i..j replaced by piece (j = i - 1 inserts before cell i).
--- All parts are normalized, so cells never merge across the joins.
---@param s string
---@param i integer First cell to replace
---@param j integer Last cell to replace
---@param piece string|number Replacement
---@return string
function textutil.splice(s, i, j, piece)
    piece = textutil.normalize(piece)
    if not utf8Mode or (isByteCells(s) and isByteCells(piece)) then
        return sub(s, 1, i - 1) .. piece .. sub(s, j + 1)
    end
    s = textutil.normalize(s)
    local before = i > 1 and textutil.sub(s, 1, i - 1) or ""
    return before .. piece .. textutil.sub(s, j + 1)
end

--- s cut or padded with spaces to exactly n cells.
---@param s string|number
---@param n integer
---@param align? "left"|"right"|"center" Where s goes (default left)
---@return string
function textutil.pad(s, n, align)
    s = str(s)
    local w = textutil.width(s)
    if w > n then
        return textutil.sub(s, 1, n)
    end
    local space = n - w
    if align == "right" then
        return rep(" ", space) .. s
    elseif align == "center" then
        local left = floor(space / 2)
        return rep(" ", left) .. s .. rep(" ", space - left)
    end
    return s .. rep(" ", space)
end

--- Text from a char or paste event, in the form Basalt stores: with the
--- Unicode mod, characters that CC's charset has arrive as one legacy byte
--- (é = "\233") and others as UTF-8; legacy bytes 0xA0-0xFF become UTF-8,
--- so the stored text is UTF-8. (The mod never sends U+0080-U+00FF as UTF-8,
--- so a two-byte sequence that looks like one is two legacy characters.)
--- Apply it exactly once per event payload: it is not idempotent (a second
--- pass turns the UTF-8 "é" into the two characters "Ã©"). Elements that
--- store typed text call it; events passed on to user code stay raw.
--- Identity without the mod.
---@param s string|number
---@return string
function textutil.fromInput(s)
    s = str(s)
    if not utf8Mode or isPlain(s) then
        return s
    end
    local out, i, n = {}, 1, byteLen(s)
    while i <= n do
        local b = byte(s, i)
        local len = cellLen(s, i, n)
        if len > 2 or (len == 2 and b > 0xC3) then
            out[#out + 1] = sub(s, i, i + len - 1)
            i = i + len
        else
            out[#out + 1] = b >= 0xA0 and latin1(b) or char(b)
            i = i + 1
        end
    end
    return concat(out)
end

--- One CC-charset byte per cell -> drawing form: with the Unicode mod,
--- bytes 0xA0-0xFF become UTF-8 (so "\195\169" stays the two characters
--- "Ã©" instead of being read as "é"). Identity without the mod.
---@param s string|number
---@return string
function textutil.fromLegacy(s)
    s = str(s)
    if not utf8Mode or isPlain(s) then
        return s
    end
    return (s:gsub("[\160-\255]", function(c) return latin1(byte(c)) end))
end

--- One CC-charset byte per cell: a single-byte cell stays as it is, a UTF-8
--- character up to U+00FF becomes its CC byte, anything else becomes "?".
---@param s string|number
---@return string
function textutil.toLegacy(s)
    s = str(s)
    if not utf8Mode or isByteCells(s) then
        return s
    end
    local out, i, n = {}, 1, byteLen(s)
    while i <= n do
        local len = cellLen(s, i, n)
        if len == 1 then
            out[#out + 1] = sub(s, i, i)
        elseif len == 2 and byte(s, i) <= 0xC3 then
            out[#out + 1] = char((byte(s, i) - 0xC0) * 64 + byte(s, i + 1) - 0x80)
        else
            out[#out + 1] = "?"
        end
        i = i + len
    end
    return concat(out)
end

--- One cell for a character code: 0-255 are CC-charset characters; above
--- that, with the Unicode mod, the Unicode character, else "?".
---@param code integer
---@return string
function textutil.char(code)
    code = floor(code)
    if code >= 0 and code <= 255 then
        return textutil.fromLegacy(char(code))
    end
    if not utf8Mode or code < 0 or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF) then
        return "?"
    end
    if code < 0x800 then
        return char(0xC0 + floor(code / 64), 0x80 + code % 64)
    elseif code < 0x10000 then
        return char(0xE0 + floor(code / 4096), 0x80 + floor(code / 64) % 64, 0x80 + code % 64)
    end
    return char(0xF0 + floor(code / 262144), 0x80 + floor(code / 4096) % 64,
        0x80 + floor(code / 64) % 64, 0x80 + code % 64)
end

--- Lower case for comparisons: ASCII letters, and with the Unicode mod also
--- the UTF-8 Latin-1 letters (À-Þ). Other bytes are kept, so UTF-8 stays
--- intact (string.lower may fold single bytes >= 0x80).
---@param s string|number
---@return string
function textutil.lower(s)
    s = str(s)
    if isPlain(s) then
        return (s:lower())
    end
    s = s:gsub("[A-Z]", function(c) return char(byte(c) + 32) end)
    if utf8Mode then
        s = s:gsub("\195([\128-\158])", function(c)
            if c == "\151" then return nil end -- U+00D7, the multiplication sign
            return "\195" .. char(byte(c) + 32)
        end)
    end
    return s
end

--- Greedily word-wraps text by cells; long words are hard-broken and blank
--- lines kept.
---@param s string|number Input text
---@param width integer Maximum line width in cells
---@return TextLines lines Always contains at least one line
function textutil.wrap(s, width)
    width = math.max(1, width)
    local measure, cut = textutil.width, textutil.sub
    ---@type TextLines
    local lines = {}
    for paragraph in (str(s) .. "\n"):gmatch("(.-)\n") do
        local line, lineWidth = "", 0
        for word in paragraph:gmatch("%S+") do
            local wordWidth = measure(word)
            if lineWidth == 0 then
                line, lineWidth = word, wordWidth
            elseif lineWidth + 1 + wordWidth <= width then
                line, lineWidth = line .. " " .. word, lineWidth + 1 + wordWidth
            else
                lines[#lines + 1] = line
                line, lineWidth = word, wordWidth
            end
            while lineWidth > width do -- hard-break oversized words
                lines[#lines + 1] = cut(line, 1, width)
                line = cut(line, width + 1)
                lineWidth = lineWidth - width
            end
        end
        lines[#lines + 1] = line
    end
    if #lines > 1 and lines[#lines] == "" then
        table.remove(lines) -- trailing newline artifact
    end
    if #lines == 0 then lines = { "" } end
    return lines
end

return textutil
