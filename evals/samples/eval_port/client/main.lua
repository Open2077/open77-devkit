-- eval_port / client
--
-- FiveM original:
--   RegisterCommand('cars', ...) -> PlayerPedId / GetEntityCoords /
--   GetGamePool('CVehicle') / GetEntityModel / GetDisplayNameFromVehicleModel
--
-- Open77 port:
--   Open77.vehicles.nearby(30)        replaces the GetGamePool + GetEntityCoords
--                                     distance loop (centred on the local player,
--                                     nearest first, distance already computed)
--   Open77.data.vehicle(record)       replaces GetEntityModel +
--                                     GetDisplayNameFromVehicleModel (a record is
--                                     a TweakDB string, not a hash)
--   open77_uikit `menu` / `showMenu`  the list the player picks from
--   TriggerServerEvent                the driver-seat warp is server authoritative

local SCAN_RADIUS = 30.0
local MENU_ID = "eval_port_cars"
local MAX_LABEL = 80 -- uikit refuses longer option labels (invalid_option_label)

local menuOpen = false

-- Display name from the live TweakDB, falling back to the record string when the
-- engine does not expose one (an absent field means "not exposed", not "unknown").
local function vehicleLabel(record)
    local data = Open77.data.vehicle(record)
    if data and type(data.displayName) == "string" and data.displayName ~= "" then
        return data.displayName
    end
    return record
end

local function notify(text)
    local ok, reason = Open77.hud.notify(text)
    if not ok then print("eval_port: notify failed: " .. tostring(reason)) end
end

local function openCarsMenu()
    if menuOpen then return end

    local cars, reason = Open77.vehicles.nearby(SCAN_RADIUS)
    if not cars then
        print("eval_port: nearby failed: " .. tostring(reason))
        return
    end
    if #cars == 0 then
        notify(("No vehicles within %d m"):format(SCAN_RADIUS))
        return
    end

    -- The original printed each name; keep that, and build the menu rows from
    -- the same list. Option ids map back to the canonical vehicle id.
    local options, vehicleByOption = {}, {}
    for _, car in ipairs(cars) do
        local name = vehicleLabel(car.record)
        print(name)

        local optionId = "veh_" .. tostring(car.id)
        local label = ("%s  (%.0f m)"):format(name, car.distance)
        if #label > MAX_LABEL then label = label:sub(1, MAX_LABEL) end
        if car.occupants and car.occupants > 0 then
            label = label:sub(1, MAX_LABEL - 4) .. " [+]"
        end

        options[#options + 1] = { id = optionId, label = label }
        vehicleByOption[optionId] = car.id
    end

    -- `await` needs a scheduler coroutine, so the dialog runs inside a thread.
    CreateThread(function()
        menuOpen = true

        local registered, regReason = Open77.exports.call("open77_uikit", "menu", {
            id = MENU_ID,
            title = "Nearby vehicles",
            options = options,
        })
        if not registered then
            menuOpen = false
            print("eval_port: uikit menu refused: " .. tostring(regReason))
            return
        end
        registered:await()

        local pending, showReason = Open77.exports.call("open77_uikit", "showMenu", MENU_ID)
        if not pending then
            menuOpen = false
            print("eval_port: uikit showMenu refused: " .. tostring(showReason))
            return
        end

        local answer = pending:await()
        menuOpen = false

        -- Escape / timeout resolve with ok = false; that is the player changing
        -- their mind, not an error.
        if not answer or not answer.ok or not answer.value then return end

        local vehicleId = vehicleByOption[answer.value.id]
        if vehicleId == nil then return end

        -- The server owns seats: ask, never assign locally.
        TriggerServerEvent("eval_port:warpIntoDriverSeat", vehicleId)
    end)
end

-- The original was a chat command; the port keeps it and adds a rebindable key.
RegisterCommand("cars", function()
    openCarsMenu()
end, false, { help = "List the vehicles nearby and warp into one." })

local mapped, mapReason = RegisterKeyMapping("eval_port_cars", "Nearby vehicles menu", "F6", function()
    openCarsMenu()
end)
if not mapped then
    print("eval_port: key mapping refused: " .. tostring(mapReason))
end

-- Server verdict on the warp request.
RegisterNetEvent("eval_port:warpResult", function(ok, reason)
    if ok then
        notify("Warped into the driver seat")
    else
        notify("Could not enter the vehicle: " .. tostring(reason))
    end
end)
