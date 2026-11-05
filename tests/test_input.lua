-- tests/test_input.lua
-- Mouse routing (click, hover, press, focus, disabled), monitor touch and
-- the Input element (editing, cursor, paste, masking, patterns).
-- Ported from the deleted 2.5 smoke test (2062cc6:test_smoke.lua).

return function(T)
    -- a 10x3 button covering x 2-11, y 6-8
    local function buttonFrame()
        local basalt, frame, win = T.frame()
        local btn = frame:addButton({ x = 2, y = 6, text = "Click me" })
        local clicks = { n = 0 }
        btn:onClick(function() clicks.n = clicks.n + 1 end)
        basalt.update()
        return basalt, frame, btn, clicks, win
    end

    T.test("a click hovers, presses and focuses; mouse_up fires once", function()
        local basalt, frame, btn, clicks = buttonFrame()
        basalt.update("mouse_click", 1, 3, 7)
        T.ok(btn:hasState("hover"), "hover")
        T.ok(btn:hasState("pressed"), "pressed")
        T.ok(btn:hasState("focused"), "focused")
        T.eq(frame:getFocused(), btn)
        basalt.update("mouse_up", 1, 3, 7)
        T.ok(not btn:hasState("pressed"), "mouse_up clears pressed")
        T.eq(clicks.n, 1)
    end)

    T.test("a disabled button ignores clicks", function()
        local basalt, _, btn, clicks = buttonFrame()
        T.click(basalt, 3, 7)
        T.eq(clicks.n, 1)
        btn.disabled = true
        T.click(basalt, 3, 7)
        T.eq(clicks.n, 1, "no click while disabled")
        btn.disabled = false
        T.click(basalt, 3, 7)
        T.eq(clicks.n, 2, "clicks again once enabled")
    end)

    T.test("mouse_move with 3 or 2 arguments updates hover", function()
        local basalt, _, btn = buttonFrame()
        -- CraftOS-PC variants may include a leading source/button value
        basalt.update("mouse_move", 0, 3, 7)
        T.ok(btn:hasState("hover"), "3-argument move onto the button")
        basalt.update("mouse_move", 0, 30, 10)
        T.ok(not btn:hasState("hover"), "3-argument move away")
        basalt.update("mouse_move", 3, 7)
        T.ok(btn:hasState("hover"), "2-argument move onto the button")
        basalt.update("mouse_move", 30, 10)
        T.ok(not btn:hasState("hover"), "2-argument move away")
    end)

    T.test("a click outside the button does not fire it", function()
        local basalt, _, _, clicks = buttonFrame()
        T.click(basalt, 1, 1)
        T.click(basalt, 12, 7)
        T.eq(clicks.n, 0)
    end)

    T.test("monitor touch arrives as click and up on the right monitor", function()
        local basalt = T.loadBasalt()
        local mon = basalt.createFrame(T.window(20, 10), "left")
        local clicks = 0
        mon:addButton({ x = 2, y = 2, text = "M" }):onClick(function()
            clicks = clicks + 1
        end)
        basalt.update()
        basalt.update("monitor_touch", "left", 3, 3)
        T.eq(clicks, 1)
        basalt.update("monitor_touch", "right", 3, 3)
        T.eq(clicks, 1, "a touch on another monitor is ignored")
    end)

    -- an 8-wide input at x 30-37, y 2, focused by a click
    local function inputFrame(props)
        local basalt, frame, win = T.frame()
        props = props or {}
        props.x, props.y, props.width = props.x or 30, props.y or 2, props.width or 8
        local input = frame:addInput(props)
        basalt.update()
        T.click(basalt, props.x + 1, props.y)
        return basalt, frame, input, win
    end

    T.test("an input gets focus by a click and edits at the cursor", function()
        local basalt, frame, input = inputFrame()
        local entered
        input:onEnter(function(_, t) entered = t end)
        T.eq(frame:getFocused(), input)
        T.type(basalt, "hello")
        T.eq(input.text, "hello", "typing")
        basalt.update("key", keys.backspace)
        T.eq(input.text, "hell", "backspace")
        basalt.update("key", keys.left)
        basalt.update("key", keys.left)
        basalt.update("char", "X")
        T.eq(input.text, "heXll", "insert at the cursor")
        basalt.update("key", keys.enter)
        T.eq(entered, "heXll", "enter event")
    end)

    T.test("long input text scrolls and the cursor follows", function()
        local basalt, frame, input, win = inputFrame()
        T.type(basalt, "abcdefghijklmno")
        T.eq(input._scroll, 8)
        local r = frame._render
        T.eq(r.cursorBlink, true, "the cursor blinks while focused")
        T.eq(r.cursorX, 37); T.eq(r.cursorY, 2)
        local cx, cy = win.getCursorPos()
        T.eq(cx, 37, "terminal cursor x"); T.eq(cy, 2, "terminal cursor y")
        T.eq(win.getCursorBlink(), true, "terminal cursor blinks")
        T.eq(T.row(win, 2):sub(30, 37), "ijklmno", "the visible slice")
        T.click(basalt, 1, 1) -- a click on the empty root blurs the input
        T.eq(r.cursorBlink, false, "the cursor hides on blur")
        T.eq(win.getCursorBlink(), false)
    end)

    T.test("paste goes to the focused input and fires onPaste", function()
        local basalt, _, input = inputFrame()
        local pasted
        input:onPaste(function(_, t) pasted = t end)
        basalt.update("paste", "geheim")
        T.eq(input.text, "geheim")
        T.eq(pasted, "geheim")
    end)

    T.test("replaceChar masks the drawn text", function()
        local basalt, _, input, win = inputFrame()
        basalt.update("paste", "geheim")
        input.replaceChar = "*"
        basalt.update()
        local row = T.row(win, 2):sub(30, 37)
        T.eq(row, "******")
        input.replaceChar = false
        basalt.update()
        T.eq(T.row(win, 2):sub(30, 37), "geheim")
    end)

    T.test("pattern filters typing and pastes", function()
        local basalt, _, input = inputFrame({ x = 12, y = 1, width = 6, pattern = "%d" })
        basalt.update("char", "a")
        basalt.update("char", "5")
        basalt.update("paste", "x7y9")
        T.eq(input.text, "579")
    end)
end
