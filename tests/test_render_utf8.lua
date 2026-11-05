-- tests/test_render_utf8.lua
-- The render buffer with the Unicode Support mod: rows always hold exactly
-- `width` cells, so the mod's strict term.blit accepts them

return function(T)
    local M = assert(loadfile(T.root .. "/tests/modsim.lua", nil, _ENV))(T)

    local CAFE = "caf\195\169"
    local DASH = "\226\128\148"
    local SAMPLE = CAFE .. " " .. DASH .. " 17 \194\176C" -- 12 cells

    -- Every row of the buffer: text cells == fg bytes == bg bytes == width
    local function checkRows(text, render)
        for y = 1, render.height do
            local cells = text.width(render.text[y])
            T.eq(cells, render.width, "text cells in row " .. y)
            T.eq(text.byteLen(render.fg[y]), render.width, "fg bytes in row " .. y)
            T.eq(text.byteLen(render.bg[y]), render.width, "bg bytes in row " .. y)
        end
    end

    T.test("UTF-8 text is drawn in its cells and redraws stay stable", function()
        local basalt, frame, t = M.frame(20, 4)
        local label = frame:addLabel({ x = 2, y = 2, text = SAMPLE })
        frame:addLabel({ x = 15, y = 2, text = "|" })
        for _ = 1, 3 do
            basalt.update()
            label.text = label.text -- unchanged, but redrawn
            frame:markRenderDirty()
        end
        basalt.update()
        T.eq(M.row(t, 2), " " .. SAMPLE .. " |", "the bar stays in column 15")
        checkRows(basalt.text, rawget(frame, "_render"))
    end)

    T.test("labels next to each other keep their cells", function()
        local basalt, frame, t = M.frame(12, 2)
        frame:addLabel({ x = 1, y = 1, text = DASH .. DASH })
        frame:addLabel({ x = 3, y = 1, text = "ab" })
        frame:addLabel({ x = 5, y = 1, text = CAFE })
        basalt.update()
        T.eq(M.row(t, 1), DASH .. DASH .. "ab" .. CAFE)
        checkRows(basalt.text, rawget(frame, "_render"))
    end)

    T.test("text is clipped by cells at the edges", function()
        local basalt, frame, t = M.frame(6, 2)
        frame:addLabel({ x = -1, y = 1, text = DASH .. "123" .. DASH .. "45678" })
        basalt.update()
        T.eq(M.row(t, 1), "23" .. DASH .. "456")
        checkRows(basalt.text, rawget(frame, "_render"))
    end)

    T.test("a CC-charset letter next to drawing characters stays separate", function()
        local basalt, frame, t = M.frame(8, 2)
        -- "\233" (é in the CC charset) right before two teletext bytes would
        -- otherwise decode as one character
        frame:addLabel({ x = 1, y = 1, text = "x\233" })
        frame:addLabel({ x = 3, y = 1, text = "\149\149" })
        basalt.update()
        T.eq(#M.cells((t.getLine(1))), 8)
        T.eq(M.row(t, 1), "x\195\169\149\149")
        checkRows(basalt.text, rawget(frame, "_render"))
    end)

    T.test("raw, coloured and masked blits keep rows whole", function()
        local basalt, frame, t = M.frame(10, 3)
        local canvas = frame:addCanvas({ x = 1, y = 1, width = 10, height = 3 })
        canvas.draw = function(_, buf)
            buf:blit(1, 1, SAMPLE, colors.white, colors.black)
            buf:colorBlit(1, 2, CAFE, { colors.red, colors.red, colors.red, colors.blue },
                { colors.black, colors.black, colors.black, colors.black })
            buf:drawBlit(6, 2, DASH .. "z", "00", "ff")
            buf:fill(1, 3, 10, 1, DASH, colors.white, colors.gray)
            buf:drawText(3, 3, CAFE)
        end
        basalt.update()
        T.eq(M.row(t, 1), "caf\195\169 " .. DASH .. " 17", "clipped at 10 cells")
        T.eq(M.row(t, 2), CAFE .. " " .. DASH .. "z")
        T.eq(M.row(t, 3), DASH .. DASH .. CAFE .. DASH:rep(4))
        local _, fg = t.getLine(2)
        T.eq(fg:sub(4, 4), "b", "the colour of the 4th cell (blue)")
        checkRows(basalt.text, rawget(frame, "_render"))
    end)

    -- Every row of a window or terminal: as many cells as colours
    local function checkTerm(t, cellsOf)
        local w, h = t.getSize()
        for y = 1, h do
            local line, fg, bg = t.getLine(y)
            T.eq(#cellsOf(line), w, "cells in terminal row " .. y)
            T.eq(#fg, w, "fg in terminal row " .. y)
            T.eq(#bg, w, "bg in terminal row " .. y)
        end
    end

    local function fractionalDraws(basalt, frame, w)
        local canvas = frame:addCanvas({ x = 1, y = 1, width = w, height = 6 })
        canvas.draw = function(_, buf)
            buf:blit(0.5, 1, "abcd", colors.white, colors.blue)          -- left clip
            buf:blit(w - 1.5, 2, "abcd", colors.white, colors.blue)      -- right clip
            buf:drawText(-0.5, 3, "xyz")
            buf:rawBlit(0.5, 4, "abcd", "\0\0\0\0", "\11\11\11\11")
            buf:maskedBlit(w - 1.5, 5, "abcd", "\0\0\0\0", "\11\11\11\11")
            buf:drawPixels(0.5, 6, 4, 3, { "\1\1\1\1", "\1\0\0\1", "\1\1\1\1" },
                { [1] = string.char(14) })
        end
        frame:addLabel({ x = 0.5, y = 2, text = "hello", background = colors.red })
        basalt.update()
    end

    T.test("fractional positions clipped on one side keep rows whole (no mod)", function()
        local basalt, frame, win = T.frame(10, 6)
        T.ok(pcall(fractionalDraws, basalt, frame, 10))
        checkRows(basalt.text, rawget(frame, "_render"))
        checkTerm(win, function(s) return { s:byte(1, -1) } end)
    end)

    T.test("fractional positions clipped on one side keep rows whole (mod)", function()
        local basalt, frame, t = M.frame(10, 6)
        fractionalDraws(basalt, frame, 10)
        checkRows(basalt.text, rawget(frame, "_render"))
        checkTerm(t, M.cells)
    end)

    T.test("colour planes longer than their text can't widen a row (mod)", function()
        local basalt, frame, t = M.frame(8, 3)
        local canvas = frame:addCanvas({ x = 1, y = 1, width = 8, height = 3 })
        canvas.draw = function(_, buf)
            -- e.g. planes sized with # under the mod, or merged getLine rows
            buf:rawBlit(6, 1, CAFE, "\0\0\0\0\0", "\15\15\15\15\15")
            buf:drawBlit(6, 2, CAFE .. DASH, "0000000", "fffffff")
            buf:maskedBlit(6, 3, CAFE, "\0\0\0\0\0", "\15\15\15\15\15")
        end
        basalt.update()
        checkRows(basalt.text, rawget(frame, "_render"))
        checkTerm(t, M.cells)
    end)

    T.test("draw calls reject text that is not a string or number", function()
        local basalt, frame = T.frame(10, 2)
        local canvas = frame:addCanvas({ x = 1, y = 1, width = 10, height = 2 })
        local bad = { "blit", "drawText", "rawBlit", "maskedBlit", "colorBlit" }
        local errors = {}
        canvas.draw = function(_, buf)
            for _, name in ipairs(bad) do
                local ok, err = pcall(buf[name], buf, 1, 1, nil)
                errors[#errors + 1] = not ok and tostring(err) or ("no error from " .. name)
            end
            buf:blit(1, 2, 42, colors.white, colors.black)
        end
        basalt.update()
        for _, err in ipairs(errors) do
            T.contains(err, "text must be a string")
        end
    end)

    T.test("without the mod nothing changes", function()
        local basalt, frame, win = T.frame(20, 2)
        frame:addLabel({ x = 1, y = 1, text = "abc" })
        basalt.update()
        T.eq(T.row(win, 1), "abc")
        T.eq(basalt.text.isUtf8(), false)
    end)
end
