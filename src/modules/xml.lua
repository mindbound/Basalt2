-- XML module: build UI trees from XML markup.
--
-- ```xml
-- <frame x="2" y="2" width="20" height="8">
--     <label text="Hello" foreground="#89b4fa"/>
--     <button text="Save" onClick="save"/>
--     <label text="{parent.width}"/> <!-- reactive works -->
-- </frame>
-- ```
--
-- ```lua
-- local xml = basalt.use("xml")
-- xml.load(frame, xmlSource, { save = function(btn) ... end })
-- ```
--
-- Tag names map to `add<Name>()` on the parent (label -> addLabel), so any
-- registered element works. Attribute values are converted: numbers,
-- true/false, "#RRGGBB" -> basalt.rgb, "{...}" stays reactive, everything
-- else is a string. on* attributes bind functions from the scope table.
--
-- XML is written by the app author, like code: "{...}" attribute values
-- and text between tags are compiled as reactive expressions even when
-- basalt.setReactiveStrings(false) turned that off for assignments
-- (rawString properties such as Input.text still keep them as written).
-- Never build XML from text that comes from outside the program; assign
-- such text to the created elements instead.
--
-- With the Unicode Support mod, text between tags may use numeric
-- character references: &#233; and &#xE9; give é, &#x2014; an em dash.
-- Without the mod, text is kept as written. Attribute values are always
-- kept as written.

local require = ...
local palette = require("core/palette")
local reactive = require("core/reactive")
local textutil = require("core/text")

local xml = {}

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

--- Replaces numeric character references (&#NNN; and &#xHHHH;) with the
--- character (see textutil.char).
---@param s string
---@return string
local function decodeReferences(s)
    if not textutil.isUtf8() or not s:find("&#", 1, true) then return s end
    return (s:gsub("&#([xX]?)(%x+);", function(hex, digits)
        local code = tonumber(digits, hex ~= "" and 16 or 10)
        if not code then return nil end -- hex digits without the x: kept
        return textutil.char(code)
    end))
end

--- Parses an XML string into a tree of {tag, attrs, children, text} nodes.
---@param src string XML source
---@return table root Parsed root node
function xml.parse(src)
    local root = { tag = nil, children = {} }
    local stack = { root }
    local pos = 1

    while true do
        local lt = src:find("<", pos, true)
        if not lt then break end

        local content = trim(src:sub(pos, lt - 1))
        if content ~= "" then
            content = decodeReferences(content)
            local top = stack[#stack]
            top.text = top.text and (top.text .. " " .. content) or content
        end

        if src:sub(lt + 1, lt + 3) == "!--" then
            local close = src:find("-->", lt + 4, true)
            if not close then error("Basalt XML: unclosed comment", 2) end
            pos = close + 3
        elseif src:sub(lt + 1, lt + 1) == "/" then
            local gt = src:find(">", lt, true)
            if not gt then error("Basalt XML: malformed closing tag", 2) end
            local tagName = trim(src:sub(lt + 2, gt - 1))
            local top = stack[#stack]
            if top.tag ~= tagName then
                error("Basalt XML: unexpected </" .. tagName .. ">"
                    .. (top.tag and (", open tag is <" .. top.tag .. ">") or ""), 2)
            end
            stack[#stack] = nil
            pos = gt + 1
        else
            local gt = src:find(">", lt, true)
            if not gt then error("Basalt XML: unclosed tag", 2) end
            local inner = src:sub(lt + 1, gt - 1)
            local selfClosing = inner:sub(-1) == "/"
            if selfClosing then inner = inner:sub(1, -2) end

            local tagName = inner:match("^([%w_]+)")
            if not tagName then error("Basalt XML: malformed tag near pos " .. lt, 2) end

            local node = { tag = tagName, attrs = {}, children = {} }
            for k, _, v in inner:gmatch([=[([%w_]+)%s*=%s*(["'])(.-)%2]=]) do
                node.attrs[k] = v
            end

            local top = stack[#stack]
            top.children[#top.children + 1] = node
            if not selfClosing then
                stack[#stack + 1] = node
            end
            pos = gt + 1
        end
    end

    if #stack ~= 1 then
        error("Basalt XML: unclosed <" .. stack[#stack].tag .. ">", 2)
    end
    return root.children
end

local function convert(v)
    local n = tonumber(v)
    if n then return n end
    if v == "true" then return true end
    if v == "false" then return false end
    if v:sub(1, 1) == "#" then return palette.rgb(v) end
    return v -- includes reactive "{...}" strings
end

-- Assigns an XML value. "{...}" strings stay reactive when
-- basalt.setReactiveStrings(false) is in effect: they are compiled here,
-- for the properties whose assignment would compile them.
local function assign(el, k, v)
    if not reactive.isEnabled() and reactive.isExpression(v) then
        local prop = rawget(el, "_class").__props[k]
        if prop and not prop.rawString then
            el[k] = reactive.compile(v, el)
            return
        end
    end
    el[k] = v
end

local function build(parent, nodes, scope)
    local created = {}
    for _, node in ipairs(nodes) do
        local addName = "add" .. node.tag:sub(1, 1):upper() .. node.tag:sub(2)
        local add = parent[addName]
        if not add then
            error("Basalt XML: unknown element <" .. node.tag .. ">", 2)
        end
        local el = add(parent)

        for k, v in pairs(node.attrs) do
            if k:find("^on%u") then
                local fn = scope and scope[v]
                if type(fn) ~= "function" then
                    error("Basalt XML: scope has no handler '" .. v
                        .. "' for " .. k .. " on <" .. node.tag .. ">", 2)
                end
                el[k](el, fn)
            else
                assign(el, k, convert(v))
            end
        end

        if node.text and el.text ~= nil and node.attrs.text == nil then
            assign(el, "text", node.text)
        end
        if #node.children > 0 then
            build(el, node.children, scope)
        end
        created[#created + 1] = el
    end
    return created
end

--- Builds elements from an XML string under `parent`.
---@param parent table The container the elements are added to
---@param src string The XML markup
---@param scope? table Functions referenced by on* attributes
---@return table elements The top-level created elements
function xml.load(parent, src, scope)
    return build(parent, xml.parse(src), scope)
end

--- Like xml.load, but reads the markup from a file.
---@param parent Container Parent container
---@param path string XML file path
---@param scope? table Event/function lookup scope
---@return table elements Top-level created elements
function xml.loadFile(parent, path, scope)
    local h = fs.open(path, "r")
    if not h then error("Basalt XML: cannot open " .. path, 2) end
    local src = h.readAll()
    h.close()
    return xml.load(parent, src, scope)
end

return xml
