-- Host-Lua compatibility runner for tools/bundle.lua.
--
-- The bundler uses the small CraftOS fs/shell API. This file provides the
-- required subset with standard Lua so release bundles can be built without
-- running CraftOS-PC. It takes the bundler's arguments, for example:
--   lua tools/bundle-host.lua out.lua --elements Frame,Label --modules none
-- When the repository root is a git checkout and --commit or --repo is not
-- given, it records in the bundle header the last commit that changed
-- src, LICENSE or tools/bundle.lua (in a shallow clone: the tree id of
-- src), marked when one of them has uncommitted changes, and the origin
-- URL (see gitSource in tools/bundle.lua). A given --commit or --repo wins.

local cliArgs = { ... }
local separator = package.config:sub(1, 1)

local function normalize(path)
    return (path:gsub("[/\\]", separator))
end

local function combine(...)
    local result = ""
    for index = 1, select("#", ...) do
        local part = normalize(tostring(select(index, ...)))
        if part ~= "" then
            if result == "" then
                result = part
            else
                result = result:gsub("[/\\]+$", "")
                    .. separator
                    .. part:gsub("^[/\\]+", "")
            end
        end
    end
    return result
end

local function getDir(path)
    path = normalize(path):gsub("[/\\]+$", "")
    return path:match("^(.*)[/\\][^/\\]+$") or ""
end

local function exists(path)
    local handle = io.open(path, "rb")
    if handle then
        handle:close()
        return true
    end
    local ok, _, code = os.rename(path, path)
    return ok or code == 13
end

local function shellQuote(path)
    if separator == "\\" then
        return '"' .. path:gsub('"', '""') .. '"'
    end
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function list(path)
    local command
    if separator == "\\" then
        command = "dir /b /a " .. shellQuote(path)
    else
        command = "find " .. shellQuote(path)
            .. " -mindepth 1 -maxdepth 1 -printf '%f\\n'"
    end

    local process = assert(io.popen(command, "r"))
    local entries = {}
    for entry in process:lines() do
        entries[#entries + 1] = entry
    end
    local ok = process:close()
    if ok == nil then
        error("bundle-host: cannot list " .. path, 0)
    end
    return entries
end

local function open(path, mode)
    local handle = io.open(path, mode == "r" and "rb" or "wb")
    if not handle then return nil end
    return {
        readAll = function()
            return handle:read("*a")
        end,
        write = function(content)
            handle:write(content)
        end,
        close = function()
            handle:close()
        end,
    }
end

local runningProgram = arg and arg[0] or "tools/bundle-host.lua"
local toolsDir = getDir(runningProgram)
if toolsDir == "" then toolsDir = "tools" end
local bundlePath = combine(toolsDir, "bundle.lua")

fs = {
    combine = combine,
    exists = exists,
    getDir = getDir,
    list = list,
    open = open,
}
shell = {
    getRunningProgram = function()
        return bundlePath
    end,
}

-- The value of a bundler option in the arguments (--name value or
-- --name=value), or nil.
local function optionValue(name)
    for index, arg in ipairs(cliArgs) do
        if arg == name then return cliArgs[index + 1] or "" end
        local value = arg:match("^" .. (name:gsub("%-", "%%-")) .. "=(.*)$")
        if value then return value end
    end
    return nil
end

-- The first output line of a git command in root, or nil.
local function git(root, command)
    local quiet = separator == "\\" and " 2>nul" or " 2>/dev/null"
    local process = io.popen("git -C " .. shellQuote(root) .. " " .. command .. quiet, "r")
    if not process then return nil end
    local output = process:read("*a") or ""
    process:close()
    return output:match("^[^\r\n]+")
end

local runBundle = assert(loadfile(bundlePath))

-- the root bundle.lua will use (its defaultRoot: the parent of tools/)
local root = optionValue("--root") or getDir(toolsDir)
if root == "" then root = "." end
local needCommit, needRepo = not optionValue("--commit"), not optionValue("--repo")
if exists(combine(root, ".git")) and (needCommit or needRepo) then
    local commit, repository = runBundle("--lib").gitSource(function(command)
        return git(root, command)
    end)
    if commit and needCommit then
        cliArgs[#cliArgs + 1] = "--commit=" .. commit
    end
    if repository and needRepo then
        cliArgs[#cliArgs + 1] = "--repo=" .. repository
    end
end

local unpackArgs = table.unpack or unpack
return runBundle(unpackArgs(cliArgs))
