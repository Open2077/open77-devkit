-- eval_cuff / server
--
-- Two restricted commands, modelled on the open77_rp_basics kit:
--   /cuff <playerId>    freeze the target (Open77.players.setFrozen), loop the
--                       `handsup` pose, take the whole control stream on his client
--   /escort <playerId>  the target walks himself with everything but movement
--                       blocked; a 2 Hz tick pulls him back when he drifts
--
-- Either command on a target the same officer already holds toggles that hold
-- off (the release path); the other verb on him supersedes the hold.
-- Callers must hold the ACL entry command.cuff / command.escort.

local Rules = {
    maxDistance        = 3.0,    -- how close the officer must be to start a verb
    tetherDistance     = 5.0,    -- how far an escorted player may drift
    tetherPullDistance = 1.6,    -- where a pull puts him, from the officer
    tetherCooldownMs   = 2000,   -- floor between two pulls
    maxHoldMs          = 900000, -- ceiling on any hold: nothing strands a player
    positionMaxAgeMs   = 2000,   -- older than this and a position is not evidence
    tickMs             = 500,    -- the sweep: 2 Hz
}

local CONTROL_EVENT = "eval_cuff:control"   -- server -> client: "cuff" | "escort" | "free"
local SYNC_EVENT    = "eval_cuff:sync"      -- client -> server: re-issue my block after a reload
local POSE          = "handsup"

-- holds[targetId] = { officer, target, verb, bucket, startedAt, expiresAt,
--                     claims = { freeze, animation, client }, pulling, lastPullAt }
local holds = {}
local byOfficer = {}

local function say(playerId, text)
    Open77.chat.send(playerId, text)
end

local function nameOf(playerId)
    return Open77.players.name(playerId) or ("#" .. tostring(playerId))
end

-- The server's own reads, never the caller's claims.
local function readPlayer(playerId)
    local read = Open77.players.get(playerId)
    if not read then return nil, "player_not_found" end
    if not read.ready then return nil, "player_not_ready" end
    if not read.position or not read.ageMs or read.ageMs > Rules.positionMaxAgeMs then
        return nil, "position_stale"
    end
    return read
end

local function isAlive(playerId)
    local life = Open77.players.getLifeState(playerId)
    return life ~= nil and life.phase == "alive"
end

-- Everything that must be true before a verb is allowed to take anything.
local function checkPair(officer, target)
    if target == officer then return false, "target_is_self" end
    if holds[officer] then return false, "officer_held" end

    local officerRead, reason = readPlayer(officer)
    if not officerRead then return false, "officer_" .. reason end
    local targetRead, treason = readPlayer(target)
    if not targetRead then return false, "target_" .. treason end

    -- A server-side action on a client that is not alive crashes that client.
    if not isAlive(target) then return false, "target_not_alive" end
    if not isAlive(officer) then return false, "officer_not_alive" end

    if officerRead.bucket ~= targetRead.bucket then return false, "different_bucket" end

    local metres, derr = Open77.players.distance(officer, target)
    if not metres then return false, derr or "distance_unknown" end
    if metres > Rules.maxDistance then return false, "too_far" end

    return true, nil, targetRead.bucket
end

local function sendControl(target, mode)
    local ok, reason = TriggerClientEvent(CONTROL_EVENT, target, mode)
    if not ok and reason then
        print(("eval_cuff: control event to %s refused: %s"):format(tostring(target), tostring(reason)))
    end
    return ok
end

-- The one function through which every hold ends. Every platform call is
-- wrapped so that one refusal cannot skip the next.
local function release(target, reason)
    local hold = holds[target]
    if not hold then return false end
    holds[target] = nil
    if byOfficer[hold.officer] == target then byOfficer[hold.officer] = nil end

    if hold.claims.freeze then
        local ok, res, err = pcall(Open77.players.setFrozen, target, false)
        if not ok or not res then
            local why = ok and (err or "refused") or res
            print(("eval_cuff: thaw of %s refused: %s"):format(tostring(target), tostring(why)))
        end
    end
    if hold.claims.animation then
        local ok, res, err = pcall(Open77.animations.stop, target, hold.claims.animation)
        if not ok or not res then
            local why = ok and (err or "refused") or res
            print(("eval_cuff: pose stop for %s refused: %s"):format(tostring(target), tostring(why)))
        end
    end
    if hold.claims.client then
        pcall(sendControl, target, "free")
    end

    local verb = hold.verb == "cuff" and "cuffs" or "escort"
    pcall(say, target, ("Your %s ended (%s)."):format(verb, reason))
    if reason ~= "released" and reason ~= "superseded" then
        pcall(say, hold.officer, ("%s on %s ended (%s)."):format(
            hold.verb == "cuff" and "Cuffs" or "Escort", nameOf(target), reason))
    end
    return true
end

local function releaseAll(reason)
    local targets = {}
    for target in pairs(holds) do targets[#targets + 1] = target end
    for _, target in ipairs(targets) do release(target, reason) end
end

-- Takes the freeze, then the pose (best effort), then the client block.
local function applyCuff(officer, target, bucket)
    local ok, reason = Open77.players.setFrozen(target, true)
    if not ok then return false, "freeze_refused:" .. tostring(reason) end

    local now = GetGameTimer()
    local hold = {
        officer = officer, target = target, verb = "cuff", bucket = bucket,
        startedAt = now, expiresAt = now + Rules.maxHoldMs,
        claims = { freeze = true, animation = nil, client = false },
        pulling = false, lastPullAt = 0,
    }
    holds[target] = hold
    byOfficer[officer] = target

    -- Stationary loop; the freeze keeps the body inside the 0.5 m cancel radius.
    local playback, perr = Open77.animations.play(target, POSE, { loop = true })
    if playback then
        hold.claims.animation = playback.playbackId
    else
        print(("eval_cuff: %s pose on %s refused: %s"):format(POSE, tostring(target), tostring(perr)))
        say(officer, ("Cuffed, but the pose was refused (%s)."):format(tostring(perr)))
    end

    hold.claims.client = sendControl(target, "cuff") and true or false
    return true
end

-- No freeze and no pose: RP profiles are stationary and walking cancels them.
local function applyEscort(officer, target, bucket)
    local now = GetGameTimer()
    local hold = {
        officer = officer, target = target, verb = "escort", bucket = bucket,
        startedAt = now, expiresAt = now + Rules.maxHoldMs,
        claims = { freeze = false, animation = nil, client = false },
        pulling = false, lastPullAt = 0,
    }
    holds[target] = hold
    byOfficer[officer] = target
    hold.claims.client = sendControl(target, "escort") and true or false
    return true
end

local function parseTarget(args)
    local id = tonumber(args and args[1])
    if not id or id <= 0 or id ~= math.floor(id) then return nil end
    return math.floor(id)
end

-- Shared front half of both commands: argument, authority of the body, the
-- toggle/supersede decision, then the pair checks.
local function verb(source, args, verbName, apply)
    if source == 0 then
        print("eval_cuff: /" .. verbName .. " needs a body; the console has none.")
        return
    end
    local target = parseTarget(args)
    if not target then return say(source, ("Usage: /%s <playerId>"):format(verbName)) end

    local existing = holds[target]
    if existing and existing.officer ~= source then
        return say(source, ("%s is already held by %s."):format(nameOf(target), nameOf(existing.officer)))
    end
    if existing and existing.verb == verbName then
        release(target, "released")
        return say(source, ("Released %s."):format(nameOf(target)))
    end
    local busyWith = byOfficer[source]
    if busyWith and busyWith ~= target then
        return say(source, ("You are already holding %s; release them first."):format(nameOf(busyWith)))
    end

    local ok, reason, bucket = checkPair(source, target)
    if not ok then
        print(("eval_cuff: /%s by %s on %s refused: %s"):format(verbName, tostring(source), tostring(target), tostring(reason)))
        return say(source, ("Cannot %s %s: %s"):format(verbName, nameOf(target), reason))
    end

    if existing then release(target, "superseded") end

    local applied, aerr = apply(source, target, bucket)
    if not applied then
        print(("eval_cuff: /%s by %s on %s failed: %s"):format(verbName, tostring(source), tostring(target), tostring(aerr)))
        return say(source, ("Cannot %s %s: %s"):format(verbName, nameOf(target), aerr))
    end
    print(("eval_cuff: /%s by %s on %s applied"):format(verbName, tostring(source), tostring(target)))

    say(source, ("%s %s."):format(verbName == "cuff" and "Cuffed" or "Escorting", nameOf(target)))
    say(target, verbName == "cuff"
        and ("You have been cuffed by %s."):format(nameOf(source))
        or ("You are being escorted by %s. Stay close."):format(nameOf(source)))
end

RegisterCommand("cuff", function(source, args)
    verb(source, args, "cuff", applyCuff)
end, true)

RegisterCommand("escort", function(source, args)
    verb(source, args, "escort", applyEscort)
end, true)

-- One pull at a time, with a floor between them: teleport resolves only once
-- the body settled and refuses a second placement with settle_superseded.
local function pull(hold, officerPos, targetPos)
    hold.pulling = true
    local dx, dy = targetPos.x - officerPos.x, targetPos.y - officerPos.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then dx, dy, len = 1, 0, 1 end
    local point = {
        x = officerPos.x + dx / len * Rules.tetherPullDistance,
        y = officerPos.y + dy / len * Rules.tetherPullDistance,
        z = officerPos.z,
    }
    CreateThread(function()
        local landed, err
        local pending, reason = Open77.players.teleport(hold.target, point, { fade = false, timeoutMs = 5000 })
        if pending then
            landed, err = pending:await()
        else
            err = reason
        end
        hold.pulling = false
        hold.lastPullAt = GetGameTimer()
        if holds[hold.target] ~= hold or landed then return end
        if err == "player_in_vehicle" then
            release(hold.target, "target_mounted")
        elseif err == "player_not_alive" then
            release(hold.target, "target_dead")
        else
            -- A stale body, a slow stream-in, a superseded settle: pause, never end on thin evidence.
            print(("eval_cuff: tether pull of %s did not land: %s"):format(tostring(hold.target), tostring(err)))
        end
    end)
end

-- The deadline is underneath every other ending; the rest are named paths.
local function sweepOne(target, hold, now)
    if now >= hold.expiresAt then return release(target, "expired") end

    local officerRead = Open77.players.get(hold.officer)
    if not officerRead then return release(target, "officer_left") end
    local targetRead = Open77.players.get(target)
    if not targetRead then return release(target, "target_left") end

    if not isAlive(hold.officer) then return release(target, "officer_dead") end
    if not isAlive(target) then return release(target, "target_dead") end

    if officerRead.bucket ~= hold.bucket then return release(target, "officer_bucket_changed") end
    if targetRead.bucket ~= hold.bucket then return release(target, "target_bucket_changed") end

    if hold.verb ~= "escort" or hold.pulling then return end
    if now - hold.lastPullAt < Rules.tetherCooldownMs then return end

    -- Both positions must be evidence before a leash is allowed to pull.
    if not officerRead.position or not targetRead.position then return end
    if (officerRead.ageMs or math.huge) > Rules.positionMaxAgeMs then return end
    if (targetRead.ageMs or math.huge) > Rules.positionMaxAgeMs then return end

    local metres = Open77.players.distance(officerRead.position, targetRead.position)
    if metres and metres > Rules.tetherDistance then
        pull(hold, officerRead.position, targetRead.position)
    end
end

CreateThread(function()
    while true do
        Wait(Rules.tickMs)
        local now = GetGameTimer()
        local targets = {}
        for target in pairs(holds) do targets[#targets + 1] = target end
        for _, target in ipairs(targets) do
            local hold = holds[target]
            if hold then sweepOne(target, hold, now) end
        end
    end
end)

-- A client-side reload dropped its claim while the server still holds the player.
RegisterNetEvent(SYNC_EVENT, function()
    local playerId = tonumber(source)
    if not playerId or playerId <= 0 then return end
    local hold = holds[playerId]
    if not hold then return end
    hold.claims.client = sendControl(playerId, hold.verb) and true or false
end)

AddEventHandler("onPlayerDisconnected", function(playerId)
    local id = tonumber(playerId)
    if not id then return end
    if holds[id] then release(id, "target_left") end
    local held = byOfficer[id]
    if held then release(held, "officer_left") end
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    releaseAll("resource_stopping")
end)
