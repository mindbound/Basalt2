-- tests/test_utf8_media.lua
-- The media modules (bigfont, charts, image, flimg, xml) with the Unicode
-- Support mod: text is taken by cells, image text is CC-charset bytes, and
-- every row stays valid on the mod's strict terminal. Plus vanilla checks
-- where a change touches the path without the mod. The codec tests use
-- byte strings that are well-formed UTF-8, so that `#` (which the mod
-- simulation makes count characters there) would give the wrong length.

return function(T)
    local M = assert(loadfile(T.root .. "/tests/modsim.lua", nil, _ENV))(T)

    local E_UTF = "\195\169"        -- é as UTF-8
    local E_CC = "\233"             -- é as a CC-charset byte (typed/legacy)
    local A_TILDE = "\195\131"      -- Ã as UTF-8 (CC byte 195)
    local COPY = "\194\169"         -- © as UTF-8 (CC byte 169)
    local DASH = "\226\128\148"     -- em dash, not in the CC charset
    local EMOJI = "\240\159\152\128" -- U+1F600
    local DOT = "\226\151\143"      -- U+25CF black circle

    -- Every row of the frame's buffer: text cells == fg bytes == bg bytes
    local function checkRows(basalt, frame)
        local text, render = basalt.text, rawget(frame, "_render")
        for y = 1, render.height do
            T.eq(text.width(render.text[y]), render.width, "text cells in row " .. y)
            T.eq(text.byteLen(render.fg[y]), render.width, "fg bytes in row " .. y)
            T.eq(text.byteLen(render.bg[y]), render.width, "bg bytes in row " .. y)
        end
    end

    ------------------------------------------------------------------------
    -- the mod simulation's `#` (tests/modlen.lua)
    ------------------------------------------------------------------------

    T.test("the simulated mod counts # like the mod, in all of Basalt's code", function()
        local ML = M.modlen
        T.eq(ML.len(E_UTF .. DASH), 2, "well-formed UTF-8: characters")
        T.eq(ML.len(E_CC .. E_UTF), 3, "one byte that is not UTF-8: bytes")
        T.eq(ML.len(""), 0)
        T.eq(ML.len({ 1, 2, 3 }), 3, "tables as usual")
        local src, count = ML.rewrite("local s = '#' -- #\nreturn #s + #t[#t] .. #s:sub(1, 2), [[#]]")
        T.eq(src, "local s = '#' -- #\nreturn __modlen(s) + __modlen(t[__modlen(t)])"
            .. " .. __modlen(s:sub(1, 2)), [[#]]")
        T.eq(count, 4)
        T.raises(function() ML.rewrite("return #x ^ 2") end, "not supported")
        local before = ML.calls
        local basalt, frame = M.frame(10, 2)
        frame:addLabel({ x = 1, y = 1, text = "caf" .. E_UTF })
        basalt.update()
        T.ok(ML.calls > before, "Basalt's # goes through the simulation")
    end)

    ------------------------------------------------------------------------
    -- bigfont
    ------------------------------------------------------------------------

    T.test("bigfont: a UTF-8 letter uses its CC-charset glyph", function()
        local basalt, frame, t = M.frame(14, 6)
        basalt.use("bigfont")
        local utf = frame:addBigFont({ x = 1, y = 1, text = "caf" .. E_UTF })
        local legacy = frame:addBigFont({ x = 1, y = 4, text = "caf" .. E_CC })
        T.eq(utf.width, 12, "4 glyphs of 3 cells")
        T.eq(utf.height, 3)
        local w, h = utf:measure()
        T.eq(w, 12, "measured width"); T.eq(h, 3, "measured height")
        local a, b = utf:getBigText(), legacy:getBigText()
        for plane = 1, 3 do
            for row = 1, 3 do
                T.eq(a[plane][row], b[plane][row], "plane " .. plane .. " row " .. row)
            end
        end
        basalt.update()
        for row = 1, 3 do
            T.eq(M.row(t, row), M.row(t, row + 3), "screen row " .. row)
        end
        checkRows(basalt, frame)
    end)

    T.test("bigfont: characters outside the CC charset are drawn as ?", function()
        local basalt, frame, t = M.frame(10, 6)
        basalt.use("bigfont")
        local wide = frame:addBigFont({ x = 1, y = 1, text = DASH .. EMOJI })
        local marks = frame:addBigFont({ x = 1, y = 4, text = "??" })
        T.eq(wide.width, 6, "one glyph per character")
        T.eq(wide:getBigText()[1][2], marks:getBigText()[1][2])
        basalt.update()
        T.eq(M.row(t, 2), M.row(t, 5))
        checkRows(basalt, frame)
    end)

    T.test("bigfont: size 2 measures UTF-8 text by cells", function()
        local basalt, frame = M.frame(30, 19)
        basalt.use("bigfont")
        local utf = frame:addBigFont({ x = 1, y = 1, text = E_UTF .. "a", fontSize = 2 })
        local legacy = frame:addBigFont({ x = 1, y = 10, text = E_CC .. "a", fontSize = 2 })
        T.eq(utf.width, 18); T.eq(utf.height, 9)
        T.eq(utf:getBigText()[1][5], legacy:getBigText()[1][5])
        basalt.update()
        checkRows(basalt, frame)
    end)

    T.test("bigfont without the mod: bytes stay glyphs, same as the mod's cells", function()
        local basalt, frame = T.frame(30, 12)
        basalt.use("bigfont")
        local legacy = frame:addBigFont({ x = 1, y = 1, text = "caf" .. E_CC })
        local bytes = frame:addBigFont({ x = 1, y = 4, text = E_UTF })
        T.eq(legacy.width, 12)
        T.eq(bytes.width, 6, "two bytes are two glyphs without the mod")

        local modBasalt, modFrame = M.frame(30, 12)
        modBasalt.use("bigfont")
        local utf = modFrame:addBigFont({ x = 1, y = 1, text = "caf" .. E_UTF })
        for row = 1, 3 do
            T.eq(utf:getBigText()[1][row], legacy:getBigText()[1][row], "row " .. row)
        end
    end)

    ------------------------------------------------------------------------
    -- charts
    ------------------------------------------------------------------------

    T.test("graph: a UTF-8 symbol is one whole cell", function()
        local basalt, frame, t = M.frame(12, 6)
        basalt.use("charts")
        local g = frame:addGraph({ x = 1, y = 1, width = 10, height = 5, maxValue = 10 })
        g:addSeries("dot", { symbol = DOT .. "x", fg = colors.red, bg = colors.black, pointCount = 5 })
        g:addSeries("legacy", { symbol = E_CC .. "y", pointCount = 5 })
        T.eq(g:getSeries("dot").symbol, DOT, "cut to the first cell")
        T.eq(g:getSeries("legacy").symbol, E_UTF, "a CC byte is stored in drawing form")
        g:addPoint("dot", 0)
        g:addPoint("dot", 10)
        basalt.update()
        T.eq(M.row(t, 5), DOT)
        T.eq(M.row(t, 1), "  " .. DOT)
        local _, fg = t.getLine(1)
        T.eq(fg:sub(3, 3), "e", "the symbol keeps its colour")
        checkRows(basalt, frame)
    end)

    T.test("graph without the mod: the symbol is cut to one byte as before", function()
        local basalt, frame = T.frame(20, 6)
        basalt.use("charts")
        local g = frame:addGraph({ x = 1, y = 1, width = 10, height = 5 })
        g:addSeries("a", { symbol = "xyz" })
        g:addSeries("b", { symbol = DOT })
        T.eq(g:getSeries("a").symbol, "x")
        T.eq(g:getSeries("b").symbol, "\226")
    end)

    ------------------------------------------------------------------------
    -- image: BIMG
    ------------------------------------------------------------------------

    T.test("image: BIMG text is CC-charset bytes, one per cell", function()
        local basalt, frame, t = M.frame(10, 3)
        basalt.use("image")
        local img = frame:addImage({ x = 2, y = 1 })
        img.bimg = { {
            { "caf" .. E_CC, "0123", "ffff" },
            { "\195\169\149", "000", "fff" }, -- the CC bytes for "Ã", "©" and a drawing char
        } }
        T.eq(img.width, 4, "auto-size counts cells")
        T.eq(img.height, 2)
        local w, h = img:measure()
        T.eq(w, 4); T.eq(h, 2)
        basalt.update()
        T.eq(M.row(t, 1), " caf" .. E_UTF)
        T.eq(M.row(t, 2), " " .. A_TILDE .. COPY .. "\149")
        local _, fg = t.getLine(1)
        T.eq(fg:sub(2, 5), "0123", "colours stay on their cells")
        checkRows(basalt, frame)
    end)

    T.test("image: a BIMG line written in UTF-8 is drawn as it is", function()
        local basalt, frame, t = M.frame(10, 2)
        basalt.use("image")
        local img = frame:addImage({ x = 1, y = 1 })
        img.bimg = { { { "caf" .. E_UTF .. " " .. DASH, "012345", "ffffff" } } }
        T.eq(img.width, 6, "the planes give the width")
        basalt.update()
        T.eq(M.row(t, 1), "caf" .. E_UTF .. " " .. DASH)
        local _, fg = t.getLine(1)
        T.eq(fg:sub(1, 6), "012345")
        checkRows(basalt, frame)
    end)

    T.test("image: BIMG text is clipped by cells", function()
        local basalt, frame, t = M.frame(6, 2)
        basalt.use("image")
        local img = frame:addImage({ x = -1, y = 1 })
        img.bimg = { { { "\195\169\195\169", "0123", "ffff" } } } -- CC bytes: Ã©Ã©
        basalt.update()
        T.eq(M.row(t, 1), A_TILDE .. COPY)
        local _, fg = t.getLine(1)
        T.eq(fg:sub(1, 2), "23", "the visible cells keep their colours")
        checkRows(basalt, frame)
    end)

    T.test("image without the mod: BIMG text and size are unchanged", function()
        local basalt, frame, win = T.frame(10, 3)
        basalt.use("image")
        local img = frame:addImage({ x = 1, y = 1 })
        img.bimg = { { { "\195\169\149", "000", "eee" } } }
        T.eq(img.width, 3)
        basalt.update()
        T.eq(T.row(win, 1):sub(1, 3), "\195\169\149")
        T.eq(T.bg(win, 3, 1), colors.red)
    end)

    ------------------------------------------------------------------------
    -- image: FLIMG
    ------------------------------------------------------------------------

    -- A one-row cell-mode FLIMG image: text is CC-charset bytes, "\0" is
    -- transparent; every cell uses palette colours 1 (fg) and 2 (bg)
    local function cellImage(flimg, text, width)
        local row = { text, ("\1"):rep(width), ("\2"):rep(width) }
        return flimg.normalize({
            mode = "cell", width = width, height = 1,
            palette = { "#FFFFFF", "#000000" },
            layers = { {} },
            frames = { { { row } } }, -- frame -> layer rows -> row
        })
    end

    T.test("image: FLIMG cell text is CC-charset bytes and NUL stays transparent", function()
        local basalt, frame, t = M.frame(8, 2)
        local image = basalt.use("image")
        frame:addLabel({ x = 1, y = 1, text = DASH:rep(5) })
        local img = frame:addImage({ x = 1, y = 1 })
        -- CC bytes é, Ã, ©, transparent, x ("\195\169" is not one é here)
        img.bimg = cellImage(image.flimg, E_CC .. "\195\169\0x", 5)
        T.eq(img.width, 5)
        basalt.update()
        T.eq(M.row(t, 1), E_UTF .. A_TILDE .. COPY .. DASH .. "x",
            "the dash under the NUL cell shows")
        checkRows(basalt, frame)
        -- clipped at the left edge
        img.x = -1
        basalt.update()
        T.eq(M.row(t, 1), COPY .. DASH .. "x" .. DASH .. DASH)
        checkRows(basalt, frame)
    end)

    T.test("image without the mod: FLIMG cell text is drawn byte for byte", function()
        local basalt, frame, win = T.frame(8, 2)
        local image = basalt.use("image")
        frame:addLabel({ x = 1, y = 1, text = "-----" })
        local img = frame:addImage({ x = 1, y = 1 })
        img.bimg = cellImage(image.flimg, E_CC .. "\195\169\0x", 5)
        basalt.update()
        T.eq(T.row(win, 1), E_CC .. "\195\169-x")
    end)

    T.test("image: a FLIMG row that is well-formed UTF-8 is still one byte per cell", function()
        local basalt, frame, t = M.frame(8, 2)
        local image = basalt.use("image")
        local img = frame:addImage({ x = 1, y = 1 })
        -- "\195\169x" is valid UTF-8 (the mod's # gives 2), but FLIMG text
        -- is the CC bytes for Ã, © and x
        img.bimg = image.flimg.normalize({
            mode = "cell", width = 3, height = 1,
            palette = { "#CC4C4C", "#3366CC" }, layers = { {} },
            frames = { { { { "\195\169x", "\1\1\1", "\2\2\2" } } } },
        })
        T.eq(img.width, 3)
        basalt.update()
        T.eq(M.row(t, 1), A_TILDE .. COPY .. "x")
        local render = rawget(frame, "_render")
        local fg, bg = render.fg[1], render.bg[1]
        T.ok(fg:sub(1, 1) ~= fg:sub(4, 4), "the image fg differs from the frame's")
        T.ok(bg:sub(1, 1) ~= bg:sub(4, 4), "the image bg differs from the frame's")
        T.eq(fg:sub(3, 3), fg:sub(1, 1), "cell 3 has the image fg")
        T.eq(bg:sub(3, 3), bg:sub(1, 1), "cell 3 has the image bg")
        checkRows(basalt, frame)
    end)

    ------------------------------------------------------------------------
    -- flimg codec (byte lengths)
    ------------------------------------------------------------------------

    T.test("flimg: encode and decode keep high bytes and UTF-8 layer names", function()
        local flimg = M.loadBasalt().use("image").flimg
        local palette = {}
        for i = 1, 200 do palette[i] = i * 4 end
        -- palette indices 195/169 make the colour planes valid UTF-8
        local text = "\195\169\226\128\148\0"
        local fg = "\195\169\195\169\200\1"
        local bg = "\169\195\1\2\3\4"
        local source = {
            mode = "cell", width = 6, height = 2, palette = palette,
            layers = { { name = "\195\137bene" } },
            frames = { -- frame -> layer rows -> {text, fg, bg}
                { { { text, fg, bg }, { text, bg, fg } } },
                { { { "\195\169\195\169\195\169", fg, bg }, { text, bg, fg } } },
            },
        }
        local data = flimg.encode(source)
        local decoded = flimg.decode(data)
        T.eq(decoded.layers[1].name, "\195\137bene")
        local rows = decoded.frames[2].layers[1].rows
        T.eq(rows[1][1], "\195\169\195\169\195\169")
        T.eq(rows[1][2], fg); T.eq(rows[1][3], bg)
        T.eq(rows[2][1], text); T.eq(rows[2][2], bg)
        T.eq(decoded.frames[1].layers[1].rows[1][1], text)

        local path = T.tmpFile("utf8-media.flimg")
        local size = flimg.save(path, source)
        T.eq(size, fs.getSize(path), "save returns the bytes written")
        T.eq(flimg.load(path).frames[2].layers[1].rows[1][1], "\195\169\195\169\195\169")
        T.cleanTmp()
    end)

    T.test("flimg: RLE round-trips byte strings", function()
        local flimg = M.loadBasalt().use("image").flimg
        -- well-formed UTF-8: the mod's # counts 43 characters, not 89 bytes
        local raw = E_UTF:rep(40) .. DASH:rep(3)
        T.eq(M.modlen.len(raw), 43)
        local packed = flimg.rleEncode(raw)
        T.eq(flimg.rleDecode(packed, 89), raw)
        T.raises(function() flimg.rleDecode(packed, 88) end, "RLE output exceeds")
    end)

    T.test("flimg: a cell row and a sprite glyph are counted in bytes", function()
        local flimg = M.loadBasalt().use("image").flimg
        T.raises(function()
            flimg.normalize({
                mode = "cell", width = 1, height = 1, palette = { 0 }, layers = { {} },
                frames = { { { { E_UTF, "\1", "\1" } } } },
            })
        end, "planes must be byte strings of width 1")
        T.raises(function()
            flimg.fromSprite({ width = 1, height = 1,
                { { { DOT } }, { { colors.white } }, { { colors.black } } } })
        end, "invalid sprite character")
        local sprite = flimg.fromSprite({ width = 2, height = 1,
            { { E_CC .. "a" }, { "0e" }, { "ff" } } })
        T.eq(sprite.frames[1].layers[1].rows[1][1], E_CC .. "a")
        local bimg = flimg.fromBimg({ { { "\195\169", "0e", "ff" } } })
        T.eq(bimg.width, 2, "BIMG text is one byte per cell")
    end)

    ------------------------------------------------------------------------
    -- BIMG to FLIMG
    ------------------------------------------------------------------------

    local NOT_ONE_PER_CELL = "FLIMG: BIMG line text must be CC-charset bytes, one per cell"
        .. " (convert UTF-8 with basalt.text.toLegacy)"

    -- An error message without its "file:line: " position
    local function message(err)
        return (tostring(err):gsub("^[^:]*:%d+: ", ""))
    end

    T.test("BIMG to FLIMG: a UTF-8 line is converted by image.fromBimg only", function()
        local basalt, frame, t = M.frame(10, 4)
        local image = basalt.use("image")
        local bimg = { {
            { "caf" .. E_UTF .. DASH, "01234", "fffff" }, -- UTF-8: 5 cells, 9 bytes
            { "\195\169\149ab", "00000", "fffff" },        -- CC bytes: Ã © (drawing) a b
        }, secondsPerFrame = 0.5 }
        local err = T.raises(function() image.flimg.fromBimg(bimg) end)
        T.eq(message(err), NOT_ONE_PER_CELL, "flimg.fromBimg stays strict")

        local converted = image.fromBimg(bimg)
        T.eq(converted.width, 5)
        T.eq(converted.height, 2)
        T.eq(converted.frames[1].duration, 500)
        local rows = converted.frames[1].layers[1].rows
        T.eq(rows[1][1], "caf" .. E_CC .. "?", "é becomes its CC byte, the dash ?")
        T.eq(rows[2][1], "\195\169\149ab", "a line of CC bytes is kept")
        T.eq(bimg[1][1][1], "caf" .. E_UTF .. DASH, "the BIMG table is not changed")

        -- drawn like the BIMG, except the character the CC charset lacks
        frame:addImage({ x = 1, y = 1 }).bimg = bimg
        frame:addImage({ x = 1, y = 3 }).bimg = converted
        basalt.update()
        T.eq(M.row(t, 1), "caf" .. E_UTF .. DASH)
        T.eq(M.row(t, 3), "caf" .. E_UTF .. "?")
        T.eq(M.row(t, 4), M.row(t, 2))
        T.eq(M.row(t, 2), A_TILDE .. COPY .. "\149ab")
        checkRows(basalt, frame)
    end)

    T.test("BIMG to FLIMG: lines of CC bytes and broken lines are left to flimg", function()
        local image = M.loadBasalt().use("image")
        -- "\195\169" has as many bytes as its planes: two CC bytes
        local bimg = { { { "\195\169" .. E_CC, "012", "fff" } } }
        local a, b = image.fromBimg(bimg), image.flimg.fromBimg(bimg)
        T.eq(a.width, 3)
        T.eq(a.frames[1].layers[1].rows[1][1], "\195\169" .. E_CC)
        T.eq(a.frames[1].layers[1].rows[1][2], b.frames[1].layers[1].rows[1][2])
        -- planes of different lengths: the usual error
        local broken = { { { "caf" .. E_UTF, "0123", "fff" } } }
        T.eq(message(T.raises(function() image.fromBimg(broken) end)),
            "FLIMG: invalid BIMG line")
        T.raises(function() image.fromBimg("nope") end, "invalid BIMG table")
    end)

    T.test("BIMG to FLIMG without the mod: image.fromBimg is flimg.fromBimg", function()
        local image = T.loadBasalt().use("image")
        local bimg = { {
            { "caf" .. E_CC, "0123", "ffff" },
            { "\195\169\149a", "0000", "eeee" },
        }, secondsPerFrame = 0.25 }
        local a, b = image.fromBimg(bimg), image.flimg.fromBimg(bimg)
        T.eq(a.width, b.width); T.eq(a.height, b.height)
        T.eq(a.frames[1].duration, b.frames[1].duration)
        T.eq(#a.palette, #b.palette)
        for y = 1, 2 do
            for plane = 1, 3 do
                T.eq(a.frames[1].layers[1].rows[y][plane], b.frames[1].layers[1].rows[y][plane],
                    "row " .. y .. " plane " .. plane)
            end
        end
        T.eq(a.frames[1].layers[1].rows[2][1], "\195\169\149a", "bytes, as before")
        -- UTF-8 text is not one byte per cell: both reject it the same way
        local utf = { { { "caf" .. E_UTF, "0123", "ffff" } } }
        local errA = T.raises(function() image.fromBimg(utf) end)
        local errB = T.raises(function() image.flimg.fromBimg(utf) end)
        T.eq(message(errA), NOT_ONE_PER_CELL)
        T.eq(message(errB), NOT_ONE_PER_CELL)
        T.contains(tostring(errA), "test_utf8_media.lua:", "reported where it was called")
        T.contains(tostring(errB), "test_utf8_media.lua:", "reported where it was called")
        T.eq(message(T.raises(function() image.fromBimg({ { { "ab", "0", "f" } } }) end)),
            NOT_ONE_PER_CELL, "any text longer than its planes")
        T.eq(message(T.raises(function() image.fromBimg({ { { "ab", "01", "f" } } }) end)),
            "FLIMG: invalid BIMG line", "planes of different lengths")
    end)

    ------------------------------------------------------------------------
    -- xml
    ------------------------------------------------------------------------

    T.test("xml: numeric character references in text become characters", function()
        local basalt, frame, t = M.frame(20, 3)
        local xml = basalt.use("xml")
        local nodes = xml.parse("<label>caf&#233; &#x2014; &#128512; &#XE9;</label>")
        T.eq(nodes[1].text, "caf" .. E_UTF .. " " .. DASH .. " " .. EMOJI .. " " .. E_UTF)
        T.eq(xml.parse("<label>&#12ab; &#x; &amp; &#;</label>")[1].text,
            "&#12ab; &#x; &amp; &#;", "anything else is kept")
        T.eq(xml.parse([[<label text="caf&#233;"/>]])[1].attrs.text, "caf&#233;",
            "attribute values are kept as written")
        local built = xml.load(frame, "<label>&#x2014;&#233;!</label>")
        T.eq(built[1].text, DASH .. E_UTF .. "!")
        basalt.update()
        T.eq(M.row(t, 1), DASH .. E_UTF .. "!")
        checkRows(basalt, frame)
    end)

    T.test("xml without the mod: text is kept as written", function()
        local xml = T.loadBasalt().use("xml")
        T.eq(xml.parse("<label>caf&#233; &#x2014; &#xA9;</label>")[1].text,
            "caf&#233; &#x2014; &#xA9;")
        T.eq(xml.parse("<label>plain text</label>")[1].text, "plain text")
    end)
end
