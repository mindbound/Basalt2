-- tests/modlen.lua
-- The length operator of the "CC: Tweaked Unicode Support" mod, for the
-- headless tests (test code only; tests/modsim.lua loads Basalt with it).
--
-- The mod patches the Lua VM's length operator: `#s` on a string counts code
-- points when the WHOLE string is well-formed UTF-8, else bytes (all or
-- nothing); tables keep the normal length. CraftOS-PC has no mod, and Lua
-- cannot override `#` for strings, so code under test is loaded through
-- M.rewrite, which turns every `#operand` into `__modlen(operand)`, with
-- M.len in the chunk's environment as __modlen.
--
--   M.len(v)              the mod's `#v`
--   M.rewrite(src, name)  src with every length operator replaced by a call
--                         to name (default "__modlen"); also returns how
--                         many it replaced
--   M.seqLen(s, i, n)     byte length of the cell at byte i (the mod's
--                         UTF-8 decoder rules)
--   M.calls               how often M.len has run
--
-- The rewriter tokenizes Lua 5.2 source (comments, short and long strings,
-- numbers, names, operators) and keeps every byte of it apart from the
-- rewritten operators, so line numbers in errors stay the same. The operand
-- of `#` is a name, a string, `...`, a parenthesised expression, a table
-- constructor or another `#` expression, followed by any suffixes (.name,
-- [key], :name(args), (args), "string" or {table} arguments). `#x ^ y`
-- (^ binds tighter than #) raises an error instead of being rewritten wrong.

local M = { calls = 0 }

local find, sub, byte = string.find, string.sub, string.byte

-- Byte length of s (string.find is byte-based, with or without the mod)
local function byteLen(s)
    return (select(2, find(s, "$")))
end

--- Byte length of the well-formed UTF-8 sequence that starts at byte i of
--- s, else 1. The mod's decoder rules: C0, C1 and F5-FF never start a
--- sequence, no overlong forms, no surrogates, nothing above U+10FFFF.
---@param s string
---@param i integer
---@param n integer Byte length of s
---@return integer
local function seqLen(s, i, n)
    local b = byte(s, i)
    local len
    if b >= 0xC2 and b <= 0xDF then len = 2
    elseif b >= 0xE0 and b <= 0xEF then len = 3
    elseif b >= 0xF0 and b <= 0xF4 then len = 4
    else return 1 end
    if i + len - 1 > n then return 1 end
    local second = byte(s, i + 1)
    if (b == 0xE0 and second < 0xA0) or (b == 0xED and second > 0x9F)
        or (b == 0xF0 and second < 0x90) or (b == 0xF4 and second > 0x8F) then
        return 1
    end
    for j = i + 1, i + len - 1 do
        local c = byte(s, j)
        if c < 0x80 or c > 0xBF then return 1 end
    end
    return len
end
M.seqLen = seqLen

--- The mod's `#v`: a string counts its code points if all of it is
--- well-formed UTF-8, else its bytes; a table its usual length.
---@param v any
---@return integer
function M.len(v)
    M.calls = M.calls + 1
    if type(v) == "table" then return #v end
    if type(v) ~= "string" then
        error("attempt to get length of a " .. type(v) .. " value", 2)
    end
    local n, i, count = byteLen(v), 1, 0
    while i <= n do
        local k = seqLen(v, i, n)
        if k == 1 and byte(v, i) >= 0x80 then return n end
        i = i + k
        count = count + 1
    end
    return count
end

local OPS3 = { ["..."] = true }
local OPS2 = {
    [".."] = true, ["=="] = true, ["~="] = true, ["<="] = true, [">="] = true,
    ["::"] = true, ["//"] = true, [">>"] = true, ["<<"] = true,
}
local CLOSE = { ["("] = ")", ["["] = "]", ["{"] = "}" }

-- Lua source as tokens { kind, text }; kind is "trivia" (white space and
-- comments), "string", "name", "number" or "op". The texts joined give the
-- source back.
local function tokenize(src)
    local toks, i, n = {}, 1, byteLen(src)
    local function push(kind, j)
        toks[#toks + 1] = { kind = kind, text = sub(src, i, j - 1) }
        i = j
    end
    local function closeLong(level, what)
        local _, e = find(src, "]" .. level .. "]", i, true)
        if not e then error("modlen: unfinished long " .. what .. " at byte " .. i, 0) end
        return e + 1
    end
    while i <= n do
        local c = sub(src, i, i)
        if find(c, "^%s") then
            push("trivia", find(src, "[^%s]", i) or n + 1)
        elseif sub(src, i, i + 1) == "--" then
            local level = src:match("^%-%-%[(=*)%[", i)
            if level then
                push("trivia", closeLong(level, "comment"))
            else
                push("trivia", find(src, "\n", i, true) or n + 1)
            end
        elseif c == '"' or c == "'" then
            local j = i + 1
            while true do
                local d = sub(src, j, j)
                if d == "" or d == "\n" then
                    error("modlen: unfinished string at byte " .. i, 0)
                elseif d == "\\" then
                    j = j + 2
                elseif d == c then
                    break
                else
                    j = j + 1
                end
            end
            push("string", j + 1)
        elseif c == "[" and src:match("^%[=*%[", i) then
            push("string", closeLong(src:match("^%[(=*)%[", i), "string"))
        elseif find(c, "^[%a_]") then
            push("name", find(src, "[^%w_]", i) or n + 1)
        elseif find(c, "^%d") or (c == "." and find(src, "^%.%d", i)) then
            local _, e
            if src:match("^0[xX]", i) then
                _, e = find(src, "^0[xX][%x%.]*", i)
                local _, exp = find(src, "^[pP][%+%-]?%d+", e + 1)
                e = exp or e
            else
                _, e = find(src, "^[%d%.]*", i)
                local _, exp = find(src, "^[eE][%+%-]?%d+", e + 1)
                e = exp or e
            end
            push("number", e + 1)
        elseif OPS3[sub(src, i, i + 2)] then
            push("op", i + 3)
        elseif OPS2[sub(src, i, i + 1)] then
            push("op", i + 2)
        else
            push("op", i + 1)
        end
    end
    return toks
end

--- src with every length operator `#x` replaced by `name(x)`.
---@param src string Lua source
---@param name? string Function to call (default "__modlen")
---@return string source, integer count
function M.rewrite(src, name)
    name = name or "__modlen"
    local toks = tokenize(src)
    local out, count, k = {}, 0, 1

    local function emit(s) out[#out + 1] = s end
    local function isOp(tok, text) return tok and tok.kind == "op" and tok.text == text end
    local function fail(what)
        local line = 1
        for j = 1, k - 1 do
            local _, breaks = toks[j].text:gsub("\n", "")
            line = line + breaks
        end
        error("modlen: " .. what .. " (line " .. line .. ")", 0)
    end

    -- Copies trivia tokens from k on
    local function trivia()
        while toks[k] and toks[k].kind == "trivia" do
            emit(toks[k].text)
            k = k + 1
        end
    end
    -- The next token after any trivia, without moving k
    local function peek()
        local j = k
        while toks[j] and toks[j].kind == "trivia" do j = j + 1 end
        return toks[j]
    end

    local copy, group, hash

    -- Copies one token (a whole bracket group, a whole `#` expression)
    function copy()
        local tok = toks[k]
        if isOp(tok, "#") then
            hash()
        elseif tok.kind == "op" and CLOSE[tok.text] then
            group()
        else
            emit(tok.text)
            k = k + 1
        end
    end

    -- toks[k] opens a bracket: copies up to its closing bracket
    function group()
        local close = CLOSE[toks[k].text]
        emit(toks[k].text)
        k = k + 1
        while not isOp(toks[k], close) do
            if not toks[k] then fail("unbalanced brackets") end
            copy()
        end
        emit(close)
        k = k + 1
    end

    -- toks[k] is `#`: writes name(operand)
    function hash()
        count = count + 1
        emit(name .. "(")
        k = k + 1
        trivia()
        local tok = toks[k]
        if isOp(tok, "#") then
            hash()
        elseif isOp(tok, "(") or isOp(tok, "{") then
            group()
        elseif tok and (tok.kind == "name" or tok.kind == "string" or isOp(tok, "...")) then
            emit(tok.text)
            k = k + 1
        else
            fail("unsupported operand after #: " .. (tok and tok.text or "end of source"))
        end
        while true do
            local nxt = peek()
            if isOp(nxt, ".") then
                trivia()
                emit(".")
                k = k + 1
                trivia()
                if not (toks[k] and toks[k].kind == "name") then fail("a name must follow '.'") end
                emit(toks[k].text)
                k = k + 1
            elseif isOp(nxt, ":") then
                trivia()
                emit(":")
                k = k + 1
                trivia()
                if not (toks[k] and toks[k].kind == "name") then fail("a name must follow ':'") end
                emit(toks[k].text)
                k = k + 1
                trivia()
                if toks[k] and toks[k].kind == "string" then
                    emit(toks[k].text)
                    k = k + 1
                elseif isOp(toks[k], "(") or isOp(toks[k], "{") then
                    group()
                else
                    fail("arguments must follow a method name")
                end
            elseif isOp(nxt, "[") or isOp(nxt, "(") or isOp(nxt, "{") then
                trivia()
                group()
            elseif nxt and nxt.kind == "string" then
                trivia()
                emit(nxt.text)
                k = k + 1
            elseif isOp(nxt, "^") then
                fail("#x ^ y is not supported")
            else
                break
            end
        end
        emit(")")
    end

    while toks[k] do copy() end
    return table.concat(out), count
end

return M
