-- eval_port2 / server.lua
-- Port of the FiveM server.lua. Every FiveM line that could NOT be ported one-to-one,
-- and what the Open77 devkit MCP (answering for build 2.31.13+op77.75) said about it:
--
--   GetPlayerPed(source)
--     ABSENT. open77_fivem_equivalent: "not in the FiveM alias table", closest hits were
--     Open77.character.* CLIENT reads (frame/forward/isInVehicle...). Open77 has no ped
--     handle on the server: every Open77.players.* / Open77.vehicles.* call takes the
--     session player id, so `source` is used directly and the ped variable is gone.
--
--   SetEntityHealth(ped, 200)
--     ABSENT. open77_fivem_equivalent returned an EMPTY match list. Replaced with
--     Open77.players.restoreHealth(playerId) ("Fills a player's health pool ... to the
--     canonical maximum without reviving a dead player"), permission players.stats.apply.
--     Behaviour difference: FiveM's 200 is "full"; here full is whatever the canonical
--     maximum is, and a dead player is NOT revived (FiveM would set health on a dead ped).
--     NOTE: the heal/setHealth cards say "Requires players.damage.apply" in their prose, but
--     open77_permissions says that permission does not exist; the cards' permission field
--     and the permission index both say players.stats.apply, which is what is declared.
--
--   GetVehiclePedIsIn(ped, false)
--     ABSENT. open77_fivem_equivalent returned an EMPTY match list. Replaced with
--     Open77.vehicles.getPlayerSeat(playerId) (server card: "returns nil when the player is
--     not assigned to a vehicle"; the table carries .vehicleId). Behaviour difference:
--     this is the server's CANONICAL seat ledger, so a vanilla car the player drove into
--     that was never adopted into the registry answers nil -> "Not in a vehicle".
--
--   DeleteEntity(veh)
--     ABSENT. open77_fivem_equivalent returned an EMPTY match list. Replaced with
--     Open77.vehicles.remove(id) ("Removes a server-authoritative network vehicle",
--     permission world.vehicles). Same limitation as above: only canonical vehicles.
--
--   TriggerClientEvent('chat:addMessage', source, { args = { '^2Healed' } })
--     DIFFERENT MODEL. The MCP documents chat:addMessage only as a host-wide bus event that
--     the open77_chat authority consumes, and Open77.chat.send(playerId, message) as the
--     facade over it (no permission needed). The FiveM { args = {...} } payload and the
--     ^2 colour code are NOT documented anywhere for chat (the fivem-compatibility guide
--     only says ^N codes are stripped from LOG output). The message table documented on
--     the card is { type, author, text, playerId, color = { r, g, b } }, so the green
--     "^2Healed" became text + a color table.
--
--   os.time()
--     ABSENT. The sandbox has no `os` library (fivem-compatibility guide + Open77.time.unix
--     card). Replaced with math.floor(Open77.time.unix()) -- wall-clock seconds since 1970
--     UTC, fractional, floored to keep os.time()'s integer shape.
--
--   RegisterNetEvent + AddEventHandler (two-step FiveM idiom)
--     DIFFERENT MODEL on the server. The server RegisterNetEvent card says: "Called with the
--     name alone it only marks the name as reachable ... and registers nothing", and that
--     `source` is set inside ITS handler, "that is the whole difference from AddEventHandler".
--     The AddEventHandler card lists the sources it serves (local, host-wide bus, lifecycle)
--     without mentioning net events, so the handler was moved into RegisterNetEvent itself.
--
--   RegisterCommand(name, fn, false)   -> EQUIVALENT, same signature (source, args, raw).
--   TriggerClientEvent(name, id, ...)  -> EQUIVALENT (same function as Open77.net.emitClient).

RegisterCommand('heal', function(source, args)
    -- FiveM: GetPlayerPed(source) + SetEntityHealth(ped, 200)
    Open77.players.restoreHealth(source)
    -- FiveM: chat:addMessage { args = { '^2Healed' } }
    Open77.chat.send(source, {
        type = "system",
        text = "Healed",
        color = { r = 0, g = 255, b = 0 },
    })
end, false)

RegisterCommand('dv', function(source, args)
    -- FiveM: GetVehiclePedIsIn(GetPlayerPed(source), false) ~= 0
    local seat = Open77.vehicles.getPlayerSeat(source)
    if seat then
        -- FiveM: DeleteEntity(veh)
        Open77.vehicles.remove(seat.vehicleId)
        Open77.chat.send(source, "Vehicle deleted")
    else
        Open77.chat.send(source, "Not in a vehicle")
    end
end, false)

-- FiveM: RegisterNetEvent('port2:ping') + AddEventHandler('port2:ping', fn)
RegisterNetEvent('port2:ping', function()
    -- FiveM: os.time()
    TriggerClientEvent('port2:pong', source, math.floor(Open77.time.unix()))
end)
