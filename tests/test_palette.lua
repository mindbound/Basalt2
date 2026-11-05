-- tests/test_palette.lua
-- basalt.rgb parsing/deduplication and more than 16 colors on screen.
-- Ported from the deleted 2.5 smoke test (2062cc6:test_smoke.lua).

return function(T)
    T.test("a custom root background", function()
        local basalt, frame = T.frame()
        frame:setBackground(basalt.rgb("#1e1e2e"))
        T.ok(frame.width > 0 and frame.height > 0, "the frame has a size")
        basalt.update()
    end)

    T.test("rgb deduplicates equal colors", function()
        local basalt = T.loadBasalt()
        T.eq(basalt.rgb("#89b4fa"), basalt.rgb(0x89b4fa))
        T.eq(basalt.rgb(0x89, 0xb4, 0xfa), basalt.rgb("#89b4fa"), "r, g, b")
        T.eq(basalt.rgb("#cc4c4c"), colors.red, "a native color stays native")
    end)

    T.test("rgb parses ARGB, #RGB and rejects invalid input", function()
        local basalt = T.loadBasalt()
        T.eq(basalt.rgb("FF4E158F"), basalt.rgb("#4E158F"), "ARGB alpha is ignored")
        T.eq(basalt.rgb("abc"), basalt.rgb("#aabbcc"), "#RGB shorthand")
        T.raises(function() basalt.rgb("#12345") end, "invalid color string")
        T.raises(function() basalt.rgb("gr\195\188n") end, "invalid color string")
        T.raises(function() basalt.rgb(-5) end, "invalid color number")
    end)

    T.test("more than 16 colors: free slots first, then nearest match", function()
        local basalt, frame, win = T.frame()
        for i = 1, 30 do
            frame:addLabel({
                x = i, y = 12, text = " ",
                background = basalt.rgb(i / 30, 0.5, 1 - i / 30),
            })
        end
        basalt.update() -- must not fail with 32 colors on screen
        -- the first registered custom color gets a free hardware slot
        local r, g, b = win.getPaletteColour(T.bg(win, 1, 12))
        T.ok(math.abs(r - 1 / 30) < 0.01 and math.abs(g - 0.5) < 0.01
            and math.abs(b - (1 - 1 / 30)) < 0.01,
            "the first custom color owns a real palette slot")
        -- the native colors on screen keep their own slots
        T.eq(T.bg(win, 31, 12), colors.black, "the root background")
        local nr, ng, nb = win.getPaletteColour(colors.black)
        T.ok(nr < 0.1 and ng < 0.1 and nb < 0.1, "black is still black")
    end)
end
