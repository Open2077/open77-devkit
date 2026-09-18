-- rp_nomade / server: Badlands convoys and crate deliveries for the `nomade` job.
--
-- Server-authoritative. The client only draws rings, prompts and asks; every decision below
-- (job, money, truck, crates, zones, ambush, pay) is re-derived here from the server's own reads.
--
-- Flow: contracts board (E, camp) -> UI-kit menu -> rental truck + N crate props at the camp
--       -> E on a crate: carried in the hand (Open77.props.attach) -> E on the truck: loaded
--       -> drive to the destination zone (rp_zones) -> E on the truck: 6 s bar per crate -> paid
--       -> E on the truck inside the camp: returned, deposit refunded.
-- A loaded truck crossing the ambush circle once spawns hostile NPCs for three minutes.

local C = RpNomadeConfig
local RESOURCE = GetCurrentResourceName()
local SOCIETY = C.Contract.society

local contracts = {}          -- [playerId] = contract (one per driver)
local boardOpen = {}          -- [playerId] = true while the contracts menu waits on that player
local heldRequests = {}       -- [requestId] = { playerId = n, index = i } for open77:helditem:completed
local store = { mode = "pending", reason = nil }
local nextLocalId = 1

---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------

local function log(fmt, ...)
    print(("[rp_nomade] " .. fmt):format(...))
end

local function say(playerId, text)
    if type(playerId) ~= "number" then return end
    Open77.chat.send(playerId, { author = "Convoys", text = text, color = { 242, 179, 61 } })
end

local function toast(playerId, kind, title, message)
    if type(playerId) ~= "number" then return end
    Open77.notifications.send(playerId, { type = kind, title = title, message = message, durationMs = 6000 })
end

local function dist3(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function dist2(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Ids cross the network as numbers or strings; compare them on one spelling.
local function idKey(v)
    if type(v) == "number" then
        local i = math.tointeger(v)
        if i then return tostring(i) end
    end
    return tostring(v)
end

local function fmtMoney(n)
    return ("%d €$"):format(n)
end

local function minutes(seconds)
    return math.max(0, math.floor(seconds / 60 + 0.5))
end

-- Synchronous export of another resource, without raising. `nil, "unavailable:..."` when the
-- resource or the export is missing; otherwise exactly what the export returned.
local function callSync(resource, name, ...)
    local ok, a, b = pcall(Open77.exports.callSync, resource, name, ...)
    if not ok then return nil, "unavailable:" .. tostring(a) end
    return a, b
end

local function playerName(playerId)
    local full = callSync("rp_identity", "fullName", playerId)
    if type(full) == "string" and full ~= "" then return full end
    return Open77.players.name(playerId) or ("player " .. tostring(playerId))
end

-- Job gate: `nomade`, on duty. Returns true, or nil and a player-facing sentence.
local function nomadOnDuty(playerId)
    local has, err = callSync("rp_jobs", "hasJob", playerId, "nomade")
    if has == nil and err then return nil, "The clan roster is offline (rp_jobs). Try again later." end
    if not has then return nil, "Nomad work only, choom. Sign up at the agency (/agence)." end
    local duty = callSync("rp_jobs", "onDuty", playerId)
    if not duty then return nil, "Clock in first (/service) before taking a run." end
    return true
end

local function isNomadBoss(playerId)
    local has = callSync("rp_jobs", "hasJob", playerId, "nomade")
    if not has then return false end
    return callSync("rp_jobs", "isBoss", playerId) == true
end

local function cashAdd(playerId, amount, reason)
    if amount <= 0 then return 0 end
    local balance, why = callSync("rp_economy", "add", playerId, amount, reason)
    if balance == nil then return nil, why or "wallet_unavailable" end
    return balance
end

local function cashRemove(playerId, amount, reason)
    if amount <= 0 then return 0 end
    local balance, why = callSync("rp_economy", "remove", playerId, amount, reason)
    if balance == nil then return nil, why or "wallet_unavailable" end
    return balance
end

local function societyAdd(amount, reason)
    if amount <= 0 then return 0 end
    local balance, why = callSync("rp_bank", "societyAdd", SOCIETY, amount, reason)
    if balance == nil then return nil, why or "bank_unavailable" end
    return balance
end

-- rp_zones:isIn, with a planar-distance fallback when rp_zones is not running.
local function playerInZone(playerId, zoneName, fallbackPos, fallbackRadius)
    local inside, err = callSync("rp_zones", "isIn", playerId, zoneName)
    if inside == nil and err then
        local p = Open77.players.position(playerId)
        if not p or not fallbackPos then return false end
        return dist2(p, fallbackPos) <= (fallbackRadius or 10.0)
    end
    return inside == true
end

local function truckPosition(contract)
    if not contract.truckId then return nil end
    local pos = Open77.vehicles.getPosition(contract.truckId)
    if not pos then return nil end
    return pos
end

---------------------------------------------------------------------------------------------------
-- Persistence: SQL first (rp_nomade_contracts), kvp only when the database never answers
---------------------------------------------------------------------------------------------------

local HISTORY_KEY = "history"
local HISTORY_MAX = 50

local function useKvp(reason)
    if store.mode == "kvp" then return end
    store.mode, store.reason = "kvp", reason
    log("store=kvp reason=%s (contract history kept in this resource's kvp file)", tostring(reason))
end

local ready, readyReason = Open77.database.ready(function()
    Open77.database.update.await([[
        CREATE TABLE IF NOT EXISTS rp_nomade_contracts (
            id          INT AUTO_INCREMENT PRIMARY KEY,
            identifier  VARCHAR(64)  NOT NULL,
            player_name VARCHAR(80)  NOT NULL DEFAULT '',
            template    VARCHAR(32)  NOT NULL,
            destination VARCHAR(32)  NOT NULL,
            crates      TINYINT      NOT NULL DEFAULT 0,
            delivered   TINYINT      NOT NULL DEFAULT 0,
            pay         INT          NOT NULL DEFAULT 0,
            bonus       INT          NOT NULL DEFAULT 0,
            society_cut INT          NOT NULL DEFAULT 0,
            convoy      TINYINT      NOT NULL DEFAULT 1,
            status      VARCHAR(16)  NOT NULL DEFAULT 'active',
            started_at  BIGINT       NOT NULL DEFAULT 0,
            ended_at    BIGINT       NOT NULL DEFAULT 0,
            INDEX idx_rp_nomade_identifier (identifier)
        )
    ]])
    store.mode = "sql"
    log("store=sql table=rp_nomade_contracts")
end)
if not ready then
    useKvp(readyReason)
end

local function readHistory()
    local raw = Open77.kvp.get(HISTORY_KEY, "[]")
    local list = type(raw) == "string" and json.decode(raw) or nil
    if type(list) ~= "table" then list = {} end
    return list
end

local function historyRow(contract)
    return {
        id = contract.rowId or contract.localId,
        identifier = contract.identifier,
        player_name = contract.playerName,
        template = contract.template.id,
        destination = contract.destination,
        crates = contract.total,
        delivered = contract.delivered,
        pay = contract.pay,
        bonus = contract.bonus,
        society_cut = contract.societyCut,
        convoy = contract.convoy,
        status = contract.status,
        started_at = contract.startedAtUnix,
        ended_at = contract.endedAtUnix or 0,
    }
end

local persistEnd

local function persistStart(contract)
    if contract.store ~= "sql" then return end
    Open77.database.insert(
        "INSERT INTO rp_nomade_contracts (identifier, player_name, template, destination, crates, status, started_at) VALUES (?, ?, ?, ?, ?, 'active', ?)",
        { contract.identifier, contract.playerName, contract.template.id, contract.destination, contract.total, contract.startedAtUnix },
        function(result)
            local id = result
            if type(result) == "table" then id = result.insertId or result.id end
            if type(id) ~= "number" then
                log("contract row insert gave no id (%s); history will show local id %d", tostring(result), contract.localId)
                return
            end
            contract.rowId = id
            if contract.pendingEnd then
                contract.pendingEnd = nil
                persistEnd(contract)
            end
        end)
end

persistEnd = function(contract)
    if contract.store == "sql" then
        if not contract.rowId then
            -- The insert has not answered yet: finish the row when it does.
            contract.pendingEnd = true
            return
        end
        Open77.database.update(
            "UPDATE rp_nomade_contracts SET delivered = ?, pay = ?, bonus = ?, society_cut = ?, convoy = ?, status = ?, ended_at = ? WHERE id = ?",
            { contract.delivered, contract.pay, contract.bonus, contract.societyCut, contract.convoy, contract.status, contract.endedAtUnix or 0, contract.rowId },
            function() end)
    else
        local row = historyRow(contract)
        local list = readHistory()
        -- A contract is written at delivery and again when the truck comes back: one row per contract.
        for i = #list, 1, -1 do
            if type(list[i]) == "table" and list[i].id == row.id and list[i].identifier == row.identifier then
                table.remove(list, i)
            end
        end
        table.insert(list, 1, row)
        while #list > HISTORY_MAX do table.remove(list) end
        local encoded = json.encode(list)
        if encoded then Open77.kvp.set(HISTORY_KEY, encoded) end
    end
end

-- Newest first, at most `limit` rows, from SQL or the kvp fallback. Yields: handlers only.
local function loadHistory(limit)
    if store.mode == "sql" then
        -- `limit` comes from the config (an integer), never from a player: inlining it keeps the
        -- statement valid on drivers that refuse a placeholder in LIMIT.
        local rows = Open77.database.query.await(
            ("SELECT id, identifier, player_name, template, destination, crates, delivered, pay, bonus, society_cut, convoy, status, started_at, ended_at FROM rp_nomade_contracts ORDER BY id DESC LIMIT %d"):format(limit))
        return rows or {}, "sql"
    end
    local list = readHistory()
    local out = {}
    for i = 1, math.min(limit, #list) do out[i] = list[i] end
    return out, "kvp"
end

---------------------------------------------------------------------------------------------------
-- Client state
---------------------------------------------------------------------------------------------------

local function snapshot(contract)
    local crates = {}
    for i, crate in ipairs(contract.crates) do
        crates[i] = { index = i, x = crate.position.x, y = crate.position.y, z = crate.position.z, state = crate.state }
    end
    local dest = C.Destinations[contract.destination]
    local remaining = 0
    if contract.status == "active" then
        remaining = math.max(0, math.floor(contract.deadline - Open77.time.monotonic()))
    end
    return {
        label = contract.template.label,
        status = contract.status,
        truckId = contract.truckId,
        crates = crates,
        carrying = contract.carrying or 0,
        loaded = contract.loaded,
        delivered = contract.delivered,
        total = contract.total,
        atDestination = contract.atDestination == true,
        atCamp = contract.atCamp == true,
        remaining = remaining,
        destination = {
            name = contract.destination,
            label = dest and dest.label or contract.destination,
            x = dest and dest.position.x or 0.0,
            y = dest and dest.position.y or 0.0,
            z = dest and dest.position.z or 0.0,
            radius = dest and dest.radius or 10.0,
        },
    }
end

local function pushState(playerId, contract)
    if contract then
        TriggerClientEvent("rp_nomade:state", playerId, snapshot(contract))
    else
        TriggerClientEvent("rp_nomade:state", playerId, false)
    end
end

---------------------------------------------------------------------------------------------------
-- Spawning: truck, crates, ambush
---------------------------------------------------------------------------------------------------

local function spawnTruck(bucket)
    local spot = C.Camp.truckSpawn
    for _, record in ipairs(C.Truck.records) do
        local id, reason = Open77.vehicles.create({
            record = record,
            position = { x = spot.x, y = spot.y, z = spot.z },
            yaw = spot.yaw or 0.0,
            bucket = bucket,
            ttlMs = C.Truck.ttlMs,
        })
        if id then return id, record end
        log("truck record %s refused: %s", record, tostring(reason))
    end
    return nil, "no_truck_record"
end

local function spawnCrate(index, bucket)
    local point = C.Camp.loadingPoints[index]
    if not point then return nil, "no_loading_point" end
    for _, model in ipairs(C.Crate.models) do
        local id, reason = Open77.props.create({
            model = model,
            position = { x = point.x, y = point.y, z = point.z },
            yaw = 0.0,
            bucket = bucket,
        })
        if id then return id, model end
        log("crate model %s refused: %s", model, tostring(reason))
    end
    return nil, "no_crate_model"
end

-- Put the crate in the carrier's hand. Returns a word for the log.
local function carryCrate(playerId, contract, crate)
    if C.Carry.mode == "attach" then
        local ok, reason = Open77.props.attach(crate.propId, {
            parentType = "player",
            parentId = playerId,
            bone = C.Carry.bone,
            offset = C.Carry.offset,
            rotation = C.Carry.rotation,
        })
        if ok then
            crate.attached = true
            return "attached:" .. C.Carry.bone
        end
        log("attach of crate %s to player %d refused: %s (falling back to a hidden prop)", tostring(crate.propId), playerId, tostring(reason))
    end
    -- "held" mode, or the attach fallback: hide the standing prop, put an item record in the hand.
    local hidden, why = Open77.props.update(crate.propId, { visible = false })
    if hidden then crate.hidden = true else log("hide of crate %s refused: %s", tostring(crate.propId), tostring(why)) end
    local item = C.Carry.heldItem
    if item and item.record then
        local requestId, reason = Open77.heldItems.hold(playerId, item.record, { slot = item.slot or "WeaponRight" })
        if requestId then
            crate.held = true
            heldRequests[requestId] = { playerId = playerId, index = crate.index }
            return "held:" .. item.record
        end
        log("heldItems.hold refused for player %d: %s", playerId, tostring(reason))
    end
    return "hidden"
end

-- Take the crate out of the hand. `restore` puts it back on the ground at its loading point.
local function releaseCrate(playerId, contract, crate, restore, playerGone)
    if crate.attached then
        Open77.props.detach(crate.propId)
        crate.attached = nil
    end
    if crate.held then
        if not playerGone then
            Open77.heldItems.release(playerId, { slot = (C.Carry.heldItem and C.Carry.heldItem.slot) or "WeaponRight" })
        end
        crate.held = nil
    end
    if restore and crate.propId then
        local moved, why = Open77.props.setTransform(crate.propId, { position = crate.position, yaw = 0.0 })
        if not moved then log("crate %s could not be put back: %s", tostring(crate.propId), tostring(why)) end
        if crate.hidden then
            Open77.props.update(crate.propId, { visible = true })
            crate.hidden = nil
        end
        crate.state = "ground"
    end
end

local function removeAmbush(contract, why)
    if not contract.ambushNpcs or #contract.ambushNpcs == 0 then return end
    local removed = 0
    for _, npcId in ipairs(contract.ambushNpcs) do
        if Open77.npcs.remove(npcId) then removed = removed + 1 end
    end
    log("player %d ambush cleared: %d/%d npcs removed (%s)", contract.playerId, removed, #contract.ambushNpcs, why)
    contract.ambushNpcs = {}
end

local function createAmbusher(position, yaw, bucket)
    for _, record in ipairs(C.Ambush.records) do
        local id, reason = Open77.npcs.create({
            record = record,
            position = position,
            yaw = yaw,
            bucket = bucket,
            damagePolicy = C.Ambush.damagePolicy,
            loadout = { combat = { group = C.Ambush.group, acquirePlayers = true } },
            despawnWhenUnobserved = false,
        })
        if id then return id, record end
        log("ambush record %s refused: %s", record, tostring(reason))
    end
    return nil, "no_ambush_record"
end

local function spawnAmbush(playerId, contract, truckPos)
    contract.ambushed = true
    local dest = C.Destinations[contract.destination]
    local towards = dest and dest.position or C.Ambush.center
    local base = math.atan(towards.y - truckPos.y, towards.x - truckPos.x)
    local n = math.max(1, C.Ambush.count)
    local bucket = (Open77.players.position(playerId) or {}).bucket or 0
    local spawned, record = {}, "?"
    for i = 1, n do
        local spread = 0.0
        if n > 1 then
            spread = -C.Ambush.spreadDegrees + (i - 1) * (2 * C.Ambush.spreadDegrees / (n - 1))
        end
        local a = base + math.rad(spread)
        local x = truckPos.x + math.cos(a) * C.Ambush.spawnDistance
        local y = truckPos.y + math.sin(a) * C.Ambush.spawnDistance
        local yaw = math.deg(math.atan(truckPos.y - y, truckPos.x - x))
        local id, used = createAmbusher({ x = x, y = y, z = truckPos.z }, yaw, bucket)
        if id then
            record = used
            spawned[#spawned + 1] = id
            local okAtt, whyAtt = Open77.npcs.setAttitude(id, "hostile")
            if not okAtt then log("npc %s setAttitude refused: %s", tostring(id), tostring(whyAtt)) end
            local task, whyTask = Open77.npcs.tasks.attack(id, playerId)
            if not task then log("npc %s attack task refused: %s", tostring(id), tostring(whyTask)) end
        end
    end
    contract.ambushNpcs = spawned
    log("player %d ambushed at %.1f %.1f: %d/%d npcs record=%s", playerId, truckPos.x, truckPos.y, #spawned, n, record)
    if #spawned > 0 then
        say(playerId, C.Ambush.announce)
        toast(playerId, "warning", "Ambush", C.Ambush.announce)
    end
    CreateThread(function()
        Wait(C.Ambush.lifetimeMs)
        if contracts[playerId] == contract then removeAmbush(contract, "timeout") end
    end)
end

---------------------------------------------------------------------------------------------------
-- Contract lifecycle
---------------------------------------------------------------------------------------------------

local function endContract(playerId, contract, status, playerGone)
    if contracts[playerId] ~= contract then return end
    contracts[playerId] = nil
    contract.status = status
    contract.endedAtUnix = math.floor(Open77.time.unix())
    for _, crate in ipairs(contract.crates) do
        if crate.propId then
            releaseCrate(playerId, contract, crate, false, playerGone)
            Open77.props.remove(crate.propId)
            crate.propId = nil
        end
    end
    removeAmbush(contract, status)
    if contract.truckId then
        contract.truckRemoving = true
        Open77.vehicles.remove(contract.truckId)
        contract.truckId = nil
    end
    persistEnd(contract)
    log("player %d contract #%s %s ended: %s crates=%d/%d pay=%d bonus=%d society=%d",
        playerId, tostring(contract.rowId or contract.localId), contract.template.id, status,
        contract.delivered, contract.total, contract.pay, contract.bonus, contract.societyCut)
    if not playerGone then pushState(playerId, false) end
end

local function startContract(playerId, template)
    local dest = C.Destinations[template.destination]
    if not dest then
        say(playerId, "That contract points at a destination this server does not know. Tell the boss.")
        return
    end
    if template.crates > #C.Camp.loadingPoints then
        say(playerId, "The camp has no room to stage that many crates. Tell the boss.")
        return
    end
    local pos = Open77.players.position(playerId)
    if not pos then
        say(playerId, "The camp cannot place you. Move a step and try again.")
        return
    end
    local balance, why = cashRemove(playerId, C.Truck.rental, "nomade:rental")
    if not balance then
        if why == "insufficient_funds" then
            say(playerId, ("The truck deposit is %s in cash. You are short, choom."):format(fmtMoney(C.Truck.rental)))
        else
            say(playerId, "The wallet is offline (rp_economy: " .. tostring(why) .. "). No deposit, no truck.")
        end
        return
    end
    local truckId, record = spawnTruck(pos.bucket)
    if not truckId then
        cashAdd(playerId, C.Truck.rental, "nomade:rental_refund")
        say(playerId, "No truck could be spawned (" .. tostring(record) .. "). Deposit refunded.")
        return
    end
    local crates = {}
    for i = 1, template.crates do
        local propId, model = spawnCrate(i, pos.bucket)
        if not propId then
            for _, crate in ipairs(crates) do Open77.props.remove(crate.propId) end
            Open77.vehicles.remove(truckId)
            cashAdd(playerId, C.Truck.rental, "nomade:rental_refund")
            say(playerId, "The crates could not be staged (" .. tostring(model) .. "). Deposit refunded.")
            return
        end
        local point = C.Camp.loadingPoints[i]
        crates[i] = {
            index = i,
            propId = propId,
            model = model,
            position = { x = point.x, y = point.y, z = point.z },
            state = "ground",
        }
    end
    local now = Open77.time.monotonic()
    local contract = {
        localId = nextLocalId,
        playerId = playerId,
        identifier = Open77.players.identifier(playerId) or ("session:" .. tostring(playerId)),
        playerName = playerName(playerId),
        template = template,
        destination = template.destination,
        total = template.crates,
        crates = crates,
        truckId = truckId,
        truckRecord = record,
        truckSpawn = { x = C.Camp.truckSpawn.x, y = C.Camp.truckSpawn.y, z = C.Camp.truckSpawn.z },
        carrying = nil,
        loaded = 0,
        delivered = 0,
        pay = 0,
        bonus = 0,
        societyCut = 0,
        convoy = 1,
        status = "active",
        startedAt = now,
        deadline = now + C.Contract.timeLimitMs / 1000,
        startedAtUnix = math.floor(Open77.time.unix()),
        ambushed = false,
        ambushNpcs = {},
        atDestination = playerInZone(playerId, template.destination, dest.position, dest.radius),
        atCamp = playerInZone(playerId, C.Camp.zone, C.Camp.position, 9.0),
        store = (store.mode == "sql") and "sql" or "kvp",
    }
    nextLocalId = nextLocalId + 1
    if contract.store == "kvp" and store.mode ~= "kvp" then
        log("contract #%d logged to kvp: database not ready yet (%s)", contract.localId, tostring(store.reason or "connecting"))
    end
    contracts[playerId] = contract
    persistStart(contract)
    log("player %d accepted contract '%s' crates=%d dest=%s truck=%s record=%s deposit=%d",
        playerId, template.id, template.crates, template.destination, tostring(truckId), record, C.Truck.rental)
    say(playerId, ("Contract signed: %s. %d crates to the %s, %s per crate, %d minutes. Deposit %s taken for the truck."):format(
        template.label, template.crates, dest.label, fmtMoney(C.Contract.payPerCrate), minutes(C.Contract.timeLimitMs / 1000), fmtMoney(C.Truck.rental)))
    say(playerId, "Pick up the crates at the loading bay (E), load them in the truck (E), then drive. Bring the truck back for the deposit.")
    pushState(playerId, contract)
end

-- Nomads on duty within convoyRadius of the truck, driver first.
local function convoyMembers(playerId, contract)
    local members = { playerId }
    local onDuty = callSync("rp_jobs", "listOnDuty", "nomade")
    if type(onDuty) ~= "table" then return members end
    local anchor = truckPosition(contract) or Open77.players.position(playerId)
    if not anchor then return members end
    local positions = Open77.players.positions()
    for _, raw in ipairs(onDuty) do
        local id = tonumber(raw)
        if id and id ~= playerId then
            local p = positions[id]
            if p and dist3(p, anchor) <= C.Contract.convoyRadius then
                members[#members + 1] = id
            end
        end
    end
    return members
end

local function payBatch(playerId, contract, crates)
    local gross = crates * C.Contract.payPerCrate
    local members = convoyMembers(playerId, contract)
    local bonus = 0
    if #members >= C.Contract.convoyMinimum then
        bonus = math.floor(gross * C.Contract.convoyBonus + 0.5)
    end
    local societyCut = math.floor(gross * C.Contract.societyShare + 0.5)

    local balance, why = cashAdd(playerId, gross, "nomade:delivery")
    if balance then
        say(playerId, ("Delivered %d crate%s: +%s cash. Wallet: %s."):format(crates, crates > 1 and "s" or "", fmtMoney(gross), fmtMoney(balance)))
    else
        say(playerId, ("The client's eddies never reached you (rp_economy: %s). Tell the boss; the run is logged."):format(tostring(why)))
        log("player %d delivery pay %d refused: %s", playerId, gross, tostring(why))
    end

    local perMember = 0
    if bonus > 0 then
        perMember = math.floor(bonus / #members)
        for _, id in ipairs(members) do
            local b = cashAdd(id, perMember, "nomade:convoy")
            if b then
                say(id, ("Convoy bonus: +%s (%d nomads rode together)."):format(fmtMoney(perMember), #members))
            end
        end
    end

    local sBalance, sWhy = societyAdd(societyCut, "nomade:contract:" .. tostring(contract.rowId or contract.localId))
    if not sBalance then
        log("society %s credit %d refused: %s", SOCIETY, societyCut, tostring(sWhy))
    end

    contract.pay = contract.pay + gross
    contract.bonus = contract.bonus + bonus
    contract.societyCut = contract.societyCut + (sBalance and societyCut or 0)
    contract.convoy = math.max(contract.convoy, #members)
    log("player %d delivered %d crates pay=%d bonus=%d convoy=%d society=+%d", playerId, crates, gross, bonus, #members, sBalance and societyCut or 0)
    toast(playerId, "success", "Delivery paid", ("+%s cash%s"):format(fmtMoney(gross), bonus > 0 and (" +" .. fmtMoney(perMember) .. " convoy") or ""))
end

local function completeContract(playerId, contract)
    contract.status = "delivered"
    contract.endedAtUnix = math.floor(Open77.time.unix())
    contract.atCamp = playerInZone(playerId, C.Camp.zone, C.Camp.position, 9.0)
    removeAmbush(contract, "delivered")
    persistEnd(contract)
    log("player %d contract #%s %s delivered: crates=%d pay=%d bonus=%d society=%d convoy=%d",
        playerId, tostring(contract.rowId or contract.localId), contract.template.id,
        contract.delivered, contract.pay, contract.bonus, contract.societyCut, contract.convoy)
    say(playerId, ("Run complete. Bring the truck back inside the camp and press E on it for your %s deposit."):format(fmtMoney(C.Truck.rental)))
end

---------------------------------------------------------------------------------------------------
-- Net events (client intents; everything re-checked here)
---------------------------------------------------------------------------------------------------

RegisterNetEvent("rp_nomade:clientReady", function()
    pushState(source, contracts[source])
end)

RegisterNetEvent("rp_nomade:board", function()
    local playerId = source
    local pos = Open77.players.position(playerId)
    if not pos then return end
    local d = dist3(pos, C.Camp.board.position)
    if d > C.Camp.board.reach then
        say(playerId, ("Get closer to the contracts board (%.0f m)."):format(d))
        return
    end
    local okJob, whyJob = nomadOnDuty(playerId)
    if not okJob then
        say(playerId, whyJob)
        return
    end
    if boardOpen[playerId] then return end
    local current = contracts[playerId]
    if current then
        if current.status == "delivered" then
            say(playerId, "Return the truck first (E on it inside the camp), or /convoi annuler to forfeit the deposit.")
        else
            say(playerId, ("You already run '%s'. /convoi for the status, /convoi annuler to drop it."):format(current.template.label))
        end
        return
    end

    local options = {}
    for _, template in ipairs(C.Templates) do
        local dest = C.Destinations[template.destination]
        options[#options + 1] = {
            id = template.id,
            label = template.label,
            description = template.description,
            icon = tostring(template.crates),
            disabled = (dest == nil) or (template.crates > #C.Camp.loadingPoints),
            metadata = {
                { label = "Crates", value = tostring(template.crates) },
                { label = "Destination", value = dest and dest.label or template.destination },
                { label = "Pay", value = ("%s (%s per crate)"):format(fmtMoney(template.crates * C.Contract.payPerCrate), fmtMoney(C.Contract.payPerCrate)) },
                { label = "Time limit", value = ("%d min"):format(minutes(C.Contract.timeLimitMs / 1000)) },
            },
        }
    end
    options[#options + 1] = { id = "leave", label = "Walk away", description = "Not today.", tone = "danger" }

    local promise, err = Open77.exports.call("open77_uikit", "context", playerId, {
        id = "rp_nomade_board",
        title = "Contracts board",
        description = ("Truck deposit %s (refunded on return). Convoy bonus %d%% when %d+ nomads ride together."):format(
            fmtMoney(C.Truck.rental), math.floor(C.Contract.convoyBonus * 100 + 0.5), C.Contract.convoyMinimum),
        options = options,
    }, { timeoutMs = 60000 })
    if not promise then
        say(playerId, "The board is offline (open77_uikit: " .. tostring(err) .. ").")
        return
    end
    boardOpen[playerId] = true
    local answer, reason = promise:await()
    boardOpen[playerId] = nil
    if not answer then
        if reason ~= "callback_timeout" then
            say(playerId, "The board did not answer (" .. tostring(reason) .. ").")
        end
        return
    end
    if not answer.ok then return end
    local choice = answer.value and answer.value.id
    if choice == nil or choice == "leave" then return end
    local template
    for _, t in ipairs(C.Templates) do
        if t.id == choice then
            template = t
            break
        end
    end
    if not template then
        say(playerId, "Unknown contract.")
        return
    end
    -- The menu waited on a human: re-check what may have changed meanwhile.
    okJob, whyJob = nomadOnDuty(playerId)
    if not okJob then
        say(playerId, whyJob)
        return
    end
    if contracts[playerId] then
        say(playerId, "You already have a contract running.")
        return
    end
    startContract(playerId, template)
end)

RegisterNetEvent("rp_nomade:pickup", function(index)
    local playerId = source
    local contract = contracts[playerId]
    if not contract then
        say(playerId, "No contract running. Read the board at the nomad camp.")
        return
    end
    if contract.status ~= "active" then
        say(playerId, "That run is over. Return the truck.")
        return
    end
    if contract.carrying then
        say(playerId, "Your hands are full, choom. Load that crate first.")
        return
    end
    index = math.tointeger(tonumber(index) or 0)
    local crate = index and contract.crates[index]
    if not crate or crate.state ~= "ground" or not crate.propId then
        say(playerId, "That crate is not on the ground.")
        return
    end
    local pos = Open77.players.position(playerId)
    if not pos then
        say(playerId, "The camp cannot place you. Move a step and try again.")
        return
    end
    local d = dist3(pos, crate.position)
    if d > C.Crate.pickupDistance then
        say(playerId, ("Get closer to the crate (%.0f m)."):format(d))
        return
    end
    local how = carryCrate(playerId, contract, crate)
    contract.carrying = index
    crate.state = "carried"
    log("player %d picked up crate %d/%d (%s)", playerId, index, contract.total, how)
    say(playerId, ("Crate %d/%d on your shoulder. Get it to the truck and press E."):format(index, contract.total))
    pushState(playerId, contract)
end)

-- Common checks for the three truck prompts. Returns the contract, or nil after telling the player.
local function truckIntent(playerId, vehicleId)
    local contract = contracts[playerId]
    if not contract then
        say(playerId, "No contract running. Read the board at the nomad camp.")
        return nil
    end
    if idKey(vehicleId) ~= idKey(contract.truckId) then
        say(playerId, "That is not your rented truck.")
        return nil
    end
    local tp = truckPosition(contract)
    if not tp then
        say(playerId, "Your truck is gone.")
        endContract(playerId, contract, "truck_lost")
        return nil
    end
    local pos = Open77.players.position(playerId)
    if not pos then
        say(playerId, "The camp cannot place you. Move a step and try again.")
        return nil
    end
    local d = dist3(pos, tp)
    if d > C.Truck.reach then
        say(playerId, ("Get closer to the truck (%.0f m)."):format(d))
        return nil
    end
    return contract
end

RegisterNetEvent("rp_nomade:load", function(vehicleId)
    local playerId = source
    local contract = truckIntent(playerId, vehicleId)
    if not contract then return end
    if contract.status ~= "active" then
        say(playerId, "That run is over. Return the truck.")
        return
    end
    local index = contract.carrying
    if not index then
        say(playerId, "You are not carrying a crate. Pick one up at the loading bay.")
        return
    end
    local crate = contract.crates[index]
    releaseCrate(playerId, contract, crate, false)
    Open77.props.remove(crate.propId)
    crate.propId = nil
    crate.state = "loaded"
    contract.carrying = nil
    contract.loaded = contract.loaded + 1
    log("player %d loaded crate %d/%d", playerId, contract.loaded, contract.total)
    local dest = C.Destinations[contract.destination]
    if contract.loaded >= contract.total then
        say(playerId, ("All %d crates loaded. Drive to the %s and press E on the truck to unload. Watch the road."):format(
            contract.total, dest and dest.label or contract.destination))
    else
        say(playerId, ("Crate %d/%d loaded. %d to go."):format(contract.loaded, contract.total, contract.total - contract.loaded))
    end
    pushState(playerId, contract)
end)

RegisterNetEvent("rp_nomade:unload", function(vehicleId)
    local playerId = source
    local contract = truckIntent(playerId, vehicleId)
    if not contract then return end
    if contract.status ~= "active" then
        say(playerId, "That run is over. Return the truck.")
        return
    end
    if contract.unloading then
        say(playerId, "Already unloading.")
        return
    end
    if contract.loaded - contract.delivered <= 0 then
        say(playerId, "The truck is empty. Load the crates at the camp first.")
        return
    end
    local dest = C.Destinations[contract.destination]
    if not playerInZone(playerId, contract.destination, dest and dest.position, dest and dest.radius) then
        say(playerId, ("This is not the %s. Check the map pin."):format(dest and dest.label or contract.destination))
        return
    end
    contract.unloading = true
    local batch = 0
    while contract.loaded - contract.delivered > 0 do
        if contracts[playerId] ~= contract or contract.status ~= "active" then break end
        local promise, err = Open77.exports.call("open77_uikit", "progress", playerId, {
            label = ("Unloading crate %d/%d"):format(contract.delivered + 1, contract.total),
            duration = C.Contract.unloadMs,
            position = "bottom",
            cancellable = true,
            disable = { move = true, combat = true },
        })
        if not promise then
            say(playerId, "Unloading failed (open77_uikit: " .. tostring(err) .. ").")
            break
        end
        local answer = promise:await()
        if contracts[playerId] ~= contract then break end
        if not answer or not answer.ok then
            say(playerId, "Unloading stopped. The rest stays in the truck.")
            break
        end
        -- Still at the warehouse, still next to the truck?
        local tp = truckPosition(contract)
        local pos = Open77.players.position(playerId)
        if not tp or not pos or dist3(pos, tp) > C.Truck.reach + 2.0 then
            say(playerId, "Stay next to the truck while unloading.")
            break
        end
        contract.delivered = contract.delivered + 1
        batch = batch + 1
        log("player %d delivered crate %d/%d", playerId, contract.delivered, contract.total)
    end
    contract.unloading = false
    if contracts[playerId] ~= contract then return end
    if batch > 0 then payBatch(playerId, contract, batch) end
    if contract.delivered >= contract.total then completeContract(playerId, contract) end
    pushState(playerId, contract)
end)

RegisterNetEvent("rp_nomade:return", function(vehicleId)
    local playerId = source
    local contract = truckIntent(playerId, vehicleId)
    if not contract then return end
    if contract.carrying then
        say(playerId, "Put the crate down first: load it, or /convoi annuler.")
        return
    end
    if contract.loaded - contract.delivered > 0 then
        say(playerId, "There is still cargo in the back. Deliver it, or /convoi annuler to forfeit the deposit.")
        return
    end
    if not playerInZone(playerId, C.Camp.zone, C.Camp.position, 9.0) then
        say(playerId, "Bring the truck inside the camp ring to return it.")
        return
    end
    local wasDelivered = contract.status == "delivered"
    local balance, why = cashAdd(playerId, C.Truck.rental, "nomade:rental_refund")
    if balance then
        say(playerId, ("Truck returned. Deposit %s refunded. Wallet: %s."):format(fmtMoney(C.Truck.rental), fmtMoney(balance)))
    else
        say(playerId, ("Truck returned, but the deposit could not be refunded (rp_economy: %s)."):format(tostring(why)))
    end
    log("player %d returned the truck, deposit %s", playerId, balance and "refunded" or ("refund refused: " .. tostring(why)))
    endContract(playerId, contract, wasDelivered and "delivered" or "returned")
end)

---------------------------------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------------------------------

local function statusLines(playerId, contract)
    local dest = C.Destinations[contract.destination]
    local lines = {}
    lines[#lines + 1] = ("Contract: %s -> %s (%s per crate)."):format(contract.template.label, dest and dest.label or contract.destination, fmtMoney(C.Contract.payPerCrate))
    local carrying = contract.carrying and (", carrying crate " .. contract.carrying) or ""
    lines[#lines + 1] = ("Crates: %d/%d loaded, %d/%d delivered%s."):format(contract.loaded, contract.total, contract.delivered, contract.total, carrying)
    if contract.status == "active" then
        local left = math.max(0, contract.deadline - Open77.time.monotonic())
        lines[#lines + 1] = ("Time left: %d min. Truck: %s (deposit %s, refunded on return in the camp)."):format(minutes(left), contract.truckRecord, fmtMoney(C.Truck.rental))
    else
        lines[#lines + 1] = ("Delivered: %s paid, %s bonus. Return the truck inside the camp (E) for the deposit."):format(fmtMoney(contract.pay), fmtMoney(contract.bonus))
    end
    local members = convoyMembers(playerId, contract)
    local names = {}
    for i = 2, #members do names[#names + 1] = playerName(members[i]) end
    if #members >= C.Contract.convoyMinimum then
        lines[#lines + 1] = ("Convoy: you + %s (%d, bonus %d%% armed)."):format(table.concat(names, ", "), #members, math.floor(C.Contract.convoyBonus * 100 + 0.5))
    else
        lines[#lines + 1] = ("Convoy: none. Another nomad on duty within %d m at delivery earns the %d%% bonus."):format(math.floor(C.Contract.convoyRadius), math.floor(C.Contract.convoyBonus * 100 + 0.5))
    end
    if contract.ambushed then
        lines[#lines + 1] = "The Wraiths already hit this convoy."
    end
    return lines
end

RegisterCommand("convoi", function(source, args)
    if source == 0 then return print("convoi: run this from the game") end
    local sub = (args[1] or ""):lower()
    local contract = contracts[source]
    if sub == "annuler" or sub == "cancel" then
        if not contract then
            say(source, "No contract to cancel.")
            return
        end
        local label = contract.template.label
        endContract(source, contract, "cancelled")
        say(source, ("Contract '%s' dropped. The truck and the crates are gone; the deposit stays with the clan."):format(label))
        return
    end
    if not contract then
        say(source, "No contract running. Read the board at the nomad camp (/camp for the way).")
        return
    end
    for _, line in ipairs(statusLines(source, contract)) do
        say(source, line)
        Wait(0)
    end
end, false)

RegisterCommand("convois", function(source)
    if source == 0 then return print("convois: run this from the game as the nomad boss") end
    if not isNomadBoss(source) then
        say(source, "Boss only. The clan's books are not for everyone.")
        return
    end
    local rows, from = loadHistory(C.Contract.historyRows)
    if #rows == 0 then
        say(source, "No contract on the books yet.")
        return
    end
    local now = math.floor(Open77.time.unix())
    say(source, ("Last %d convoys (%s):"):format(#rows, from))
    for _, row in ipairs(rows) do
        Wait(0)
        local started = tonumber(row.started_at) or 0
        local ended = tonumber(row.ended_at) or 0
        local took = (ended > 0 and started > 0) and (" in " .. minutes(ended - started) .. " min") or ""
        local ago = started > 0 and (minutes(now - started) .. " min ago") or "?"
        say(source, ("#%s %s: %s -> %s, %s/%s crates, %s +%s bonus, society +%s, convoy %s, %s%s, %s."):format(
            tostring(row.id), tostring(row.player_name), tostring(row.template), tostring(row.destination),
            tostring(row.delivered), tostring(row.crates), fmtMoney(tonumber(row.pay) or 0), fmtMoney(tonumber(row.bonus) or 0),
            fmtMoney(tonumber(row.society_cut) or 0), tostring(row.convoy), tostring(row.status), took, ago))
    end
end, false)

local function compass(dx, dy)
    local angle = math.deg(math.atan(dy, dx))   -- 0 = east, 90 = north
    local names = { "east", "north-east", "north", "north-west", "west", "south-west", "south", "south-east" }
    local index = math.floor(((angle + 360 + 22.5) % 360) / 45) + 1
    return names[index] or "?"
end

RegisterCommand("camp", function(source)
    if source == 0 then
        return print(("camp: %.1f, %.1f, %.1f (zone %s)"):format(C.Camp.position.x, C.Camp.position.y, C.Camp.position.z, C.Camp.zone))
    end
    local camp = C.Camp.position
    local pos = Open77.players.position(source)
    if not pos then
        say(source, ("Nomad camp: %.0f, %.0f (z %.0f)."):format(camp.x, camp.y, camp.z))
        return
    end
    local d = dist2(pos, camp)
    say(source, ("Nomad camp: %.0f, %.0f (z %.0f), %.0f m %s of you. The contracts board is the small ring by the camp."):format(
        camp.x, camp.y, camp.z, d, compass(camp.x - pos.x, camp.y - pos.y)))
end, false)

---------------------------------------------------------------------------------------------------
-- Host and bus events
---------------------------------------------------------------------------------------------------

local SUGGESTIONS = {
    { command = "/convoi", help = "Your convoy contract: crates, time left, convoy. `/convoi annuler` drops it.",
      parameters = { { name = "annuler", help = "optional: cancel the contract" } } },
    { command = "/convois", help = "Nomad boss: the last contracts on the clan's books" },
    { command = "/camp", help = "Where the nomad camp is and how far" },
}

RegisterNetEvent("chat:ready", function()
    Open77.chat.addSuggestions(source, SUGGESTIONS)
end)

local function defineItems()
    local ok, registered, rejected = pcall(function()
        return exports.rp_inventory:define(C.Items)
    end)
    if ok then
        log("rp_inventory items defined: registered=%s rejected=%s", tostring(registered), tostring(rejected))
    else
        log("rp_inventory not reachable, nomad_crate not defined (%s)", tostring(registered))
    end
end

AddEventHandler("onResourceStart", function(name)
    if name == RESOURCE then
        Open77.chat.addSuggestions(-1, SUGGESTIONS)
        defineItems()
        log("started: %d templates, camp at %.1f %.1f %.1f, board at %.1f %.1f, ambush %s at %.1f %.1f r=%.0f, carry=%s",
            #C.Templates, C.Camp.position.x, C.Camp.position.y, C.Camp.position.z,
            C.Camp.board.position.x, C.Camp.board.position.y,
            C.Ambush.enabled and "on" or "off", C.Ambush.center.x, C.Ambush.center.y, C.Ambush.radius, C.Carry.mode)
        -- A database that never answers: fall back to kvp for the history after 15 s.
        CreateThread(function()
            Wait(15000)
            if store.mode == "pending" then
                local isReady, why = Open77.database.isReady()
                if not isReady then useKvp(why or "database_not_ready") end
            end
        end)
    elseif name == "rp_inventory" then
        defineItems()
    end
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= RESOURCE then return end
    for playerId, contract in pairs(contracts) do
        endContract(playerId, contract, "resource_stopped")
    end
end)

AddEventHandler("onPlayerDisconnected", function(playerId)
    local id = tonumber(playerId)
    if id then boardOpen[id] = nil end
    local contract = id and contracts[id]
    if not contract then return end
    endContract(id, contract, "abandoned", true)
end)

-- Down or dead while carrying: the crate goes back to the loading bay.
AddEventHandler("onPlayerLifeStateChanged", function(playerId, revision, phase)
    local id = tonumber(playerId)
    local contract = id and contracts[id]
    if not contract or not contract.carrying then return end
    if tostring(phase):lower() == "alive" then return end
    local crate = contract.crates[contract.carrying]
    releaseCrate(id, contract, crate, true)
    contract.carrying = nil
    log("player %d dropped crate %d/%d (life phase %s), back at the loading bay", id, crate.index, contract.total, tostring(phase))
    say(id, "You went down. The crate is back at the loading bay.")
    pushState(id, contract)
end)

AddEventHandler("onVehicleRemoved", function(vehicleId, reason)
    for playerId, contract in pairs(contracts) do
        if contract.truckId and idKey(vehicleId) == idKey(contract.truckId) and not contract.truckRemoving then
            log("player %d truck %s removed by the world (%s)", playerId, tostring(vehicleId), tostring(reason))
            say(playerId, "Your truck is gone. The run is over; the deposit stays with the clan.")
            contract.truckId = nil
            endContract(playerId, contract, "truck_lost")
        end
    end
end)

AddEventHandler("open77:helditem:completed", function(player, requestId, operation, accepted, reason)
    local pending = heldRequests[requestId]
    if not pending then return end
    heldRequests[requestId] = nil
    log("player %s held item %s: %s%s", tostring(player), tostring(operation), accepted and "accepted" or "refused", accepted and "" or (" (" .. tostring(reason) .. ")"))
end)

AddEventHandler("rp_zones:entered", function(playerId, name)
    local id = tonumber(playerId)
    local contract = id and contracts[id]
    if not contract then return end
    local changed = false
    if name == contract.destination and not contract.atDestination then
        contract.atDestination = true
        changed = true
        if contract.status == "active" and contract.loaded - contract.delivered > 0 then
            say(id, "You made it. Park, get out and press E on the truck to unload.")
        end
    end
    if name == C.Camp.zone and not contract.atCamp then
        contract.atCamp = true
        changed = true
    end
    if changed then pushState(id, contract) end
end)

AddEventHandler("rp_zones:left", function(playerId, name)
    local id = tonumber(playerId)
    local contract = id and contracts[id]
    if not contract then return end
    local changed = false
    if name == contract.destination and contract.atDestination then
        contract.atDestination = false
        changed = true
    end
    if name == C.Camp.zone and contract.atCamp then
        contract.atCamp = false
        changed = true
    end
    if changed then pushState(id, contract) end
end)

---------------------------------------------------------------------------------------------------
-- Tick: deadline, truck watch, ambush
---------------------------------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(C.Ui.tickMs)
        local now = Open77.time.monotonic()
        for playerId, contract in pairs(contracts) do
            if contract.status == "active" then
                if now > contract.deadline and not contract.unloading then
                    say(playerId, "Too slow, choom. The client walked; the truck and the crates are gone.")
                    endContract(playerId, contract, "expired")
                else
                    local tp = truckPosition(contract)
                    if not tp then
                        -- A few seconds of grace after the spawn; then a missing truck ends the run.
                        if now - contract.startedAt > 5.0 then
                            say(playerId, "Your truck is gone. The run is over.")
                            endContract(playerId, contract, "truck_lost")
                        end
                    elseif C.Ambush.enabled and not contract.ambushed
                        and contract.loaded - contract.delivered > 0
                        and dist2(tp, C.Ambush.center) <= C.Ambush.radius
                        and dist2(tp, contract.truckSpawn) >= C.Ambush.minTravel then
                        spawnAmbush(playerId, contract, tp)
                    end
                end
            end
        end
    end
end)

---------------------------------------------------------------------------------------------------
-- Exports (synchronous, never yield)
---------------------------------------------------------------------------------------------------

exports("activeContract", function(playerId)
    local id = tonumber(playerId)
    local contract = id and contracts[id]
    if not contract then return nil end
    return {
        id = contract.rowId or contract.localId,
        template = contract.template.id,
        label = contract.template.label,
        destination = contract.destination,
        crates = contract.total,
        loaded = contract.loaded,
        delivered = contract.delivered,
        carrying = contract.carrying,
        status = contract.status,
        truckId = contract.truckId,
        ambushed = contract.ambushed,
    }
end)

exports("hasContract", function(playerId)
    local id = tonumber(playerId)
    return id ~= nil and contracts[id] ~= nil
end)
