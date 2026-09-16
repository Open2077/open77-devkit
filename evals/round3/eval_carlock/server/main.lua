-- eval_carlock -- server side only.
--
--   /lock    toggle the entry lock of the vehicle the caller sits in
--   /whosin  list the occupants of the caller's vehicle, seat by seat
--
-- Everything below is written from the Open77 devkit MCP alone
-- (answering for build 2.31.13+op77.75).

local RESOURCE_TAG = "[eval_carlock]"

-- Vehicles this resource locked, keyed by the vehicle id as a string.
-- Event arguments arrive as strings on the server, while getPlayerSeat
-- answers an integer, so both are normalised through vehicleKey().
local lockedByUs = {}

local function vehicleKey(id)
    local n = tonumber(id)
    if n == nil then return tostring(id) end
    return tostring(n)
end

local function log(fmt, ...)
    print(("%s %s"):format(RESOURCE_TAG, fmt:format(...)))
end

-- Chat delivery can itself fail (invalid_chat_message, invalid_chat_target);
-- a console caller (source 0) gets the line printed instead.
local function tell(source, text)
    if source == nil or source == 0 then
        log("%s", text)
        return
    end
    local ok, reason = Open77.chat.send(source, text)
    if not ok then
        log("chat.send to %s failed: %s -- %s", tostring(source), tostring(reason), text)
    end
end

-- Display name, never nil: players.name answers nil for a departed session.
local function nameOf(playerId)
    local name = Open77.players.name(playerId)
    if name == nil or name == "" then
        return ("player #%s"):format(tostring(playerId))
    end
    return name
end

-- --------------------------------------------------------------------------
-- Vehicle flag bits.
--
-- The MCP documents a public constant table `Open77.vehicles.flags`
-- (engineOn = 1, locked = 2, destroyed = 4, exploded = 8, invulnerable = 16,
-- immortal = 32, lightsOn = 64, highBeams = 128, sirenOn = 256,
-- paintApplied = 512) but marks it NOT AVAILABLE on build 2.31.13+op77.75.
-- The same values are documented in the guides
-- `vehicles#entry-lock-and-synchronized-horn` and
-- `data-reference#vehicle-seats-doors-windows-and-state-bits`, so the table
-- is used when the runtime has it and the documented values otherwise.
-- --------------------------------------------------------------------------
local DOCUMENTED_FLAGS = {
    engineOn = 1, locked = 2, destroyed = 4, exploded = 8,
    invulnerable = 16, immortal = 32, lightsOn = 64, highBeams = 128,
    sirenOn = 256, paintApplied = 512,
}

local function vehicleFlagBits()
    local ok, t = pcall(function() return Open77.vehicles.flags end)
    if ok and type(t) == "table" and type(t.locked) == "number" then
        return t, "Open77.vehicles.flags"
    end
    return DOCUMENTED_FLAGS, "documented values (constant table absent on this build)"
end

local FLAGS, FLAGS_SOURCE = vehicleFlagBits()

-- Reads the locked state from the snapshot's `flags` integer. Returns nil
-- when the snapshot carries no usable flags field.
local function lockedFromFlags(snapshot)
    if snapshot == nil then return nil end
    local flags = tonumber(snapshot.flags)
    if flags == nil then return nil end
    -- Lua 5.4 bitwise operators accept an integral float and raise on
    -- anything else; the pcall turns that raise into "unknown".
    local ok, locked = pcall(function() return (flags & FLAGS.locked) ~= 0 end)
    if not ok then return nil end
    return locked
end

-- --------------------------------------------------------------------------
-- Seats. Canonical names come from the MCP's data reference; the order is
-- the one freeSeats() documents (driver, frontPassenger, rearLeft, rearRight).
-- `Open77.vehicles.seats` (driver = -1 ...) is documented but NOT AVAILABLE
-- on this build, so the seats are named by their documented aliases and
-- resolved through Open77.vehicles.seatName, which needs no permission.
-- --------------------------------------------------------------------------
local SEAT_ORDER = { "driver", "frontPassenger", "rearLeft", "rearRight" }
local SEAT_LABEL = {
    driver = "Driver",
    frontPassenger = "Front passenger",
    rearLeft = "Rear left",
    rearRight = "Rear right",
}

-- Failure messages for the lock natives' documented reasons.
local LOCK_FAILURE = {
    invalid_argument = "The vehicle id was refused as invalid.",
    ["permission_denied:world.vehicles"] = "This resource lacks the world.vehicles permission.",
    vehicle_not_found = "That vehicle no longer exists.",
    vehicles_unavailable = "The vehicle service is unavailable right now.",
}

local SEAT_FAILURE = {
    invalid_seat = "the seat name was refused",
    vehicle_not_found = "the vehicle no longer exists",
}

-- Resolves the caller's vehicle. Returns vehicleId, assignment or nil, message.
local function callerVehicle(source)
    if source == nil or source == 0 then
        return nil, nil, "This command must be run by a player seated in a vehicle."
    end
    local seat = Open77.vehicles.getPlayerSeat(source)
    if seat == nil then
        return nil, nil, "You are not in a vehicle."
    end
    local vehicleId = seat.vehicleId
    if vehicleId == nil then
        return nil, nil, "Your seat assignment carries no vehicle id."
    end
    return vehicleId, seat, nil
end

-- --------------------------------------------------------------------------
-- /lock
-- --------------------------------------------------------------------------
RegisterCommand("lock", function(source, args, raw)
    local vehicleId, seat, why = callerVehicle(source)
    if vehicleId == nil then
        return tell(source, why)
    end

    local car = Open77.vehicles.get(vehicleId)
    if car == nil then
        return tell(source, "Your vehicle could not be read (unknown id).")
    end

    -- Current state, from the snapshot's flags bits first; the derived
    -- `locked` boolean and isLocked() are fallbacks in case the snapshot
    -- carries no flags field.
    local currentlyLocked = lockedFromFlags(car)
    if currentlyLocked == nil then
        if type(car.locked) == "boolean" then
            currentlyLocked = car.locked
        else
            currentlyLocked = Open77.vehicles.isLocked(vehicleId)
        end
    end
    if currentlyLocked == nil then
        return tell(source, "The lock state of your vehicle could not be determined.")
    end

    local wantLocked = not currentlyLocked
    local ok, reason = Open77.vehicles.setLocked(vehicleId, wantLocked)
    if not ok then
        local msg = LOCK_FAILURE[reason] or ("Lock change refused: " .. tostring(reason))
        log("setLocked(%s, %s) by %s failed: %s", vehicleKey(vehicleId), tostring(wantLocked),
            nameOf(source), tostring(reason))
        return tell(source, msg)
    end

    local key = vehicleKey(vehicleId)
    if wantLocked then
        lockedByUs[key] = { by = source, at = Open77.time.unix() }
    else
        lockedByUs[key] = nil
    end

    -- Report the state the server now holds, not the one we asked for.
    local after = Open77.vehicles.isLocked(vehicleId)
    if after == nil then after = wantLocked end
    tell(source, ("Vehicle %s is now %s."):format(key, after and "locked" or "unlocked"))
    log("%s %s vehicle %s from seat %s (flags read via %s)", nameOf(source),
        after and "locked" or "unlocked", key, tostring(seat.seat), FLAGS_SOURCE)
end, false)

-- --------------------------------------------------------------------------
-- /whosin
-- --------------------------------------------------------------------------
RegisterCommand("whosin", function(source, args, raw)
    local vehicleId, seat, why = callerVehicle(source)
    if vehicleId == nil then
        return tell(source, why)
    end

    tell(source, ("Occupants of vehicle %s:"):format(vehicleKey(vehicleId)))
    Wait(0) -- chat sends in one tick arrive in reverse order; keep the header first

    for _, alias in ipairs(SEAT_ORDER) do
        local canonical = Open77.vehicles.seatName(alias) or alias
        local label = SEAT_LABEL[alias] or alias

        -- occupantInSeat answers: playerId, occupantRecord
        --                     or: nil               (seat free)
        --                     or: nil, reason       (invalid_seat, vehicle_not_found)
        local occupant, extra = Open77.vehicles.occupantInSeat(vehicleId, alias)
        local line
        if occupant == nil then
            if type(extra) == "string" then
                line = ("%s (%s): unreadable, %s"):format(label, canonical,
                    SEAT_FAILURE[extra] or tostring(extra))
                if extra == "vehicle_not_found" then
                    tell(source, line)
                    return
                end
            else
                line = ("%s (%s): empty"):format(label, canonical)
            end
        else
            local state = ""
            if type(extra) == "table" then
                if extra.entering then state = " (entering)" end
                if extra.exiting then state = " (exiting)" end
            end
            local who = nameOf(occupant)
            if tostring(occupant) == tostring(source) then who = who .. " (you)" end
            line = ("%s (%s): %s%s"):format(label, canonical, who, state)
        end
        tell(source, line)
        -- Two sends in the same tick can arrive out of order; keep the list readable.
        Wait(0)
    end
end, false)

-- --------------------------------------------------------------------------
-- A player left a vehicle. onPlayerLeftVehicle(playerId, vehicleId, seat)
-- is the derived, reserved platform event; arguments arrive as strings.
-- --------------------------------------------------------------------------
AddEventHandler("onPlayerLeftVehicle", function(playerId, vehicleId, seat)
    if vehicleId == nil then return end
    local key = vehicleKey(vehicleId)
    local entry = lockedByUs[key]
    if entry == nil then return end
    log("%s left vehicle %s (seat %s) -- that vehicle was locked by this resource (by %s)",
        nameOf(playerId), key, tostring(seat), nameOf(entry.by))
end)

-- Forget vehicles that are gone so the table does not grow forever.
AddEventHandler("onVehicleRemoved", function(id, reason)
    if id == nil then return end
    local key = vehicleKey(id)
    if lockedByUs[key] ~= nil then
        lockedByUs[key] = nil
        log("vehicle %s removed (%s); it was locked by this resource", key, tostring(reason))
    end
end)

AddEventHandler("onResourceStart", function(name)
    if name ~= Open77.resource.name() then return end
    log("started; vehicle flag bits from %s (locked = %d)", FLAGS_SOURCE, FLAGS.locked)
end)
