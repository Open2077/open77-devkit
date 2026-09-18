-- rp_inventory / client: ALT+click actions on other players.
--
-- The client decides nothing. Each action sends the canonical target id to the
-- server, which re-checks distance, life, weight and ownership before moving
-- anything. The /inv menu itself is driven by the server through the UI kit's
-- server twins, so there is nothing to render here.

local RESOURCE = GetCurrentResourceName()

local function menu(method, ...)
    local promise, dispatchError = Open77.exports.call("open77_contextmenu", method, ...)
    if not promise then return nil, dispatchError end
    return promise:await()
end

-- Only another network player: never yourself, never an NPC.
exports("rpInventoryIsOtherPlayer", function(ctx)
    local target = ctx and ctx.target
    if type(target) ~= "table" then return false end
    if target.playerId == nil then return false end
    if target.isLocalPlayer == true then return false end
    return true
end)

exports("rpInventoryGive", function(ctx)
    local target = ctx and ctx.target
    if type(target) ~= "table" or target.playerId == nil then return false end
    TriggerServerEvent("rp_inventory:giveMenu", target.playerId)
    return true
end)

exports("rpInventorySearch", function(ctx)
    local target = ctx and ctx.target
    if type(target) ~= "table" or target.playerId == nil then return false end
    TriggerServerEvent("rp_inventory:search", target.playerId)
    return true
end)

local function registerActions()
    local tokens, err = menu("registerPlayers", {
        {
            id = "rp_inventory_give",
            label = "Give item",
            description = "Hand something from your pockets. The server checks the 3 m and their weight.",
            group = "Inventory",
            icon = "interact",
            networked = true,
            distance = 3.0,
            order = 20,
            canInteract = "rpInventoryIsOtherPlayer",
            onSelect = "rpInventoryGive",
        },
        {
            id = "rp_inventory_search",
            label = "Search pockets",
            description = "Frisk a cuffed or surrendering player.",
            group = "Inventory",
            icon = "person",
            networked = true,
            distance = 3.0,
            order = 21,
            canInteract = "rpInventoryIsOtherPlayer",
            onSelect = "rpInventorySearch",
        },
    })
    if not tokens then
        print("[rp_inventory] context menu registration failed: " .. tostring(err))
        return
    end
    print("[rp_inventory] context menu actions registered")
end

-- Register on our own start and again when the context menu package restarts:
-- a stopped provider loses its registrations.
AddEventHandler("onClientResourceStart", function(name)
    if name == RESOURCE or name == "open77_contextmenu" then
        CreateThread(registerActions)
    end
end)
