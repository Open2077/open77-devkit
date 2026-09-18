-- rp_nomade configuration. Loaded on both runtimes (shared_script): the client reads the
-- positions to draw rings and prompts, the server checks every distance against the same numbers.
-- Every position is in world metres. The eval server spawns everyone at 381.36, -2401.79, 181.99.
RpNomadeConfig = {}

-- The nomad camp (rp_zones `nomad_camp`: centre 420, -2378, z 182, radius 9).
RpNomadeConfig.Camp = {
    zone = "nomad_camp",                                   -- rp_zones name used for the truck return
    position = { x = 420.0, y = -2378.0, z = 182.0 },      -- camp centre, what /camp reports
    -- The contracts board: a ring, a map pin and an E prompt (open77_worldui).
    board = {
        position = { x = 420.0, y = -2381.5, z = 182.0 },
        radius = 1.0,
        promptDistance = 3.0,
        reach = 5.0,                                       -- server-side distance check when the prompt fires
        label = "Contracts board",
        description = "Convoys and crate runs for the clan.",
    },
    -- Where the rented truck appears.
    truckSpawn = { x = 427.0, y = -2381.0, z = 182.3, yaw = 180.0 },
    -- Loading points: one crate per point, in order. Templates never ask for more crates than points.
    loadingPoints = {
        { x = 416.0, y = -2374.5, z = 182.0 },
        { x = 418.0, y = -2373.5, z = 182.0 },
        { x = 420.0, y = -2373.5, z = 182.0 },
        { x = 422.0, y = -2374.5, z = 182.0 },
    },
}

-- Delivery destinations, keyed by rp_zones name. The server asks rp_zones:isIn(driver, name);
-- the ring is drawn at `position` and the distance fallback (rp_zones missing) uses `radius`.
RpNomadeConfig.Destinations = {
    blackmarket = {
        label = "Black market warehouse",
        position = { x = 400.0, y = -2390.0, z = 182.0 },
        radius = 10.0,
    },
    scrapyard = {
        label = "Scrapyard",
        position = { x = 462.0, y = -2352.0, z = 178.0 },
        radius = 12.0,
    },
}

-- Contract templates offered on the board. `crates` 2..4, `destination` a key of Destinations.
RpNomadeConfig.Templates = {
    {
        id = "scav_parts",
        label = "Scav parts run",
        description = "Three crates of stripped parts for the black market. No questions.",
        crates = 3,
        destination = "blackmarket",
    },
    {
        id = "chooh2_barrels",
        label = "CHOOH2 barrels",
        description = "Two crates of fuel cans. Do not smoke on the way.",
        crates = 2,
        destination = "blackmarket",
    },
    {
        id = "militech_salvage",
        label = "Militech salvage",
        description = "Four crates nobody should ask about. Heavy, and the Wraiths know.",
        crates = 4,
        destination = "blackmarket",
    },
}

RpNomadeConfig.Contract = {
    payPerCrate = 150,          -- eddies, cash, paid to the driver per delivered crate
    convoyBonus = 0.25,         -- share of the gross pay, split between the convoy members
    convoyRadius = 30.0,        -- nomads on duty within this distance of the truck at delivery form the convoy
    convoyMinimum = 2,          -- driver included: two or more nomads = a convoy
    societyShare = 0.15,        -- share of the gross pay credited to the `nomade` society (on top of the pay)
    society = "nomade",         -- rp_bank society name (lower-case job name)
    timeLimitMs = 20 * 60 * 1000,
    unloadMs = 6000,            -- progress bar per crate at the warehouse
    historyRows = 10,           -- /convois: last N contracts
}

RpNomadeConfig.Truck = {
    -- Player-spawnable records (they end in _player) tried in order until one spawns.
    -- Thorton Mackinaw: the nomad pickup. Legatus: a heavy Chevalier truck.
    records = {
        "Vehicle.v_standard3_thorton_mackinaw_player",
        "Vehicle.v_standard3_thorton_mackinaw_02_player",
        "Vehicle.v_utility4_chevalier_legatus_player",
    },
    rental = 100,               -- eddies, cash, refunded when the truck is returned inside the camp zone
    reach = 4.0,                -- load / unload / return: the player must be within this distance of the truck
    ttlMs = 40 * 60 * 1000,     -- safety net: the vehicle registry removes a forgotten truck after this
}

RpNomadeConfig.Crate = {
    -- Curated prop aliases tried in order. Attachment to a hand needs an alias (a raw .mesh path
    -- spawns a standing crate but cannot be attached, the carry then hides the prop instead).
    models = { "crate.small" },
    pickupDistance = 3.5,       -- server-side check when the crate prompt fires (prompt itself: 3.0 m)
    promptDistance = 3.0,
    ringRadius = 0.6,
    label = "Pick up the crate",
    description = "Heavy. Get it to the truck.",
}

-- How a carried crate is shown. "attach": the crate prop rides the carrier's hand bone
-- (Open77.props.attach, everyone sees it). "held": the prop is hidden and an item record is put
-- in the right hand through Open77.heldItems.hold (needs the bundled open77_helditems client).
RpNomadeConfig.Carry = {
    mode = "attach",
    bone = "RightHand",
    offset = { x = 0.0, y = 0.0, z = 0.0 },
    rotation = { x = 0.0, y = 0.0, z = 0.0 },
    heldItem = { record = "Items.GenericCraftingMaterial1", slot = "WeaponRight" },
}

-- The ambush: the FIRST time a loaded truck is inside this circle (and at least minTravel metres
-- from where it was rented, the eval circle overlaps the camp), hostile NPCs spawn around it.
RpNomadeConfig.Ambush = {
    enabled = true,
    center = { x = 410.0, y = -2384.0, z = 182.0 },
    radius = 20.0,
    minTravel = 10.0,
    count = 3,
    spawnDistance = 15.0,
    spreadDegrees = 35.0,
    lifetimeMs = 3 * 60 * 1000,
    -- Character.* records tried in order. The Maelstrom grunt is the platform's validated ranged
    -- combatant (legacy alias hostile_female_ranged_lab); swap in a Wraith record from the
    -- npc-catalogue once it is proven on your build.
    records = { "Character.cpz_maelstrom_grunt1_ranged1_lexington_wa" },
    damagePolicy = 0,           -- numeric: 0 = mortal (normal), 2 = invulnerable
    group = "rp_nomade_ambush", -- combat group: the ambushers never shoot each other
    announce = "Wraiths on the road! Raffen shivs closing on the convoy.",
}

-- Item declared in rp_inventory (exports.rp_inventory:define) so the crates exist as inventory items too.
RpNomadeConfig.Items = {
    nomad_crate = { label = "Nomad cargo crate", weight = 25.0, usable = false, illegal = false },
}

RpNomadeConfig.Ui = {
    tickMs = 1000,              -- server tick: deadline, ambush zone, truck watch
    color = "#F2B33D",          -- sand: the nomad colour on rings and prompts
    prefix = "[Convoys] ",
}
