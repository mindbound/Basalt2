-- tests/test_utf8_widgets.lua
-- Simple widgets with the Unicode Support mod: Label, Button, Checkbox,
-- Switch, Slider, ProgressBar, Toast, Dialog, Program and the flex layout
-- measure and draw text in screen cells, and every row they draw stays a
-- valid blit on the mod's strict terminal. Vanilla checks make sure that
-- without the mod nothing changes (one byte = one cell).

return function(T)
    local M = assert(loadfile(T.root .. "/tests/modsim.lua", nil, _ENV))(T)

    local CAFE = "caf\195\169"          -- 4 cells, 5 bytes
    local DASH = "\226\128\148"         -- em dash: 1 cell, 3 bytes
    local EMOJI = "\240\159\152\128"    -- 1 cell, 4 bytes
    local CHECK = "\226\156\147"        -- check mark: 1 cell, 3 bytes
    local LEGACY_E = "\233"             -- e-acute as a CC-charset byte
    local UTF8_E = "\195\169"           -- e-acute in UTF-8

    -- Every row of the buffer: text cells == fg bytes == bg bytes == width
    local function checkRows(basalt, frame)
        local text, render = basalt.text, rawget(frame, "_render")
        for y = 1, render.height do
            T.eq(text.width(render.text[y]), render.width, "text cells in row " .. y)
            T.eq(text.byteLen(render.fg[y]), render.width, "fg bytes in row " .. y)
            T.eq(text.byteLen(render.bg[y]), render.width, "bg bytes in row " .. y)
        end
    end

    -- Every row of the strict terminal has exactly w cells
    local function checkTerm(t)
        local w, h = t.getSize()
        for y = 1, h do
            T.eq(#M.cells((t.getLine(y))), w, "terminal cells in row " .. y)
        end
    end

    -- ---------------------------------------------------------------- Label

    T.test("a label auto-sizes to its text in cells", function()
        local basalt, frame, t = M.frame(20, 3)
        local text = CAFE .. " " .. DASH .. " " .. EMOJI
        local label = frame:addLabel({ x = 2, y = 1, text = text })
        T.eq(label.width, 8, "c a f e-acute space dash space emoji")
        frame:addLabel({ x = 10, y = 1, text = "|" })
        basalt.update()
        T.eq(M.row(t, 1), " " .. text .. "|", "the next label starts right after it")
        label.text = DASH .. EMOJI
        T.eq(label.width, 2, "re-measured when the text changes")
        T.eq(label:measure(), 2, "measure() agrees")
        basalt.update()
        checkRows(basalt, frame)
        checkTerm(t)
    end)

    T.test("a label with a legacy byte next to UTF-8 counts every cell", function()
        local basalt, frame, t = M.frame(12, 2)
        -- one legacy byte makes # count bytes for the whole string under the mod
        local label = frame:addLabel({ x = 1, y = 1, text = "x" .. LEGACY_E .. DASH .. "y" })
        T.eq(label.width, 4)
        frame:addLabel({ x = 5, y = 1, text = "|" })
        basalt.update()
        T.eq(M.row(t, 1), "x" .. UTF8_E .. DASH .. "y|")
        checkRows(basalt, frame)
        checkTerm(t)
    end)

    T.test("a label with a manual width wraps by cells and grows its height", function()
        local basalt, frame, t = M.frame(10, 4)
        local label = frame:addLabel({
            x = 1, y = 1, width = 6,
            text = CAFE .. " " .. DASH .. " na\195\175ve",
        })
        T.eq(label.height, 2, "two wrapped lines")
        basalt.update()
        T.eq(M.row(t, 1), CAFE .. " " .. DASH)
        T.eq(M.row(t, 2), "na\195\175ve")
        checkRows(basalt, frame)
        checkTerm(t)
    end)

    T.test("a label hard-breaks long words between whole characters", function()
        local basalt, frame, t = M.frame(6, 3)
        local label = frame:addLabel({ x = 1, y = 1, width = 3, text = DASH:rep(4) .. EMOJI })
        T.eq(label.height, 2)
        basalt.update()
        T.eq(M.row(t, 1), DASH:rep(3))
        T.eq(M.row(t, 2), DASH .. EMOJI)
        checkRows(basalt, frame)
        checkTerm(t)
    end)

    T.test("a label with a fixed size clips its text by cells", function()
        local basalt, frame, t = M.frame(8, 2)
        frame:addLabel({ x = 1, y = 1, width = 3, height = 1, text = DASH .. CAFE })
        frame:addLabel({ x = 4, y = 1, text = "|" })
        basalt.update()
        T.eq(M.row(t, 1), DASH .. "ca|")
        checkRows(basalt, frame)
        checkTerm(t)
    end)

    -- --------------------------------------------------------------- Button

    T.test("a button centres its text by cells", function()
        local basalt, frame, t = M.frame(10, 3)
        frame:addButton({ x = 1, y = 1, width = 8, height = 1, text = CAFE })
        frame:addButton({ x = 1, y = 2, width = 5, height = 1, text = DASH .. EMOJI })
        basalt.update()
        T.eq(M.row(t, 1), "  " .. CAFE, "(8 - 4) / 2 cells on the left")
        T.eq(M.row(t, 2), " " .. DASH .. EMOJI, "(5 - 2) / 2 cells on the left")
        checkRows(basalt, frame)
        checkTerm(t)
    end)

    T.test("a button narrower than its text clips whole cells", function()
        local basalt, frame, t = M.frame(6, 2)
        -- 5 cells in 3: one cell is cut on the left, one on the right
        frame:addButton({ x = 1, y = 1, width = 3, height = 1, text = "a" .. DASH .. CAFE:sub(1, 3) })
        frame:addLabel({ x = 4, y = 1, text = "|" })
        basalt.update()
        T.eq(M.row(t, 1), DASH .. "ca|")
        checkRows(basalt, frame)
        checkTerm(t)
    end)

    T.test("auto-sized labels and buttons in a row measure cells", function()
        local basalt, frame, t = M.frame(24, 3)
        local row = frame:addRow({ x = 1, y = 1, width = 24, height = 3, gap = 1 })
        local first = row:addLabel({ text = CAFE .. DASH, width = basalt.auto(), height = basalt.auto() })
        local button = row:addButton({ text = EMOJI .. DASH, width = basalt.auto(), height = basalt.auto() })
        local last = row:addLabel({ text = "|", width = basalt.auto(), height = basalt.auto() })
        basalt.update()
        T.eq(first.width, 5)
        T.eq(button.width, 4, "two cells plus padding")
        T.eq(button.x, 7)
        T.eq(last.x, 12)
        T.eq(M.row(t, 1), CAFE .. DASH .. "      |")
        T.eq(M.row(t, 2), "       " .. EMOJI .. DASH)
        checkRows(basalt, frame)
        checkTerm(t)
    end)

    -- ------------------------------------------------------------- Checkbox

    T.test("a checkbox sizes to its label in cells", function()
        local _, frame = M.frame(20, 2)
        local box = frame:addCheckbox({ x = 1, y = 1, text = CAFE })
        T.eq(box.width, 8, "[x] plus 4 cells")
        box.text = "x" .. LEGACY_E .. DASH
        T.eq(box.width, 7)
    end)

    T.test("a checkbox draws a UTF-8 symbol as one whole cell", function()
        local basalt, frame, t = M.frame(12, 3)
        local on = frame:addCheckbox({ x = 1, y = 1, text = CAFE, checked = true,
            checkedSymbol = CHECK .. CHECK })
        frame:addCheckbox({ x = 1, y = 2, text = DASH, uncheckedSymbol = "\215" })
        basalt.update()
        T.eq(M.row(t, 1), "[" .. CHECK .. "] " .. CAFE, "only the first cell")
        T.eq(M.row(t, 2), "[\195\151] " .. DASH, "a legacy symbol is drawn as its glyph")
        on.checked = false
        basalt.update()
        T.eq(M.row(t, 1), "[ ] " .. CAFE)
        checkRows(basalt, frame)
        checkTerm(t)
    end)

    -- ------------------------------------------ Switch, Slider, ProgressBar

    T.test("switch, slider and progress bar rows stay valid next to UTF-8", function()
        local basalt, frame, t = M.frame(14, 6)
        -- a lone lead byte right before the slider's teletext bytes
        frame:addLabel({ x = 1, y = 1, text = LEGACY_E })
        local slider = frame:addSlider({ x = 2, y = 1, width = 6, value = 40 })
        frame:addLabel({ x = 8, y = 1, text = DASH })
        frame:addLabel({ x = 1, y = 2, text = LEGACY_E })
        frame:addSlider({ x = 2, y = 2, width = 1, height = 3, horizontal = false,
            value = 100 })
        frame:addSwitch({ x = 4, y = 2, checked = true })
        frame:addProgressBar({ x = 4, y = 3, width = 8, progress = 50, showPercentage = true })
        frame:addLabel({ x = 12, y = 3, text = EMOJI })
        basalt.update()
        local cells = M.cells((t.getLine(1)))
        T.eq(cells[1], UTF8_E, "the CC letter keeps its own cell")
        T.eq(cells[2], "\140", "the track starts in the next cell")
        T.eq(cells[8], DASH)
        T.eq(M.cells((t.getLine(2)))[1], UTF8_E)
        T.eq(M.cells((t.getLine(2)))[2], "\149", "vertical track")
        T.contains(M.row(t, 3), "50%   " .. EMOJI)
        slider.value = 100
        basalt.update()
        checkRows(basalt, frame)
        checkTerm(t)
    end)

    -- ---------------------------------------------------------------- Toast

    T.test("a toast is as wide as its widest wrapped line in cells", function()
        local basalt, frame, t = M.frame(20, 5)
        local toast = frame:addToast({ maxWidth = 10 })
        toast:show(CAFE .. " " .. DASH .. " " .. EMOJI .. EMOJI, nil, 0)
        -- wrapped at 8 cells: "cafe -" (6) and two emoji (2)
        T.eq(toast.width, 8)
        T.eq(toast.height, 2)
        T.eq(toast.x, 12, "right-aligned by its width in cells")
        basalt.update()
        T.eq(M.row(t, 2), (" "):rep(12) .. CAFE .. " " .. DASH)
        T.eq(M.row(t, 3), (" "):rep(12) .. EMOJI .. EMOJI)
        checkRows(basalt, frame)
        checkTerm(t)
    end)

    T.test("a toast hard-breaks a long word between whole characters", function()
        local basalt, frame, t = M.frame(12, 5)
        local toast = frame:addToast({ maxWidth = 5 })
        toast:show(DASH:rep(4) .. "ab", nil, 0)
        T.eq(toast.width, 5)
        T.eq(toast.height, 2)
        basalt.update()
        T.eq(toast.x, 7)
        T.eq(M.row(t, 2), "       " .. DASH:rep(3))
        T.eq(M.row(t, 3), "       " .. DASH .. "ab")
        checkRows(basalt, frame)
        checkTerm(t)
    end)

    -- --------------------------------------------------------------- Dialog

    T.test("a dialog wraps its message by cells and sizes its labels", function()
        local basalt, frame, t = M.frame(30, 12)
        local dlg = frame:addDialog({ boxWidth = 14 })
        local message = "Gr\195\188\195\159e " .. DASH .. " " .. CAFE .. " " .. DASH:rep(14)
        dlg:alert("T" .. DASH .. "tel", message)
        basalt.update()
        local box = dlg:getChildren()[1]
        T.eq(box.width, 14)
        local lines = basalt.text.wrap(message, 12)
        T.eq(#lines, 3)
        T.eq(box.height, 2 + #lines + 2, "title, padding, lines, buttons")
        local labels = {}
        for _, child in ipairs(box:getChildren()) do
            if child.y >= 3 and child.text ~= "OK" then labels[#labels + 1] = child end
        end
        T.eq(#labels, 3)
        for i, label in ipairs(labels) do
            T.eq(label.text, lines[i])
            T.eq(label.width, basalt.text.width(lines[i]), "label " .. i .. " width")
        end
        local bx, by = box:getAbsolutePosition()
        T.eq(M.row(t, by), (" "):rep(bx - 1) .. "T" .. DASH .. "tel")
        T.eq(M.row(t, by + 2), (" "):rep(bx) .. "Gr\195\188\195\159e " .. DASH .. " " .. CAFE)
        T.eq(M.row(t, by + 3), (" "):rep(bx) .. DASH:rep(12))
        T.eq(M.row(t, by + 4), (" "):rep(bx) .. DASH:rep(2))
        checkRows(basalt, frame)
        checkTerm(t)
    end)

    T.test("dialog buttons keep their positions and close the dialog", function()
        local basalt, frame, t = M.frame(30, 12)
        local dlg = frame:addDialog()
        local answer
        dlg:confirm(CAFE, DASH .. " ok?", function(yes) answer = yes end)
        basalt.update()
        local box = dlg:getChildren()[1]
        local yes, no
        for _, child in ipairs(box:getChildren()) do
            if child.text == "Yes" then yes = child elseif child.text == "No" then no = child end
        end
        T.ok(yes and no, "both buttons")
        -- totalWidth = (3 + 3) + (2 + 3) = 11; x = floor((26 - 11 + 1) / 2) + 1
        T.eq(yes.x, 9); T.eq(yes.width, 5)
        T.eq(no.x, 15); T.eq(no.width, 4)
        checkRows(basalt, frame)
        checkTerm(t)
        local nx, ny = no:getAbsolutePosition()
        T.click(basalt, nx, ny)
        T.eq(answer, false)
    end)

    -- -------------------------------------------------------------- Program

    -- Runs fn with window.create replaced by M.window: the program's window
    -- keeps its rows the way the mod's window API does (three strings per
    -- row, joined from the pieces of every write, never padded again)
    local function withModWindow(fn)
        local had = rawget(_ENV, "window")
        local real = window
        window = setmetatable({
            create = function(_, _, _, w, h) return M.window(w, h) end,
        }, { __index = real })
        local ok, err = pcall(fn)
        window = had
        if not ok then error(err, 0) end
    end

    local WRITER = [[
term.setCursorPos(1, 1)
term.write("caf\195\169 \226\128\148 \240\159\152\128")
term.setCursorPos(1, 2)
term.write("\233")
term.write("\176")
term.write(" ok")
os.pullEvent("never_ev")
]]

    T.test("a program's UTF-8 window rows are drawn cell for cell", function()
        local basalt, frame, t = M.frame(16, 4)
        local path = T.tmpFile("utf8writer.lua", WRITER)
        local prog = frame:addProgram({ x = 3, y = 1, width = 10, height = 3 })
        withModWindow(function() prog:execute(path) end)
        frame:addLabel({ x = 13, y = 1, text = "|" })
        basalt.update()
        T.eq(M.row(t, 1), "  " .. CAFE .. " " .. DASH .. " " .. EMOJI .. "  |")
        T.eq(M.row(t, 2), "  " .. UTF8_E .. "\176 ok", "a lone CC byte keeps its own cell")
        checkRows(basalt, frame)
        checkTerm(t)
        prog:stop()
    end)

    -- Background colours (blit hex) of cells first..last of a terminal row
    local function bgOf(t, y, first, last)
        local _, _, bg = t.getLine(y)
        return bg:sub(first, last)
    end

    -- A program on the mod's window that makes rows with fewer cells than
    -- colours: "\195" and "\169" written separately merge into one é, and
    -- the cells after them move one to the left (row 1); plain text written
    -- over such a row gives a plain row one byte shorter than its colours
    -- (row 2). The window is blue, the Program element's background black,
    -- so a cell Basalt does not take from the window shows up.
    local MERGER = [[
term.setBackgroundColor(colors.blue)
term.clear()
term.setCursorPos(1, 1)
term.write("\195")
term.write("\169")
term.write("ab")
term.setCursorPos(1, 2)
term.write("\195")
term.write("\169")
term.setCursorPos(1, 2)
term.write("xyz")
os.pullEvent("never_ev")
]]

    -- Runs MERGER in a Program of the given width on a mod window and checks
    -- that the window rows are what the mod's window makes of it
    local function runMerger(frameWidth, x, width)
        local basalt, frame, t = M.frame(frameWidth, 3)
        local path = T.tmpFile("utf8merge.lua", MERGER)
        local prog = frame:addProgram({ x = x, y = 1, width = width, height = 2 })
        withModWindow(function() prog:execute(path) end)
        local win = rawget(prog, "_proc").window
        local line1 = win.getLine(1)
        local line2 = win.getLine(2)
        T.eq(line1, UTF8_E .. " ab" .. (" "):rep(width - 5), "window row 1")
        T.eq(line2, "xyz" .. (" "):rep(width - 4), "window row 2")
        for y = 1, 2 do
            local line, fg, bg = win.getLine(y)
            T.eq(#M.cells(line), width - 1, "cells in window row " .. y)
            T.eq(basalt.text.byteLen(fg), width, "fg bytes in window row " .. y)
            T.eq(bg, ("b"):rep(width), "bg in window row " .. y)
        end
        return basalt, frame, t, prog
    end

    T.test("a program row with merged writes stays valid", function()
        local basalt, frame, t, prog = runMerger(12, 3, 5)
        frame:addLabel({ x = 8, y = 1, text = "|" })
        frame:addLabel({ x = 8, y = 2, text = "|" })
        basalt.update()
        T.eq(M.row(t, 1), "  " .. UTF8_E .. " ab |")
        T.eq(M.row(t, 2), "  xyz  |")
        T.eq(bgOf(t, 1, 3, 7), "bbbbb", "all 5 cells of row 1 have the window's colours")
        T.eq(bgOf(t, 2, 3, 7), "bbbbb", "all 5 cells of row 2 have the window's colours")
        checkRows(basalt, frame)
        checkTerm(t)
        prog:stop()
    end)

    T.test("a program row with merged writes, clipped on the right, stays valid", function()
        local basalt, frame, t, prog = runMerger(6, 3, 5)
        basalt.update()
        T.eq(M.row(t, 1), "  " .. UTF8_E .. " ab")
        T.eq(M.row(t, 2), "  xyz")
        T.eq(bgOf(t, 1, 3, 6), "bbbb")
        T.eq(bgOf(t, 2, 3, 6), "bbbb")
        checkRows(basalt, frame)
        checkTerm(t)
        prog:stop()
    end)

    T.test("a program row with merged writes, clipped on the left, stays valid", function()
        local basalt, frame, t, prog = runMerger(8, -2, 10)
        frame:addLabel({ x = 8, y = 1, text = "|" })
        frame:addLabel({ x = 8, y = 2, text = "|" })
        basalt.update()
        T.eq(M.row(t, 1), "b      |", "window cells 4-10")
        T.eq(M.row(t, 2), "       |")
        T.eq(bgOf(t, 1, 1, 7), ("b"):rep(7), "window cells 4-10 of row 1")
        T.eq(bgOf(t, 2, 1, 7), ("b"):rep(7), "window cells 4-10 of row 2")
        checkRows(basalt, frame)
        checkTerm(t)
        prog:stop()
    end)

    T.test("fitLine pads a program row with fewer cells than colours", function()
        local basalt, frame, t = M.frame(12, 3)
        -- A unit test of Program's padding, with a row from CraftOS-PC's own
        -- byte-based window, which the mod would not make: 10 bytes of UTF-8
        -- are 4 cells, with 10 colours. The padded cells keep the window's
        -- blue; unpadded, the render buffer would cut the colours to the 4
        -- cells, and the rest of the element would show its black
        -- background. (The mod's window makes such rows by merging writes,
        -- see the tests above.)
        local path = T.tmpFile("utf8clip.lua", [[
term.setBackgroundColor(colors.blue)
term.clear()
term.setCursorPos(1, 1)
term.write("\226\128\148\226\128\148\226\128\148ab")
os.pullEvent("never_ev")
]])
        local prog = frame:addProgram({ x = 5, y = 1, width = 10, height = 2 })
        prog:execute(path)
        basalt.update()
        T.eq(M.row(t, 1), "    " .. DASH:rep(3) .. "a")
        T.eq(bgOf(t, 1, 5, 12), ("b"):rep(8), "the 8 visible cells")
        checkRows(basalt, frame)
        checkTerm(t)
        prog:stop()
    end)

    T.test("typed and pasted text reaches a program unchanged", function()
        local basalt, frame = M.frame(20, 4)
        local got = {}
        local path = T.tmpFile("utf8keys.lua", [[
while true do
    local e, a = os.pullEvent()
    if e == "char" or e == "paste" then report(e, a) end
end
]])
        local prog = frame:addProgram({ x = 1, y = 1, width = 10, height = 2 })
        prog.env = { report = function(e, a) got[#got + 1] = e .. ":" .. a end }
        prog:execute(path)
        prog:focus()
        basalt.update("char", LEGACY_E)
        basalt.update("char", DASH)
        basalt.update("char", EMOJI)
        basalt.update("paste", "a" .. LEGACY_E .. "\176" .. DASH .. UTF8_E)
        T.eq(#got, 4)
        T.eq(got[1], "char:" .. LEGACY_E, "the legacy byte, not UTF-8")
        T.eq(got[2], "char:" .. DASH)
        T.eq(got[3], "char:" .. EMOJI)
        T.eq(got[4], "paste:a" .. LEGACY_E .. "\176" .. DASH .. UTF8_E)
        prog:stop()
    end)

    T.test("char and paste events reach element handlers raw", function()
        local basalt, frame = M.frame(20, 4)
        local got = {}
        local button = frame:addButton({ x = 1, y = 1, width = 5, height = 1, text = "b" })
        button:onChar(function(_, ch) got[#got + 1] = ch end)
        button:onPaste(function(_, s) got[#got + 1] = s end)
        button:focus()
        basalt.update("char", LEGACY_E)
        basalt.update("paste", LEGACY_E .. DASH)
        T.eq(got[1], LEGACY_E)
        T.eq(got[2], LEGACY_E .. DASH)
    end)

    -- -------------------------------------------------------------- vanilla

    T.test("without the mod widgets measure bytes as before", function()
        local basalt, frame, win = T.frame(30, 6)
        T.eq(basalt.text.isUtf8(), false)
        local label = frame:addLabel({ x = 1, y = 1, text = CAFE })
        T.eq(label.width, 5, "one cell per byte")
        T.eq(label:measure(), 5)
        local wrapped = frame:addLabel({ x = 1, y = 2, width = 4, text = DASH:rep(2) })
        T.eq(wrapped.height, 2, "hard-broken by bytes")
        local button = frame:addButton({ x = 10, y = 1, width = 9, height = 1, text = CAFE })
        T.eq(button:measure(), 7)
        local box = frame:addCheckbox({ x = 1, y = 4, text = CAFE, checked = true,
            checkedSymbol = CHECK })
        T.eq(box.width, 9)
        local toast = frame:addToast({ maxWidth = 10 })
        toast:show(DASH:rep(2), nil, 0)
        T.eq(toast.width, 8)
        basalt.update()
        T.eq(T.row(win, 1):sub(1, 5), CAFE)
        T.eq(T.row(win, 1):sub(10, 16), "  " .. CAFE, "centred by bytes")
        T.eq(T.row(win, 4), "[\226] " .. CAFE, "the symbol's first byte")
    end)

    T.test("without the mod a program's rows are copied byte for byte", function()
        local basalt, frame, win = T.frame(20, 4)
        local path = T.tmpFile("bytewriter.lua", WRITER)
        local prog = frame:addProgram({ x = 3, y = 1, width = 16, height = 3 })
        prog:execute(path)
        basalt.update()
        T.eq(T.row(win, 1), "  " .. CAFE .. " " .. DASH .. " " .. EMOJI)
        T.eq(T.row(win, 2), "  \233\176 ok")
        prog:stop()
    end)

    T.cleanTmp()
end
