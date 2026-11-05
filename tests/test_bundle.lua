-- tests/test_bundle.lua
-- Booting from src/main.lua directly and the single-file bundler
-- (tools/bundle.lua). Ported from the deleted 2.5 smoke test
-- (2062cc6:test_smoke.lua).

return function(T)
    T.test("loading main.lua directly bootstraps through init.lua", function()
        local path = T.src .. "/main.lua"
        local direct = assert(loadfile(path, nil, _ENV))("main", path)
        T.eq(type(direct), "table")
        T.eq(type(direct.run), "function")
    end)

    T.test("the bundler packs src/ into one working file", function()
        local bundler = assert(loadfile(T.root .. "/tools/bundle.lua", nil, _ENV))("--lib")
        T.eq(type(bundler.build), "function", "library mode")
        local output = T.tmpFile("bundle.lua")
        local stats = bundler.build({ root = T.root, output = output })
        T.ok(fs.exists(output), "bundle written")
        T.ok(stats.files >= 30, "files: " .. tostring(stats.files))
        T.ok(stats.bytesOut < stats.bytesIn,
            "bundle smaller than the sources: " .. stats.bytesOut .. " >= " .. stats.bytesIn)

        local bundled = assert(loadfile(output, nil, _ENV))("basalt", output)
        T.eq(type(bundled), "table")
        T.eq(type(bundled.run), "function")
        T.eq(bundled.VERSION, T.loadBasalt().VERSION, "same version")

        local win = T.window(20, 8)
        local frame = bundled.createFrame(win)
        local clicked = false
        frame:addButton({ x = 1, y = 1, width = 6, height = 1, text = "Go" })
            :onClick(function() clicked = true end)
        T.click(bundled, 2, 1)
        T.ok(clicked, "the bundled basalt handles input")
        T.contains(T.row(win, 1), "Go", "the bundled basalt renders")

        T.eq(type(bundled.use("theme").set), "function", "bundled module")
        bundled.use("bigfont") -- the heaviest module: font data survives
        T.eq(frame:addBigFont({ x = 8, y = 1, text = "B" }).width, 3)
        local label = frame:addLabel({ text = "r", x = "{parent.width - 2}" })
        T.eq(label.x, 18, "reactive expressions compile inside the bundle")
        T.cleanTmp()
    end)
end
