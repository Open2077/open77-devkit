-- rp_nomade / client: rings, prompts and intents. Nothing here decides anything.
--
-- * the contracts board: one open77_worldui POI (ring + map pin + E prompt) at the camp;
-- * one POI per crate still on the ground, rebuilt from the server's snapshot;
-- * a ring at the destination while a contract runs;
-- * three E prompts on the rented truck through open77_interactions (globalVehicle target):
--   "Load the crate" / "Unload" / "Return the truck", each gated by a canInteract export that
--   only reads the last snapshot the server pushed (rp_nomade:state).
-- Every prompt sends the smallest intent to the server, which re-checks everything.

local C = RpNomadeConfig
local RESOURCE = GetCurrentResourceName()

local state = nil            -- last snapshot from the server; nil = no contract
local boardHandle = nil
local crateHandles = {}      -- [index] = worldui handle
local destHandle = nil

local NONE = {}
local pending = NONE         -- latest snapshot waiting to be applied (false = clear)

local function log(fmt, ...)
    print(("[rp_nomade] " .. fmt):format(...))
end

local function idKey(v)
    if type(v) == "number" then
        local i = math.tointeger(v)
        if i then return tostring(i) end
    end
    return tostring(v)
end

-- Await a client export of another resource. Yields: managed coroutines only.
local function call(resource, name, ...)
    local promise, reason = Open77.exports.call(resource, name, ...)
    if not promise then return nil, reason end
    local result, err = promise:await()
    if result == nil then return nil, err end
    return result
end

---------------------------------------------------------------------------------------------------
-- canInteract predicates for the truck prompts (synchronous, no yield, no network)
---------------------------------------------------------------------------------------------------

local function isMyTruck(payload)
    if not state or not state.truckId then return false end
    local vid = payload and (payload.vehicleId or (payload.vehicle and payload.vehicle.id))
    return vid ~= nil and idKey(vid) == idKey(state.truckId)
end

exports("canLoad", function(payload)
    return isMyTruck(payload) and state.status == "active" and (state.carrying or 0) > 0
end)

exports("canUnload", function(payload)
    return isMyTruck(payload) and state.status == "active" and state.atDestination == true
        and (state.loaded or 0) > (state.delivered or 0)
end)

exports("canReturn", function(payload)
    return isMyTruck(payload) and state.atCamp == true and (state.carrying or 0) == 0
        and (state.loaded or 0) == (state.delivered or 0)
end)

---------------------------------------------------------------------------------------------------
-- POIs and targets
---------------------------------------------------------------------------------------------------

local function createPoi(def)
    local result, err = call("open77_worldui", "create", def)
    if not result or not result.ok then
        log("POI %s not created: %s", tostring(def.id), tostring(err or (result and result.error)))
        return nil
    end
    return result.handle
end

local function removePoi(handle)
    if handle == nil then return end
    call("open77_worldui", "remove", handle)
end

local function registerTruckPrompts()
    local defs = {
        { id = "rp_nomade_load", label = "Load the crate", description = "Put the crate in the back of the truck.",
          event = "rp_nomade:ui:load", canInteract = "canLoad", icon = "LOAD" },
        { id = "rp_nomade_unload", label = "Unload", description = "Hand the cargo over, one crate at a time.",
          event = "rp_nomade:ui:unload", canInteract = "canUnload", icon = "CARGO" },
        { id = "rp_nomade_return", label = "Return the truck", description = "Give the keys back and get the deposit.",
          event = "rp_nomade:ui:return", canInteract = "canReturn", icon = "KEYS" },
    }
    -- Vehicle targets make open77_interactions poll Open77.world.nearby every 250 ms; unproven
    -- on 2.31 and correlated with heap-corruption crashes (18 Sept). Off until base PR #37.
    if C.Truck.nativePrompts ~= true then defs = {} end
    for _, def in ipairs(defs) do
        local result, err = call("open77_interactions", "addGlobalVehicle", {
            id = def.id,
            distance = C.Truck.reach,
            markerDistance = 30.0,
            marker = "vehicle",
            label = def.label,
            description = def.description,
            key = "E",
            icon = def.icon,
            color = C.Ui.color,
            event = def.event,
            canInteract = def.canInteract,
            maxMatches = 4,
        })
        if not result or not result.ok then
            log("truck prompt %s not registered: %s", def.id, tostring(err or (result and result.error)))
        end
    end
end

local function createBoard()
    local board = C.Camp.board
    boardHandle = createPoi({
        id = "rp_nomade_board",
        position = { x = board.position.x, y = board.position.y, z = board.position.z },
        radius = board.radius,
        style = "interaction",
        maxDistance = 120.0,
        label = board.label,
        description = board.description,
        key = "E",
        color = C.Ui.color,
        promptDistance = board.promptDistance,
        event = "rp_nomade:ui:board",
    })
end

-- Rebuild the crate POIs and the destination ring from a snapshot (or clear them).
local function applyState(snapshot)
    state = snapshot or nil

    local wanted = {}
    if state then
        for _, crate in ipairs(state.crates or {}) do
            if crate.state == "ground" then wanted[crate.index] = crate end
        end
    end
    for index, handle in pairs(crateHandles) do
        if not wanted[index] then
            removePoi(handle)
            crateHandles[index] = nil
        end
    end
    for index, crate in pairs(wanted) do
        if not crateHandles[index] then
            crateHandles[index] = createPoi({
                id = "rp_nomade_crate_" .. index,
                position = { x = crate.x, y = crate.y, z = crate.z },
                radius = C.Crate.ringRadius,
                style = "objective",
                maxDistance = 80.0,
                label = C.Crate.label,
                description = C.Crate.description,
                key = "E",
                color = C.Ui.color,
                promptDistance = C.Crate.promptDistance,
                event = "rp_nomade:ui:crate" .. index,
            })
        end
    end

    local wantDest = state ~= nil and state.status == "active" and state.destination ~= nil
    if wantDest and not destHandle then
        local dest = state.destination
        destHandle = createPoi({
            id = "rp_nomade_destination",
            position = { x = dest.x, y = dest.y, z = dest.z },
            radius = math.min(dest.radius or 10.0, 50.0),
            style = "objective",
            maxDistance = 400.0,
            color = C.Ui.color,
            -- no label: a ring and a map pin only, nothing to press
        })
    elseif not wantDest and destHandle then
        removePoi(destHandle)
        destHandle = nil
    end
end

-- One worker applies snapshots in order; the latest one wins when several arrive at once.
CreateThread(function()
    while true do
        if pending ~= NONE then
            local snapshot = pending
            pending = NONE
            applyState(snapshot)
        end
        Wait(100)
    end
end)

RegisterNetEvent("rp_nomade:state", function(snapshot)
    if snapshot == false or snapshot == nil then
        pending = false
    else
        pending = snapshot
    end
end)

---------------------------------------------------------------------------------------------------
-- Prompt events -> server intents
---------------------------------------------------------------------------------------------------

AddEventHandler("rp_nomade:ui:board", function()
    TriggerServerEvent("rp_nomade:board")
end)

for index = 1, #C.Camp.loadingPoints do
    AddEventHandler("rp_nomade:ui:crate" .. index, function()
        TriggerServerEvent("rp_nomade:pickup", index)
    end)
end

local function vehicleOf(context)
    if type(context) ~= "table" then return nil end
    return context.vehicleId or (context.vehicle and context.vehicle.id)
end

AddEventHandler("rp_nomade:ui:load", function(context)
    TriggerServerEvent("rp_nomade:load", vehicleOf(context))
end)

AddEventHandler("rp_nomade:ui:unload", function(context)
    TriggerServerEvent("rp_nomade:unload", vehicleOf(context))
end)

AddEventHandler("rp_nomade:ui:return", function(context)
    TriggerServerEvent("rp_nomade:return", vehicleOf(context))
end)

---------------------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------------------

AddEventHandler("onClientResourceStart", function(name)
    if name ~= RESOURCE then return end
    CreateThread(function()
        registerTruckPrompts()
        createBoard()
        -- Ask the server for the standing contract (a client reload loses the snapshot).
        TriggerServerEvent("rp_nomade:clientReady")
    end)
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= RESOURCE then return end
    -- open77_worldui and open77_interactions sweep this owner's entries on stop; drop our references.
    boardHandle = nil
    crateHandles = {}
    destHandle = nil
    state = nil
end)
