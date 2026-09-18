-- rp_ambiance configuration. Shared script: public, no secret and no ACL in here.
-- Every position is in world metres around the freeroam spawn 381.36, -2401.79, 181.99.
-- Runtime overrides: rp_config (when it runs) may override the scalar keys listed at the
-- bottom of this file (`Config.overrides`); `/ambiance reload` re-reads them.

Config = {}

-- ---------------------------------------------------------------------------
-- (1) Day cycle and weather
-- ---------------------------------------------------------------------------
Config.cycle = {
    -- Real hours for one 24-hour game day. 3 h -> 8 game seconds per real second, which is
    -- the engine's own rate: at 8 the projection never has to correct the clock. Any other
    -- value costs a world time-jump every drift correction (setTimeRate card, measured 25 Aug).
    realHoursPerDay = 3,

    -- nil keeps the clock where the server left it; a number (0..23) forces that hour on start
    -- and on /ambiance reload.
    startHour = nil,

    -- Real minutes one weather draw lasts before the next draw.
    weatherMinMinutes = 12,
    weatherMaxMinutes = 25,

    -- Seconds the sky takes to blend into the new preset (0..300).
    weatherTransitionSeconds = 45,

    -- The RP map sits in the Badlands: sandstorms are allowed. Set false for a city map and
    -- the sandstorm row is dropped from the draw (its weight is simply not counted).
    badlands = true,

    -- Weighted table. `preset` is an open77_weather name (sunny, lightclouds, cloudy, rain,
    -- heavyclouds, fog, pollution, sandstorm). Weights need not sum to 100.
    weather = {
        { preset = "sunny",     weight = 50, label = "Clear skies",  toast = "Clear skies over the Badlands. Enjoy it while it lasts, choom." },
        { preset = "cloudy",    weight = 25, label = "Overcast",     toast = "Clouds rolling in from the west." },
        { preset = "rain",      weight = 15, label = "Rain",         toast = "Acid rain incoming. Keep your chrome dry." },
        { preset = "sandstorm", weight = 5,  label = "Sandstorm",    toast = "Sandstorm warning. Visibility dropping - stay off the roads.", badlandsOnly = true },
        { preset = "fog",       weight = 5,  label = "Fog",          toast = "Fog on the flats. Watch your step out there." },
    },

    -- Toast everyone on each draw (and on /ambiance weather).
    announceWeather = true,
    weatherToastMs = 8000,
}

-- ---------------------------------------------------------------------------
-- (2) Figurants: 2-3 civilian NPCs per key zone
-- ---------------------------------------------------------------------------
Config.figurants = {
    enabled = true,

    -- Re-spawn sweep: a killed or missing figurant comes back at the next sweep.
    sweepSeconds = 300,

    -- Wander radius around the zone centre and the distance a player must be within to
    -- trigger a line.
    wanderRadius = 6.0,
    speakRadius = 8.0,

    -- A figurant speaks every 60-120 s while somebody is within speakRadius.
    speakMinSeconds = 60,
    speakMaxSeconds = 120,

    -- Numeric damage policy (2 = invulnerable) -- the create native wants the number.
    damagePolicy = 2,
    streamingRadius = 150,

    -- Audible barks paired with the text lines: voContext names from Open77.npcs.voices().
    -- A name a record's voiceset does not carry is silent (the engine drops it without a word).
    barks = { "greeting", "bump", "stlh_curious" },

    -- The bodies. Each entry is a `record` (Character.*) or a legacy `template` alias.
    -- These three have documentation provenance (npcs / npc-behavior guides); swap in vanilla
    -- crowd citizens from docs/generated/npc-records-2.31.csv once tested on your clients.
    bodies = {
        regular = { record = "Character.Judy" },
        nomad   = { template = "civilian_female_relaxed_01" },          -- Character.Panam, passive background body
        ganger  = { record = "Character.cpz_maelstrom_grunt1_ranged1_lexington_wa" },
    },

    -- Chat colour of a figurant line.
    chatColor = { 170, 170, 190 },

    -- Per zone: the centre (mirrors rp_zones/README.md), the bodies (2-3), display names,
    -- and the six lines. `linesForJob` (optional) replaces the pool when the nearest player
    -- holds that rp_jobs job.
    zones = {
        afterlife = {
            centre = { x = 360.0, y = -2390.0, z = 182.0 },
            bodies = { "regular", "nomad", "regular" },
            names  = { "Afterlife regular", "Tired merc", "Bar fly" },
            lines = {
                "You buying, choom, or just breathing my air?",
                "Heard a merc from Watson got flatlined over a data shard. Eddies ain't worth it.",
                "Two Johnny Silverhands and a tab I'll never pay. That's the Afterlife.",
                "Don't stare at the ripper in the corner. He bites. Literally, since the mantis job.",
                "Trauma Team never comes out here. Platinum or not, you're on your own past the plaza.",
                "If a fixer offers you a milk run, it's never a milk run.",
            },
            linesForJob = {
                ncpd = {
                    "Relax, officer. Nobody in here has a warrant. Tonight.",
                    "NCPD in the Afterlife. Now I've seen everything.",
                },
            },
        },
        blackmarket = {
            centre = { x = 400.0, y = -2390.0, z = 182.0 },
            bodies = { "ganger", "regular" },
            names  = { "Street dealer", "Lookout" },
            lines = {
                "Synthcoke, chips, a quickhack or two. Cash only, no questions.",
                "You didn't see me, I didn't see you. That's the deal, choom.",
                "Word is the NCPD outpost got a new sergeant. Bad for business.",
                "Scavs pay good eddies for chrome. Don't ask where they get it.",
                "Need a lockpick? A crowbar? Or something that goes bang?",
                "Netrunner fried a whole convoy's brakes last week. Nomads are still pissed.",
            },
            linesForJob = {
                ncpd = {
                    "Nothing to see here, officer. Just... vitamins.",
                    "Badge or no badge, you're standing on my corner.",
                },
            },
        },
        nomad_camp = {
            centre = { x = 420.0, y = -2378.0, z = 182.0 },
            bodies = { "nomad", "nomad" },
            names  = { "Aldecaldo mechanic", "Nomad kid" },
            lines = {
                "Convoy rolls at dawn. Chooh2 is topped up, tyres are not.",
                "City folks call it wasteland. We call it home, choom.",
                "Raffen Shiv hit the eastern route again. Ride in pairs.",
                "That Delamain cab won't make it past the first dune. Trust me.",
                "Family first, clan second, eddies a distant third.",
                "You want a ride? Bring your own fuel and your own gun.",
            },
        },
        ncpd_hq = {
            centre = { x = 440.0, y = -2366.0, z = 181.0 },
            bodies = { "regular", "nomad", "regular" },
            names  = { "Desk sergeant", "Off-duty cop", "Informant" },
            lines = {
                "Filing a complaint? Take a number. We'll get to it next year.",
                "Keep your iron holstered around the precinct, choom. Rookies are twitchy.",
                "Wanted list got longer overnight. Black market again, I'd bet.",
                "MaxTac doesn't come out this far. That's the good news and the bad news.",
                "If you see a Trauma AV, stay clear. They don't slow down for pedestrians.",
                "Somebody stole a patrol car last night. From the lot. With the lights on.",
            },
        },
    },
}

-- ---------------------------------------------------------------------------
-- (3) Rotating server notices
-- ---------------------------------------------------------------------------
Config.notices = {
    enabled = true,
    intervalMinutes = 15,
    -- Toast look (open77_notifications definition fields).
    type = "info",
    title = "Night City",
    icon = "NC",
    position = "top_right",
    durationMs = 10000,
    color = "#F5C400",
    -- Also write the notice in chat, in this colour.
    chatEcho = true,
    chatAuthor = "Night City",
    chatColor = { 245, 196, 0 },
    lines = {
        "Rules: no RDM, no VDM, stay in character. /ooc for out-of-character talk.",
        "New in town? /carte shows your ID card, /civil registers one.",
        "Looking for work? Walk to the employment agency by the spawn, or type /agence.",
        "The Afterlife, the black market, the nomad camp and the NCPD outpost are all within 80 m of the plaza. /zones lists them.",
        "Cash runs out. /bank for an account, /solde for the balance, /payday every 10 minutes.",
        "Hurt? /911 pages Trauma Team. Robbed? /ncpd pages the badges. Both cost eddies.",
        "The plaza is a safe zone. Step outside the ring and you are fair game, choom.",
        "Report griefers with /report. Admins read the tickets.",
    },
}

-- ---------------------------------------------------------------------------
-- (4) NCPD alert sirens
-- ---------------------------------------------------------------------------
Config.alerts = {
    enabled = true,
    -- The one-shot world effect flashed at the alert position and the Wwise event played
    -- spatialised there (Open77.effects.play `sound`). Both names come from the platform's
    -- catalogues; the siren event is a 2.31 seed entry that still awaits runtime validation.
    effect = "sparks.burst.small",
    sound = "amb_g_city_el_signals_police_siren_short_01",
    -- Players within this many metres of the alert see and hear it.
    range = 60.0,
    -- The flash is repeated to read as a strobe; the siren plays once, with the first flash.
    flashes = 3,
    flashIntervalMs = 1200,
    -- One siren per position per this many seconds (rp_ncpd can raise several alerts at once).
    cooldownSeconds = 8,
}

-- ---------------------------------------------------------------------------
-- (5) Ambience loop per zone
-- ---------------------------------------------------------------------------
Config.music = {
    enabled = true,
    -- 0..1 gain of the loop, and the sound id prefix (one loop per player per zone).
    volume = 0.35,
    -- rp_bar already plays its own ambience at the counter: when it runs, the Afterlife loop is
    -- skipped so the two never stack.
    skipWhenResourceRuns = { afterlife = "rp_bar" },
    -- Files must be declared in the manifest `files` entry. The shipped WAVs are synthesised
    -- placeholders (12 s seamless loops); replace them with real assets of at most 1 MiB.
    zones = {
        afterlife   = { file = "sfx/afterlife.wav" },
        blackmarket = { file = "sfx/blackmarket.wav" },
    },
}

-- ---------------------------------------------------------------------------
-- Command and log
-- ---------------------------------------------------------------------------
Config.command = {
    name = "ambiance",
    chatAuthor = "Ambiance",
    chatColor = { 0, 229, 255 },
}

-- Keys rp_config may override (`rp_ambiance.<key>` -> Config.<section>.<field>).
-- Read with pcall(exports.rp_config:get, key) at start and on /ambiance reload; the
-- resource keeps working untouched when rp_config does not run.
Config.overrides = {
    { key = "rp_ambiance.realHoursPerDay",        section = "cycle",     field = "realHoursPerDay" },
    { key = "rp_ambiance.weatherMinMinutes",      section = "cycle",     field = "weatherMinMinutes" },
    { key = "rp_ambiance.weatherMaxMinutes",      section = "cycle",     field = "weatherMaxMinutes" },
    { key = "rp_ambiance.badlands",               section = "cycle",     field = "badlands" },
    { key = "rp_ambiance.noticeIntervalMinutes",  section = "notices",   field = "intervalMinutes" },
    { key = "rp_ambiance.figurantsEnabled",       section = "figurants", field = "enabled" },
    { key = "rp_ambiance.musicVolume",            section = "music",     field = "volume" },
    { key = "rp_ambiance.alertsEnabled",          section = "alerts",    field = "enabled" },
}
