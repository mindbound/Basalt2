-- tests/test_layout.lua
-- Layout tokens (auto/fill/percent), Row/Column flow, constraints, shrink,
-- nested auto sizes, terminal resize and the responsive module.
-- Ported from the deleted 2.5 smoke test (2062cc6:test_smoke.lua).

return function(T)
    -- a 40x15 root with a padded row (auto, fill, percent+max, absolute)
    -- and a half-width column below it
    local function flowLayout()
        local basalt, lf, win = T.frame(40, 15)
        local l = { basalt = basalt, lf = lf, win = win, clicks = 0 }
        l.row = lf:addRow({
            x = 1, y = 1, width = basalt.fill(), height = 5,
            padding = 1, gap = 1, align = "center",
        })
        l.left = l.row:addLabel({ text = "A", width = basalt.auto(), height = basalt.auto() })
        l.middle = l.row:addButton({ text = "Grow", width = basalt.fill(), height = basalt.auto() })
            :onClick(function() l.clicks = l.clicks + 1 end)
        l.right = l.row:addLabel({
            text = "Right", width = basalt.percent(0.25), height = basalt.auto(),
            maxWidth = 6,
        })
        l.abs = l.row:addLabel({ position = "absolute", x = 35, y = 1, text = "ABS" })
        l.column = lf:addColumn({
            x = 1, y = 7, width = basalt.percent(0.5), height = basalt.fill(),
            padding = 1, gap = 1,
        })
        l.top = l.column:addLabel({ text = "Top", width = basalt.auto(), height = basalt.auto() })
        l.growing = l.column:addInput({ width = basalt.fill(), height = basalt.fill() })
        lf:draw()
        return l
    end

    T.test("a row resolves fill, auto, align and maxWidth", function()
        local l = flowLayout()
        T.eq(l.row.width, 40); T.eq(l.row.height, 5)
        T.eq(l.left.x, 2, "auto x"); T.eq(l.left.width, 1, "auto width")
        T.eq(l.left.y, 3, "centered on the cross axis")
        T.eq(l.right.width, 6, "maxWidth caps the percent width")
        T.eq(l.middle.width, 29, "fill takes the rest")
        T.eq(l.middle.x, 4); T.eq(l.right.x, 34)
        T.eq(l.abs.x, 35, "absolute children keep their position")
        T.eq(l.abs.y, 1)
    end)

    T.test("a column resolves percent and fill sizes", function()
        local l = flowLayout()
        T.eq(l.column.width, 20); T.eq(l.column.height, 9)
        T.eq(l.top.x, 2); T.eq(l.top.y, 2)
        T.eq(l.growing.x, 2); T.eq(l.growing.y, 4)
        T.eq(l.growing.width, 18); T.eq(l.growing.height, 5)
    end)

    T.test("hit testing uses the resolved geometry", function()
        local l = flowLayout()
        T.click(l.basalt, l.middle.x + 1, l.middle.y + 1)
        T.eq(l.clicks, 1)
    end)

    T.test("a terminal resize re-runs the layout", function()
        local l = flowLayout()
        l.win.reposition(1, 1, 50, 15)
        l.basalt.update("term_resize")
        T.eq(l.row.width, 50)
        T.eq(l.middle.width, 39)
    end)

    T.test("a nested frame clips its children", function()
        local basalt, frame, win = T.frame()
        local sub = frame:addFrame({ x = 5, y = 3, width = 10, height = 4 })
        sub:addLabel({ x = 8, y = 2, text = "clipped-text-far-too-long" })
        basalt.update()
        -- the label starts at x 12; the frame ends at x 14
        T.eq(T.row(win, 4), (" "):rep(11) .. "cli")
        T.eq(T.bg(win, 15, 4), colors.black, "nothing drawn past the frame")
    end)

    T.test("intrinsic children shrink before fixed ones, down to minWidth", function()
        local basalt, lf = T.frame(40, 15)
        local row = lf:addRow({ x = 1, y = 1, width = 10, height = 3, gap = 1 })
        local shrinkable = row:addLabel({
            text = "12345678", width = basalt.auto(), minWidth = 3,
        })
        local fixed = row:addButton({ text = "F", width = 5, height = 3 })
        lf:draw()
        T.eq(shrinkable.width, 4)
        T.eq(fixed.width, 5)
    end)

    T.test("nested auto sizes are measured inside-out", function()
        local basalt, lf = T.frame(40, 15)
        local outer = lf:addColumn({
            x = 1, y = 7, width = basalt.auto(), height = basalt.auto(),
            padding = 1,
        })
        local inner = outer:addRow({
            width = basalt.auto(), height = basalt.auto(), gap = 1,
        })
        inner:addLabel({ text = "Hi", width = basalt.auto(), height = basalt.auto() })
        inner:addButton({ text = "Go", width = basalt.auto(), height = basalt.auto() })
        lf:draw()
        T.eq(outer.width, 9); T.eq(outer.height, 5)
        T.eq(inner.width, 7); T.eq(inner.height, 3)
        T.eq(inner.x, 2); T.eq(inner.y, 2)
    end)

    T.test("a layout token from a state style stays a token", function()
        local basalt, lf = T.frame(40, 15)
        local row = lf:addRow({ x = 1, y = 1, width = 20, height = 3, gap = 1 })
        local sized = row:addButton({ text = "State", width = 5, height = 3 })
        row:addButton({ text = "Fixed", width = 5, height = 3 })
        sized:setStateStyle("expanded", { width = basalt.fill() })
        sized:setState("expanded", true)
        lf:draw()
        T.eq(sized.width, 14)
        sized:setState("expanded", false)
        lf:draw()
        T.eq(sized.width, 5, "back to the authored width")
    end)

    T.test("responsive breakpoints switch named states and props", function()
        local basalt, lf, win = T.frame(40, 15)
        local responsive = basalt.use("responsive")
        local panel = lf:addFlex({
            x = 1, y = 1, width = basalt.fill(), height = 6,
            direction = "row", gap = 1,
        })
        local one = panel:addButton({ text = "One", width = 6, height = 2 })
        local two = panel:addButton({ text = "Two", width = 6, height = 2 })
        responsive.apply(panel, {
            { name = "compact", maxWidth = 30, props = { direction = "column" } },
            { name = "wide", minWidth = 31, props = { direction = "row" } },
        })
        win.reposition(1, 1, 50, 15)
        basalt.update("term_resize")
        T.ok(panel:hasState("wide") and not panel:hasState("compact"), "wide state")
        T.ok(two.x > one.x and two.y == one.y, "row direction")
        win.reposition(1, 1, 25, 15)
        basalt.update("term_resize")
        T.ok(panel:hasState("compact") and not panel:hasState("wide"), "compact state")
        T.ok(two.y > one.y and two.x == one.x, "column direction")
        panel:clearResponsive()
        lf:draw()
        T.eq(panel.direction, "row", "cleanup restores the authored props")
        T.ok(not panel:hasState("compact"), "cleanup clears the states")
    end)
end
