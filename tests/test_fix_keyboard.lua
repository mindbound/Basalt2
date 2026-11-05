-- tests/test_fix_keyboard.lua
-- Keyboard use without a mouse: Dialog focus and buttons, List scrolling
-- when it is not selectable, Menu submenus and ContextMenu focus.

return function(T)
    local function dialogButton(dialog, text)
        local box = dialog:getChildren()[1]
        for _, child in ipairs(box:getChildren()) do
            if child.text == text and child.__name == "Button" then return child end
        end
    end

    local function dialogInput(dialog)
        local box = dialog:getChildren()[1]
        for _, child in ipairs(box:getChildren()) do
            if child.__name == "Input" then return child end
        end
    end

    local function key(basalt, code)
        basalt.update("key", code)
        basalt.update("key_up", code)
    end

    local function shiftTab(basalt)
        basalt.update("key", keys.leftShift)
        key(basalt, keys.tab)
        basalt.update("key_up", keys.leftShift)
    end

    -- an input at the bottom of a 40x18 frame, focused, with "ab" typed
    local function inputBehind()
        local basalt, frame, win = T.frame(40, 18)
        local input = frame:addInput({ x = 2, y = 17, width = 10 })
        local dlg = frame:addDialog()
        basalt.update()
        input:focus()
        T.type(basalt, "ab")
        T.eq(input.text, "ab")
        return basalt, frame, input, dlg, win
    end

    -- ---------------------------------------------------------------- Dialog

    T.test("a confirm dialog takes the focus and answers by keyboard", function()
        local basalt, frame, input, dlg = inputBehind()
        local answer
        dlg:confirm("Delete?", "Really?", function(yes) answer = yes end)
        basalt.update()
        local yes, no = dialogButton(dlg, "Yes"), dialogButton(dlg, "No")
        T.eq(frame:getFocused(), yes, "the default button has the focus")
        key(basalt, keys.right)
        T.eq(frame:getFocused(), no, "right moves to No")
        key(basalt, keys.right)
        T.eq(frame:getFocused(), no, "right stops at the last button")
        key(basalt, keys.left)
        T.eq(frame:getFocused(), yes, "left moves back to Yes")
        key(basalt, keys.tab)
        T.eq(frame:getFocused(), no, "tab moves to No")
        key(basalt, keys.tab)
        T.eq(frame:getFocused(), yes, "tab wraps around")
        shiftTab(basalt)
        T.eq(frame:getFocused(), no, "shift+tab goes backwards")
        key(basalt, keys.enter)
        T.eq(answer, false, "enter presses the focused button")
        T.eq(dlg.visible, false)
        T.eq(frame:getFocused(), input, "the focus returns to the input")
    end)

    T.test("typed characters do not reach an input behind an open dialog", function()
        local basalt, frame, input, dlg = inputBehind()
        local closed = false
        dlg:alert("Info", "Saved", function() closed = true end)
        basalt.update()
        T.eq(frame:getFocused(), dialogButton(dlg, "OK"))
        T.type(basalt, "xy")
        basalt.update("paste", "pasted")
        key(basalt, keys.backspace)
        T.eq(input.text, "ab", "the input behind is untouched")
        key(basalt, keys.enter)
        T.eq(closed, true, "enter on OK closes the alert")
        T.eq(frame:getFocused(), input, "the focus is back")
        T.type(basalt, "c")
        T.eq(input.text, "abc", "typing reaches the input again")
    end)

    T.test("the focused dialog button is drawn in the title colors", function()
        local basalt, _, _, dlg, win = inputBehind()
        dlg:confirm("Q", "Sure?")
        basalt.update()
        local yes, no = dialogButton(dlg, "Yes"), dialogButton(dlg, "No")
        local yx, yy = yes:getAbsolutePosition()
        local nx, ny = no:getAbsolutePosition()
        T.eq(T.bg(win, yx, yy), dlg.titleBackground, "focused Yes")
        T.eq(T.fg(win, yx + 1, yy), dlg.titleForeground, "focused Yes text")
        T.eq(T.bg(win, nx, ny), colors.gray, "No keeps the button color")
        key(basalt, keys.right)
        T.eq(T.bg(win, yx, yy), colors.gray, "Yes after moving on")
        T.eq(T.bg(win, nx, ny), dlg.titleBackground, "focused No")
    end)

    T.test("a prompt focuses its input; tab cycles input and buttons", function()
        local basalt, frame, input, dlg = inputBehind()
        local value = "unset"
        dlg:prompt("Name", "Your name:", "Steve", function(v) value = v end)
        basalt.update()
        local field = dialogInput(dlg)
        local ok, cancel = dialogButton(dlg, "OK"), dialogButton(dlg, "Cancel")
        T.eq(frame:getFocused(), field, "the prompt's input has the focus")
        T.eq(field.text, "Steve", "the default is the starting text")
        T.type(basalt, "x")
        T.eq(field.text, "Stevex", "typing appends to the default")
        key(basalt, keys.left)
        T.eq(frame:getFocused(), field, "left/right stay in the input")
        key(basalt, keys.tab)
        T.eq(frame:getFocused(), ok)
        key(basalt, keys.right)
        T.eq(frame:getFocused(), cancel)
        key(basalt, keys.tab)
        T.eq(frame:getFocused(), field, "tab wraps to the input")
        shiftTab(basalt)
        T.eq(frame:getFocused(), cancel, "shift+tab wraps backwards")
        shiftTab(basalt)
        T.eq(frame:getFocused(), ok)
        key(basalt, keys.enter)
        T.eq(value, "Stevex", "enter on OK accepts")
        T.eq(input.text, "ab")
        T.eq(frame:getFocused(), input, "the focus is back")
    end)

    T.test("enter in a prompt's input confirms; enter on Cancel cancels", function()
        local basalt, frame, input, dlg = inputBehind()
        local value = "unset"
        dlg:prompt("Name", "Your name:", "", function(v) value = v end)
        basalt.update()
        T.type(basalt, "Alex")
        key(basalt, keys.enter)
        T.eq(value, "Alex")
        T.eq(dlg.visible, false)
        T.eq(frame:getFocused(), input)
        T.eq(input.text, "ab")

        value = "unset"
        dlg:prompt("Name", "Your name:", "x", function(v) value = v end)
        key(basalt, keys.tab)
        key(basalt, keys.tab)
        T.eq(frame:getFocused(), dialogButton(dlg, "Cancel"))
        key(basalt, keys.enter)
        T.eq(value, nil, "cancel answers nil")
        T.eq(frame:getFocused(), input)
    end)

    T.test("a prompt without a default takes the callback third", function()
        local basalt, _, _, dlg = inputBehind()
        local value = "unset"
        dlg:prompt("Name", "Your name:", function(v) value = v end)
        basalt.update()
        T.eq(dialogInput(dlg).text, "", "no function text as the default")
        T.type(basalt, "Kim")
        key(basalt, keys.enter)
        T.eq(value, "Kim")
    end)

    T.test("escape answers no, cancel or OK", function()
        T.withEscape(function(escape)
            local basalt, frame, input, dlg = inputBehind()
            local answer
            dlg:confirm("Q", "Sure?", function(yes) answer = yes end)
            key(basalt, escape)
            T.eq(answer, false, "confirm")
            local value = "unset"
            dlg:prompt("Q", "Name?", "a", function(v) value = v end)
            key(basalt, escape)
            T.eq(value, nil, "prompt")
            local closed = false
            dlg:alert("Q", "Done", function() closed = true end)
            key(basalt, escape)
            T.eq(closed, true, "alert")
            T.eq(frame:getFocused(), input)
        end)
    end)

    T.test("clicks inside a dialog keep the focus on its controls", function()
        local basalt, frame, input, dlg = inputBehind()
        local answer
        dlg:confirm("Question", "Sure?", function(yes) answer = yes end)
        basalt.update()
        local no = dialogButton(dlg, "No")
        key(basalt, keys.right)
        T.click(basalt, 1, 1) -- the backdrop
        T.eq(frame:getFocused(), no, "a backdrop click")
        local box = dlg:getChildren()[1]
        local bx, by = box:getAbsolutePosition()
        T.click(basalt, bx + 1, by) -- the title bar
        T.eq(frame:getFocused(), no, "a title click")
        T.click(basalt, bx + 1, by + 1) -- the box padding
        T.eq(frame:getFocused(), no, "a box click")
        dlg:focus() -- the documented pattern still works
        T.eq(frame:getFocused(), no, "focusing the dialog")
        key(basalt, keys.enter)
        T.eq(answer, false)
        T.eq(frame:getFocused(), input)
    end)

    T.test("a mouse answer also gives the focus back", function()
        local basalt, frame, input, dlg = inputBehind()
        local answer
        dlg:confirm("Q", "Sure?", function(yes) answer = yes end)
        basalt.update()
        local bx, by = dialogButton(dlg, "Yes"):getAbsolutePosition()
        T.click(basalt, bx, by)
        T.eq(answer, true)
        T.eq(frame:getFocused(), input)
    end)

    T.test("a dialog only gives back a focus it holds", function()
        local basalt, frame, input, dlg = inputBehind()
        local other = frame:addInput({ x = 20, y = 17, width = 5 })
        dlg:confirm("Q", "Sure?")
        basalt.update()
        other:focus() -- the app moves the focus while the dialog is open
        dlg:close(false)
        T.eq(frame:getFocused(), other, "the app's focus is kept")
        T.eq(input.text, "ab")
    end)

    T.test("chained dialogs give the focus back to the first owner", function()
        local basalt, frame, input, dlg = inputBehind()
        local done = false
        dlg:confirm("Q", "Sure?", function()
            dlg:alert("Info", "Done", function() done = true end)
        end)
        key(basalt, keys.enter)
        T.eq(dlg.visible, true, "the alert is open")
        T.eq(frame:getFocused(), dialogButton(dlg, "OK"))
        key(basalt, keys.enter)
        T.eq(done, true)
        T.eq(frame:getFocused(), input)
    end)

    T.test("a dialog opened without a focus leaves none behind", function()
        local basalt, frame = T.frame(40, 18)
        local dlg = frame:addDialog()
        dlg:alert("Info", "Hi")
        basalt.update()
        T.eq(frame:getFocused(), dialogButton(dlg, "OK"))
        key(basalt, keys.enter)
        T.eq(frame:getFocused(), nil)
    end)

    T.test("hiding an open dialog gives the focus back; enter does not answer it", function()
        local basalt, frame, input, dlg = inputBehind()
        local answer = "unset"
        dlg:confirm("Q", "Sure?", function(yes) answer = yes end)
        basalt.update()
        local yes = dialogButton(dlg, "Yes")
        T.eq(frame:getFocused(), yes)
        dlg.visible = false
        T.eq(frame:getFocused(), input, "the focus is back on the input")
        key(basalt, keys.enter)
        T.eq(answer, "unset", "enter does not answer the hidden dialog")
        T.type(basalt, "c")
        T.eq(input.text, "abc", "typing reaches the input")
        yes:focus() -- even a control focused by the app ignores the keys
        key(basalt, keys.enter)
        T.eq(answer, "unset", "a focused control of a hidden dialog")
        input:focus()
        dlg.visible = true -- shown again: the focus stays where it is
        T.eq(frame:getFocused(), input)
        dlg:close(false)
        T.eq(frame:getFocused(), input, "close keeps a focus outside the dialog")
        T.eq(dlg.visible, false)
    end)

    T.test("a dialog in a hidden frame does not take the focus", function()
        local basalt, frame, input = inputBehind()
        local hidden = frame:addFrame({ x = 1, y = 1, width = 40, height = 15, visible = false })
        local dlg = hidden:addDialog()
        local closed = false
        dlg:alert("Info", "Hi", function() closed = true end)
        basalt.update()
        T.eq(frame:getFocused(), input, "an alert")
        key(basalt, keys.enter)
        T.eq(closed, false, "enter does not answer it")
        local answer = "unset"
        dlg:confirm("Q", "Sure?", function(yes) answer = yes end)
        T.eq(frame:getFocused(), input, "a confirm")
        key(basalt, keys.enter)
        T.eq(answer, "unset")
        local value = "unset"
        dlg:prompt("Name", "Your name:", function(v) value = v end)
        T.eq(frame:getFocused(), input, "a prompt")
        T.type(basalt, "c")
        T.eq(input.text, "abc", "typing reaches the input, not the prompt")
        T.eq(dialogInput(dlg).text, "")
        key(basalt, keys.enter)
        T.eq(value, "unset")
        hidden.visible = true
        dlg:focus() -- shown: the documented pattern moves the focus in
        T.eq(frame:getFocused(), dialogInput(dlg))
        T.type(basalt, "Kim")
        key(basalt, keys.enter)
        T.eq(value, "Kim")
        T.eq(frame:getFocused(), input, "the focus goes back to the input")
    end)

    T.test("a held enter does not answer a dialog", function()
        local basalt, frame, input, dlg = inputBehind()
        local answer = "unset"
        input:onEnter(function()
            dlg:confirm("Q", "Sure?", function(yes) answer = yes end)
        end)
        basalt.update("key", keys.enter) -- opens the confirm
        T.eq(dlg.visible, true)
        T.eq(frame:getFocused(), dialogButton(dlg, "Yes"))
        basalt.update("key", keys.enter, true) -- the key is still held
        basalt.update("key", keys.enter, true)
        T.eq(answer, "unset", "auto-repeat does not press Yes")
        T.eq(dlg.visible, true)
        basalt.update("key_up", keys.enter)
        key(basalt, keys.enter)
        T.eq(answer, true, "a new press does")
        T.eq(frame:getFocused(), input)

        local value = "unset"
        dlg:prompt("Name", "Your name:", "x", function(v) value = v end)
        T.eq(frame:getFocused(), dialogInput(dlg))
        basalt.update("key", keys.enter, true)
        T.eq(value, "unset", "a held enter does not accept a prompt")
        T.eq(dlg.visible, true)
        basalt.update("key_up", keys.enter)
        key(basalt, keys.enter)
        T.eq(value, "x", "a new press does")
    end)

    T.test("dialog titles and messages are shown as written, also with reactive strings on", function()
        local basalt, frame, win = T.frame(40, 18)
        T.eq(basalt.getReactiveStrings(), true)
        local dlg = frame:addDialog()
        -- no wrapped line of the message as a whole looks like "{...}"
        -- before wrapping; the second one does after it
        local message = ("x"):rep(20) .. " {self:destroy()} " .. ("y"):rep(20)
            .. ' {"a":1}'
        dlg:alert("{1 + 1}", message)
        basalt.update()
        local screen = T.screen(win)
        T.contains(screen, "{1 + 1}", "the title")
        T.eq(dlg.title, "{1 + 1}")
        T.contains(screen, "{self:destroy()}", "a wrapped line")
        T.contains(screen, '{"a":1}', "a wrapped JSON line")
        T.eq(#dlg:getChildren()[1]:getChildren(), 6, "box: title, 4 lines, OK")
        dlg:close()
        T.eq(rawget(dlg, "parent"), frame)

        dlg:confirm(basalt.literal("{self:destroy()}"), basalt.literal("{2 + 2}"))
        basalt.update()
        screen = T.screen(win)
        T.contains(screen, "{self:destroy()}", "a literal title")
        T.contains(screen, "{2 + 2}", "a literal message")
        T.eq(rawget(dlg, "parent"), frame)
        dlg:close()

        dlg:prompt(7, "{3 + 3}", "{4 + 4}")
        basalt.update()
        screen = T.screen(win)
        T.contains(screen, "7", "a number title")
        T.contains(screen, "{3 + 3}")
        T.eq(dialogInput(dlg).text, "{4 + 4}", "the input's text")
        dlg:close()
    end)

    T.test("stacked dialogs closed out of order give the focus back", function()
        local basalt, frame, input, first = inputBehind()
        local second = frame:addDialog()
        first:confirm("Q", "Sure?")
        basalt.update()
        T.eq(frame:getFocused(), dialogButton(first, "Yes"))
        local closed = false
        second:alert("Info", "Busy", function() closed = true end)
        T.eq(frame:getFocused(), dialogButton(second, "OK"))
        first:close(false) -- the app closes the first one meanwhile
        T.eq(frame:getFocused(), dialogButton(second, "OK"), "the open one keeps it")
        key(basalt, keys.enter)
        T.eq(closed, true)
        T.eq(frame:getFocused(), input, "past the closed dialog to its owner")
    end)

    -- ------------------------------------------------------------------ List

    -- 20 rows L1..L20 in a 5-row list
    local function longList(props)
        local basalt, frame = T.frame(30, 15)
        props.x, props.y, props.width, props.height = 2, 2, 10, 5
        local list = frame:addList(props)
        for i = 1, 20 do list:addItem("L" .. i) end
        basalt.update()
        list:focus()
        return basalt, list
    end

    T.test("keys scroll a list that is not selectable", function()
        local basalt, list = longList({ selectable = false })
        local selects = 0
        list:onSelect(function() selects = selects + 1 end)
        key(basalt, keys.down)
        T.eq(list.offset, 1, "down: one line")
        key(basalt, keys.down)
        T.eq(list.offset, 2)
        key(basalt, keys.up)
        T.eq(list.offset, 1, "up: one line")
        key(basalt, keys.pageDown)
        T.eq(list.offset, 6, "page down: one page")
        key(basalt, keys.pageDown)
        T.eq(list.offset, 11)
        key(basalt, keys.pageUp)
        T.eq(list.offset, 6, "page up: one page")
        key(basalt, keys["end"])
        T.eq(list.offset, 15, "end: the bottom")
        key(basalt, keys.down)
        key(basalt, keys.pageDown)
        T.eq(list.offset, 15, "clamped at the bottom")
        key(basalt, keys.home)
        T.eq(list.offset, 0, "home: the top")
        key(basalt, keys.up)
        key(basalt, keys.pageUp)
        T.eq(list.offset, 0, "clamped at the top")
        key(basalt, keys.enter)
        T.eq(list.selected, false, "nothing is selected")
        T.eq(selects, 0, "enter selects nothing")
    end)

    T.test("a selectable list keeps moving its selection", function()
        local basalt, list = longList({})
        key(basalt, keys.down)
        T.eq(list.selected, 1)
        key(basalt, keys.pageDown)
        T.eq(list.selected, 6)
        T.eq(list.offset, 1, "the selection is scrolled into view")
        key(basalt, keys["end"])
        T.eq(list.selected, 20)
        T.eq(list.offset, 15)
        key(basalt, keys.home)
        T.eq(list.selected, 1)
        T.eq(list.offset, 0)
    end)

    T.test("list keys step over separators and disabled items", function()
        local basalt, frame = T.frame(30, 15)
        local list = frame:addList({ x = 2, y = 2, width = 10, height = 5 })
        list.items = {
            { separator = true }, "A", { separator = true },
            { text = "B", disabled = true }, "C", { separator = true },
        }
        basalt.update()
        list:focus()
        key(basalt, keys.down)
        T.eq(list.selected, 2, "down from nothing: the first selectable")
        key(basalt, keys.down)
        T.eq(list.selected, 5, "down skips a separator and a disabled item")
        key(basalt, keys.down)
        T.eq(list.selected, 5, "nothing selectable below")
        key(basalt, keys.up)
        T.eq(list.selected, 2)
        key(basalt, keys.up)
        T.eq(list.selected, 2, "nothing selectable above")
        key(basalt, keys["end"])
        T.eq(list.selected, 5, "end: the last selectable")
        key(basalt, keys.home)
        T.eq(list.selected, 2, "home: the first selectable")
    end)

    T.test("a selectable list without a selectable item scrolls", function()
        local basalt, list = longList({})
        for _, item in ipairs(list.items) do item.selectable = false end
        key(basalt, keys.down)
        key(basalt, keys.pageDown)
        T.eq(list.offset, 6)
        T.eq(list.selected, false)
    end)

    T.test("list keys show a header and a footer that cannot be selected", function()
        local basalt, frame = T.frame(30, 12)
        local list = frame:addList({ x = 2, y = 2, width = 20, height = 5 })
        local items = { { text = "== Header ==", selectable = false } }
        for i = 2, 20 do items[i] = "L" .. i end
        items[21] = { text = "-- footer --", disabled = true }
        list.items = items
        basalt.update()
        list:focus()
        key(basalt, keys["end"])
        T.eq(list.selected, 20)
        T.eq(list.offset, 16, "end shows the footer")
        key(basalt, keys.home)
        T.eq(list.selected, 2)
        T.eq(list.offset, 0, "home shows the header")
        key(basalt, keys["end"])
        key(basalt, keys.home)
        key(basalt, keys.down)
        T.eq(list.selected, 3)
        key(basalt, keys.up)
        T.eq(list.selected, 2)
        list:setOffset(1) -- the header scrolled out of view
        key(basalt, keys.up)
        T.eq(list.selected, 2, "up at the first selectable item keeps it")
        T.eq(list.offset, 0, "and shows the header")
        key(basalt, keys.pageDown)
        key(basalt, keys.pageDown)
        key(basalt, keys.pageDown)
        key(basalt, keys.pageDown)
        T.eq(list.selected, 20, "page down stops at the last selectable item")
        T.eq(list.offset, 16, "and shows the footer")
        list:setOffset(15) -- the footer scrolled out of view
        key(basalt, keys.down)
        T.eq(list.selected, 20)
        T.eq(list.offset, 16, "down at the last selectable item shows the footer")
    end)

    -- ------------------------------------------------------------------ Menu

    -- File (New, Open), separator, Edit (Undo, Redo), Help at y 3
    local function menuBar(subFile)
        local basalt, frame, win = T.frame(40, 18)
        local menu = frame:addMenu({ x = 1, y = 3 })
        menu.items = {
            { text = "File", items = subFile or { "New", "Open" } },
            { separator = true },
            { text = "Edit", items = { "Undo", "Redo" } },
            "Help",
        }
        local events = {}
        menu:onSelect(function(_, index, item, parent)
            events[#events + 1] = { index = index, item = item, parent = parent }
        end)
        basalt.update()
        menu:focus()
        return basalt, frame, menu, events, win
    end

    local function openIndex(menu)
        return rawget(menu, "_openIndex")
    end

    T.test("left and right walk the menu bar past submenus and separators", function()
        local basalt, _, menu, events = menuBar()
        key(basalt, keys.right)
        T.eq(openIndex(menu), 1, "right opens File")
        T.eq(menu.height, 3)
        key(basalt, keys.right)
        T.eq(openIndex(menu), 3, "right skips the separator and opens Edit")
        key(basalt, keys.right)
        T.eq(openIndex(menu), nil, "Help has no submenu")
        T.eq(menu.selected, 4, "a plain entry is selected silently")
        T.eq(#events, 0)
        key(basalt, keys.right)
        T.eq(menu.selected, 4, "right stops at the end")
        key(basalt, keys.left)
        T.eq(openIndex(menu), 3, "left opens Edit again")
        key(basalt, keys.left)
        T.eq(openIndex(menu), 1)
        key(basalt, keys.left)
        T.eq(openIndex(menu), 1, "left stops at the start")
    end)

    T.test("up, down and enter choose an entry inside a submenu", function()
        local basalt, frame, menu, events, win = menuBar()
        key(basalt, keys.right)
        key(basalt, keys.down)
        T.eq(rawget(menu, "_subCursor"), 1, "down enters the submenu")
        T.eq(T.bg(win, 2, 4), menu.selectionBackground, "New is highlighted")
        key(basalt, keys.down)
        T.eq(T.bg(win, 2, 5), menu.selectionBackground, "Open is highlighted")
        T.eq(T.bg(win, 2, 4), menu.dropBackground)
        key(basalt, keys.down)
        T.eq(T.bg(win, 2, 4), menu.selectionBackground, "down wraps to New")
        key(basalt, keys.up)
        key(basalt, keys.enter)
        T.eq(#events, 1)
        T.eq(events[1].index, 2)
        T.eq(events[1].item, "Open")
        T.eq(events[1].parent, 1)
        T.eq(openIndex(menu), nil, "the submenu closes after the choice")
        T.eq(frame:getFocused(), menu)
        key(basalt, keys.right)
        T.eq(openIndex(menu), 3, "the bar continues from File")
    end)

    T.test("left and escape close a submenu back to its parent", function()
        local basalt, frame, menu, events, win = menuBar()
        key(basalt, keys.right)
        key(basalt, keys.right)
        key(basalt, keys.down)
        key(basalt, keys.left)
        T.eq(openIndex(menu), nil, "left closes Edit")
        T.eq(menu.height, 1)
        -- " File " is x 1-6, the separator x 8, " Edit " x 10-15
        T.eq(T.bg(win, 11, 3), menu.selectionBackground, "Edit stays highlighted")
        T.eq(T.bg(win, 2, 3), menu.background, "File is not")
        frame:setFocused(nil)
        basalt.update()
        T.eq(T.bg(win, 11, 3), menu.background, "the cursor shows only while focused")
        menu:focus()
        key(basalt, keys.right)
        T.eq(openIndex(menu), nil, "right moves on to Help")
        T.eq(menu.selected, 4)
        key(basalt, keys.left)
        T.eq(openIndex(menu), 3)
        key(basalt, keys.enter)
        T.eq(rawget(menu, "_subCursor"), 1, "enter on a parent enters its submenu")
        key(basalt, keys.right)
        T.eq(menu.selected, 4, "right inside a submenu moves to the next entry")
        key(basalt, keys.left)
        key(basalt, keys.up)
        T.eq(rawget(menu, "_subCursor"), 2, "up enters at the last entry")
        T.withEscape(function(escape)
            key(basalt, escape)
            T.eq(openIndex(menu), nil, "escape closes the submenu")
            key(basalt, keys.down)
            T.eq(openIndex(menu), 3, "down opens it again")
            key(basalt, keys.down)
            key(basalt, keys.enter)
        end)
        T.eq(events[1].item, "Redo")
        T.eq(events[1].parent, 3)
    end)

    T.test("submenu keys skip separators and disabled entries", function()
        local called
        local basalt, _, menu, events, win = menuBar({
            "A", { separator = true }, { text = "B", disabled = true },
            { text = "C", callback = function(_, item) called = item.text end },
        })
        key(basalt, keys.right)
        T.eq(T.row(win, 7):sub(1, 3), " C", "a table entry shows its text")
        key(basalt, keys.down)
        key(basalt, keys.down)
        T.eq(rawget(menu, "_subCursor"), 4, "down skips two rows")
        key(basalt, keys.down)
        T.eq(rawget(menu, "_subCursor"), 1, "and wraps")
        key(basalt, keys.up)
        key(basalt, keys.enter)
        T.eq(called, "C", "the entry's callback runs")
        T.eq(events[1].item, "C")
    end)

    T.test("the keyboard cursor walks a menu that is not selectable", function()
        local basalt, _, menu, events = menuBar()
        menu.selectable = false
        key(basalt, keys.right)
        key(basalt, keys.right)
        key(basalt, keys.right)
        T.eq(openIndex(menu), nil, "the cursor reached Help")
        T.eq(menu.selected, false, "nothing is selected")
        key(basalt, keys.left)
        T.eq(openIndex(menu), 3, "and moves back from it")
        key(basalt, keys.right)
        key(basalt, keys.enter)
        T.eq(#events, 0, "a plain entry fires nothing while not selectable, as with a click")
        menu.selectable = true
        key(basalt, keys.enter)
        T.eq(#events, 1, "enter acts on the keyboard cursor, not on a selection")
        T.eq(events[1].index, 4)
        T.eq(events[1].parent, nil)
    end)

    T.test("submenu separators and disabled entries look apart and ignore the mouse", function()
        local called
        local basalt, frame, menu, events, win = menuBar({
            "A", { separator = true },
            { text = "B", disabled = true, callback = function() called = "B" end },
            "C",
        })
        key(basalt, keys.right)
        T.eq(openIndex(menu), 1)
        -- the submenu box is x 1-3, rows y 4-7
        T.eq(T.row(win, 5):sub(1, 3), ("\140"):rep(3), "a separator is a line")
        T.eq(T.fg(win, 1, 5), menu.separatorColor)
        T.eq(T.fg(win, 2, 6), menu.separatorColor, "a disabled entry is dimmed")
        T.eq(T.fg(win, 2, 4), menu.foreground, "a plain entry is not")
        T.click(basalt, 2, 5)
        T.eq(#events, 0, "a click on the separator does nothing")
        T.eq(openIndex(menu), 1, "and keeps the submenu open")
        T.click(basalt, 2, 6)
        T.eq(called, nil, "a click on a disabled entry runs no callback")
        T.eq(#events, 0, "and fires nothing")
        T.eq(openIndex(menu), 1)
        T.click(basalt, 2, 7)
        T.eq(#events, 1, "a plain entry is still chosen by a click")
        T.eq(events[1].item, "C")
        T.eq(openIndex(menu), nil)
        T.eq(frame:getFocused(), menu)
    end)

    T.test("a held enter never chooses a menu entry", function()
        local basalt, _, menu, events = menuBar()
        key(basalt, keys.right)
        basalt.update("key", keys.enter)
        T.eq(rawget(menu, "_subCursor"), 1, "enter on File enters its submenu")
        basalt.update("key", keys.enter, true)
        basalt.update("key", keys.enter, true)
        basalt.update("key_up", keys.enter)
        T.eq(#events, 0, "the repeat of that enter does not choose New")
        T.eq(openIndex(menu), 1, "the submenu stays open")
        key(basalt, keys.enter)
        T.eq(#events, 1, "a new press chooses")
        T.eq(events[1].item, "New")
        -- the submenu closed with the choice: a repeat does not open it again
        basalt.update("key", keys.enter, true)
        T.eq(openIndex(menu), nil)
        key(basalt, keys.right)
        key(basalt, keys.right)
        basalt.update("key", keys.enter)
        T.eq(#events, 2, "enter chooses Help")
        T.eq(events[2].index, 4)
        basalt.update("key", keys.enter, true)
        basalt.update("key_up", keys.enter)
        T.eq(#events, 2, "its repeat does not choose it again")
    end)

    T.test("mouse submenus still toggle and restore the stacking order", function()
        local basalt, frame = T.frame(40, 18)
        local menu = frame:addMenu({ x = 1, y = 3, z = 5 })
        menu.items = {
            { text = "File", items = { "New" } },
            { text = "Edit", items = { "Undo" } },
        }
        basalt.update()
        T.click(basalt, 2, 3)
        T.eq(openIndex(menu), 1)
        T.click(basalt, 8, 3)
        T.eq(openIndex(menu), 2, "another entry switches the submenu")
        T.click(basalt, 8, 3)
        T.eq(openIndex(menu), nil, "the same entry closes it")
        T.eq(menu.z, 5, "the stacking order is restored")
    end)

    -- ----------------------------------------------------------- ContextMenu

    T.test("a context menu gives the focus back and ignores keys when closed", function()
        local basalt, frame, input = inputBehind()
        local cm = frame:addContextMenu()
        cm:setItems({ "Copy", { separator = true }, "Paste" })
        local picked = {}
        cm:onSelect(function(_, index) picked[#picked + 1] = index end)
        cm:openAt(5, 5)
        basalt.update()
        T.eq(frame:getFocused(), cm)
        key(basalt, keys.down)
        key(basalt, keys.down)
        key(basalt, keys.enter)
        T.eq(#picked, 1)
        T.eq(picked[1], 3, "down skips the separator")
        T.eq(cm.visible, false)
        T.eq(frame:getFocused(), input, "the focus is back")
        key(basalt, keys.enter)
        T.eq(#picked, 1, "enter does not choose from a closed menu")
        T.type(basalt, "c")
        T.eq(input.text, "abc")

        cm:openAt(5, 5)
        basalt.update()
        key(basalt, keys.enter)
        T.eq(#picked, 1, "a reopened menu starts without a highlight")
        T.withEscape(function(escape) key(basalt, escape) end)
        T.eq(cm.visible, false, "escape closes")
        T.eq(frame:getFocused(), input)
    end)

    T.test("a dialog opened from a context menu entry gives the focus back to the owner", function()
        local basalt, frame, input, dlg = inputBehind()
        local cm = frame:addContextMenu()
        cm:setItems({ "Delete", "Rename" })
        local answers = {}
        cm:onSelect(function(_, index)
            T.eq(cm.visible, false, "the menu is closed when the entry runs")
            T.eq(frame:getFocused(), input, "with the focus back on its owner")
            dlg:confirm("Q", "Delete #" .. index .. "?", function(yes)
                answers[#answers + 1] = yes
            end)
        end)

        cm:openAt(5, 5) -- chosen by key
        basalt.update()
        key(basalt, keys.down)
        key(basalt, keys.enter)
        T.eq(frame:getFocused(), dialogButton(dlg, "Yes"))
        key(basalt, keys.enter)
        T.eq(answers[1], true)
        T.eq(frame:getFocused(), input, "after a key choice")

        cm:openAt(5, 5) -- chosen by click
        basalt.update()
        local cx, cy = cm:getAbsolutePosition()
        T.click(basalt, cx + 1, cy + 1)
        T.eq(frame:getFocused(), dialogButton(dlg, "Yes"))
        key(basalt, keys.right)
        key(basalt, keys.enter)
        T.eq(answers[2], false)
        T.eq(frame:getFocused(), input, "after a click choice")
        T.type(basalt, "c")
        T.eq(input.text, "abc")
    end)

    T.test("a dialog opened while a context menu is open falls back to the owner", function()
        local basalt, frame, input, dlg = inputBehind()
        local cm = frame:addContextMenu()
        cm:setItems({ "Copy" })
        cm:openAt(5, 5)
        basalt.update()
        T.eq(frame:getFocused(), cm)
        local answer
        dlg:confirm("Q", "Sure?", function(yes) answer = yes end)
        T.eq(cm.visible, false, "the menu closed when it lost the focus")
        key(basalt, keys.enter)
        T.eq(answer, true)
        T.eq(frame:getFocused(), input, "past the hidden menu to its owner")
    end)

    T.test("a context menu entry may open the menu again", function()
        local basalt, frame, input = inputBehind()
        local cm = frame:addContextMenu()
        cm:setItems({ "More..." })
        local opened = 0
        cm:onSelect(function()
            opened = opened + 1
            if opened == 1 then cm:openAt(8, 6) end
        end)
        cm:openAt(5, 5)
        basalt.update()
        key(basalt, keys.down)
        key(basalt, keys.enter)
        T.eq(opened, 1)
        T.eq(cm.visible, true, "the openAt in the entry is kept")
        T.eq(frame:getFocused(), cm)
        T.eq(cm.x, 8)
        T.withEscape(function(escape) key(basalt, escape) end)
        T.eq(cm.visible, false)
        T.eq(frame:getFocused(), input, "the focus still goes back to the owner")
    end)
end
