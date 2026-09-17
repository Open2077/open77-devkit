-- rp_medic - server-only medic service for an RP server.
--
-- /soin <playerId>   medic only, target alive within 5 m, full health, 100 eddies
-- /reanimer <playerId> medic only, target dead within 5 m, revived where it fell, 300 eddies
-- /911 <message>     anyone: message + rounded position sent to every medic and cop
-- /medic             connected medics with their distance to the caller
--
-- Authority: everything is decided here. Money goes through rp_economy, jobs through
-- rp_jobs; when rp_jobs publishes no export the ACL right of a restricted command
-- (command.soin / command.reanimer) decides instead. Persistence (per-medic counters)
-- goes through Open77.kvp keyed by the durable identifier, never the session id.

-- The platform already owns /heal (open77_admin) and /revive (freeroam), and a
-- command name registered twice across resources is served by the first one:
-- the medic verbs are /soin and /reanimer.

local RESOURCE = GetCurrentResourceName()

local HEAL_FEE = 100
local REVIVE_FEE = 300
local RANGE_M = 5.0
local COOLDOWN_S = 30
local MEDIC_JOB = "medecin"
local POLICE_JOB = "police"
local REVIVE_HEALTH = 1.0   -- fraction of the maximum after a paid revive
local REVIVE_GRACE_MS = 5000

-- [medicId] = Open77.time.monotonic() of the medic's last paid act (heal or revive).
local cooldowns = {}

local COLOR_MEDIC = { 80, 220, 160 }
local COLOR_ALERT = { 255, 90, 90 }

local function log(fmt, ...)
    print(("[rp_medic] " .. fmt):format(...))
end

-- Chat to one player. `playerId` is always a number here (command / net-event source).
local function say(playerId, text)
    local ok, reason = Open77.chat.send(playerId, { author = "MEDIC", text = text, color = COLOR_MEDIC })
    if not ok then
        log("chat.send to %s failed: %s", tostring(playerId), tostring(reason))
    end
end

local function round(value)
    return math.floor(value + 0.5)
end

-- ---------------------------------------------------------------------------
-- rp_jobs (synchronous exports raise when the export or the resource is missing)
-- ---------------------------------------------------------------------------

-- Returns `job, true` when rp_jobs answered, `nil, false` when its export is unavailable.
local function jobOf(playerId)
    local ok, job = pcall(function()
        return exports.rp_jobs:getJob(playerId)
    end)
    if not ok then
        log("rp_jobs getJob unavailable: %s", tostring(job))
        return nil, false
    end
    return job, true
end

-- Returns true / false when rp_jobs answered, nil when its export is unavailable.
local function hasJob(playerId, jobName)
    local ok, result = pcall(function()
        return exports.rp_jobs:hasJob(playerId, jobName)
    end)
    if not ok then
        log("rp_jobs hasJob unavailable: %s", tostring(result))
        return nil
    end
    return result == true
end

-- ACL fallback: the same right a restricted command of that name would require.
local function aclAllows(playerId, right)
    local allowed, reason = Open77.acl.isAllowed(playerId, right)
    if allowed ~= true and reason then
        log("acl.isAllowed(%s, %s) refused: %s", tostring(playerId), right, tostring(reason))
    end
    return allowed == true
end

-- May this player use the medic command `commandName`? Returns allowed, mode.
local function isMedic(playerId, commandName)
    local viaJobs = hasJob(playerId, MEDIC_JOB)
    if viaJobs ~= nil then
        return viaJobs, "jobs"
    end
    return aclAllows(playerId, "command." .. commandName), "acl"
end

-- Roles of a connected player for the roster commands. Without rp_jobs a medic is
-- whoever holds command.heal; the police cannot be identified and is left out.
local function rolesOf(playerId)
    local job, available = jobOf(playerId)
    if available then
        return { medic = job == MEDIC_JOB, police = job == POLICE_JOB }, "jobs"
    end
    return { medic = aclAllows(playerId, "command.soin"), police = false }, "acl"
end

-- ---------------------------------------------------------------------------
-- rp_economy
-- ---------------------------------------------------------------------------

-- Charges `amount` to the patient and credits the medic.
-- Returns "paid", "free" (patient cannot pay) or "unavailable" (no economy service).
local function charge(patient, medic, amount, reason)
    local ok, newBalance, why = pcall(function()
        return exports.rp_economy:remove(patient, amount, reason)
    end)
    if not ok then
        log("rp_economy remove unavailable: %s", tostring(newBalance))
        return "unavailable"
    end
    if newBalance == nil then
        log("player %d cannot pay %d (%s): free", patient, amount, tostring(why))
        return "free"
    end

    local okAdd, credited, addWhy = pcall(function()
        return exports.rp_economy:add(medic, amount, reason)
    end)
    if not okAdd or credited == nil then
        -- The patient paid but the medic could not be credited: give the money back.
        log("crediting medic %d failed (%s), refunding player %d", medic,
            tostring(okAdd and addWhy or credited), patient)
        pcall(function()
            return exports.rp_economy:add(patient, amount, reason .. "_refund")
        end)
        return "free"
    end
    return "paid"
end

-- ---------------------------------------------------------------------------
-- Persistence: per-medic counters keyed by the durable identifier
-- ---------------------------------------------------------------------------

local function recordAct(medic, kind, fee)
    local identifier = Open77.players.identifier(medic)
    if not identifier then
        return
    end
    local _, reason = Open77.kvp.increment(kind .. ":" .. identifier, 1)
    if reason then
        log("kvp increment %s failed: %s", kind, tostring(reason))
    end
    if fee > 0 then
        Open77.kvp.increment("earned:" .. identifier, fee)
    end
end

local function statsLine(medic)
    local identifier = Open77.players.identifier(medic)
    if not identifier then
        return nil
    end
    local heals = Open77.kvp.get("heal:" .. identifier, 0) or 0
    local revives = Open77.kvp.get("revive:" .. identifier, 0) or 0
    local earned = Open77.kvp.get("earned:" .. identifier, 0) or 0
    return ("Vos interventions : %d soin(s), %d réanimation(s), %d €$ gagnés."):format(heals, revives, earned)
end

-- ---------------------------------------------------------------------------
-- Shared checks
-- ---------------------------------------------------------------------------

local function cooldownLeft(medic)
    local last = cooldowns[medic]
    if not last then
        return 0
    end
    local left = COOLDOWN_S - (Open77.time.monotonic() - last)
    if left > 0 then
        return left
    end
    return 0
end

-- Common gate of /heal and /revive: a player, a medic, no cooldown, a valid patient
-- within range. Returns the patient id, or nil after telling the caller why.
local function medicGate(source, args, commandName, usage)
    if source == 0 then
        print(("[rp_medic] /%s must be used by a player in game, not from the console"):format(commandName))
        return nil
    end

    local allowed, mode = isMedic(source, commandName)
    if not allowed then
        if mode == "acl" then
            say(source, "Réservé aux médecins (service rp_jobs indisponible : droit command." .. commandName .. " requis).")
        else
            say(source, "Réservé aux médecins.")
        end
        return nil
    end

    local left = cooldownLeft(source)
    if left > 0 then
        say(source, ("Patientez encore %d s avant une nouvelle intervention."):format(math.ceil(left)))
        return nil
    end

    local target = tonumber(args[1])
    if not target or target < 1 or target % 1 ~= 0 then
        say(source, usage)
        return nil
    end
    target = math.tointeger(target)
    if target == source then
        say(source, "Vous ne pouvez pas intervenir sur vous-même.")
        return nil
    end

    local read, reason = Open77.players.get(target)
    if not read then
        say(source, ("Joueur %d introuvable (%s)."):format(target, tostring(reason)))
        return nil
    end
    if not read.ready then
        say(source, "Ce joueur n'est pas encore en jeu.")
        return nil
    end

    local metres, dreason = Open77.players.distance(source, target)
    if not metres then
        say(source, "Position du patient inconnue (" .. tostring(dreason) .. ").")
        return nil
    end
    if metres > RANGE_M then
        say(source, ("Trop loin : %.1f m (5 m maximum)."):format(metres))
        return nil
    end
    return target
end

local function feeSentence(outcome, fee)
    if outcome == "paid" then
        return ("%d €$ encaissés."):format(fee)
    elseif outcome == "free" then
        return "Le patient ne peut pas payer : intervention gratuite."
    end
    return "Service économique indisponible : intervention gratuite."
end

-- ---------------------------------------------------------------------------
-- /soin <playerId>
-- ---------------------------------------------------------------------------

RegisterCommand("soin", function(source, args)
    local patient = medicGate(source, args, "soin", "Usage : /soin <idJoueur>")
    if not patient then
        return
    end

    local dead = Open77.players.isDead(patient)
    if dead == nil then
        return say(source, "État du patient inconnu.")
    end
    if dead then
        return say(source, "Ce patient est mort : utilisez /reanimer.")
    end

    local stats = Open77.stats.get(patient)
    if stats and stats.health and stats.health.value >= stats.health.maximum then
        return say(source, "Ce patient est déjà en pleine santé.")
    end

    local ok, reason = Open77.stats.restoreHealth(patient)
    if not ok then
        return say(source, "Soin impossible : " .. tostring(reason) .. ".")
    end

    cooldowns[source] = Open77.time.monotonic()
    local outcome = charge(patient, source, HEAL_FEE, "medic_heal")
    local fee = outcome == "paid" and HEAL_FEE or 0
    recordAct(source, "heal", fee)

    local medicName = Open77.players.name(source) or ("joueur " .. source)
    local patientName = Open77.players.name(patient) or ("joueur " .. patient)
    say(source, ("Patient %s soigné. %s"):format(patientName, feeSentence(outcome, HEAL_FEE)))
    if outcome == "paid" then
        say(patient, ("Le médecin %s vous a soigné : %d €$ prélevés."):format(medicName, HEAL_FEE))
    else
        say(patient, ("Le médecin %s vous a soigné gratuitement."):format(medicName))
    end
    log("player %d healed player %d fee=%d", source, patient, fee)
end, false)

-- ---------------------------------------------------------------------------
-- /reanimer <playerId>
-- ---------------------------------------------------------------------------

RegisterCommand("reanimer", function(source, args)
    local patient = medicGate(source, args, "reanimer", "Usage : /reanimer <idJoueur>")
    if not patient then
        return
    end

    local dead = Open77.players.isDead(patient)
    if dead == nil then
        return say(source, "État du patient inconnu.")
    end
    if not dead then
        return say(source, "Ce patient est vivant : utilisez /soin.")
    end

    -- Documented safe path for a dead player: the server's life authority revives
    -- the body where it fell; the call refuses (false, reason) during a transition.
    local ok, reason = Open77.players.revive(patient, { health = REVIVE_HEALTH, graceMs = REVIVE_GRACE_MS })
    if not ok then
        return say(source, "Réanimation impossible : " .. tostring(reason) .. ".")
    end

    cooldowns[source] = Open77.time.monotonic()
    local outcome = charge(patient, source, REVIVE_FEE, "medic_revive")
    local fee = outcome == "paid" and REVIVE_FEE or 0
    recordAct(source, "revive", fee)

    local medicName = Open77.players.name(source) or ("joueur " .. source)
    local patientName = Open77.players.name(patient) or ("joueur " .. patient)
    say(source, ("Patient %s réanimé. %s"):format(patientName, feeSentence(outcome, REVIVE_FEE)))
    if outcome == "paid" then
        say(patient, ("Le médecin %s vous a réanimé : %d €$ prélevés."):format(medicName, REVIVE_FEE))
    else
        say(patient, ("Le médecin %s vous a réanimé gratuitement."):format(medicName))
    end
    log("player %d revived player %d fee=%d", source, patient, fee)
end, false)

-- ---------------------------------------------------------------------------
-- /911 <message>
-- ---------------------------------------------------------------------------

RegisterCommand("911", function(source, args)
    if source == 0 then
        return print("[rp_medic] /911 must be used by a player in game, not from the console")
    end

    local message = table.concat(args, " ", 1, args.n or #args)
    message = message:match("^%s*(.-)%s*$")
    if message == "" then
        return say(source, "Usage : /911 <message>")
    end

    local pos = Open77.players.position(source)
    local where = "position inconnue"
    if pos then
        where = ("%d, %d, %d"):format(round(pos.x), round(pos.y), round(pos.z))
    end
    local callerName = Open77.players.name(source) or ("joueur " .. source)
    local alert = {
        author = "911",
        text = ("%s (id %d) en %s : %s"):format(callerName, source, where, message),
        color = COLOR_ALERT,
    }

    local notified = 0
    local mode = "jobs"
    for _, id in ipairs(Open77.players.all()) do
        if id ~= source then
            local roles, m = rolesOf(id)
            mode = m
            if roles.medic or roles.police then
                local ok, reason = Open77.chat.send(id, alert)
                if ok then
                    notified = notified + 1
                else
                    log("911 alert to player %d failed: %s", id, tostring(reason))
                end
            end
        end
    end

    if mode == "acl" then
        say(source, ("Appel transmis à %d intervenant(s) (service rp_jobs indisponible : police non joignable)."):format(notified))
    else
        say(source, ("Appel transmis à %d intervenant(s) (médecins et police)."):format(notified))
    end
    log("player %d called 911 at %s notified=%d", source, where, notified)
end, false)

-- ---------------------------------------------------------------------------
-- /medic
-- ---------------------------------------------------------------------------

RegisterCommand("medic", function(source)
    if source == 0 then
        return print("[rp_medic] /medic must be used by a player in game, not from the console")
    end

    local medics = {}
    local callerIsMedic = false
    for _, id in ipairs(Open77.players.all()) do
        local roles = rolesOf(id)
        if roles.medic then
            if id == source then
                callerIsMedic = true
            else
                local metres = Open77.players.distance(source, id)
                medics[#medics + 1] = {
                    id = id,
                    name = Open77.players.name(id) or ("joueur " .. id),
                    metres = metres,
                }
            end
        end
    end

    table.sort(medics, function(a, b)
        if a.metres and b.metres then
            return a.metres < b.metres
        end
        return a.metres ~= nil and b.metres == nil
    end)

    if #medics == 0 then
        if callerIsMedic then
            say(source, "Aucun autre médecin connecté.")
        else
            say(source, "Aucun médecin connecté.")
        end
    else
        say(source, ("%d médecin(s) en service :"):format(#medics))
        for _, medic in ipairs(medics) do
            Wait(0)   -- two sends in the same tick arrive in reverse order
            local dist = medic.metres and ("%.0f m"):format(medic.metres) or "distance inconnue"
            say(source, ("- %s (id %d) : %s"):format(medic.name, medic.id, dist))
        end
    end

    if callerIsMedic then
        local line = statsLine(source)
        if line then
            Wait(0)
            say(source, line)
        end
    end
end, false)

-- ---------------------------------------------------------------------------
-- Lifecycle and chat suggestions
-- ---------------------------------------------------------------------------

local SUGGESTIONS = {
    {
        command = "/soin",
        help = "Soigner un patient vivant à moins de 5 m (médecin, 100 €$)",
        parameters = { { name = "idJoueur", help = "Identifiant du patient (/id)" } },
    },
    {
        command = "/reanimer",
        help = "Réanimer un patient mort à moins de 5 m (médecin, 300 €$)",
        parameters = { { name = "idJoueur", help = "Identifiant du patient (/id)" } },
    },
    {
        command = "/911",
        help = "Alerter les médecins et la police avec votre position",
        parameters = { { name = "message", help = "Ce qui se passe" } },
    },
    {
        command = "/medic",
        help = "Médecins connectés et leur distance",
    },
}

local function publishSuggestions(target)
    local ok, reason = Open77.chat.addSuggestions(target, SUGGESTIONS)
    if not ok then
        log("addSuggestions(%s) failed: %s", tostring(target), tostring(reason))
    end
end

AddEventHandler("onResourceStart", function(name)
    if name ~= RESOURCE then
        return
    end
    publishSuggestions(-1)
    log("started: fees heal=%d revive=%d, range=%.0f m, cooldown=%d s", HEAL_FEE, REVIVE_FEE, RANGE_M, COOLDOWN_S)
end)

RegisterNetEvent("chat:ready", function()
    if type(source) ~= "number" or source < 1 then
        return
    end
    publishSuggestions(source)
end)

-- Host lifecycle arguments are strings: convert before touching the cooldown table.
AddEventHandler("onPlayerDisconnected", function(playerId)
    local id = tonumber(playerId)
    if id then
        cooldowns[id] = nil
    end
end)
