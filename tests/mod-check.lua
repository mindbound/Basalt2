-- tests/mod-check.lua
-- In-game check for the "CC: Tweaked Unicode Support" mod (the headless
-- suite can only simulate it). Run it on a computer with the mod:
--   basalt/tests/mod-check          (from where the repository is)
-- It compares Basalt's cell counts with what the mod's own terminal does,
-- draws a Basalt UI on the native terminal (whose blit is strict), records
-- what the mod's window.getLine returns, and lets you type into an Input.
-- Results are printed and saved to /basalt-mod-check.txt.

local root = "/" .. fs.getDir(fs.getDir(shell.getRunningProgram()))
local src = "/" .. fs.combine(root, "src")
local basalt = assert(loadfile(src .. "/init.lua", nil, _ENV))("basalt", src .. "/init.lua")
local text = basalt.text

local lines = {}
local function out(s)
    lines[#lines + 1] = s
end
local function hex(s)
    return (s:gsub(".", function(c) return ("%02X "):format(c:byte()) end))
end

out("Host: " .. tostring(_HOST))
out("unicode global: " .. type(unicode) .. ", Basalt sees the mod: " .. tostring(text.isUtf8()))

-- 1) Cell counts: Basalt's decoder against the cursor movement of the
-- native terminal (the mod's own decoder) and unicode.len
local cases = {
    { "ASCII", "abc" },
    { "cafe in UTF-8", "caf\195\169" },
    { "em dash", "\226\128\148" },
    { "emoji (4 bytes)", "\240\159\152\128" },
    { "CC-charset e-acute", "\233" },
    { "lead byte + 2 continuation bytes", "\233\149\149" },
    { "C0 AF", "\192\175" },
    { "overlong E0 80 AF", "\224\128\175" },
    { "surrogate ED A0 80", "\237\160\128" },
    { "above U+10FFFF", "\244\144\128\128" },
    { "cut-off E2 80", "\226\128" },
    { "teletext bytes", "\149\128\159" },
    { "Latin-1 bytes", "\176\177\255" },
}
local native = term.native()
local nw = native.getSize()
out("")
out("Cell counts (basalt / terminal / unicode.len):")
local mismatches = 0
for _, case in ipairs(cases) do
    native.setCursorPos(1, 1)
    native.write(case[2])
    local cx = native.getCursorPos()
    local termCells = cx - 1
    local modLen = type(unicode) == "table" and unicode.len(case[2]) or -1
    local mine = text.width(case[2])
    local ok = mine == termCells
    if not ok then mismatches = mismatches + 1 end
    out(("  %-34s %d / %d / %d %s  [%s]"):format(case[1], mine, termCells, modLen,
        ok and "" or "MISMATCH", hex(case[2])))
end
out("  " .. (mismatches == 0 and "all match" or (mismatches .. " MISMATCH(ES)")))

-- 2) What window.getLine returns for mixed text (Program draws from it)
local win = window.create(native, 1, 1, 12, 1, false)
win.setCursorPos(1, 1)
win.write("\233\149\149" .. "caf\195\169" .. "\226\128\148")
local wtext, wfg = win.getLine(1)
out("")
out("window.getLine after writing E9 95 95 + 'cafe' + em dash:")
out("  text: " .. hex(wtext))
out("  basalt cells: " .. text.width(wtext) .. ", fg bytes: " .. text.byteLen(wfg))

-- 3) A Basalt UI on the native terminal: its blit raises an error on any
-- row whose cells and colours don't match
local sample = "caf\195\169 \226\128\148 17 \194\176C \240\159\152\128 \233"
local ok, err = pcall(function()
    local frame = basalt.createFrame(native)
    frame:addLabel({ x = 2, y = 2, text = sample })
    frame:addLabel({ x = 2, y = 3, text = "\233" .. "\149\149" .. "|" })
    local list = frame:addList({ x = 2, y = 5, width = 16, height = 3 })
    list:setItems({ sample, "\226\128\148 dash", "plain" })
    frame:addButton({ x = 20, y = 5, text = "\195\137t\195\169" })
    for _ = 1, 3 do
        basalt.update()
        frame:markRenderDirty()
    end
    basalt.update()
end)
out("")
out("Basalt UI on the native terminal: " .. (ok and "drawn without errors" or ("ERROR: " .. tostring(err))))

-- 4) Optional: type into an Input (a separate Basalt instance, so the
-- frame above doesn't take the keys)
local typed
if ok then
    local app = assert(loadfile(src .. "/init.lua", nil, _ENV))("basalt", src .. "/init.lua")
    native.setBackgroundColour(colours.black)
    native.clear()
    local frame = app.createFrame(native)
    frame:addLabel({ x = 2, y = 2, text = "Type e.g. caf\195\169 \226\128\148, then Enter (Ctrl+T skips):" })
    local input = frame:addInput({ x = 2, y = 4, width = math.min(30, nw - 2) })
    input:focus()
    input:onEnter(function(self) typed = self.text app.stop() end)
    local runOk = pcall(app.run)
    if typed then
        out("")
        out("Typed into an Input: " .. hex(typed) .. " (" .. text.width(typed) .. " cells)")
    end
    if not runOk then out("Input check stopped") end
end

-- Restore the screen and report
native.setBackgroundColour(colours.black)
native.setTextColour(colours.white)
native.clear()
native.setCursorPos(1, 1)
local current = term.current()
if current.redraw then current.redraw() end
term.clear()
term.setCursorPos(1, 1)

local f = fs.open("/basalt-mod-check.txt", "w")
f.write(table.concat(lines, "\n") .. "\n")
f.close()
for _, line in ipairs(lines) do print(line) end
print("Saved to /basalt-mod-check.txt")
