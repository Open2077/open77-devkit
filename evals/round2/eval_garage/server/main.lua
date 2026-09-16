-- eval_garage: a small per-player, in-memory garage (server side only).
--
-- Commands:
--   /park           store the vehicle the caller sits in, then delete it
--   /garage         list the caller's parked vehicles (slot, model)
--   /unpark <slot>  spawn that vehicle again next to the caller and seat them
--
-- Real vehicle records confirmed through open77_data (catalogue "vehicles",
-- game 2.31) so /unpark can be exercised with known models:
--   Vehicle.v_standard2_archer_hella_player   ("Archer Hella", saloon, 4 seats)
--   Vehicle.v_sport1_quadra_turbo_r_player    ("Quadra Turbo R", hypercar, 4 seats)
-- Any car created from those records (for example by another resource's spawn
-- command) can be parked here and brought back.
--
-- Everything is kept in memory: a server restart or a disconnect empties the
-- garage of that player.

local SPAWN_OFFSET_X = 4.0 -- metres beside the caller, as in the create card example

-- garages[playerId] = { { record, appearance, position, heading, props }, ... }
local garages = {}

local function say(playerId, text)
    Open77.chat.send(playerId, text)
end

local function garageOf(playerId)
    local list = garages[playerId]
    if not list then
        list = {}
        garages[playerId] = list
    end
    return list
end

local function shortName(record)
    -- "Vehicle.v_standard2_archer_hella_player" -> "v_standard2_archer_hella_player"
    return (tostring(record):gsub("^Vehicle%.", ""))
end

-- Human wording for the stable seat refusal reasons documented in the
-- vehicles guide ("Authoritative player seats"); anything else is echoed raw.
local SEAT_REASONS = {
    player_unavailable = "you cannot be seated right now (dead or respawning)",
    player_not_found = "the server does not know you as a player",
    vehicle_not_found = "the spawned vehicle vanished before you could be seated",
    vehicle_unavailable = "the spawned vehicle is not usable",
    seat_occupied = "the driver seat is already taken",
    wrong_bucket = "you are in a different routing bucket than the vehicle",
    exit_locked = "you are locked in another vehicle",
}

-- /park -------------------------------------------------------------------

RegisterCommand("park", function(source)
    local playerId = tonumber(source) or 0
    if playerId <= 0 then
        print("[eval_garage] /park needs a player, not the console")
        return
    end

    local seat = Open77.vehicles.getPlayerSeat(playerId)
    if not seat then
        return say(playerId, "Garage: you are not in a vehicle.")
    end

    local car = Open77.vehicles.get(seat.vehicleId)
    if not car then
        return say(playerId, "Garage: your vehicle is not a server vehicle (vehicle_not_found).")
    end
    if car.destroyed or car.exploded then
        return say(playerId, "Garage: this wreck cannot be parked.")
    end

    -- The player's own position, as asked; the car's canonical position when
    -- the player has not reported one yet.
    local me = Open77.players.get(playerId)
    local position = (me and me.position) or car.position
    local heading = (me and me.heading) or car.heading or 0.0
    if not position then
        return say(playerId, "Garage: your position is unknown, try again in a moment.")
    end

    -- Best effort: the full property table (paint, health, damage...) so the
    -- car comes back the way it was. nil, reason is documented; not fatal.
    local props = Open77.vehicles.getProperties(seat.vehicleId)

    local entry = {
        record = car.record,
        appearance = car.appearance,
        position = { x = position.x, y = position.y, z = position.z },
        heading = heading,
        props = props,
    }

    if not Open77.vehicles.remove(seat.vehicleId) then
        return say(playerId, "Garage: the vehicle could not be removed, nothing was parked.")
    end

    local list = garageOf(playerId)
    list[#list + 1] = entry
    say(playerId, ("Garage: %s parked in slot %d."):format(shortName(entry.record), #list))
end, false)

-- /garage -----------------------------------------------------------------

RegisterCommand("garage", function(source)
    local playerId = tonumber(source) or 0
    if playerId <= 0 then
        print("[eval_garage] /garage needs a player, not the console")
        return
    end

    local list = garages[playerId]
    if not list or #list == 0 then
        return say(playerId, "Garage: empty. Sit in a vehicle and use /park.")
    end

    -- Two sends in the same tick arrive in reverse order (chat guide,
    -- "Ordering"), so each line goes out on its own tick.
    say(playerId, ("Garage: %d vehicle(s) parked:"):format(#list))
    Wait(0)
    for slot, entry in ipairs(list) do
        say(playerId, ("  [%d] %s"):format(slot, shortName(entry.record)))
        Wait(0)
    end
    say(playerId, "Use /unpark <slot> to bring one back.")
end, false)

-- /unpark <slot> ----------------------------------------------------------

RegisterCommand("unpark", function(source, args)
    local playerId = tonumber(source) or 0
    if playerId <= 0 then
        print("[eval_garage] /unpark needs a player, not the console")
        return
    end

    local slot = tonumber(args and args[1])
    local list = garages[playerId]
    if not slot or slot ~= math.floor(slot) or slot < 1 then
        return say(playerId, "Garage: usage /unpark <slot>  (see /garage).")
    end
    if not list or not list[slot] then
        return say(playerId, ("Garage: no vehicle in slot %d."):format(slot))
    end
    local entry = list[slot]

    if Open77.vehicles.getPlayerSeat(playerId) then
        return say(playerId, "Garage: leave your current vehicle first.")
    end

    local me = Open77.players.get(playerId)
    if not me or not me.position then
        return say(playerId, "Garage: your position is unknown, try again in a moment.")
    end

    local id, reason = Open77.vehicles.create({
        record = entry.record,
        appearance = entry.appearance,
        position = {
            x = me.position.x + SPAWN_OFFSET_X,
            y = me.position.y,
            z = me.position.z,
        },
        yaw = me.heading or entry.heading or 0.0,
        bucket = me.bucket,
    })
    if not id then
        return say(playerId, ("Garage: spawn refused (%s). The slot is kept."):format(tostring(reason)))
    end

    -- The slot is consumed only once the car exists again.
    table.remove(list, slot)

    -- Restore paint, health, damage... when we managed to capture them.
    if entry.props then
        local ok, why = Open77.vehicles.setProperties(id, entry.props)
        if not ok then
            say(playerId, ("Garage: vehicle restored with default properties (%s)."):format(tostring(why)))
            Wait(0)
        end
    end

    local seated, seatReason = Open77.vehicles.warpPlayerIntoVehicle(playerId, id, "driver", { moveBucket = true })
    if seated then
        say(playerId, ("Garage: %s is back, you are in the driver seat."):format(shortName(entry.record)))
    else
        local why = SEAT_REASONS[seatReason] or tostring(seatReason)
        say(playerId, ("Garage: %s is parked next to you, but %s."):format(shortName(entry.record), why))
    end
end, false)

-- Forget a player's garage when they leave: the list is in memory only.
AddEventHandler("onPlayerDisconnected", function(playerId)
    local key = tonumber(playerId)
    if key then garages[key] = nil end
end)
