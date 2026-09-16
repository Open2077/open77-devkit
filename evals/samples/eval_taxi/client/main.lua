-- eval_taxi / client
-- /taxi reads the player's manual map waypoint and asks the server for a ride.
-- The client only *requests*: the server owns the vehicle, the driver and the trip.

RegisterCommand("taxi", function()
    local waypoint, reason = Open77.map.getWaypoint()

    -- nil + reason: the map snapshot is missing/stale (map_unavailable).
    -- nil alone:    the player simply has no waypoint placed.
    if not waypoint then
        TriggerServerEvent("eval_taxi:request", { reason = reason or "no_waypoint" })
        return
    end

    local ok, sendReason = TriggerServerEvent("eval_taxi:request", { position = waypoint.position })
    if not ok then
        print(("[eval_taxi] could not send taxi request: %s"):format(tostring(sendReason)))
    end
end, false, { help = "Call a taxi that drives you to your map waypoint", parameters = {} })
