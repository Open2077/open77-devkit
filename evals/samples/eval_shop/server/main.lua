-- eval_shop: server side. The catalogue, every price and every wallet live here.
-- The client renders what it is sent and asks to buy an item by id; it never
-- carries a price, and nothing it sends is trusted beyond the item id's shape.

local CATALOG = {
    { id = "maxdoc",      name = "MaxDoc Mk.1",       price = 250 },
    { id = "ammo_pistol", name = "Pistol ammo (x50)", price = 40 },
    { id = "bounceback",  name = "Bounce Back Mk.2",  price = 500 },
}

local ITEMS = {}
for _, item in ipairs(CATALOG) do
    ITEMS[item.id] = item
end

-- In-memory wallet per session. There is no money API on this build, so the
-- resource owns a small ledger; it resets when the player leaves.
local STARTING_BALANCE = 1000
local wallets = {}

local function balanceOf(playerId)
    if wallets[playerId] == nil then
        wallets[playerId] = STARTING_BALANCE
    end
    return wallets[playerId]
end

-- `source` is set from the authenticated connection during a net handler, but
-- the same handler also receives host-wide bus events; only act on a real player.
local function authenticatedSource()
    local playerId = source
    if type(playerId) ~= "number" or playerId <= 0 then
        return nil
    end
    return playerId
end

local function notify(playerId, kind, title, message)
    local id, reason = Open77.notifications.send(playerId, {
        type = kind,
        title = title,
        message = message,
        icon = "E$",
        durationMs = 5000,
        position = "middle_left",
    })
    if not id then
        Open77.log.warn("notification to", playerId, "refused:", tostring(reason))
    end
end

-- The client asks for the catalogue when the shop opens; the answer carries
-- the authoritative prices and the player's balance.
RegisterNetEvent("eval_shop:requestCatalog", function()
    local playerId = authenticatedSource()
    if not playerId then return end
    TriggerClientEvent("eval_shop:catalog", playerId, CATALOG, balanceOf(playerId))
end)

-- A purchase request: only the item id comes from the client. Price and
-- balance are looked up here, at the moment of the write.
RegisterNetEvent("eval_shop:buy", function(itemId)
    local playerId = authenticatedSource()
    if not playerId then return end

    if type(itemId) ~= "string" or #itemId == 0 or #itemId > 64 then
        notify(playerId, "error", "Shop", "Invalid purchase request.")
        return
    end

    local item = ITEMS[itemId]
    if not item then
        Open77.log.warn("player", playerId, "asked for unknown item", itemId)
        notify(playerId, "error", "Shop", "That item is not for sale.")
        return
    end

    local balance = balanceOf(playerId)
    if balance < item.price then
        notify(playerId, "warning", "Not enough eddies",
            ("%s costs %d E$, you have %d E$."):format(item.name, item.price, balance))
        TriggerClientEvent("eval_shop:balance", playerId, balance)
        return
    end

    wallets[playerId] = balance - item.price
    Open77.log.info("player", playerId, "bought", item.id, "for", item.price)

    notify(playerId, "success", "Purchase complete",
        ("Bought %s for %d E$. Balance: %d E$."):format(item.name, item.price, wallets[playerId]))
    TriggerClientEvent("eval_shop:balance", playerId, wallets[playerId])
end)

AddEventHandler("onPlayerDisconnected", function(playerId)
    wallets[playerId] = nil
end)

Open77.log.info("eval_shop started with", #CATALOG, "items")
