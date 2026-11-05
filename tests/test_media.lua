-- tests/test_media.lua
-- The charts, image and bigfont modules.
-- Ported from the deleted 2.5 smoke test (2062cc6:test_smoke.lua).

return function(T)
    T.test("a graph plots its series points", function()
        local basalt, frame, win = T.frame(30, 12)
        basalt.use("charts")
        local g = frame:addGraph({ x = 1, y = 1, width = 10, height = 5, maxValue = 10 })
        g:addSeries("s", { symbol = " ", bg = colors.red, pointCount = 5 })
        g:addPoint("s", 0)
        g:addPoint("s", 10)
        basalt.update()
        T.eq(T.bg(win, 1, 5), colors.red, "the low point")
        T.eq(T.bg(win, 3, 1), colors.red, "the high point")
    end)

    T.test("a bar chart scales its bars to the data maximum", function()
        local basalt, frame, win = T.frame(30, 12)
        basalt.use("charts")
        local bc = frame:addBarChart({ x = 12, y = 1, width = 7, height = 4 })
        bc.data = { 1, 2, 4 }
        basalt.update()
        T.eq(T.bg(win, 16, 1), colors.lime, "the tallest bar reaches the top")
        T.ok(T.bg(win, 12, 1) ~= colors.lime, "the short bar does not")
        T.eq(T.bg(win, 12, 4), colors.lime, "the short bar starts at the bottom")
    end)

    T.test("a line chart spans its width", function()
        local basalt, frame, win = T.frame(30, 12)
        basalt.use("charts")
        local lc = frame:addLineChart({ x = 1, y = 7, width = 10, height = 4, maxValue = 4 })
        lc.data = { 0, 4 }
        basalt.update()
        T.eq(T.bg(win, 1, 10), colors.lime, "the start at the bottom")
        T.eq(T.bg(win, 10, 7), colors.lime, "the end at the top")
    end)

    T.test("an image auto-sizes, draws and switches frames", function()
        local basalt, frame, win = T.frame(30, 12)
        basalt.use("image")
        local img = frame:addImage({ x = 12, y = 7 })
        img.bimg = { { { "AB", "00", "ee" }, { "CD", "00", "ee" } } }
        T.eq(img.width, 2); T.eq(img.height, 2)
        basalt.update()
        T.eq(T.row(win, 7):sub(12, 13), "AB")
        T.eq(T.row(win, 8):sub(12, 13), "CD")
        T.eq(T.bg(win, 12, 7), colors.red, "image colors")
        img.bimg = { { { "X", "0", "e" } }, { { "Y", "0", "e" } } }
        img:nextFrame()
        T.eq(img.currentFrame, 2)
        basalt.update()
        T.eq(T.row(win, 7):sub(12, 12), "Y", "the second frame")
    end)

    T.test("a big font character is 3x3 at size 1", function()
        local basalt, frame, win = T.frame(30, 12)
        basalt.use("bigfont")
        local bf = frame:addBigFont({ x = 20, y = 7, text = "A", fontSize = 1 })
        T.eq(bf.width, 3); T.eq(bf.height, 3)
        basalt.update()
        local glyph = T.row(win, 7):sub(20, 22) .. T.row(win, 8):sub(20, 22)
        T.ok(glyph:find("[^ ]"), "the glyph is not empty")
        T.raises(function() bf.fontSize = 5 end, "fontSize must be 1, 2 or 3")
    end)
end
