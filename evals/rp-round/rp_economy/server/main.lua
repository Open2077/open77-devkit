-- rp_economy — server-authoritative wallet (eurodollars) for an RP server.
--
-- One integer balance per player, keyed by the durable identifier
-- (Open77.players.identifier), persisted in this resource's KVP store on every
-- change. Loaded when the player is ready, dropped from memory when they leave.
--
-- Exports (contract shared with the other resources of the round):
--   getBalance(playerId) -> integer (0 when unknown)
--   add(playerId, amount, reason) -> newBalance | nil, reason
--   remove(playerId, amount, reason) -> newBalance | nil, "insufficient_funds" | nil, reason
-- Every change publishes TriggerEvent("rp_economy:changed", playerId, newBalance, delta, reason).

local RESOURCE = GetCurrentResourceName()

local START_BALANCE = 500
local PAYDAY_AMOUNT = 200
local PAYDAY_INTERVAL_MS = 10 * 60 * 1000
local MAX_BALANCE = 1000000000000 -- 1e12: keeps every balance an exact JSON integer
local MAX_REASON_BYTES = 64
local KEY_PREFIX = "balance:"
local CURRENCY = "€$"

-- Live state. Both tables are keyed by the numeric session id and only hold
-- players whose wallet was actually loaded (identifier known, store readable).
local wallets = {}     -- [playerId] = integer balance
local identifiers = {} -- [playerId] = durable userId, cached at load time

local paydayThreadStarted = false

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

local function log(text)
    print("[" .. RESOURCE .. "] " .. text)
end

-- Reason as it appears in the log: one grep-able token, never empty.
local function logToken(reason)
    if reason == nil then
        return "unspecified"
    end
    return (tostring(reason):gsub("%s+", "_"))
end

local function formatMoney(amount)
    return ("%d %s"):format(amount, CURRENCY)
end

-- tonumber that tolerates nil (tonumber(nil) raises in Lua 5.4).
local function asNumber(value)
    if value == nil then
        return nil
    end
    return tonumber(value)
end

-- A positive integer (integer-valued floats such as 5.0 are accepted), bounded.
local function toPositiveInteger(value, maximum)
    if type(value) ~= "number" then
        return nil
    end
    if value ~= value or value <= 0 or value % 1 ~= 0 then
        return nil
    end
    local integer = math.tointeger(value)
    if not integer or integer > maximum then
        return nil
    end
    return integer
end

-- Chat line to one player; player ids from host events are strings, so always
-- convert. Failures are logged, never raised: chat is a courtesy, not authority.
local function tell(playerId, text)
    local id = asNumber(playerId)
    if not id or id <= 0 then
        return
    end
    local ok, reason = Open77.chat.send(id, text)
    if not ok then
        log(("chat.send refused for player %d: %s"):format(id, tostring(reason)))
    end
end

-- Toast, only when the notifications API exists on this server build.
local function notify(playerId, definition)
    local id = asNumber(playerId)
    if not id or id <= 0 then
        return
    end
    if type(Open77.notifications) ~= "table" or type(Open77.notifications.send) ~= "function" then
        return
    end
    local notificationId, reason = Open77.notifications.send(id, definition)
    if not notificationId then
        log(("notifications.send refused for player %d: %s"):format(id, tostring(reason)))
    end
end

-- Connected AND ready according to the host roster.
local function isPlayerReady(playerId)
    local read = Open77.players.get(playerId)
    return read ~= nil and read.ready == true
end

------------------------------------------------------------------------------
-- Persistence
------------------------------------------------------------------------------

local function storageKey(userId)
    return KEY_PREFIX .. userId
end

local function persist(playerId)
    local userId = identifiers[playerId]
    local balance = wallets[playerId]
    if not userId or balance == nil then
        return false
    end
    local ok, reason = Open77.kvp.set(storageKey(userId), balance)
    if not ok then
        log(("kvp.set failed for player %d (%s): %s"):format(playerId, userId, tostring(reason)))
        return false
    end
    return true
end

-- Loads (or creates) the wallet of a connected player. Returns the balance,
-- or nil, reason when the player cannot take part in the economy.
local function loadWallet(playerId)
    if wallets[playerId] ~= nil then
        return wallets[playerId]
    end
    local userId = Open77.players.identifier(playerId)
    if type(userId) ~= "string" or userId == "" then
        log(("no durable identifier for player %d, wallet not loaded"):format(playerId))
        return nil, "identifier_unavailable"
    end

    local key = storageKey(userId)
    local stored, reason = Open77.kvp.get(key)
    if stored == nil and reason ~= nil then
        -- A storage failure, not a missing key: never invent a balance on top of it.
        log(("kvp.get failed for player %d (%s): %s"):format(playerId, userId, tostring(reason)))
        return nil, "storage_unavailable"
    end

    local balance
    if stored == nil then
        balance = START_BALANCE
    else
        balance = math.tointeger(stored)
        if balance == nil or balance < 0 then
            log(("corrupt balance for player %d (%s): %s, reset to 0"):format(playerId, userId, tostring(stored)))
            balance = 0
        end
    end

    identifiers[playerId] = userId
    wallets[playerId] = balance
    if stored == nil then
        persist(playerId)
        log(("new wallet player %d %s balance=%d"):format(playerId, userId, balance))
    else
        log(("loaded player %d %s balance=%d"):format(playerId, userId, balance))
    end
    return balance
end

local function unloadWallet(playerId)
    if wallets[playerId] ~= nil then
        persist(playerId)
    end
    wallets[playerId] = nil
    identifiers[playerId] = nil
end

------------------------------------------------------------------------------
-- Core ledger operation
------------------------------------------------------------------------------

-- Applies a signed delta to a loaded wallet. Validation of playerId/amount/reason
-- is the caller's job; this only enforces the balance bounds, persists, logs
-- and publishes the change.
local function applyDelta(playerId, delta, reason)
    local balance = wallets[playerId]
    if balance == nil then
        return nil, "player_not_found"
    end
    local newBalance = balance + delta
    if newBalance < 0 then
        return nil, "insufficient_funds"
    end
    if newBalance > MAX_BALANCE then
        return nil, "balance_limit"
    end

    wallets[playerId] = newBalance
    persist(playerId)

    log(("%+d player %d %s balance=%d"):format(delta, playerId, logToken(reason), newBalance))

    local ok, publishReason = TriggerEvent("rp_economy:changed", playerId, newBalance, delta, reason)
    if not ok then
        log(("rp_economy:changed not published: %s"):format(tostring(publishReason)))
    end
    return newBalance
end

------------------------------------------------------------------------------
-- Exports (validate everything: an export is never proof of anything)
------------------------------------------------------------------------------

local function validatePlayerId(playerId)
    local id = toPositiveInteger(playerId, 2147483647)
    if not id then
        return nil, "invalid_player_id"
    end
    if wallets[id] == nil then
        return nil, "player_not_found"
    end
    return id
end

local function validateAmount(amount)
    local value = toPositiveInteger(amount, MAX_BALANCE)
    if not value then
        return nil, "invalid_amount"
    end
    return value
end

local function validateReason(reason)
    if reason == nil then
        return true
    end
    if type(reason) ~= "string" or reason == "" or #reason > MAX_REASON_BYTES then
        return nil, "invalid_reason"
    end
    if reason:find("[%c]") then
        return nil, "invalid_reason"
    end
    return true
end

exports("getBalance", function(playerId)
    local id = toPositiveInteger(playerId, 2147483647)
    if not id then
        return 0
    end
    return wallets[id] or 0
end)

exports("add", function(playerId, amount, reason)
    local id, idReason = validatePlayerId(playerId)
    if not id then
        return nil, idReason
    end
    local value, amountReason = validateAmount(amount)
    if not value then
        return nil, amountReason
    end
    local reasonOk, reasonReason = validateReason(reason)
    if not reasonOk then
        return nil, reasonReason
    end
    return applyDelta(id, value, reason)
end)

exports("remove", function(playerId, amount, reason)
    local id, idReason = validatePlayerId(playerId)
    if not id then
        return nil, idReason
    end
    local value, amountReason = validateAmount(amount)
    if not value then
        return nil, amountReason
    end
    local reasonOk, reasonReason = validateReason(reason)
    if not reasonOk then
        return nil, reasonReason
    end
    return applyDelta(id, -value, reason)
end)

------------------------------------------------------------------------------
-- Payday
------------------------------------------------------------------------------

local function runPayday(trigger)
    local paid = 0
    for _, rawId in ipairs(Open77.players.all() or {}) do
        local playerId = asNumber(rawId)
        if playerId and wallets[playerId] ~= nil and isPlayerReady(playerId) then
            local newBalance = applyDelta(playerId, PAYDAY_AMOUNT, "payday")
            if newBalance then
                paid = paid + 1
                tell(playerId, ("Paie : +%d %s"):format(PAYDAY_AMOUNT, CURRENCY))
            end
        end
    end
    log(("payday (%s) paid %d player(s)"):format(trigger, paid))
    return paid
end

local function startPaydayThread()
    if paydayThreadStarted then
        return
    end
    paydayThreadStarted = true
    CreateThread(function()
        while true do
            Wait(PAYDAY_INTERVAL_MS)
            runPayday("timer")
        end
    end)
end

------------------------------------------------------------------------------
-- Chat suggestions
------------------------------------------------------------------------------

local SUGGESTIONS = {
    { command = "/money", help = "Affiche votre solde" },
    { command = "/pay", help = "Envoie de l'argent à un joueur connecté", parameters = {
        { name = "playerId", help = "Identifiant du joueur" },
        { name = "amount", help = "Montant en €$" },
    } },
    { command = "/givemoney", help = "[Admin] Crédite un joueur", parameters = {
        { name = "playerId", help = "Identifiant du joueur" },
        { name = "amount", help = "Montant en €$" },
    } },
    { command = "/payday", help = "[Admin] Déclenche une paie immédiate" },
}

local function publishSuggestions(target)
    local ok, reason = Open77.chat.addSuggestions(target, SUGGESTIONS)
    if not ok then
        log(("addSuggestions refused for target %s: %s"):format(tostring(target), tostring(reason)))
    end
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

AddEventHandler("onResourceStart", function(name)
    if name ~= RESOURCE then
        return
    end
    -- Players already in the world had their onPlayerReady before this
    -- generation existed (hot reload): load them now.
    for _, rawId in ipairs(Open77.players.all() or {}) do
        local playerId = asNumber(rawId)
        if playerId and isPlayerReady(playerId) then
            loadWallet(playerId)
        end
    end
    publishSuggestions(-1)
    startPaydayThread()
    log("started")
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= RESOURCE then
        return
    end
    -- Every change is already persisted; this is belt and braces.
    for playerId in pairs(wallets) do
        persist(playerId)
    end
end)

AddEventHandler("onPlayerReady", function(rawPlayerId)
    local playerId = asNumber(rawPlayerId)
    if not playerId then
        return
    end
    local balance, reason = loadWallet(playerId)
    if not balance then
        tell(playerId, ("Portefeuille indisponible (%s) : préviens un admin."):format(tostring(reason)))
        return
    end
    tell(playerId, ("Solde : %s"):format(formatMoney(balance)))
end)

AddEventHandler("onPlayerDisconnected", function(rawPlayerId)
    local playerId = asNumber(rawPlayerId)
    if playerId then
        unloadWallet(playerId)
    end
end)

RegisterNetEvent("chat:ready", function()
    local playerId = asNumber(source)
    if playerId and playerId > 0 then
        publishSuggestions(playerId)
    end
end)

------------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------------

-- Parses "<playerId> <amount>" from a command; answers French errors to `reply`.
local function parseTargetAndAmount(args, reply, usage)
    local target = toPositiveInteger(asNumber(args[1]), 2147483647)
    local amount = toPositiveInteger(asNumber(args[2]), MAX_BALANCE)
    if not target or not amount then
        reply("Usage : " .. usage)
        return nil
    end
    if wallets[target] == nil or not isPlayerReady(target) then
        reply("Joueur introuvable ou pas encore en jeu.")
        return nil
    end
    return target, amount
end

RegisterCommand("money", function(source, args, raw)
    if source == 0 then
        print("[" .. RESOURCE .. "] /money : à utiliser depuis le jeu, pas depuis la console.")
        return
    end
    local balance = wallets[source]
    if balance == nil then
        balance = loadWallet(source)
    end
    if balance == nil then
        tell(source, "Portefeuille indisponible : préviens un admin.")
        return
    end
    tell(source, ("Solde : %s"):format(formatMoney(balance)))
    notify(source, {
        type = "info",
        title = "Portefeuille",
        message = ("Solde : %s"):format(formatMoney(balance)),
        icon = "E$",
        durationMs = 5000,
    })
end, false)

RegisterCommand("pay", function(source, args, raw)
    if source == 0 then
        print("[" .. RESOURCE .. "] /pay : à utiliser depuis le jeu, pas depuis la console.")
        return
    end
    local reply = function(text) tell(source, text) end
    if wallets[source] == nil then
        reply("Portefeuille indisponible : préviens un admin.")
        return
    end
    local target, amount = parseTargetAndAmount(args, reply, "/pay <playerId> <montant>")
    if not target then
        return
    end
    if target == source then
        reply("Tu ne peux pas te payer toi-même.")
        return
    end
    if wallets[source] < amount then
        reply(("Fonds insuffisants : il te manque %s."):format(formatMoney(amount - wallets[source])))
        return
    end

    local senderBalance, removeReason = applyDelta(source, -amount, "pay:to:" .. target)
    if not senderBalance then
        reply(("Paiement refusé (%s)."):format(tostring(removeReason)))
        return
    end
    local targetBalance, addReason = applyDelta(target, amount, "pay:from:" .. source)
    if not targetBalance then
        -- Refund: the target could not receive (balance cap, vanished between checks).
        applyDelta(source, amount, "pay:refund:" .. target)
        reply(("Paiement refusé (%s), montant remboursé."):format(tostring(addReason)))
        return
    end

    local senderName = Open77.players.name(source) or ("#" .. source)
    local targetName = Open77.players.name(target) or ("#" .. target)
    reply(("Tu as envoyé %s à %s. Solde : %s"):format(formatMoney(amount), targetName, formatMoney(senderBalance)))
    tell(target, ("%s t'a envoyé %s. Solde : %s"):format(senderName, formatMoney(amount), formatMoney(targetBalance)))
end, false)

-- Restricted: ACL command.givemoney; the server console is always allowed.
RegisterCommand("givemoney", function(source, args, raw)
    local reply
    if source == 0 then
        reply = function(text) print("[" .. RESOURCE .. "] givemoney : " .. text) end
    else
        reply = function(text) tell(source, text) end
    end
    local target, amount = parseTargetAndAmount(args, reply, "/givemoney <playerId> <montant>")
    if not target then
        return
    end
    local newBalance, reason = applyDelta(target, amount, "givemoney:by:" .. source)
    if not newBalance then
        reply(("Crédit refusé (%s)."):format(tostring(reason)))
        return
    end
    tell(target, ("Un administrateur t'a crédité de %s. Solde : %s"):format(formatMoney(amount), formatMoney(newBalance)))
    if source ~= 0 then
        local targetName = Open77.players.name(target) or ("#" .. target)
        reply(("%s crédité de %s (solde : %s)."):format(targetName, formatMoney(amount), formatMoney(newBalance)))
    end
end, true)

-- Restricted: ACL command.payday; the server console is always allowed.
RegisterCommand("payday", function(source, args, raw)
    local paid = runPayday(source == 0 and "console" or ("player:" .. source))
    if source ~= 0 then
        tell(source, ("Paie déclenchée : %d joueur(s) payé(s)."):format(paid))
    else
        print("[" .. RESOURCE .. "] payday : " .. paid .. " joueur(s) payé(s).")
    end
end, true)
