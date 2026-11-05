-- tests/test_collection.lua
-- The shared Collection API (List, Dropdown, Menu, ContextMenu, ComboBox,
-- Collection). Ported from the deleted 2.5 test 2062cc6:test_collection.lua.

return function(T)
    -- a list with One, Two (yellow) and Three; events are counted and
    -- their arguments checked
    local function countedList()
        local _, frame = T.frame()
        local list = frame:addList({ width = 14, height = 4 })
        local counts = { changes = 0, selects = 0 }
        list:onChange(function(_, index, item)
            counts.changes = counts.changes + 1
            T.ok(index == false or item == list.items[index], "change arguments")
        end)
        list:onSelect(function(_, index, item)
            counts.selects = counts.selects + 1
            T.eq(item, list.items[index], "select arguments")
        end)
        list:setItems({ "One", { text = "Two", fg = colors.yellow }, "Three" })
        return frame, list, counts
    end

    T.test("setItems normalizes entries; addItem returns an entry", function()
        local _, list = countedList()
        T.eq(list:getItemCount(), 3)
        T.eq(tostring(list:getItem(2)), "Two")
        T.eq(list:getItems()[2].fg, colors.yellow, "item data is kept")
        local four = list:addItem("Four")
        T.eq(tostring(four), "Four")
        T.eq(four:getParent(), list)
        four:setText("Fourth")
        T.eq(tostring(list:getItem(4)), "Fourth", "an entry edits in place")
    end)

    T.test("selectItem fires change; activateItem fires select", function()
        local _, list, counts = countedList()
        list:selectItem(2)
        T.eq(counts.changes, 1)
        T.eq(counts.selects, 0)
        T.eq(list:getSelectedIndex(), 2)
        T.eq(list:getSelectedItem(), list.items[2])
        T.ok(list.items[2]:isSelected())
        T.eq(list.selected, 2)
        list:activateItem(2)
        T.eq(counts.changes, 1, "already selected: no change")
        T.eq(counts.selects, 1)
    end)

    T.test("a selected entry keeps its selection when moved or removed", function()
        local _, list = countedList()
        list:addItem("Four")
        list:selectItem(2)
        local selected = list:getSelectedItem()
        selected:moveToBottom()
        T.eq(list:getSelectedItem(), selected)
        T.eq(list:getSelectedIndex(), 4)
        selected:moveToTop()
        T.eq(list:getSelectedIndex(), 1)
        selected:remove()
        T.eq(list:getSelectedItem(), nil)
        T.eq(list:getItemCount(), 3)
    end)

    T.test("multi-selection by index and by entry flag", function()
        local _, list = countedList()
        list:setMultiSelection(true):clearItemSelection(false)
        list:selectItem(1):selectItem(3)
        local indices = list:getSelection()
        T.eq(#indices, 2)
        T.eq(indices[1], 1); T.eq(indices[2], 3)
        list.items[1].selected = false
        T.ok(not list.items[1]:isSelected())
        T.ok(list.items[3]:isSelected())
    end)

    T.test("clear, then an entry forwards addItem to its list", function()
        local _, list = countedList()
        list:clear()
        local first = list:addItem("A")
        local second = first:addItem("B")
        T.eq(list:getItemCount(), 2)
        T.eq(tostring(second), "B")
    end)

    T.test("every collection element shares the API", function()
        local _, frame = T.frame()
        local elements = {
            frame:addDropdown():setItems({ "Red", "Green" }),
            frame:addMenu():setItems({ "File", "Help" }),
            frame:addContextMenu():setItems({ "Copy", "Paste" }),
            frame:addComboBox():setItems({ "Apple", "Pear" }),
        }
        for _, element in ipairs(elements) do
            T.eq(element:getItemCount(), 2, element.__name)
            T.eq(type(element.getSelectedItem), "function", element.__name)
            T.eq(type(element.clearItemSelection), "function", element.__name)
        end
    end)

    T.test("a combo box fires selectionChange on selectDisplayed", function()
        local _, frame = T.frame()
        local combo = frame:addComboBox():setItems({ "Apple", "Pear" })
        local changes = 0
        combo:onSelectionChange(function(_, index, item)
            changes = changes + 1
            T.eq(index, 2); T.eq(tostring(item), "Pear")
        end)
        combo:selectDisplayed(2)
        T.eq(combo.text, "Pear")
        T.eq(combo:getSelectedIndex(), 2)
        T.eq(changes, 1)
    end)

    T.test("a generic collection: initial selection and color accessors", function()
        local _, frame = T.frame()
        local generic = frame:addCollection()
        local entry = generic:addItem({ text = "Generic", selected = true })
        T.eq(generic:getSelectedItem(), entry)
        T.eq(entry.selected, true)
        generic:setSelectionColor(colors.black, colors.white)
        local fg, bg = generic:getSelectionColor()
        T.eq(fg, colors.black); T.eq(bg, colors.white)
        generic:setSelectedForeground(colors.red):setSelectedBackground(colors.blue)
        T.eq(generic.selectionForeground, colors.red)
        T.eq(generic.selectionBackground, colors.blue)
    end)
end
