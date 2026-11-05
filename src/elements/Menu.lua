-- Menu: horizontal menu bar with optional dropdown submenus and separators.
--
-- items entries:
--   "Save"                                       -- plain item
--   { text = "File", items = {"New", "Open"} }   -- item with submenu
--   { separator = true }                         -- vertical separator
--
-- Submenu entries are strings or tables like { text = "New", callback = fn },
-- { separator = true } (drawn as a line) or { text = "Old", disabled = true }
-- (dimmed). The mouse and the keyboard ignore separators and disabled
-- entries.
-- Fires "select"(index, item) for plain items and
-- "select"(subIndex, subText, parentIndex) for submenu entries.
-- Plain top-level entries fire select (by click or Enter) only while
-- selectable is true; submenu entries always do.
--
-- Keyboard: Left/Right move along the bar (an entry with a submenu opens
-- when reached); Down/Up/Enter go into its submenu, where Up/Down move,
-- Enter chooses, and Left (or Escape where available) closes the submenu
-- back to its parent entry; Right moves on to the next entry. Separators
-- and disabled entries are stepped over. A held Enter (auto-repeat) does
-- nothing: it never chooses an entry or opens a submenu.

local require = ...
local class = require("core/class")
local Collection = require("elements/Collection")
local textutil = require("core/text")

---@alias MenuSpan [number, number, string]

---@class MenuSubmenuBox
---@field x number Local x coordinate
---@field width number Box width
---@field items (CollectionItem|string)[]
---@field parent integer Parent item index

---@class Menu : Collection
---@field public spacing number Gap between top-level entries
---@field public separatorColor number Separator color
---@field public dropBackground number Expanded-list background
---@field private _openIndex? integer Open top-level submenu index
---@field private _zBefore? number Stacking order before expansion
---@field private _cursor? integer Top-level entry under the keyboard cursor
---@field private _subCursor? integer Highlighted submenu entry (keyboard)
local Menu = class.create("Menu", Collection)

---@param item any
---@return string label
local function labelOf(item)
    if type(item) == "table" then
        if item.separator then return "\149" end
        return tostring(item.text)
    end
    return tostring(item)
end

---@param item any
---@return boolean separator
local function isSeparator(item)
    return type(item) == "table" and item.separator == true
end

---@param item any
---@return (CollectionItem|string)[]? items
local function submenuItems(item)
    return type(item) == "table" and (item.items or item.dropdown) or nil
end

--- Display text of a submenu entry (a string or a CollectionItem table).
---@param sub any
---@return string label
local function subLabel(sub)
    if type(sub) == "table" then
        local text = sub.text
        if text == nil then text = sub.label end
        if text == nil then text = sub.value end
        return text ~= nil and tostring(text) or ""
    end
    return tostring(sub)
end

--- Whether the keyboard may stop on an entry (not a separator or disabled).
---@param item any
---@return boolean
local function reachable(item)
    if item == nil then return false end
    return type(item) ~= "table" or (item.separator ~= true and item.disabled ~= true)
end

--- Returns {x1, x2, label} per item plus the total width, in cells.
---@param self Menu
---@return MenuSpan[] spans
---@return number width
local function spans(self)
    local out = {}
    local x = 1
    for i, item in ipairs(self.items) do
        local label = isSeparator(item)
            and labelOf(item) or (" " .. labelOf(item) .. " ")
        local labelWidth = textutil.width(label)
        out[i] = { x, x + labelWidth - 1, label }
        x = x + labelWidth + self.spacing
    end
    return out, math.max(1, x - self.spacing - 1)
end

---@param self Menu
---@return MenuSubmenuBox? box
local function submenuBox(self)
    local index = rawget(self, "_openIndex")
    if not index then return nil end
    local item = self.items[index]
    local children = submenuItems(item)
    if not children then return nil end
    local itemSpans = spans(self)
    local w = 1
    for _, sub in ipairs(children) do
        w = math.max(w, textutil.width(subLabel(sub)) + 2)
    end
    local x = math.min(itemSpans[index][1], math.max(1, self.width - w + 1))
    return { x = x, width = w, items = children, parent = index }
end

--- Gap between menu entries
class.property(Menu, "spacing", 1)
--- Background color (false = transparent)
class.property(Menu, "background", colors.gray)
--- Color of separator entries
class.property(Menu, "separatorColor", colors.lightGray)
--- Background of the expanded list
class.property(Menu, "dropBackground", colors.black)
--- Width in terminal cells
class.property(Menu, "width", function(self)
    local _, total = spans(self)
    return total
end)
--- Height in terminal cells
class.property(Menu, "height", function(self)
    local box = submenuBox(self)
    return box and (1 + #box.items) or 1
end)

---@param self Menu
local function closeSubmenu(self)
    rawset(self, "_subCursor", nil)
    if rawget(self, "_openIndex") then
        rawset(self, "_openIndex", nil)
        self.z = rawget(self, "_zBefore") or self.z
        self:markDirty()
    end
end

---@param self Menu
---@param index integer
local function openSubmenu(self, index)
    -- switching from one open submenu to another keeps the original z
    if not rawget(self, "_openIndex") then rawset(self, "_zBefore", self.z) end
    rawset(self, "_openIndex", index)
    rawset(self, "_subCursor", nil)
    self.z = 999
    self:markDirty()
end

--- Runs a submenu entry like a click on it: closes the submenu, calls the
--- entry's callback and fires select(subIndex, label, parentIndex).
---@param self Menu
---@param box MenuSubmenuBox
---@param subIndex integer
local function chooseSubItem(self, box, subIndex)
    local subItem = box.items[subIndex]
    closeSubmenu(self)
    if type(subItem) == "table" and type(subItem.callback) == "function" then
        subItem.callback(self, subItem)
    end
    self:fire("select", subIndex, subLabel(subItem), box.parent)
end

--- Selects a top-level item; items with a submenu toggle it open instead.
---@param index integer The item index
---@param emit? boolean false suppresses the select event
---@return self
function Menu:select(index, emit)
    local item = self.items[index]
    if item == nil or isSeparator(item) then return self end
    rawset(self, "_cursor", nil) -- keys continue from the selection or submenu
    if submenuItems(item) then
        if rawget(self, "_openIndex") == index then
            closeSubmenu(self)
        else
            openSubmenu(self, index)
        end
        return self
    end
    closeSubmenu(self)
    Collection.select(self, index, emit)
    return self
end

--- Initializes per-instance state and input handlers.
function Menu:setup()
    Collection.setup(self)

    self:on("click", function(s, _, x, y)
        rawset(s, "_cursor", nil)
        if y == 1 then
            for i, span in ipairs(spans(s)) do
                if x >= span[1] and x <= span[2] then
                    s:select(i)
                    return
                end
            end
            closeSubmenu(s)
        else
            local box = submenuBox(s)
            if box and x >= box.x and x < box.x + box.width
                and box.items[y - 1] ~= nil then
                -- a separator or disabled entry does nothing, as in ContextMenu
                if reachable(box.items[y - 1]) then chooseSubItem(s, box, y - 1) end
            else
                closeSubmenu(s)
            end
        end
    end)
    self:on("blur", function(s) closeSubmenu(s) end)
end

--- The top-level entry the keyboard is on: the cursor, else the open
--- submenu's parent, else the selection (nil when there is none).
---@param self Menu
---@return integer? index
local function keyboardIndex(self)
    local index = rawget(self, "_cursor") or rawget(self, "_openIndex")
        or self.selected or nil
    if index and reachable(self.items[index]) then return index end
    return nil
end

--- The next entry from index in direction dir the keyboard may stop on.
---@param items any[]
---@param index integer
---@param dir integer 1 or -1
---@return integer? index
local function nextReachable(items, index, dir)
    local i = index + dir
    while items[i] ~= nil do
        if reachable(items[i]) then return i end
        i = i + dir
    end
    return nil
end

--- Moves the keyboard cursor along the bar; an entry with a submenu opens,
--- a plain entry is selected without firing select (as before).
---@param self Menu
---@param dir integer 1 or -1
local function moveAlongBar(self, dir)
    local items = self.items
    local current = keyboardIndex(self)
    local target
    if current then
        target = nextReachable(items, current, dir)
    else
        target = nextReachable(items, 0, 1) -- start at the first entry
    end
    if not target then return end
    if submenuItems(items[target]) then
        if rawget(self, "_openIndex") ~= target then openSubmenu(self, target) end
        rawset(self, "_subCursor", nil)
    else
        self:select(target, false)
    end
    rawset(self, "_cursor", target)
    self:markDirty()
end

--- Opens the submenu of an entry (when closed) and highlights its first
--- (or last) entry the keyboard may stop on.
---@param self Menu
---@param index integer
---@param fromEnd boolean
local function enterSubmenu(self, index, fromEnd)
    if rawget(self, "_openIndex") ~= index then openSubmenu(self, index) end
    local box = submenuBox(self)
    if not box then return end
    local sub = fromEnd and nextReachable(box.items, #box.items + 1, -1)
        or nextReachable(box.items, 0, 1)
    rawset(self, "_cursor", index)
    rawset(self, "_subCursor", sub)
    self:markDirty()
end

--- Moves the submenu highlight, wrapping around.
---@param self Menu
---@param box MenuSubmenuBox
---@param dir integer 1 or -1
local function moveInSubmenu(self, box, dir)
    local items, current = box.items, rawget(self, "_subCursor")
    local sub = nextReachable(items, current, dir)
        or nextReachable(items, dir > 0 and 0 or #items + 1, dir)
    rawset(self, "_subCursor", sub or current)
    self:markDirty()
end

--- Handles keyboard input while focused: Left/Right along the bar,
--- Down/Up/Enter into a submenu and through it, Enter chooses, Left or
--- Escape closes a submenu back to its parent entry. A held Enter
--- (auto-repeat) does nothing, so holding the Enter that opened a submenu
--- does not choose its first entry.
---@param event string The key event name (key, key_up, char, paste)
---@param a any Key code or typed text
---@param b? any Secondary key-event value (true for a held key)
function Menu:handleKey(event, a, b)
    -- a held (repeated) Enter neither chooses nor opens anything
    if event == "key" and #self.items > 0 and not (a == keys.enter and b) then
        local escape = keys.escape ~= nil and a == keys.escape
        local box = submenuBox(self)
        local sub = box and rawget(self, "_subCursor")
        if box and sub and box.items[sub] ~= nil then -- inside a submenu
            if a == keys.down or a == keys.up then
                moveInSubmenu(self, box, a == keys.down and 1 or -1)
            elseif a == keys.enter then
                chooseSubItem(self, box, sub)
                rawset(self, "_cursor", box.parent)
            elseif a == keys.left or escape then
                closeSubmenu(self)
                rawset(self, "_cursor", box.parent)
            elseif a == keys.right then
                moveAlongBar(self, 1)
            end
        else
            local current = keyboardIndex(self)
            if a == keys.left then
                moveAlongBar(self, -1)
            elseif a == keys.right then
                moveAlongBar(self, 1)
            elseif escape then
                closeSubmenu(self)
                rawset(self, "_cursor", current)
            elseif current and submenuItems(self.items[current])
                and (a == keys.down or a == keys.up or a == keys.enter) then
                enterSubmenu(self, current, a == keys.up)
            elseif a == keys.enter and current then
                self:select(current)
                rawset(self, "_cursor", current)
            end
        end
    end
    Collection.handleKey(self, event, a, b)
end

--- Removes all menu entries and closes any open submenu.
---@return self
function Menu:clear()
    Collection.clear(self)
    closeSubmenu(self)
    rawset(self, "_cursor", nil)
    self:markDirty()
    return self
end

--- Intrinsic size for basalt.auto().
---@return number width The measured width
---@return number height The measured height
function Menu:measure()
    local _, total = spans(self)
    return total, 1
end

--- Renders the element into the buffer.
---@param buf Render The render buffer (local coordinates, pre-clipped)
function Menu:render(buf)
    local fg, bg = self.foreground, self.background
    buf:fill(1, 1, self.width, 1, " ", fg, bg)
    local sel = self.selected
    local openIndex = rawget(self, "_openIndex")
    -- the keyboard cursor shows only while focused
    local cursor = self:hasState("focused") and rawget(self, "_cursor") or nil
    for i, span in ipairs(spans(self)) do
        local item = self.items[i]
        if isSeparator(item) then
            buf:blit(span[1], 1, span[3], self.separatorColor, bg)
        elseif i == sel or i == openIndex or i == cursor then
            buf:blit(span[1], 1, span[3],
                self.selectionForeground, self.selectionBackground)
        else
            buf:blit(span[1], 1, span[3], fg, bg)
        end
    end

    local box = submenuBox(self)
    if box then
        local highlighted = rawget(self, "_subCursor")
        for row, sub in ipairs(box.items) do
            local rowFg, rowBg = fg, self.dropBackground
            if isSeparator(sub) then
                buf:fill(box.x, 1 + row, box.width, 1, "\140",
                    self.separatorColor, rowBg)
            else
                if row == highlighted then
                    rowFg, rowBg = self.selectionForeground, self.selectionBackground
                elseif not reachable(sub) then
                    rowFg = self.separatorColor -- disabled entries are dimmed
                end
                buf:fill(box.x, 1 + row, box.width, 1, " ", rowFg, rowBg)
                buf:blit(box.x + 1, 1 + row,
                    textutil.sub(subLabel(sub), 1, box.width - 2), rowFg, rowBg)
            end
        end
    end
end

return Menu
