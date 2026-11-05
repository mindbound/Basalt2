-- tests/test_modules.lua
-- Optional modules: xml, animation, theme (incl. the basalt preset) and
-- debug. Ported from the deleted 2.5 smoke test (2062cc6:test_smoke.lua).

return function(T)
    T.test("xml builds a tree with converted and reactive attributes", function()
        local basalt, frame = T.frame()
        local xml = basalt.use("xml")
        local clicked = false
        local built = xml.load(frame, [[
            <!-- demo ui -->
            <frame x="35" y="16" width="14" height="3" name="xf">
                <label x="2" y="1" name="xlbl" text="XML!"/>
                <label x="8" y="1" name="xrl" text="{parent.width}"/>
                <button x="2" y="2" width="5" height="1" text="Go" onClick="go"/>
                <label x="9" y="2" name="xtxt">TXT</label>
            </frame>
        ]], { go = function() clicked = true end })
        T.eq(#built, 1)
        T.eq(built[1].__name, "Frame")
        T.eq(frame:find("xlbl").text, "XML!", "attribute")
        T.eq(frame:find("xrl").text, 14, "reactive attribute")
        T.eq(frame:find("xtxt").text, "TXT", "text content")
        basalt.update()
        T.click(basalt, 36, 17)
        T.ok(clicked, "onClick is bound from the scope")
    end)

    T.test("xml rejects mismatched tags", function()
        local xml = T.loadBasalt().use("xml")
        T.raises(function() xml.parse("<a><b></a>") end, "unexpected </a>")
    end)

    T.test("an animation tweens to its target and can be cancelled", function()
        local basalt, frame = T.frame()
        local label = frame:addLabel({ x = 2, y = 2, text = "Hello" })
        local anim = basalt.use("animation")
        local done = false
        anim.to(label, { x = 8 }, 0.25, "linear", function() done = true end)
        T.ok(T.waitFor(basalt, function() return done end, 5), "finished within 5 seconds")
        T.eq(label.x, 8)
        local handle = label:animate({ x = 2 }, 1, "linear") -- Element sugar
        handle.cancel()
        T.waitFor(basalt, function() return false end, 0.3) -- let ticks pass
        T.eq(label.x, 8, "a cancelled animation does not move")
    end)

    T.test("theme.set restyles class defaults live", function()
        local basalt, frame = T.frame()
        local theme = basalt.use("theme")
        local btn = frame:addButton({ x = 2, y = 6 })
        local blue = basalt.rgb("#0000aa")
        theme.set({ Button = { background = blue } })
        T.eq(btn.background, blue, "an existing button follows")
        local btn2 = frame:addButton({ x = 44, y = 10, width = 5, height = 1 })
        T.eq(btn2.background, blue, "a new button inherits")
        btn2.background = colors.red
        T.eq(btn2.background, colors.red, "an explicit value wins")
    end)

    T.test("theme state styles override and restore explicit values", function()
        local basalt, frame = T.frame()
        local theme = basalt.use("theme")
        local btn = frame:addButton({ x = 44, y = 10, width = 5, height = 1 })
        btn.background = colors.red
        theme.set({ Button = { states = {
            hover = { background = colors.yellow },
            disabled = { foreground = colors.lightGray },
        } } })
        btn:setState("hover", true)
        T.eq(btn.background, colors.yellow, "the state style wins")
        btn:setState("hover", false)
        T.eq(btn.background, colors.red, "the explicit value is back")
        btn.disabled = true
        T.eq(btn.foreground, colors.lightGray, "disabled state style")
    end)

    T.test("theme.apply styles a subtree, including state styles", function()
        local basalt, frame = T.frame()
        local theme = basalt.use("theme")
        local sub = frame:addFrame({ x = 40, y = 14, width = 10, height = 3 })
        local label = sub:addLabel({ text = "abc" })
        local outside = frame:addLabel({ text = "out" })
        theme.apply(sub, { Label = {
            foreground = colors.yellow,
            states = { alert = { foreground = colors.red } },
        } })
        T.eq(label.foreground, colors.yellow)
        T.eq(outside.foreground, colors.white, "outside the subtree")
        label:setState("alert", true)
        T.eq(label.foreground, colors.red)
    end)

    T.test("theme.set rejects reactive strings and unknown types", function()
        local theme = T.loadBasalt().use("theme")
        T.raises(function() theme.set({ Button = { background = "{self.x}" } }) end,
            "reactive strings")
        T.raises(function() theme.set({ Nope = {} }) end, "unknown element type")
    end)

    T.test("the basalt preset styles defaults and class states", function()
        local basalt = T.loadBasalt()
        local theme = basalt.use("theme")
        T.ok(theme.presets and theme.presets.basalt, "preset registered")
        local explicit = basalt.createFrame(T.window())
        explicit:setBackground(basalt.rgb("#1e1e2e"))
        local follower = basalt.createFrame(T.window(40, 18))
        local pal = theme.applyPreset("basalt")
        T.ok(pal.lava and pal.bg and pal.text, "palette tokens")
        local btn = follower:addButton({ x = 30, y = 16, width = 6, height = 1 })
        T.eq(btn.background, pal.raised, "preset default on a new button")
        T.eq(btn.foreground, pal.text, "Element foreground token inherited")
        btn:setState("hover", true)
        T.eq(btn.background, pal.border, "preset hover style")
        btn:setState("hover", false)
        T.eq(follower.background, pal.bg, "a root without a background follows live")
        T.ok(explicit.background ~= pal.bg, "an explicit background wins")
        basalt.update()
    end)

    T.test("the debug overlay logs and toggles with F12", function()
        local basalt = T.frame()
        local dbg = basalt.use("debug")
        T.eq(type(basalt.debug), "function", "basalt.debug installed")
        basalt.debug("Hello", 42)
        local overlay = dbg.getOverlay()
        T.eq(overlay.visible, false, "starts hidden")
        basalt.update("key", keys.f12)
        T.eq(overlay.visible, true, "F12 shows it")
        local found = false
        for _, child in ipairs(overlay:getChildren()) do
            if child.text == "Hello 42" then found = true end
        end
        T.ok(found, "the log line is shown")
        basalt.update()
        basalt.update("key", keys.f12)
        T.eq(overlay.visible, false, "F12 hides it again")
    end)
end
