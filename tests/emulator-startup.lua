-- tests/emulator-startup.lua
-- Startup script for headless CraftOS-PC runs (tests/run.ps1): the
-- repository is mounted at /basalt, the suite runs, the emulator shuts down.
-- (run.lua writes the results file itself, also when it crashes.)
shell.run("/basalt/tests/run.lua", ...)
os.shutdown()
