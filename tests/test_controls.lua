-- tests/test_controls.lua
-- Checkbox, Switch, ProgressBar, Slider, wrapping Labels and draggable
-- Frames. Ported from the deleted 2.5 smoke test (2062cc6:test_smoke.lua).

return function(T)
    T.test("a checkbox auto-sizes, toggles and binds two-way", function()
        local basalt, frame = T.frame(30, 15)
        local cb = frame:addCheckbox({ x = 2, y = 2, text = "Ok" })
        local checked = basalt.state(false)
        local changed
        cb:bind("checked", checked)
        cb:onChange(function(_, v) changed = v end)
        T.eq(cb.width, 6, "auto width")
        T.eq(cb.checked, false)
        T.eq(checked:get(), false)
        basalt.update()
        T.click(basalt, 3, 2)
        T.eq(cb.checked, true, "toggled")
        T.eq(changed, true, "change event")
        T.eq(checked:get(), true, "state written")
        T.ok(basalt.isState(cb:raw("checked")), "binding restored")
        T.ok(cb:hasState("checked"), "checked state mirrored")
    end)

    T.test("a custom checked symbol is drawn", function()
        local basalt, frame, win = T.frame(30, 15)
        local cb = frame:addCheckbox({ x = 2, y = 2, text = "Ok", checked = true })
        cb.checkedSymbol = "o"
        basalt.update()
        T.eq(T.row(win, 2), " [o] Ok")
    end)

    T.test("a switch toggles on click", function()
        local basalt, frame = T.frame(30, 15)
        local sw = frame:addSwitch({ x = 2, y = 4 })
        basalt.update()
        T.click(basalt, 3, 4)
        T.eq(sw.checked, true)
        T.ok(sw:hasState("checked"), "checked state mirrored")
    end)

    T.test("progress is clamped to 0-100", function()
        local _, frame = T.frame(30, 15)
        local pb = frame:addProgressBar({ x = 2, y = 6, width = 10 })
        pb.progress = 150
        T.eq(pb.progress, 100)
        pb.progress = -5
        T.eq(pb.progress, 0)
    end)

    T.test("a progress bar fills leftwards and shows a percentage", function()
        local basalt, frame, win = T.frame(40, 18)
        frame:addProgressBar({
            x = 1, y = 5, width = 10, height = 1,
            progress = 50, direction = "left", showPercentage = true,
        })
        basalt.update()
        T.contains(T.row(win, 5):sub(1, 10), "50%")
        T.eq(T.bg(win, 10, 5), colors.lime, "the filled end is on the right")
        T.eq(T.bg(win, 1, 5), colors.gray, "the empty end is on the left")
    end)

    T.test("a slider: click sets the value, drag clamps, binding two-way", function()
        local basalt, frame = T.frame(30, 15)
        local sl = frame:addSlider({ x = 2, y = 8, width = 11 })
        local value = basalt.state(0)
        local changed
        sl:bind("value", value)
        sl:onChange(function(_, v) changed = v end)
        basalt.update()
        basalt.update("mouse_click", 1, 7, 8) -- local x 6 of 11: 50%
        T.eq(sl.value, 50)
        T.eq(changed, 50)
        T.eq(value:get(), 50, "state written")
        basalt.update("mouse_drag", 1, 29, 8) -- beyond the end
        basalt.update("mouse_up", 1, 29, 8)
        T.eq(sl.value, 100, "drag clamps to max")
    end)

    T.test("the mouse wheel moves a slider by one step", function()
        local basalt, frame = T.frame(30, 15)
        local sl = frame:addSlider({ x = 2, y = 8, width = 11, value = 100 })
        basalt.update()
        basalt.update("mouse_scroll", -1, 3, 8)
        T.eq(sl.value, 99)
        basalt.update("mouse_scroll", 1, 3, 8)
        T.eq(sl.value, 100)
        basalt.update("mouse_scroll", 1, 3, 8)
        T.eq(sl.value, 100, "clamped at max")
    end)

    T.test("a vertical slider uses its height", function()
        local basalt, frame = T.frame(40, 18)
        local vs = frame:addSlider({
            x = 14, y = 3, horizontal = false,
            width = 1, height = 6, min = 0, max = 10,
        })
        basalt.update()
        T.click(basalt, 14, 8) -- local y 6 = the end
        T.eq(vs.value, 10)
    end)

    T.test("a label with a manual width wraps and grows", function()
        local basalt, frame, win = T.frame(40, 18)
        local label = frame:addLabel({ x = 1, y = 1, text = "one two three four" })
        label.width = 8
        T.eq(label.height, 3)
        basalt.update()
        T.eq(T.row(win, 1), "one two")
        T.eq(T.row(win, 2), "three")
        T.eq(T.row(win, 3), "four")
    end)

    T.test("a draggable frame moves by its top row only", function()
        local basalt, frame = T.frame(40, 18)
        local df = frame:addFrame({ x = 3, y = 8, width = 8, height = 4, draggable = true })
        basalt.update()
        basalt.update("mouse_click", 1, 4, 8) -- grab the top row
        basalt.update("mouse_drag", 1, 7, 10)
        basalt.update("mouse_up", 1, 7, 10)
        T.eq(df.x, 6); T.eq(df.y, 10)
        basalt.update("mouse_click", 1, 7, 12) -- the body is no drag zone
        basalt.update("mouse_drag", 1, 9, 12)
        basalt.update("mouse_up", 1, 9, 12)
        T.eq(df.x, 6, "a body drag does not move the frame")
        T.eq(df.y, 10)
    end)
end
