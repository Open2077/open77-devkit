-- eval_port2 -- port of a small FiveM resource (heal / dv / ping-pong) to Open77.
-- Written against what the Open77 devkit MCP answered for build 2.31.13+op77.75.
--
-- fxmanifest.lua -> open77.lua mapping (per open77_manifest_schema and the
-- fivem-compatibility guide, "Manifest keys"):
--   fx_version 'cerulean'   -> dropped. The guide says it would be "accepted and ignored"
--                              and logged as manifest_ignored_keys; the schema does not list it.
--   game 'gta5'             -> dropped, same reason.
--   server_script / client_script -> same directive names.
--   (new) resource / version -> `resource` is required and must equal the directory name.
--   (new) permissions        -> every native below that is gated must be declared here,
--                              otherwise it answers permission_denied:<name>.

resource "eval_port2"
version "1.0.0"

server_script "server.lua"
client_script "client.lua"

permissions {
    "network.events",       -- RegisterNetEvent / TriggerClientEvent (server), RegisterNetEvent / TriggerServerEvent (client)
    "players.stats.apply",  -- Open77.players.restoreHealth (the /heal command)
    "world.vehicles",       -- Open77.vehicles.remove (the /dv command)
    "input.actions",        -- RegisterKeyMapping on the client (replaces IsControlJustReleased)
}
