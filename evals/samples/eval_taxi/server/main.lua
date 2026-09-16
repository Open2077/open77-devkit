-- eval_taxi / server
-- Spawns a server-owned taxi next to the requesting player, seats them, and lets the
-- networked vehicle AI drive to the waypoint the client reported.

-- The Hella is the record the vehicle AI was validated with (vehicle-ai guide).
local TAXI_RECORD        = "Vehicle.v_standard2_archer_hella_player"
local TAXI_SEAT          = "frontPassenger"   -- driver seat is reserved by the AI controller
local SPAWN_OFFSET_M     = 6.0                -- metres from the player, as in the create() card
local SETTLE_MS          = 3000               -- let the spawn/mount settle before driveTo
local RIDE_SPEED_MPS     = 12                 -- 0.5..55
local ARRIVAL_RADIUS_M   = 5                  -- 1..20
local RIDE_TIMEOUT_MS    = 10 * 60 * 1000     -- 1000..3600000
local TAXI_TTL_MS        = 20 * 60 * 1000     -- safety net: the car goes away on its own
local LINGER_MS          = 10000              -- how long the cab stays after the ride ends
local COORD_LIMIT        = 16000              -- driveTo: coordinates must be finite, within ±16000

local rides          = {}   -- playerId -> { vehicleId = integer }
local ridesByVehicle = {}   -- tostring(vehicleId) -> playerId  (AI states carry string ids)

local function say(playerId, text)
    Open77.chat.send(playerId, {
        author = "Delamain",
        text   = text,
        color  = { r = 255, g = 200, b = 0 },
    })
end

local function isBoundedNumber(v)
    return type(v) == "number" and v == v and v > -COORD_LIMIT and v < COORD_LIMIT
end

-- Ends a ride and disposes of the taxi. `ejectPlayer` is false when the player is gone.
local function finishRide(playerId, ejectPlayer)
    local ride = rides[playerId]
    if not ride then return end
    rides[playerId] = nil
    ridesByVehicle[tostring(ride.vehicleId)] = nil

    Open77.vehicles.ai.removeDriver(ride.vehicleId)

    if ejectPlayer then
        local ok, reason = Open77.vehicles.forcePlayerOutOfVehicle(playerId, ride.vehicleId)
        if not ok then
            print(("[eval_taxi] could not eject player %d: %s"):format(playerId, tostring(reason)))
        end
        SetTimeout(LINGER_MS, function()
            Open77.vehicles.remove(ride.vehicleId)
        end)
    else
        Open77.vehicles.remove(ride.vehicleId)
    end
end

RegisterNetEvent("eval_taxi:request", function(request)
    local playerId = source   -- authenticated by Open77, never taken from the payload

    if type(request) ~= "table" then return end

    if request.reason == "no_waypoint" then
        return say(playerId, "Place a waypoint on your map first, then type /taxi.")
    elseif request.reason then
        return say(playerId, "Your map is not ready (" .. tostring(request.reason) .. "). Try again.")
    end

    local destination = request.position
    if type(destination) ~= "table"
        or not isBoundedNumber(destination.x)
        or not isBoundedNumber(destination.y)
        or not isBoundedNumber(destination.z) then
        return say(playerId, "That destination is not valid.")
    end

    if rides[playerId] then
        return say(playerId, "You already have a taxi. Finish that ride first.")
    end

    -- Never seat a player who is not alive.
    if Open77.players.isDead(playerId) then
        return say(playerId, "Delamain does not pick up corpses.")
    end

    if Open77.vehicles.getPlayerSeat(playerId) then
        return say(playerId, "Get out of your current vehicle first.")
    end

    local me, readReason = Open77.players.get(playerId)
    if not me or not me.position then
        return say(playerId, "Could not locate you (" .. tostring(readReason or "no_position") .. ").")
    end

    local vehicleId, createReason = Open77.vehicles.create({
        record   = TAXI_RECORD,
        position = { x = me.position.x + SPAWN_OFFSET_M, y = me.position.y, z = me.position.z },
        yaw      = me.heading,
        bucket   = me.bucket,
        ttlMs    = TAXI_TTL_MS,
    })
    if not vehicleId then
        return say(playerId, "No taxi available: " .. tostring(createReason))
    end

    -- Driverless AI: the driver seat is reserved, no NPC needed.
    local aiState, aiReason = Open77.vehicles.ai.attachDriver(vehicleId)
    if not aiState then
        Open77.vehicles.remove(vehicleId)
        return say(playerId, "The taxi has no driver: " .. tostring(aiReason))
    end

    -- Animated entry with a guaranteed warp fallback; same refusals as warpPlayerIntoVehicle.
    local seated, seatReason = Open77.vehicles.taskPlayerEnter(playerId, vehicleId, TAXI_SEAT, {
        moveBucket = true,
        exitLocked = false,
    })
    if not seated then
        Open77.vehicles.ai.removeDriver(vehicleId)
        Open77.vehicles.remove(vehicleId)
        return say(playerId, "Could not board the taxi: " .. tostring(seatReason))
    end

    rides[playerId] = { vehicleId = vehicleId }
    ridesByVehicle[tostring(vehicleId)] = playerId
    say(playerId, "Your Delamain is here. Boarding...")

    -- Allow the spawn/mount to settle before issuing the destination (vehicle-ai guide).
    SetTimeout(SETTLE_MS, function()
        local ride = rides[playerId]
        if not ride or ride.vehicleId ~= vehicleId then return end

        local task, driveReason = Open77.vehicles.ai.driveTo(vehicleId, {
            position            = { x = destination.x, y = destination.y, z = destination.z },
            speed               = RIDE_SPEED_MPS,
            arrivalRadius       = ARRIVAL_RADIUS_M,
            timeoutMilliseconds = RIDE_TIMEOUT_MS,
            behavior            = "normal",
        })
        if not task then
            print(("[eval_taxi] ride %s for player %d: driveTo refused (%s)"):format(tostring(vehicleId), playerId, tostring(driveReason)))
            say(playerId, "The taxi cannot reach that destination: " .. tostring(driveReason))
            return finishRide(playerId, true)
        end
        print(("[eval_taxi] ride %s for player %d: driving to %.1f,%.1f,%.1f"):format(tostring(vehicleId), playerId, destination.x, destination.y, destination.z))
        say(playerId, "Sit back. Heading to your waypoint.")
    end)
end)

-- Acceptance is not arrival: the trip ends on one of these events.
Open77.vehicles.ai.on("arrived", function(state)
    local playerId = ridesByVehicle[tostring(state.vehicleId)]
    if not playerId then return end
    print(("[eval_taxi] ride %s for player %d: arrived"):format(tostring(state.vehicleId), playerId))
    say(playerId, "You have arrived. Thank you for riding Delamain.")
    finishRide(playerId, true)
end)

Open77.vehicles.ai.on("failed", function(state)
    local playerId = ridesByVehicle[tostring(state.vehicleId)]
    if not playerId then return end
    print(("[eval_taxi] ride %s for player %d: failed (%s)"):format(tostring(state.vehicleId), playerId, tostring(state.reason)))
    say(playerId, "The ride was aborted (" .. tostring(state.reason) .. ").")
    finishRide(playerId, true)
end)

Open77.vehicles.ai.on("cancelled", function(state)
    local playerId = ridesByVehicle[tostring(state.vehicleId)]
    if not playerId then return end
    print(("[eval_taxi] ride %s for player %d: cancelled"):format(tostring(state.vehicleId), playerId))
    say(playerId, "The ride was cancelled.")
    finishRide(playerId, true)
end)

Open77.vehicles.ai.on("blocked", function(state)
    local playerId = ridesByVehicle[tostring(state.vehicleId)]
    if not playerId then return end
    say(playerId, "Traffic ahead, please be patient.")
end)

Open77.vehicles.ai.on("resumed", function(state)
    local playerId = ridesByVehicle[tostring(state.vehicleId)]
    if not playerId then return end
    say(playerId, "Moving again.")
end)

-- A passenger who leaves the server takes their taxi with them.
AddEventHandler("onPlayerDisconnected", function(playerId)
    finishRide(playerId, false)
end)
