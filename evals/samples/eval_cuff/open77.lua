resource "eval_cuff"
version "1.0.0"
auto_start true

-- network.events              server: TriggerClientEvent / RegisterNetEvent
--                             client: RegisterNetEvent / TriggerServerEvent
-- players.life.read           server: Open77.players.getLifeState (refuse a target who is not alive)
-- players.life.freeze         server: Open77.players.setFrozen (the hold under /cuff)
-- players.teleport            server: Open77.players.teleport (the escort tether pull)
-- players.animations.control  server: Open77.animations.play / stop (the handsup pose)
-- input.actions               client: Open77.input.setActionBlocked (Map and Hub by name)
--                             client: Open77.input.blockAll carries no permission on this build
--                                     (`input.blockAll` is not a name the op77.69 runtime enforces)
permissions {
    "network.events",
    "players.life.read",
    "players.life.freeze",
    "players.teleport",
    "players.animations.control",
    "input.actions",
}

client_script "client/main.lua"
server_script "server/main.lua"
