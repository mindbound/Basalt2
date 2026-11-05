-- tests/test_fix_palette.lua
-- With more than 16 colors Basalt rewrites hardware palette slots. When it
-- lets go of a slot (cleanup, basalt.run ending, a native color taking its
-- slot back, setTerm) the slot must get back the color the terminal had
-- before Basalt took it over, not CC's default palette.

-- A custom palette, clearly different from CC's defaults in every slot
local function customRGB(i)
    return (i * 15 + 7) / 255, (250 - i * 13) / 255, (i * 37 % 256) / 255
end

local function paint(t)
    for i = 0, 15 do t.setPaletteColour(2 ^ i, customRGB(i)) end
end

local function near(a, b)
    return math.abs(a - b) < 0.002
end

local function show(r, g, b)
    return string.format("(%.3f, %.3f, %.3f)", r, g, b)
end

-- Slots whose color is no longer the expected one (default: the custom one)
local function changedSlots(t, expected)
    expected = expected or customRGB
    local changed = {}
    for i = 0, 15 do
        local r, g, b = t.getPaletteColour(2 ^ i)
        local er, eg, eb = expected(i)
        if not (near(r, er) and near(g, eg) and near(b, eb)) then
            changed[#changed + 1] = i
        end
    end
    return changed
end

local function assertCustom(T, t, label)
    for i = 0, 15 do
        local r, g, b = t.getPaletteColour(2 ^ i)
        local er, eg, eb = customRGB(i)
        T.ok(near(r, er) and near(g, eg) and near(b, eb),
            label .. ": slot " .. i .. " should be the custom color "
            .. show(er, eg, eb) .. ", got " .. show(r, g, b))
    end
end

local function assertTaken(T, t, label)
    T.ok(#changedSlots(t) > 0, label .. ": Basalt should have taken palette slots")
end

-- n labels with distinct custom colors on row y (one cell each)
local function addColors(basalt, parent, n, y, hueShift)
    local labels = {}
    for i = 1, n do
        local f = (i + (hueShift or 0)) / (n + 1)
        labels[i] = parent:addLabel({
            x = i, y = y, text = " ",
            background = basalt.rgb(0.2 + f * 0.6, 0.15, 0.95 - f * 0.7),
        })
    end
    return labels
end

-- Runs basalt.run() and calls fn inside the loop (after the first draw);
-- the loop stops afterwards. With fail = true fn's error ends the run.
local function runOnce(basalt, fn)
    local ev = "basalt_fix_palette_" .. tostring(math.random(1, 1e9))
    basalt.schedule(function()
        os.pullEvent(ev)
        if fn then fn() end
        basalt.stop()
    end)
    os.queueEvent(ev)
    basalt.run()
end

-- A monitor stand-in: a window with the monitor-only methods. With a name
-- it also looks like a wrapped peripheral to peripheral.getName.
local function wrapMonitor(win, name)
    local mon = {}
    for k, v in pairs(win) do mon[k] = v end
    mon.setTextScale = function() end
    mon.getTextScale = function() return 1 end
    if name then
        setmetatable(mon, { __name = "peripheral", name = name, type = "monitor" })
    end
    return mon
end

local function fakeMonitor(T, w, h)
    local win = T.window(w, h)
    return wrapMonitor(win), win
end

-- A fresh core/palette module (its own registry), for direct checks
local function loadPalette(T)
    return assert(loadfile(T.src .. "/core/palette.lua", nil, _ENV))()
end

-- Sets every slot of a terminal to CC's default color
local function paintDefault(t)
    for i = 0, 15 do t.setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i)) end
end

local function nativeRGB(i)
    return term.nativePaletteColour(2 ^ i)
end

-- The color shown in a window cell's background (through its palette slot)
local function shownBg(T, win, x, y)
    return win.getPaletteColour(T.bg(win, x, y))
end

-- Copies a window, counting palette writes
local function counting(win)
    local t, count = {}, { writes = 0 }
    for k, v in pairs(win) do t[k] = v end
    t.setPaletteColour = function(...)
        count.writes = count.writes + 1
        return win.setPaletteColour(...)
    end
    t.setPaletteColor = t.setPaletteColour
    return t, count
end

return function(T)
    T.test("cleanup gives a custom palette back after many rgb colors", function()
        local basalt, frame, win = T.frame()
        paint(win)
        addColors(basalt, frame, 30, 2)
        basalt.update()
        assertTaken(T, win, "after the draw")
        frame:cleanup()
        assertCustom(T, win, "after cleanup")
    end)

    T.test("a native color taking its slot back gets the terminal's color", function()
        local basalt, frame, win = T.frame()
        paint(win)
        addColors(basalt, frame, 6, 2)
        basalt.update()
        local slot = changedSlots(win)[1]
        T.ok(slot, "a slot was taken")
        frame:addLabel({ x = 1, y = 5, text = " ", background = 2 ^ slot })
        basalt.update()
        local r, g, b = win.getPaletteColour(2 ^ slot)
        local er, eg, eb = customRGB(slot)
        T.ok(near(r, er) and near(g, eg) and near(b, eb),
            "slot " .. slot .. " shows the custom color again, got " .. show(r, g, b))
        frame:cleanup()
        assertCustom(T, win, "after cleanup")
    end)

    T.test("basalt.run gives the palette back when it stops", function()
        local basalt, frame, win = T.frame()
        paint(win)
        addColors(basalt, frame, 20, 2)
        local taken
        runOnce(basalt, function() taken = #changedSlots(win) end)
        T.ok(taken and taken > 0, "slots were taken while running")
        assertCustom(T, win, "after run")
    end)

    T.test("a second run after stop saves the terminal's colors again", function()
        local basalt, frame, win = T.frame()
        paint(win)
        frame:addLabel({ x = 1, y = 1, text = "hello" })
        addColors(basalt, frame, 20, 2)
        runOnce(basalt)
        assertCustom(T, win, "after the first run")

        -- the user changes a slot between the runs: that is the color to keep
        win.setPaletteColour(colors.orange, 0.5, 0.25, 0.125)
        local function expected(i)
            if i == 1 then return 0.5, 0.25, 0.125 end
            return customRGB(i)
        end
        local taken, row
        runOnce(basalt, function()
            taken = #changedSlots(win, expected)
            row = T.row(win, 1)
        end)
        T.ok(taken and taken > 0, "slots were taken during the second run")
        T.eq(row, "hello", "the second run repaints the screen")
        T.eq(#changedSlots(win, expected), 0, "slots changed after the second run")
        local r, g, b = win.getPaletteColour(colors.orange)
        T.ok(near(r, 0.5) and near(g, 0.25) and near(b, 0.125),
            "the user's orange is kept, got " .. show(r, g, b))
    end)

    T.test("cleanup after an error in the event loop gives the palette back", function()
        local basalt, frame, win = T.frame()
        paint(win)
        addColors(basalt, frame, 20, 2)
        local screen = T.window()
        local previous = term.redirect(screen) -- the error screen draws here
        local ev = "basalt_fix_palette_error"
        local taken
        basalt.schedule(function()
            os.pullEvent(ev)
            taken = #changedSlots(win)
            error("boom")
        end)
        os.queueEvent(ev)
        os.queueEvent("key", keys.enter) -- dismisses the error screen
        local ok, err = pcall(basalt.run)
        term.redirect(previous)
        T.ok(ok, tostring(err))
        T.ok(taken and taken > 0, "slots were taken before the error")
        assertCustom(T, win, "after the error")
    end)

    T.test("redraws, color changes and resizes keep the saved colors", function()
        local basalt, frame, win = T.frame(40, 10)
        paint(win)
        local labels = addColors(basalt, frame, 12, 2)
        basalt.update()
        -- new colors: slots get reassigned and rewritten
        for i, label in ipairs(labels) do
            label.background = basalt.rgb(0.1, 0.3 + i / 40, 0.2)
        end
        addColors(basalt, frame, 10, 3, 0.5)
        basalt.update()
        win.reposition(1, 1, 30, 8)
        basalt.update("term_resize")
        assertTaken(T, win, "after the resize")
        frame:cleanup()
        assertCustom(T, win, "after cleanup")
    end)

    T.test("two frames on one terminal give back the pre-Basalt colors", function()
        for _, order in ipairs({ "AB", "BA" }) do
            local basalt = T.loadBasalt()
            local win = T.window()
            paint(win)
            local a = basalt.createFrame(win)
            local b = basalt.createFrame(win)
            addColors(basalt, a, 10, 2)
            addColors(basalt, b, 10, 3, 0.37)
            basalt.update()
            assertTaken(T, win, order .. " after the draw")
            if order == "AB" then
                a:cleanup()
                b:cleanup()
            else
                b:cleanup()
                a:cleanup()
            end
            assertCustom(T, win, "cleanup order " .. order)
        end
    end)

    T.test("cleaning one frame keeps the slots another frame still uses", function()
        local basalt = T.loadBasalt()
        local win = T.window()
        paint(win)
        local a = basalt.createFrame(win)
        local b = basalt.createFrame(win)
        addColors(basalt, a, 8, 2)
        addColors(basalt, b, 8, 3, 0.4)
        basalt.update()
        local before = {}
        for i = 0, 15 do before[i] = { win.getPaletteColour(2 ^ i) } end
        a:cleanup()
        for i = 0, 15 do
            local r, g, b2 = win.getPaletteColour(2 ^ i)
            T.ok(near(r, before[i][1]) and near(g, before[i][2]) and near(b2, before[i][3]),
                "slot " .. i .. " still shows frame B's color")
        end
        b:cleanup()
        assertCustom(T, win, "after both cleanups")
    end)

    T.test("a monitor-like terminal and the main terminal both get theirs back", function()
        local basalt, frame, win = T.frame()
        local mon, monWin = fakeMonitor(T, 30, 10)
        paint(win)
        paint(monWin)
        -- a different user color on the monitor for one slot
        monWin.setPaletteColour(colors.magenta, 0.9, 0.9, 0.1)
        local monFrame = basalt.createFrame(mon)
        addColors(basalt, frame, 14, 2)
        addColors(basalt, monFrame, 14, 2, 0.21)
        local taken
        runOnce(basalt, function()
            taken = #changedSlots(win) > 0 and #changedSlots(monWin) > 0
        end)
        T.ok(taken, "both terminals had slots taken")
        assertCustom(T, win, "main terminal")
        for i = 0, 15 do
            local r, g, b = monWin.getPaletteColour(2 ^ i)
            local er, eg, eb = customRGB(i)
            if i == 2 then er, eg, eb = 0.9, 0.9, 0.1 end
            T.ok(near(r, er) and near(g, eg) and near(b, eb),
                "monitor slot " .. i .. ": got " .. show(r, g, b))
        end
    end)

    T.test("two wraps of one monitor share the saved colors", function()
        local basalt = T.loadBasalt()
        local screen = T.window(30, 10)
        paint(screen)
        -- every peripheral.wrap() returns a new table for the same screen
        local name = "basalt_fix_palette_monitor_0"
        local m1, m2 = wrapMonitor(screen, name), wrapMonitor(screen, name)
        T.eq(peripheral.getName(m2), name, "the stand-in looks like a peripheral")
        local f1 = basalt.createFrame(m1)
        local f2 = basalt.createFrame(m2)
        T.eq(rawget(f2, "monitor"), name, "the monitor name was detected")
        addColors(basalt, f1, 10, 2)
        addColors(basalt, f2, 10, 3, 0.37)
        basalt.update()
        assertTaken(T, screen, "after the draw")
        f1:cleanup()
        f2:cleanup()
        assertCustom(T, screen, "after both cleanups")
    end)

    T.test("a terminal without getPaletteColour falls back to CC's colors", function()
        local basalt = T.loadBasalt()
        local win = T.window()
        paint(win)
        local t = {}
        for k, v in pairs(win) do t[k] = v end
        t.getPaletteColour, t.getPaletteColor = nil, nil
        local frame = basalt.createFrame(t)
        addColors(basalt, frame, 6, 2)
        basalt.update()
        local taken = changedSlots(win)
        T.ok(#taken > 0, "slots were taken")
        frame:cleanup()
        local isTaken = {}
        for _, slot in ipairs(taken) do isTaken[slot] = true end
        for i = 0, 15 do
            local r, g, b = win.getPaletteColour(2 ^ i)
            local er, eg, eb
            if isTaken[i] then
                er, eg, eb = term.nativePaletteColour(2 ^ i)
            else
                er, eg, eb = customRGB(i)
            end
            T.ok(near(r, er) and near(g, eg) and near(b, eb),
                "slot " .. i .. ": got " .. show(r, g, b) .. ", expected " .. show(er, eg, eb))
        end
    end)

    T.test("setTerm gives the old terminal its palette back", function()
        local basalt, frame, win = T.frame()
        local other = T.window()
        paint(win)
        paint(other)
        addColors(basalt, frame, 12, 2)
        basalt.update()
        assertTaken(T, win, "first terminal after the draw")
        frame:setTerm(other)
        assertCustom(T, win, "first terminal after setTerm")
        basalt.update()
        assertTaken(T, other, "second terminal after the draw")
        -- binding to the same terminal again must not lose the saved colors
        frame:setTerm(other)
        basalt.update()
        frame:cleanup()
        assertCustom(T, other, "second terminal after cleanup")
    end)

    T.test("a Program's own palette colors are given back too", function()
        local path = T.tmpFile("fix_palette_prog.lua", table.concat({
            "term.setPaletteColour(colors.red, 0.1, 0.9, 0.3)",
            "term.setPaletteColour(colors.lime, 0.95, 0.1, 0.6)",
            "term.setBackgroundColor(colors.red)",
            "term.clear()",
            "term.setCursorPos(1, 1)",
            "term.setBackgroundColor(colors.lime)",
            "term.write('  ')",
            "os.pullEvent('basalt_fix_palette_never')",
        }, "\n"))
        local ok, err = pcall(function()
            local basalt, frame, win = T.frame()
            paint(win)
            addColors(basalt, frame, 4, 1)
            local prog = frame:addProgram({ x = 1, y = 3, width = 20, height = 6 })
            prog:execute(path)
            basalt.update()
            local found = false
            for i = 0, 15 do
                local r, g, b = win.getPaletteColour(2 ^ i)
                if near(r, 0.1) and near(g, 0.9) and near(b, 0.3) then found = true end
            end
            T.ok(found, "the program's red is shown")
            prog:terminate()
            frame:cleanup()
            assertCustom(T, win, "after cleanup")
        end)
        T.cleanTmp()
        if not ok then error(err, 0) end
    end)

    -- A visible window copies its parent's palette when it is created, and
    -- writes its own palette through to the parent. Created while Basalt
    -- holds slots of the parent, it starts with Basalt's colors.
    T.test("a frame on a window created after the first draw gives back the parent's colors", function()
        for _, order in ipairs({ "parent first", "child first" }) do
            local basalt = T.loadBasalt()
            local parent = T.window()
            paint(parent)
            local a = basalt.createFrame(parent)
            addColors(basalt, a, 10, 2)
            basalt.update()
            assertTaken(T, parent, order .. ": parent after the first draw")
            local child = window.create(parent, 1, 1, 30, 8, true)
            local b = basalt.createFrame(child)
            addColors(basalt, b, 10, 3, 0.37)
            basalt.update()
            assertTaken(T, child, order .. ": child after its draw")
            if order == "parent first" then
                -- basalt.run cleans the frames in creation order
                a:cleanup()
                b:cleanup()
            else
                b:cleanup()
                a:cleanup()
            end
            assertCustom(T, parent, order .. ": parent after both cleanups")
        end
    end)

    T.test("a window created while Basalt held a slot keeps the original after the slot is given back", function()
        local basalt = T.loadBasalt()
        local parent = T.window()
        paint(parent)
        local a = basalt.createFrame(parent)
        addColors(basalt, a, 10, 2)
        basalt.update()
        local child = window.create(parent, 1, 1, 30, 8, true)
        -- the parent gets its slots back; the child keeps its copy
        a:cleanup()
        assertCustom(T, parent, "parent after the first cleanup")
        local b = basalt.createFrame(child)
        addColors(basalt, b, 10, 3, 0.37)
        basalt.update()
        assertTaken(T, child, "child after its draw")
        b:cleanup()
        assertCustom(T, parent, "parent after the child frame's cleanup")
    end)

    T.test("a frame rebound to a window created after the first draw gives back the parent's colors", function()
        local basalt, frame, parent = T.frame()
        paint(parent)
        addColors(basalt, frame, 10, 2)
        basalt.update()
        local child = window.create(parent, 1, 1, 30, 8, true)
        frame:setTerm(child)
        assertCustom(T, parent, "parent after setTerm")
        basalt.update()
        assertTaken(T, child, "child after the draw")
        frame:cleanup()
        assertCustom(T, parent, "parent after cleanup")
    end)

    T.test("windowTranslation gives nil for a window with CC's palette", function()
        local palette = loadPalette(T)
        local win = T.window(4, 2)
        for i = 0, 15 do win.setPaletteColour(2 ^ i, palette.getRGB(2 ^ i)) end
        T.eq(palette.windowTranslation(win), nil, "translation of an untouched window")
        -- slot 1 (orange) set to slot 0's color (white) is a change too
        win.setPaletteColour(colors.orange, palette.getRGB(colors.white))
        local translate = palette.windowTranslation(win)
        T.ok(translate, "a changed slot 1 gives a translation")
        T.eq(translate["1"], string.char(0), "orange cells draw as white")
        T.eq(translate["0"], string.char(0), "white cells stay white")
        T.eq(translate["4"], string.char(4), "untouched yellow stays yellow")
    end)

    -- A Program's window copies the frame terminal's palette when it is
    -- created. Started after the first draw, it must not take Basalt's colors
    -- in some slots for the program's own.
    T.test("a Program started after the first draw shows its native colors", function()
        local path = T.tmpFile("fix_palette_native.lua", table.concat({
            "for i = 0, 15 do",
            "  term.setCursorPos(i + 1, 1)",
            "  term.setBackgroundColor(2 ^ i)",
            "  term.write(' ')",
            "end",
            "os.pullEvent('basalt_fix_palette_never')",
        }, "\n"))
        local ok, err = pcall(function()
            for _, variant in ipairs({ "CC palette", "custom palette" }) do
                local basalt, frame, win = T.frame()
                local expected = nativeRGB
                if variant == "custom palette" then
                    paint(win)
                    expected = customRGB
                else
                    paintDefault(win)
                end
                addColors(basalt, frame, 14, 1)
                basalt.update()
                T.ok(#changedSlots(win, expected) >= 10,
                    variant .. ": Basalt took most slots before the program starts")
                local prog = frame:addProgram({ x = 1, y = 3, width = 20, height = 2 })
                prog:execute(path)
                basalt.update()
                for i = 0, 15 do
                    local r, g, b = shownBg(T, win, i + 1, 3)
                    local er, eg, eb = expected(i)
                    T.ok(near(r, er) and near(g, eg) and near(b, eb),
                        variant .. ": program color " .. i .. " should show "
                        .. show(er, eg, eb) .. ", got " .. show(r, g, b))
                end
                prog:terminate()
                frame:cleanup()
                T.eq(#changedSlots(win, expected), 0, variant .. ": slots changed after cleanup")
            end
        end)
        T.cleanTmp()
        if not ok then error(err, 0) end
    end)

    T.test("a Program that sets orange to white's color draws white", function()
        local path = T.tmpFile("fix_palette_orange.lua", table.concat({
            "term.setPaletteColour(colors.orange, 0xF0F0F0)",
            "term.setBackgroundColor(colors.orange)",
            "term.setCursorPos(1, 1)",
            "term.write('  ')",
            "os.pullEvent('basalt_fix_palette_never')",
        }, "\n"))
        local ok, err = pcall(function()
            local basalt, frame, win = T.frame()
            paintDefault(win)
            local prog = frame:addProgram({ x = 1, y = 1, width = 10, height = 2 })
            prog:execute(path)
            basalt.update()
            local r, g, b = shownBg(T, win, 1, 1)
            local er, eg, eb = nativeRGB(0)
            T.ok(near(r, er) and near(g, eg) and near(b, eb),
                "the program's orange shows white, got " .. show(r, g, b))
            prog:terminate()
            frame:cleanup()
            T.eq(#changedSlots(win, nativeRGB), 0, "slots changed after cleanup")
        end)
        T.cleanTmp()
        if not ok then error(err, 0) end
    end)

    T.test("the theme module's colors are given back", function()
        local basalt, frame, win = T.frame()
        paint(win)
        basalt.use("theme").applyPreset("basalt")
        frame:addButton({ x = 2, y = 2, text = "OK" })
        frame:addLabel({ x = 2, y = 4, text = "label" })
        frame:addInput({ x = 2, y = 6, width = 10, placeholder = "type" })
        frame:addProgressBar({ x = 2, y = 8, width = 10, progress = 50 })
        local list = frame:addList({ x = 20, y = 2, width = 10, height = 4 })
        list:addItem("one")
        list:addItem("two")
        list.selected = 1
        local taken
        runOnce(basalt, function() taken = #changedSlots(win) end)
        T.ok(taken and taken > 0, "the theme took palette slots")
        assertCustom(T, win, "after run")
    end)

    T.test("16-color apps never write the palette", function()
        local basalt = T.loadBasalt()
        local win = T.window()
        paint(win)
        local t, count = counting(win)
        local frame = basalt.createFrame(t)
        frame:addLabel({ x = 1, y = 1, text = "hi", background = colors.blue })
        frame:addButton({ x = 1, y = 3, text = "OK" })
        basalt.update()
        T.click(basalt, 2, 3)
        frame:cleanup()
        T.eq(count.writes, 0, "palette writes with native colors only")

        -- the theme module registers RGB colors: still no writes while only
        -- native colors are on screen
        local basalt2 = T.loadBasalt()
        basalt2.use("theme")
        local t2, count2 = counting(win)
        local frame2 = basalt2.createFrame(t2)
        frame2:addLabel({ x = 1, y = 1, text = "hi", background = colors.blue })
        basalt2.update()
        frame2:cleanup()
        T.eq(count2.writes, 0, "palette writes with the theme module loaded")
        assertCustom(T, win, "the palette is untouched")
    end)
end
