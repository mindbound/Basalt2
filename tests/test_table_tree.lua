-- tests/test_table_tree.lua
-- Table and Tree: mouse/keyboard use, sorting without mutating data, and
-- the Basalt2-compatible API. Ported from the deleted 2.5 tests
-- (2062cc6:test_smoke.lua and 2062cc6:test_table_tree.lua).

return function(T)
    ------------------------------------------------------------------ Tree
    local function smallTree()
        local basalt, frame = T.frame(40, 18)
        local tree = frame:addTree({ x = 1, y = 8, width = 12, height = 4 })
        tree.nodes = {
            { text = "root", children = { { text = "child1" }, { text = "child2" } } },
            { text = "other" },
        }
        basalt.update()
        return basalt, frame, tree
    end

    T.test("a tree expands its first root like Basalt2", function()
        local _, _, tree = smallTree()
        T.eq(tree.nodes[1].expanded, true)
    end)

    T.test("the marker cell collapses and expands a node", function()
        local basalt, _, tree = smallTree()
        T.click(basalt, 1, 8)
        T.eq(tree.nodes[1].expanded, false, "collapsed")
        T.click(basalt, 1, 8)
        T.eq(tree.nodes[1].expanded, true, "expanded")
    end)

    T.test("tree selection by click and keyboard", function()
        local basalt, _, tree = smallTree()
        local selected
        tree:onSelect(function(_, node) selected = node end)
        T.click(basalt, 5, 9) -- row 2: child1
        T.ok(selected, "select event")
        T.eq(selected.text, "child1")
        T.eq(tree.selected, selected)
        basalt.update("key", keys.down)
        T.eq(tree.selected.text, "child2", "down")
        basalt.update("key", keys.left) -- leaf: jump to the parent
        T.eq(tree.selected.text, "root", "left on a leaf")
        basalt.update("key", keys.left) -- expanded parent: collapse
        T.eq(tree.nodes[1].expanded, false, "left on an expanded node")
    end)

    local function apiTree()
        local root = {
            text = "Root with a very long label",
            children = {
                { text = "Child A" },
                { text = "Child B", children = { { text = "Grandchild" } } },
            },
        }
        local _, frame = T.frame()
        local tree = frame:addTree({ x = 1, y = 8, width = 12, height = 5 })
        tree:setNodes({ root })
        return frame, tree, root
    end

    T.test("tree compat API: selection, events and toggles", function()
        local _, tree, root = apiTree()
        T.eq(root.expanded, true)
        local changes, selects, toggles = 0, 0, 0
        tree:onChange(function() changes = changes + 1 end)
        tree:onSelect(function(_, node)
            selects = selects + 1
            T.eq(node, root.children[1], "select event node")
        end)
        tree:onToggle(function() toggles = toggles + 1 end)
        tree:setSelectedNode(root.children[1])
        T.eq(tree:getSelectedNode(), root.children[1])
        T.eq(changes, 1, "setSelectedNode fires change")
        T.eq(selects, 0, "but not select")
        tree:select(root.children[1])
        T.eq(selects, 1)
        tree:collapseNode(root):expandNode(root):toggleNode(root)
        T.eq(toggles, 3)
        T.eq(root.expanded, false)
    end)

    T.test("tree compat API: expanded nodes, size and offsets", function()
        local frame, tree, root = apiTree()
        tree:setExpandedNodes({ [root] = true, [root.children[2]] = true })
        local expanded = tree:getExpandedNodes()
        T.ok(expanded[root], "root expanded")
        T.ok(expanded[root.children[2]], "Child B expanded")
        local nodeWidth, nodeHeight = tree:getNodeSize()
        T.ok(nodeWidth > tree.width, "the long label is wider than the tree")
        T.eq(nodeHeight, 4)
        tree:setHorizontalOffset(999)
        T.eq(tree.horizontalOffset, nodeWidth - tree.width, "clamped")
        frame:draw()
    end)

    T.test("tree compat API: color accessors", function()
        local frame, tree = apiTree()
        tree:setSelectedForegroundColor(colors.yellow)
            :setSelectedBackgroundColor(colors.blue)
            :setScrollBarColor(colors.white)
            :setScrollBarBackgroundColor(colors.gray)
        T.eq(tree:getSelectedForegroundColor(), colors.yellow)
        T.eq(tree:getSelectedBackgroundColor(), colors.blue)
        T.eq(tree:getScrollBarColor(), colors.white)
        T.eq(tree:getScrollBarBackgroundColor(), colors.gray)
        frame:draw()
    end)

    ----------------------------------------------------------------- Table
    -- a 24x5 table at x 14-37, y 12-16 (header on row 12)
    local function fruitTable()
        local basalt, frame = T.frame(40, 18)
        local tbl = frame:addTable({ x = 14, y = 12, width = 24, height = 5 })
        tbl.columns = { { title = "Name", width = 8 }, { title = "Qty" } }
        tbl.data = { { "Banane", 3 }, { "Apfel", 12 }, { "Citrone", 1 } }
        basalt.update()
        return basalt, frame, tbl
    end

    T.test("a table row click selects by data index", function()
        local basalt, _, tbl = fruitTable()
        local row
        tbl:onSelect(function(_, _, r) row = r end)
        T.click(basalt, 15, 14) -- display row 2: Apfel
        T.ok(row, "select event")
        T.eq(row[1], "Apfel")
        T.eq(tbl.selected, 2)
    end)

    T.test("a header click sorts the view, not the data", function()
        local basalt, _, tbl = fruitTable()
        local row
        tbl:onSelect(function(_, _, r) row = r end)
        T.click(basalt, 24, 12) -- header of column 2: sort by Qty
        T.click(basalt, 15, 13) -- display row 1: Citrone
        T.ok(row, "select event")
        T.eq(row[1], "Citrone")
        T.eq(tbl.selected, 3, "selected stays a data index")
        T.eq(tbl.data[1][1], "Banane", "sorting does not mutate data")
        basalt.update("key", keys.down) -- next in view order: Banane
        T.eq(tbl.selected, 1, "keyboard follows the view order")
    end)

    T.test("custom column sort, updateCell and removeRow", function()
        local basalt, frame = T.frame(40, 18)
        local t2 = frame:addTable({ x = 25, y = 1, width = 14, height = 5 })
        t2.columns = { { title = "N", width = 6 }, { title = "V" } }
        t2.data = { { "a", "x2" }, { "b", "x10" }, { "c", "x1" } }
        t2:setColumnSort(2, function(va, vb, asc)
            local na, nb = tonumber(va:sub(2)), tonumber(vb:sub(2))
            if asc then return na < nb end
            return na > nb
        end)
        t2:sortBy(2, true)
        local index
        t2:onSelect(function(_, i) index = i end)
        basalt.update()
        T.click(basalt, 26, 2) -- the top view row: x1 = data row 3
        T.eq(index, 3, "custom comparator")
        t2:updateCell(3, 2, "x99") -- re-sorts: x2 is first now
        basalt.update()
        T.click(basalt, 26, 2)
        T.eq(index, 1, "updateCell re-sorts")
        t2:removeRow(1)
        T.eq(#t2.data, 2)
        T.eq(t2.selected, false, "removing the selected row clears the selection")
    end)

    local function apiTable()
        local _, frame = T.frame()
        local tbl = frame:addTable({ x = 1, y = 1, width = 30, height = 6 })
        tbl:setColumns({
            "Name",
            { name = "Age", width = "30%", minWidth = 3 },
            { title = "City", width = "auto" },
        })
        return frame, tbl
    end

    T.test("table compat API: columns and rows", function()
        local _, tbl = apiTable()
        T.eq(tbl.columns[1].title, "Name")
        T.eq(tbl.columns[2].name, "Age")
        local widths = tbl:calculateColumnWidths(tbl.columns, 30)
        T.eq(#widths, 3)
        T.ok(widths[2].visibleWidth >= 3, "percent width respects minWidth")
        tbl:addRow("Alice", 30, "Vienna"):addRow({ "Bob", 25, "Berlin" })
        T.eq(#tbl:getData(), 2)
        T.eq(tbl:getRow(1)[1], "Alice")
        tbl:addColumn("Score", 6)
        T.eq(#tbl.columns, 4)
        T.eq(tbl.columns[4].title, "Score")
    end)

    T.test("table compat API: select fires change and rowSelect", function()
        local _, tbl = apiTable()
        tbl:addRow("Alice", 30, "Vienna"):addRow({ "Bob", 25, "Berlin" })
        local changes, rowSelects = 0, 0
        tbl:onChange(function(_, index, row)
            changes = changes + 1
            T.ok(index == false or row == tbl.data[index], "change arguments")
        end)
        tbl:onRowSelect(function(_, index, row)
            rowSelects = rowSelects + 1
            T.eq(row, tbl.data[index], "rowSelect arguments")
        end)
        tbl:select(2)
        T.eq(tbl:getSelectedRow(), tbl:getRow(2))
        T.eq(changes, 1)
        T.eq(rowSelects, 1)
    end)

    T.test("table compat API: formatted data and sorting", function()
        local frame, tbl = apiTable()
        tbl:setData({ { "ten", 10 }, { "two", 2 } }, {
            [2] = function(value) return value .. " years" end,
        })
        T.eq(tbl.data[1][2], "10 years", "formatter")
        tbl:setSortColumn(2):setSortDirection("asc")
        T.eq(tbl:getSortColumn(), 2)
        T.eq(tbl:getSortDirection(), "asc")
        tbl:sortByColumn(2)
        local called = false
        tbl:setColumnSortFunction(1, function(rowA, rowB, direction)
            called = direction == "asc" or direction == "desc"
            return tostring(rowA[1]) < tostring(rowB[1])
        end):sortByColumn(1)
        frame:draw()
        T.ok(called, "the row comparator ran with a direction")
    end)

    T.test("table compat API: colors, scrollbar and clearData", function()
        local _, tbl = apiTable()
        tbl:addRow("Alice", 30, "Vienna")
        tbl:select(1)
        tbl:setHeaderColor(colors.blue)
            :setSelectionColor(colors.white, colors.red)
            :setShowScrollBar(false)
        T.eq(tbl:getHeaderColor(), colors.blue)
        T.ok(not tbl:getShowScrollBar())
        tbl:clearData()
        T.eq(#tbl.data, 0)
        T.eq(tbl:getSelectedRow(), nil)
    end)
end
