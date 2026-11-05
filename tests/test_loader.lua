-- tests/test_loader.lua
-- The source loader and a first frame on a hidden window

return function(T)
    T.test("the source loader returns basalt with a version", function()
        local basalt = T.loadBasalt()
        T.eq(type(basalt), "table")
        T.eq(type(basalt.VERSION), "string")
        T.eq(type(basalt.update), "function")
    end)

    T.test("every load is a separate instance", function()
        T.ok(T.loadBasalt() ~= T.loadBasalt())
    end)

    T.test("a label is drawn on a hidden window", function()
        local basalt, frame, win = T.frame(30, 5)
        frame:addLabel({ x = 2, y = 2, text = "Hello" })
        basalt.update()
        T.eq(T.row(win, 2), " Hello")
    end)
end
