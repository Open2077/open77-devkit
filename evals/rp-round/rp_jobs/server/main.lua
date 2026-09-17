-- rp_jobs -- server-authoritative jobs for an RP server.
--
-- A player holds at most one job, persisted in this resource's KVP store under
-- the player's durable identifier and restored on onPlayerReady. The only
-- scripted mission in this version is the courier run (job "livreur"):
-- a cheap car is spawned next to the player, three delivery points are drawn
-- at increasing distance, arrival is detected by polling the server-side
-- position once per second, and each delivery is paid through rp_economy.
--
-- Exports (synchronous, never yield): getJob(playerId), hasJob(playerId, jobName)
-- Host-wide event raised on every change: rp_jobs:changed (playerId, jobName | nil)

local RESOURCE = GetCurrentResourceName()

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------

local JOBS = {
    { name = "livreur", label = "Livreur", description = "Livre des colis aux quatre coins de Night City (/mission)." },
    { name = "taxi",    label = "Taxi",    description = "Transporte les habitants d'un point a l'autre de la ville." },
    { name = "mecano",  label = "Mecano",  description = "Repare et entretient les vehicules des habitants." },
    { name = "medecin", label = "Medecin", description = "Soigne et reanime les blesses de Night City." },
    { name = "police",  label = "Police",  description = "Fait respecter la loi au sein du NCPD." },
}

local JOB_BY_NAME = {}
for _, job in ipairs(JOBS) do
    JOB_BY_NAME[job.name] = job
end

local MISSION = {
    job = "livreur",
    -- Cheapest player car in the catalogue; *_player records are the ones the docs say to prefer.
    vehicleRecord = "Vehicle.v_standard2_makigai_maimai_player",
    vehicleTtlMs = 30 * 60 * 1000, -- safety net: a crash should not leave a car forever
    pointCount = 3,
    -- Distance bands in metres, one per delivery point; each band starts after the previous one ends.
    bands = { { 150, 220 }, { 230, 310 }, { 320, 400 } },
    arriveRadius = 12.0,
    pollMs = 1000,
    positionMaxAgeMs = 5000,
    payout = 150,
    payoutReason = "livraison",
}

local SUGGESTIONS = {
    { command = "/jobs", help = "Liste des metiers et celui que vous occupez" },
    { command = "/job", help = "Prendre un metier, ou /job quit pour demissionner",
      parameters = { { name = "metier", help = "livreur, taxi, mecano, medecin, police ou quit" } } },
    { command = "/mission", help = "Livreur : demarrer une tournee de livraison" },
    { command = "/stopmission", help = "Annuler la tournee de livraison en cours" },
}

---------------------------------------------------------------------------
-- State (keyed by numeric player id, valid for one connection only)
---------------------------------------------------------------------------

local jobs = {}        -- [playerId] = jobName
local identifiers = {} -- [playerId] = durable identifier, cached at ready time
local missions = {}    -- [playerId] = mission table (see startMission)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function log(fmt, ...)
    print(("[rp_jobs] " .. fmt):format(...))
end

-- Chat to one player. playerId must already be a number.
local function tell(playerId, text)
    local ok, reason = Open77.chat.send(playerId, text)
    if not ok then
        log("chat to player %s refused: %s", tostring(playerId), tostring(reason))
    end
    return ok
end

local function toPlayerId(value)
    local id = tonumber(value)
    if id == nil or id < 1 or id % 1 ~= 0 then
        return nil
    end
    return id
end

local function identifierOf(playerId)
    local cached = identifiers[playerId]
    if cached then
        return cached
    end
    local identifier = Open77.players.identifier(playerId)
    if identifier ~= nil and identifier ~= "" then
        identifiers[playerId] = identifier
        return identifier
    end
    return nil
end

local function kvpKey(identifier)
    return "job:" .. identifier
end

local function distance2D(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- Fresh server-side position (and heading) of a player, or nil.
local function freshPosition(playerId)
    local read = Open77.players.get(playerId)
    if not read or not read.position then
        return nil
    end
    if (read.ageMs or 0) > MISSION.positionMaxAgeMs then
        return nil
    end
    return read.position, read.heading
end

---------------------------------------------------------------------------
-- Jobs
---------------------------------------------------------------------------

local function announceChange(playerId, jobName)
    local ok, reason = TriggerEvent("rp_jobs:changed", playerId, jobName)
    if not ok then
        log("rp_jobs:changed for player %d not published: %s", playerId, tostring(reason))
    end
end

-- Persist the job (or its absence) for a player, in the KVP store.
local function persistJob(playerId, jobName)
    local identifier = identifierOf(playerId)
    if not identifier then
        log("player %d has no durable identifier, job not persisted", playerId)
        return false
    end
    local ok, reason
    if jobName then
        ok, reason = Open77.kvp.set(kvpKey(identifier), jobName)
    else
        ok, reason = Open77.kvp.delete(kvpKey(identifier))
        if not ok and reason == nil then
            ok = true -- absent key: nothing to delete, that is fine
        end
    end
    if not ok then
        log("kvp write for player %d failed: %s", playerId, tostring(reason))
    end
    return ok
end

local function setJob(playerId, jobName)
    jobs[playerId] = jobName
    persistJob(playerId, jobName)
    log("player %d job=%s", playerId, jobName or "none")
    announceChange(playerId, jobName)
end

-- Restore a job from the KVP store; returns the job name or nil.
local function restoreJob(playerId)
    local identifier = identifierOf(playerId)
    if not identifier then
        return nil
    end
    local stored = Open77.kvp.get(kvpKey(identifier))
    if type(stored) == "string" and JOB_BY_NAME[stored] then
        jobs[playerId] = stored
        log("player %d job=%s (restored)", playerId, stored)
        return stored
    end
    if stored ~= nil then
        -- An unknown job name in the store: drop it rather than carry garbage.
        Open77.kvp.delete(kvpKey(identifier))
    end
    return nil
end

---------------------------------------------------------------------------
-- Courier mission
---------------------------------------------------------------------------

local cancelMission -- forward declaration

local function sendWaypoint(playerId, point)
    local ok, reason = Open77.net.emitClient("rp_jobs:waypoint", playerId, { x = point.x, y = point.y, z = point.z })
    if not ok then
        log("waypoint for player %d not sent: %s", playerId, tostring(reason))
    end
end

local function clearWaypoint(playerId)
    Open77.net.emitClient("rp_jobs:waypointClear", playerId)
end

local function describePoint(playerId, mission)
    local point = mission.points[mission.index]
    local here = freshPosition(playerId)
    local distanceText = ""
    if here then
        distanceText = (" (a %d m)"):format(math.floor(distance2D(here.x, here.y, point.x, point.y) + 0.5))
    end
    tell(playerId, ("Livraison %d/%d : rendez-vous en X=%.1f Y=%.1f%s."):format(
        mission.index, #mission.points, point.x, point.y, distanceText))
    sendWaypoint(playerId, point)
end

-- Three points at increasing distance on the player's own ground plane (z reused).
local function drawPoints(origin)
    local points = {}
    for i = 1, MISSION.pointCount do
        local band = MISSION.bands[i] or MISSION.bands[#MISSION.bands]
        local distance = band[1] + math.random() * (band[2] - band[1])
        local angle = math.random() * 2 * math.pi
        points[i] = {
            x = math.floor((origin.x + math.cos(angle) * distance) * 10 + 0.5) / 10,
            y = math.floor((origin.y + math.sin(angle) * distance) * 10 + 0.5) / 10,
            z = origin.z,
        }
    end
    return points
end

-- Pay through rp_economy; the synchronous export raises when missing, hence pcall.
local function payDelivery(playerId)
    local ok, balance, reason = pcall(function()
        return exports.rp_economy:add(playerId, MISSION.payout, MISSION.payoutReason)
    end)
    if not ok then
        log("mission player %d payout failed: %s", playerId, tostring(balance))
        tell(playerId, "Le systeme d'argent est hors ligne : cette livraison ne sera pas payee.")
        return
    end
    if balance == nil then
        log("mission player %d payout refused: %s", playerId, tostring(reason))
        tell(playerId, ("Paiement refuse (%s)."):format(tostring(reason or "inconnu")))
        return
    end
    tell(playerId, ("Livraison payee : +%d $. Solde : %s $."):format(MISSION.payout, tostring(balance)))
end

local function removeMissionVehicle(mission)
    if mission.vehicleId == nil then
        return
    end
    local removed = Open77.vehicles.remove(mission.vehicleId)
    if not removed then
        log("mission player %d vehicle %s already gone", mission.playerId, tostring(mission.vehicleId))
    end
    mission.vehicleId = nil
end

local function finishMission(playerId, mission)
    missions[playerId] = nil
    removeMissionVehicle(mission)
    clearWaypoint(playerId)
    log("mission player %d finished", playerId)
    tell(playerId, "Tournee terminee, beau travail ! Le vehicule de service est rendu.")
end

cancelMission = function(playerId, reason, silent)
    local mission = missions[playerId]
    if not mission then
        return false
    end
    missions[playerId] = nil
    removeMissionVehicle(mission)
    if not silent then
        clearWaypoint(playerId)
        tell(playerId, "Tournee annulee.")
    end
    log("mission player %d cancelled reason=%s", playerId, reason)
    return true
end

-- Runs inside the /mission command task; ends when the mission is over or replaced.
local function pollMission(playerId, mission)
    while missions[playerId] == mission do
        Wait(MISSION.pollMs)
        if missions[playerId] ~= mission then
            return
        end
        local here = freshPosition(playerId)
        if here then
            local point = mission.points[mission.index]
            if distance2D(here.x, here.y, point.x, point.y) <= MISSION.arriveRadius then
                log("mission player %d point %d/%d reached", playerId, mission.index, #mission.points)
                tell(playerId, ("Colis %d/%d livre !"):format(mission.index, #mission.points))
                payDelivery(playerId)
                if mission.index >= #mission.points then
                    finishMission(playerId, mission)
                    return
                end
                mission.index = mission.index + 1
                describePoint(playerId, mission)
            end
        end
    end
end

local function startMission(playerId)
    local origin, heading = freshPosition(playerId)
    if not origin then
        tell(playerId, "Position inconnue pour le moment, reessayez dans un instant.")
        return
    end

    local mission = {
        playerId = playerId,
        points = drawPoints(origin),
        index = 1,
        vehicleId = nil,
    }
    missions[playerId] = mission

    local vehicleId, reason = Open77.vehicles.create({
        record = MISSION.vehicleRecord,
        position = { x = origin.x + 4.0, y = origin.y, z = origin.z },
        yaw = heading or 0.0,
        ttlMs = MISSION.vehicleTtlMs,
    })
    if vehicleId then
        mission.vehicleId = vehicleId
        tell(playerId, "Tournee lancee : un vehicule de service vous attend juste a cote.")
    else
        tell(playerId, ("Pas de vehicule disponible (%s) : la tournee se fera a pied."):format(tostring(reason)))
    end
    log("mission player %d started vehicle=%s", playerId, tostring(vehicleId or "none"))

    describePoint(playerId, mission)
    pollMission(playerId, mission)
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

RegisterCommand("jobs", function(source)
    if source == 0 then
        print("[rp_jobs] /jobs : a lancer depuis le jeu, pas depuis la console")
        return
    end
    local current = jobs[source]
    tell(source, "Metiers disponibles :")
    for _, job in ipairs(JOBS) do
        Wait(0) -- two sends in one tick arrive reversed; one line per tick keeps the order
        local marker = (job.name == current) and " [actuel]" or ""
        tell(source, ("- %s%s : %s"):format(job.name, marker, job.description))
    end
    Wait(0)
    if current then
        tell(source, ("Vous etes %s. /job quit pour demissionner."):format(JOB_BY_NAME[current].label))
    else
        tell(source, "Vous n'avez pas de metier. /job <nom> pour en prendre un.")
    end
end, false)

RegisterCommand("job", function(source, args)
    if source == 0 then
        print("[rp_jobs] /job : a lancer depuis le jeu, pas depuis la console")
        return
    end
    local wanted = args[1] and string.lower(args[1]) or nil
    if not wanted then
        tell(source, "Usage : /job <livreur|taxi|mecano|medecin|police> ou /job quit")
        return
    end

    local current = jobs[source]
    if wanted == "quit" then
        if not current then
            tell(source, "Vous n'avez pas de metier a quitter.")
            return
        end
        if missions[source] then
            cancelMission(source, "job_quit")
        end
        setJob(source, nil)
        tell(source, ("Vous avez quitte votre poste de %s."):format(JOB_BY_NAME[current].label))
        return
    end

    local job = JOB_BY_NAME[wanted]
    if not job then
        tell(source, ("Metier inconnu : %s. /jobs pour la liste."):format(wanted))
        return
    end
    if current == job.name then
        tell(source, ("Vous etes deja %s."):format(job.label))
        return
    end
    if current and missions[source] then
        cancelMission(source, "job_changed")
    end
    setJob(source, job.name)
    tell(source, ("Vous etes maintenant %s. %s"):format(job.label, job.description))
end, false)

RegisterCommand("mission", function(source)
    if source == 0 then
        print("[rp_jobs] /mission : a lancer depuis le jeu, pas depuis la console")
        return
    end
    if jobs[source] ~= MISSION.job then
        tell(source, "Seuls les livreurs ont une mission pour l'instant. /job livreur pour le devenir.")
        return
    end
    if missions[source] then
        tell(source, "Une tournee est deja en cours. /stopmission pour l'annuler.")
        return
    end
    startMission(source)
end, false)

RegisterCommand("stopmission", function(source)
    if source == 0 then
        print("[rp_jobs] /stopmission : a lancer depuis le jeu, pas depuis la console")
        return
    end
    if not cancelMission(source, "player_request") then
        tell(source, "Aucune tournee en cours.")
    end
end, false)

---------------------------------------------------------------------------
-- Exports (synchronous: they never yield)
---------------------------------------------------------------------------

exports("getJob", function(playerId)
    local id = toPlayerId(playerId)
    if not id then
        return nil
    end
    return jobs[id]
end)

exports("hasJob", function(playerId, jobName)
    local id = toPlayerId(playerId)
    if not id or type(jobName) ~= "string" then
        return false
    end
    return jobs[id] == string.lower(jobName)
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

AddEventHandler("onResourceStart", function(name)
    if name ~= RESOURCE then
        return
    end
    Open77.chat.addSuggestions(-1, SUGGESTIONS)
    -- Players who were already in the world when the resource (re)started.
    for _, playerId in ipairs(Open77.players.all()) do
        local id = toPlayerId(playerId)
        if id then
            local read = Open77.players.get(id)
            if read and read.ready then
                restoreJob(id)
            end
        end
    end
    log("started")
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= RESOURCE then
        return
    end
    for playerId in pairs(missions) do
        cancelMission(playerId, "resource_stop", true)
    end
end)

RegisterNetEvent("chat:ready", function()
    local id = toPlayerId(source)
    if id then
        Open77.chat.addSuggestions(id, SUGGESTIONS)
    end
end)

AddEventHandler("onPlayerReady", function(playerId)
    local id = toPlayerId(playerId)
    if not id then
        return
    end
    local restored = restoreJob(id)
    if restored then
        tell(id, ("Bon retour : vous reprenez votre poste de %s."):format(JOB_BY_NAME[restored].label))
    end
end)

AddEventHandler("onPlayerDisconnected", function(playerId)
    local id = toPlayerId(playerId)
    if not id then
        return
    end
    if missions[id] then
        cancelMission(id, "disconnected", true)
    end
    jobs[id] = nil
    identifiers[id] = nil
end)
