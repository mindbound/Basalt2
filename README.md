# Basalt 2.5

[![Basalt 2.5 CI](https://github.com/Pyroxenium/Basalt2/actions/workflows/ci.yml/badge.svg?branch=basalt2.5)](https://github.com/Pyroxenium/Basalt2/actions/workflows/ci.yml)
[![Discord](https://img.shields.io/discord/976905222251233320?label=Discord)](https://discord.gg/yNNnmBVBpE)
[![Documentation](https://img.shields.io/badge/docs-Basalt_2.5-b84a1b)](https://basalt.madefor.cc/2.5/)
[![Download on PineStore](https://raster.shields.io/badge/dynamic/json?url=https%3A%2F%2Fpinestore.cc%2Fapi%2Fproject%2F15&query=%24.project.downloads&suffix=%20downloads&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPHN2ZyB3aWR0aD0iNzYuOTA0IiBoZWlnaHQ9Ijg5LjI5NSIgcHJlc2VydmVBc3BlY3RSYXRpbz0ieE1pZFlNaWQiIHZlcnNpb249IjEuMSIgdmlld0JveD0iMCAwIDc2OS4wNCA4OTIuOTUiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI%2BCiA8ZyB0cmFuc2Zvcm09InRyYW5zbGF0ZSgtMTQuNzQgLTQuNjgyNikiIGZpbGw9IiM5YWIyZjIiPgogIDxwYXRoIGQ9Im00MTAgODUxYzAtMTIgMjYtMjEgNTgtMjEgMTUgMCAyMiA0IDE3IDktMTQgMTItNzUgMjItNzUgMTJ6Ii8%2BCiAgPHBhdGggZD0ibTU4NSA3NDJjLTEtNDkgNC03MiAxNi04NSAyMi0yNCAzMC02OCAxNi04Ni0xMi0xNC0yNy0zOS00OC03OC0xMC0xOS05LTI2IDQtNDEgMjItMjQgMjEtNjctMi0xNDQtMjEtNjktMzktMTQ0LTQ4LTE5NS00LTI2LTItMzMgMTEtMzMgMzEgMCAxMTIgMzMgMTQxIDU4IDI4IDIzIDgxIDkyIDcxIDkyLTIgMCA1IDI2IDE2IDU3IDI4IDc5IDI5IDIyNCAzIDMwOC0xMCAzMy0xOSA2Mi0xOSA2NS00IDI2LTEzMiAxNTAtMTU1IDE1MC0zIDAtNi0zMC02LTY4eiIvPgogIDxwYXRoIGQ9Im02OCA2NzNjLTcyLTEwOS03MS0yNzggMy00MjMgMzYtNzEgNjItMTAwIDEyOC0xNDAgNDMtMjcgNjUtMzQgMTE4LTM2IDEwMC00IDk4IDExLTE5IDEzNi0zNCAzNy03OCA4OC05NiAxMTMtMjggMzktMzEgNDgtMjEgNjUgMTEgMTcgNiAyNy0zMyA3OS00MCA1My00NCA2Mi0zMiA3OCAxNyAyMyAxOCA1NyAyIDczLTYgNi0xNCAzMS0xNyA1NC02IDQyLTYgNDItMzMgMXoiLz4KIDwvZz4KIDxnIHRyYW5zZm9ybT0idHJhbnNsYXRlKC0xNC43NCAtNC42ODI2KSIgZmlsbD0iIzU5YTY0ZiI%2BCiAgPHBhdGggZD0ibTM2NSA4MTNjLTUzLTYtMTM5LTMzLTE5Mi02MS02OC0zNS04My02Ny01OC0xMjIgMjYtNTkgNDAtNjcgNzgtNDkgNjggMzMgMTY3IDU4IDI2NiA2OSA1OCA1IDEwNiAxMiAxMDkgMTQgMiAzIDYgMzIgOSA2NSA4IDg1IDAgOTEtMTAxIDkwLTQ0LTEtOTQtNC0xMTEtNnoiLz4KICA8cGF0aCBkPSJtNDEwIDQ1OWMtNjctNy0xNjAtMjktMTk5LTQ4LTI3LTE0LTM0LTM2LTIwLTYzIDIxLTM4IDk3LTEzNiAxNTAtMTkzIDI1LTI3IDU4LTcxIDczLTk3IDI1LTQzIDMxLTQ3IDU0LTQyIDQwIDEwIDQyIDEyIDQyIDUyIDAgMjAgNiA1NyAxNCA4MiAyNCA3MyA1NCAxOTIgNjIgMjM2IDUgMzUgMyA0NS0xNSA2My0yMyAyMy0zNiAyNC0xNjEgMTB6Ii8%2BCiA8L2c%2BCiA8ZyB0cmFuc2Zvcm09InRyYW5zbGF0ZSgtMTQuNzQgLTQuNjgyNikiIGZpbGw9IiM3ZWNiMjUiPgogIDxwYXRoIGQ9Im01NTggNjc0Yy0yLTItNTEtOS0xMDktMTQtMTAyLTExLTIwNC0zNy0yNjQtNjktMTYtOC0zMi0xNC0zNC0xMi00IDMtMzEtNDgtMzEtNjEgMC01IDIxLTMxIDQ2LTU4IDUxLTU0IDcxLTYwIDEzMC0zNSAxOSA4IDgzIDE5IDE0MiAyNSA1OCA2IDEwNyAxMiAxMDcgMTNzMTUgMjYgMzMgNTZjMjcgNDMgMzIgNjMgMzAgOTktMiAzNS04IDQ3LTI1IDUzLTExIDQtMjMgNi0yNSAzeiIvPgogPC9nPgogPGcgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoLTE0Ljc0IC00LjY4MjYpIiBmaWxsPSIjZWNlZGVmIj4KICA8cGF0aCBkPSJtMjYwIDg5MGMtMzQtOC03MC00MS03MC02NSAwLTYtOS0yMC0yMC0zMHMtMjAtMjItMjAtMjctMTMtMjEtMzAtMzVjLTM1LTI5LTQxLTgzLTEzLTEyMiAxNS0yMiAxNS0yNi0xLTU2LTE4LTMzLTE4LTMzIDI3LTkxIDI4LTM2IDQyLTYzIDM2LTY4LTIzLTI1IDktNzggMTIwLTE5NyAzNi0zOCA3Mi04MSA4Mi05NiAxMC0xNCAyNS0zMCAzMy0zNSAzNi0yMCA3IDMyLTUzIDk3LTQ4IDUxLTEyNiAxNTAtMTQ5IDE4OS0xMCAxOC05IDI0IDEwIDQwIDIzIDE5IDIzIDE5LTI5IDcxLTUzIDUyLTUzIDUyLTM4IDgyIDE0IDI4IDE0IDMzLTEwIDc2LTMyIDU3LTIzIDgxIDQ2IDEyMCAzNCAxOSA0OSAzMyA0NSA0Mi0xNCAzNyAzNiA3NSA5OCA3NSAyNSAwIDQwLTcgNTQtMjUgMTgtMjMgMjctMjUgOTUtMjUgOTQgMCAxMDItOCA5My04OS02LTUzLTUtNTkgMTQtNjQgMzItOCAyNi02NC0xNS0xMzItMzUtNTgtMzUtNTgtOS04MiAyMS0xOSAyNC0yOSAxOS01Ni0xMC00Ny00NC0xNzUtNjEtMjI3LTgtMjUtMTQtNjItMTQtODMgMC0yNy01LTM5LTE3LTQzLTEwLTMtMjUtOC0zMy0xMC0xMi00LTEyLTYtMS0xNCAyNy0xNiA1NiA1IDY5IDUxIDM1IDExNyA0MyAxNDggNDYgMTcwIDIgMTMgMTEgNTEgMjEgODQgMjEgNzEgMjEgMTIxIDAgMTQ1LTE0IDE1LTEzIDE5IDUgNDMgMTEgMTQgMjAgMzAgMjAgMzVzNyAxNSAxNSAyMmMyMSAxNyAxNiA3NS0xMCAxMDItMTggMTktMjAgMzItMTcgNzkgNCA1MCAyIDU4LTE5IDcyLTEyIDktNTAgMTktODMgMjMtNDUgNS02NSAxMy04MyAzMi0yNiAyOC05MiAzOC0xNTMgMjJ6Ii8%2BCiA8L2c%2BCiA8ZyB0cmFuc2Zvcm09InRyYW5zbGF0ZSgtMTQuNzQgLTQuNjgyNikiIGZpbGw9IiM3ZTY3NGQiPgogIDxwYXRoIGQ9Im0yNDggODU0Yy0zMC0xNi00Ny01OS0zMC03NiA4LTggMjMtNyA1NCAyIDI0IDcgNjEgMTQgODMgMTcgNTQgNyA1OSAxNSAzNSA0Ni0xOCAyMy0yOSAyNy02OCAyNy0yNi0xLTU5LTctNzQtMTZ6Ii8%2BCiA8L2c%2BCjwvc3ZnPgo%3D&label=PineStore)](https://pinestore.cc/projects/15/basalt)

A modern UI framework for
[CC:Tweaked](https://tweaked.cc/) with reactive state, flexible layouts,
rich components, and first-class tooling.

Basalt 2.5 is an improved and extended release of Basalt 2. It modernizes
the internals and developer experience while keeping the familiar approach
to building terminal interfaces.

![Basalt 2.5 interface showcase](.github/assets/preview.gif)

## Features

- A broad component set including buttons, inputs, lists, tables, dialogs,
  menus, trees, tabs, and more
- Reactive state and computed values
- Responsive values and flex-based layouts
- RGB colors, palettes, and themes
- Optional modules for animations, charts, images, XML, debugging, and more
- Direct property access as well as method chaining
- LuaLS annotations and generated API documentation
- Readable and Shale-optimized single-file builds

## Installation

Run the following command inside CC:Tweaked:

```sh
wget run https://basalt.madefor.cc/2.5/install.lua minified
```

This downloads the recommended minified build as `basalt.lua`. You can then
load it with:

```lua
local basalt = require("basalt")
```

Run the installer without arguments to choose a version and destination
interactively:

```sh
wget run https://basalt.madefor.cc/2.5/install.lua
```

### Available builds

| Variant | Output | Intended use |
| --- | --- | --- |
| `source` | `basalt/` | Editable source files and development |
| `bundled` | `basalt.lua` | Readable single-file build |
| `minified` | `basalt.lua` | Shale-minified build with immediate startup; recommended |
| `compressed` | `basalt.lua` | Smallest [Shale](https://github.com/Pyroxenium/Shale)-powered build with a short startup delay |

A custom destination can be passed after the variant:

```sh
wget run https://basalt.madefor.cc/2.5/install.lua minified lib/basalt.lua
```

## Quick start

```lua
local basalt = require("basalt")

local frame = basalt.getMainFrame()
frame:setBackground(basalt.rgb("#1e1e2e"))

local label = frame:addLabel({
    x = 2,
    y = 2,
    text = "Hello World",
})

frame:addButton({
    x = 2,
    y = 4,
    text = "Click me",
})
    :onClick(function(self)
        self.text = "Thanks!"
        label.text = "Button clicked!"
    end)

basalt.run()
```

Elements accept properties when they are created. Most properties can also
be updated directly later:

```lua
label.text = "A new value"
label.x = 4
```

## Examples

- [`examples/basic.lua`](examples/basic.lua) is a small, commented starter
  application intended for copying and modification.
- [`examples/showcase.lua`](examples/showcase.lua) is the full animated
  Basalt 2.5 feature showcase.

## Unicode text

With the "CC: Tweaked Unicode Support" mod installed, the terminal draws
UTF-8: one character is one cell, even
when it takes several bytes. Basalt detects the mod and then measures,
cuts, wraps and edits text in cells, so labels, lists, tables and inputs
show and edit UTF-8 correctly. Characters typed or pasted in CC's own
charset (such as `é`) are stored as UTF-8. Without the mod nothing changes:
a cell is a byte.

For your own drawing code (for example in a `Canvas`), use the same helpers
instead of `#` and `string.sub`, which count bytes (or, under the mod,
characters only when the whole string is valid UTF-8):

```lua
local text = basalt.text
text.width(s)          -- width in cells
text.sub(s, i, j)      -- substring by cells
text.pad(s, n, align)  -- cut or pad to n cells
text.wrap(s, width)    -- word wrap by cells
```

## Text from outside the program

A string assigned to an element property that starts with `{` and ends
with `}` is compiled as a Lua expression (a reactive string), with access
to the element tree. Text from files, the network, chat or an AI model must
never be compiled, so turn reactive strings off for such an app, or mark
single values:

```lua
basalt.setReactiveStrings(false)    -- store every "{...}" string as written
label.text = basalt.literal(reply)  -- or keep them on and mark one value
```

Dialog titles and messages, Toast messages, debug log lines and collection
items (List, Menu, ...) are always shown as written. XML layouts are author
code and stay reactive.

## Ctrl+T

`basalt.run()` ends the app on Ctrl+T. To use Ctrl+T to cancel work
instead, pass `onTerminate`:

```lua
basalt.run({ onTerminate = function()
    status.text = "Cancelled"  -- the loop keeps running until basalt.stop()
end })
```

Ctrl+T then ends scheduled tasks that are waiting (in `sleep`,
`os.pullEvent` or an http call), except those started with
`basalt.schedule(fn, { ignoreTerminate = true })`. A focused `Program`
passes it to its program, as multishell does.

## Focus and the input cursor

A click on an element with a background or a click handler gives it the
keyboard focus. Set `focusOnClick = false` on an element that must leave
the focus where it is, such as a log, a popup list or the root frame. It
still gets its click, drag and scroll events, and `focus()` from code
still works:

```lua
basalt.getMainFrame().focusOnClick = false  -- a click on the background keeps the focus
log.focusOnClick = false
```

Such a click blurs nothing, so a popup that closes when it loses the
focus (an open `ContextMenu`, `Dropdown`, `ComboBox` or a `Menu`'s
submenu) stays open, and keeps the keys, when the click lands there. If
it must close, move the focus from that element's `onClick`:

```lua
frame:onClick(function() input:focus() end)  -- the blur closes the popup
```

`input:setCursorPos(pos)` and `input:getCursorPos()` move and read an
Input's cursor, in cells (1 is before the first character). Assigning
`input.text` keeps the cursor where it is, clamped to the new text, so
put it after a recalled entry like this:

```lua
input.text = history[i]
input:setCursorPos(math.huge)
```

## Driving Basalt yourself

An app with its own event loop can feed events to Basalt instead of
calling `basalt.run()`:

```lua
local ok, err = pcall(function()
    basalt.update()                        -- no event: just draw
    while running do
        local ev = table.pack(os.pullEventRaw())
        -- look at ev first if you like, and keep it from Basalt
        basalt.update(table.unpack(ev, 1, ev.n))
    end
end)
basalt.cleanup()                           -- palette and terminal back
if not ok then printError(tostring(err)) end
```

- `basalt.update(event, ...)` gives one event to the frames and the
  scheduled tasks, then draws what changed. A `term_resize` resizes every
  root frame, as in `basalt.run()`. Your loop decides what Ctrl+T does
  (the `basalt.update` docs say where Basalt sends a `terminate` event).
- Errors come out of `basalt.update`; there is no error screen. An error in
  an event handler or a draw callback comes out as it was raised (a
  traceback taken around `basalt.update` then starts at Basalt's draw; the
  message keeps the callback's position). An error in a scheduled task is
  a table: `err.err` is the error, `err.trace` the task's traceback (also
  for a draw the task started), and `tostring(err)` gives the message.
  Basalt can go on after you handled it.
- `basalt.cleanup()` does what `basalt.run()` does when it ends: every
  palette slot Basalt changed gets its earlier color back, and the
  terminal is cleared. A second call leaves what you printed after the
  first. The next `basalt.update` draws the frames again.
- `basalt.repaint()` draws every frame again in full, at once. Basalt only
  sends lines that changed, so call it after something else wrote to the
  screen, for example a program that used `term.native()`. Called from a
  draw callback, the running draw repaints every frame once it has drawn
  them all. Frames also
  take their terminal's current size, as `basalt.run()` does when it
  starts (for a `term_resize` that another program took).

## Handing the palette back

Basalt shows `basalt.rgb` colors by changing palette slots. A shell
command should see the terminal's own colors (a program may read them,
and a multishell tab copies them). Hand them back while it runs:

```lua
basalt.suspendPalette()   -- the terminal's own colors are back
shell.run(command)        -- the UI may keep drawing meanwhile
basalt.resumePalette()    -- RGB colors again; everything is redrawn
```

While the palette is suspended, Basalt draws each RGB color as the
nearest of the 16 colors the terminal shows and never changes the
palette, also for frames created meanwhile, so a status line can keep
ticking. Calls nest: the palette comes back after as many
`resumePalette` calls (`basalt.isPaletteSuspended()` tells). Resume on
the error path too; `basalt.cleanup()` ends a suspension.

## Building bundles

`lua tools/bundle-host.lua out.lua` (or `bundle` in CraftOS) builds the
readable single-file bundle. To ship only part of Basalt, choose the
elements and modules:

```sh
lua tools/bundle-host.lua ui.lua --elements Frame,Label,Input,List,Canvas --modules none
```

Elements that a chosen element needs (`List` needs `Collection`; `Dialog`
needs `Frame`, `Label`, `Button` and `Input`) are added and reported. A
module that needs elements you did not choose stops the build (`theme`
needs all elements except `Canvas`). For a subset, each
`Container.register("Name", require("elements/File"))` in `src/main.lua`
must be a statement of its own; anything else stops the build, and the
patched `main.lua` is compile-checked before anything is written.

Every bundle starts with the MIT licence notice and records its source,
its commit and the selection. The host runner fills these in from git.
The commit is the last one that changed `src`, `LICENSE` or
`tools/bundle.lua`, so commits that change only other files build the same
bundle. A shallow clone (as in CI) can't tell that commit and records
`not known (shallow clone); src tree <id>` instead. `(with uncommitted
changes)` marks a build from a tree where those files differ from HEAD.
`--commit <sha>` and `--repo <url>` override both values. The host runner
needs Lua 5.1 or later. Bundled modules run in the environment the bundle
is loaded with, as the source form does, so a `Program` element finds
programs through `shell`.

## Testing

The headless test suite runs in [CraftOS-PC](https://www.craftos-pc.cc/)
(CI runs it on pushes and pull requests to `basalt2.5`) or in-game on a
computer without the Unicode Support mod:

```sh
basalt/tests/run              # all suites
basalt/tests/run test_text    # one suite
```

From Windows: `tests\run.ps1 -Emulator <path to CraftOS-PC_console.exe>`.
The suite simulates the Unicode Support mod (`tests/modsim.lua`). On a
computer that has the mod, run `basalt/tests/mod-check` instead: it
compares Basalt's cell counts with the mod's own terminal and draws a test
UI on the native terminal, whose blit rejects any row of the wrong width.

## Documentation

- [Getting started](https://basalt.madefor.cc/2.5/guides/getting-started)
- [Guides](https://basalt.madefor.cc/2.5/guides/)
- [API reference](https://basalt.madefor.cc/2.5/api/)
- [Basalt 2 documentation](https://basalt.madefor.cc/2.0/)

## Community and support

- [Report a bug](https://github.com/Pyroxenium/Basalt2/issues)
- [GitHub Discussions](https://github.com/Pyroxenium/Basalt2/discussions)
- [Discord](https://discord.gg/yNNnmBVBpE)
