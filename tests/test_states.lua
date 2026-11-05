-- tests/test_states.lua
-- Named element states: priorities, non-destructive overrides, mirrored
-- states and releasing transient states when a subtree goes away.
-- Ported from the deleted 2.5 smoke test (2062cc6:test_smoke.lua).

return function(T)
    local function styledButton(frame)
        local btn = frame:addButton({ x = 2, y = 6, text = "Click me" })
        btn:setStateStyle("hover", { background = colors.lightGray })
        btn:setStateStyle("pressed", { background = colors.blue })
        btn:setStateStyle("loading", { text = "Loading" }, 50)
        return btn
    end

    T.test("state styles override properties by priority", function()
        local _, frame = T.frame()
        local btn = styledButton(frame)
        local baseBackground = btn.background
        btn:setState("hover", true)
        T.eq(btn.background, colors.lightGray, "hover style")
        btn:setState("pressed", true)
        T.eq(btn.background, colors.blue, "pressed outranks hover")
        btn:setState("pressed", false)
        btn:setState("hover", false)
        T.eq(btn.background, baseBackground, "falls back to the stored value")
    end)

    T.test("custom states: idempotent and non-destructive", function()
        local _, frame = T.frame()
        local btn = styledButton(frame)
        local changes = 0
        btn:onStateChange(function(_, name, active)
            if name == "loading" and active then changes = changes + 1 end
        end)
        local baseText = btn.text
        btn:setState("loading", true)
        T.eq(btn.text, "Loading")
        T.eq(changes, 1)
        btn:setState("loading", true)
        T.eq(changes, 1, "setting an active state again is a no-op")
        btn:setState("loading", false)
        T.eq(btn.text, baseText, "the stored property survives the state")
        T.eq(btn:raw("text"), "Click me")
    end)

    T.test("behaviour properties cannot be state-styled", function()
        local _, frame = T.frame()
        local btn = frame:addButton({ text = "x" })
        T.raises(function()
            btn:setStateStyle("bad", { disabled = false })
        end, "cannot be state-styled")
    end)

    T.test("hiding an element releases focus, press and hover", function()
        local basalt, frame = T.frame()
        local input = frame:addInput({ x = 30, y = 4, width = 5 })
        basalt.update()
        basalt.update("mouse_click", 1, 31, 4)
        T.ok(input:hasState("focused"), "focused after the click")
        T.ok(input:hasState("pressed"), "pressed after the click")
        T.ok(input:hasState("hover"), "hovered after the click")
        input.visible = false
        T.ok(not input:hasState("focused"), "focus released")
        T.ok(not input:hasState("pressed"), "press released")
        T.ok(not input:hasState("hover"), "hover released")
        T.eq(frame:getFocused(), nil)
    end)

    T.test("destroying an element releases focus, press and hover", function()
        local basalt, frame = T.frame()
        local input = frame:addInput({ x = 30, y = 4, width = 5 })
        basalt.update()
        basalt.update("mouse_click", 1, 31, 4)
        T.ok(input:hasState("focused") and input:hasState("pressed"))
        input:destroy()
        T.ok(not input:hasState("focused"), "focus released")
        T.ok(not input:hasState("pressed"), "press released")
        T.ok(not input:hasState("hover"), "hover released")
        T.eq(frame:getFocused(), nil)
        basalt.update("mouse_up", 1, 31, 4) -- the released press is not resumed
    end)

    T.test("disabled mirrors to a state and drops focus and press", function()
        local basalt, frame = T.frame()
        local btn = frame:addButton({ x = 2, y = 6, text = "Click me" })
        basalt.update()
        basalt.update("mouse_click", 1, 3, 7)
        T.ok(btn:hasState("focused") and btn:hasState("pressed"))
        btn.disabled = true
        T.ok(btn:hasState("disabled"), "disabled state mirrored")
        T.ok(not btn:hasState("focused"), "focus released")
        T.ok(not btn:hasState("pressed"), "press released")
        btn.disabled = false
        T.ok(not btn:hasState("disabled"), "disabled state cleared")
    end)
end
