-- tests/test_properties.lua
-- Element properties: label auto-size, fluent setters, combined properties
-- and dynamic (function) values. Ported from the deleted 2.5 smoke test
-- (2062cc6:test_smoke.lua) and test_combined.lua.

return function(T)
    T.test("a label auto-sizes to its text until a width is set", function()
        local _, frame = T.frame()
        local label = frame:addLabel({ x = 2, y = 2, text = "Hello" })
        T.eq(label.width, 5, "initial auto width")
        label.text = "Hello World"
        T.eq(label.width, 11, "auto width after a text change")
        label:setWidth(4)
        label.text = "xxxxxxxx"
        T.eq(label.width, 4, "a manual width disables auto-size")
    end)

    T.test("chained setters and plain properties are the same thing", function()
        local _, frame = T.frame()
        local btn = frame:addButton({ x = 2, y = 6, text = "Click me" })
        T.eq(btn:setText("Klick"):setX(2), btn, "setters are fluent")
        T.eq(btn.text, "Klick")
        T.eq(btn.x, 2)
        btn.text = "Click me"
        T.eq(btn:getText(), "Click me")
    end)

    T.test("combined position/size setters are fluent", function()
        local _, frame = T.frame()
        local el = frame:addButton({ text = "Combined" })
        T.eq(el:setPosition(4, 5):setSize(12, 3), el)
        local x, y = el:getPosition()
        local w, h = el:getSize()
        T.eq(x, 4); T.eq(y, 5); T.eq(w, 12); T.eq(h, 3)
    end)

    T.test("combined bounds set and get four properties", function()
        local _, frame = T.frame()
        local el = frame:addButton({ text = "Combined" })
        el:setBounds(6, 7, 14, 2)
        local x, y, w, h = el:getBounds()
        T.eq(x, 6); T.eq(y, 7); T.eq(w, 14); T.eq(h, 2)
    end)

    T.test("combined getters preserve false values", function()
        local _, frame = T.frame()
        local el = frame:addButton({ text = "Combined" })
        el:setColors(colors.red, false)
        local fg, bg = el:getColors()
        T.eq(fg, colors.red)
        T.eq(bg, false)
    end)

    T.test("combined min/max size", function()
        local _, frame = T.frame()
        local el = frame:addButton({ text = "Combined" })
        el:setMinSize(3, 2):setMaxSize(20, 8)
        local minW, minH = el:getMinSize()
        local maxW, maxH = el:getMaxSize()
        T.eq(minW, 3); T.eq(minH, 2); T.eq(maxW, 20); T.eq(maxH, 8)
    end)

    T.test("the raw combined getter keeps layout tokens", function()
        local basalt, frame = T.frame()
        local el = frame:addButton({ text = "Combined" })
        el:setSize(basalt.fill(), basalt.auto())
        local rawW, rawH = el:getRawSize()
        T.eq(type(rawW), "table")
        T.eq(type(rawH), "table")
        el:destroy()
        T.eq(#frame:getChildren(), 0, "destroy detaches the element")
    end)

    T.test("combined setters validate their arity", function()
        local _, frame = T.frame()
        local el = frame:addButton({ text = "Combined" })
        T.raises(function() el:setPosition(1) end, "expects 2 values")
    end)

    T.test("a layout-managed child: effective vs authored position", function()
        local _, frame = T.frame()
        local row = frame:addRow({ x = 1, y = 10, width = 20, height = 1 })
        local managed = row:addLabel({ text = "Layout" }):setPosition(9, 9)
        frame:draw()
        local x, y = managed:getPosition()
        local rawX, rawY = managed:getRawPosition()
        T.eq(x, 1, "effective x"); T.eq(y, 1, "effective y")
        T.eq(rawX, 9, "authored x"); T.eq(rawY, 9, "authored y")
    end)

    T.test("function values are evaluated on read", function()
        local _, frame = T.frame()
        local dynFrame = frame:addFrame({ x = 20, y = 14, width = 10, height = 3 })
        local dynLabel = dynFrame:addLabel({
            text = "dyn",
            x = function(s) return s.parent.width - 2 end,
            foreground = function() return colors.red end,
        })
        T.eq(dynLabel.x, 8, "dynamic x")
        T.eq(dynLabel.foreground, colors.red, "dynamic foreground")
        dynFrame.width = 15 -- followed immediately, no observers
        T.eq(dynLabel.x, 13, "dynamic x after a parent resize")
        T.eq(type(dynLabel:raw("x")), "function", "raw() returns the function")
        T.eq(dynLabel:getX(), 13, "the getter evaluates the dynamic value")
    end)

    T.test("auto-size does not clobber a dynamic width", function()
        local basalt, frame = T.frame()
        local dynFrame = frame:addFrame({ x = 20, y = 14, width = 15, height = 3 })
        local dynLabel = dynFrame:addLabel({ text = "dyn" })
        dynLabel:setWidth(function(s) return s.parent.width - 4 end)
        dynLabel.text = "longer text"
        T.eq(dynLabel.width, 11)
        basalt.update()
        dynLabel.x = function(s) return s.parent.width - 2 end
        dynLabel.x = 2 -- a plain value replaces the dynamic one
        T.eq(dynLabel.x, 2)
        T.eq(dynLabel:raw("x"), 2)
    end)
end
