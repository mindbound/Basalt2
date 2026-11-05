-- tests/test_errors.lua
-- basalt.errors: structured parsing, user-frame detection, wrapping and
-- the error screen. Ported from the deleted 2.5 smoke test
-- (2062cc6:test_smoke.lua).

return function(T)
    -- Basalt's own source directory, as the loader passes it to errors.lua
    local function srcDir()
        return fs.getDir(T.src .. "/init.lua")
    end

    local function trace(dir)
        return "stack traceback:\n"
            .. "\t" .. dir .. "/core/render.lua:99: in function 'blit'\n"
            .. "\t" .. dir .. "/core/element.lua:120: in function 'render'\n"
            .. "\tstartup.lua:42: in function <startup.lua:40>\n"
            .. "\t[C]: in function 'xpcall'"
    end

    T.test("parse splits the message, site and first user frame", function()
        local em = T.loadBasalt().errors
        local dir = srcDir()
        local info = em.parse(dir .. "/core/render.lua:99: unknown color 123", trace(dir))
        T.eq(info.message, "unknown color 123")
        T.eq(info.file, dir .. "/core/render.lua")
        T.eq(info.line, 99)
        T.eq(info.userFile, "startup.lua", "the first non-Basalt frame")
        T.eq(info.userLine, 42)
        T.eq(#info.trace, 3, "the xpcall frame is filtered")
    end)

    T.test("parse keeps a message without a site", function()
        local em = T.loadBasalt().errors
        local plain = em.parse("just a message without site")
        T.eq(plain.message, "just a message without site")
        T.eq(plain.file, nil)
    end)

    T.test("wrap marks the error and keeps its text", function()
        local em = T.loadBasalt().errors
        local wrapped = em.wrap("boom", "stack traceback:")
        T.ok(wrapped.__basaltError, "marker")
        T.eq(tostring(wrapped), "boom")
    end)

    T.test("the error screen renders and returns on a key", function()
        local em = T.loadBasalt().errors
        local dir = srcDir()
        local screen = T.window()
        local previous = term.redirect(screen)
        -- queue the "any key" first so show() returns at once
        os.queueEvent("key", keys.enter)
        local ok, err = pcall(em.show, dir .. "/core/render.lua:99: unknown color value 123",
            "stack traceback:\n\t" .. dir .. "/core/render.lua:99: in function 'blit'\n"
            .. "\tstartup.lua:1: in main chunk")
        term.redirect(previous)
        T.ok(ok, tostring(err))
    end)
end
