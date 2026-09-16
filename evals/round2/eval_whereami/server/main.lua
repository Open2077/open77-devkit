-- eval_whereami (server): /whereami answers the caller in chat with their
-- world position and whether they sit in a vehicle (and which model).

local function describeVehicle(playerId)
    -- Canonical seat ledger; nil when the player is not assigned to a vehicle.
    local seat = Open77.players.getVehicleSeat(playerId)
    if not seat then
        return "on foot"
    end
    local model = "unknown model"
    local car = Open77.vehicles.get(seat.vehicleId)
    if car and car.record then
        model = car.record
    end
    return ("in vehicle #%s (%s), seat %s"):format(
        tostring(seat.vehicleId), model, tostring(seat.seat))
end

RegisterCommand("whereami", function(source, args, raw)
    if source == 0 then
        print("/whereami is a player command; the console has no position.")
        return
    end

    local read = Open77.players.get(source)
    if not read or not read.position then
        Open77.chat.send(source, "whereami: your position is not known yet.")
        return
    end

    local p = read.position
    local line = ("whereami: x=%.2f y=%.2f z=%.2f (bucket %s, %s ms old) - %s"):format(
        p.x, p.y, p.z, tostring(read.bucket), tostring(read.ageMs or 0), describeVehicle(source))
    Open77.chat.send(source, line)
end, false)

-- Advertise the command in the chat composer's completion list for everyone.
Open77.chat.addSuggestion(-1, "/whereami", "Show your world position and vehicle state")
