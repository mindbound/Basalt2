-- tests/test_scroll.lua
-- Scrollable containers: automatic bars, wheel, hit testing through the
-- offset, thumb dragging, hidden bars, horizontal fallback, disabling,
-- and cached layout / viewport culling. Ported from the deleted 2.5 tests
-- (2062cc6:test_smoke.lua and 2062cc6:test_scroll_performance.lua); the
-- performance checks count work done, never milliseconds.

return function(T)
    -- a 10x4 scrollable column with eight one-row buttons
    local function scrollColumn()
        local basalt, sf, win = T.frame(20, 8)
        local s = { basalt = basalt, sf = sf, win = win, items = {} }
        s.sc = sf:addColumn({
            x = 1, y = 1, width = 10, height = 4,
            scrollable = true, scrollbar = "auto",
            scrollXEnabled = false, scrollYEnabled = true,
            scrollStep = 3,
        })
        for i = 1, 8 do
            local index = i
            s.items[i] = s.sc:addButton({
                text = "Item " .. i, width = basalt.fill(), height = 1,
            }):onClick(function() s.clicked = index end)
        end
        sf:draw()
        return s
    end

    T.test("overflowing content shows a vertical bar", function()
        local s = scrollColumn()
        local info = s.sc:getScrollInfo()
        T.ok(info.showY, "vertical bar")
        T.ok(not info.showX, "no horizontal bar")
        T.eq(info.maxY, 4)
        local w, h = s.sc:getContentSize()
        T.eq(w, 10); T.eq(h, 8)
    end)

    T.test("the wheel scrolls and clicks hit through the offset", function()
        local s = scrollColumn()
        s.basalt.update("mouse_scroll", 1, 2, 2)
        local x, y = s.sc:getScroll()
        T.eq(x, 0); T.eq(y, 3)
        T.click(s.basalt, 2, 1) -- offset 3: Item 4
        T.eq(s.clicked, 4)
    end)

    T.test("dragging the thumb scrolls", function()
        local s = scrollColumn()
        s.basalt.update("mouse_click", 1, 10, 1) -- grab the thumb
        s.basalt.update("mouse_drag", 1, 10, 3)
        s.basalt.update("mouse_up", 1, 10, 3)
        T.eq(select(2, s.sc:getScroll()), 4)
    end)

    T.test("ensureVisible scrolls just enough", function()
        local s = scrollColumn()
        s.sc:scrollTo(0, 0):ensureVisible(s.items[8])
        T.eq(select(2, s.sc:getScroll()), 4)
    end)

    T.test("a hidden bar is not drawn but the wheel still scrolls", function()
        local s = scrollColumn()
        T.eq(T.bg(s.win, 10, 1), colors.lightGray, "the thumb is drawn")
        s.sc.scrollbar = "hidden"
        s.sf:draw()
        T.ok(not s.sc:getScrollInfo().showY, "no bar")
        T.eq(T.bg(s.win, 10, 1), colors.gray, "the button shows through")
        s.basalt.update("mouse_scroll", 1, 2, 2)
        T.eq(select(2, s.sc:getScroll()), 3)
    end)

    T.test("a focused input scrolled out of view hides the cursor", function()
        local s = scrollColumn()
        s.sc:addInput({ width = s.basalt.fill(), height = 1, text = "cursor" })
        s.sf:draw()
        s.sc:scrollTo(0, 5)
        T.click(s.basalt, 2, 4) -- the input is on the last visible row
        T.eq(s.sf._render.cursorBlink, true, "visible input shows the cursor")
        s.sc:scrollTo(0, 0)
        s.sf:draw()
        T.eq(s.sf._render.cursorBlink, false, "off-viewport input hides it")
    end)

    T.test("a horizontal container falls back to horizontal wheel scrolling", function()
        local basalt, sf = T.frame(20, 8)
        local row = sf:addRow({
            x = 12, y = 1, width = 6, height = 2,
            scrollable = true, scrollbar = "auto",
            scrollXEnabled = true, scrollYEnabled = false,
        })
        row:addButton({ text = "A", width = 5, height = 1 })
        row:addButton({ text = "B", width = 5, height = 1 })
        sf:draw()
        T.ok(row:getScrollInfo().showX, "horizontal bar")
        basalt.update("mouse_scroll", 1, 13, 1)
        T.eq(select(1, row:getScroll()), 3)
    end)

    T.test("disabling scrolling resets the offset and ignores the wheel", function()
        local s = scrollColumn()
        s.basalt.update("mouse_scroll", 1, 2, 2)
        s.sc.scrollable = false
        s.sf:draw()
        local x, y = s.sc:getScroll()
        T.eq(x, 0); T.eq(y, 0)
        T.ok(not s.sc:getScrollInfo().showY, "no bar")
        s.basalt.update("mouse_scroll", 1, 2, 2)
        T.eq(select(2, s.sc:getScroll()), 0)
    end)

    -------------------------------------------- cached layout and culling
    -- 200 buttons in a 12x5 scrollable column; layout passes and child
    -- renders are counted
    local function bigColumn()
        local basalt, frame = T.frame()
        local p = { basalt = basalt, frame = frame, layouts = 0, renders = 0, buttons = {} }
        p.content = frame:addColumn({
            x = 1, y = 1, width = 12, height = 5, gap = 0,
            scrollable = true, scrollXEnabled = false, scrollYEnabled = true,
            scrollStep = 3,
        })
        p.content:onLayout(function() p.layouts = p.layouts + 1 end)
        for i = 1, 200 do
            local button = p.content:addButton({
                text = "Item " .. i, width = basalt.fill(), height = 1,
            })
            local original = button.render
            button.render = function(self, buf)
                p.renders = p.renders + 1
                return original(self, buf)
            end
            p.buttons[i] = button
        end
        frame:draw()
        return p
    end

    T.test("the first draw lays out once and renders only visible children", function()
        local p = bigColumn()
        T.eq(p.layouts, 1, "one initial layout pass")
        T.ok(p.renders >= 5, "the visible children were rendered: " .. p.renders)
        T.ok(p.renders <= 6, "offscreen children rendered: " .. p.renders)
        local w, h = p.content:getContentSize()
        T.eq(w, 12); T.eq(h, 200)
    end)

    T.test("scrolling reuses the layout and culls offscreen children", function()
        local p = bigColumn()
        p.renders = 0
        p.content:scrollTo(0, 50)
        p.frame:draw()
        T.eq(p.layouts, 1, "scrolling does not lay out again")
        T.ok(p.renders >= 5, "the visible children were rendered: " .. p.renders)
        T.ok(p.renders <= 6, "offscreen children rendered: " .. p.renders)
        T.eq(p.frame:findAt(1, 1), p.buttons[51], "hit testing follows the scroll")
    end)

    T.test("a content change lays out again and keeps culling", function()
        local p = bigColumn()
        p.content:scrollTo(0, 50)
        p.frame:draw()
        p.renders = 0
        p.buttons[100].text = "Changed width-affecting text"
        p.frame:draw()
        T.eq(p.layouts, 2, "the mutation invalidated the layout")
        T.ok(p.renders <= 6, "offscreen children rendered: " .. p.renders)
    end)

    T.test("a paint-only state change does not lay out again", function()
        local p = bigColumn()
        p.content:scrollTo(0, 50)
        p.frame:draw()
        p.renders = 0
        p.buttons[51]:setStateStyle("hover", { background = colors.blue })
        p.buttons[51]:setState("hover", true)
        p.frame:draw()
        T.eq(p.layouts, 1, "hover is paint-only")
        T.ok(p.renders <= 6, "offscreen children rendered: " .. p.renders)
        T.ok(p.renders >= 1, "the visible children were redrawn")
    end)
end
