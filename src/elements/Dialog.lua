-- Dialog: modal message box with helpers.
--
--   local dialog = frame:addDialog()
--   dialog:alert("Info", "Saved successfully", function() ... end)
--   dialog:confirm("Delete?", "Really delete this?", function(yes) ... end)
--   dialog:prompt("Name", "Enter your name:", "Steve", function(text) ... end)
--
-- The element spans its whole parent while open and swallows every click
-- outside the box (modal). Fires "close"(result).
--
-- Keyboard: an open dialog takes the focus (the first button, or the
-- prompt's input) and keeps it while open. Left/Right move between the
-- buttons, Tab/Shift+Tab cycle through the input and buttons, Enter presses
-- the focused button (in the prompt's input it confirms) and Escape, where
-- the keys API has it, answers No/Cancel/OK. A held Enter (auto-repeat)
-- never answers, so holding the Enter that opened the dialog does not press
-- its default button. The focused button is drawn in the title colors.
-- Closing (or hiding) the dialog gives the focus back to the element that
-- had it; if that one is gone or hidden, to the element it would give the
-- focus back to (a dialog or context menu it was opened from). A dialog
-- that is hidden, or whose parent is, does not take the focus.
--
-- The title and the message are always shown as written: a "{...}" title or
-- message line is not compiled as a reactive expression, whatever
-- basalt.setReactiveStrings says.

local require = ...
local class = require("core/class")
local Container = require("core/container")
local reactive = require("core/reactive")
local textutil = require("core/text")

---@alias DialogAlertCallback fun()
---@alias DialogConfirmCallback fun(confirmed: boolean)
---@alias DialogPromptCallback fun(value: string?)
---@alias DialogButtonDefinition [string, fun()]

---@class Dialog : Container
---@field public title string Title-bar text
---@field public titleBackground number Title-bar background
---@field public titleForeground number Title-bar foreground
---@field public boxBackground number Message-box background
---@field public boxForeground number Message-box foreground
---@field public boxWidth number Maximum message-box width
---@field private _controls? Element[] Focusable controls of the open dialog, in Tab order
---@field private _presses? (fun()|false)[] Each control's button action (false for the input)
---@field private _focusIndex? integer Control that gets the focus back after a click elsewhere in the dialog
---@field private _cancel? fun() Action for the escape key
---@field private _restoreFocus? Element|false Element that had the focus before the dialog opened
---@field private _restoreTargets? Element[] Where the focus goes back on close: _restoreFocus first, then its own restore targets
local Dialog = class.create("Dialog", Container)

--- Title bar text
class.property(Dialog, "title", "")
--- Title bar background
class.property(Dialog, "titleBackground", colors.blue)
--- Title bar text color
class.property(Dialog, "titleForeground", colors.white)
--- Message box background
class.property(Dialog, "boxBackground", colors.lightGray)
--- Message box text color
class.property(Dialog, "boxForeground", colors.black)
--- Maximum width of the message box
class.property(Dialog, "boxWidth", 26)
class.property(Dialog, "background", false) -- invisible modal backdrop
-- backdrop always covers the parent
--- Width in terminal cells
class.property(Dialog, "width", function(self)
    local parent = rawget(self, "parent")
    return parent and parent.width or 1
end)
--- Height in terminal cells
class.property(Dialog, "height", function(self)
    local parent = rawget(self, "parent")
    return parent and parent.height or 1
end)

--- Fired when the dialog closes, with the result
class.event(Dialog, "close")

---@param el Element?
---@param ancestor Element
---@return boolean inside
local function isInside(el, ancestor)
    while el do
        if el == ancestor then return true end
        el = rawget(el, "parent")
    end
    return false
end

---@param self Dialog
---@return Element? focused
local function focusedElement(self)
    local root = self:getRoot()
    return root.getFocused and root:getFocused() or nil
end

--- Whether an element can take the focus back: enabled, shown and still
--- in the dialog's UI tree.
---@param el Element
---@param root Element
---@return boolean
local function canTakeFocus(el, root)
    if el.disabled then return false end
    local node = el
    while node do
        if not node.visible then return false end
        local parent = rawget(node, "parent")
        if not parent then return node == root end
        node = parent
    end
    return false
end

--- Where the focus goes back when a dialog opened now closes: the focused
--- element, then the element that one would give the focus back to (the
--- nearest _restoreFocus on it or its ancestors, as set by an open dialog
--- or context menu), and so on. Later entries are used when an earlier one
--- is gone or hidden by then (stacked dialogs closed out of order).
---@param focused Element?
---@return Element[] targets
local function restoreTargets(focused)
    local targets = {}
    local el = focused
    while el and #targets < 8 do
        targets[#targets + 1] = el
        local node, nextEl = el, nil
        while node and not nextEl do
            nextEl = rawget(node, "_restoreFocus") or nil
            node = rawget(node, "parent")
        end
        el = nextEl
    end
    return targets
end

--- The first restore target that can take the focus now.
---@param targets? Element[]
---@param root Element
---@return Element? target
local function firstFocusable(targets, root)
    if not targets then return nil end
    for _, el in ipairs(targets) do
        if canTakeFocus(el, root) then return el end
    end
    return nil
end

--- Whether the element is shown and hit by events
class.property(Dialog, "visible", false, {
    -- like Element's: hiding releases the focus, press and hover; a focus
    -- that was in the dialog goes back to the element that had it before
    -- (close() clears the restore targets first, so it does not run twice)
    onChange = function(self, visible)
        if visible then return end
        local root = self:getRoot()
        local focused = focusedElement(self)
        local inside = focused ~= nil and isInside(focused, self)
        if root._releaseSubtree then root:_releaseSubtree(self) end
        if inside then
            local target = firstFocusable(rawget(self, "_restoreTargets"), root)
            if target then target:focus() end
        end
    end,
})

--- Focuses a control of the open dialog (clamped to the control list).
--- Nothing is focused while the dialog or one of its ancestors is hidden.
---@param self Dialog
---@param index? integer
local function focusControl(self, index)
    local controls = rawget(self, "_controls")
    if not controls or #controls == 0 then return end
    index = math.max(1, math.min(#controls, index or 1))
    rawset(self, "_focusIndex", index)
    if canTakeFocus(controls[index], self:getRoot()) then
        controls[index]:focus()
    end
end

--- Focus that lands on the dialog itself or a non-control part of the box
--- (a click on the backdrop, title or padding, or dialog:focus()) moves on
--- to the current control, so the keyboard keeps working.
---@param self Dialog
local function keepFocusOnControls(self)
    focusControl(self, rawget(self, "_focusIndex"))
end

--- Initializes per-instance state and input handlers.
function Dialog:setup()
    Container.setup(self)
    self.x, self.y = 1, 1
    self.z = 950
    -- a click handler makes the (transparent) backdrop consume every click
    self:on("click", function() end)
    self:on("focus", keepFocusOnControls)
end

---@param self Dialog
local function clearChildren(self)
    local children = self:getChildren()
    for i = #children, 1, -1 do
        self:removeChild(children[i])
    end
end

--- Closes the dialog and fires its callback/close event. If the focus is
--- in the dialog, it goes back to the element that had it before (or, if
--- that one is gone or hidden, to the element it would give it back to).
---@param result? any Optional dialog result
---@return self
function Dialog:close(result)
    local targets = rawget(self, "_restoreTargets")
    local focused = focusedElement(self)
    local focusInside = focused == nil or isInside(focused, self)
    rawset(self, "_restoreFocus", nil)
    rawset(self, "_restoreTargets", nil)
    rawset(self, "_controls", nil)
    rawset(self, "_presses", nil)
    rawset(self, "_focusIndex", nil)
    rawset(self, "_cancel", nil)
    clearChildren(self)
    self.visible = false
    if focusInside then
        local root = self:getRoot()
        local target = firstFocusable(targets, root)
        if target then
            target:focus()
        elseif focused == self and root.setFocused then
            root:setFocused(nil) -- not left on a hidden dialog
        end
    end
    self:fire("close", result)
    return self
end

--- Builds the box: message + a row of buttons; returns box and content y.
---@param self Dialog
---@param title any
---@param message string
---@param extraRows? integer
---@return Frame box
---@return number contentY
local function buildBox(self, title, message, extraRows)
    -- remember the focus owner, unless the dialog is open and already has it
    local focused = focusedElement(self)
    if not isInside(focused, self) then
        rawset(self, "_restoreFocus", focused or false)
        rawset(self, "_restoreTargets", restoreTargets(focused))
    end
    clearChildren(self)
    rawset(self, "_controls", {})
    rawset(self, "_presses", {})
    rawset(self, "_focusIndex", nil)
    -- text from the caller is shown as written, never compiled
    self.title = reactive.literal(tostring(title or ""))
    self.visible = true

    local boxWidth = math.min(self.boxWidth, math.max(10, self.width - 2))
    local lines = textutil.wrap(message or "", boxWidth - 2)
    local boxHeight = 1 + 1 + #lines + (extraRows or 0) + 2 -- title/pad/btns

    local box = self:addFrame({
        x = math.max(1, math.floor((self.width - boxWidth) / 2) + 1),
        y = math.max(1, math.floor((self.height - boxHeight) / 2) + 1),
        width = boxWidth,
        height = boxHeight,
        background = self.boxBackground,
        foreground = self.boxForeground,
    })
    local function keepFocus() keepFocusOnControls(self) end
    box:on("focus", keepFocus)
    box:addLabel({
        x = 1, y = 1, width = boxWidth, height = 1,
        text = reactive.literal(self.title),
        background = self.titleBackground,
        foreground = self.titleForeground,
    }):on("focus", keepFocus)
    for i, line in ipairs(lines) do
        -- a wrapped line can look like "{...}" when the message does not
        box:addLabel({
            x = 2, y = 2 + i, text = reactive.literal(line),
            foreground = self.boxForeground,
        }):on("focus", keepFocus)
    end
    return box, 2 + #lines + 1
end

---@param self Dialog
---@return boolean down
local function shiftDown(self)
    local root = self:getRoot() --[[@as BaseFrame]] -- checked below
    return root.isKeyDown ~= nil
        and (root:isKeyDown(keys.leftShift) or root:isKeyDown(keys.rightShift))
end

--- Adds a control to the Tab order and gives it the dialog's keys.
---@param self Dialog
---@param control Element
---@param press? fun() The button's action; nil for the prompt's input
---@param accept? fun() What Enter does in the prompt's input
local function addControl(self, control, press, accept)
    local controls = rawget(self, "_controls")
    local presses = rawget(self, "_presses")
    local index = #controls + 1
    controls[index] = control
    -- false for the input, so Left/Right only move between buttons
    presses[index] = press or false

    control:on("focus", function()
        if rawget(self, "_controls") == controls then
            rawset(self, "_focusIndex", index)
        end
    end)
    control:on("key", function(_, key, held)
        -- ignore keys after this dialog closed or was replaced by another,
        -- and while it (or an ancestor) is hidden
        if rawget(self, "_controls") ~= controls
            or not canTakeFocus(control, self:getRoot()) then
            return
        end
        if key == keys.tab then
            local step = shiftDown(self) and -1 or 1
            focusControl(self, (index - 1 + step) % #controls + 1)
        elseif keys.escape and key == keys.escape then
            local cancel = rawget(self, "_cancel")
            if cancel then cancel() end
        elseif key == keys.enter then
            -- a held Enter (auto-repeat) never answers: it is still the
            -- press that opened the dialog
            local action = press or accept
            if action and not held then action() end
        elseif press and (key == keys.left or key == keys.right) then
            -- the input keeps Left/Right for its cursor
            local target = index + (key == keys.right and 1 or -1)
            if presses[target] then focusControl(self, target) end
        end
    end)
end

---@param self Dialog
---@param box Frame
---@param buttons DialogButtonDefinition[]
---@param contentY number
local function addButtons(self, box, buttons, contentY)
    local totalWidth = 0
    for _, buttonDef in ipairs(buttons) do
        totalWidth = totalWidth + textutil.width(buttonDef[1]) + 2 + 1
    end
    local x = math.max(2, math.floor((box.width - totalWidth + 1) / 2) + 1)
    for _, buttonDef in ipairs(buttons) do
        local label, onPress = buttonDef[1], buttonDef[2]
        local labelWidth = textutil.width(label)
        local button = box:addButton({
            x = x, y = contentY + 1,
            width = labelWidth + 2, height = 1,
            text = label,
        }):onClick(function()
            onPress()
        end)
        button:setStateStyle("focused", {
            background = self.titleBackground,
            foreground = self.titleForeground,
        })
        addControl(self, button, onPress)
        x = x + labelWidth + 3
    end
    -- escape answers like the last button: OK, No or Cancel
    rawset(self, "_cancel", buttons[#buttons][2])
end

--- Message + OK button; callback() runs after closing. OK gets the focus.
---@param title string The title bar text (shown as written)
---@param message string The message (word-wrapped, shown as written)
---@param callback? DialogAlertCallback Called after the dialog closes
---@return self
function Dialog:alert(title, message, callback)
    local box, contentY = buildBox(self, title, message, 0)
    addButtons(self, box, {
        { "OK", function()
            self:close(true)
            if callback then callback() end
        end },
    }, contentY)
    focusControl(self, 1)
    return self
end

--- Yes/No question; callback(true|false). Yes gets the focus.
---@param title string The title bar text (shown as written)
---@param message string The question (word-wrapped, shown as written)
---@param callback? DialogConfirmCallback Receives true (Yes) or false (No)
---@return self
function Dialog:confirm(title, message, callback)
    local box, contentY = buildBox(self, title, message, 0)
    addButtons(self, box, {
        { "Yes", function()
            self:close(true)
            if callback then callback(true) end
        end },
        { "No", function()
            self:close(false)
            if callback then callback(false) end
        end },
    }, contentY)
    focusControl(self, 1)
    return self
end

--- Text input; callback(text) on OK or Enter, callback(nil) on Cancel.
--- The input gets the focus with the cursor after the default text. The
--- default may be left out: dialog:prompt(title, message, callback).
---@param title string The title bar text (shown as written)
---@param message string The prompt text (word-wrapped, shown as written)
---@param default? string Prefilled input value
---@param callback? DialogPromptCallback Receives the entered text, or nil
---@overload fun(self: Dialog, title: string, message: string, callback?: DialogPromptCallback): Dialog
---@return self
function Dialog:prompt(title, message, default, callback)
    if callback == nil and type(default) == "function" then
        default, callback = nil, default
    end
    local box, contentY = buildBox(self, title, message, 2)
    local input = box:addInput({
        x = 2, y = contentY + 1,
        width = box.width - 2,
        text = tostring(default or ""),
    })
    -- typing continues the default instead of going in front of it
    input:_moveCursor(textutil.width(input.text) + 1)
    local function accept()
        local value = input.text
        self:close(value)
        if callback then callback(value) end
    end
    -- Enter in the input accepts through the dialog's key handler, which
    -- ignores a held Enter (the input's "enter" event cannot tell)
    addControl(self, input, nil, accept)
    addButtons(self, box, {
        { "OK", accept },
        { "Cancel", function()
            self:close(nil)
            if callback then callback(nil) end
        end },
    }, contentY + 2)
    focusControl(self, 1)
    return self
end

return Dialog
