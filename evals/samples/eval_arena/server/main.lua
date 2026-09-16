-- eval_arena: server authority. Who is in, who is alive, who won and where every body
-- goes is decided here; the client only renders what it is told.
--
-- Round state machine:   idle -> waiting -> live -> resolving -> idle
--   idle       nobody in the arena bucket
--   waiting    players landing and walking around, god mode on; countdown once minPlayers
--   live       fighting; a death is an elimination; ends at one alive or the time limit
--   resolving  winner announced, everyone returned to the main bucket, then idle
--
-- Participant states:    entering -> arena -> alive -> eliminated -> returning
-- plus `queue`: players who asked during a live round, admitted once it has resolved.

local config = Config -- from shared/config.lua
local MAIN, ARENA = config.mainBucket, config.arenaBucket

local phase = "idle"
local phaseSince = GetGameTimer()
local countdownEndsAt = nil -- ms, waiting only
local roundEndsAt = nil     -- ms, live only

local roster = {}      -- playerId -> { state, returning, returnTo = {x,y,z}, returnHeading, spawn, joinedAt, protectedUntil }
local queue = {}       -- playerId -> true
local pendingAmmo = {} -- tostring(requestId) -> { slot, ammo }: ammo to apply once the assign lands
local spawns = {}      -- { x, y, z, heading }; from config, or a ring, plus /arena.mark
local nextSpawn = 0

local ALLOWED = {
    idle      = { waiting = true },
    waiting   = { idle = true, live = true },
    live      = { resolving = true },
    resolving = { idle = true },
}

local CHAT_COLOR = { r = 255, g = 120, b = 0 }

-- ---------------------------------------------------------------- helpers

local function log(fmt, ...)
    print(("eval_arena: " .. fmt):format(...))
end

local function nameOf(playerId)
    return Open77.players.name(playerId) or ("player " .. tostring(playerId))
end

local function say(playerId, text)
    local ok, reason = Open77.chat.send(playerId, { author = "Arena", text = text, color = CHAT_COLOR })
    if not ok then log("chat to %s refused: %s", tostring(playerId), tostring(reason)) end
end

local function shout(text)
    local ok, reason = Open77.chat.broadcast({ author = "Arena", text = text, color = CHAT_COLOR })
    if not ok then log("broadcast refused: %s", tostring(reason)) end
end

local function toast(playerId, text)
    TriggerClientEvent("eval_arena:toast", playerId, text)
end

-- One line to every participant, in chat and as a toast.
local function tellArena(text)
    for playerId in pairs(roster) do
        say(playerId, text)
        toast(playerId, text)
    end
end

local function count(state)
    local n = 0
    for _, entry in pairs(roster) do
        if state == nil or entry.state == state then n = n + 1 end
    end
    return n
end

local function idsInState(state)
    local ids = {}
    for playerId, entry in pairs(roster) do
        if entry.state == state then ids[#ids + 1] = playerId end
    end
    table.sort(ids)
    return ids
end

local function capacity()
    return math.min(config.maxPlayers, #spawns)
end

local function transition(to, detail)
    if not (ALLOWED[phase] and ALLOWED[phase][to]) then
        log("refused transition %s -> %s (%s)", phase, to, tostring(detail))
        return false
    end
    log("%s -> %s (%s)", phase, to, tostring(detail))
    phase, phaseSince = to, GetGameTimer()
    return true
end

-- Run step(playerId) in its own coroutine for every id; done() once all have finished.
-- A step that throws is logged and still counted, so a resolve can never hang on one body.
local function forEachAsync(ids, step, done)
    local remaining = #ids
    if remaining == 0 then return done() end
    for _, playerId in ipairs(ids) do
        CreateThread(function()
            local ok, err = pcall(step, playerId)
            if not ok then log("step failed for %s: %s", tostring(playerId), tostring(err)) end
            remaining = remaining - 1
            if remaining == 0 then done() end
        end)
    end
end

-- Moves a living, ready player and waits for the body to settle. nil, reason on failure.
-- Must run inside a managed coroutine (the promise is awaited).
local function place(playerId, position, heading, bucket)
    local pending, reason = Open77.players.teleport(playerId,
        { x = position.x, y = position.y, z = position.z },
        { heading = heading or 0.0, bucket = bucket, dismount = true, timeoutMs = 8000 })
    if not pending then return nil, reason end
    return pending:await()
end

local function buildSpawns()
    spawns = {}
    if #config.spawns > 0 then
        for _, mark in ipairs(config.spawns) do
            spawns[#spawns + 1] = { x = mark.x, y = mark.y, z = mark.z, heading = mark.heading or 0.0 }
        end
        return
    end
    local c = config.arenaCenter
    for i = 0, config.spawnCount - 1 do
        local angle = (2 * math.pi * i) / config.spawnCount
        spawns[#spawns + 1] = {
            x = c.x + math.cos(angle) * config.spawnRadius,
            y = c.y + math.sin(angle) * config.spawnRadius,
            z = c.z,
            heading = (math.deg(angle) + 180.0) % 360.0, -- face the centre
        }
    end
    if #spawns == 0 then -- spawnCount 0: one mark on the centre rather than a division by zero
        spawns[1] = { x = c.x, y = c.y, z = c.z, heading = 0.0 }
    end
    log("using a PROVISIONAL %d-mark ring around %.2f %.2f %.2f; survey it with /arena.mark",
        #spawns, c.x, c.y, c.z)
end

local function takeSpawn()
    local mark = spawns[(nextSpawn % #spawns) + 1]
    nextSpawn = nextSpawn + 1
    return mark
end

-- ---------------------------------------------------------------- loadout

local function giveLoadout(playerId)
    for _, item in ipairs(config.loadout) do
        local requestId, reason = Open77.weapons.assign(playerId, item.record, item.slot,
            { active = item.active == true, addToInventory = true })
        if not requestId then
            log("assign %s slot %d refused for %d: %s", item.record, item.slot, playerId, tostring(reason))
            say(playerId, ("Loadout problem on slot %d: %s"):format(item.slot, tostring(reason)))
        elseif item.ammo then
            pendingAmmo[tostring(requestId)] = { slot = item.slot, ammo = item.ammo }
        end
    end
end

-- The relay answers every request of ours here, matched to this resource.
AddEventHandler("open77:weapons:completed", function(playerId, requestId, operation, accepted, reason, result)
    playerId = tonumber(playerId)
    local follow = pendingAmmo[tostring(requestId)]
    pendingAmmo[tostring(requestId)] = nil
    local ok = accepted == true or accepted == "true"
    if not ok then
        log("weapon %s for %s refused: %s", tostring(operation), tostring(playerId), tostring(reason))
        if playerId and roster[playerId] then
            say(playerId, ("Loadout problem (%s): %s"):format(tostring(operation), tostring(reason)))
        end
        return
    end
    if follow and playerId and roster[playerId] then
        local id, err = Open77.weapons.setAmmo(playerId, follow.slot, follow.ammo)
        if not id then log("setAmmo slot %d refused for %d: %s", follow.slot, playerId, tostring(err)) end
    end
end)

-- ---------------------------------------------------------------- round flow (forward decls)

local checkCountdown, checkWin, admit

-- ---------------------------------------------------------------- return transaction

-- The arena is empty again? Only meaningful while waiting; resolve() owns the other phases.
local function afterReturn()
    if phase ~= "waiting" then return end
    checkCountdown()
    if count() == 0 then transition("idle", "arena emptied") end
end

-- Puts one participant back in the main bucket where they stood when they joined: alive,
-- without the arena kit, without god mode. Handles a body in any life phase; a transition
-- in flight (revivepending / respawnpending) is retried, never guessed at.
local function returnPlayer(playerId)
    local entry = roster[playerId]
    if not entry then return end
    if entry.returning then
        -- Another coroutine is already returning this body (a leaver whose round then
        -- resolved). Wait for it, so a caller that needs "everyone is back" really gets it.
        local deadline = GetGameTimer() + 15000
        while roster[playerId] and GetGameTimer() < deadline do Wait(250) end
        return
    end
    entry.returning = true
    entry.state = "returning"
    entry.protectedUntil = nil

    Open77.players.setGodMode(playerId, false)
    local clearId, clearReason = Open77.weapons.clear(playerId)
    if not clearId then log("weapons.clear refused for %d: %s", playerId, tostring(clearReason)) end

    local dest, moved = entry.returnTo, false
    for attempt = 1, 8 do
        if not roster[playerId] then return end -- disconnected meanwhile
        local life = Open77.players.getLifeState(playerId)
        local lifePhase = life and life.phase
        if lifePhase == "alive" then
            local landed, reason = place(playerId, dest, entry.returnHeading, MAIN)
            if landed then
                moved = true
                break
            end
            log("return teleport for %d refused (attempt %d): %s", playerId, attempt, tostring(reason))
        elseif lifePhase == "dead" then
            local ok, reason = Open77.players.respawn(playerId, {
                position = { x = dest.x, y = dest.y, z = dest.z },
                heading = entry.returnHeading or 0.0,
                bucket = MAIN,
                health = 1.0,
            })
            if ok then
                moved = true
                break
            end
            log("return respawn for %d refused (attempt %d): %s", playerId, attempt, tostring(reason))
        else
            log("return for %d waiting on life phase %s (attempt %d)", playerId, tostring(lifePhase), attempt)
        end
        Wait(500)
    end

    -- Whatever happened above, nobody stays scoped to the arena.
    if not moved and Open77.routingBuckets.getPlayer(playerId) == ARENA then
        log("falling back to a bare bucket switch for %d", playerId)
        Open77.routingBuckets.setPlayer(playerId, MAIN)
    end
    Open77.players.restoreHealth(playerId)
    roster[playerId] = nil
    say(playerId, "Back to the city.")
    afterReturn()
end

-- ---------------------------------------------------------------- round flow

checkCountdown = function()
    if phase ~= "waiting" then return end
    local n = count("arena")
    if n >= config.minPlayers then
        if not countdownEndsAt then
            countdownEndsAt = GetGameTimer() + config.countdownSeconds * 1000
            tellArena(("%d players in. The round starts in %d seconds."):format(n, config.countdownSeconds))
        end
    elseif countdownEndsAt then
        countdownEndsAt = nil
        tellArena(("Countdown cancelled: %d of %d players."):format(n, config.minPlayers))
    end
end

local function admitQueued()
    local waiting = {}
    for playerId in pairs(queue) do waiting[#waiting + 1] = playerId end
    table.sort(waiting)
    queue = {}
    for _, playerId in ipairs(waiting) do
        if Open77.players.name(playerId) then -- still connected
            local ok, reason = admit(playerId)
            if not ok then say(playerId, "Could not enter the next round: " .. tostring(reason)) end
        end
    end
end

local function resolve(winnerId, why)
    if not transition("resolving", why) then return end
    roundEndsAt, countdownEndsAt = nil, nil

    local text
    if winnerId then
        text = ("%s wins the arena round! (%s)"):format(nameOf(winnerId), why)
    else
        text = ("The arena round ends with no winner (%s)."):format(why)
    end
    shout(text) -- the whole server hears the result
    for playerId in pairs(roster) do toast(playerId, text) end

    local ids = {}
    for playerId in pairs(roster) do ids[#ids + 1] = playerId end
    table.sort(ids)
    forEachAsync(ids, returnPlayer, function()
        -- A step that failed may have left an entry; it must not leak into the next round.
        for playerId in pairs(roster) do
            log("dropping stale roster entry for %d after resolve", playerId)
            roster[playerId] = nil
        end
        transition("idle", "everyone returned")
        admitQueued()
    end)
end

checkWin = function()
    if phase ~= "live" then return end
    local alive = idsInState("alive")
    if #alive == 1 then
        resolve(alive[1], "last one standing")
    elseif #alive == 0 then
        resolve(nil, "nobody left standing")
    end
end

local function eliminate(playerId, why)
    local entry = roster[playerId]
    if not entry or entry.state ~= "alive" or phase ~= "live" then return end
    entry.state = "eliminated"
    entry.protectedUntil = nil
    tellArena(("%s is out (%s). %d remain."):format(nameOf(playerId), tostring(why), count("alive")))
    checkWin()
end

local function goLive()
    if not transition("live", ("%d players"):format(count("arena"))) then return end
    countdownEndsAt = nil
    roundEndsAt = GetGameTimer() + config.roundSeconds * 1000

    local ids = idsInState("arena")
    for _, playerId in ipairs(ids) do roster[playerId].state = "alive" end
    tellArena("Placing everyone on their mark...")

    -- Everyone on their mark at full health, then one go signal and one protection window.
    -- God mode from admission stays on until that window expires, so there is no gap.
    forEachAsync(ids, function(playerId)
        local entry = roster[playerId]
        if not entry or entry.state ~= "alive" then return end
        Open77.players.restoreHealth(playerId)
        local landed, reason = place(playerId, entry.spawn, entry.spawn.heading, ARENA)
        if not landed then
            log("could not place %d at round start: %s", playerId, tostring(reason))
        end
    end, function()
        if phase ~= "live" then return end
        local protectedUntil = GetGameTimer() + config.spawnProtectionSeconds * 1000
        for _, entry in pairs(roster) do
            if entry.state == "alive" then entry.protectedUntil = protectedUntil end
        end
        tellArena(("FIGHT! Last one standing wins. %d s of spawn protection, %d s round."):format(
            config.spawnProtectionSeconds, config.roundSeconds))
        checkWin() -- a disconnect during placement can already have decided it
    end)
end

-- ---------------------------------------------------------------- admission

admit = function(playerId)
    if roster[playerId] then return false, "already_in_arena" end
    if queue[playerId] then return false, "already_queued" end
    if phase == "live" or phase == "resolving" then
        queue[playerId] = true
        return false, "round_in_progress_queued"
    end
    if count() >= capacity() then return false, "arena_full" end
    if not Open77.ready.isReady(playerId) then return false, "player_not_ready" end
    local life = Open77.players.getLifeState(playerId)
    if not life or life.phase ~= "alive" then return false, "player_not_alive" end
    local pos = Open77.players.position(playerId)
    if not pos then return false, "position_unknown" end

    local spawn = takeSpawn()
    roster[playerId] = {
        state = "entering",
        returnTo = { x = pos.x, y = pos.y, z = pos.z },
        returnHeading = 0.0, -- position() carries no heading
        spawn = spawn,
        joinedAt = GetGameTimer(),
    }

    CreateThread(function()
        -- No combat before the round is live; dropped by the protection window after the go.
        Open77.players.setGodMode(playerId, true)
        local landed, reason = place(playerId, spawn, spawn.heading, ARENA)
        local entry = roster[playerId]
        if not entry or entry.state ~= "entering" then return end -- dropped meanwhile
        if not landed then
            log("entry teleport for %d refused: %s", playerId, tostring(reason))
            roster[playerId] = nil
            Open77.players.setGodMode(playerId, false)
            say(playerId, "Could not enter the arena: " .. tostring(reason))
            return
        end
        if phase == "live" or phase == "resolving" then
            -- The round started while this body was in flight: next round, not this one.
            queue[playerId] = true
            say(playerId, "The round started while you were on your way; you are queued for the next one.")
            returnPlayer(playerId)
            return
        end
        entry.state = "arena"
        giveLoadout(playerId)
        Open77.players.restoreHealth(playerId)
        say(playerId, ("You are in the arena (%s). /arena leave to go back."):format(landed.state))
        if phase == "idle" then transition("waiting", "first player landed") end
        checkCountdown()
    end)
    return true
end

local function leave(playerId)
    if queue[playerId] then
        queue[playerId] = nil
        return true, "left_queue"
    end
    local entry = roster[playerId]
    if not entry then return false, "not_in_arena" end
    if entry.state == "returning" then return false, "already_leaving" end
    if entry.state == "entering" then
        -- The entry teleport is still in flight; let it land, then send them home.
        CreateThread(function()
            while roster[playerId] and roster[playerId].state == "entering" do Wait(250) end
            queue[playerId] = nil
            if roster[playerId] then returnPlayer(playerId) end
        end)
        return true, "leaving"
    end
    -- Leave the counts right before anything asynchronous runs: a leaver forfeits.
    local wasAlive = entry.state == "alive"
    entry.state = "returning"
    entry.protectedUntil = nil
    CreateThread(function() returnPlayer(playerId) end)
    if wasAlive then
        tellArena(("%s left the round. %d remain."):format(nameOf(playerId), count("alive")))
        checkWin()
    end
    checkCountdown()
    return true, "leaving"
end

-- ---------------------------------------------------------------- host events

AddEventHandler("onPlayerLifeStateChanged", function(playerId, revision, lifePhase, reason)
    playerId = tonumber(playerId)
    local entry = playerId and roster[playerId]
    if not entry then return end
    if lifePhase == "dead" then
        if entry.state == "alive" then eliminate(playerId, reason or "dead") end
    elseif lifePhase == "alive" then
        if entry.state == "eliminated" and phase == "live" then
            -- Another resource brought them back mid-round. They are out: send them home now
            -- rather than leaving a living non-participant in the arena bucket.
            CreateThread(function() returnPlayer(playerId) end)
        end
    end
end)

AddEventHandler("onPlayerDisconnected", function(playerId, reason)
    playerId = tonumber(playerId)
    if not playerId then return end
    queue[playerId] = nil
    local entry = roster[playerId]
    if not entry then return end
    local wasAlive = entry.state == "alive"
    roster[playerId] = nil
    if wasAlive then
        tellArena(("%s disconnected. %d remain."):format(nameOf(playerId), count("alive")))
        checkWin()
    end
    afterReturn()
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    -- Handlers and timers are swept for us; the player state we set is not. Undo it
    -- synchronously: no fade and no await, the VM is going away.
    for playerId, entry in pairs(roster) do
        Open77.players.setGodMode(playerId, false)
        Open77.weapons.clear(playerId)
        local pending = Open77.players.teleport(playerId, entry.returnTo,
            { bucket = MAIN, dismount = true, fade = false })
        if not pending and Open77.routingBuckets.getPlayer(playerId) == ARENA then
            Open77.routingBuckets.setPlayer(playerId, MAIN)
        end
    end
    roster, queue = {}, {}
end)

-- ---------------------------------------------------------------- tick

CreateThread(function()
    while true do
        Wait(config.tickMs)
        local now = GetGameTimer()
        if phase == "waiting" then
            if countdownEndsAt and now >= countdownEndsAt then
                -- Re-check the count at the deadline rather than trusting every path to have.
                if count("arena") >= config.minPlayers then goLive() else checkCountdown() end
            end
        elseif phase == "live" then
            -- Snapshot the ids first: eliminate() may resolve the round mid-loop.
            local alive = idsInState("alive")
            for _, playerId in ipairs(alive) do
                local entry = roster[playerId]
                if entry and entry.protectedUntil and now >= entry.protectedUntil then
                    entry.protectedUntil = nil
                    Open77.players.setGodMode(playerId, false)
                end
            end
            -- Re-derive life from the authority rather than trusting the event stream alone.
            for _, playerId in ipairs(alive) do
                if phase == "live" and roster[playerId] and roster[playerId].state == "alive"
                    and Open77.players.isDead(playerId) then
                    eliminate(playerId, "dead")
                end
            end
            if phase == "live" and roundEndsAt and now >= roundEndsAt then
                resolve(nil, ("time limit, %d still standing"):format(count("alive")))
            end
        end
    end
end)

-- ---------------------------------------------------------------- commands

local function describePlayer(playerId)
    local pos = Open77.players.position(playerId)
    local life = Open77.players.getLifeState(playerId)
    local entry = roster[playerId]
    return ("%s: pos=%s bucket=%s life=%s arena=%s queued=%s ready=%s"):format(
        nameOf(playerId),
        pos and ("%.1f %.1f %.1f"):format(pos.x, pos.y, pos.z) or "unknown",
        tostring(Open77.routingBuckets.getPlayer(playerId)),
        life and life.phase or "unknown",
        entry and entry.state or "no",
        tostring(queue[playerId] == true),
        tostring(Open77.ready.isReady(playerId)))
end

local function describeRound()
    local now = GetGameTimer()
    local extra = ""
    if phase == "waiting" and countdownEndsAt then
        extra = (" starts in %ds"):format(math.max(0, math.ceil((countdownEndsAt - now) / 1000)))
    elseif phase == "live" and roundEndsAt then
        extra = (" %ds left"):format(math.max(0, math.ceil((roundEndsAt - now) / 1000)))
    end
    local queued = 0
    for _ in pairs(queue) do queued = queued + 1 end
    return ("phase=%s%s in=%d/%d alive=%d queued=%d for %ds"):format(
        phase, extra, count(), capacity(), count("alive"), queued, math.floor((now - phaseSince) / 1000))
end

-- /arena            join (or queue while a round runs)
-- /arena leave      leave the queue, the arena or the round (a leaver forfeits)
-- /arena status     the authoritative phase and population
-- /arena where      what the server sees about you (console: arena where <id>)
RegisterCommand("arena", function(source, args)
    source = tonumber(source) or 0
    args = args or {}
    local sub = (args[1] or ""):lower()

    if sub == "status" then
        local text = describeRound()
        if source == 0 then print("eval_arena: " .. text) else say(source, text) end
        return
    end

    if sub == "where" then
        local target = source
        if source == 0 then target = tonumber(args[2]) end
        if not target then return print("eval_arena: arena where <playerId> from the console") end
        local text = describePlayer(target) .. " | " .. describeRound()
        if source == 0 then print("eval_arena: " .. text) else say(source, text) end
        return
    end

    if source == 0 then
        return print("eval_arena: /arena is a player command; the console has arena status and arena where <id>")
    end

    if sub == "leave" then
        local ok, reason = leave(source)
        say(source, ok and ("Leaving the arena (%s)."):format(reason) or ("Nothing to leave: %s"):format(reason))
        return
    end

    local ok, reason = admit(source)
    if ok then
        say(source, "Entering the arena...")
    elseif reason == "round_in_progress_queued" then
        say(source, "A round is in progress. You are queued for the next one; /arena leave to withdraw.")
    else
        say(source, "Cannot join the arena: " .. tostring(reason))
    end
end, false)

-- Restricted (ACL command.arena.mark): capture a spawn mark where the caller stands.
-- Coordinates are read from the server snapshot, never from the caller's arguments.
-- position() carries no heading: pass the yaw, or the mark records 0.
RegisterCommand("arena.mark", function(source, args)
    source = tonumber(source) or 0
    args = args or {}
    if source == 0 then return print("eval_arena: arena.mark needs a player body to stand somewhere") end
    local pos = Open77.players.position(source)
    if not pos then return say(source, "No position snapshot for you yet.") end
    local mark = { x = pos.x, y = pos.y, z = pos.z, heading = tonumber(args[1]) or 0.0 }
    spawns[#spawns + 1] = mark
    local line = ("{ x = %.2f, y = %.2f, z = %.2f, heading = %.1f },"):format(mark.x, mark.y, mark.z, mark.heading)
    log("spawn mark %d captured by %s: %s", #spawns, nameOf(source), line)
    say(source, ("Mark %d: %s (paste into Config.spawns)"):format(#spawns, line))
end, true)

-- Restricted (ACL command.arena.end): end the live round now with no winner.
RegisterCommand("arena.end", function(source)
    source = tonumber(source) or 0
    if phase ~= "live" then
        return print("eval_arena: no live round to end (phase " .. phase .. ")")
    end
    resolve(nil, "ended by " .. (source == 0 and "the console" or nameOf(source)))
end, true)

-- ---------------------------------------------------------------- setup

buildSpawns()
Open77.routingBuckets.setPopulationEnabled(ARENA, false)
Open77.routingBuckets.setLockdownMode(ARENA, "relaxed")

-- Reload-safe adoption: a previous generation that never ran its stop handler can have
-- left bodies scoped to the arena. Their return positions are gone; the bucket is not.
local leftovers = Open77.players.inBucket(ARENA)
if leftovers then
    for _, playerId in ipairs(leftovers) do
        log("adopting leftover %d from the arena bucket", playerId)
        Open77.players.setGodMode(playerId, false)
        Open77.weapons.clear(playerId)
        Open77.routingBuckets.setPlayer(playerId, MAIN)
        say(playerId, "The arena restarted; you are back in the city.")
    end
end

log("ready: bucket %d, %d spawn marks, %d-%d players", ARENA, #spawns, config.minPlayers, capacity())
