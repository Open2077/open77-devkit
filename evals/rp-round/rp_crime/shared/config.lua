-- rp_crime configuration. Every position, price, delay and chance lives here so the
-- owner can move things without touching server/main.lua. Coordinates are world metres;
-- the eval map sits on the flat band around the freeroam spawn 381.36, -2401.79, 181.99.
RpCrimeConfig = {
    -- Chat presentation.
    chat = {
        author = "CRIME",
        color = { 255, 96, 64 },        -- the robber's lines
        ncpdColor = { 0, 229, 255 },    -- the APB line an officer reads
    },

    -- rp_config overrides: every key below may be overridden through
    -- pcall(exports.rp_config:get, "rp_crime.<path>") when rp_config runs (optional).
    configPrefix = "rp_crime.",

    -- Shop robbery (/braquer). The vendors are the rp_shops v2 vendors; rp_shops exposes no
    -- export for their positions, so they are repeated here (keep them in sync with
    -- rp_shops/shared/config.lua).
    robbery = {
        reach = 3.0,                      -- metres from the vendor to start
        finishReach = 5.0,                -- re-checked after the bar (rp_shops:rob applies 5 m too)
        durationMs = 20000,               -- "Emptying the till..." progress bar
        cooldownMs = 20 * 60 * 1000,      -- per shop, on top of rp_shops' own 20 min cooldown
        requireWeaponDrawn = true,        -- Open77.weapons.get(id).drawn must be true
        alertText = "%s is being robbed",
        recordText = "Armed robbery of %s (%d eddies)",
        shops = {
            supermarket = { label = "Badlands Market",        vendor = "Rosa",    position = { x = 370.0, y = -2385.0, z = 182.0 } },
            pharmacy    = { label = "Med-Point Pharmacy",     vendor = "Dr. Osei", position = { x = 396.0, y = -2372.0, z = 182.0 } },
            gunshop     = { label = "2nd Amendment Outpost",  vendor = "Wilson",  position = { x = 410.0, y = -2386.0, z = 182.0 } },
            clothes     = { label = "Jinguji Threads",        vendor = "Kimiko",  position = { x = 352.0, y = -2398.0, z = 182.0 } },
            blackmarket = { label = "Back-alley Dealer",      vendor = "Dex",     position = { x = 402.0, y = -2393.0, z = 182.0 } },
        },
    },

    -- Vehicle theft (/crocheter).
    theft = {
        reach = 4.0,                      -- metres from the vehicle
        durationMs = 12000,               -- "Jimmying the lock..." progress bar
        lockpickItem = "lockpick",        -- rp_inventory built-in item
        lockpickBreakChance = 0.5,        -- consumed 50 % of the time, on success only
        wantedReason = "stolen",          -- rp_garage:setWanted(plate, true, reason)
        hornMs = 300,                     -- a short horn when the lock gives (0 = silent)
        -- On-duty officers within this distance of a wanted vehicle read an APB line every tick.
        spotDistance = 20.0,
        spotTickMs = 30000,
    },

    -- Street deal (/dealer <playerId>).
    deal = {
        item = "drug_pack",               -- declared by rp_gangs in rp_inventory
        price = 120,                      -- eddies, cash, buyer -> dealer
        reach = 3.0,                      -- metres between dealer and buyer
        durationMs = 3000,                -- the synchronized `give` animation
        inviteTimeoutMs = 30000,          -- the buyer has 30 s to /interaction accept
        influence = 1,                    -- rp_gangs:addInfluence(zone, gang, influence, "deal")
        alertChance = 0.20,               -- rp_ncpd:alert("drugs", ...) 20 % of the time
        alertText = "Street deal spotted near %s",
    },

    -- Contraband (/voler): gut a nomad crate that is not yours.
    contraband = {
        reach = 3.0,                      -- metres from the crate prop
        durationMs = 8000,                -- "Prying the crate open..." progress bar
        ownerResource = "rp_nomade",      -- props whose snapshot.resource is this are crates
        item = "stolen_parts",            -- what lands in the pockets
        count = 1,
    },

    -- The fence (/receler and the E prompt on the NPC), scrapyard, night only.
    fence = {
        name = "Vik the Fence",
        -- measured 18 Sept (groundz): 470,-2344 is 3 m down the slope (175.1); Vik now stands
        -- on the scrapyard floor at 178.3, between the wrecks, inside the rp_zones `scrapyard`
        position = { x = 464.0, y = -2350.0, z = 178.3 },
        yaw = 225.0,
        reach = 5.0,                      -- metres for /receler and the prompt (server re-check)
        openHour = 22,                    -- [openHour, closeHour) in server world time
        closeHour = 6,
        openWithoutClock = true,          -- no open77_weather = never closed (logged once)
        promptLabel = "Sell stolen goods",
        promptDescription = "Cash for anything that fell off a truck",
        promptKey = "E",
        promptDistance = 2.5,
        -- NPC look: legacy aliases tried in order (Open77.npcs.templates()), then the raw records.
        -- Only these four aliases are validated on this build; a Character.* record from the
        -- catalogue may be put first in `records` once proven on your clients.
        aliases = { "gang_tygerclaws_ranged_01", "gang_valentinos_ranged_01", "civilian_female_relaxed_01" },
        records = { "Character.Judy" },
        damagePolicy = 2,                 -- numeric: 2 = invulnerable
        stolenPartsPrice = 300,           -- eddies per stolen_parts
        implantRatio = 0.40,              -- share of the ripper's price paid for an implant_box_* item
        -- The ripper's prices per boxed implant id (rp_ripperdoc). Unknown ids use `default`.
        implantPrices = {
            default = 1000,
        },
        greetingVoice = "greeting",       -- Open77.npcs.speak voContext names
        closedVoice = "rep_ask_to_leave",
    },

    -- Items declared in rp_inventory through exports.rp_inventory:define.
    items = {
        stolen_parts = { label = "Stolen parts", weight = 2.0, usable = false, illegal = true },
    },

    -- Persistence.
    database = {
        table = "rp_crime_log",
        graceMs = 15000,                  -- wait this long for the database before falling back to kvp
        kvpKeep = 200,                    -- rows kept in the kvp fallback
    },
}
