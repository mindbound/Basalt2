-- tests/test_focus_input.lua
-- focusOnClick: a click that leaves the keyboard focus where it is (on the
-- root frame, a log canvas, a popup list, containers and their children),
-- popups that close on blur and so stay open after such a click, and the
-- "focused" state and focus events that follow the root's focus when focus
-- and blur handlers move it on. Input's public cursor API (setCursorPos,
-- getCursorPos), what assigning text does to the cursor, the scroll when
-- the field gets narrower or wider, and all of it with UTF-8 text under
-- the simulated Unicode Support mod.

return function(T)
    -- An input at x 2-21, y 18 with the focus, a canvas "log" at y 1-10 and
    -- a list "popup" at x 2-11, y 13-16 with the items a-d
    local function chatFrame(logProps, listProps)
        local basalt, frame, win = T.frame(30, 19)
        logProps = logProps or {}
        logProps.x, logProps.y = 1, 1
        logProps.width, logProps.height = 30, 10
        if logProps.background == nil then logProps.background = colors.gray end
        local log = frame:addCanvas(logProps)
        listProps = listProps or {}
        listProps.x, listProps.y, listProps.width, listProps.height = 2, 13, 10, 4
        local list = frame:addList(listProps)
        for _, v in ipairs({ "a", "b", "c", "d" }) do list:addItem(v) end
        local input = frame:addInput({ x = 2, y = 18, width = 20 })
        basalt.update()
        input:focus()
        basalt.update()
        return basalt, frame, input, log, list, win
    end

    -- Every element of the tree with the "focused" state
    local function focusedStates(el, out)
        out = out or {}
        if el:hasState("focused") then out[#out + 1] = el end
        if el.getChildren then
            for _, c in ipairs(el:getChildren()) do focusedStates(c, out) end
        end
        return out
    end

    -- The focus is on el, and el is the only element marked focused
    local function onlyFocused(frame, el, msg)
        msg = msg and (msg .. ": ") or ""
        T.eq(frame:getFocused(), el, msg .. "the root's focus")
        local marked = focusedStates(frame)
        T.eq(#marked, 1, msg .. "elements marked focused")
        T.eq(marked[1], el, msg .. "the marked element")
    end

    ------------------------------------------------------------ focusOnClick

    T.test("focusOnClick defaults to true and has accessors", function()
        local basalt, frame = T.frame()
        local canvas = frame:addCanvas()
        T.eq(canvas.focusOnClick, true)
        T.eq(frame.focusOnClick, true, "the root frame too")
        T.eq(canvas:setFocusOnClick(false), canvas, "the setter chains")
        T.eq(canvas:getFocusOnClick(), false)
        basalt.update()
    end)

    T.test("by default a click on a log or a list takes the focus", function()
        local basalt, frame, input, log, list = chatFrame()
        T.click(basalt, 5, 5)
        onlyFocused(frame, log, "log")
        input:focus()
        T.click(basalt, 3, 13)
        onlyFocused(frame, list, "list")
        basalt.update("char", "x")
        T.eq(input.text, "", "the input gets no keys")
    end)

    T.test("by default a click on the empty root takes the focus from the input", function()
        local basalt, frame, input = chatFrame()
        T.click(basalt, 28, 12)
        T.eq(frame:getFocused(), frame, "the root holds the focus")
        T.ok(not input:hasState("focused"), "the input is blurred")
        basalt.update("char", "x")
        T.eq(input.text, "", "the root passes no keys on")
    end)

    T.test("a click on a log with focusOnClick false leaves the focus on the input", function()
        local basalt, frame, input, log = chatFrame({ focusOnClick = false })
        local events, blurs = {}, 0
        log:onClick(function(_, btn, x, y) events[#events + 1] = "click " .. btn .. " " .. x .. " " .. y end)
        log:onClickUp(function() events[#events + 1] = "up" end)
        log:onDrag(function(_, _, x, y) events[#events + 1] = "drag " .. x .. " " .. y end)
        input:onBlur(function() blurs = blurs + 1 end)
        basalt.update("mouse_click", 1, 5, 4)
        T.ok(log:hasState("pressed"), "the log is pressed")
        basalt.update("mouse_drag", 1, 6, 4)
        basalt.update("mouse_up", 1, 6, 4)
        T.ok(not log:hasState("pressed"), "released")
        T.eq(table.concat(events, ","), "click 1 5 4,drag 6 4,up", "the log's mouse events")
        onlyFocused(frame, input, "after the click")
        T.eq(blurs, 0, "the input is not blurred")
        T.type(basalt, "hi")
        T.eq(input.text, "hi", "keys still reach the input")
        T.eq(rawget(frame, "_render").cursorBlink, true, "the input's cursor still blinks")
    end)

    T.test("a log without a background lets the click through to the root", function()
        local basalt, frame, input = chatFrame({ background = false })
        frame.focusOnClick = false
        T.click(basalt, 5, 5)
        onlyFocused(frame, input, "root focusOnClick false")
        frame.focusOnClick = true
        T.click(basalt, 5, 5)
        T.eq(frame:getFocused(), frame, "the root takes the focus again")
    end)

    T.test("a root frame with focusOnClick false keeps the focus on the input", function()
        local basalt, frame, input = chatFrame()
        frame.focusOnClick = false
        local rootClicks = 0
        frame:onClick(function() rootClicks = rootClicks + 1 end)
        T.click(basalt, 28, 12)
        T.eq(rootClicks, 1, "the root still gets the click")
        onlyFocused(frame, input, "after a click on the root")
        T.type(basalt, "ok")
        T.eq(input.text, "ok")
        -- the input still takes the focus back by a click after it lost it
        frame:setFocused(nil)
        T.click(basalt, 3, 18)
        onlyFocused(frame, input, "a click on the input")
    end)

    T.test("a popup list with focusOnClick false selects and scrolls without the focus", function()
        local basalt, frame, input, _, list = chatFrame(nil, { focusOnClick = false })
        local picked
        list:onSelect(function(_, i) picked = i end)
        T.click(basalt, 3, 14) -- row 2: b
        T.eq(picked, 2, "the click selects")
        T.eq(list.selected, 2)
        onlyFocused(frame, input, "after a click on the popup")
        basalt.update("mouse_scroll", 1, 3, 14)
        T.eq(list.offset, 0, "nothing to scroll with 4 items in 4 rows")
        list:addItem("e")
        basalt.update("mouse_scroll", 1, 3, 14)
        T.eq(list.offset, 1, "the wheel scrolls the popup")
        onlyFocused(frame, input, "after the wheel")
        basalt.update("key", keys.down)
        T.eq(list.selected, 2, "keys go to the input, not the popup")
    end)

    T.test("focusOnClick is decided by each element, not by its container", function()
        local basalt, frame, input = chatFrame()
        local panel = frame:addFrame({ x = 23, y = 12, width = 8, height = 6,
            background = colors.blue, focusOnClick = false })
        local btn = panel:addButton({ x = 1, y = 1, width = 4, height = 1, text = "B" })
        local quiet = panel:addButton({ x = 1, y = 3, width = 4, height = 1, text = "Q",
            focusOnClick = false })
        panel:addLabel({ x = 1, y = 5, text = "L" })
        basalt.update()
        T.click(basalt, 27, 16) -- the panel's empty area
        onlyFocused(frame, input, "the panel")
        T.eq(frame:findAt(23, 16).text, "L", "the label is at 23,16")
        T.click(basalt, 23, 16) -- the label: no background, the panel decides
        onlyFocused(frame, input, "a label in the panel")
        local quietClicks = 0
        quiet:onClick(function() quietClicks = quietClicks + 1 end)
        T.click(basalt, 24, 14)
        T.eq(quietClicks, 1)
        onlyFocused(frame, input, "a non-focusing button")
        T.click(basalt, 24, 12)
        onlyFocused(frame, btn, "a focusing button in the panel")

        -- a focusing frame with a non-focusing child: the child consumes the
        -- click, the frame stays unfocused
        input:focus()
        panel.focusOnClick = true
        T.click(basalt, 24, 14)
        onlyFocused(frame, input, "the child of a focusing frame")
        T.click(basalt, 27, 16)
        onlyFocused(frame, panel, "the focusing frame itself")
    end)

    T.test("focus() from code still focuses an element with focusOnClick false", function()
        local basalt, frame, input, log = chatFrame({ focusOnClick = false })
        log:focus()
        onlyFocused(frame, log, "log:focus()")
        T.click(basalt, 5, 5)
        onlyFocused(frame, log, "a click keeps it on the log")
        T.click(basalt, 3, 18)
        onlyFocused(frame, input, "the input takes it by a click")
    end)

    T.test("a disabled element with focusOnClick false ignores the click", function()
        local basalt, frame, input, log = chatFrame({ focusOnClick = false })
        local clicks = 0
        log:onClick(function() clicks = clicks + 1 end)
        log.disabled = true
        frame.focusOnClick = false
        T.click(basalt, 5, 5)
        T.eq(clicks, 0)
        onlyFocused(frame, input)
    end)

    -- Popups that close on blur: a click on an element with focusOnClick
    -- false blurs nothing, so they stay open (documented on the property)
    T.test("a context menu stays open after a click on a non-focusing element", function()
        local basalt, frame, input, log = chatFrame({ focusOnClick = false })
        frame.focusOnClick = false
        local cm = frame:addContextMenu()
        cm:setItems({ "Copy", "Paste" })
        cm:openAt(20, 12) -- x 20-26, y 12-13
        basalt.update()
        onlyFocused(frame, cm, "the open menu")
        T.click(basalt, 28, 12) -- the empty root
        T.eq(cm.visible, true, "open after a click on the root")
        onlyFocused(frame, cm, "the menu keeps the focus")
        T.click(basalt, 5, 5)
        T.eq(cm.visible, true, "open after a click on the log")
        -- the workaround: close it from the element's onClick
        frame:onClick(function() cm:close() end)
        T.click(basalt, 28, 12)
        T.eq(cm.visible, false, "closed by the root's onClick")
        onlyFocused(frame, input, "the focus went back to the input")
        -- a focusing element still closes it by the blur
        log.focusOnClick = true
        cm:openAt(20, 12)
        basalt.update()
        T.click(basalt, 5, 5)
        T.eq(cm.visible, false, "a focusing click closes it")
    end)

    T.test("a dropdown and a combo box stay open after a click on a non-focusing root", function()
        local basalt, frame = chatFrame()
        frame.focusOnClick = false
        local dd = frame:addDropdown({ x = 15, y = 12, width = 10 })
        dd:setItems({ "one", "two" })
        basalt.update()
        T.click(basalt, 16, 12) -- the dropdown's row opens it
        T.eq(dd.open, true)
        onlyFocused(frame, dd, "the open dropdown")
        T.click(basalt, 28, 12) -- the empty root
        T.eq(dd.open, true, "the dropdown stays open")
        onlyFocused(frame, dd, "the dropdown keeps the focus")
        frame.focusOnClick = true
        T.click(basalt, 28, 12)
        T.eq(dd.open, false, "a focusing root closes it")

        dd.visible = false
        frame.focusOnClick = false
        local cbx = frame:addComboBox({ x = 15, y = 12, width = 10 })
        cbx:setItems({ "one", "two" })
        basalt.update()
        T.click(basalt, 24, 12) -- the arrow cell opens it
        T.eq(cbx.open, true)
        onlyFocused(frame, cbx, "the open combo box")
        T.click(basalt, 28, 12)
        T.eq(cbx.open, true, "the combo box stays open")
        onlyFocused(frame, cbx, "the combo box keeps the focus")
    end)

    ---------------------------------------------------- the focused state

    T.test("an onBlur that refocuses the input leaves no stale focused state", function()
        local basalt, frame, input, log = chatFrame()
        input:onBlur(function(s) s:focus() end)
        T.click(basalt, 5, 5)
        onlyFocused(frame, input, "after the refocus")
        T.ok(not log:hasState("focused"), "the log is not marked focused")
        T.type(basalt, "z")
        T.eq(input.text, "z", "the next key reaches the input")
        T.click(basalt, 28, 12) -- the root: the input refocuses again
        onlyFocused(frame, input, "after a click on the root")
    end)

    T.test("no focus event reaches an element after the focus moved on", function()
        local basalt, frame, input, log = chatFrame()
        local refocus = true
        input:onBlur(function(s) if refocus then s:focus() end end)
        local focusEvents, stale = 0, 0
        log:onFocus(function()
            focusEvents = focusEvents + 1
            if frame:getFocused() ~= log then stale = stale + 1 end
        end)
        T.click(basalt, 5, 5)
        T.eq(stale, 0, "focus events on the log without the focus")
        T.eq(focusEvents, 0, "the input took the focus back first")
        onlyFocused(frame, input, "after the refocus")
        -- without the refocus the log gets its focus event as before
        refocus = false
        T.click(basalt, 5, 5)
        T.eq(focusEvents, 1, "one focus event")
        T.eq(stale, 0)
        onlyFocused(frame, log, "the log took the focus")
    end)

    T.test("an element destroyed by the old element's onBlur is not focused", function()
        local basalt, frame, input, log = chatFrame()
        local focusEvents = 0
        log:onFocus(function() focusEvents = focusEvents + 1 end)
        input:onBlur(function() log:destroy() end)
        T.click(basalt, 5, 5)
        T.eq(rawget(log, "parent"), nil, "the log was removed")
        T.eq(frame:getFocused(), nil, "nothing has the focus")
        T.eq(focusEvents, 0, "no focus event on the removed log")
        T.ok(not log:hasState("focused"), "the removed log is not marked focused")
        T.eq(#focusedStates(frame), 0, "nothing in the frame is marked focused")
    end)

    T.test("an onFocus that passes the focus on keeps the states consistent", function()
        local basalt, frame, input, log = chatFrame()
        log:onFocus(function() input:focus() end)
        T.click(basalt, 5, 5)
        onlyFocused(frame, input, "after the log passed the focus on")
        basalt.update("char", "q")
        T.eq(input.text, "q")
    end)

    T.test("an onBlur that clears the focus leaves nothing marked focused", function()
        local basalt, frame, input, log = chatFrame()
        input:onBlur(function() frame:setFocused(nil) end)
        T.click(basalt, 5, 5)
        T.eq(frame:getFocused(), nil, "nothing has the focus")
        T.eq(#focusedStates(frame), 0, "nothing is marked focused")
        T.ok(not log:hasState("focused"))
    end)

    T.test("a focus event outside a frame still sets the state", function()
        local basalt = T.loadBasalt()
        local frame = basalt.createFrame(T.window(10, 5))
        local loose = frame:addButton({ text = "x" })
        frame:removeChild(loose)
        loose:fire("focus")
        T.ok(loose:hasState("focused"), "no root focus to follow: the event decides")
        loose:fire("blur")
        T.ok(not loose:hasState("focused"))
    end)

    ------------------------------------------------------- Input cursor

    -- an 8-wide input at x 30-37, y 2, focused by a click
    local function inputFrame(props)
        local basalt, frame, win = T.frame()
        props = props or {}
        props.x, props.y, props.width = 30, 2, props.width or 8
        local input = frame:addInput(props)
        basalt.update()
        T.click(basalt, 31, 2)
        return basalt, frame, input, win
    end

    T.test("setCursorPos moves the insertion point and clamps", function()
        local basalt, _, input = inputFrame()
        input.text = "hello"
        T.eq(input:getCursorPos(), 1, "assigned text keeps the cursor at 1")
        T.eq(input:setCursorPos(3), input, "the setter chains")
        T.eq(input:getCursorPos(), 3)
        basalt.update("char", "X")
        T.eq(input.text, "heXllo", "typing inserts at the new position")
        T.eq(input:getCursorPos(), 4)
        input:setCursorPos(0)
        T.eq(input:getCursorPos(), 1, "below 1")
        input:setCursorPos(100)
        T.eq(input:getCursorPos(), 7, "past the end")
        input:setCursorPos(-math.huge)
        T.eq(input:getCursorPos(), 1)
        input:setCursorPos(math.huge)
        T.eq(input:getCursorPos(), 7, "math.huge is the end")
        input:setCursorPos(2.9)
        T.eq(input:getCursorPos(), 2, "whole cells")
        T.raises(function() input:setCursorPos("3") end, "cursor position must be a number")
        T.raises(function() input:setCursorPos(0 / 0) end, "cursor position must be a number")
        T.raises(function() input:setCursorPos() end, "cursor position must be a number")
        T.eq(input:getCursorPos(), 2, "a rejected call changes nothing")
    end)

    T.test("setCursorPos scrolls sideways like typing and moves the terminal cursor", function()
        local basalt, frame, input, win = inputFrame()
        input.text = "abcdefghijklmno"
        basalt.update()
        T.eq(input._scroll, 0)
        input:setCursorPos(math.huge)
        basalt.update()
        T.eq(input:getCursorPos(), 16)
        T.eq(input._scroll, 8, "the same scroll as typing the text")
        T.eq(T.row(win, 2):sub(30, 37), "ijklmno")
        local r = rawget(frame, "_render")
        T.eq(r.cursorX, 37); T.eq(r.cursorY, 2)
        input:setCursorPos(12)
        basalt.update()
        T.eq(input._scroll, 8, "no scroll while the cursor stays in view")
        T.eq(r.cursorX, 33)
        input:setCursorPos(3)
        basalt.update()
        T.eq(input._scroll, 2, "scrolled just enough")
        T.eq(T.row(win, 2):sub(30, 37), "cdefghij")
        T.eq(r.cursorX, 30)
        input:setCursorPos(1)
        basalt.update()
        T.eq(input._scroll, 0)
        T.eq(r.cursorX, 30)
    end)

    T.test("assigned text keeps the cursor, clamped to the new text", function()
        local basalt, _, input = inputFrame()
        T.type(basalt, "hello")
        T.eq(input:getCursorPos(), 6)
        input.text = "hi"
        T.eq(input:getCursorPos(), 3, "past the new end: the end")
        input.text = "hello world"
        T.eq(input:getCursorPos(), 3, "a longer text keeps the position")
        input.text = ""
        T.eq(input:getCursorPos(), 1, "empty text")
        -- recalling a history entry: assign it, then move to the end
        input.text = "previous command"
        input:setCursorPos(math.huge)
        T.type(basalt, "!")
        T.eq(input.text, "previous command!")
        T.eq(input:getCursorPos(), 18)
    end)

    T.test("a cursor past the end of bound text is clamped when drawn", function()
        local basalt, frame, input = inputFrame()
        local value = basalt.state("")
        input:bind("text", value)
        T.type(basalt, "hello")
        T.eq(value:get(), "hello", "typing writes the state")
        T.eq(input:getCursorPos(), 6)
        value:set("") -- cleared from code through the state
        basalt.update()
        T.eq(input.text, "")
        T.eq(rawget(frame, "_render").cursorX, 30, "the cursor is drawn at the start")
        T.eq(input:getCursorPos(), 1)
        T.type(basalt, "ab")
        T.eq(value:get(), "ab")
        T.eq(input:getCursorPos(), 3)
    end)

    T.test("a narrower input scrolls so the cursor stays in view", function()
        local basalt, frame, input = inputFrame()
        T.type(basalt, "abcdefghijklmno")
        T.eq(input._scroll, 8)
        input.width = 4
        basalt.update()
        local r = rawget(frame, "_render")
        T.eq(input._scroll, 12)
        T.eq(r.cursorBlink, true, "the cursor is still shown")
        T.eq(r.cursorX, 33, "in the last cell of the field")
    end)

    T.test("an input that gets wider again shows as much text as fits", function()
        local basalt, frame, input, win = inputFrame()
        local r = rawget(frame, "_render")
        T.type(basalt, "abcdefghijklmno")
        input.width = 4
        basalt.update()
        T.eq(input._scroll, 12)
        T.eq(T.row(win, 2):sub(30, 33), "mno")
        input.width = 8
        basalt.update()
        T.eq(input._scroll, 8, "the scroll that puts the cursor in the last cell")
        T.eq(T.row(win, 2):sub(30, 37), "ijklmno")
        T.eq(r.cursorX, 37)
        input.width = 20
        basalt.update()
        T.eq(input._scroll, 0, "the whole text fits")
        T.eq(T.row(win, 2):sub(30, 49), "abcdefghijklmno")
        T.eq(r.cursorX, 45, "after the last character")
        T.type(basalt, "p")
        T.eq(input.text, "abcdefghijklmnop", "typing goes on at the end")
        T.eq(r.cursorX, 46)
    end)

    T.test("a wider input lowers the scroll only as far as the text needs", function()
        local basalt, frame, input, win = inputFrame()
        local r = rawget(frame, "_render")
        T.type(basalt, "abcdefghijklmno")
        for _ = 1, 4 do basalt.update("key", keys.left) end
        T.eq(input:getCursorPos(), 12)
        T.eq(input._scroll, 8)
        input.width = 3
        basalt.update()
        T.eq(input._scroll, 9, "narrower: scrolled to the cursor")
        T.eq(T.row(win, 2):sub(30, 32), "jkl")
        input.width = 10
        basalt.update()
        T.eq(input._scroll, 6, "the text ends at the field's last cell but one")
        T.eq(T.row(win, 2):sub(30, 39), "ghijklmno")
        T.eq(r.cursorX, 35, "the cursor stays before l")
        -- Delete keeps the cursor and, at the same width, the scroll (as
        -- upstream); the next widening fills the field
        for _ = 1, 3 do basalt.update("key", keys.delete) end
        T.eq(input.text, "abcdefghijko")
        T.eq(input._scroll, 6, "same width: the scroll stays")
        T.eq(T.row(win, 2):sub(30, 39), "ghijko")
        input.width = 12
        basalt.update()
        T.eq(input._scroll, 1, "wider: the text ends at the last cell but one")
        T.eq(T.row(win, 2):sub(30, 41), "bcdefghijko")
        T.eq(r.cursorX, 40)
    end)

    T.test("a key pressed after the input got wider and before the draw", function()
        local basalt, frame, input, win = inputFrame()
        T.type(basalt, "abcdefghijklmno")
        input.width = 4
        basalt.update()
        T.eq(input._scroll, 12)
        input.width = 20
        basalt.update("key", keys.left) -- moves the cursor before any redraw
        T.eq(input._scroll, 0, "the cursor move sees the wider field")
        basalt.update()
        T.eq(T.row(win, 2):sub(30, 49), "abcdefghijklmno")
        T.eq(rawget(frame, "_render").cursorX, 44)
    end)

    T.test("an input made wider before its first draw shows the text", function()
        local basalt, frame, win = T.frame()
        local input = frame:addInput({ x = 30, y = 2, width = 4 })
        input.text = "abcdefghij"
        input:setCursorPos(math.huge)
        T.eq(input._scroll, 7, "fitted to the 4-wide field")
        input.width = 16
        basalt.update()
        T.eq(input._scroll, 0)
        T.eq(T.row(win, 2):sub(30, 45), "abcdefghij")
        T.eq(input:getCursorPos(), 11)
    end)

    --------------------------------------------- UTF-8 (simulated mod)

    local M = assert(loadfile(T.root .. "/tests/modsim.lua", nil, _ENV))(T)
    local E = "\195\169"             -- é as UTF-8
    local DASH = "\226\128\148"      -- em dash
    local EMOJI = "\240\159\152\128" -- U+1F600

    local function modInput(width)
        local basalt, frame, t = M.frame(20, 4)
        local input = frame:addInput({ x = 1, y = 1, width = width or 10 })
        basalt.update()
        T.click(basalt, 1, 1)
        return basalt, frame, input, t
    end

    local function cellsAt(t, y, x, n)
        return table.concat(M.cells((t.getLine(y))), "", x, x + n - 1)
    end

    T.test("utf8: setCursorPos counts cells", function()
        local basalt, frame, input, t = modInput()
        input.text = "a" .. E .. DASH .. EMOJI .. "b"
        input:setCursorPos(math.huge)
        T.eq(input:getCursorPos(), 6, "five cells, the end is 6")
        input:setCursorPos(3)
        basalt.update("char", "x")
        T.eq(input.text, "a" .. E .. "x" .. DASH .. EMOJI .. "b", "inserted between whole characters")
        T.eq(input:getCursorPos(), 4)
        basalt.update()
        T.eq(rawget(frame, "_render").cursorX, 4)
        T.eq(cellsAt(t, 1, 1, 6), "a" .. E .. "x" .. DASH .. EMOJI .. "b")
        input.text = E .. DASH
        T.eq(input:getCursorPos(), 3, "clamped to the cells of the new text")
    end)

    T.test("utf8: setCursorPos scrolls by cells", function()
        local basalt, frame, input, t = modInput(5)
        input.text = E:rep(4) .. DASH:rep(4)
        input:setCursorPos(math.huge)
        basalt.update()
        T.eq(input:getCursorPos(), 9)
        T.eq(input._scroll, 4)
        T.eq(cellsAt(t, 1, 1, 5), DASH:rep(4) .. " ", "the last 4 cells and the cursor cell")
        T.eq(rawget(frame, "_render").cursorX, 5)
        input:setCursorPos(2)
        basalt.update()
        T.eq(input._scroll, 1)
        T.eq(cellsAt(t, 1, 1, 5), E:rep(3) .. DASH:rep(2))
        T.eq(rawget(frame, "_render").cursorX, 1)
    end)

    T.test("utf8: a narrower then wider input scrolls by cells", function()
        local basalt, frame, input, t = modInput(10)
        local r = rawget(frame, "_render")
        input.text = E:rep(6) .. DASH:rep(5) .. EMOJI -- 12 cells
        input:setCursorPos(math.huge)
        basalt.update()
        T.eq(input._scroll, 3)
        input.width = 4
        basalt.update()
        T.eq(input._scroll, 9, "narrower: the cursor stays in view")
        T.eq(cellsAt(t, 1, 1, 4), DASH:rep(2) .. EMOJI .. " ")
        T.eq(r.cursorX, 4)
        input.width = 10
        basalt.update()
        T.eq(input._scroll, 3, "wider: the field is filled again")
        T.eq(cellsAt(t, 1, 1, 10), E:rep(3) .. DASH:rep(5) .. EMOJI .. " ")
        T.eq(r.cursorX, 10)
        input.width = 16
        basalt.update()
        T.eq(input._scroll, 0, "the whole text fits")
        T.eq(cellsAt(t, 1, 1, 13), E:rep(6) .. DASH:rep(5) .. EMOJI .. " ")
        T.eq(r.cursorX, 13)
        basalt.update("char", "x")
        T.eq(input.text, E:rep(6) .. DASH:rep(5) .. EMOJI .. "x")
        T.eq(r.cursorX, 14)
    end)
end
