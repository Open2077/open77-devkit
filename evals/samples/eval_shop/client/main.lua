-- eval_shop: client side. Renders the shop page and forwards requests to the
-- server. It never knows a price it did not receive from the server.

local RESOURCE = GetCurrentResourceName()

local page = nil        -- the WebUI surface, created hidden on start
local isOpen = false

local function requestCatalog()
    local ok, reason = TriggerServerEvent("eval_shop:requestCatalog")
    if not ok then
        Open77.log.warn("catalog request failed: " .. tostring(reason))
    end
end

local function openShop()
    if not page or isOpen then return end
    isOpen = true
    page:show()
    page:setFocus(true, true)   -- keyboard (Escape / F6 to close) and cursor
    requestCatalog()
end

local function closeShop()
    if not page or not isOpen then return end
    isOpen = false
    page:setFocus(false, false) -- hand keyboard and cursor back to the game
    page:hide()
end

local function toggleShop()
    if isOpen then closeShop() else openShop() end
end

AddEventHandler("onClientResourceStart", function(name)
    if name ~= RESOURCE then return end

    -- Created hidden: show() runs later, on the key press, so it cannot race
    -- the `visible` flag the create request carried.
    local surface, reason = Open77.webui.create({
        entry = "web/index.html",
        layer = "menu",
        transparent = true,
        visible = false,
    })
    if not surface then
        Open77.log.error("shop page unavailable: " .. tostring(reason))
        return
    end
    page = surface

    -- The page asks for the catalogue once its document is ready, so an open
    -- that raced the document load still ends up populated.
    page:on("ready", function()
        if isOpen then requestCatalog() end
    end)

    -- The page sends only the item id. The server looks the price up itself.
    page:on("buy", function(payload)
        if type(payload) ~= "table" or type(payload.id) ~= "string" then
            Open77.log.warn("ignoring malformed buy request from the page")
            return
        end
        local ok, why = TriggerServerEvent("eval_shop:buy", payload.id)
        if not ok then
            Open77.log.warn("purchase request failed: " .. tostring(why))
        end
    end)

    page:on("close", function()
        closeShop()
    end)

    -- Rebindable from Pause -> Settings -> KEY BINDINGS; F6 by default.
    local key, why = RegisterKeyMapping("eval_shop_toggle", "Open the shop", "F6", function()
        toggleShop()
    end)
    if not key then
        Open77.log.error("shop key mapping refused: " .. tostring(why))
    end
end)

-- Server -> client: the authoritative catalogue (items with prices) and balance.
RegisterNetEvent("eval_shop:catalog", function(items, balance)
    if not page then return end
    local ok, reason = page:send("catalog", { items = items, balance = balance })
    if not ok then
        Open77.log.warn("catalog push to the page failed: " .. tostring(reason))
    end
end)

-- Server -> client: the balance after a purchase attempt.
RegisterNetEvent("eval_shop:balance", function(balance)
    if not page then return end
    page:send("balance", { balance = balance })
end)
