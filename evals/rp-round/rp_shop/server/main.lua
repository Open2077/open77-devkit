-- rp_shop: server-authoritative shop for an RP server.
--
-- /shop            lists the catalogue, grouped by family
-- /buy <objet>     charges the price through rp_economy, then delivers
-- /sell <objet>    sells back the last shop-bought vehicle of that model (50 %)
--
-- Money is never touched here: every charge and refund goes through the
-- rp_economy server exports. Vehicles bought here are remembered per durable
-- player identifier in this resource's KVP store, so /sell survives a reload.

local RESOURCE = GetCurrentResourceName()
local LOG = "[" .. RESOURCE .. "]"

-- Catalogue: `id` is what the player types. Families are listed in this
-- order by /shop. Prices are eurodollars.
local CATALOGUE = {
    { id = "soin",     family = "consommable", label = "Kit de soin (vie au maximum)",       price = 50,    kind = "restore", pool = "health" },
    { id = "stim",     family = "consommable", label = "Stimulant (endurance au maximum)",   price = 30,    kind = "restore", pool = "stamina" },
    { id = "armure",   family = "consommable", label = "Gilet pare-balles (armure 100)",     price = 150,   kind = "armor",   amount = 100 },
    { id = "pistolet", family = "arme",        label = "Pistolet M-10AF Lexington",          price = 400,   kind = "weapon",  record = "Items.Preset_Lexington_Default", slot = 1 },
    { id = "fusil",    family = "arme",        label = "Fusil à pompe Carnage",              price = 1200,  kind = "weapon",  record = "Items.Preset_Carnage_Default",   slot = 2 },
    { id = "katana",   family = "arme",        label = "Katana",                             price = 900,   kind = "weapon",  record = "Items.Preset_Katana_Default",    slot = 3 },
    { id = "hella",    family = "vehicule",    label = "Archer Hella (berline)",             price = 15000, kind = "vehicle", record = "Vehicle.v_standard2_archer_hella_player" },
    { id = "quadra",   family = "vehicule",    label = "Quadra Turbo-R (hypercar)",          price = 60000, kind = "vehicle", record = "Vehicle.v_sport1_quadra_turbo_r_player" },
}

local FAMILIES = {
    { key = "consommable", title = "Consommables" },
    { key = "arme",        title = "Armes" },
    { key = "vehicule",    title = "Véhicules" },
}

local SELL_RATIO = 0.5            -- refund on /sell
local VEHICLE_SIDE_OFFSET = 3.5   -- metres to the player's right
local POSITION_MAX_AGE_MS = 5000  -- reject a stale player snapshot
local WEAPON_FALLBACK_MS = 15000  -- refund if the weapon relay never answers

local byId = {}
for _, item in ipairs(CATALOGUE) do
    byId[item.id] = item
end

-- Vehicles bought and not yet sold, keyed by durable identifier:
-- garages[identifier] = { { id, record, item, price, at }, ... } (oldest first).
local garages = {}

-- Weapon deliveries waiting for open77:weapons:completed, keyed by request id.
local pendingWeapons = {}

local SUGGESTIONS = {
    { command = "/shop", help = "Affiche le catalogue de la boutique" },
    { command = "/buy",  help = "Achète un objet de la boutique",
      parameters = { { name = "objet", help = "soin, stim, armure, pistolet, fusil, katana, hella, quadra" } } },
    { command = "/sell", help = "Revend un véhicule acheté ici (50 % du prix)",
      parameters = { { name = "objet", help = "hella ou quadra (vide = dernier véhicule)" } } },
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function say(playerId, text)
    local ok, reason = Open77.chat.send(playerId, text)
    if not ok then
        print(LOG .. " chat.send refused for player " .. tostring(playerId) .. ": " .. tostring(reason))
    end
end

local function priceLabel(amount)
    return tostring(math.floor(tonumber(amount) or 0)) .. " $"
end

local function identifierOf(playerId)
    local identifier = Open77.players.identifier(playerId)
    if identifier == nil or identifier == "" then
        return nil
    end
    return tostring(identifier)
end

-- Every economy call is synchronous and RAISES when rp_economy is missing or
-- refuses the call, so it is wrapped. Returns: status, value, reason
--   status = "offline"  the export could not be reached (value = error text)
--   status = "refused"  the export answered nil, reason
--   status = "ok"       value is the new balance
local function ecoRemove(playerId, amount, reason)
    local ok, balance, why = pcall(function()
        return exports.rp_economy:remove(playerId, amount, reason)
    end)
    if not ok then
        return "offline", tostring(balance)
    end
    if balance == nil then
        return "refused", nil, tostring(why or "unknown")
    end
    return "ok", balance
end

local function ecoAdd(playerId, amount, reason)
    local ok, balance, why = pcall(function()
        return exports.rp_economy:add(playerId, amount, reason)
    end)
    if not ok then
        return "offline", tostring(balance)
    end
    if balance == nil then
        return "refused", nil, tostring(why or "unknown")
    end
    return "ok", balance
end

local function ecoBalance(playerId)
    local ok, balance = pcall(function()
        return exports.rp_economy:getBalance(playerId)
    end)
    if ok and type(balance) == "number" then
        return balance
    end
    return nil
end

-- Refund after a failed delivery; tells the player either way.
local function refund(playerId, item, why)
    local status, value, reason = ecoAdd(playerId, item.price, "remboursement " .. item.id)
    if status == "ok" then
        say(playerId, ("Livraison impossible (%s) : %s remboursé."):format(tostring(why), priceLabel(item.price)))
        print(LOG .. " player " .. tostring(playerId) .. " refunded " .. item.price .. " for " .. item.id .. " (" .. tostring(why) .. ")")
    else
        say(playerId, ("Livraison impossible (%s) et remboursement impossible (%s) : contacte un admin."):format(tostring(why), tostring(reason or value)))
        print(LOG .. " REFUND FAILED for player " .. tostring(playerId) .. " item " .. item.id .. " amount " .. item.price .. ": " .. tostring(reason or value))
    end
end

-- Refuses the console and dead players; returns true when the caller may trade.
local function canTrade(source)
    if source == 0 then
        print(LOG .. " cette commande se lance depuis le jeu, pas depuis la console")
        return false
    end
    local dead, reason = Open77.players.isDead(source)
    if dead == nil then
        say(source, "Impossible de vérifier ton état (" .. tostring(reason or "inconnu") .. "), réessaie dans un instant.")
        return false
    end
    if dead then
        say(source, "Tu es mort : la boutique ne sert pas les cadavres.")
        return false
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Garage ledger (KVP, keyed by durable identifier)
-- ---------------------------------------------------------------------------

local function garageKey(identifier)
    return "garage:" .. identifier
end

local function loadGarage(identifier)
    if garages[identifier] then
        return garages[identifier]
    end
    local list = {}
    local raw = Open77.kvp.get(garageKey(identifier), nil)
    if type(raw) == "string" and raw ~= "" then
        local decoded = json.decode(raw)
        if type(decoded) == "table" then
            for _, entry in ipairs(decoded) do
                if type(entry) == "table" and entry.id ~= nil and type(entry.item) == "string" then
                    list[#list + 1] = entry
                end
            end
        else
            print(LOG .. " garage ledger of " .. identifier .. " is corrupt, starting empty")
        end
    end
    garages[identifier] = list
    return list
end

local function saveGarage(identifier)
    local list = garages[identifier] or {}
    local ok, reason
    if #list == 0 then
        -- false with no reason just means the key was already absent
        ok, reason = Open77.kvp.delete(garageKey(identifier))
        ok = ok or reason == nil
    else
        local encoded = json.encode(list)
        if not encoded then
            print(LOG .. " could not encode the garage ledger of " .. identifier)
            return
        end
        ok, reason = Open77.kvp.set(garageKey(identifier), encoded)
    end
    if not ok then
        print(LOG .. " kvp write failed for " .. identifier .. ": " .. tostring(reason))
    end
end

-- The ledger entry's vehicle, if it still exists and is still ours.
local function ledgerVehicle(entry)
    local vehicle = Open77.vehicles.get(entry.id)
    if not vehicle then
        return nil
    end
    -- Guard against a recycled id pointing at somebody else's car.
    if vehicle.record ~= entry.record then
        return nil
    end
    if vehicle.resource ~= nil and vehicle.resource ~= RESOURCE then
        return nil
    end
    return vehicle
end

-- Drops entries whose vehicle is gone; returns true when something changed.
local function pruneGarage(identifier)
    local list = garages[identifier]
    if not list then
        return false
    end
    local kept, changed = {}, false
    for _, entry in ipairs(list) do
        if ledgerVehicle(entry) then
            kept[#kept + 1] = entry
        else
            changed = true
        end
    end
    if changed then
        garages[identifier] = kept
        saveGarage(identifier)
    end
    return changed
end

-- ---------------------------------------------------------------------------
-- Delivery
-- ---------------------------------------------------------------------------

local function deliverRestore(playerId, item)
    local ok, reason = Open77.stats.restore(playerId, item.pool)
    if not ok then
        return false, reason or "refus"
    end
    return true
end

local function deliverArmor(playerId, item)
    local ok, reason = Open77.players.setArmor(playerId, item.amount)
    if not ok then
        return false, reason or "refus"
    end
    return true
end

-- Asynchronous: the money is already taken, the answer comes back on
-- open77:weapons:completed (or never, hence the fallback thread).
local function deliverWeapon(playerId, item)
    local requestId, reason = Open77.weapons.assign(playerId, item.record, item.slot, { active = true })
    if not requestId then
        return false, reason or "refus"
    end
    local key = tostring(requestId)
    pendingWeapons[key] = { playerId = playerId, item = item }
    CreateThread(function()
        Wait(WEAPON_FALLBACK_MS)
        local pending = pendingWeapons[key]
        if pending then
            pendingWeapons[key] = nil
            print(LOG .. " weapon request " .. key .. " never completed for player " .. tostring(playerId))
            refund(playerId, item, "pas de réponse du client")
        end
    end)
    return true, nil, "pending"
end

AddEventHandler("open77:weapons:completed", function(playerId, requestId, operation, accepted, reason, result)
    local pending = pendingWeapons[tostring(requestId)]
    if not pending then
        return
    end
    pendingWeapons[tostring(requestId)] = nil
    local target = tonumber(playerId) or pending.playerId
    local okAccepted = (accepted == true) or (accepted == "true")
    if okAccepted then
        local slot = (type(result) == "table" and result.slot) or pending.item.slot
        say(target, ("Livré : %s (emplacement %s)."):format(pending.item.label, tostring(slot)))
        print(LOG .. " player " .. tostring(target) .. " received " .. pending.item.id)
    else
        refund(target, pending.item, tostring(reason or operation or "refus"))
    end
end)

-- Spawns the car beside the player, facing the same way. `me` is a fresh
-- Open77.players.get snapshot validated by the caller.
local function deliverVehicle(playerId, item, me, identifier)
    local yaw = tonumber(me.heading) or tonumber(me.yaw) or 0.0
    -- REDengine: yaw 0 faces +y, +x is the entity's right. A positive yaw is
    -- taken as a counter-clockwise turn seen from above, so the right-hand
    -- unit vector is (cos, sin); a wrong sign only swaps left and right.
    local rad = math.rad(yaw)
    local rx, ry = math.cos(rad), math.sin(rad)
    local vehicleId, reason = Open77.vehicles.create({
        record = item.record,
        position = {
            x = me.position.x + rx * VEHICLE_SIDE_OFFSET,
            y = me.position.y + ry * VEHICLE_SIDE_OFFSET,
            z = me.position.z,
        },
        yaw = yaw,
        bucket = me.bucket,
        persistent = true, -- the player's property: only /sell removes it
    })
    if not vehicleId then
        return false, reason or "refus"
    end
    local list = loadGarage(identifier)
    list[#list + 1] = {
        id = vehicleId,
        record = item.record,
        item = item.id,
        price = item.price,
        at = math.floor(Open77.time.unix()),
    }
    saveGarage(identifier)
    return true, nil, vehicleId
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------

RegisterCommand("shop", function(source, args, raw)
    if source == 0 then
        for _, item in ipairs(CATALOGUE) do
            print(LOG .. " " .. item.id .. " - " .. item.label .. " - " .. priceLabel(item.price))
        end
        return
    end
    local lines = { "=== Boutique === (/buy <objet>, /sell <objet>)" }
    for _, family in ipairs(FAMILIES) do
        lines[#lines + 1] = "-- " .. family.title .. " --"
        for _, item in ipairs(CATALOGUE) do
            if item.family == family.key then
                lines[#lines + 1] = ("  %s : %s - %s"):format(item.id, item.label, priceLabel(item.price))
            end
        end
    end
    local balance = ecoBalance(source)
    if balance then
        lines[#lines + 1] = "Ton solde : " .. priceLabel(balance)
    else
        lines[#lines + 1] = "Système monétaire hors ligne : les achats sont impossibles pour le moment."
    end
    -- Two sends in the same tick arrive in reverse order: one line per tick.
    for _, line in ipairs(lines) do
        say(source, line)
        Wait(0)
    end
end, false)

RegisterCommand("buy", function(source, args, raw)
    if not canTrade(source) then
        return
    end
    local wanted = args[1] and string.lower(args[1]) or nil
    local item = wanted and byId[wanted] or nil
    if not item then
        say(source, "Usage : /buy <objet>. Objets : soin, stim, armure, pistolet, fusil, katana, hella, quadra (/shop pour les prix).")
        return
    end

    -- Everything that can refuse for free is checked BEFORE the money moves.
    local me, identifier
    if item.kind == "vehicle" then
        identifier = identifierOf(source)
        if not identifier then
            say(source, "Identité introuvable : impossible d'enregistrer le véhicule à ton nom.")
            return
        end
        local reason
        me, reason = Open77.players.get(source)
        if not me then
            say(source, "Position inconnue (" .. tostring(reason or "inconnu") .. ") : réessaie dans un instant.")
            return
        end
        if not me.position or (me.ageMs or 0) > POSITION_MAX_AGE_MS then
            say(source, "Position trop ancienne : bouge un peu puis réessaie.")
            return
        end
    end

    local status, balance, reason = ecoRemove(source, item.price, "achat " .. item.id)
    if status == "offline" then
        say(source, "Système monétaire hors ligne : achat impossible pour le moment.")
        print(LOG .. " rp_economy unreachable for player " .. tostring(source) .. ": " .. tostring(balance))
        return
    end
    if status == "refused" then
        if reason == "insufficient_funds" then
            local have = ecoBalance(source)
            say(source, ("Fonds insuffisants : %s coûte %s%s."):format(item.label, priceLabel(item.price),
                have and (", tu as " .. priceLabel(have)) or ""))
        else
            say(source, "Paiement refusé (" .. tostring(reason) .. ").")
        end
        return
    end
    print(LOG .. " player " .. tostring(source) .. " bought " .. item.id .. " for " .. item.price)

    local ok, why, extra
    if item.kind == "restore" then
        ok, why = deliverRestore(source, item)
    elseif item.kind == "armor" then
        ok, why = deliverArmor(source, item)
    elseif item.kind == "weapon" then
        ok, why, extra = deliverWeapon(source, item)
    elseif item.kind == "vehicle" then
        ok, why, extra = deliverVehicle(source, item, me, identifier)
    else
        ok, why = false, "objet mal configuré"
    end

    if not ok then
        refund(source, item, why)
        return
    end
    if item.kind == "weapon" then
        say(source, ("Achat de %s pour %s, livraison en cours... (solde : %s)"):format(item.label, priceLabel(item.price), priceLabel(balance)))
    elseif item.kind == "vehicle" then
        say(source, ("Achat de %s pour %s : il t'attend à côté de toi (solde : %s)."):format(item.label, priceLabel(item.price), priceLabel(balance)))
        print(LOG .. " vehicle " .. tostring(extra) .. " created for player " .. tostring(source))
    else
        say(source, ("Achat de %s pour %s (solde : %s)."):format(item.label, priceLabel(item.price), priceLabel(balance)))
    end
end, false)

RegisterCommand("sell", function(source, args, raw)
    if not canTrade(source) then
        return
    end
    local wanted = args[1] and string.lower(args[1]) or nil
    local item = wanted and byId[wanted] or nil
    if wanted and not item then
        say(source, "Objet inconnu. Usage : /sell <hella|quadra> (vide = ton dernier véhicule).")
        return
    end
    if item and item.kind ~= "vehicle" then
        say(source, "Seuls les véhicules achetés ici se revendent (hella, quadra).")
        return
    end

    local identifier = identifierOf(source)
    if not identifier then
        say(source, "Identité introuvable : impossible de retrouver tes véhicules.")
        return
    end
    local list = loadGarage(identifier)
    pruneGarage(identifier)
    list = garages[identifier]

    -- The last still-existing shop-bought vehicle (of that model, if given).
    local index
    for i = #list, 1, -1 do
        if (not item or list[i].item == item.id) and ledgerVehicle(list[i]) then
            index = i
            break
        end
    end
    if not index then
        if item then
            say(source, "Tu n'as aucun " .. item.label .. " acheté ici encore en circulation.")
        else
            say(source, "Tu n'as aucun véhicule acheté ici encore en circulation.")
        end
        return
    end
    local entry = list[index]
    local sold = byId[entry.item]
    local refundAmount = math.floor((tonumber(entry.price) or (sold and sold.price) or 0) * SELL_RATIO)
    local label = sold and sold.label or entry.item

    -- Money first: a refund that fails leaves the car with its owner.
    local status, balance, reason = ecoAdd(source, refundAmount, "vente " .. entry.item)
    if status == "offline" then
        say(source, "Système monétaire hors ligne : vente impossible pour le moment.")
        print(LOG .. " rp_economy unreachable for player " .. tostring(source) .. ": " .. tostring(balance))
        return
    end
    if status == "refused" then
        say(source, "Remboursement refusé (" .. tostring(reason) .. ") : vente annulée.")
        return
    end

    local removed = Open77.vehicles.remove(entry.id)
    if not removed then
        -- Take the refund back; the player keeps the car.
        local back = ecoRemove(source, refundAmount, "annulation vente " .. entry.item)
        if back ~= "ok" then
            print(LOG .. " could not take back the refund of " .. refundAmount .. " from player " .. tostring(source))
        end
        say(source, "Le véhicule n'a pas pu être retiré : vente annulée.")
        return
    end
    table.remove(list, index)
    saveGarage(identifier)
    say(source, ("%s vendu pour %s (solde : %s)."):format(label, priceLabel(refundAmount), priceLabel(balance)))
    print(LOG .. " player " .. tostring(source) .. " sold " .. entry.item .. " (vehicle " .. tostring(entry.id) .. ") for " .. refundAmount)
end, false)

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

-- Host event: every argument is a string. Keep the ledgers honest when a car
-- disappears for any reason (explosion cleanup, admin removal...).
AddEventHandler("onVehicleRemoved", function(vehicleId, reason)
    local gone = tostring(vehicleId)
    for identifier, list in pairs(garages) do
        for i = #list, 1, -1 do
            if tostring(list[i].id) == gone then
                table.remove(list, i)
                saveGarage(identifier)
            end
        end
    end
end)

-- Forget the in-memory ledger of a departed player; the KVP copy stays.
AddEventHandler("onPlayerDisconnected", function(playerId, reason)
    local identifier = Open77.players.identifier(playerId)
    if identifier ~= nil and identifier ~= "" then
        garages[tostring(identifier)] = nil
    end
end)

RegisterNetEvent("chat:ready", function()
    if type(source) ~= "number" or source == 0 then
        return
    end
    Open77.chat.addSuggestions(source, SUGGESTIONS)
end)

AddEventHandler("onResourceStart", function(name)
    if name ~= RESOURCE then
        return
    end
    Open77.chat.addSuggestions(-1, SUGGESTIONS)
    print(LOG .. " boutique ouverte : " .. #CATALOGUE .. " objets, /shop pour le catalogue")
end)
