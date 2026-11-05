-- Input: single-line text input with cursor, horizontal scrolling and
-- placeholder. Fires "change" while typing and "enter" on return.
--
-- Cursor and scroll positions are screen cells (see core/text): with the
-- "CC: Tweaked Unicode Support" mod a UTF-8 character is one cell, so text
-- is measured with text.width, cut with text.sub and edited with
-- text.splice. Typed and pasted text is converted with text.fromInput.

local require = ...
local class = require("core/class")
local Element = require("core/element")
local textutil = require("core/text")

local cellWidth, cellSub = textutil.width, textutil.sub
local normalize, splice = textutil.normalize, textutil.splice

---@class Input : Element
---@field public text string Current input value
---@field public placeholder string Placeholder shown while empty and unfocused
---@field public placeholderColor number Placeholder color
---@field public maxLength number|false Maximum length in characters, or false when unlimited
---@field public replaceChar string|false Replacement character for password input
---@field public pattern string|false Lua pattern each inserted character must match
---@field onChange fun(self: Input, fn: ElementEventHandler<Input>): Input
---@field onEnter fun(self: Input, fn: ElementEventHandler<Input>): Input
---@field package _cursor integer One-based insertion position (cell)
---@field package _scroll integer Horizontal text offset (cells)
local Input = class.create("Input", Element)

--- Current input value (rawString: typed braces stay literal text)
class.property(Input, "text", "", {
    rawString = true, -- user-typed text must never compile as reactive
    onChange = function(self, v)
        -- store the drawing form (identity without the Unicode mod), so
        -- cells never merge when the text is edited
        if type(v) == "string" then
            local stored = normalize(v)
            if stored ~= v then rawget(self, "_p").text = stored end
        end
        -- keep cursor valid when text is replaced programmatically
        local cur = rawget(self, "_cursor")
        local n = v == nil and 0 or cellWidth(v)
        if cur and cur > n + 1 then
            rawset(self, "_cursor", n + 1)
            rawset(self, "_scroll", math.max(0, n + 1 - self.width))
        end
    end,
})
class.property(Input, "placeholder", "") -- shown while empty and unfocused
--- Color of the placeholder text
class.property(Input, "placeholderColor", colors.gray)
class.property(Input, "maxLength", false) -- maximum text length in characters, false = unlimited
class.property(Input, "replaceChar", false) -- e.g. "*" for password fields
class.property(Input, "pattern", false)     -- Lua pattern each typed character must match
-- class-level defaults so themes can restyle inputs
--- Width in terminal cells
class.property(Input, "width", 12)
--- Height in terminal cells
class.property(Input, "height", 1)
--- Background color (false = transparent)
class.property(Input, "background", colors.lightGray)
--- Text color
class.property(Input, "foreground", colors.black)

--- Fired after every text edit with the new text
class.event(Input, "change")
--- Fired on the enter key with the current text
class.event(Input, "enter")

--- The current text as a string in its drawing form.
---@param self Input
---@return string
local function currentText(self)
    return normalize(self.text)
end

--- Initializes per-instance state and input handlers.
function Input:setup()
    Element.setup(self)
    rawset(self, "_cursor", 1) -- insert position in cells, 1..width(text)+1
    rawset(self, "_scroll", 0)

    self:on("click", function(s, _, x, y)
        if y ~= 1 then return end -- subclasses may be taller (ComboBox)
        s:_moveCursor(s._scroll + x)
    end)
    self:on("focus", function(s) s:markDirty() end)
    self:on("blur", function(s) s:markDirty() end)
end

--- Moves the insertion cursor and keeps it inside the visible text slice.
---@param pos number New one-based insertion position (cell)
function Input:_moveCursor(pos)
    local n = cellWidth(self.text)
    if pos < 1 then pos = 1 end
    if pos > n + 1 then pos = n + 1 end
    rawset(self, "_cursor", pos)

    -- keep the cursor inside the visible slice
    local w, scroll = self.width, self._scroll
    if pos - scroll > w then scroll = pos - w end
    if pos - scroll < 1 then scroll = pos - 1 end
    rawset(self, "_scroll", scroll)
    self:markDirty()
end

--- Inserts text at the cursor after applying pattern and length constraints.
--- The pattern is matched against each whole character (with the Unicode
--- mod a UTF-8 character is several bytes; %a, %w etc. are ASCII-only).
---@param str string Text to insert (already converted with text.fromInput)
function Input:_insert(str)
    str = normalize(str)
    local pattern = self.pattern
    if pattern then -- keep only characters matching the pattern
        local kept = {}
        for _, ch in ipairs(textutil.cells(str)) do
            if ch:match(pattern) then kept[#kept + 1] = ch end
        end
        str = table.concat(kept)
        if str == "" then return end
    end
    local value = currentText(self)
    local max = self.maxLength
    local added = cellWidth(str)
    if max and cellWidth(value) + added > max then return end
    local c = self._cursor
    self.text = splice(value, c, c - 1, str)
    self:_moveCursor(c + added)
    self:fire("change", self.text)
end

--- Handles typing, paste and editing keys while focused.
---@param event string The key event name (key, key_up, char, paste)
---@param a any Key code or typed/pasted text
---@param b? any Secondary key-event value
function Input:handleKey(event, a, b)
    if event == "char" or event == "paste" then
        if type(a) == "string" then self:_insert(textutil.fromInput(a)) end
    elseif event == "key" then
        local c = self._cursor
        if a == keys.backspace then
            if c > 1 then
                self.text = splice(currentText(self), c - 1, c - 1, "")
                self:_moveCursor(c - 1)
                self:fire("change", self.text)
            end
        elseif a == keys.delete then
            local value = currentText(self)
            if c <= cellWidth(value) then
                self.text = splice(value, c, c, "")
                self:fire("change", self.text)
            end
        elseif a == keys.left then
            self:_moveCursor(c - 1)
        elseif a == keys.right then
            self:_moveCursor(c + 1)
        elseif a == keys.home then
            self:_moveCursor(1)
        elseif a == keys["end"] then
            self:_moveCursor(cellWidth(self.text) + 1)
        elseif a == keys.enter then
            self:fire("enter", self.text)
        end
    end
    Element.handleKey(self, event, a, b)
end

--- Renders the text (or placeholder) and requests the cursor while focused.
---@param buf Render The render buffer
function Input:render(buf)
    Element.render(self, buf)
    local root = self:getRoot()
    local focused = root.getFocused and root:getFocused() == self
    local value = currentText(self)
    local w = self.width

    if value == "" and not focused then
        buf:blit(1, 1, cellSub(self.placeholder, 1, w), self.placeholderColor, nil)
    else
        local visible = cellSub(value, self._scroll + 1, self._scroll + w)
        local rc = self.replaceChar
        if rc then
            visible = cellSub(normalize(rc), 1, 1):rep(cellWidth(visible))
        end
        buf:blit(1, 1, visible, self.foreground, nil)
    end

    if focused then
        self:setCursor(self._cursor - self._scroll, 1, true, self.foreground)
    end
end

--- Intrinsic size for basalt.auto(): longest of text/placeholder x 1.
---@return number width The measured width
---@return number height The measured height
function Input:measure()
    return math.max(1, cellWidth(self.text), cellWidth(self.placeholder)), 1
end

return Input
