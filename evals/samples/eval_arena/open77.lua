-- eval_arena: last-player-standing arena. /arena moves the player into a private routing
-- bucket with a fixed loadout; the round goes live when enough players are in, ends when one
-- player is left alive, announces the winner in chat and returns everyone to the main bucket.
-- Server-authoritative, built on the conventions of the shipped deathmatch mode.
resource "eval_arena"
version "1.0.0"
auto_start true

-- network.events        server: TriggerClientEvent (toasts), Open77.weapons.clear (relay)
--                       client: RegisterNetEvent
-- players.life.read     server: Open77.players.getLifeState / isDead (who is alive)
-- players.life.respawn  server: Open77.players.respawn (a dead loser back to the main bucket)
-- players.stats.apply   server: Open77.players.setGodMode (pre-round / spawn protection),
--                               Open77.players.restoreHealth
-- players.teleport      server: Open77.players.teleport (its card: "Requires players.teleport";
--                               the permission is server-enforced, the catalogue lists no native)
-- ui.vanilla.hud        client: Open77.hud.notify
permissions {
    "network.events",
    "players.life.read",
    "players.life.respawn",
    "players.stats.apply",
    "players.teleport",
    "ui.vanilla.hud",
}

-- Open77.weapons.* on the server is a relay to the official client package.
dependency "open77_weapons"

shared_script "shared/config.lua"
server_script "server/main.lua"
client_script "client/main.lua"
