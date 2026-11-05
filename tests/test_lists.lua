-- tests/test_lists.lua
-- List and Dropdown: selection, scrolling, scrollbars, keyboard, binding,
-- empty text and multi-selection. Ported from the deleted 2.5 smoke test
-- (2062cc6:test_smoke.lua).

return function(T)
    -- a 10x4 list at x 14-23, y 2-5 with the items A-F; beforeItems(basalt,
    -- list) runs before the items are added
    local function letterList(beforeItems)
        local basalt, frame, win = T.frame(30, 15)
        local list = frame:addList({ x = 14, y = 2, width = 10, height = 4 })
        if beforeItems then beforeItems(basalt, list) end
        for _, v in ipairs({ "A", "B", "C", "D", "E", "F" }) do list:addItem(v) end
        basalt.update()
        return basalt, frame, list, win
    end

    T.test("a list click selects, fires select and binds two-way", function()
        local selected
        local basalt, _, list = letterList(function(b, l)
            selected = b.state(false)
            l:bind("selected", selected)
        end)
        local index, item
        list:onSelect(function(_, i, it) index, item = i, it end)
        T.click(basalt, 15, 3) -- row 2: B
        T.eq(index, 2)
        T.eq(tostring(item), "B")
        T.eq(list.selected, 2)
        T.eq(selected:get(), 2, "state written")
        T.ok(list:hasState("selected"), "selected state mirrored")
    end)

    T.test("the wheel scrolls a list and clicks follow the offset", function()
        local basalt, _, list = letterList()
        local item
        list:onSelect(function(_, _, it) item = it end)
        basalt.update("mouse_scroll", 1, 15, 3)
        T.eq(list.offset, 1)
        T.click(basalt, 15, 3) -- row 2 + offset 1: C
        T.eq(tostring(item), "C")
        list:removeItem(1)
        T.eq(list.selected, 2, "the selection follows the removal")
        T.eq(tostring(list.items[2]), "C")
    end)

    T.test("a list shows a scrollbar and navigates by keyboard", function()
        local basalt, frame = T.frame(30, 15)
        local list = frame:addList({ x = 22, y = 6, width = 8, height = 3 })
        for i = 1, 8 do list:addItem("L" .. i) end
        local info = list:getScrollInfo()
        T.ok(info.show, "scrollbar shown")
        T.eq(info.maximum, 5)
        list:focus()
        basalt.update("key", keys.down)
        T.eq(list.selected, 1, "down selects the first item")
        basalt.update("key", keys["end"])
        T.eq(list.selected, 8, "end selects the last item")
        T.eq(list.offset, 5, "and scrolls it into view")
    end)

    T.test("dragging a list scrollbar thumb scrolls", function()
        local basalt, frame = T.frame(30, 15)
        local list = frame:addList({ x = 22, y = 6, width = 8, height = 3 })
        for i = 1, 8 do list:addItem("L" .. i) end
        basalt.update()
        basalt.update("mouse_click", 1, 29, 6) -- grab the thumb
        basalt.update("mouse_drag", 1, 29, 8)
        basalt.update("mouse_up", 1, 29, 8)
        T.eq(list.offset, 5)
    end)

    T.test("an empty list shows its empty text", function()
        local basalt, frame, win = T.frame(40, 18)
        frame:addList({ x = 16, y = 1, width = 8, height = 4, emptyText = "leer" })
        basalt.update()
        T.contains(T.row(win, 2):sub(16, 23), "leer")
    end)

    T.test("multi-selection toggles items by click", function()
        local basalt, frame = T.frame(40, 18)
        local list = frame:addList({
            x = 16, y = 1, width = 8, height = 4, multiSelection = true,
        })
        for _, v in ipairs({ "A", "B", "C" }) do list:addItem(v) end
        basalt.update()
        T.click(basalt, 17, 1)
        T.click(basalt, 17, 3)
        local selection = list:getSelection()
        T.eq(#selection, 2)
        T.eq(selection[1], 1); T.eq(selection[2], 3)
        T.click(basalt, 17, 1) -- toggles off again
        selection = list:getSelection()
        T.eq(#selection, 1)
        T.eq(selection[1], 3)
    end)

    -- a 10-wide dropdown at x 2-11, y 10 with eight items, three visible
    local function numberDropdown()
        local basalt, frame = T.frame(30, 15)
        local dd = frame:addDropdown({ x = 2, y = 10, width = 10, dropHeight = 3 })
        for _, value in ipairs({ "Eins", "Zwei", "Drei", "Vier",
            "Fuenf", "Sechs", "Sieben", "Acht" }) do
            dd:addItem(value)
        end
        basalt.update()
        return basalt, frame, dd
    end

    T.test("a dropdown opens and selects an item with the mouse", function()
        local basalt, _, dd = numberDropdown()
        T.eq(dd.height, 1, "starts closed")
        T.click(basalt, 3, 10)
        T.eq(dd.open, true, "opened")
        T.eq(dd.height, 4)
        local index
        dd:onSelect(function(_, i) index = i end)
        T.click(basalt, 3, 12) -- list row 2
        T.eq(index, 2)
        T.eq(dd.selected, 2)
        T.eq(dd.open, false, "closes after the selection")
        T.ok(dd:hasState("selected"), "selected state mirrored")
    end)

    T.test("an open dropdown scrolls by wheel and selects by keyboard", function()
        local basalt, _, dd = numberDropdown()
        local index
        dd:onSelect(function(_, i) index = i end)
        T.click(basalt, 3, 10)
        local info = dd:getScrollInfo()
        T.ok(info.show, "scrollbar shown")
        T.eq(info.maximum, 5)
        basalt.update("mouse_scroll", 1, 3, 11)
        T.eq(dd.offset, 1, "wheel")
        basalt.update("key", keys["end"])
        T.eq(dd.offset, 5, "end scrolls the last item into view")
        T.eq(dd.open, true)
        basalt.update("key", keys.enter)
        T.eq(dd.selected, 8)
        T.eq(index, 8)
        T.eq(dd.open, false)
    end)

    T.test("a dropdown closes on escape and on blur", function()
        local basalt, _, dd = numberDropdown()
        T.click(basalt, 3, 10)
        T.withEscape(function(escape) basalt.update("key", escape) end)
        T.eq(dd.open, false, "escape closes")
        T.click(basalt, 3, 10)
        T.eq(dd.open, true)
        T.click(basalt, 25, 14) -- a click elsewhere moves the focus
        T.eq(dd.open, false, "blur closes")
    end)
end
