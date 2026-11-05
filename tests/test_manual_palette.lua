-- tests/test_manual_palette.lua
-- Driving Basalt with basalt.update instead of basalt.run (basalt.cleanup,
-- basalt.repaint, resizes and errors through update), and handing the
-- palette back while Basalt keeps drawing (basalt.suspendPalette /
-- basalt.resumePalette), e.g. while a shell command runs.

-- A custom palette, clearly different from CC's defaults in every slot
local function customRGB(i)
    return (i * 15 + 7) / 255, (250 - i * 13) / 255, (i * 37 % 256) / 255
end

local function paint(t)
    for i = 0, 15 do t.setPaletteColour(2 ^ i, customRGB(i)) end
end

-- CC's default palette (the headless emulator's terminal starts with others)
local function paintDefault(t)
    for i = 0, 15 do t.setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i)) end
end

local function near(a, b)
    return math.abs(a - b) < 0.002
end

local function show(r, g, b)
    return string.format("(%.3f, %.3f, %.3f)", r, g, b)
end

-- Slots whose color is not the custom one
local function changedSlots(t)
    local changed = {}
    for i = 0, 15 do
        local r, g, b = t.getPaletteColour(2 ^ i)
        local er, eg, eb = customRGB(i)
        if not (near(r, er) and near(g, eg) and near(b, eb)) then
            changed[#changed + 1] = i
        end
    end
    return changed
end

local function assertCustom(T, t, label)
    local changed = changedSlots(t)
    T.eq(#changed, 0, label .. ": slots that are not the terminal's own color ("
        .. table.concat(changed, ", ") .. ")")
end

local function assertTaken(T, t, label)
    T.ok(#changedSlots(t) > 0, label .. ": Basalt should have taken palette slots")
end

-- A custom color just next to the terminal's own color of a slot
local function nextTo(basalt, slot)
    local r, g, b = customRGB(slot)
    return basalt.rgb(r + 0.01, g, b)
end

-- The color shown in a window cell's background (through its palette slot)
local function shownBg(T, win, x, y)
    return win.getPaletteColour(T.bg(win, x, y))
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

-- Runs fn with term.current() redirected to a fresh window (where an error
-- screen would be drawn) and returns that window
local function onScreen(T, fn)
    local screen = T.window()
    local previous = term.redirect(screen)
    screen.setCursorPos(1, 1)
    screen.write("app screen")
    local ok, err = pcall(fn)
    term.redirect(previous)
    if not ok then error(err, 0) end
    return screen
end

-- Records basalt.run's error screens instead of showing them (no key wait)
local function catchErrorScreen(basalt)
    local shown = {}
    basalt.errors.show = function(err, trace)
        shown[#shown + 1] = { err = err, trace = trace }
    end
    return shown
end

-- The line after the one that calls it (where a test raises its error)
local function nextLine()
    return debug.getinfo(2, "l").currentline + 1
end

return function(T)
    T.test("suspendPalette gives the terminal's own colors back", function()
        local basalt, frame, win = T.frame()
        paint(win)
        addColors(basalt, frame, 12, 2)
        basalt.update()
        assertTaken(T, win, "after the draw")
        T.eq(basalt.isPaletteSuspended(), false)
        basalt.suspendPalette()
        T.eq(basalt.isPaletteSuspended(), true)
        assertCustom(T, win, "while suspended")
        basalt.resumePalette()
        T.eq(basalt.isPaletteSuspended(), false)
        assertTaken(T, win, "after resume")
        basalt.cleanup()
        assertCustom(T, win, "after cleanup")
    end)

    T.test("while suspended RGB colors are drawn as the nearest own color", function()
        local basalt, frame, win = T.frame()
        paint(win)
        frame:addLabel({ x = 1, y = 1, text = "  ", background = nextTo(basalt, 3) })
        frame:addLabel({ x = 4, y = 1, text = "  ", background = nextTo(basalt, 9) })
        frame:addLabel({ x = 1, y = 2, text = "hi", foreground = nextTo(basalt, 12) })
        basalt.update()
        basalt.suspendPalette()
        T.eq(T.bg(win, 1, 1), 2 ^ 3, "a color next to slot 3's own color")
        T.eq(T.bg(win, 4, 1), 2 ^ 9, "a color next to slot 9's own color")
        T.eq(T.fg(win, 1, 2), 2 ^ 12, "a text color next to slot 12's own color")
        T.eq(T.row(win, 2), "hi")
        basalt.resumePalette()
        basalt.cleanup()
    end)

    T.test("a dark RGB background is drawn black with CC's palette", function()
        -- the shell-command case of the cc-code survey (experiment F2)
        local basalt, frame, win = T.frame()
        paintDefault(win)
        frame.background = basalt.rgb("#1e1e2e")
        local status = frame:addLabel({ x = 1, y = 19, text = "Thinking" })
        basalt.update()
        local slot = T.bg(win, 1, 5)
        T.ok(slot ~= colors.black, "the custom background has a slot of its own")
        basalt.suspendPalette()
        T.eq(T.bg(win, 1, 5), colors.black, "the background while suspended")
        local r, g, b = win.getPaletteColour(slot)
        local er, eg, eb = term.nativePaletteColour(slot)
        T.ok(near(r, er) and near(g, eg) and near(b, eb),
            "the borrowed slot shows its own color again, got " .. show(r, g, b))
        status.text = "Running shell 0.5"
        basalt.update()
        T.eq(T.row(win, 19), "Running shell 0.5", "the status kept drawing")
        basalt.resumePalette()
        T.eq(T.bg(win, 1, 5), slot, "the custom color is back in its slot")
        local sr, sg, sb = shownBg(T, win, 1, 5)
        T.ok(near(sr, 0x1e / 255) and near(sg, 0x1e / 255) and near(sb, 0x2e / 255),
            "the slot shows the custom color again, got " .. show(sr, sg, sb))
        basalt.cleanup()
    end)

    T.test("drawing while suspended writes no palette slot", function()
        local basalt = T.loadBasalt()
        local win = T.window()
        paint(win)
        local t, count = counting(win)
        local frame = basalt.createFrame(t)
        local labels = addColors(basalt, frame, 10, 2)
        local status = frame:addLabel({ x = 1, y = 5, text = "0" })
        basalt.update()
        T.ok(count.writes > 0, "the first draw took slots")
        basalt.suspendPalette()
        local writes = count.writes
        for i = 1, 5 do
            status.text = tostring(i)
            labels[i].background = basalt.rgb(0.1, 0.2 + i / 20, 0.6)
            basalt.update()
        end
        T.eq(count.writes, writes, "palette writes while suspended")
        T.eq(T.row(win, 5), "5", "the status kept drawing")
        assertCustom(T, win, "after the draws")
        basalt.resumePalette()
        T.ok(count.writes > writes, "resume took slots again")
        local r, g, b = shownBg(T, win, 5, 2)
        T.ok(near(r, 0.1) and near(g, 0.45) and near(b, 0.6),
            "a color set while suspended has its own slot after resume, got " .. show(r, g, b))
        basalt.cleanup()
        assertCustom(T, win, "after cleanup")
    end)

    T.test("suspend calls nest; resume without suspend does nothing", function()
        local basalt, frame, win = T.frame()
        paint(win)
        addColors(basalt, frame, 8, 2)
        basalt.resumePalette() -- not suspended: nothing happens
        T.eq(basalt.isPaletteSuspended(), false)
        basalt.update()
        assertTaken(T, win, "after the draw")
        basalt.suspendPalette()
        basalt.suspendPalette()
        basalt.resumePalette()
        T.eq(basalt.isPaletteSuspended(), true, "one resume for two suspends")
        basalt.update()
        assertCustom(T, win, "still suspended")
        basalt.resumePalette()
        T.eq(basalt.isPaletteSuspended(), false)
        assertTaken(T, win, "after the second resume")
        basalt.resumePalette()
        T.eq(basalt.isPaletteSuspended(), false, "an extra resume")
        assertTaken(T, win, "after an extra resume")
        basalt.cleanup()
        assertCustom(T, win, "after cleanup")
    end)

    T.test("frames on several terminals all give their slots back", function()
        local basalt = T.loadBasalt()
        local a, b = T.window(), T.window(30, 8)
        paint(a)
        paint(b)
        local fa = basalt.createFrame(a)
        local fa2 = basalt.createFrame(a)
        local fb = basalt.createFrame(b)
        addColors(basalt, fa, 8, 2)
        addColors(basalt, fa2, 8, 3, 0.37)
        addColors(basalt, fb, 8, 2, 0.21)
        basalt.update()
        assertTaken(T, a, "terminal A")
        assertTaken(T, b, "terminal B")
        basalt.suspendPalette()
        assertCustom(T, a, "terminal A while suspended")
        assertCustom(T, b, "terminal B while suspended")
        basalt.resumePalette()
        assertTaken(T, a, "terminal A after resume")
        assertTaken(T, b, "terminal B after resume")
        basalt.cleanup()
        assertCustom(T, a, "terminal A after cleanup")
        assertCustom(T, b, "terminal B after cleanup")
    end)

    T.test("frames and windows created while suspended", function()
        local basalt = T.loadBasalt()
        local parent = T.window()
        paint(parent)
        local a = basalt.createFrame(parent)
        addColors(basalt, a, 10, 2)
        basalt.update()
        basalt.suspendPalette()
        -- the new window copies the parent's palette: its own colors now
        local child = window.create(parent, 1, 1, 30, 8, false)
        assertCustom(T, child, "the new window")
        local b = basalt.createFrame(child)
        b:addLabel({ x = 1, y = 1, text = "  ", background = nextTo(basalt, 6) })
        addColors(basalt, b, 10, 3, 0.37)
        basalt.update()
        assertCustom(T, child, "the new window after its frame drew")
        assertCustom(T, parent, "the parent")
        T.eq(T.bg(child, 1, 1), 2 ^ 6, "the new frame draws the nearest own color")
        basalt.resumePalette()
        assertTaken(T, child, "the new window after resume")
        assertTaken(T, parent, "the parent after resume")
        -- a frame created after resume takes slots as usual
        local other = T.window(20, 5)
        paint(other)
        local c = basalt.createFrame(other)
        addColors(basalt, c, 6, 1)
        basalt.update()
        assertTaken(T, other, "a frame created after resume")
        basalt.cleanup()
        assertCustom(T, child, "the new window after cleanup")
        assertCustom(T, parent, "the parent after cleanup")
        assertCustom(T, other, "the later window after cleanup")
    end)

    T.test("a frame created while suspended takes slots after resume", function()
        local basalt = T.loadBasalt()
        local win = T.window()
        paint(win)
        basalt.suspendPalette()
        local frame = basalt.createFrame(win)
        frame:addLabel({ x = 1, y = 1, text = "  ", background = nextTo(basalt, 10) })
        basalt.update()
        assertCustom(T, win, "while suspended")
        T.eq(T.bg(win, 1, 1), 2 ^ 10, "the nearest own color")
        basalt.resumePalette()
        assertTaken(T, win, "after resume")
        local r, g, b = shownBg(T, win, 1, 1)
        local er, eg, eb = customRGB(10)
        T.ok(near(r, er + 0.01) and near(g, eg) and near(b, eb),
            "the cell shows the RGB color, got " .. show(r, g, b))
        basalt.cleanup()
        assertCustom(T, win, "after cleanup")
    end)

    T.test("repaint redraws what another program wrote over", function()
        local basalt, frame, win = T.frame()
        paintDefault(win)
        frame:addLabel({ x = 1, y = 1, text = "hello" })
        local custom = basalt.rgb("#1e1e2e")
        frame:addLabel({ x = 1, y = 3, text = "  ", background = custom })
        basalt.update()
        local slot = T.bg(win, 1, 3)
        -- a program draws on the terminal and changes the slot Basalt holds
        win.setCursorPos(1, 1)
        win.write("XXXXXXX")
        win.setPaletteColour(slot, 1, 0, 0)
        basalt.update()
        T.eq(T.row(win, 1), "XXXXXXX", "only changes are sent, so update leaves it")
        basalt.repaint()
        T.eq(T.row(win, 1), "hello", "the row after repaint")
        local r, g, b = shownBg(T, win, 1, 3)
        T.ok(near(r, 0x1e / 255) and near(g, 0x1e / 255) and near(b, 0x2e / 255),
            "the slot shows Basalt's color again, got " .. show(r, g, b))
        basalt.cleanup()
    end)

    T.test("resumePalette repaints too", function()
        local basalt, frame, win = T.frame()
        frame:addLabel({ x = 1, y = 1, text = "hello" })
        basalt.update()
        basalt.suspendPalette()
        win.setCursorPos(1, 1)
        win.write("ls output")
        basalt.resumePalette()
        T.eq(T.row(win, 1), "hello")
        basalt.cleanup()
    end)

    T.test("repaint takes the terminal's new size", function()
        local basalt, frame, win = T.frame(30, 10)
        frame:addLabel({ x = 1, y = 1, text = "hello" })
        basalt.update()
        win.reposition(1, 1, 20, 6) -- queues no term_resize
        basalt.repaint()
        T.eq(frame.width, 20)
        T.eq(frame.height, 6)
        T.eq(T.row(win, 1), "hello")
        basalt.cleanup()
    end)

    T.test("a term_resize through update resizes every root frame", function()
        local basalt = T.loadBasalt()
        local a, b = T.window(30, 10), T.window(25, 8)
        local fa = basalt.createFrame(a)
        local fb = basalt.createFrame(b)
        fa:addLabel({ x = 1, y = 1, text = "aaaaaaaaaaaaaaaaaaaaaaaaa" })
        fb:addLabel({ x = 1, y = 1, text = "b" })
        basalt.update()
        a.reposition(1, 1, 20, 5)
        b.reposition(1, 1, 12, 4)
        basalt.update("term_resize")
        T.eq(fa.width, 20, "frame A width")
        T.eq(fa.height, 5, "frame A height")
        T.eq(fb.width, 12, "frame B width")
        T.eq(fb.height, 4, "frame B height")
        T.eq(T.row(a, 1), string.rep("a", 20), "frame A drew at its new width")
        basalt.cleanup()
    end)

    T.test("cleanup gives the terminal back and is safe to call twice", function()
        local basalt, frame, win = T.frame()
        paint(win)
        frame:addLabel({ x = 1, y = 1, text = "hello" })
        addColors(basalt, frame, 10, 2)
        basalt.update()
        assertTaken(T, win, "after the draw")
        basalt.cleanup()
        assertCustom(T, win, "after cleanup")
        T.eq((T.screen(win):gsub("\n", "")), "", "the screen is cleared")
        T.eq(win.getCursorBlink(), false)
        win.setCursorPos(1, 1)
        win.write("Goodbye!")
        basalt.cleanup()
        T.eq(T.row(win, 1), "Goodbye!", "a second cleanup keeps what was printed")
        assertCustom(T, win, "after the second cleanup")
        -- repaint and the palette calls leave a terminal that was given back
        basalt.repaint()
        basalt.suspendPalette()
        basalt.resumePalette()
        T.eq(T.row(win, 1), "Goodbye!", "repaint after cleanup")
        assertCustom(T, win, "after repaint")
        -- the next update draws again, and the next cleanup clears again
        basalt.update()
        T.eq(T.row(win, 1), "hello", "update draws again")
        assertTaken(T, win, "after drawing again")
        basalt.cleanup()
        T.eq(T.row(win, 1), "", "cleared again")
        assertCustom(T, win, "after the last cleanup")
    end)

    T.test("cleanup ends a palette suspension", function()
        local basalt, frame, win = T.frame()
        paint(win)
        addColors(basalt, frame, 8, 2)
        basalt.update()
        basalt.suspendPalette()
        basalt.suspendPalette()
        basalt.cleanup()
        T.eq(basalt.isPaletteSuspended(), false)
        assertCustom(T, win, "after cleanup")
        basalt.update()
        assertTaken(T, win, "the next draw takes slots")
        basalt.cleanup()
    end)

    T.test("basalt.run gives a suspended palette back and ends the suspension", function()
        local basalt, frame, win = T.frame()
        paint(win)
        addColors(basalt, frame, 8, 2)
        local suspended
        basalt.schedule(function()
            os.pullEvent("basalt_manual_palette_run")
            basalt.suspendPalette()
            suspended = #changedSlots(win) == 0
            basalt.stop()
        end)
        os.queueEvent("basalt_manual_palette_run")
        basalt.run()
        T.eq(suspended, true, "the palette was given back while running")
        T.eq(basalt.isPaletteSuspended(), false)
        assertCustom(T, win, "after run")
        win.setCursorPos(1, 1)
        win.write("Goodbye!")
        basalt.cleanup() -- after run: nothing left to do
        T.eq(T.row(win, 1), "Goodbye!")
    end)

    T.test("errors from update reach the caller without an error screen", function()
        local basalt, frame, win = T.frame()
        local button = frame:addButton({ x = 1, y = 1, width = 7, height = 1, text = "go" })
        button:onClick(function() error("handler failed", 0) end)
        local handlerErr, coErr
        local screen = onScreen(T, function()
            local ok, err = pcall(T.click, basalt, 2, 1)
            T.eq(ok, false, "the click raised")
            handlerErr = err
            basalt.schedule(function()
                os.pullEvent("basalt_manual_palette_late")
                error("scheduled failed", 0)
            end)
            ok, err = pcall(basalt.update, "basalt_manual_palette_late")
            T.eq(ok, false, "the scheduled error raised")
            coErr = err
        end)
        T.eq(handlerErr, "handler failed", "a handler error comes out as raised")
        T.eq(type(coErr), "table", "a scheduled coroutine's error is wrapped")
        T.eq(coErr.err, "scheduled failed")
        T.eq(tostring(coErr), "scheduled failed")
        T.eq(type(coErr.trace), "string", "with the coroutine's traceback")
        T.eq(T.row(screen, 1), "app screen", "no error screen was drawn")
        -- Basalt goes on
        button.text = "again"
        basalt.update()
        T.contains(T.row(win, 1), "again", "the next draw")
        basalt.cleanup()
    end)

    T.test("a draw that failed does not spoil the next one", function()
        local basalt, frame, win = T.frame()
        local root = frame:addLabel({ x = 1, y = 1, text = "root" })
        local box = frame:addFrame({ x = 10, y = 5, width = 20, height = 8 })
        local fail = true
        box:addCanvas({ x = 3, y = 2, width = 10, height = 3,
            draw = function(_, buf)
                if fail then error("draw failed", 0) end
                buf:drawText(1, 1, "canvas")
            end })
        local err = T.raises(function() basalt.update() end, "draw failed")
        T.eq(err, "draw failed")
        fail = false
        root.text = "root2"
        basalt.update()
        T.eq(T.row(win, 1), "root2", "the root draws at its place")
        T.eq(T.row(win, 6), string.rep(" ", 11) .. "canvas", "the canvas draws at its place")
        basalt.cleanup()
    end)

    T.test("repaint and suspend from a draw callback are done by the running draw", function()
        local basalt, frame, win = T.frame()
        local calls = 0
        frame:addCanvas({ x = 3, y = 2, width = 10, height = 2,
            background = basalt.rgb("#203040"),
            draw = function(_, buf)
                calls = calls + 1
                if calls == 1 then
                    basalt.repaint()
                    basalt.suspendPalette()
                end
                buf:drawText(1, 1, "canvas")
            end })
        frame:addLabel({ x = 1, y = 1, text = "top" })
        basalt.update()
        T.eq(T.row(win, 1), "top")
        T.eq(T.row(win, 2), "  canvas")
        T.eq(basalt.isPaletteSuspended(), true)
        T.eq(calls, 2, "the running draw drew once more")
        basalt.resumePalette()
        basalt.cleanup()
    end)

    T.test("after a caught draw error, repaint and the palette calls act at once", function()
        local basalt, frame, win = T.frame(30, 10)
        paintDefault(win)
        frame.background = basalt.rgb("#1e1e2e")
        local label = frame:addLabel({ x = 1, y = 1, text = "hello" })
        local fail = false
        frame:addCanvas({ x = 1, y = 3, width = 10, height = 2,
            draw = function(_, buf)
                if fail then
                    fail = false -- fails once
                    error("draw failed", 0)
                end
                buf:drawText(1, 1, "canvas")
            end })
        basalt.update()
        local slot = T.bg(win, 1, 6)
        T.ok(slot ~= colors.black, "the custom background has a slot of its own")
        fail = true
        label.text = "hello2"
        T.raises(function() basalt.update() end, "draw failed")
        -- another program writes over the frame; no update follows
        win.setCursorPos(1, 1)
        win.write("XXXXXXXXXX")
        basalt.repaint()
        T.eq(T.row(win, 1), "hello2", "repaint drew at once")
        T.eq(T.row(win, 3), "canvas", "with the canvas that failed before")
        win.reposition(1, 1, 20, 6) -- queues no term_resize
        basalt.repaint()
        T.eq(frame.width, 20, "repaint took the terminal's new width")
        T.eq(frame.height, 6, "and its new height")
        basalt.suspendPalette()
        T.eq(T.bg(win, 1, 6), colors.black, "suspendPalette drew the background at once")
        win.setCursorPos(1, 1)
        win.write("XXXXXXXXXX")
        basalt.resumePalette()
        T.eq(T.bg(win, 1, 6), slot, "resumePalette drew the background at once")
        T.eq(T.row(win, 1), "hello2", "resumePalette drew the row at once")
        basalt.cleanup()
    end)

    T.test("repaint from a draw callback also draws the frames drawn before it", function()
        local basalt = T.loadBasalt()
        local a, b = T.window(30, 6), T.window(30, 6)
        paintDefault(a)
        paintDefault(b)
        local fa = basalt.createFrame(a)
        local fb = basalt.createFrame(b)
        fa.background = basalt.rgb("#1e1e2e")
        fa:addLabel({ x = 1, y = 1, text = "frame A" })
        -- frame B (drawn after frame A) runs action from its draw callback
        local action
        fb:addCanvas({ x = 1, y = 1, width = 10, height = 2,
            draw = function(_, buf)
                if action then
                    local fn = action
                    action = nil
                    fn()
                end
                buf:drawText(1, 1, "canvas")
            end })
        local note = fb:addLabel({ x = 1, y = 4, text = "0" })
        basalt.update()
        local slot = T.bg(a, 1, 4)
        T.ok(slot ~= colors.black, "frame A's custom background has a slot of its own")

        -- another program writes over frame A, then frame B asks for a repaint
        a.setCursorPos(1, 1)
        a.write("XXXXXXXXXX")
        action = basalt.repaint
        note.text = "1"
        basalt.update()
        T.eq(action, nil, "frame B's callback ran")
        T.eq(T.row(a, 1), "frame A", "frame A was drawn again in the same update")
        T.eq(T.row(b, 4), "1", "frame B drew")

        action = basalt.suspendPalette
        note.text = "2"
        basalt.update()
        T.eq(basalt.isPaletteSuspended(), true)
        local r, g, bl = a.getPaletteColour(slot)
        local er, eg, eb = term.nativePaletteColour(slot)
        T.ok(near(r, er) and near(g, eg) and near(bl, eb),
            "the borrowed slot shows its own color again, got " .. show(r, g, bl))
        T.eq(T.bg(a, 1, 4), colors.black, "frame A's background while suspended")

        action = basalt.resumePalette
        note.text = "3"
        basalt.update()
        T.eq(basalt.isPaletteSuspended(), false)
        T.eq(T.bg(a, 1, 4), slot, "frame A's background is back in its slot")
        T.eq(T.row(b, 4), "3", "frame B drew")
        basalt.cleanup()
    end)

    T.test("run's error screen shows where a draw callback raised", function()
        local basalt, frame = T.frame()
        local shown = catchErrorScreen(basalt)
        local errLine
        frame:addCanvas({ x = 1, y = 1, width = 10, height = 2,
            draw = function()
                errLine = nextLine()
                error("draw failed", 0)
            end })
        -- ends the loop if the draw does not raise
        local stopped = false
        basalt.schedule(function()
            os.pullEvent("basalt_manual_palette_stop")
            stopped = true
            basalt.stop()
        end)
        os.queueEvent("basalt_manual_palette_stop")
        basalt.run()
        if not stopped then os.pullEvent("basalt_manual_palette_stop") end
        T.eq(#shown, 1, "error screens")
        T.eq(shown[1].err, "draw failed")
        T.contains(shown[1].trace, "test_manual_palette.lua:" .. errLine .. ":",
            "the traceback has the callback's line")
    end)

    T.test("run's error screen shows where a draw callback raised after basalt.stop", function()
        -- the loop draws once more after the event that called stop
        local basalt, frame = T.frame()
        local shown = catchErrorScreen(basalt)
        local fail, errLine = false, nil
        frame:addCanvas({ x = 1, y = 1, width = 10, height = 2,
            draw = function(_, buf)
                if fail then
                    errLine = nextLine()
                    error("draw failed", 0)
                end
                buf:drawText(1, 1, "canvas")
            end })
        basalt.schedule(function()
            os.pullEvent("basalt_manual_palette_stop_draw")
            fail = true
            frame.background = colors.gray -- the frame draws again
            basalt.stop()
        end)
        os.queueEvent("basalt_manual_palette_stop_draw")
        basalt.run()
        T.eq(#shown, 1, "error screens")
        T.eq(shown[1].err, "draw failed")
        T.contains(shown[1].trace, "test_manual_palette.lua:" .. tostring(errLine) .. ":",
            "the traceback has the callback's line")
    end)

    T.test("run's error screen shows where a draw callback raised in a scheduled repaint", function()
        local basalt, frame, win = T.frame()
        paint(win)
        addColors(basalt, frame, 6, 5)
        local shown = catchErrorScreen(basalt)
        local fail, errLine = false, nil
        frame:addCanvas({ x = 1, y = 1, width = 10, height = 2,
            draw = function(_, buf)
                if fail then
                    errLine = nextLine()
                    error("draw failed", 0)
                end
                buf:drawText(1, 1, "canvas")
            end })
        basalt.schedule(function()
            os.pullEvent("basalt_manual_palette_suspend")
            fail = true
            basalt.suspendPalette() -- draws at once: the callback raises
            basalt.stop()
        end)
        os.queueEvent("basalt_manual_palette_suspend")
        basalt.run()
        T.eq(#shown, 1, "error screens")
        T.eq(shown[1].err, "draw failed", "the error, wrapped once")
        T.contains(shown[1].trace, "test_manual_palette.lua:" .. errLine .. ":",
            "the traceback has the callback's line")
        T.eq(basalt.isPaletteSuspended(), false, "run's cleanup ended the suspension")
        assertCustom(T, win, "after run")
    end)

    T.test("a draw error from update keeps its message and position", function()
        -- draw catches the error to clear its state, and raises it again
        -- unchanged outside basalt.run
        local basalt, frame = T.frame()
        local errLine
        frame:addCanvas({ x = 1, y = 1, width = 10, height = 2,
            draw = function()
                errLine = nextLine()
                error("draw failed")
            end })
        local ok, err = pcall(basalt.update)
        T.eq(ok, false)
        T.eq(type(err), "string", "a draw error comes out as raised")
        T.contains(err, "test_manual_palette.lua:" .. errLine .. ": draw failed",
            "with the callback's position")
        basalt.cleanup()
    end)

    T.test("a draw error in a scheduled task keeps the callback in the task's trace", function()
        -- outside basalt.run: the task's draw raises (suspendPalette draws
        -- at once); err.trace must show the callback, not Basalt's draw
        local basalt, frame = T.frame()
        local fail, errLine = false, nil
        frame:addCanvas({ x = 1, y = 1, width = 10, height = 2,
            draw = function(_, buf)
                if fail then
                    errLine = nextLine()
                    error("draw failed", 0)
                end
                buf:drawText(1, 1, "canvas")
            end })
        basalt.update()
        basalt.schedule(function()
            os.pullEvent("basalt_manual_palette_task_draw")
            fail = true
            basalt.suspendPalette()
        end)
        local ok, err = pcall(basalt.update, "basalt_manual_palette_task_draw")
        T.eq(ok, false)
        T.eq(type(err), "table", "a task's error is a table")
        T.eq(err.err, "draw failed", "wrapped once")
        T.contains(err.trace, "test_manual_palette.lua:" .. errLine .. ":",
            "the traceback has the callback's line")
        basalt.cleanup()
    end)

    T.test("a scheduled coroutine's error that has its traceback is not wrapped again", function()
        local basalt = T.frame()
        basalt.schedule(function()
            os.pullEvent("basalt_manual_palette_wrapped")
            error(basalt.errors.wrap("inner failed", "inner trace"), 0)
        end)
        local ok, err = pcall(basalt.update, "basalt_manual_palette_wrapped")
        T.eq(ok, false)
        T.eq(type(err), "table")
        T.eq(err.err, "inner failed", "the error itself, not a wrapped one")
        T.eq(err.trace, "inner trace", "the traceback it had")
        T.eq(tostring(err), "inner failed")
        basalt.cleanup()
    end)
end
