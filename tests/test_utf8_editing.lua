-- tests/test_utf8_editing.lua
-- Input, TextBox and ComboBox with the Unicode Support mod: cursor, scroll
-- and selection positions are cells, edits never split or merge UTF-8
-- characters, typed and pasted text is converted from its mixed encodings,
-- and every blit stays valid on the mod's strict terminal. Without the mod
-- a byte is a cell, as before.

return function(T)
    local M = assert(loadfile(T.root .. "/tests/modsim.lua", nil, _ENV))(T)

    local E = "\195\169"             -- é as UTF-8
    local LEGACY_E = "\233"          -- é as a char event delivers it
    local E_UPPER = "\195\137"       -- É as UTF-8
    local DASH = "\226\128\148"      -- em dash (not in CC's charset)
    local EMOJI = "\240\159\152\128" -- U+1F600
    local EURO = "\226\130\172"
    local DEG = "\194\176"           -- ° as UTF-8 (legacy "\176")
    local BULLET = "\226\128\162"

    -- Every row of the buffer: text cells == fg bytes == bg bytes == width
    local function checkRows(basalt, frame)
        local text, render = basalt.text, rawget(frame, "_render")
        basalt.update()
        for y = 1, render.height do
            T.eq(text.width(render.text[y]), render.width, "text cells in row " .. y)
            T.eq(text.byteLen(render.fg[y]), render.width, "fg bytes in row " .. y)
            T.eq(text.byteLen(render.bg[y]), render.width, "bg bytes in row " .. y)
        end
    end

    -- The cells x..x+n-1 of a terminal row
    local function cellsAt(t, y, x, n)
        local cells = M.cells((t.getLine(y)))
        return table.concat(cells, "", x, x + n - 1)
    end

    -- Sends each character as its own char event (whole UTF-8 sequences)
    local function typeChars(basalt, ...)
        for _, ch in ipairs({ ... }) do basalt.update("char", ch) end
    end

    local function key(basalt, name, times)
        for _ = 1, times or 1 do basalt.update("key", keys[name]) end
    end

    -- a focused input at x 1, y 1 on a strict mod terminal
    local function modInput(props, w, h)
        local basalt, frame, t = M.frame(w or 20, h or 4)
        props = props or {}
        props.x, props.y, props.width = props.x or 1, props.y or 1, props.width or 10
        local input = frame:addInput(props)
        basalt.update()
        T.click(basalt, 1, props.y)
        return basalt, frame, input, t
    end

    ---------------------------------------------------------------- Input

    T.test("input: é, an em dash and an emoji are one cell each", function()
        local basalt, frame, input, t = modInput()
        typeChars(basalt, LEGACY_E, DASH, EMOJI, "a")
        T.eq(input.text, E .. DASH .. EMOJI .. "a", "typed legacy é is stored as UTF-8")
        T.eq(input._cursor, 5)
        T.eq(cellsAt(t, 1, 1, 4), E .. DASH .. EMOJI .. "a")
        T.eq(rawget(frame, "_render").cursorX, 5, "cursor after the 4th cell")
        checkRows(basalt, frame)
    end)

    T.test("input: inserting after a euro sign keeps it whole", function()
        local basalt, frame, input = modInput()
        typeChars(basalt, EURO, "a")
        T.eq(input.text, EURO .. "a")
        T.eq(input._cursor, 3, "the cursor is a cell position")
        key(basalt, "left")
        T.eq(input._cursor, 2)
        typeChars(basalt, "b")
        T.eq(input.text, EURO .. "ba")
        T.eq(rawget(frame, "_render").cursorX, 3)
        checkRows(basalt, frame)
    end)

    T.test("input: typed legacy bytes never merge into one character", function()
        local basalt, frame, input, t = modInput()
        -- é, °, ° as legacy bytes would read as one CJK character
        typeChars(basalt, LEGACY_E, "\176", "\176")
        T.eq(input.text, E .. DEG .. DEG)
        T.eq(basalt.text.width(input.text), 3)
        T.eq(input._cursor, 4)
        T.eq(cellsAt(t, 1, 1, 3), E .. DEG .. DEG)
        checkRows(basalt, frame)
    end)

    T.test("input: arrows, backspace and delete step over whole characters", function()
        local basalt, frame, input = modInput()
        input.text = "a" .. E .. DASH .. EMOJI .. "b"
        key(basalt, "end")
        T.eq(input._cursor, 6)
        key(basalt, "backspace")
        T.eq(input.text, "a" .. E .. DASH .. EMOJI)
        key(basalt, "backspace")
        T.eq(input.text, "a" .. E .. DASH, "the emoji is removed whole")
        key(basalt, "left")
        T.eq(input._cursor, 3)
        key(basalt, "delete")
        T.eq(input.text, "a" .. E, "the dash is removed whole")
        typeChars(basalt, "x")
        T.eq(input.text, "a" .. E .. "x")
        key(basalt, "home")
        key(basalt, "right", 2)
        key(basalt, "backspace")
        T.eq(input.text, "ax")
        T.eq(input._cursor, 2)
        checkRows(basalt, frame)
    end)

    T.test("input: a click places the cursor by cell", function()
        local basalt, frame, input = modInput()
        input.text = E .. DASH .. "abc"
        T.click(basalt, 3, 1)
        T.eq(input._cursor, 3)
        typeChars(basalt, "x")
        T.eq(input.text, E .. DASH .. "xabc")
        checkRows(basalt, frame)
    end)

    T.test("input: horizontal scrolling counts cells", function()
        local basalt, frame, input, t = modInput({ width = 5 })
        for _ = 1, 4 do typeChars(basalt, LEGACY_E) end
        for _ = 1, 4 do typeChars(basalt, DASH) end
        T.eq(input._cursor, 9)
        T.eq(input._scroll, 4)
        T.eq(cellsAt(t, 1, 1, 5), DASH:rep(4) .. " ", "the last 4 cells and the cursor cell")
        T.eq(rawget(frame, "_render").cursorX, 5)
        key(basalt, "home")
        T.eq(input._scroll, 0)
        T.eq(cellsAt(t, 1, 1, 5), E:rep(4) .. DASH)
        checkRows(basalt, frame)
    end)

    T.test("input: a paste with mixed encodings is stored as UTF-8", function()
        local basalt, frame, input, t = modInput({ width = 12 })
        basalt.update("paste", "caf" .. LEGACY_E .. " " .. DASH .. " " .. EMOJI)
        T.eq(input.text, "caf" .. E .. " " .. DASH .. " " .. EMOJI)
        T.eq(input._cursor, 9)
        T.eq(cellsAt(t, 1, 1, 8), "caf" .. E .. " " .. DASH .. " " .. EMOJI)
        -- the mod never sends U+0080-U+00FF as UTF-8, so this is "Ã©"
        basalt.update("paste", "\195\169")
        T.eq(input._cursor, 11)
        checkRows(basalt, frame)
    end)

    T.test("input: maxLength counts characters", function()
        local basalt, frame, input = modInput({ maxLength = 3 })
        typeChars(basalt, LEGACY_E, DASH, EMOJI)
        T.eq(input.text, E .. DASH .. EMOJI)
        typeChars(basalt, "x")
        T.eq(input.text, E .. DASH .. EMOJI, "full")
        key(basalt, "backspace")
        basalt.update("paste", E .. "y")
        T.eq(input.text, E .. DASH, "a paste longer than the room is rejected")
        basalt.update("paste", EURO)
        T.eq(input.text, E .. DASH .. EURO)
        checkRows(basalt, frame)
    end)

    T.test("input: a pattern keeps or drops whole characters", function()
        local basalt, frame, input = modInput({ pattern = "[%d\192-\255]" })
        basalt.update("paste", "1" .. LEGACY_E .. "x" .. DASH .. "2")
        T.eq(input.text, "1" .. E .. DASH .. "2")
        input.pattern = "%d"
        typeChars(basalt, LEGACY_E, EMOJI, "3")
        T.eq(input.text, "1" .. E .. DASH .. "23")
        checkRows(basalt, frame)
    end)

    T.test("input: replaceChar masks with one whole character per cell", function()
        local basalt, frame, input, t = modInput({ replaceChar = BULLET })
        typeChars(basalt, "a", LEGACY_E, DASH, EMOJI)
        basalt.update()
        T.eq(cellsAt(t, 1, 1, 5), BULLET:rep(4) .. " ")
        input.replaceChar = LEGACY_E -- a legacy byte as the mask
        basalt.update()
        T.eq(cellsAt(t, 1, 1, 4), E:rep(4))
        checkRows(basalt, frame)
    end)

    T.test("input: the placeholder is cut by cells", function()
        local basalt, frame, t = M.frame(12, 2)
        frame:addInput({ x = 1, y = 1, width = 5, placeholder = "caf" .. E .. DASH .. "xyz" })
        basalt.update()
        T.eq(cellsAt(t, 1, 1, 6), "caf" .. E .. DASH .. " ")
        checkRows(basalt, frame)
    end)

    T.test("input: assigned text is stored in its drawing form", function()
        local basalt, frame, input = modInput()
        typeChars(basalt, "a", "b", "c", "d", "e")
        T.eq(input._cursor, 6)
        input.text = "x" .. LEGACY_E
        T.eq(input.text, "x" .. E, "the stray lead byte becomes UTF-8")
        T.eq(input._cursor, 3, "the cursor is clamped to the cells")
        typeChars(basalt, "\169") -- a legacy © must not merge with é
        T.eq(input.text, "x" .. E .. "\194\169")
        T.eq(basalt.text.width(input.text), 3)
        checkRows(basalt, frame)
    end)

    T.test("input: measure counts cells", function()
        local _, _, input = modInput({ text = E .. DASH .. EMOJI, placeholder = "ab" })
        T.eq(input:measure(), 3)
        input.placeholder = DASH:rep(5)
        T.eq(input:measure(), 5)
        input.text = 12345678
        T.eq(input:measure(), 8, "a number text is measured too")
    end)

    ---------------------------------------------------------------- TextBox

    -- a focused 10x4 text box at the top-left corner
    local function modTextBox(text, w)
        local basalt, frame, t = M.frame(20, 6)
        local tb = frame:addTextBox({ x = 1, y = 1, width = w or 10, height = 4,
            scrollbar = "hidden" })
        if text then tb.text = text end
        basalt.update()
        T.click(basalt, 1, 1)
        return basalt, frame, tb, t
    end

    T.test("textbox: typing, enter and the cursor work in cells", function()
        local basalt, frame, tb, t = modTextBox()
        typeChars(basalt, LEGACY_E, DASH, EMOJI, "a")
        T.eq(tb.text, E .. DASH .. EMOJI .. "a")
        T.eq(tb._curCol, 5)
        T.eq(rawget(frame, "_render").cursorX, 5)
        key(basalt, "left", 2)
        key(basalt, "enter")
        T.eq(tb.text, E .. DASH .. "\n" .. EMOJI .. "a")
        T.eq(tb._curLine, 2); T.eq(tb._curCol, 1)
        T.eq(cellsAt(t, 1, 1, 2), E .. DASH)
        T.eq(cellsAt(t, 2, 1, 2), EMOJI .. "a")
        checkRows(basalt, frame)
    end)

    T.test("textbox: backspace and delete remove whole characters and join lines", function()
        local basalt, frame, tb = modTextBox("a" .. E .. DASH .. "\n" .. EMOJI .. "b")
        key(basalt, "end")
        T.eq(tb._curCol, 4)
        key(basalt, "backspace")
        T.eq(tb.text, "a" .. E .. "\n" .. EMOJI .. "b")
        key(basalt, "delete") -- joins the next line
        T.eq(tb.text, "a" .. E .. EMOJI .. "b")
        T.eq(tb._curCol, 3)
        key(basalt, "delete")
        T.eq(tb.text, "a" .. E .. "b")
        key(basalt, "left")
        key(basalt, "backspace")
        T.eq(tb.text, E .. "b")
        T.eq(tb._curCol, 1)
        checkRows(basalt, frame)
    end)

    T.test("textbox: joined lines never merge their edge bytes", function()
        -- a legacy Ã at the end of one line and a legacy © at the start of
        -- the next would read as é when the raw bytes are joined
        local basalt, frame, tb = modTextBox("x\195\ny\n\169z")
        T.eq(tb.text, "x\195\131\ny\n\169z", "stored in its drawing form")
        key(basalt, "down", 2)
        key(basalt, "backspace") -- joins lines 2 and 3
        key(basalt, "backspace") -- removes "y"
        key(basalt, "backspace") -- joins with the first line
        T.eq(tb.text, "x\195\131\169z")
        T.eq(tb._curCol, 3)
        T.eq(basalt.text.width(tb._lines[1]), 4)
        key(basalt, "enter") -- and splits it again at the same cell
        T.eq(tb.text, "x\195\131\n\169z")
        checkRows(basalt, frame)
    end)

    T.test("textbox: up and down keep the cell column", function()
        local basalt, frame, tb = modTextBox(DASH:rep(3) .. "z\nabcdefghij")
        key(basalt, "end")
        T.eq(tb._curCol, 5)
        key(basalt, "down")
        T.eq(tb._curCol, 5)
        key(basalt, "right", 3)
        key(basalt, "up")
        T.eq(tb._curCol, 5, "clamped to the end of the dash line")
        key(basalt, "left", 2)
        key(basalt, "down")
        T.eq(tb._curCol, 3)
        key(basalt, "home")
        key(basalt, "left") -- to the end of the previous line
        T.eq(tb._curLine, 1); T.eq(tb._curCol, 5)
        key(basalt, "right") -- and back to the start of the next one
        T.eq(tb._curLine, 2); T.eq(tb._curCol, 1)
        checkRows(basalt, frame)
    end)

    T.test("textbox: shift selection, copy, cut and typing over it", function()
        local basalt, frame, tb = modTextBox("a" .. E .. DASH .. "\n" .. EMOJI .. "bc")
        key(basalt, "right")
        basalt.update("key", keys.leftShift)
        key(basalt, "right", 2)
        T.eq(tb:getSelection(), E .. DASH)
        key(basalt, "down")
        T.eq(tb:getSelection(), E .. DASH .. "\n" .. EMOJI .. "bc")
        key(basalt, "left", 2)
        T.eq(tb:getSelection(), E .. DASH .. "\n" .. EMOJI)
        basalt.update("key_up", keys.leftShift)
        basalt.update("key", keys.leftCtrl)
        key(basalt, "c")
        basalt.update("key_up", keys.leftCtrl)
        T.eq(tb:getClipboard(), E .. DASH .. "\n" .. EMOJI)
        typeChars(basalt, LEGACY_E)
        T.eq(tb.text, "a" .. E .. "bc")
        T.eq(tb._curCol, 3)
        checkRows(basalt, frame)
    end)

    T.test("textbox: mouse clicks and drags map to cells", function()
        local basalt, frame, tb = modTextBox(E .. DASH .. "abc")
        basalt.update("mouse_click", 1, 3, 1)
        basalt.update("mouse_drag", 1, 5, 1)
        basalt.update("mouse_up", 1, 5, 1)
        T.eq(tb:getSelection(), "ab")
        basalt.update("mouse_click", 1, 2, 1)
        basalt.update("mouse_drag", 1, 9, 1) -- past the end: clamped
        basalt.update("mouse_up", 1, 9, 1)
        T.eq(tb:getSelection(), DASH .. "abc")
        key(basalt, "backspace")
        T.eq(tb.text, E)
        checkRows(basalt, frame)
    end)

    T.test("textbox: the selection overlay covers whole cells and the newline", function()
        local basalt, frame, tb, t = modTextBox(E .. DASH .. "\n" .. EMOJI .. "x")
        basalt.update("key", keys.leftCtrl)
        key(basalt, "a")
        basalt.update("key_up", keys.leftCtrl)
        basalt.update()
        local _, _, bg1 = t.getLine(1)
        local _, _, bg2 = t.getLine(2)
        T.eq(bg1:sub(1, 4), "bbbf", "line 1: 2 cells + the newline cell")
        T.eq(bg2:sub(1, 3), "bbf", "line 2: 2 cells")
        T.eq(cellsAt(t, 1, 1, 3), E .. DASH .. " ")
        -- a selection inside a line, after a multi-byte character
        T.click(basalt, 2, 1)
        basalt.update("key", keys.leftShift)
        key(basalt, "right")
        basalt.update("key_up", keys.leftShift)
        T.eq(tb:getSelection(), DASH)
        basalt.update()
        _, _, bg1 = t.getLine(1)
        T.eq(bg1:sub(1, 3), "fbf")
        checkRows(basalt, frame)
    end)

    T.test("textbox: horizontal scrolling counts cells", function()
        local basalt, frame, tb, t = modTextBox(nil, 5)
        for _ = 1, 4 do typeChars(basalt, LEGACY_E) end
        for _ = 1, 4 do typeChars(basalt, DASH) end
        T.eq(tb._curCol, 9)
        T.eq(tb._viewX, 4)
        T.eq(cellsAt(t, 1, 1, 5), DASH:rep(4) .. " ")
        T.eq(rawget(frame, "_render").cursorX, 5)
        key(basalt, "home")
        T.eq(tb._viewX, 0)
        T.eq(cellsAt(t, 1, 1, 5), E:rep(4) .. DASH)
        checkRows(basalt, frame)
    end)

    T.test("textbox: pastes are converted; measure counts cells", function()
        local basalt, frame, tb = modTextBox()
        basalt.update("paste", "caf" .. LEGACY_E .. " " .. DASH .. EMOJI)
        T.eq(tb.text, "caf" .. E .. " " .. DASH .. EMOJI)
        T.eq(tb._curCol, 8)
        local w, h = tb:measure()
        T.eq(w, 8); T.eq(h, 1)
        checkRows(basalt, frame)
    end)

    ---------------------------------------------------------------- ComboBox

    -- a focused 8-wide auto-complete combo box at x 1, y 1
    local function modCombo(items, w)
        local basalt, frame, t = M.frame(20, 8)
        local cbx = frame:addComboBox({ x = 1, y = 1, width = w or 8, autoComplete = true })
        for _, item in ipairs(items) do cbx:addItem(item) end
        basalt.update()
        T.click(basalt, 1, 1)
        return basalt, frame, cbx, t
    end

    local function labels(cbx)
        local out = {}
        for i, entry in ipairs(cbx:getDisplayItems()) do out[i] = entry.text end
        return table.concat(out, ",")
    end

    T.test("combobox: typed legacy é matches UTF-8 labels, ignoring case", function()
        local basalt, frame, cbx = modCombo({ "Caf" .. E, "Cafeteria",
            E_UPPER .. "clair", "Eis" })
        typeChars(basalt, "c", "a", "f", LEGACY_E)
        T.eq(labels(cbx), "Caf" .. E)
        T.eq(cbx.open, true)
        key(basalt, "backspace", 4)
        typeChars(basalt, LEGACY_E)
        T.eq(labels(cbx), E_UPPER .. "clair", "é matches É")
        typeChars(basalt, "\201") -- legacy É
        T.eq(labels(cbx), "", "nothing starts with éÉ")
        checkRows(basalt, frame)
    end)

    T.test("combobox: accepting an entry puts the cursor after its last cell", function()
        local basalt, frame, cbx = modCombo({ DASH .. "x" .. EMOJI, "abc" })
        typeChars(basalt, DASH)
        T.eq(labels(cbx), DASH .. "x" .. EMOJI)
        key(basalt, "enter")
        T.eq(cbx.text, DASH .. "x" .. EMOJI)
        T.eq(cbx._cursor, 4)
        typeChars(basalt, LEGACY_E)
        T.eq(cbx.text, DASH .. "x" .. EMOJI .. E)
        checkRows(basalt, frame)
    end)

    T.test("combobox: list rows are cut by cells", function()
        local basalt, frame, cbx, t = modCombo({ "caf" .. E .. DASH .. "long", "ab" }, 6)
        cbx.open = true
        basalt.update()
        T.eq(cellsAt(t, 2, 1, 6), "caf" .. E .. DASH .. "l")
        T.eq(cellsAt(t, 3, 1, 3), "ab ")
        checkRows(basalt, frame)
    end)

    ---------------------------------------------------------------- vanilla

    T.test("without the mod a byte is a cell, as before", function()
        local basalt, frame, win = T.frame(20, 6)
        T.eq(basalt.text.isUtf8(), false)
        local input = frame:addInput({ x = 1, y = 1, width = 10 })
        basalt.update()
        T.click(basalt, 1, 1)
        basalt.update("char", "\195")
        basalt.update("char", "\169")
        T.eq(input.text, "\195\169", "two legacy characters")
        T.eq(input._cursor, 3)
        key(basalt, "backspace")
        T.eq(input.text, "\195")
        input.text = "x\233"
        T.eq(input.text, "x\233", "assigned text is kept as it is")
        key(basalt, "end")
        T.eq(input._cursor, 3)
        T.eq(T.row(win, 1), "x\233")

        local tb = frame:addTextBox({ x = 1, y = 3, width = 10, height = 2 })
        tb.text = "a\195\n\169b"
        T.eq(tb.text, "a\195\n\169b")
        basalt.update()
        T.click(basalt, 1, 4)
        key(basalt, "backspace")
        T.eq(tb.text, "a\195\169b")
        T.eq(tb._curCol, 3)
        T.eq(tb:measure(), 5)

        local cbx = frame:addComboBox({ x = 12, y = 1, width = 8, autoComplete = true })
        cbx:addItem("Apfel"):addItem("\233clair")
        basalt.update()
        T.click(basalt, 12, 1)
        basalt.update("char", "\233")
        T.eq(#cbx:getDisplayItems(), 1)
        T.eq(cbx:getDisplayItems()[1].text, "\233clair")
    end)
end
