resource "eval_harness"
version "1.0.0"
auto_start true

-- Test-harness helper, not an eval sample. It gives the harness two things a
-- keystroke injector cannot reach on its own: a hotkey that closes the vanilla
-- world map (F7, the map eats Escape) and a resource-side waypoint for
-- experiments. The taxi eval reads only the USER waypoint (a pin placed on the
-- map UI), so the probe opens the map with M and right-clicks to place it.
permissions { "ui.vanilla.map", "map.control", "input.actions" }

client_script "client/main.lua"
