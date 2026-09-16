-- eval_whereami (client): F9 prints the local player's position and vehicle
-- state to the Open77 client log (resource-prefixed).

local function report()
    local x, y, z = Open77.character.position()
    if not x then
        print("whereami: position unavailable")
        return
    end

    local vehicleText
    local inVehicle, reason = Open77.players.isInVehicle()
    if inVehicle == true then
        vehicleText = "in a vehicle"
        local seat = Open77.vehicles.getPlayerSeat()
        if seat then
            local car = Open77.vehicles.get(seat.vehicleId)
            local model = (car and car.record) or "unknown model"
            vehicleText = ("in vehicle #%s (%s), seat %s"):format(
                tostring(seat.vehicleId), model, tostring(seat.seat))
        end
    elseif inVehicle == false then
        vehicleText = "on foot"
    else
        vehicleText = "vehicle state unavailable (" .. tostring(reason) .. ")"
    end

    print(("whereami: x=%.2f y=%.2f z=%.2f - %s"):format(x, y, z, vehicleText))
end

-- Positional form: (id, name, defaultKey, onPressed). Rebindable from the pause menu.
local ok, detail = RegisterKeyMapping("whereami", "Print my position", "F9", function()
    report()
end)
if ok == false then
    print("whereami: key mapping refused: " .. tostring(detail))
else
    print("whereami: bound to " .. tostring(detail or ok))
end
