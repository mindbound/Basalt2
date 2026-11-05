-- tests/test_fix_reactive_run.lua
-- basalt.setReactiveStrings / basalt.literal (untrusted "{...}" text) and
-- basalt.run({ onTerminate }) (Ctrl+T without quitting; Basalt's own
-- scheduled work survives it; Element:handleTerminate), and a second
-- basalt.run after the terminal was resized.

return function(T)
    ------------------------------------------------------------------------
    -- reactive strings
    ------------------------------------------------------------------------

    T.test("reactive strings are on by default and per instance", function()
        local a, frameA = T.frame()
        local b, frameB = T.frame()
        T.eq(a.getReactiveStrings(), true, "default")
        a.setReactiveStrings(false)
        T.eq(a.getReactiveStrings(), false)
        T.eq(b.getReactiveStrings(), true, "another instance keeps its switch")
        local la = frameA:addLabel({ x = "{1 + 1}" })
        local lb = frameB:addLabel({ x = "{1 + 1}" })
        T.eq(la.x, "{1 + 1}", "off: stored as written")
        T.eq(lb.x, 2, "on: compiled")
        a.setReactiveStrings(true)
        la.x = "{2 + 2}"
        T.eq(la.x, 4, "on again")
        T.raises(function() a.setReactiveStrings("no") end, "expects a boolean")
    end)

    T.test("switch off: untrusted text is stored as written", function()
        local basalt, frame, win = T.frame()
        basalt.setReactiveStrings(false)
        local label = frame:addLabel({ x = 1, y = 1, text = "{self:destroy()}" })
        T.eq(label.text, "{self:destroy()}")
        T.eq(rawget(label, "parent"), frame, "the expression did not run")
        basalt.update()
        T.eq(T.row(win, 1), "{self:destroy()}")

        label.text = '{"a":1}'
        T.eq(label.text, '{"a":1}', "JSON by assignment")
        label:setText('{"b":[1,2]}')
        T.eq(label.text, '{"b":[1,2]}', "JSON by setter")
        label:apply({ text = "{parent.width}" })
        T.eq(label.text, "{parent.width}", "apply")
        local button = frame:addButton({ y = 3, text = "{error('ran')}" })
        T.eq(button.text, "{error('ran')}", "constructor props")
        T.eq(type(label:raw("text")), "string")
    end)

    T.test("switch off keeps values compiled before", function()
        local basalt, frame = T.frame()
        local inner = frame:addFrame({ width = 10, height = 3 })
        local label = inner:addLabel({ text = "x" })
        label.x = "{parent.width - 2}"
        basalt.setReactiveStrings(false)
        T.eq(label.x, 8)
        inner.width = 12
        T.eq(label.x, 10, "still dynamic")
    end)

    T.test("switch off: Dialog and Toast messages", function()
        local basalt, frame, win = T.frame(40, 18)
        basalt.setReactiveStrings(false)
        local toast = frame:addToast()
        toast:show('{"a":1}', "info", 0)
        T.eq(toast.message, '{"a":1}')
        toast:show("{self:destroy()}", "info", 0)
        T.eq(toast.message, "{self:destroy()}")
        T.eq(rawget(toast, "parent"), frame)
        toast:hide()

        local dialog = frame:addDialog()
        dialog:alert("{self:destroy()}", "{a} {b}")
        basalt.update()
        local screen = T.screen(win)
        T.contains(screen, "{self:destroy()}", "title")
        T.contains(screen, "{a} {b}", "message line")
        dialog:close()
    end)

    T.test("collection items are never compiled", function()
        local basalt, frame, win = T.frame()
        local list = frame:addList({ x = 1, y = 1, width = 20, height = 4 })
        list:addItem("{self:destroy()}")
        list:addItem('{"a":1}')
        basalt.update()
        T.eq(T.row(win, 1), "{self:destroy()}")
        T.eq(T.row(win, 2), '{"a":1}')
        T.eq(rawget(list, "parent"), frame)
    end)

    T.test("a literal marker as a collection item is its string", function()
        local basalt, frame, win = T.frame()
        local lit = basalt.literal
        local list = frame:addList({ x = 1, y = 1, width = 20, height = 4 })
        local entry = list:addItem(lit("{marker}"))
        T.eq(entry:getText(), "{marker}", "the entry has the text")
        list.items = { "plain", lit("{set}"), lit('{"a":1}') }
        local added = list:addItem(lit("{added}"))
        basalt.update()
        T.eq(T.row(win, 1), "plain")
        T.eq(T.row(win, 2), "{set}", "items table")
        T.eq(T.row(win, 3), '{"a":1}')
        T.eq(T.row(win, 4), "{added}", "addItem")
        T.eq(added:getText(), "{added}")
        T.eq(added.value, "{added}", "and the string as its value")
        T.eq(type(added:getData().text), "string")
        added.text = "edited"
        T.eq(added:getText(), "edited", "edits change the entry, not a marker")

        local menu = frame:addMenu({ x = 1, y = 6, width = 30 })
        menu.items = { lit("{one}"), "two", lit("{three}") }
        basalt.update()
        local row = T.row(win, 6)
        T.contains(row, "{one}", "menu row")
        T.contains(row, "{three}")
        T.eq(row:find("nil", 1, true), nil, "no entry shows nil")
        T.eq(menu.items[1]:getText(), "{one}")
        T.eq(rawget(menu, "parent"), frame)
    end)

    T.test("literal stores one value as written in every assignment path", function()
        local basalt, frame, win = T.frame()
        T.eq(basalt.getReactiveStrings(), true)
        local lit = basalt.literal

        local label = frame:addLabel({ x = 1, y = 1, text = lit("{self:destroy()}") })
        T.eq(label.text, "{self:destroy()}", "constructor props")
        T.eq(rawget(label, "parent"), frame)
        T.eq(type(label:raw("text")), "string", "stored as the plain string")
        basalt.update()
        T.eq(T.row(win, 1), "{self:destroy()}")

        label.text = lit('{"a":1}')
        T.eq(label.text, '{"a":1}', "assignment")
        label:setText(lit("{1 + 1}"))
        T.eq(label.text, "{1 + 1}", "setter")
        label:apply({ text = lit("{2}") })
        T.eq(label.text, "{2}", "apply")

        local input = frame:addInput({ y = 3, width = 10 })
        input.text = lit("{5}")
        T.eq(input.text, "{5}", "rawString property")
        T.eq(type(input:raw("text")), "string")

        label:setStateStyle("hover", { text = lit("{hover}") })
        label:setState("hover", true)
        T.eq(label.text, "{hover}", "state style")
        label:setState("hover", false)
        T.eq(label.text, "{2}")

        local signal = basalt.state(lit("{signal}"))
        label.text = signal
        T.eq(label.text, "{signal}", "a signal value")

        label.text = "{3 + 4}"
        T.eq(label.text, 7, "an unmarked string still compiles")
    end)

    T.test("literal works in theme defaults, theme states and theme.apply", function()
        local basalt, frame = T.frame()
        local theme = basalt.use("theme")
        theme.set({ Label = {
            text = basalt.literal("{theme}"),
            states = { hover = { text = basalt.literal("{themeHover}") } },
        } })
        local label = frame:addLabel({ x = 1, y = 1 })
        T.eq(label.text, "{theme}", "class default")
        label:setState("hover", true)
        T.eq(label.text, "{themeHover}", "class state style")
        label:setState("hover", false)
        theme.apply(frame, { Label = { text = basalt.literal("{applied}") } })
        T.eq(label.text, "{applied}", "theme.apply")
    end)

    T.test("literal: other values, tostring, other instances", function()
        local basalt = T.loadBasalt()
        T.eq(basalt.literal(5), 5)
        T.eq(basalt.literal(nil), nil)
        T.eq(basalt.literal(true), true)
        T.eq(tostring(basalt.literal("{x}")), "{x}")
        local _, frame = T.frame()
        local label = frame:addLabel({ text = basalt.literal("{other}") })
        T.eq(label.text, "{other}", "a marker from another instance")
    end)

    T.test("xml stays reactive when reactive strings are off", function()
        local basalt, frame = T.frame()
        local xml = basalt.use("xml")
        basalt.setReactiveStrings(false)
        xml.load(frame, [[
            <frame name="xf" width="14" height="4">
                <label name="attr" text="{parent.width}"/>
                <label name="body" y="2">{parent.width - 4}</label>
                <label name="plain" y="3" text="plain"/>
                <input name="raw" y="4" width="6" text="{5}"/>
            </frame>
        ]])
        T.eq(frame:find("attr").text, 14, "attribute")
        T.eq(frame:find("body").text, 10, "text between tags")
        T.eq(frame:find("plain").text, "plain")
        T.eq(frame:find("raw").text, "{5}", "rawString keeps it as written")
        frame:find("xf").width = 20
        T.eq(frame:find("attr").text, 20, "follows its source")
        local label = frame:addLabel({ text = "{1 + 1}" })
        T.eq(label.text, "{1 + 1}", "assignments are still not compiled")
        T.eq(basalt.getReactiveStrings(), false)
    end)

    T.test("unbind and rebind keep a bound string as written", function()
        local basalt, frame = T.frame()
        T.eq(basalt.getReactiveStrings(), true)
        local label = frame:addLabel({ x = 1, y = 1, text = "x" })

        -- a literal in a signal: rebinding writes the old value back first
        label:bind("text", basalt.state(basalt.literal('{"a":1}')))
        label:bind("text", basalt.state("other"))
        T.eq(label.text, "other", "rebinding raised no error")
        label:bind("text", basalt.state(basalt.literal('{"a":1}')))
        label:unbind("text")
        T.eq(label.text, '{"a":1}', "unbind keeps the text")
        T.eq(type(label:raw("text")), "string")

        -- untrusted text shown through a signal
        label:bind("text", basalt.state("{self:destroy()}"))
        label:unbind("text")
        T.eq(label.text, "{self:destroy()}")
        T.eq(rawget(label, "parent"), frame, "the expression did not run")

        label:bind("text", basalt.state("{1 + 1}"))
        label:unbind("text")
        T.eq(label.text, "{1 + 1}", "not compiled to 2")

        label:bind("text", basalt.state(1), function() return "{a}" end)
        label:unbind("text")
        T.eq(label.text, "{a}", "a fromState result")

        label:bind("x", basalt.state(4))
        label:unbind("x")
        T.eq(label.x, 4, "other values are kept as they are")
        label:bind("text", basalt.state("{b}"))
        label:unbind("text", false)
        T.eq(label.text, "", "keepCurrent = false restores the default")
    end)

    T.test("switch on: Dialog, Toast and debug text is shown as written", function()
        local basalt, frame, win = T.frame(40, 18)
        T.eq(basalt.getReactiveStrings(), true)
        local toast = frame:addToast()
        toast:show('{"a":1}', "info", 0)
        T.eq(toast.message, '{"a":1}', "JSON message")
        toast:show("{self:destroy()}", "info", 0)
        T.eq(toast.message, "{self:destroy()}")
        T.eq(rawget(toast, "parent"), frame, "the expression did not run")
        T.eq(type(toast:raw("message")), "string")
        toast:show(basalt.literal("{marked}"), "info", 0)
        T.eq(toast.message, "{marked}", "a marker shows its string")
        basalt.update()
        T.contains(T.screen(win), "{marked}")
        toast:hide()

        local dialog = frame:addDialog()
        -- the whole message is no expression, but its second wrapped line is
        dialog:alert("Server", "Reply from the server: {self:destroy()}")
        basalt.update()
        local screen = T.screen(win)
        T.contains(screen, "Reply from the server:")
        T.contains(screen, "{self:destroy()}", "the wrapped line")
        T.eq(rawget(dialog, "parent"), frame)
        dialog:close()
        dialog:alert(basalt.literal("{title}"), basalt.literal("{message}"))
        basalt.update()
        screen = T.screen(win)
        T.contains(screen, "{title}", "a literal title")
        T.contains(screen, "{message}", "a literal message")
        T.eq(dialog.title, "{title}")
        dialog:close()
        dialog:confirm('{"t":1}', '{"m":2}')
        basalt.update()
        screen = T.screen(win)
        T.contains(screen, '{"t":1}', "a JSON title")
        T.contains(screen, '{"m":2}', "a JSON message")
        dialog:close()
    end)

    T.test("debug log lines are shown as written", function()
        local basalt, frame, win = T.frame()
        T.eq(basalt.getReactiveStrings(), true)
        local dbg = basalt.use("debug")
        dbg.show(true)
        local serialized = textutils.serialize({ a = 1 }, { compact = true })
        basalt.debug(serialized)
        basalt.debug("{self:destroy()}")
        basalt.debug(basalt.literal("{marked}"))
        basalt.update()
        local screen = T.screen(win)
        T.contains(screen, serialized, "a serialized table")
        T.contains(screen, "{self:destroy()}")
        T.contains(screen, "{marked}")
        local overlay = dbg.getOverlay()
        T.eq(rawget(overlay, "parent"), frame)
        for _, child in ipairs(overlay:getChildren()) do
            T.eq(type(child:raw("text")), "string")
        end
        dbg.show(false)
    end)

    T.test("switch off: the debug overlay still follows its parent", function()
        local basalt, frame, win = T.frame(40, 15)
        basalt.setReactiveStrings(false)
        local dbg = basalt.use("debug")
        dbg.show(true)
        basalt.debug("hello")
        basalt.update()
        local overlay = dbg.getOverlay()
        T.eq(overlay.y, 15 - 7)
        T.eq(overlay.width, 40)
        T.contains(T.row(win, 8), "Basalt Debug")
        T.contains(T.row(win, 9), "hello")
        win.reposition(1, 1, 30, 12)
        basalt.update("term_resize")
        T.eq(overlay.y, 12 - 7, "follows the new height")
        T.eq(overlay.width, 30)
        dbg.show(false)
    end)

    T.test("switch off: theme.apply stores reactive strings as written", function()
        local basalt, frame = T.frame()
        local theme = basalt.use("theme")
        basalt.setReactiveStrings(false)
        local inner = frame:addFrame({ width = 20, height = 4 })
        local plain = inner:addLabel({ name = "plain", text = "a" })
        local dynamic = frame:addLabel({ name = "dynamic", text = "b" })
        theme.apply(inner, { Label = { x = "{parent.width - 2}" } })
        T.eq(plain.x, "{parent.width - 2}", "stored as written")
        theme.apply(dynamic, {
            Label = { x = function(self) return rawget(self, "parent").width - 2 end },
        })
        T.eq(dynamic.x, 49, "a function value works")
        frame.width = 40
        T.eq(dynamic.x, 38, "and follows its parent")
    end)

    ------------------------------------------------------------------------
    -- basalt.run({ onTerminate })
    ------------------------------------------------------------------------

    -- Stops basalt.run after `seconds` if a test hangs; the coroutine uses
    -- pullEventRaw and ignores terminate, so Ctrl+T cannot end it.
    local function watchdog(basalt, seconds)
        local fired = { value = false }
        local timer = os.startTimer(seconds or 3)
        basalt.schedule(function()
            while true do
                local ev, id = os.pullEventRaw("timer")
                if ev == "timer" and id == timer then
                    fired.value = true
                    basalt.stop()
                    return
                end
            end
        end, { ignoreTerminate = true })
        return fired
    end

    -- Stops basalt.run on the custom event "fix_stop" (survives terminate).
    local function stopOn(basalt, log)
        basalt.schedule(function()
            repeat
                local ev = os.pullEventRaw("fix_stop")
            until ev == "fix_stop"
            if log then log[#log + 1] = "stop" end
            basalt.stop()
        end)
    end

    -- Records error screens instead of showing them (no key wait).
    local function catchErrorScreen(basalt)
        local shown = {}
        basalt.errors.show = function(message)
            shown[#shown + 1] = tostring(message)
        end
        return shown
    end

    T.test("run() without options still ends on Ctrl+T", function()
        local basalt = T.frame()
        local shown = catchErrorScreen(basalt)
        local fired = watchdog(basalt)
        local after = false
        basalt.schedule(function()
            repeat
                local ev = os.pullEventRaw("fix_after")
            until ev == "fix_after"
            after = true
        end)
        os.queueEvent("terminate")
        os.queueEvent("fix_after") -- left in the queue: nobody waits for it
        basalt.run()
        T.eq(fired.value, false, "terminate ended the loop")
        T.eq(after, false, "no event after terminate was handled")
        T.eq(#shown, 0, "no error screen")
    end)

    T.test("run({ onTerminate }) cancels scheduled work and keeps running", function()
        local basalt = T.frame()
        local shown = catchErrorScreen(basalt)
        local fired = watchdog(basalt)
        local log = {}
        local task = basalt.schedule(function()
            sleep(30) -- waits for "timer": terminate still reaches it
            log[#log + 1] = "task finished"
        end)
        local request = basalt.schedule(function()
            os.pullEvent("fix_never") -- like an http call: ends on terminate
            log[#log + 1] = "request finished"
        end)
        local clock = basalt.schedule(function()
            while true do
                os.pullEvent("fix_tick")
                log[#log + 1] = "tick"
            end
        end, { ignoreTerminate = true })
        basalt.schedule(function()
            while true do
                local ev = os.pullEventRaw("fix_raw")
                log[#log + 1] = "raw " .. ev
            end
        end)
        stopOn(basalt, log)
        os.queueEvent("terminate")
        os.queueEvent("fix_tick")
        os.queueEvent("fix_stop")
        basalt.run({
            onTerminate = function()
                log[#log + 1] = "onTerminate " .. coroutine.status(task)
                    .. " " .. coroutine.status(request)
            end,
        })
        T.eq(fired.value, false, "stopped by basalt.stop, not the watchdog")
        T.eq(#shown, 0, "Terminated is not an error screen")
        T.eq(table.concat(log, ", "),
            "raw terminate, onTerminate dead dead, tick, stop")
        T.eq(coroutine.status(clock), "suspended", "ignoreTerminate survives")
    end)

    T.test("other errors on Ctrl+T still show the error screen", function()
        local basalt = T.frame()
        local shown = catchErrorScreen(basalt)
        local fired = watchdog(basalt)
        basalt.schedule(function()
            os.pullEventRaw("fix_never")
            error("cleanup failed", 0)
        end)
        os.queueEvent("terminate")
        basalt.run({ onTerminate = function() end })
        T.eq(fired.value, false, "the error ended the loop")
        T.eq(#shown, 1)
        T.contains(shown[1], "cleanup failed")
    end)

    T.test("an error in onTerminate shows the error screen", function()
        local basalt = T.frame()
        local shown = catchErrorScreen(basalt)
        local fired = watchdog(basalt)
        os.queueEvent("terminate")
        basalt.run({ onTerminate = function() error("handler broke", 0) end })
        T.eq(fired.value, false)
        T.eq(#shown, 1)
        T.contains(shown[1], "handler broke")
    end)

    T.test("run and schedule options are checked", function()
        local basalt = T.frame()
        T.raises(function() basalt.run(5) end, "run options must be a table")
        T.raises(function() basalt.run({ onTerminate = 1 }) end,
            "onTerminate must be a function")
        T.raises(function() basalt.schedule(function() end, 5) end,
            "schedule options must be a table")
        -- the failed calls left the loop startable
        local fired = watchdog(basalt)
        os.queueEvent("terminate")
        basalt.run()
        T.eq(fired.value, false)
    end)

    local LOOP = [[
term.setCursorPos(1, 1)
term.write("RUN")
while true do os.pullEvent() end
]]

    T.test("a focused Program takes Ctrl+T for its program", function()
        local basalt, frame = T.frame()
        local shown = catchErrorScreen(basalt)
        local fired = watchdog(basalt)
        local path = T.tmpFile("fix_loop.lua", LOOP)
        local prog = frame:addProgram({ x = 1, y = 1, width = 10, height = 3 })
        local doneOk
        prog:onDone(function(_, ok) doneOk = ok end)
        prog:execute(path)
        prog:focus()
        local task = basalt.schedule(function() sleep(30) end)
        local called = false
        stopOn(basalt)
        os.queueEvent("terminate")
        os.queueEvent("fix_stop")
        basalt.run({ onTerminate = function() called = true end })
        T.eq(fired.value, false)
        T.eq(#shown, 0)
        T.eq(doneOk, true, "the program ended normally")
        T.eq(prog.running, false)
        T.eq(called, false, "onTerminate is not called")
        T.eq(coroutine.status(task), "suspended", "scheduled work is kept")
        T.cleanTmp()
    end)

    T.test("an unfocused Program does not get Ctrl+T", function()
        local basalt, frame = T.frame()
        local shown = catchErrorScreen(basalt)
        local fired = watchdog(basalt)
        local path = T.tmpFile("fix_loop.lua", LOOP)
        local prog = frame:addProgram({ x = 1, y = 1, width = 10, height = 3 })
        prog:execute(path)
        local idle = frame:addProgram({ x = 1, y = 5, width = 10, height = 3 })
        idle:focus() -- focused, but runs no program: the event goes on
        local called = false
        stopOn(basalt)
        os.queueEvent("terminate")
        os.queueEvent("fix_stop")
        basalt.run({ onTerminate = function() called = true end })
        T.eq(fired.value, false)
        T.eq(#shown, 0)
        T.eq(prog.running, true, "the unfocused program keeps running")
        T.eq(called, true)
        prog:destroy()
        T.cleanTmp()
    end)

    -- Basalt's own scheduled loops wait with sleep() or os.pullEvent; they
    -- use basalt.schedule(fn, { ignoreTerminate = true }), so Ctrl+T under
    -- onTerminate does not end them.
    T.test("animations still run after Ctrl+T", function()
        local basalt, frame = T.frame()
        local anim = basalt.use("animation")
        local label = frame:addLabel({ x = 1, y = 1, text = "a" })
        local fired = watchdog(basalt, 3)
        local done = {}
        local function finished(name)
            return function()
                done[#done + 1] = name
                if #done == 2 then basalt.stop() end
            end
        end
        anim.to(label, { x = 8 }, 0.3, "linear", finished("running"))
        -- started after Ctrl+T: the loop must still be usable
        basalt.schedule(function()
            repeat
                local ev = os.pullEventRaw("fix_later")
            until ev == "fix_later"
            anim.to(label, { y = 4 }, 0.2, "linear", finished("later"))
        end, { ignoreTerminate = true })
        os.queueEvent("terminate")
        os.queueEvent("fix_later")
        basalt.run({ onTerminate = function() end })
        T.eq(fired.value, false, "both finished before the watchdog")
        T.eq(#done, 2)
        T.eq(label.x, 8, "the running animation finished")
        T.eq(label.y, 4, "the one started after Ctrl+T finished")
    end)

    T.test("an animation loop that ended with an error starts again", function()
        local basalt, frame = T.frame()
        local anim = basalt.use("animation")
        local label = frame:addLabel({ x = 1, y = 1, text = "a" })
        anim.to(label, { x = 3 }, 0.05, "linear", function()
            error("onDone broke", 0)
        end)
        T.raises(function()
            T.waitFor(basalt, function() return false end, 2)
        end, "onDone broke")
        local done = false
        anim.to(label, { x = 6 }, 0.05, "linear", function() done = true end)
        T.ok(T.waitFor(basalt, function() return done end, 2), "a new loop ran")
        T.eq(label.x, 6)
    end)

    T.test("a toast still hides itself after Ctrl+T", function()
        local basalt, frame = T.frame()
        local toast = frame:addToast()
        local fired = watchdog(basalt, 1.5)
        toast:onHide(function() basalt.stop() end)
        toast:show("saved", "info", 0.3)
        os.queueEvent("terminate")
        basalt.run({ onTerminate = function() end })
        T.eq(fired.value, false)
        T.eq(toast.visible, false)
    end)

    T.test("the debug overlay key still works after Ctrl+T", function()
        local basalt = T.frame()
        local dbg = basalt.use("debug")
        local fired = watchdog(basalt)
        stopOn(basalt)
        os.queueEvent("terminate")
        os.queueEvent("key", keys.f12, false)
        os.queueEvent("fix_stop")
        basalt.run({ onTerminate = function() end })
        T.eq(fired.value, false)
        T.eq(dbg.getOverlay().visible, true, "F12 after Ctrl+T showed it")
    end)

    T.test("image playback goes on after Ctrl+T", function()
        local basalt, frame = T.frame()
        basalt.use("image")
        local img = frame:addImage({ x = 1, y = 1 })
        img.bimg = {
            { { "X", "0", "e" } }, { { "Y", "0", "e" } }, { { "Z", "0", "e" } },
        }
        local fired = watchdog(basalt)
        local advanced = 0
        img:play(20)
        -- counts frame changes; terminate is queued first, so they all
        -- happen after Ctrl+T
        basalt.schedule(function()
            local last = img.currentFrame
            while advanced < 3 do
                sleep(0.02)
                if img.currentFrame ~= last then
                    advanced = advanced + 1
                    last = img.currentFrame
                end
            end
            basalt.stop()
        end, { ignoreTerminate = true })
        os.queueEvent("terminate")
        basalt.run({ onTerminate = function() end })
        img:stop()
        T.eq(fired.value, false, "playback went on")
        T.eq(advanced, 3)
    end)

    T.test("update('terminate') without run keeps its old behaviour", function()
        local basalt, frame = T.frame()
        local path = T.tmpFile("fix_loop.lua", LOOP)
        local focused = frame:addProgram({ x = 1, y = 1, width = 10, height = 3 })
        local other = frame:addProgram({ x = 1, y = 5, width = 10, height = 3 })
        focused:execute(path)
        other:execute(path)
        local sleeper = basalt.schedule(function() sleep(30) end)
        local got
        local waiter = basalt.schedule(function() got = os.pullEventRaw() end)

        basalt.update("terminate") -- nothing focused
        T.eq(focused.running, true, "no Program without focus")
        T.eq(other.running, true)
        T.eq(coroutine.status(sleeper), "suspended", "a filtered coroutine")
        T.eq(got, "terminate", "an unfiltered coroutine")
        T.eq(coroutine.status(waiter), "dead")

        local raiser = basalt.schedule(function() os.pullEvent() end)
        T.raises(function() basalt.update("terminate") end, "Terminated")
        T.eq(coroutine.status(raiser), "dead")

        focused:focus()
        basalt.update("terminate")
        T.eq(focused.running, false, "the focused Program got it")
        T.eq(other.running, true, "the other one did not")
        T.eq(coroutine.status(sleeper), "suspended")
        other:destroy()
        T.cleanTmp()
    end)

    T.test("Element:handleTerminate: false by default, an override takes it", function()
        local basalt, frame = T.frame()
        local shown = catchErrorScreen(basalt)
        local fired = watchdog(basalt)
        local label = frame:addLabel({ text = "x" })
        T.eq(label:handleTerminate(), false, "the default")
        local input = frame:addInput({ y = 2, width = 10 })
        local taken = 0
        function input:handleTerminate()
            taken = taken + 1
            self.text = ""
            return true
        end
        input.text = "typed"
        input:focus()
        local task = basalt.schedule(function() sleep(30) end)
        local called = false
        stopOn(basalt)
        os.queueEvent("terminate")
        os.queueEvent("fix_stop")
        basalt.run({ onTerminate = function() called = true end })
        T.eq(fired.value, false)
        T.eq(#shown, 0)
        T.eq(taken, 1, "the focused element got Ctrl+T")
        T.eq(input.text, "", "and handled it")
        T.eq(called, false, "onTerminate did not see it")
        T.eq(coroutine.status(task), "suspended", "nor did scheduled work")
    end)

    T.test("a second run lays out at the terminal's new size", function()
        local basalt, frame, win = T.frame(30, 8)
        local shown = catchErrorScreen(basalt)
        frame.background = colors.blue
        local label = frame:addLabel({ x = "{parent.width - 4}", y = 1, text = "R" })
        -- one plain run; returns what was on screen while it ran
        local function runOnce()
            local fired = watchdog(basalt)
            local seen = {}
            basalt.schedule(function()
                repeat
                    local ev = os.pullEventRaw("fix_look")
                until ev == "fix_look"
                if win.getSize() >= 35 then seen.bg = T.bg(win, 35, 1) end
                seen.row = T.row(win, 1)
                basalt.stop()
            end)
            os.queueEvent("fix_look")
            basalt.run()
            T.eq(fired.value, false)
            T.eq(#shown, 0, "no error screen")
            return seen
        end
        local first = runOnce()
        T.eq(first.row:sub(26, 26), "R", "first run")
        -- no term_resize reaches the stopped loop
        win.reposition(1, 1, 40, 10)
        local second = runOnce()
        T.eq(frame.width, 40)
        T.eq(frame.height, 10)
        T.eq(label.x, 36, "the right-anchored label moved")
        T.eq(second.bg, colors.blue, "the new columns are drawn")
        T.eq(second.row:sub(36, 36), "R")
    end)
end
