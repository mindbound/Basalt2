-- tests/test_menus.lua
-- Menu (with submenus), TabControl, ContextMenu and ComboBox.
-- Ported from the deleted 2.5 smoke test (2062cc6:test_smoke.lua).

return function(T)
    T.test("a menu auto-sizes, selects by click and by keyboard", function()
        local basalt, frame = T.frame(40, 18)
        local menu = frame:addMenu({ x = 1, y = 5 })
        menu:addItem("File"):addItem("Edit") -- entries forward addItem
        T.eq(menu.width, 13, "auto width: ' File ' + gap + ' Edit '")
        local index
        menu:onSelect(function(_, i) index = i end)
        basalt.update()
        T.click(basalt, 9, 5) -- inside " Edit "
        T.eq(index, 2)
        T.eq(menu.selected, 2)
        basalt.update("key", keys.left)
        T.eq(menu.selected, 1, "left arrow")
    end)

    T.test("a menu opens submenus and skips separators", function()
        local basalt, frame = T.frame(40, 18)
        local menu = frame:addMenu({ x = 1, y = 14 })
        menu.items = {
            { text = "File", items = { "New", "Open" } },
            { separator = true },
            "Help",
        }
        local item, parent
        menu:onSelect(function(_, _, it, p) item, parent = it, p end)
        basalt.update()
        T.click(basalt, 2, 14) -- File opens its submenu
        T.eq(menu.height, 3, "the submenu expands the menu")
        T.click(basalt, 2, 16) -- submenu row 2
        T.eq(item, "Open")
        T.eq(parent, 1)
        T.eq(menu.height, 1, "the submenu closes after the selection")
        item = nil
        T.click(basalt, 8, 14) -- the separator
        T.eq(item, nil, "a separator does not select")
    end)

    T.test("a tab control switches tabs and routes content", function()
        local basalt, frame = T.frame(40, 18)
        local tc = frame:addTabControl({ x = 15, y = 5, width = 20, height = 6 })
        local one = tc:addTab("One")
        local two = tc:addTab("Two")
        one:addLabel({ x = 1, y = 1, text = "T1", name = "t1lbl" })
        two:addLabel({ x = 1, y = 1, text = "T2", name = "t2lbl" })
        basalt.update()
        T.eq(tc.active, 1, "the first tab is active")
        T.ok(one.visible and not two.visible, "only the active tab is visible")
        T.eq(one.width, 20); T.eq(one.height, 5)
        local switched
        tc:onChange(function(_, _, title) switched = title end)
        T.click(basalt, 21, 5) -- header " Two " (local x 7)
        T.eq(tc.active, 2)
        T.eq(switched, "Two")
        T.ok(two.visible and not one.visible, "visibility follows")
        basalt.update()
        T.eq(frame:findAt(15, 6), frame:find("t2lbl"),
            "hit testing reaches the active tab")
    end)

    T.test("a context menu opens, selects and closes", function()
        local basalt, frame = T.frame(40, 18)
        local cm = frame:addContextMenu()
        cm:setItems({ "Copy", { separator = true }, "Delete" })
        cm:openAt(30, 12)
        T.eq(cm.visible, true)
        T.eq(cm.x, 30); T.eq(cm.y, 12)
        local item
        cm:onSelect(function(_, _, it) item = it end)
        basalt.update()
        T.click(basalt, 32, 14) -- row 3: Delete
        T.eq(tostring(item), "Delete")
        T.eq(cm.visible, false, "closes after the selection")
        cm:openAt(30, 12)
        basalt.update()
        T.click(basalt, 2, 2) -- outside: blur closes
        T.eq(cm.visible, false, "closes on an outside click")
    end)

    -- a 10-wide auto-complete combo box at x 25-34, y 8
    local function fruitCombo()
        local basalt, frame = T.frame(40, 18)
        local cbx = frame:addComboBox({ x = 25, y = 8, width = 10, autoComplete = true })
        cbx:addItem("Apfel"):addItem("Apfelsaft"):addItem("Birne")
        basalt.update()
        return basalt, frame, cbx
    end

    T.test("a combo box opens by its arrow and selects a row", function()
        local basalt, _, cbx = fruitCombo()
        local index
        cbx:onSelect(function(_, i) index = i end)
        T.click(basalt, 34, 8) -- the arrow cell
        T.eq(cbx.open, true)
        T.eq(cbx.height, 4)
        T.click(basalt, 26, 10) -- row 2
        T.eq(cbx.text, "Apfelsaft")
        T.eq(index, 2)
        T.eq(cbx.open, false)
    end)

    T.test("a combo box filters while typing and accepts with enter", function()
        local basalt, _, cbx = fruitCombo()
        local index
        cbx:onSelect(function(_, i) index = i end)
        T.click(basalt, 26, 8) -- focus the input row
        basalt.update("char", "B")
        T.eq(cbx.open, true, "auto-complete opens while typing")
        local display = cbx:getDisplayItems()
        T.eq(#display, 1)
        T.eq(display[1].text, "Birne")
        basalt.update("key", keys.enter)
        T.eq(cbx.text, "Birne")
        T.eq(index, 3)
    end)
end
