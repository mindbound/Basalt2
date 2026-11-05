-- tests/test_text.lua
-- core/text: measuring and cutting in screen cells, with and without the
-- Unicode Support mod

return function(T)
    local M = assert(loadfile(T.root .. "/tests/modsim.lua", nil, _ENV))(T)

    local CAFE = "caf\195\169" -- "café" in UTF-8
    local DASH = "\226\128\148" -- em dash
    local SAMPLE = CAFE .. " " .. DASH .. " 17 \194\176C" -- "café — 17 °C"

    T.test("without the mod a cell is a byte (plain string semantics)", function()
        local text = T.loadBasalt().text
        T.eq(text.isUtf8(), false)
        T.eq(text.width(SAMPLE), #SAMPLE)
        T.eq(text.sub(SAMPLE, 2, 4), SAMPLE:sub(2, 4))
        T.eq(text.normalize("caf\233"), "caf\233")
        T.eq(text.fromInput("\233"), "\233")
        T.eq(text.offset(SAMPLE, 5), 5)
        T.eq(text.pad("ab", 4), "ab  ")
        T.eq(text.width(42), 2, "numbers are measured as strings")
    end)

    T.test("with the mod, UTF-8 characters are one cell each", function()
        local text = M.loadBasalt().text
        T.eq(text.width(SAMPLE), 12)
        T.eq(text.byteLen(SAMPLE), 16)
        T.eq(text.sub(SAMPLE, 1, 4), CAFE)
        T.eq(text.sub(SAMPLE, 6, 6), DASH)
        T.eq(text.sub(SAMPLE, -2), "\194\176C")
        T.eq(text.sub(SAMPLE, 13), "")
        T.eq(text.sub(SAMPLE, 3, 2), "")
        T.eq(text.sub(SAMPLE, 3.7, 4.2), "f\195\169", "fractions truncate like string.sub")
        T.eq(text.sub(SAMPLE, -2.5), "\194\176C")
        T.eq(text.offset(SAMPLE, 5), 6)
        T.eq(text.offset(SAMPLE, 13), 17)
        T.eq(text.offset(SAMPLE, 0), 0, "before cell 1: unchanged")
        T.eq(text.offset(SAMPLE, -1), -1)
        local cells = text.cells(SAMPLE)
        T.eq(#cells, 12)
        T.eq(cells[4], "\195\169")
    end)

    T.test("cells follow the mod's decoder rules", function()
        local text = M.loadBasalt().text
        local cases = {
            "\192\175",             -- C0 never starts a sequence: 2 cells
            "\224\128\175",         -- overlong 3-byte form: 3 cells
            "\237\160\128",         -- a surrogate: 3 cells
            "\244\144\128\128",     -- above U+10FFFF: 4 cells
            "\240\159\152\128",     -- an emoji: 1 cell
            "\226\128",             -- cut-off sequence: 2 cells
            "a\149b",               -- a lone continuation byte is one cell
        }
        for _, s in ipairs(cases) do
            T.eq(text.width(s), #M.cells(s), "cells of " .. s:gsub(".", function(c) return ("%02X "):format(c:byte()) end))
        end
    end)

    T.test("normalize keeps stray lead bytes from merging", function()
        local text = M.loadBasalt().text
        -- "\233" (é in the CC charset) followed by two continuation bytes
        -- would decode as one character; normalized it can't
        local joined = text.normalize("caf\233") .. "\149\149"
        T.eq(text.width(joined), 6)
        T.eq(#M.cells(joined), 6)
        T.eq(text.normalize("caf\233"), CAFE, "é as UTF-8")
        T.eq(text.normalize(SAMPLE), SAMPLE, "valid UTF-8 unchanged")
        T.eq(text.normalize("\176"), "\176", "a lone continuation byte stays")
    end)

    T.test("splice replaces cells without merging them", function()
        local text = M.loadBasalt().text
        T.eq(text.splice(CAFE, 4, 4, "e"), "cafe")
        T.eq(text.splice(CAFE, 5, 4, DASH), CAFE .. DASH, "insert at the end")
        T.eq(text.splice(CAFE .. DASH, 4, 4, ""), "caf" .. DASH, "delete one cell")
        local s = text.splice("ab", 2, 1, "\226")
        T.eq(text.width(s .. "\128\128"), 5, "a stray lead byte is normalized")
    end)

    T.test("input: legacy bytes become UTF-8", function()
        local text = M.loadBasalt().text
        T.eq(text.fromInput("\233"), "\195\169", "typed é")
        T.eq(text.fromInput("\176"), "\194\176", "typed °")
        T.eq(text.fromInput(DASH), DASH, "typed em dash")
        T.eq(text.fromInput("caf\233 " .. DASH), CAFE .. " " .. DASH, "pasted mix")
        T.eq(text.fromInput("\195\169"), "\195\131\194\169", "pasted 'Ã©' is two characters")
        T.eq(text.fromInput("\208\175"), "\208\175", "Cyrillic stays UTF-8")
    end)

    T.test("legacy conversion both ways", function()
        local text = M.loadBasalt().text
        T.eq(text.fromLegacy("\195\169"), "\195\131\194\169")
        T.eq(text.toLegacy(CAFE), "caf\233")
        T.eq(text.toLegacy(DASH), "?")
        T.eq(text.toLegacy("\149"), "\149")
        T.eq(text.char(233), "\195\169")
        T.eq(text.char(0x2014), DASH)
        T.eq(T.loadBasalt().text.char(0x2014), "?", "no mod: '?'")
    end)

    T.test("lower folds ASCII and, with the mod, Latin-1 letters", function()
        local text = M.loadBasalt().text
        T.eq(text.lower("CAF\195\137"), CAFE)
        T.eq(text.lower("\195\151"), "\195\151", "the multiplication sign")
        T.eq(T.loadBasalt().text.lower("ABC\201"), "abc\201")
    end)

    T.test("pad and wrap count cells", function()
        local text = M.loadBasalt().text
        T.eq(text.pad(CAFE, 6, "right"), "  " .. CAFE)
        T.eq(text.pad(SAMPLE, 3), "caf")
        local lines = text.wrap("tr\195\168s " .. CAFE .. " " .. DASH .. " ok", 6)
        T.eq(#lines, 3)
        T.eq(lines[1], "tr\195\168s")
        T.eq(lines[2], CAFE .. " " .. DASH)
        T.eq(lines[3], "ok")
        T.eq(text.wrap(DASH:rep(5), 2)[3], DASH, "long words break by cells")
    end)
end
