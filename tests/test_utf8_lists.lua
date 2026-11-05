-- tests/test_utf8_lists.lua
-- List, Dropdown, Menu, ContextMenu, Table, Tree and TabControl with the
-- Unicode Support mod: item text is measured, cut, centred and hit-tested
-- in cells, and every row stays valid on the mod's strict terminal

return function(T)
    local M = assert(loadfile(T.root .. "/tests/modsim.lua", nil, _ENV))(T)

    local CAFE = "caf\195\169"            -- "café": 4 cells, 5 bytes
    local DASH = "\226\128\148"           -- em dash: 1 cell, 3 bytes
    local EMOJI = "\240\159\152\128"      -- 1 cell, 4 bytes
    local TRI = "\226\150\182"            -- U+25B6, a triangle
    local E = "\195\169"                  -- é in UTF-8 (how "\233" is drawn)

    -- Every row of the root buffer: text cells == fg bytes == bg bytes == width
    local function checkRows(basalt, frame)
        local text, render = basalt.text, rawget(frame, "_render")
        for y = 1, render.height do
            T.eq(text.width(render.text[y]), render.width, "text cells in row " .. y)
            T.eq(text.byteLen(render.fg[y]), render.width, "fg bytes in row " .. y)
            T.eq(text.byteLen(render.bg[y]), render.width, "bg bytes in row " .. y)
        end
    end

    -- The background hex digits of cells x1..x2 of a mod-terminal row
    local function bgOf(t, y, x1, x2)
        local _, _, bg = t.getLine(y)
        return bg:sub(x1, x2)
    end

    T.test("list items are cut by cells before the scrollbar", function()
        local basalt, frame, t = M.frame(12, 4)
        local list = frame:addList({ x = 1, y = 1, width = 8, height = 3 })
        list:setItems({
            DASH .. "abcdefghij",
            CAFE .. "-" .. CAFE,
            EMOJI .. EMOJI .. "xyz",
            "\233t\233",
            "p5",
        })
        basalt.update()
        T.ok(list:getScrollInfo().show, "the scrollbar takes column 8")
        T.eq(M.row(t, 1), DASH .. "abcdef", "7 cells")
        T.eq(M.row(t, 2), CAFE .. "-ca")
        T.eq(M.row(t, 3), EMOJI .. EMOJI .. "xyz")
        T.eq(bgOf(t, 1, 8, 8), "8", "the thumb stays in column 8")
        checkRows(basalt, frame)

        list:selectItem(1) -- the selected-row path
        basalt.update()
        T.eq(M.row(t, 1), DASH .. "abcdef")
        T.eq(bgOf(t, 1, 1, 8), "bbbbbbb8", "selection fill, then the thumb")

        basalt.update("mouse_scroll", 1, 2, 2)
        basalt.update("mouse_scroll", 1, 2, 2)
        T.eq(list.offset, 2)
        T.eq(M.row(t, 2), E .. "t" .. E, "a legacy é is one cell")
        T.eq(M.row(t, 3), "p5")
        checkRows(basalt, frame)
    end)

    T.test("a list centres its empty text by cells", function()
        local basalt, frame, t = M.frame(12, 3)
        local list = frame:addList({ x = 1, y = 1, width = 10, height = 3,
            emptyText = DASH .. CAFE .. DASH })
        basalt.update()
        T.eq(M.row(t, 2), "  " .. DASH .. CAFE .. DASH, "6 cells centred in 10")
        checkRows(basalt, frame)

        list.emptyText = "\233\233"
        basalt.update()
        T.eq(M.row(t, 2), "    " .. E .. E, "2 legacy cells centred")

        list.emptyText = DASH:rep(12)
        basalt.update()
        T.eq(M.row(t, 2), DASH:rep(10), "cut to the width")
        checkRows(basalt, frame)
    end)

    T.test("list separators repeat their first cell", function()
        local basalt, frame, t = M.frame(8, 3)
        local list = frame:addList({ x = 1, y = 1, width = 6, height = 3 })
        list:setItems({
            { text = DASH .. "x", separator = true },
            { text = "\233z", separator = true },
            { text = "", separator = true },
        })
        basalt.update()
        T.eq(M.row(t, 1), DASH:rep(6))
        T.eq(M.row(t, 2), E:rep(6), "a legacy lead byte, one cell per copy")
        T.eq(M.row(t, 3), ("-"):rep(6))
        checkRows(basalt, frame)
    end)

    T.test("list icons are one cell: UTF-8 strings and character codes", function()
        local basalt, frame, t = M.frame(10, 5)
        local list = frame:addList({ x = 1, y = 1, width = 8, height = 5 })
        list:setItems({
            { text = "  file", iconChar = TRI, iconForeground = colors.red },
            { text = "  dir", iconChar = 0x25B6, iconX = 2 },
            { text = "  x", iconChar = 233 },
            { text = "  y", iconChar = 16 },
            { text = "  z" .. DASH, iconChar = EMOJI .. "zz" },
        })
        basalt.update()
        T.eq(M.row(t, 1), TRI .. " file")
        local _, fg = t.getLine(1)
        T.eq(fg:sub(1, 1), "e", "the icon has its own colour")
        T.eq(M.row(t, 2), " " .. TRI .. "dir", "a code above 255")
        T.eq(M.row(t, 3), E .. " x", "a CC-charset code above 0x9F")
        T.eq(M.row(t, 4), "\16 y")
        T.eq(M.row(t, 5), EMOJI .. " z" .. DASH, "only the first cell of the icon")
        checkRows(basalt, frame)

        list:selectItem(2) -- the selected-row icon path
        basalt.update()
        T.eq(M.row(t, 2), " " .. TRI .. "dir")
        checkRows(basalt, frame)
    end)

    T.test("a dropdown cuts its title and rows by cells", function()
        local basalt, frame, t = M.frame(12, 5)
        local dd = frame:addDropdown({ x = 1, y = 1, width = 8, dropHeight = 2 })
        dd:setItems({ "\233", DASH .. "1234567", EMOJI })
        dd.text = CAFE .. CAFE
        basalt.update()
        T.eq(M.row(t, 1), CAFE .. "ca \31", "placeholder: 6 cells, the arrow in 8")
        dd.selected = 2
        basalt.update()
        T.eq(M.row(t, 1), DASH .. "12345 \31")
        checkRows(basalt, frame)

        T.click(basalt, 1, 1)
        T.eq(dd.open, true)
        basalt.update()
        T.eq(M.row(t, 2), E)
        T.eq(M.row(t, 3), DASH .. "123456", "7 cells before the scrollbar")
        T.eq(bgOf(t, 3, 1, 7), "bbbbbbb", "the highlighted row")
        checkRows(basalt, frame)

        basalt.update("mouse_scroll", 1, 2, 3)
        basalt.update()
        T.eq(M.row(t, 3), EMOJI)
        T.click(basalt, 2, 3)
        T.eq(dd.selected, 3)
        basalt.update()
        T.eq(M.row(t, 1), EMOJI .. "      \31")
        checkRows(basalt, frame)
    end)

    T.test("a menu sizes and hit-tests its entries in cells", function()
        local basalt, frame, t = M.frame(30, 3)
        local menu = frame:addMenu({ x = 1, y = 1 })
        menu:setItems({ CAFE, DASH .. "x", EMOJI, { separator = true }, "\233t" })
        -- " café " 1-6, " —x " 8-11, " 😀 " 13-15, separator 17, " ét " 19-22
        T.eq(menu.width, 22)
        T.eq((menu:measure()), 22)
        basalt.update()
        T.eq(M.row(t, 1), " " .. CAFE .. "   " .. DASH .. "x   " .. EMOJI
            .. "  \149  " .. E .. "t")
        checkRows(basalt, frame)

        local index
        menu:onSelect(function(_, i) index = i end)
        T.click(basalt, 13, 1)
        T.eq(index, 3, "the emoji entry starts at cell 13")
        T.click(basalt, 8, 1)
        T.eq(index, 2)
        T.click(basalt, 22, 1)
        T.eq(index, 5, "the last entry ends at cell 22")
        index = nil
        T.click(basalt, 17, 1)
        T.eq(index, nil, "the separator does not select")
        basalt.update()
        checkRows(basalt, frame)
    end)

    T.test("a menu submenu is as wide as its widest label in cells", function()
        local basalt, frame, t = M.frame(24, 5)
        local menu = frame:addMenu({ x = 1, y = 1, dropBackground = colors.red })
        menu:setItems({
            { text = "File", items = { CAFE .. DASH, EMOJI .. "abcdef", "\233" } },
            "Edit", "View",
        })
        T.eq(menu.width, 20)
        local item, parent
        menu:onSelect(function(_, _, it, p) item, parent = it, p end)
        basalt.update()
        T.click(basalt, 2, 1)
        T.eq(menu.height, 4, "the submenu is open")
        basalt.update()
        -- the widest label is 7 cells, so the box is 9 cells wide
        T.eq(bgOf(t, 2, 1, 10), "eeeeeeeeef", "the box covers cells 1-9")
        T.eq(M.row(t, 2), " " .. CAFE .. DASH)
        T.eq(M.row(t, 3), " " .. EMOJI .. "abcdef")
        T.eq(M.row(t, 4), " " .. E)
        checkRows(basalt, frame)

        T.click(basalt, 10, 3) -- just right of the box
        T.eq(item, nil, "outside the box: no selection")
        T.eq(menu.height, 1, "and the submenu closes")
        T.click(basalt, 2, 1)
        T.click(basalt, 9, 3) -- the last cell of the box
        T.eq(item, EMOJI .. "abcdef")
        T.eq(parent, 1)
        basalt.update()
        checkRows(basalt, frame)
    end)

    T.test("a context menu sizes, clamps and cuts by cells", function()
        local basalt, frame, t = M.frame(20, 8)
        local cm = frame:addContextMenu()
        cm:setItems({ EMOJI .. CAFE .. DASH, "\233\233\233", { separator = true }, DASH })
        T.eq(cm.width, 8, "6 cells + 2")
        cm:openAt(18, 2)
        T.eq(cm.x, 13, "clamped by the cell width")
        basalt.update()
        T.eq(M.row(t, 2), (" "):rep(13) .. EMOJI .. CAFE .. DASH)
        T.eq(M.row(t, 3), (" "):rep(13) .. E:rep(3))
        T.eq(M.row(t, 4), (" "):rep(12) .. ("\140"):rep(8), "the separator row")
        T.eq(M.row(t, 5), (" "):rep(13) .. DASH)
        checkRows(basalt, frame)

        basalt.update("key", keys.down)
        T.eq(bgOf(t, 2, 13, 20), "bbbbbbbb", "the highlighted row")
        T.eq(M.row(t, 2), (" "):rep(13) .. EMOJI .. CAFE .. DASH)
        checkRows(basalt, frame)

        cm.width = 4
        basalt.update()
        T.eq(M.row(t, 2), (" "):rep(13) .. EMOJI .. "c", "2 cells")
        checkRows(basalt, frame)
    end)

    T.test("table columns, headers and cells are measured in cells", function()
        local basalt, frame, t = M.frame(24, 5)
        local tbl = frame:addTable({ x = 1, y = 1, width = 20, height = 4 })
        tbl.columns = { CAFE, { title = DASH .. "xyz", width = 3 }, "n" }
        T.eq(tbl.columns[1].width, 5, "a string column: title cells + 1")
        T.eq(tbl.columns[3].width, 2)
        tbl.data = {
            { EMOJI .. "abcdefgh", DASH:rep(4), "\233\233\233" },
            { "\233t", 7, 42 },
        }
        local w, h = tbl:measure()
        T.eq(w, 12)
        T.eq(h, 3)
        basalt.update()
        T.eq(M.row(t, 1), CAFE .. "  " .. DASH .. "xy n", "headers cut to their column")
        T.eq(M.row(t, 2), EMOJI .. "abcd " .. DASH:rep(3) .. " " .. E .. E)
        T.eq(M.row(t, 3), E .. "t    7   42")
        checkRows(basalt, frame)

        tbl:sortBy(2)
        basalt.update()
        T.eq(M.row(t, 1), CAFE .. "  " .. DASH .. "x\30 n", "the arrow in the last cell")
        tbl:sortBy(1)
        basalt.update()
        T.eq(M.row(t, 1), CAFE .. "\30 " .. DASH .. "xy n")
        T.eq(M.row(t, 2), E .. "t    7   42", "byte order: \\233 sorts before \\240")
        checkRows(basalt, frame)

        tbl:select(1) -- now in the second display row
        basalt.update()
        T.eq(M.row(t, 3), EMOJI .. "abcd " .. DASH:rep(3) .. " " .. E .. E)
        T.eq(bgOf(t, 3, 1, 20), ("b"):rep(20), "the selected row is filled")
        checkRows(basalt, frame)
    end)

    T.test("a tree measures, scrolls horizontally and cuts by cells", function()
        local basalt, frame, t = M.frame(10, 3)
        local tree = frame:addTree({ x = 1, y = 1, width = 6, height = 2 })
        local child = { text = EMOJI .. "leaf" .. DASH }
        tree.nodes = { { text = CAFE .. DASH .. "end", children = { child } } }
        -- "- café—end" is 10 cells, "   😀leaf—" 9
        local w, h = tree:getNodeSize()
        T.eq(w, 10)
        T.eq(h, 2)
        T.eq((tree:measure()), 11, "measure: depth + 3 + text cells")
        basalt.update()
        T.eq(M.row(t, 1), "- " .. CAFE)
        T.eq(M.row(t, 2), "   " .. EMOJI .. "le")
        checkRows(basalt, frame)

        tree:setHorizontalOffset(999)
        T.eq(tree.horizontalOffset, 4, "clamped to 10 - 6 cells")
        basalt.update()
        T.eq(M.row(t, 1), "f" .. E .. DASH .. "end")
        T.eq(M.row(t, 2), "leaf" .. DASH)
        checkRows(basalt, frame)

        tree:setHorizontalOffset(2)
        tree:select(child)
        basalt.update()
        T.eq(M.row(t, 1), CAFE .. DASH .. "e")
        T.eq(M.row(t, 2), " " .. EMOJI .. "leaf")
        T.eq(bgOf(t, 2, 1, 6), "bbbbbb", "the selected row")
        checkRows(basalt, frame)

        tree.nodes = { { text = ("\233"):rep(8) } }
        T.eq((tree:getNodeSize()), 10, "legacy bytes are one cell each")
        basalt.update()
        T.eq(M.row(t, 1), "  " .. E:rep(4))
        tree:setHorizontalOffset(999)
        basalt.update()
        T.eq(M.row(t, 1), E:rep(6))
        checkRows(basalt, frame)
    end)

    T.test("tab titles are hit-tested in cells", function()
        local basalt, frame, t = M.frame(24, 4)
        local tc = frame:addTabControl({ x = 1, y = 1, width = 20, height = 4 })
        tc:addTab(CAFE)
        tc:addTab(DASH)
        tc:addTab(EMOJI .. "x")
        tc:addTab("\233")
        -- " café " 1-6, " — " 7-9, " 😀x " 10-13, " é " 14-16
        basalt.update()
        T.eq(M.row(t, 1), " " .. CAFE .. "  " .. DASH .. "  " .. EMOJI .. "x  " .. E)
        T.eq(bgOf(t, 1, 1, 7), "bbbbbb7", "the active title is 6 cells")
        T.click(basalt, 7, 1)
        T.eq(tc.active, 2)
        T.click(basalt, 10, 1)
        T.eq(tc.active, 3)
        T.click(basalt, 16, 1)
        T.eq(tc.active, 4)
        T.click(basalt, 17, 1)
        T.eq(tc.active, 4, "past the last title")
        basalt.update()
        T.eq(bgOf(t, 1, 13, 17), "7bbb7")
        checkRows(basalt, frame)
    end)

    T.test("without the mod lists still measure and cut by bytes", function()
        local basalt, frame, win = T.frame(30, 6)
        local list = frame:addList({ x = 1, y = 1, width = 5, height = 2 })
        list:setItems({ CAFE .. "xyz", { text = "  a", iconChar = 16 } })
        local menu = frame:addMenu({ x = 1, y = 4 })
        menu:setItems({ CAFE, "x" })
        T.eq(menu.width, 11, "' caf\\195\\169 ' is 7 bytes")
        local tree = frame:addTree({ x = 10, y = 1, width = 4, height = 2 })
        tree.nodes = { { text = CAFE } }
        T.eq((tree:getNodeSize()), 7)
        tree:setHorizontalOffset(999)
        T.eq(tree.horizontalOffset, 3)
        local tc = frame:addTabControl({ x = 1, y = 5, width = 20, height = 2 })
        tc:addTab(CAFE)
        tc:addTab("x")
        local tbl = frame:addTable({ x = 16, y = 1, width = 12, height = 3 })
        tbl.columns = { CAFE }
        T.eq(tbl.columns[1].width, 6)
        basalt.update()
        T.eq(T.row(win, 1):sub(1, 5), CAFE, "5 bytes")
        T.eq(T.row(win, 2):sub(1, 1), "\16")
        T.eq(T.row(win, 1):sub(10, 13), "af\195\169", "the tree window, by bytes")
        T.click(basalt, 7, 5)
        T.eq(tc.active, 1, "' caf\\195\\169 ' covers columns 1-7")
        T.click(basalt, 8, 5)
        T.eq(tc.active, 2)
        T.eq(basalt.text.isUtf8(), false)
    end)

    T.test("without the mod a large icon code draws '?'", function()
        local basalt, frame, win = T.frame(10, 2)
        local list = frame:addList({ x = 1, y = 1, width = 6, height = 1 })
        list:setItems({ { text = "  a", iconChar = 0x25B6 } })
        basalt.update()
        T.eq(T.row(win, 1), "? a")
    end)
end
