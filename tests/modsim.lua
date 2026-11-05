-- tests/modsim.lua
-- Simulates the "CC: Tweaked Unicode Support" mod for the headless tests
-- (CraftOS-PC has no such mod). Load it from a suite with:
--   local M = assert(loadfile(T.root .. "/tests/modsim.lua", nil, _ENV))(T)
--
-- M.loadBasalt()      a fresh Basalt that sees the mod: the `unicode` global
--                     exists and `#` counts like the mod's (see below)
-- M.frame(w, h)       basalt, frame, term on a strict mod terminal (below)
-- M.term(w, h)        a terminal that decodes UTF-8 like the mod's native
--                     terminal, and is as strict about blit lengths
-- M.window(w, h)      an invisible window that stores its rows like the
--                     mod's window API (Program runs programs in one)
-- M.cells(s)          the cells of s, decoded independently of Basalt
-- M.row(t, y)         a terminal row, trailing spaces removed
-- M.modlen            tests/modlen.lua (M.modlen.len is the mod's `#`)
--
-- With the mod, the native term.blit decodes the text into cells (a
-- well-formed UTF-8 sequence is one cell, any other byte one cell) and
-- raises "Arguments must be the same length" unless the fg and bg strings
-- have as many BYTES as the text has CELLS. The mod also changes `#` on a
-- string: it counts code points when the whole string is well-formed UTF-8,
-- else bytes; string.len counts characters; string.sub, find and byte stay
-- byte-based. Lua cannot override `#` for strings, so M.loadBasalt loads
-- every Basalt file with `#` rewritten to a call of the mod's length
-- (tests/modlen.lua). This file counts bytes with find (byteLen), which
-- means the same with or without the mod.

local T = ...
local M = {}

local ML = assert(loadfile(T.root .. "/tests/modlen.lua", nil, _ENV))()
M.modlen = ML

-- Byte length of s (string.find is byte-based, with or without the mod)
local function byteLen(s)
    return (select(2, s:find("$")))
end

--- The cells of s: a well-formed UTF-8 sequence is one cell, any other
--- byte is one cell (the mod's decoder rules).
---@param s string
---@return string[]
function M.cells(s)
    local out, i, n = {}, 1, byteLen(s)
    while i <= n do
        local len = ML.seqLen(s, i, n)
        out[#out + 1] = s:sub(i, i + len - 1)
        i = i + len
    end
    return out
end

-- Cells i..j of s, with string.sub's rules for i and j (the mod's
-- unicode.sub)
local function cellSub(s, i, j)
    local cells = M.cells(s)
    local n = #cells
    i, j = i or 1, j or -1
    if i < 0 then i = n + i + 1 end
    if j < 0 then j = n + j + 1 end
    if i < 1 then i = 1 end
    if j > n then j = n end
    if i > j then return "" end
    return table.concat(cells, "", i, j)
end

-- The fake mod's global: Basalt only checks that it exists
local fakeUnicode = {
    len = function(s) return #M.cells(s) end,
    sub = cellSub,
}

-- Rewritten sources by path (the files don't change during a run)
local rewritten = {}

-- A loadfile for Basalt under the mod: the file's source with `#`
-- rewritten to __modlen (tests/modlen.lua), loaded into env, which defaults
-- to modEnv. Takes loadfile's arguments (path, mode, env) or (path, env).
local function modLoader(modEnv)
    return function(path, mode, env)
        if type(mode) == "table" and env == nil then mode, env = nil, mode end
        local src = rewritten[path]
        if not src then
            local file = fs.open(path, "rb")
            if not file then return nil, "File not found" end
            src = ML.rewrite(file.readAll())
            file.close()
            rewritten[path] = src
        end
        return load(src, "@/" .. fs.combine(path, ""), mode or "t", env or modEnv)
    end
end

--- A fresh Basalt that sees the mod. init.lua and every module it loads run
--- in an environment with the `unicode` global (the text module detects the
--- mod once, at load), with `#` counting like the mod's (__modlen), and with
--- a loadfile that gives the same to the modules it loads.
---@return table basalt
function M.loadBasalt()
    local env = setmetatable({ __modlen = ML.len, unicode = fakeUnicode }, { __index = _ENV })
    env.loadfile = modLoader(env)
    local initPath = T.src .. "/init.lua"
    local basalt = assert(env.loadfile(initPath, nil, env))("basalt", initPath)
    assert(basalt.text.isUtf8(), "the text module did not detect the mod")
    return basalt
end

local HEX = "0123456789abcdef"
local function hexOf(colour)
    local i = 0
    while colour > 1 do
        colour = colour / 2
        i = i + 1
    end
    return HEX:sub(i + 1, i + 1)
end

-- Size, cursor, colour and palette methods of a terminal; st holds the
-- cursor (x, y, blink) and the colours (fg, bg)
local function addTermMethods(t, st, w, h)
    local palette = {}
    function t.getSize() return w, h end
    function t.setCursorPos(x, y) st.x, st.y = math.floor(x), math.floor(y) end
    function t.getCursorPos() return st.x, st.y end
    function t.setCursorBlink(b) st.blink = b end
    function t.getCursorBlink() return st.blink end
    function t.isColour() return true end
    t.isColor = t.isColour
    function t.setTextColour(c) st.fg = c end
    t.setTextColor = t.setTextColour
    function t.getTextColour() return st.fg end
    t.getTextColor = t.getTextColour
    function t.setBackgroundColour(c) st.bg = c end
    t.setBackgroundColor = t.setBackgroundColour
    function t.getBackgroundColour() return st.bg end
    t.getBackgroundColor = t.getBackgroundColour
    function t.setPaletteColour(c, r, g, b)
        if g == nil then
            palette[c] = { colours.unpackRGB(r) }
        else
            palette[c] = { r, g, b }
        end
    end
    t.setPaletteColor = t.setPaletteColour
    function t.getPaletteColour(c)
        local p = palette[c]
        if p then return p[1], p[2], p[3] end
        return term.nativePaletteColour(c)
    end
    t.getPaletteColor = t.getPaletteColour
end

local function newState()
    return { x = 1, y = 1, blink = false, fg = colours.white, bg = colours.black }
end

--- A terminal like the mod's native one: cells are decoded UTF-8, and blit
--- is strict about lengths. getLine returns the cells joined, and fg/bg as
--- blit hex strings with one character per cell.
---@param w integer
---@param h integer
---@return table term
function M.term(w, h)
    local t, st = { blits = 0 }, newState()
    local rows = {}

    local function blank(y)
        local cells, fg, bg = {}, {}, {}
        for x = 1, w do cells[x], fg[x], bg[x] = " ", hexOf(st.fg), hexOf(st.bg) end
        rows[y] = { cells = cells, fg = fg, bg = bg }
    end
    for y = 1, h do blank(y) end

    local function put(cells, fgs, bgs)
        local row = rows[st.y]
        for k = 1, #cells do
            local x = st.x + k - 1
            if row and x >= 1 and x <= w then
                row.cells[x], row.fg[x], row.bg[x] = cells[k], fgs[k], bgs[k]
            end
        end
        st.x = st.x + #cells
    end

    function t.write(s)
        local cells = M.cells(tostring(s))
        local fgs, bgs = {}, {}
        for k = 1, #cells do fgs[k], bgs[k] = hexOf(st.fg), hexOf(st.bg) end
        put(cells, fgs, bgs)
    end

    function t.blit(text, fg, bg)
        local cells = M.cells(text)
        if #cells ~= byteLen(fg) or #cells ~= byteLen(bg) then
            error("Arguments must be the same length", 2)
        end
        local fgs, bgs = {}, {}
        for k = 1, #cells do fgs[k], bgs[k] = fg:sub(k, k), bg:sub(k, k) end
        t.blits = t.blits + 1
        put(cells, fgs, bgs)
    end

    function t.getLine(y)
        local row = rows[y]
        return table.concat(row.cells), table.concat(row.fg), table.concat(row.bg)
    end

    function t.clear() for y = 1, h do blank(y) end end
    function t.clearLine() blank(st.y) end
    function t.scroll(n)
        for _ = 1, n do
            table.remove(rows, 1)
            blank(h)
        end
    end
    addTermMethods(t, st, w, h)
    return t
end

--- An invisible window that keeps its rows the way the mod's window API
--- does (Program runs its program in one). A row is three strings: text,
--- and fg/bg blit colours.
--- * A write that covers the whole row replaces it.
--- * Any other write keeps the text before and after it, cut by cells (the
---   mod's unicode.sub), and the colours before and after it, cut by bytes,
---   and joins the pieces.
--- * A row is never padded back to the window width (the mod only does that
---   when it draws a visible window), and reposition does nothing.
--- So bytes from separate writes can merge into one cell ("\195" and then
--- "\169" become one "é"), and a row can have fewer cells than colour
--- bytes. getLine returns the three strings as they are stored.
---@param w integer
---@param h integer
---@return table window
function M.window(w, h)
    local win, st = {}, newState()
    local rows = {}
    local visible = false

    local function blank()
        return { (" "):rep(w), hexOf(st.fg):rep(w), hexOf(st.bg):rep(w) }
    end
    for y = 1, h do rows[y] = blank() end

    -- Puts text at the cursor; fg and bg have one byte per cell of text
    local function put(text, fg, bg)
        local n = #M.cells(text)
        local first, last = st.x, st.x + n - 1
        local row = rows[st.y]
        if row and first <= w and last >= 1 then
            if first == 1 and last == w then
                rows[st.y] = { text, fg, bg }
            else
                if first < 1 or last > w then
                    local i, j = math.max(1, 2 - first), math.min(n, w - first + 1)
                    text, fg, bg = cellSub(text, i, j), fg:sub(i, j), bg:sub(i, j)
                end
                if first > 1 then
                    text = cellSub(row[1], 1, first - 1) .. text
                    fg = row[2]:sub(1, first - 1) .. fg
                    bg = row[3]:sub(1, first - 1) .. bg
                end
                if last < w then
                    text = text .. cellSub(row[1], last + 1, w)
                    fg = fg .. row[2]:sub(last + 1, w)
                    bg = bg .. row[3]:sub(last + 1, w)
                end
                rows[st.y] = { text, fg, bg }
            end
        end
        st.x = last + 1
    end

    -- A colour string cut or padded to n bytes (padded with its last byte,
    -- or the current colour when it is empty)
    local function fitColours(plane, n, colour)
        local len = byteLen(plane)
        if len >= n then return plane:sub(1, n):lower() end
        local fill = len > 0 and plane:sub(len, len) or hexOf(colour)
        return (plane .. fill:rep(n - len)):lower()
    end

    function win.write(s)
        s = tostring(s)
        local n = #M.cells(s)
        put(s, hexOf(st.fg):rep(n), hexOf(st.bg):rep(n))
    end

    function win.blit(text, fg, bg)
        local n = #M.cells(text)
        put(text, fitColours(fg, n, st.fg), fitColours(bg, n, st.bg))
    end

    function win.getLine(y)
        local row = rows[y]
        if not row then error("Line is out of range.", 2) end
        return row[1], row[2], row[3]
    end

    function win.clear() for y = 1, h do rows[y] = blank() end end
    function win.clearLine()
        if rows[st.y] then rows[st.y] = blank() end
    end
    function win.scroll(n)
        local moved = {}
        for y = 1, h do moved[y] = rows[y + n] or blank() end
        rows = moved
    end
    function win.reposition() end
    function win.setVisible(v) visible = v end
    function win.isVisible() return visible end
    function win.redraw() end
    function win.restoreCursor() end
    function win.getPosition() return 1, 1 end
    addTermMethods(win, st, w, h)
    return win
end

--- A fresh Basalt that sees the mod, with a root frame on a strict mod
--- terminal.
---@return table basalt, table frame, table term
function M.frame(w, h)
    local basalt = M.loadBasalt()
    local t = M.term(w or 51, h or 19)
    local frame = basalt.createFrame(t)
    return basalt, frame, t
end

--- One row of a (mod) terminal, trailing spaces removed.
function M.row(t, y)
    return ((t.getLine(y)):gsub("%s+$", ""))
end

return M
