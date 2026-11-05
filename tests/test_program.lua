-- tests/test_program.lua
-- The Program element: hosted CC programs with event forwarding, mouse
-- routing, done/error events and crash isolation between programs.
-- Ported from the deleted 2.5 smoke test (2062cc6:test_smoke.lua).

return function(T)
    local ECHO = [[
term.setCursorPos(1, 1)
term.write("HELLO W" .. select(1, term.getSize()))
local total = 0
while true do
    local e, a = os.pullEvent()
    if e == "test_ev" then
        total = total + a
        term.setCursorPos(1, 2)
        term.write("N" .. total)
    elseif e == "mouse_click" then
        term.setCursorPos(1, 3)
        term.write("M" .. a)
    elseif e == "quit_ev" then
        return "bye"
    end
end
]]

    -- a program whose output tags lines with `tag` and which crashes on
    -- crashEvent
    local function taggedProgram(tag, crashEvent)
        return ([[
term.setCursorPos(1, 1)
term.write("P%s")
while true do
    local e, a = os.pullEvent()
    if e == "tick_ev" then
        term.setCursorPos(1, 2)
        term.write("%s" .. a)
    elseif e == "mouse_click" then
        term.setCursorPos(1, 3)
        term.write("M%s")
    elseif e == "%s" then
        error("crash %s", 0)
    end
end
]]):format(tag, tag, tag, crashEvent, tag)
    end

    T.test("a program runs in its own window and gets forwarded events", function()
        local basalt, frame, win = T.frame()
        local path = T.tmpFile("echo.lua", ECHO)
        local prog = frame:addProgram({ x = 40, y = 5, width = 10, height = 4 })
        local ok, result
        prog:onDone(function(_, o, r) ok, result = o, r end)
        prog:execute(path)
        T.eq(prog.running, true)
        basalt.update()
        T.eq(T.row(win, 5):sub(40, 49), "HELLO W10", "output sized to the element")
        basalt.update("test_ev", 2) -- forwarded by the event pump
        basalt.update("test_ev", 3)
        T.eq(T.row(win, 6):sub(40, 41), "N5", "custom events forwarded")
        T.click(basalt, 41, 7) -- element-local (2, 3)
        T.eq(T.row(win, 7):sub(40, 41), "M1", "mouse events forwarded")
        basalt.update("quit_ev")
        T.eq(ok, true, "done event")
        T.eq(result, "bye", "done result")
        T.eq(prog.running, false)
        prog:destroy()
        T.cleanTmp()
    end)

    T.test("onError keeps the app alive when a program crashes", function()
        local basalt, frame = T.frame()
        local path = T.tmpFile("crash.lua", 'os.pullEvent("boom_ev") error("kaputt", 0)')
        local caught
        local prog = frame:addProgram({
            x = 40, y = 5, width = 10, height = 4,
            onError = function(_, e) caught = e end,
        })
        prog:execute(path)
        basalt.update("boom_ev")
        T.eq(caught, "kaputt")
        T.eq(prog.running, false)
        prog:destroy()
        T.cleanTmp()
    end)

    T.test("two programs: independent events, mouse and crash isolation", function()
        local basalt, frame, win = T.frame()
        local pathA = T.tmpFile("multi_a.lua", taggedProgram("A", "crash_a_ev"))
        local pathB = T.tmpFile("multi_b.lua", taggedProgram("B", "crash_b_ev"))
        local progA = frame:addProgram({ x = 40, y = 5, width = 8, height = 4 })
        local caughtB
        local progB = frame:addProgram({
            x = 28, y = 5, width = 8, height = 4,
            onError = function(_, e) caughtB = e end,
        })
        progA:execute(pathA)
        progB:execute(pathB)
        basalt.update("tick_ev", 7)
        local row6 = T.row(win, 6)
        T.contains(row6:sub(40, 47), "A7", "program A got tick_ev")
        T.contains(row6:sub(28, 35), "B7", "program B got tick_ev")

        T.click(basalt, 29, 7) -- inside B only
        local row7 = T.row(win, 7)
        T.contains(row7:sub(28, 35), "MB", "B got its click")
        T.ok(not row7:sub(40, 47):find("MA", 1, true), "A did not see B's click")

        basalt.update("crash_b_ev")
        T.eq(caughtB, "crash B")
        T.eq(progB.running, false)
        T.eq(progA.running, true, "A survives B's crash")
        basalt.update("tick_ev", 9)
        T.contains(T.row(win, 6):sub(40, 47), "A9", "A stays responsive")
        progA:destroy()
        progB:destroy()
        T.cleanTmp()
    end)
end
