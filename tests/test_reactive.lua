-- tests/test_reactive.lua
-- Application state (signals, computed values, bindings) and "{...}"
-- reactive expressions. Ported from the deleted 2.5 smoke test
-- (2062cc6:test_smoke.lua).

return function(T)
    T.test("a computed property follows its signals and dirties the tree", function()
        local basalt, frame = T.frame()
        local count = basalt.state(1)
        local prefix = basalt.state("Count")
        local label = frame:addLabel({
            x = 25, y = 2, width = 20,
            text = basalt.computed(function()
                return prefix:get() .. ": " .. count:get()
            end),
        })
        T.eq(label.text, "Count: 1", "initial value")
        basalt.update()
        T.ok(not rawget(frame, "_dirty"), "a draw clears the dirty flag")
        count:set(2)
        T.ok(rawget(frame, "_dirty"), "a signal write dirties the dependent tree")
        T.eq(label.text, "Count: 2")
        prefix:set("Total")
        T.eq(label.text, "Total: 2", "second dependency")
    end)

    T.test("map and update derive values", function()
        local basalt, frame = T.frame()
        local count = basalt.state(2)
        local mapped = count:map(function(v) return v * 10 end)
        local label = frame:addLabel({ x = 25, y = 3, width = 6, text = mapped })
        T.eq(label.text, 20)
        count:update(function(v) return v + 1 end)
        T.eq(label.text, 30)
        T.ok(basalt.isState(count), "a signal is state")
        T.ok(basalt.isState(mapped), "a mapped value is state")
        T.ok(not basalt.isState({}), "a table is not state")
    end)

    T.test("subscribe reports new and old values until unsubscribed", function()
        local basalt = T.loadBasalt()
        local count = basalt.state(3)
        local observedNew, observedOld
        local unsubscribe = count:subscribe(function(new, old)
            observedNew, observedOld = new, old
        end)
        count:set(4)
        T.eq(observedNew, 4); T.eq(observedOld, 3)
        unsubscribe()
        count:set(5)
        T.eq(observedNew, 4, "no call after unsubscribe")
    end)

    T.test("touch notifies after an in-place table mutation", function()
        local basalt = T.loadBasalt()
        local tableState = basalt.state({ value = 1 })
        local touches = 0
        tableState:subscribe(function() touches = touches + 1 end)
        tableState:get().value = 2
        tableState:touch()
        T.eq(touches, 1)
    end)

    T.test("a replaced signal keeps no stale UI dependency", function()
        local basalt, frame = T.frame()
        local stale = basalt.state("bound")
        local label = frame:addLabel({ x = 25, y = 4, width = 8, text = stale })
        basalt.update()
        label.text = "fixed"
        basalt.update()
        T.ok(not rawget(frame, "_dirty"), "setup finishes clean")
        stale:set("obsolete")
        T.ok(not rawget(frame, "_dirty"), "the old signal no longer dirties the tree")
    end)

    T.test("an input binding is two-way", function()
        local basalt, frame = T.frame()
        local value = basalt.state("A")
        local input = frame:addInput({ x = 25, y = 5, width = 8 })
        input:bind("text", value)
        T.eq(input.text, "A", "initial value")
        input:handleKey("char", "B")
        T.eq(value:get(), "BA", "typing writes the state")
        T.eq(input.text, "BA")
        T.ok(basalt.isState(input:raw("text")), "the binding is restored after the edit")
        value:set("External")
        T.eq(input.text, "External", "a state write reaches the input")
        input:unbind("text")
        value:set("Detached")
        T.eq(input.text, "External", "unbind keeps the current value")
    end)

    T.test("a binding with a transform", function()
        local basalt, frame = T.frame()
        local count = basalt.state(5)
        local label = frame:addLabel({ x = 25, y = 6, width = 12 })
        label:bind("text", count, function(v) return "Value=" .. v end)
        T.eq(label.text, "Value=5")
        count:set(6)
        T.eq(label.text, "Value=6")
    end)

    T.test("changing a drawn element dirties the root every time", function()
        local basalt, frame, win = T.frame()
        local label = frame:addLabel({ x = 2, y = 2, text = "Hello" })
        basalt.update()
        label.text = "42"
        T.ok(rawget(frame, "_dirty"), "first change")
        basalt.update()
        T.eq(T.row(win, 2), " 42")
        label.text = "43"
        T.ok(rawget(frame, "_dirty"), "second change")
        basalt.update()
        T.eq(T.row(win, 2), " 43")
    end)

    T.test("reactive expressions follow their sources", function()
        local _, frame = T.frame()
        local rframe = frame:addFrame({ x = 40, y = 14, width = 10, height = 3 })
        local rl = rframe:addLabel({ text = "abc", name = "rl" })
        rl.x = "{parent.width - 2}"
        T.eq(rl.x, 8)
        rframe.width = 12
        T.eq(rl.x, 10, "after a parent resize")
        rl.width = "{#self.text + 2}"
        T.eq(rl.width, 5, "self reference")
        rl:setY("{clamp(parent.height * 5, 1, 2)}")
        T.eq(rl.y, 2, "helper function")
        local other = rframe:addLabel({ text = "q", x = "{rl.x + 1}" })
        T.eq(other.x, 11, "reference by name")
    end)

    T.test("an invalid reactive expression raises", function()
        local _, frame = T.frame()
        local label = frame:addLabel({ text = "abc" })
        T.raises(function() label.y = "{this is not lua}" end,
            "invalid reactive expression")
    end)

    T.test("raw-string properties never compile as expressions", function()
        local _, frame = T.frame()
        local input = frame:addInput({ x = 30, y = 2, width = 8 })
        input.text = "{5 + 5}"
        T.eq(input.text, "{5 + 5}")
    end)
end
