-- tests/test_bundle_subset.lua
-- tools/bundle.lua beyond the full build (tests/test_bundle.lua): bundles
-- with chosen elements and modules (main.lua patching, dependencies, loud
-- failures), the environment bundled modules run in, the licence header,
-- and that manifest.txt lists every file under src/.

return function(T)
    local function bundler()
        return assert(loadfile(T.root .. "/tools/bundle.lua", nil, _ENV))("--lib")
    end

    local function readAll(path)
        local handle = assert(fs.open(path, "r"), "cannot read " .. path)
        local content = handle.readAll()
        handle.close()
        return content
    end

    -- the module names a bundle holds, in order
    local function bundledNames(text)
        local names = {}
        for name in text:gmatch('\nsources%["([^"]+)"%] = %[') do
            names[#names + 1] = name
        end
        return names
    end

    -- the (patched) main.lua inside a bundle
    local function bundledMain(text)
        local _, main = text:match('\nsources%["main"%] = %[(=*)%[\n(.-)%]%1%]')
        return main
    end

    local function has(list, value)
        for _, v in ipairs(list) do
            if v == value then return true end
        end
        return false
    end

    local function join(list) return table.concat(list, ",") end

    local SUBSET = { "Frame", "Canvas", "Label", "Input", "List" }

    T.test("a subset keeps the chosen elements and adds their base classes", function()
        local output = T.tmpFile("subset.lua")
        local stats = bundler().build({
            root = T.root, output = output, elements = SUBSET, modules = "none",
        })
        T.eq(join(stats.elements), "Canvas,Collection,Frame,Input,Label,List")
        T.eq(#stats.added, 1, "one element added")
        T.eq(stats.added[1].name, "Collection")
        T.eq(stats.added[1].by, "elements/List")
        T.eq(#stats.modules, 0, "no modules")

        local text = readAll(output)
        local names = bundledNames(text)
        T.eq(stats.files, #names)
        for _, name in ipairs({ "main", "core/render", "core/itemview",
            "elements/List", "elements/Collection", "elements/Canvas" }) do
            T.ok(has(names, name), name .. " bundled")
        end
        for _, name in ipairs({ "elements/Button", "elements/Dialog",
            "elements/TextBox", "modules/theme", "flimg" }) do
            T.ok(not has(names, name), name .. " left out")
        end

        -- the bundled main.lua registers exactly the kept elements
        local main = T.ok(bundledMain(text), "main found in the bundle")
        local kept = {}
        for _, reg in ipairs(bundler().findRegistrations(main)) do
            kept[#kept + 1] = reg.name
        end
        table.sort(kept)
        T.eq(join(kept), join(stats.elements))
        local all = bundler().findRegistrations(
            bundler().stripComments(readAll(T.src .. "/main.lua")))
        T.eq(#stats.removed, #all - #kept, "every other registration removed")
        T.cleanTmp()
    end)

    T.test("the subset bundle loads and runs a small UI", function()
        local output = T.tmpFile("subset.lua")
        bundler().build({ root = T.root, output = output, elements = SUBSET, modules = {} })
        local basalt = assert(loadfile(output, nil, _ENV))("basalt", output)
        T.eq(basalt.VERSION, T.loadBasalt().VERSION, "same version")

        local win = T.window(30, 10)
        local frame = basalt.createFrame(win)
        frame:addLabel({ x = 1, y = 1, text = "Chat" })
        local canvas = frame:addCanvas({ x = 1, y = 2, width = 12, height = 1 })
        canvas.draw = function(_, buf) buf:drawText(1, 1, "log line") end
        local list = frame:addList({ x = 1, y = 3, width = 12, height = 3 })
        list:addItem("/help")
        list:addItem("/clear")
        local input = frame:addInput({ x = 1, y = 10, width = 20 })
        T.click(basalt, 2, 10)
        T.type(basalt, "hi")
        basalt.update()
        T.eq(input.text, "hi", "the input edits")
        T.contains(T.row(win, 1), "Chat")
        T.contains(T.row(win, 2), "log line", "the canvas draws")
        T.contains(T.row(win, 3), "/help")
        T.contains(T.row(win, 4), "/clear")
        T.contains(T.row(win, 10), "hi")

        T.eq(frame.addButton, nil, "Button is not registered")
        T.eq(type(frame.addCollection), "function", "the added base class is registered")
        T.raises(function() basalt.use("theme") end, "module not bundled: modules/theme")
        T.cleanTmp()
    end)

    T.test("elements a chosen element creates are added; modules never add any", function()
        local b = bundler()
        local stats = b.build({ root = T.root, output = T.tmpFile("dialog.lua"),
            elements = "Dialog", modules = "none" })
        T.eq(join(stats.elements), "Button,Dialog,Frame,Input,Label")
        T.eq(#stats.added, 4)
        T.eq(stats.added[1].why:sub(1, 3), "add", "found through addX calls")

        local err = T.raises(function()
            b.build({ root = T.root, output = T.tmpFile("x.lua"),
                elements = { "Canvas" }, modules = { "debug" } })
        end, "modules/debug needs elements that are not chosen: Frame, Label")
        T.contains(err, "--modules")
        err = T.raises(function()
            b.build({ root = T.root, output = T.tmpFile("x.lua"), elements = SUBSET })
        end, "modules/theme needs elements that are not chosen: Button")
        T.ok(not tostring(err):find("Collection", 1, true), "only missing elements are named")

        -- modules that need no elements are fine
        stats = b.build({ root = T.root, output = T.tmpFile("anim.lua"),
            elements = SUBSET, modules = "animation,image" })
        T.eq(join(stats.modules), "animation,image")
        T.ok(has(stats.names, "flimg"), "flimg comes with the image module")
        T.cleanTmp()
    end)

    T.test("unknown elements and modules fail loudly", function()
        local b = bundler()
        local out = T.tmpFile("x.lua")
        T.raises(function()
            b.build({ root = T.root, output = out, elements = { "Frame", "Nope" }, modules = "none" })
        end, "unknown element 'Nope'")
        T.raises(function()
            b.build({ root = T.root, output = out, elements = "Frame", modules = "nothere" })
        end, "unknown module 'nothere'")
        T.raises(function()
            b.build({ root = T.root, output = out, elements = 42 })
        end, "elements must be")
        T.ok(not fs.exists(out), "nothing written")
        T.cleanTmp()
    end)

    ------------------------------------------------------------------------
    -- a small fake repository: main.lua in several formats
    ------------------------------------------------------------------------

    local FIXTURE = T.tmpDir .. "/fixture"

    local MAIN = [[
local require = ...
local Container = require("core/container")
Container.register("Alpha", require("elements/Alpha"))
Container.register( 'Beta' , require 'elements/Beta' ) ;
    Container.register("Gamma",
        require("elements/Gamma")) -- trailing comment
-- Container.register("Delta", require("elements/Delta"))
return table.concat(Container.names, ",")
]]

    local function writeFixture(files)
        if fs.exists(FIXTURE) then fs.delete(FIXTURE) end
        local all = {
            ["LICENSE"] = "Fixture licence\n\nSecond paragraph.\n",
            ["src/main.lua"] = MAIN,
            ["src/flimg.lua"] = "return {}\n",
            ["src/core/container.lua"] = [[
local Container = { names = {} }
function Container.register(name, cls)
    Container.names[#Container.names + 1] = name .. "=" .. cls.kind
end
return Container
]],
            ["src/elements/Alpha.lua"] = 'return { kind = "alpha" }\n',
            ["src/elements/Beta.lua"] = [[
local require = ...
local base = require("elements/Gamma")
return { kind = "beta+" .. base.kind }
]],
            ["src/elements/Gamma.lua"] = 'return { kind = "gamma" }\n',
            ["src/elements/Delta.lua"] = 'return { kind = "delta" }\n',
            ["src/modules/extra.lua"] = [[
local extra = {}
function extra.box(parent) return parent:addAlpha({}) end
return extra
]],
        }
        for path, content in pairs(files or {}) do all[path] = content or nil end
        for path, content in pairs(all) do
            local full = FIXTURE .. "/" .. path
            fs.makeDir(fs.getDir(full))
            local handle = fs.open(full, "w")
            handle.write(content)
            handle.close()
        end
    end

    local function buildFixture(options)
        options.root = FIXTURE
        options.output = options.output or T.tmpFile("fixture-out.lua")
        local stats = bundler().build(options)
        local loaded = assert(loadfile(options.output, nil, _ENV))("basalt", options.output)
        return stats, loaded, readAll(options.output)
    end

    T.test("main.lua registrations are found in several formats", function()
        writeFixture()
        local stats, registered, text = buildFixture({ elements = { "Beta" }, modules = "none" })
        T.eq(join(stats.elements), "Beta,Gamma", "Gamma added for Beta")
        T.eq(stats.added[1].name, "Gamma")
        T.eq(registered, "Beta=beta+gamma,Gamma=gamma", "the patched main runs")
        T.eq(join(stats.removed), "Alpha")
        local names = bundledNames(text)
        T.eq(join(names), "main,core/container,elements/Beta,elements/Gamma")

        stats, registered = buildFixture({ elements = "Gamma", modules = "none" })
        T.eq(registered, "Gamma=gamma", "a multi-line registration is kept alone")
        T.eq(join(stats.removed), "Alpha,Beta")

        stats, registered = buildFixture({ elements = "Alpha", modules = "extra" })
        T.eq(registered, "Alpha=alpha")
        T.eq(join(stats.modules), "extra")

        -- the full build does not patch main.lua
        stats, registered, text = buildFixture({})
        T.eq(registered, "Alpha=alpha,Beta=beta+gamma,Gamma=gamma")
        T.eq(#bundledNames(text), 8, "every file")
        T.cleanTmp()
    end)

    T.test("selection fails loudly when main.lua does not fit", function()
        writeFixture()
        T.raises(function() buildFixture({ elements = "Delta", modules = "none" }) end,
            "src/elements/Delta.lua has no Container.register line")
        T.raises(function() buildFixture({ elements = "Beta", modules = "extra" }) end,
            "modules/extra needs elements that are not chosen: Alpha")

        -- an element required outside a register call: a format change
        writeFixture({ ["src/main.lua"] = MAIN:gsub(
            "Container.register%(\"Alpha\", require%(\"elements/Alpha\"%)%)",
            "local Alpha = require(\"elements/Alpha\")\nContainer.register(\"Alpha\", Alpha)") })
        T.raises(function() buildFixture({ elements = "Beta", modules = "none" }) end,
            "main.lua requires 3 element files, but only 2")
        local _, registered = buildFixture({})
        T.eq(registered, "Alpha=alpha,Beta=beta+gamma,Gamma=gamma",
            "the full build does not depend on the format")

        writeFixture({ ["src/main.lua"] = MAIN .. 'Container.register("Gamma", require("elements/Gamma"))\n' })
        T.raises(function() buildFixture({ elements = "Beta", modules = "none" }) end,
            "registers the element Gamma twice")

        writeFixture({ ["src/main.lua"] = MAIN:gsub("elements/Alpha", "elements/Omega") })
        T.raises(function() buildFixture({ elements = "Beta", modules = "none" }) end,
            "src/elements/Omega.lua does not exist")

        writeFixture({ ["src/elements/Gamma.lua"] = 'local require = ...\nreturn require("core/missing")\n' })
        T.raises(function() buildFixture({ elements = "Gamma", modules = "none" }) end,
            "src/elements/Gamma.lua requires core/missing")

        writeFixture({ ["LICENSE"] = false })
        T.raises(function() buildFixture({}) end, "no LICENSE")
        T.cleanTmp()
    end)

    -- a main.lua that registers Alpha, then runs statement
    local function mainWith(statement)
        return 'local require = ...\nlocal Container = require("core/container")\n'
            .. 'Container.register("Alpha", require("elements/Alpha"))\n'
            .. statement .. '\nreturn table.concat(Container.names, ",")\n'
    end

    local GAMMA = 'Container.register("Gamma", require("elements/Gamma"))'

    T.test("only registrations that are statements of their own are removed", function()
        -- inside a larger expression: removing the call would break
        -- main.lua or change what it does (removing the call in
        -- 'C.register(...).done = true' would set done on the result of
        -- Alpha's call on the line before), so it is not a registration
        -- and the build stops
        for index, statement in ipairs({
            "local last = " .. GAMMA,
            "assert(" .. GAMMA .. ")",
            "local api = { Container = Container }\napi." .. GAMMA,
            "assert(\n    " .. GAMMA .. "\n)",
            "local list = { 1,\n" .. GAMMA .. " }",
            "local n = 1 +\n" .. GAMMA,
            "local ok = true and\n" .. GAMMA,
            GAMMA .. ".done = true",
            GAMMA .. "\n    :alias(\"G\")",
            GAMMA .. "\n(print)(\"called on the result\")",
        }) do
            writeFixture({ ["src/main.lua"] = mainWith(statement) })
            local output = T.tmpFile("expression-" .. index .. ".lua")
            T.raises(function()
                buildFixture({ elements = "Alpha", modules = "none", output = output })
            end, "main.lua requires 2 element files, but only 1")
            T.ok(not fs.exists(output), "nothing written: " .. statement)
        end

        -- statements of their own: after a ";" on the line, or in a block
        for _, statement in ipairs({
            "local n = 1; " .. GAMMA,
            "do\n    " .. GAMMA .. "\nend",
            "if true then\n    " .. GAMMA .. "\nend",
            "local n = 1\n" .. GAMMA .. ";",
            -- the ";" keeps a following "(" statement apart: it stays
            GAMMA .. ";\n(function() end)()",
        }) do
            writeFixture({ ["src/main.lua"] = mainWith(statement) })
            local _, registered = buildFixture({ elements = "Alpha", modules = "none" })
            T.eq(registered, "Alpha=alpha", "Gamma removed: " .. statement)
            _, registered = buildFixture({ elements = "Gamma", modules = "none" })
            T.eq(registered, "Gamma=gamma", "Gamma kept: " .. statement)
        end
        T.cleanTmp()
    end)

    T.test("a patched main.lua that does not compile is never written", function()
        -- a third argument: the pattern stops at require's ")", so only
        -- part of the call would be removed, leaving ", { hidden = true })"
        writeFixture({ ["src/main.lua"] = mainWith(
            'Container.register("Gamma", require("elements/Gamma"), { hidden = true })') })
        local output = T.tmpFile("broken.lua")
        local err = T.raises(function()
            buildFixture({ elements = "Alpha", modules = "none", output = output })
        end, "the patched main.lua does not compile (main.lua:")
        T.contains(err, "removed only part of a registration")
        T.ok(not fs.exists(output), "nothing written")
        local _, registered = buildFixture({ elements = "Gamma", modules = "none" })
        T.eq(registered, "Gamma=gamma", "keeping the call is fine")
        _, registered = buildFixture({})
        T.eq(registered, "Alpha=alpha,Gamma=gamma", "the original runs")

        -- a main.lua that does not compile at all is named as such
        writeFixture({ ["src/main.lua"] = mainWith(GAMMA .. "\nlocal = 1") })
        T.raises(function()
            buildFixture({ elements = "Alpha", modules = "none", output = output })
        end, "src/main.lua does not compile")
        T.ok(not fs.exists(output), "nothing written")
        T.cleanTmp()
    end)

    T.test("patchMain removes only the registrations that are not kept", function()
        local b = bundler()
        local code = b.stripComments(MAIN)
        local patched, removed = b.patchMain(code, { Beta = true })
        T.eq(join(removed), "Alpha,Gamma")
        T.ok(not patched:find("Alpha", 1, true), "Alpha gone")
        T.ok(not patched:find("Gamma", 1, true), "the multi-line Gamma call gone")
        T.contains(patched, "Container.register( 'Beta' , require 'elements/Beta' )")
        T.ok(not patched:find("\n\n", 1, true), "no blank lines left")
        local same = b.patchMain(code, { Alpha = true, Beta = true, Gamma = true })
        T.eq(same, code, "keeping everything changes nothing")
    end)

    ------------------------------------------------------------------------
    -- environment
    ------------------------------------------------------------------------

    T.test("bundled modules see the globals of the code that loads them", function()
        -- the Program element resolves program names through `shell`, which
        -- exists in a program's environment but not in _G
        local programPath = T.tmpFile("probe.lua", "probe.ran = true\nprobe.shell = shell\n")
        local output = T.tmpFile("env.lua")
        bundler().build({ root = T.root, output = output,
            elements = { "Frame", "Program" }, modules = "none" })

        local function probeWith(path)
            local probe = {}
            local fakeShell = {
                resolveProgram = function(name)
                    probe.resolved = name
                    return programPath
                end,
            }
            local env = setmetatable({ shell = fakeShell, probe = probe }, { __index = _G })
            local basalt = assert(loadfile(path, nil, env))("basalt", path)
            local frame = basalt.createFrame(T.window(20, 6))
            frame:addProgram({ width = 10, height = 3 }):execute("probe-program")
            T.eq(probe.resolved, "probe-program", path .. ": resolved through shell")
            T.eq(probe.ran, true, path .. ": the program ran")
            T.eq(probe.shell, fakeShell, path .. ": the program got the same shell")
        end
        probeWith(output)
        probeWith(T.src .. "/init.lua") -- the same as the source form
        T.cleanTmp()
    end)

    ------------------------------------------------------------------------
    -- header
    ------------------------------------------------------------------------

    T.test("every bundle starts with the licence, the source and the selection", function()
        local b = bundler()
        local output = T.tmpFile("header.lua")
        local stats = b.build({ root = T.root, output = output,
            elements = "Frame,Label", modules = "none",
            commit = "0123abc", repository = "https://example.invalid/Basalt2" })
        local text = readAll(output)
        local header = text:sub(1, (text:find("\nlocal sources = {}", 1, true)))
        T.eq(stats.header, header)
        T.eq(header:sub(1, 10), "-- Basalt ")
        for line in header:gmatch("([^\n]*)\n") do
            T.eq(line:sub(1, 2), "--", "only comment lines: " .. line)
        end
        T.contains(header, "\n-- Source: https://example.invalid/Basalt2\n")
        T.contains(header, "\n-- Commit: 0123abc\n")
        T.contains(header, "\n-- Elements: Frame, Label\n")
        T.contains(header, "\n-- Modules: none\n")
        -- the whole LICENSE, line by line (the MIT licence requires the
        -- copyright line and the permission notice in every copy)
        local license = readAll(T.root .. "/LICENSE")
        T.contains(license, "Copyright (c)")
        for line in license:gmatch("([^\n]*)\n") do
            T.contains(header, "\n" .. (line == "" and "--" or ("-- " .. line)) .. "\n")
        end

        -- the full build records everything; missing values say so
        stats = b.build({ root = T.root, output = output })
        T.contains(stats.header, "\n-- Commit: not recorded")
        T.contains(stats.header, "\n-- Source: not recorded")
        T.contains(stats.header, ", TextBox, Toast, Tree\n")
        T.contains(stats.header, "\n-- Modules: animation, bigfont,")
        T.contains(stats.header, "-- Copyright (c)")

        -- a line break in a value cannot end the comment
        stats = b.build({ root = T.root, output = output, elements = "Frame",
            modules = "none", commit = "abc\nerror('injected')" })
        T.contains(stats.header, "\n-- Commit: abc error('injected')\n")
        local basalt = assert(loadfile(output, nil, _ENV))("basalt", output)
        T.eq(type(basalt.createFrame), "function", "the bundle still loads")
        T.cleanTmp()
    end)

    -- tools/bundle-host.lua runs git for gitSource; CraftOS has no git, so
    -- these tests answer its git commands from a table
    T.test("the header records the last commit that changed the bundle's inputs", function()
        local b = bundler()
        local INPUTS = "src LICENSE tools/bundle.lua"
        local SHALLOW = "rev-parse --is-shallow-repository"
        local LOG = "log -1 --format=%H -- " .. INPUTS
        local STATUS = "status --porcelain -- " .. INPUTS
        local SHA = "7dbf1cf0a1b2c3d4e5f60718293a4b5c6d7e8f90"
        local HEAD = "2fe248b0a1b2c3d4e5f60718293a4b5c6d7e8f90"
        local TREE = "29c9c24a1b2c3d4e5f60718293a4b5c6d7e8f901"
        local asked
        local function source(answers)
            asked = {}
            return b.gitSource(function(command)
                asked[#asked + 1] = command
                return answers[command]
            end)
        end

        -- a full clone: the commit that last changed src, LICENSE or the
        -- bundler, not HEAD, so a README-only push rebuilds the same bundle
        local commit, repository = source({
            [SHALLOW] = "false", [LOG] = SHA, ["rev-parse HEAD"] = HEAD,
            ["remote get-url origin"] = "https://someone:token@github.com/someone/Basalt2.git",
        })
        T.eq(commit, SHA)
        T.eq(repository, "https://github.com/someone/Basalt2", "no credentials, no .git")
        T.ok(#asked > 0 and not has(asked, "rev-parse HEAD"), "HEAD not asked")

        -- an uncommitted change to an input (the bundler counts) is marked
        commit = source({ [SHALLOW] = "false", [LOG] = SHA, [STATUS] = " M tools/bundle.lua" })
        T.eq(commit, SHA .. " (with uncommitted changes)")

        -- a shallow clone (CI checks out one commit) shows every file as
        -- added by HEAD: the src tree id is recorded, and said to be one
        commit = source({ [SHALLOW] = "true", [LOG] = HEAD, ["rev-parse HEAD:src"] = TREE })
        T.eq(commit, "not known (shallow clone); src tree " .. TREE)
        local stats = b.build({ root = T.root, output = T.tmpFile("git.lua"),
            elements = "Frame", modules = "none", commit = commit })
        T.contains(stats.header, "\n-- Commit: not known (shallow clone); src tree "
            .. TREE .. "\n")
        commit = source({ [SHALLOW] = "true", ["rev-parse HEAD:src"] = TREE, [STATUS] = "?? src/x.lua" })
        T.eq(commit, "not known (shallow clone); src tree " .. TREE .. " (with uncommitted changes)")

        -- no git, no commit, no origin: nothing is recorded
        commit, repository = source({})
        T.eq(commit, nil, "no git")
        T.eq(repository, nil, "no git")
        commit, repository = source({ [SHALLOW] = "false", [STATUS] = "?? src/" })
        T.eq(commit, nil, "inputs never committed")
        T.eq(repository, nil, "no origin")
        T.cleanTmp()
    end)

    T.test("the command line takes the selection options", function()
        local output = T.tmpFile("cli.lua")
        local cli = assert(loadfile(T.root .. "/tools/bundle.lua", nil, _ENV))
        cli(output, "--root", T.root, "--elements=Frame,Label", "--modules", "none",
            "--commit", "feed123", "--repo=https://example.invalid/b")
        local text = readAll(output)
        T.contains(text, "\n-- Commit: feed123\n")
        T.contains(text, "\n-- Elements: Frame, Label\n")
        T.ok(not has(bundledNames(text), "elements/List"), "List left out")
        T.raises(function() cli(output, "--element", "Frame") end, "unknown option --element")
        T.raises(function() cli(output, "--elements") end, "--elements needs a value")
        T.cleanTmp()
    end)

    ------------------------------------------------------------------------
    -- manifest.txt (the web installer's "source" variant downloads it)
    ------------------------------------------------------------------------

    T.test("manifest.txt lists every file under src/", function()
        -- build configuration, never loaded at runtime
        local NOT_INSTALLED = { ["src/Shalefile.lua"] = true }
        local listed, count = {}, 0
        for line in (readAll(T.root .. "/manifest.txt") .. "\n"):gmatch("([^\n]*)\n") do
            line = line:gsub("\r", ""):gsub("%s+$", "")
            if line ~= "" then
                T.ok(not listed[line], line .. " is listed twice")
                listed[line] = true
                count = count + 1
                T.ok(fs.exists(T.root .. "/" .. line) and not fs.isDir(T.root .. "/" .. line),
                    line .. " is listed but is not a file")
            end
        end
        local found = 0
        local function walk(dir, relative)
            for _, name in ipairs(fs.list(dir)) do
                local path, rel = fs.combine(dir, name), relative .. "/" .. name
                if fs.isDir(path) then
                    walk(path, rel)
                elseif not NOT_INSTALLED[rel] then
                    found = found + 1
                    T.ok(listed[rel], rel .. " is missing from manifest.txt")
                end
            end
        end
        walk(T.src, "src")
        T.eq(count, found, "nothing else listed")
        T.ok(listed["src/flimg.lua"], "flimg (modules/image needs it)")
    end)
end
