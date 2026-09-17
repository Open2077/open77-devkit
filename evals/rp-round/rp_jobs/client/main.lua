-- rp_jobs client -- renders the delivery waypoint the server asks for.
--
-- Open77.blips is a client-only API, so the server relays the next delivery
-- point through a net event and this script only draws it. Nothing here is
-- authoritative: arrival, payment and the vehicle are decided on the server.

RegisterNetEvent("rp_jobs:waypoint", function(position)
    if type(position) ~= "table" or type(position.x) ~= "number"
        or type(position.y) ~= "number" or type(position.z) ~= "number" then
        return
    end
    local ok, reason = Open77.blips.setWaypoint({ x = position.x, y = position.y, z = position.z })
    if not ok then
        print("[rp_jobs] client waypoint refused: " .. tostring(reason))
    end
end)

RegisterNetEvent("rp_jobs:waypointClear", function()
    -- Success is `true, wasSet`; the card does not say where the reason sits on failure.
    local ok, second, third = Open77.blips.clearWaypoint()
    if not ok then
        print("[rp_jobs] client waypoint clear refused: " .. tostring(third or second))
    end
end)
