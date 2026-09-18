-- rp_trauma - shared configuration (loaded on the server and on every client).
-- Everything a server owner may want to move or retune lives here.

Config = {}

-- The job (rp_jobs v2 name; "medecin" is accepted as an alias by rp_jobs) and the
-- society (rp_bank) every fee and bill is paid into.
Config.job = "trauma"
Config.society = "trauma"

-- How long a player stays "down" after death before /respawn is accepted while a
-- medic is on duty. Production value: 600 (10 min). This eval config uses 60 so the
-- whole flow can be tested with one player in a minute.
Config.downSeconds = 60

-- /respawn is accepted after the countdown, or at once when no medic is on duty.
-- `true` keeps the countdown even with nobody on duty, so one tester alone can see it
-- (this eval config). Production: false.
Config.countdownWithoutMedics = true

-- What the hospital charges for a /respawn (account -> society, then cash, then an
-- unpaid row in rp_trauma_bills).
Config.hospitalBill = 500

-- Medic fees, charged to the patient and paid into the trauma society.
Config.healFee = 100    -- Stabilise (ALT+click) / /soin
Config.reviveFee = 300  -- Revive (ALT+click) / /reanimer; free for contract holders

-- Progress bars shown to the medic (milliseconds).
Config.stabiliseMs = 5000
Config.reviveMs = 8000

-- Ranges in metres: the ALT+click action, and the slash-command fallback.
Config.actionRange = 3.0
Config.commandRange = 5.0

-- Health of a player while down (fraction of their maximum) and after a medic
-- revive. A hospital respawn restores full health.
Config.downHealthFraction = 0.05
Config.reviveHealthFraction = 0.5
Config.reviveGraceMs = 5000

-- Seconds between two paid acts of the same medic (spam guard).
Config.medicCooldownSeconds = 10

-- Reminder sent to a down player every N seconds (chat + toast).
Config.downReminderSeconds = 30

-- Trauma Team contract: price per period, period length in minutes of server time,
-- and how many consecutive failed renewals cancel the contract.
Config.contractPrice = 1000
Config.contractMinutes = 30
Config.contractMaxFailures = 2

-- "The hospital": where a /respawn puts the body. In the lore you wake up at Vik's, so
-- it is Viktor Vektor's clinic (Little China, Watson; the rp_zones `viktor_clinic` zone,
-- AMM chair room -1548, 1230, 11.5), 855 m south-west of the freeroam spawn (Kabuki
-- Market Centre -1191.30, 2006.88, 7.82). The respawn point is 2 m off the chair.
-- The keys keep their names (rp_config overrides `rp_trauma.hospital.*`).
Config.hospital = {
    zone = "viktor_clinic",
    respawn = { x = -1546.0, y = 1231.0, z = 11.6 },
    heading = 180.0,
}

-- The Trauma Team AV spawned by /trauma av (on-duty medic, standing on the pad).
-- `Vehicle.av_trauma` is the "AV Trauma" record of the 2.31 catalogue (class av,
-- 4 seats). No `_player` variant of any AV exists in the catalogue; if this record
-- refuses to spawn on your build, try `Vehicle.av_rayfield_excalibur`.
Config.av = {
    record = "Vehicle.av_trauma",
    spawnDistance = 8.0,   -- metres in front of the medic
    spawnUp = 1.0,         -- metres above the medic's feet
    ttlMs = 30 * 60 * 1000,
    despawnWhenUnobserved = true,
    -- The landing / dispatch pad: the real street outside the Afterlife ramp (probed
    -- crosswalk -1408.0, 960.0, 23.5; a clinic interior cannot take an AV). The medic must
    -- stand within `radius` metres (planar) of it for /trauma av.
    pad = { x = -1370.0, y = 953.0, z = 23.5, radius = 12.0, label = "Afterlife street" },  -- east of the garage bays (-1398..-1380, y 953) so the AV never lands on a parked car
}

-- Blips drawn on every on-duty medic's map while a player is down. A per-blip
-- colour does not exist on 2.31, so the "gold" contract-holder pin is a different
-- sprite. `refreshMs` is how often the distance in the pin title is refreshed.
Config.blip = {
    sprite = "SOSsignalVariant",
    contractSprite = "important",
    refreshMs = 2000,
}

-- Chat colours (positional { r, g, b } arrays, as the chat UI expects).
Config.colors = {
    trauma = { 255, 96, 96 },
    alert = { 255, 190, 60 },
    info = { 120, 200, 255 },
}
