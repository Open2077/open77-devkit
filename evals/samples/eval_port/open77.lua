resource "eval_port"
version "1.0.0"
auto_start true

-- Port of a FiveM "/cars" script: a key (default F6) or /cars opens a menu of
-- the server vehicles within 30 m; picking one asks the server to warp the
-- player into its driver seat.

-- client: vehicles.read  -> Open77.vehicles.nearby
--         input.actions  -> RegisterKeyMapping
--         network.events -> TriggerServerEvent / RegisterNetEvent
--         ui.vanilla.hud -> Open77.hud.notify
-- server: world.vehicles -> Open77.vehicles.warpPlayerIntoVehicle
--         network.events -> RegisterNetEvent / TriggerClientEvent
permissions {
    "vehicles.read",
    "input.actions",
    "network.events",
    "ui.vanilla.hud",
    "world.vehicles",
}

-- The keyboard menu is the UI kit's `menu` widget; no permission is needed for it.
dependency "open77_uikit"

client_script "client/main.lua"
server_script "server/main.lua"
