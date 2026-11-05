-- tests/test_textbox.lua
-- TextBox: editing, line split/merge, external assignment, scrolling,
-- paste and selection (keyboard, mouse, clipboard).
-- Ported from the deleted 2.5 smoke test (2062cc6:test_smoke.lua).

return function(T)
    -- a 10x3 text box at the top-left corner, focused by a click
    local function textBox()
        local basalt, frame, win = T.frame(40, 18)
        local tb = frame:addTextBox({ x = 1, y = 1, width = 10, height = 3 })
        basalt.update()
        T.click(basalt, 1, 1)
        return basalt, frame, tb, win
    end

    T.test("typing, enter and backspace edit lines", function()
        local basalt, _, tb = textBox()
        local changes = 0
        tb:onChange(function() changes = changes + 1 end)
        basalt.update("char", "a")
        basalt.update("char", "b")
        basalt.update("key", keys.enter)
        basalt.update("char", "c")
        T.eq(tb.text, "ab\nc")
        T.eq(changes, 4, "one change event per edit")
        basalt.update("key", keys.backspace)
        basalt.update("key", keys.backspace) -- merges the lines again
        T.eq(tb.text, "ab")
    end)

    T.test("external assignment replaces the buffer; the view follows", function()
        local basalt, frame, tb = textBox()
        tb.text = "1\n2\n3\n4\n5"
        T.eq(#tb._lines, 5)
        for _ = 1, 6 do basalt.update("key", keys.down) end
        T.eq(tb._viewY, 2, "scrolled to the cursor")
        T.eq(frame._render.cursorBlink, true, "cursor shown")
    end)

    T.test("paste inserts at the cursor", function()
        local basalt, _, tb = textBox()
        tb.text = "x"
        basalt.update("key", keys["end"])
        basalt.update("paste", "YZ")
        T.eq(tb.text, "xYZ")
    end)

    T.test("shift+arrows select; typing replaces the selection", function()
        local basalt, _, tb = textBox()
        tb.text = "abcdef\nghijkl\nmnopqr"
        T.click(basalt, 1, 1)
        basalt.update("key", keys.leftShift)
        for _ = 1, 3 do basalt.update("key", keys.right) end
        T.eq(tb:getSelection(), "abc")
        basalt.update("key", keys.down) -- still shifted
        T.eq(tb:getSelection(), "abcdef\nghi")
        basalt.update("key_up", keys.leftShift)
        basalt.update("char", "X")
        T.eq(tb.text, "Xjkl\nmnopqr")
    end)

    T.test("ctrl+a, ctrl+c and ctrl+x use the internal clipboard", function()
        local basalt, _, tb = textBox()
        tb.text = "Xjkl\nmnopqr"
        basalt.update("key", keys.leftCtrl)
        basalt.update("key", keys.a)
        T.eq(tb:getSelection(), "Xjkl\nmnopqr", "select all")
        basalt.update("key", keys.c)
        basalt.update("key", keys.x)
        basalt.update("key_up", keys.leftCtrl)
        T.eq(tb:getClipboard(), "Xjkl\nmnopqr")
        T.eq(tb.text, "")
        T.eq(#tb._lines, 1)
    end)

    T.test("a mouse drag selects; backspace deletes only the selection", function()
        local basalt, _, tb = textBox()
        tb.text = "hello world"
        basalt.update("mouse_click", 1, 1, 1)
        basalt.update("mouse_drag", 1, 6, 1)
        T.eq(tb:getSelection(), "hello")
        basalt.update("mouse_up", 1, 6, 1)
        basalt.update("key", keys.backspace)
        T.eq(tb.text, " world")
        T.eq(tb:getSelection(), nil, "deleting collapsed the selection")
        T.withEscape(function(escape) basalt.update("key", escape) end)
        T.eq(tb:getSelection(), nil, "escape is a no-op without a selection")
    end)

    T.test("escape collapses a selection without editing", function()
        local basalt, _, tb = textBox()
        tb.text = "hello"
        basalt.update("mouse_click", 1, 1, 1)
        basalt.update("mouse_drag", 1, 4, 1)
        basalt.update("mouse_up", 1, 4, 1)
        T.eq(tb:getSelection(), "hel")
        T.withEscape(function(escape) basalt.update("key", escape) end)
        T.eq(tb:getSelection(), nil)
        T.eq(tb.text, "hello")
    end)

    T.test("the selection overlay is drawn in the selection colors", function()
        local basalt, _, tb, win = textBox()
        tb.text = "hello world"
        basalt.update("mouse_click", 1, 1, 1)
        basalt.update("mouse_drag", 1, 6, 1)
        basalt.update("mouse_up", 1, 6, 1)
        T.eq(T.bg(win, 1, 1), colors.blue, "selected cell")
        T.eq(T.bg(win, 5, 1), colors.blue, "last selected cell")
        T.eq(T.bg(win, 6, 1), colors.black, "first unselected cell")
    end)
end
