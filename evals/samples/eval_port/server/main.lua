-- eval_port / server
--
-- The driver-seat warp. FiveM would do TaskWarpPedIntoVehicle on the client;
-- Open77 seats are server-authoritative, so the client only asks and the
-- server calls Open77.vehicles.warpPlayerIntoVehicle for `source`.
--
-- The native itself rejects dead / pending-respawn players (player_unavailable),
-- destroyed vehicles and occupied seats, so no separate life check is needed
-- and no extra permission is granted for one.

local MAX_WARP_DISTANCE = 35.0 -- the client scans 30 m; allow a little drift

local function tell(playerId, ok, reason)
    TriggerClientEvent("eval_port:warpResult", playerId, ok, reason)
end

RegisterNetEvent("eval_port:warpIntoDriverSeat", function(vehicleId)
    -- `source` is the authenticated sender; never read an actor out of the payload.
    local playerId = source
    if type(playerId) ~= "number" or playerId <= 0 then return end

    if type(vehicleId) ~= "number" and type(vehicleId) ~= "string" then
        return tell(playerId, false, "invalid_vehicle")
    end

    -- Forced entry bypasses distance on purpose; re-impose the 30 m rule here so
    -- a tampered client cannot warp into a car across the map. The server-side
    -- `nearby` anchored on the player only sees registered vehicles in the
    -- player's own bucket, which is exactly the set the client menu listed.
    local around, reason = Open77.vehicles.nearby(playerId, MAX_WARP_DISTANCE)
    if not around then
        return tell(playerId, false, reason or "position_unknown")
    end
    local inRange = false
    for _, entry in ipairs(around) do
        if tostring(entry.id) == tostring(vehicleId) then
            inRange = true
            break
        end
    end
    if not inRange then
        return tell(playerId, false, "too_far")
    end

    local ok, warpReason = Open77.vehicles.warpPlayerIntoVehicle(playerId, vehicleId, "driver")
    if not ok then
        print(("eval_port: warp refused for player %s into vehicle %s: %s"):format(
            tostring(playerId), tostring(vehicleId), tostring(warpReason)))
    end
    tell(playerId, ok, warpReason)
end)
