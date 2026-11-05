-- Basalt bundler tool (not part of the framework itself).
--
-- Packs everything under src/ into one release file that behaves exactly
-- like require("Basalt"): every source file is embedded as a string and
-- compiled on first require with its own chunk name, so error tracebacks
-- still show "basalt/core/render.lua:123" instead of bundle offsets.
-- Modules are compiled with the environment the bundle was loaded with
-- (as src/init.lua does), so they see the program's globals, such as shell.
--
-- Every bundle starts with a comment header: the version, the source
-- repository and commit (when given), the elements and modules it holds,
-- and the MIT licence notice from LICENSE, which every copy must carry.
-- The host runner (tools/bundle-host.lua) records the last commit that
-- changed the bundle's inputs (src, LICENSE and this file), not HEAD, so
-- a commit that changes only other files rebuilds a byte-identical
-- bundle. A shallow clone cannot tell which commit that was; it records
-- the tree id of src instead (git rev-parse <commit>:src gives the same
-- id for every commit with the same src). See gitSource.
--
-- A bundle can hold only some elements and modules. The bundled copy of
-- main.lua is then patched: the Container.register(...) statements of the
-- elements left out are removed, and the patched copy must compile.
-- Registrations must be statements of their own (see isStatement).
-- Elements that a chosen element needs (a base class such as Collection,
-- or elements it creates, such as the Frame, Label, Button and Input of a
-- Dialog) are added and reported.
-- Modules never add elements: the build fails and names the missing ones.
-- Core files and flimg are included when a bundled file requires them.
--
-- CLI usage (from the repository root):
--   bundle                      -> writes bundle/basalt.lua, comments removed
--   bundle myout.lua            -> custom output path
--   bundle ui.lua --elements Frame,Label,Input,List,Canvas --modules none
--   bundle ui.lua --modules theme,debug   (all elements, two modules)
-- Options: --elements <list|all>  --modules <list|all|none>
--          --commit <sha>  --repo <url>   (recorded in the header)
--          --root <dir>                   (repository root)
-- With host Lua: lua tools/bundle-host.lua <same arguments> (it fills in
-- --commit and --repo from git when the root is a git checkout; a given
-- --commit or --repo wins).
--
-- Library usage (e.g. from the installer):
--   local bundler = assert(loadfile("Basalt/tools/bundle.lua"))("--lib")
--   local stats = bundler.build({ output = "basalt.lua" })
--   bundler.build({ output = "ui.lua", elements = { "Frame", "List" },
--       modules = {}, commit = "50fe11f" })

local args = { ... }

----------------------------------------------------------------------------
-- Lua-aware comment stripping (strings and long brackets stay untouched)
----------------------------------------------------------------------------

local function stripComments(code)
    local out = {}
    local i, n = 1, #code
    while i <= n do
        local j = code:find("[\"'%[%-]", i)
        if not j then
            out[#out + 1] = code:sub(i)
            break
        end
        if j > i then
            out[#out + 1] = code:sub(i, j - 1)
        end
        i = j
        local c = code:sub(i, i)
        if c == '"' or c == "'" then
            local k = i + 1
            while k <= n do
                local ch = code:sub(k, k)
                if ch == "\\" then
                    k = k + 2
                elseif ch == c then
                    break
                else
                    k = k + 1
                end
            end
            out[#out + 1] = code:sub(i, k)
            i = k + 1
        elseif c == "[" then
            local eqs = code:match("^%[(=*)%[", i)
            if eqs then
                local _, closeEnd = code:find("]" .. eqs .. "]",
                    i + 2 + #eqs, true)
                closeEnd = closeEnd or n
                out[#out + 1] = code:sub(i, closeEnd)
                i = closeEnd + 1
            else
                out[#out + 1] = c
                i = i + 1
            end
        else -- "-"
            if code:sub(i, i + 1) == "--" then
                local eqs = code:match("^%-%-%[(=*)%[", i)
                if eqs then -- block comment
                    local _, closeEnd = code:find("]" .. eqs .. "]",
                        i + 4 + #eqs, true)
                    i = (closeEnd or n) + 1
                else -- line comment: keep the newline
                    i = code:find("\n", i, true) or (n + 1)
                end
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
    end
    local result = table.concat(out)
    result = result:gsub("[ \t]+\n", "\n"):gsub("\n\n+", "\n")
    return result
end

----------------------------------------------------------------------------
-- build
----------------------------------------------------------------------------

local function defaultRoot()
    local root = shell
        and fs.getDir(fs.getDir(shell.getRunningProgram()))
        or "basalt"
    if not fs.exists(fs.combine(root, "src/main.lua")) then
        root = "basalt" -- fallback when loaded outside the repository root
    end
    return root
end

local function collect(srcDir)
    local names = { "main", "flimg" }
    for _, folder in ipairs({ "core", "elements", "modules" }) do
        local path = fs.combine(srcDir, folder)
        if fs.exists(path) then
            local entries = fs.list(path)
            table.sort(entries)
            for _, file in ipairs(entries) do
                local moduleName = file:match("^(.+)%.lua$")
                if moduleName then
                    names[#names + 1] = folder .. "/" .. moduleName
                end
            end
        end
    end
    return names
end

local function readFile(path)
    local handle = fs.open(path, "r")
    if not handle then return nil end
    local content = handle.readAll()
    handle.close()
    return content
end

local function readSource(srcDir, moduleName)
    local content = readFile(fs.combine(srcDir, moduleName .. ".lua"))
    if not content then
        error("bundle: cannot read " .. moduleName .. ".lua from " .. srcDir, 0)
    end
    return content
end

--- Picks a long-bracket level that cannot occur inside the content.
local function bracketFor(content)
    local level = 1
    while content:find("]" .. string.rep("=", level) .. "]", 1, true) do
        level = level + 1
    end
    return string.rep("=", level)
end

----------------------------------------------------------------------------
-- element and module selection
----------------------------------------------------------------------------

-- One element registration in main.lua:
--   Container.register("Name", require("elements/File"))
-- Line breaks and other whitespace, either quote style, a paren-less
-- require "elements/File" and a trailing ";" are accepted, so small
-- formatting changes keep working. Captures: quote, Name, quote, File.
local REGISTER_PATTERN = "[%a_][%w_]*%s*%.%s*register%s*%(%s*([\"'])([%w_]+)%1"
    .. "%s*,%s*require%s*%(?%s*([\"'])elements/([%w_]+)%3%s*%)?%s*%)"

-- Words that an expression must follow: a call after one of them is part
-- of a larger expression or statement.
local OPERAND_WORDS = {
    ["and"] = true, ["or"] = true, ["not"] = true, ["return"] = true,
    ["local"] = true, ["in"] = true, ["if"] = true, ["elseif"] = true,
    ["while"] = true, ["until"] = true,
}

--- Whether the call from position first to last is a statement of its
--- own. Before it: the start of the text, or only whitespace on its line
--- (after a ";" on that line, if any), and the code before it must not
--- end with a token that an expression must follow, such as "=", "(",
--- ",", ".", an operator or "return". After it: no suffix that goes on
--- with the expression (".x", ":m()", "[k]", "(...)", "{...}", a string).
--- A registration inside a larger expression (local x = C.register(...),
--- assert(C.register(...)), api.C.register(...), C.register(...).x = 1)
--- is therefore not found, and findRegistrations fails loudly: removing
--- it would break main.lua or silently change what it does.
---@param code string main.lua source without comments
---@param first integer Position of the call's first character
---@param last integer Position of its last character
---@return boolean
local function isStatement(code, first, last)
    local after = code:match("^%s*(.)", last + 1)
    if after and after:find("[%.:%[%({\"']") then
        return false
    end
    local before = code:sub(1, first - 1)
    local line = before:match(".*\n(.*)$") or before
    if line:find("%S") and not line:find(";%s*$") then
        return false
    end
    local stop = before:match(".*()%S")
    if not stop then return true end -- the start of the text
    local char = before:sub(stop, stop)
    if char:find("[%w_]") then
        return not OPERAND_WORDS[before:sub(1, stop):match("[%w_]+$")]
    end
    return char:find("[;%)%]}\"']") ~= nil
end

local function sortedKeys(set)
    local list = {}
    for key in pairs(set) do list[#list + 1] = key end
    table.sort(list)
    return list
end

--- Finds the element registrations in main.lua: the register calls that
--- are statements of their own (see isStatement). Fails when main.lua
--- requires an element anywhere else, or registers one twice: a subset
--- could otherwise silently keep or lose elements after a format change.
---@param code string main.lua source without comments (see stripComments)
---@return table[] registrations { name, file, first, last } in source order
local function findRegistrations(code)
    local found, byName = {}, {}
    local init = 1
    while true do
        local first, last, _, name, _, file = code:find(REGISTER_PATTERN, init)
        if not first then break end
        if isStatement(code, first, last) then
            -- The ";" goes with the call, unless the next statement starts
            -- with "(": then it is what keeps the two statements apart
            local _, semicolon = code:find("^[ \t]*;", last + 1)
            if semicolon and not code:find("^%s*%(", semicolon + 1) then
                last = semicolon
            end
            if byName[name] then
                error("bundle: main.lua registers the element " .. name .. " twice", 0)
            end
            byName[name] = true
            found[#found + 1] = { name = name, file = file, first = first, last = last }
        end
        init = last + 1
    end
    local requires = 0
    for _ in code:gmatch("require%s*%(?%s*[\"']elements/") do
        requires = requires + 1
    end
    if requires ~= #found then
        error(("bundle: main.lua requires %d element files, but only %d are in "
            .. "Container.register(\"Name\", require(\"elements/Name\")) statements "
            .. "the bundler can parse; update tools/bundle.lua"):format(
                requires, #found), 0)
    end
    return found
end

--- Removes the registrations of the elements not in keep from main.lua,
--- then checks that exactly the kept registrations are left and that the
--- patched source compiles.
---@param code string main.lua source without comments
---@param keep table<string, boolean> Registered element names to keep
---@return string patched The patched source
---@return string[] removed Names of the removed registrations
local function patchMain(code, keep)
    local registrations = findRegistrations(code)
    local parts, removed, pos = {}, {}, 1
    local expectedLeft = 0
    for _, reg in ipairs(registrations) do
        if keep[reg.name] then
            expectedLeft = expectedLeft + 1
        else
            parts[#parts + 1] = code:sub(pos, reg.first - 1)
            pos = reg.last + 1
            removed[#removed + 1] = reg.name
        end
    end
    parts[#parts + 1] = code:sub(pos)
    local patched = table.concat(parts):gsub("[ \t]+\n", "\n"):gsub("\n\n+", "\n")

    local left = findRegistrations(patched)
    if #left ~= expectedLeft
        or #removed ~= #registrations - expectedLeft then
        error(("bundle: patching main.lua went wrong: %d registrations, "
            .. "%d removed, %d left, %d expected left"):format(
                #registrations, #removed, #left, expectedLeft), 0)
    end
    for _, reg in ipairs(left) do
        if not keep[reg.name] then
            error("bundle: patching main.lua left the registration of "
                .. reg.name, 0)
        end
    end
    -- A backstop for registrations the pattern matches only in part, such
    -- as one with a third argument (the match ends at require's ")"). load
    -- only compiles. Line numbers in its messages count the lines of the
    -- comment-stripped copy, not those of src/main.lua.
    -- (loadstring: a host Lua 5.1, whose load takes only a function)
    local compile = loadstring or load
    local compiles, reason = compile(patched, "=main.lua")
    if not compiles then
        local _, original = compile(code, "=main.lua")
        if original then
            error("bundle: src/main.lua does not compile: " .. tostring(original), 0)
        end
        error("bundle: the patched main.lua does not compile (" .. tostring(reason)
            .. "): the bundler removed only part of a registration; "
            .. "update tools/bundle.lua", 0)
    end
    return patched, removed
end

--- What a source file needs, sorted by target: its literal require("x")
--- calls, and the registered elements it creates through Container
--- methods (box:addFrame(...) needs Frame). Methods the file defines
--- itself (Table:addRow) are not element creations.
---@param code string Source without comments
---@param registered table<string, string> Registered element name -> file
---@return table[] needs { target = module name, why = "require" or "addX" }
local function scanNeeds(code, registered)
    code = "\n" .. code
    local found = {}
    local function need(target, why)
        if not found[target] then found[target] = why end
    end
    -- require("x") and require "x"; require("modules/" .. name) is
    -- dynamic (basalt.use) and not matched
    for _, target in code:gmatch("[^%w_]require%s*%(%s*([\"'])([^\"'\n]+)%1%s*%)") do
        need(target, "require")
    end
    for _, target in code:gmatch("[^%w_]require%s*([\"'])([^\"'\n]+)%1") do
        need(target, "require")
    end
    local own = {}
    for name in code:gmatch("function%s+[%w_%.]+:add(%u[%w_]*)%s*%(") do
        own[name] = true
    end
    for name in code:gmatch("[%w_]+%.add(%u[%w_]*)%s*=%s*function") do
        own[name] = true
    end
    for name in code:gmatch(":add(%u[%w_]*)%s*[%(%{\"']") do
        if registered[name] and not own[name] then
            need("elements/" .. registered[name], "add" .. name)
        end
    end
    local needs = {}
    for _, target in ipairs(sortedKeys(found)) do
        needs[#needs + 1] = { target = target, why = found[target] }
    end
    return needs
end

-- Turns an elements or modules option into a list, or nil for all of
-- them: "all" or nil = all, "none", "" or {} = none, a string is a comma
-- separated list.
local function toList(value, what)
    if value == nil or value == "all" then return nil end
    if value == "none" then return {} end
    if type(value) == "string" then
        local list = {}
        for item in value:gmatch("[^,%s]+") do list[#list + 1] = item end
        return list
    end
    if type(value) ~= "table" then
        error("bundle: " .. what .. " must be a list, a comma-separated "
            .. "string, \"all\" or \"none\"", 0)
    end
    return value
end

--- Works out which files a bundle with the chosen elements and modules
--- holds (see the header of this file for the rules).
---@param names string[] All module names (see collect)
---@param code table<string, string> Module name -> source without comments
---@param wantElements string[]|nil Registered element names, nil = all
---@param wantModules string[]|nil Module names (modules/<name>), nil = all
---@return table selection { included, keep, added, modules, removed, main }
local function resolve(names, code, wantElements, wantModules)
    local present = {}
    for _, name in ipairs(names) do present[name] = true end

    local registered, nameOfFile = {}, {}
    local registrationNames = {}
    for _, reg in ipairs(findRegistrations(code.main)) do
        local file = "elements/" .. reg.file
        if not present[file] then
            error("bundle: main.lua registers " .. reg.name .. ", but src/"
                .. file .. ".lua does not exist", 0)
        end
        registered[reg.name] = reg.file
        nameOfFile[file] = reg.name
        registrationNames[#registrationNames + 1] = reg.name
    end
    table.sort(registrationNames)

    local needsOf = {}
    local function needs(name)
        if not needsOf[name] then
            needsOf[name] = scanNeeds(code[name], registered)
        end
        return needsOf[name]
    end

    -- the chosen elements
    local keep = {}
    if wantElements == nil then
        for _, name in ipairs(registrationNames) do keep[name] = true end
    else
        for _, name in ipairs(wantElements) do
            if not registered[name] then
                if present["elements/" .. tostring(name)] then
                    error("bundle: src/elements/" .. name .. ".lua has no "
                        .. "Container.register line in main.lua", 0)
                end
                error("bundle: unknown element '" .. tostring(name)
                    .. "'; main.lua registers: "
                    .. table.concat(registrationNames, ", "), 0)
            end
            keep[name] = true
        end
    end

    -- the chosen modules
    local moduleNames = {}
    if wantModules == nil then
        for _, name in ipairs(names) do
            local short = name:match("^modules/(.+)$")
            if short then moduleNames[#moduleNames + 1] = short end
        end
    else
        local available = {}
        for _, name in ipairs(names) do
            available[#available + 1] = name:match("^modules/(.+)$")
        end
        local seen = {}
        for _, short in ipairs(wantModules) do
            if not present["modules/" .. tostring(short)] then
                error("bundle: unknown module '" .. tostring(short)
                    .. "'; src/modules has: " .. table.concat(available, ", "), 0)
            end
            if not seen[short] then
                seen[short] = true
                moduleNames[#moduleNames + 1] = short
            end
        end
    end

    -- main and the chosen elements, plus everything they need. main's own
    -- element requires are its registrations, which follow keep.
    local included, queue, added = {}, {}, {}
    local function include(name)
        included[name] = true
        queue[#queue + 1] = name
    end
    include("main")
    for _, name in ipairs(sortedKeys(keep)) do
        include("elements/" .. registered[name])
    end
    local index = 1
    while index <= #queue do
        local from = queue[index]
        index = index + 1
        for _, dep in ipairs(needs(from)) do
            local target = dep.target
            local isElement = target:sub(1, 9) == "elements/"
            local registration = from == "main" and isElement and dep.why == "require"
            if not registration and not included[target] then
                if not present[target] then
                    error("bundle: src/" .. from .. ".lua requires " .. target
                        .. ", which is not in src/", 0)
                end
                if isElement then
                    local name = nameOfFile[target] or target:sub(10)
                    if nameOfFile[target] then keep[name] = true end
                    added[#added + 1] = { name = name, by = from, why = dep.why }
                end
                include(target)
            end
        end
    end

    -- the chosen modules and what they need; elements they need must be
    -- chosen explicitly
    local missing = {}
    for _, short in ipairs(moduleNames) do
        local lacking, seen = {}, {}
        index = #queue + 1
        if not included["modules/" .. short] then include("modules/" .. short) end
        while index <= #queue do
            local from = queue[index]
            index = index + 1
            for _, dep in ipairs(needs(from)) do
                local target = dep.target
                if not included[target] then
                    if target:sub(1, 9) == "elements/" then
                        local name = nameOfFile[target] or target:sub(10)
                        if not seen[name] then
                            seen[name] = true
                            lacking[#lacking + 1] = name
                        end
                    elseif not present[target] then
                        error("bundle: src/" .. from .. ".lua requires " .. target
                            .. ", which is not in src/", 0)
                    else
                        include(target)
                    end
                end
            end
        end
        if #lacking > 0 then
            missing[#missing + 1] = "modules/" .. short
                .. " needs elements that are not chosen: "
                .. table.concat(lacking, ", ")
        end
    end
    if #missing > 0 then
        error("bundle: " .. table.concat(missing, "; ") .. ". Choose these "
            .. "elements too, or leave the module out (--modules, for "
            .. "example --modules none).", 0)
    end

    local patched, removed = patchMain(code.main, keep)
    return {
        included = included,
        registered = registered,
        keep = keep,
        added = added,
        modules = moduleNames,
        removed = removed,
        main = patched,
    }
end

--- Checks that every file in a subset bundle finds what it needs in it:
--- the files it requires, and the registrations of the elements it
--- creates. Guards against mistakes in resolve().
local function checkClosed(bundled, code, registered, keep)
    local inBundle = {}
    for _, name in ipairs(bundled) do inBundle[name] = true end
    for _, name in ipairs(bundled) do
        for _, dep in ipairs(scanNeeds(code[name], registered)) do
            local created = dep.why ~= "require" and dep.why:sub(4)
            if not inBundle[dep.target] or (created and not keep[created]) then
                error("bundle: src/" .. name .. ".lua needs " .. dep.target
                    .. " (" .. dep.why .. "), which is not in the bundle", 0)
            end
        end
    end
end

----------------------------------------------------------------------------
-- header
----------------------------------------------------------------------------

-- Header values go into "--" comment lines: control characters (a line
-- break would end the comment) become spaces.
local function headerValue(value)
    return (tostring(value):gsub("%c", " "))
end

-- The files and folders a bundle is built from, relative to the root.
local INPUTS = "src LICENSE tools/bundle.lua"

--- Works out the Commit and Source header values of a git checkout.
--- git(command) runs "git <command>" in the root and returns the first
--- line it prints, or nil (tools/bundle-host.lua runs git; CraftOS has
--- no git, and the tests answer from a table).
--- Commit: the last commit that changed the bundle's inputs (INPUTS), not
--- HEAD, so a commit that changes only other files (the README, tests, or
--- CI's own bundle commit) rebuilds a byte-identical bundle, and CI makes
--- no new bundle commit. A shallow clone (CI checks out one commit) shows
--- every file as added by its oldest commit, so it cannot tell that commit;
--- it records the tree id of src instead, which changes only with src.
--- " (with uncommitted changes)" is added when an input differs from
--- HEAD or is untracked.
--- Source: the origin URL without credentials and ".git".
---@param git fun(command: string): string|nil Runs git in the root
---@return string|nil commit nil when git cannot tell
---@return string|nil repository nil when there is no origin
local function gitSource(git)
    local commit
    if git("rev-parse --is-shallow-repository") == "false" then
        local id = git("log -1 --format=%H -- " .. INPUTS)
        if id and id:match("^%x+$") then commit = id end
    else -- shallow, or a git without --is-shallow-repository
        local tree = git("rev-parse HEAD:src")
        if tree and tree:match("^%x+$") then
            commit = "not known (shallow clone); src tree " .. tree
        end
    end
    if commit and git("status --porcelain -- " .. INPUTS) then
        commit = commit .. " (with uncommitted changes)"
    end
    local repository = git("remote get-url origin")
    if repository then
        -- never copy credentials (https://user:token@host/...) into a file
        repository = repository:gsub("^(%a[%w+.-]*://)[^/@]*@", "%1"):gsub("%.git$", "")
    end
    return commit, repository
end

local function makeHeader(info)
    local lines = {
        ("-- Basalt %s, single-file build made by tools/bundle.lua")
            :format(headerValue(info.version)),
        "-- Source: " .. (info.repository and headerValue(info.repository)
            or "not recorded (pass --repo)"),
        "-- Commit: " .. (info.commit and headerValue(info.commit)
            or "not recorded (pass --commit)"),
        "-- Elements: " .. (#info.elements > 0
            and table.concat(info.elements, ", ") or "none"),
    }
    if #info.added > 0 then
        local parts = {}
        for _, entry in ipairs(info.added) do
            parts[#parts + 1] = entry.name .. " (" .. (entry.by:gsub("^elements/", ""))
                .. ", " .. entry.why .. ")"
        end
        lines[#lines + 1] = "-- Added as dependencies: " .. table.concat(parts, ", ")
    end
    lines[#lines + 1] = "-- Modules: " .. (#info.modules > 0
        and table.concat(info.modules, ", ") or "none")
    lines[#lines + 1] = "--"
    local license = info.license:gsub("\r", ""):gsub("%s+$", "")
    for line in (license .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line == "" and "--" or ("-- " .. line)
    end
    return table.concat(lines, "\n") .. "\n"
end

--- Builds a single-file bundle.
--- options: root, output, elements, modules, commit, repository, license.
--- elements: registered element names (a list or "A,B"); "all" or nil =
--- all. modules: names under src/modules; "all" or nil = all, "none" or
--- {} = none. commit, repository: recorded in the header. license: the
--- licence text (default: the root's LICENSE file).
--- Returns stats: { output, files, bytesIn, bytesOut, version, elements,
--- added, modules, removed, names }.
---@param options? table Build options (see above)
---@return table stats
local function build(options)
    options = options or {}
    if options.minify == true or options.compress == true then
        error(
            "bundle: optimization is provided by Shale; "
                .. "build src/Shalefile.lua instead",
            0
        )
    end
    local root = options.root or defaultRoot()
    local srcDir = fs.combine(root, "src")
    local output = options.output
        or fs.combine(root, "bundle/basalt.lua")
    local license = options.license or readFile(fs.combine(root, "LICENSE"))
    if type(license) ~= "string" or license:find("%S") == nil then
        error("bundle: no LICENSE in " .. root .. "; the MIT licence must be "
            .. "copied into every bundle (or pass options.license)", 0)
    end

    local names = collect(srcDir)
    local raw, code = {}, {}
    for _, moduleName in ipairs(names) do
        raw[moduleName] = readSource(srcDir, moduleName)
        code[moduleName] = stripComments(raw[moduleName])
    end
    local version = raw.main:match('VERSION%s*=%s*"([^"]+)"') or "?"

    local wantElements = toList(options.elements, "elements")
    local wantModules = toList(options.modules, "modules")
    local bundled, info = {}, { added = {}, removed = {}, elements = {}, modules = {} }
    if wantElements == nil and wantModules == nil then
        -- everything, main.lua unchanged (the upstream release bundle);
        -- main.lua is not parsed, so the header lists the element files
        bundled = names
        for _, name in ipairs(names) do
            local element = name:match("^elements/(.+)$")
            local module = name:match("^modules/(.+)$")
            if element then info.elements[#info.elements + 1] = element end
            if module then info.modules[#info.modules + 1] = module end
        end
    else
        local selection = resolve(names, code, wantElements, wantModules)
        for _, name in ipairs(names) do
            if selection.included[name] then bundled[#bundled + 1] = name end
        end
        code.main = selection.main
        checkClosed(bundled, code, selection.registered, selection.keep)
        info.elements = sortedKeys(selection.keep)
        info.added = selection.added
        info.removed = selection.removed
        info.modules = selection.modules
    end

    local header = makeHeader({
        version = version,
        repository = options.repository,
        commit = options.commit,
        elements = info.elements,
        added = info.added,
        modules = info.modules,
        license = license,
    })

    local out = { header .. "local sources = {}" }
    local bytesIn, bytesOut = 0, 0
    for _, moduleName in ipairs(bundled) do
        local content = code[moduleName]
        bytesIn = bytesIn + #raw[moduleName]
        bytesOut = bytesOut + #content
        if content:sub(-1) ~= "\n" then
            content = content .. "\n"
        end
        local eqs = bracketFor(content)
        out[#out + 1] = ("sources[%q] = [%s[\n%s]%s]")
            :format(moduleName, eqs, content, eqs)
    end

    out[#out + 1] = [[
local loaded = {}
local function loader(name)
    local cached = loaded[name]
    if cached ~= nil then return cached end
]]
    -- _ENV: modules run in the environment this bundle was loaded with,
    -- like src/init.lua's loadfile(path, nil, _ENV)
    out[#out + 1] = [[
    local source = sources[name]
        or error("Basalt: module not bundled: " .. tostring(name), 0)
    local chunk = assert(load(source, "@basalt/" .. name .. ".lua", nil, _ENV))
    local result = chunk(loader, "basalt")
    loaded[name] = result == nil and true or result
    return loaded[name]
end
return loader("main")]]

    local generated = table.concat(out, "\n")
    local handle = fs.open(output, "w")
    if not handle then
        error("bundle: cannot write " .. output, 0)
    end
    handle.write(generated)
    handle.close()

    return {
        output = output,
        files = #bundled,
        bytesIn = bytesIn,
        bytesOut = #generated,
        processedBytes = bytesOut,
        version = version,
        commentsRemoved = true,
        elements = info.elements,
        added = info.added,
        modules = info.modules,
        removed = info.removed,
        names = bundled,
        header = header,
    }
end

----------------------------------------------------------------------------
-- CLI / library entry
----------------------------------------------------------------------------

local api = {
    build = build,
    collect = collect,
    stripComments = stripComments,
    defaultRoot = defaultRoot,
    findRegistrations = findRegistrations,
    patchMain = patchMain,
    scanNeeds = scanNeeds,
    gitSource = gitSource,
}

-- options that take a value: --name value or --name=value
local VALUE_OPTIONS = {
    ["--elements"] = "elements",
    ["--modules"] = "modules",
    ["--commit"] = "commit",
    ["--repo"] = "repository",
    ["--root"] = "root",
}

local options = {}
local index = 1
while index <= #args do
    local arg = args[index]
    local flag, value = arg:match("^(%-%-[%w%-]+)=(.*)$")
    flag = flag or arg
    if arg == "--lib" then
        return api -- library mode: hand the API to the caller (installer)
    elseif arg == "--no-minify" then
        -- Retained as a no-op for compatibility with older build commands.
    elseif arg == "--compress" then
        error(
            "bundle: minification and compression were replaced by Shale "
                .. "(see src/Shalefile.lua)",
            0
        )
    elseif VALUE_OPTIONS[flag] then
        if value == nil then
            index = index + 1
            value = args[index]
        end
        if value == nil then
            error("bundle: " .. flag .. " needs a value", 0)
        end
        options[VALUE_OPTIONS[flag]] = value
    elseif arg:sub(1, 2) == "--" then
        error("bundle: unknown option " .. arg, 0)
    else
        options.output = arg
    end
    index = index + 1
end

local stats = build(options)
print(("Basalt %s bundled: %d files -> %s"):format(
    stats.version, stats.files, stats.output))
print("Elements: " .. (#stats.elements > 0
    and table.concat(stats.elements, ", ") or "none"))
for _, entry in ipairs(stats.added) do
    print(("  added %s: %s needs it (%s)"):format(entry.name, entry.by, entry.why))
end
print("Modules: " .. (#stats.modules > 0
    and table.concat(stats.modules, ", ") or "none"))
print(("%d KB -> %d KB (comments stripped)"):format(
    math.floor(stats.bytesIn / 1024 + 0.5),
    math.floor(stats.bytesOut / 1024 + 0.5)))
