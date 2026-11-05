-- tests/test_dialogs.lua
-- Dialog (confirm, modal alert) and Toast (colors, hide, auto-hide).
-- Ported from the deleted 2.5 smoke test (2062cc6:test_smoke.lua).

return function(T)
    local function findButton(dialog, text)
        local box = dialog:getChildren()[1]
        for _, child in ipairs(box:getChildren()) do
            if child.text == text then return child end
        end
    end

    T.test("a confirm dialog covers its parent and answers yes", function()
        local basalt, frame = T.frame(40, 18)
        local dlg = frame:addDialog()
        local result
        dlg:confirm("Frage", "Wirklich?", function(yes) result = yes end)
        T.eq(dlg.visible, true)
        T.eq(dlg.width, 40); T.eq(dlg.height, 18)
        basalt.update()
        local yes = T.ok(findButton(dlg, "Yes"), "yes button")
        local bx, by = yes:getAbsolutePosition()
        T.click(basalt, bx, by)
        T.eq(result, true)
        T.eq(dlg.visible, false)
    end)

    T.test("an alert is modal and closes with OK", function()
        local basalt, frame = T.frame(40, 18)
        local dlg = frame:addDialog()
        local behind = false
        frame:addButton({ x = 1, y = 17, width = 5, height = 1, text = "B" })
            :onClick(function() behind = true end)
        local closed = false
        dlg:alert("T", "msg", function() closed = true end)
        basalt.update()
        T.click(basalt, 2, 17) -- swallowed by the backdrop
        T.eq(behind, false, "the dialog is modal")
        local ok = T.ok(findButton(dlg, "OK"), "OK button")
        local bx, by = ok:getAbsolutePosition()
        T.click(basalt, bx, by)
        T.eq(dlg.visible, false)
        T.eq(closed, true, "callback")
        T.click(basalt, 2, 17)
        T.eq(behind, true, "the button is reachable again")
    end)

    T.test("a toast shows with its type colors and hides", function()
        local _, frame = T.frame(40, 18)
        local toast = frame:addToast()
        toast:success("Gespeichert")
        T.eq(toast.visible, true)
        T.eq(toast.background, colors.green)
        toast:hide()
        T.eq(toast.visible, false)
    end)

    T.test("a toast hides itself after its duration", function()
        local basalt, frame = T.frame(40, 18)
        local toast = frame:addToast()
        local hidden = 0
        toast:onHide(function() hidden = hidden + 1 end)
        toast:show("Kurz", nil, 0.2)
        T.eq(toast.visible, true)
        T.ok(T.waitFor(basalt, function() return not toast.visible end, 5),
            "auto-hide within 5 seconds")
        T.eq(hidden, 1, "hide event")
    end)
end
