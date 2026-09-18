-- rp_garage configuration. Shared: the client places the POIs from it, the server checks every
-- distance against the same numbers. Every position is here so the owner can move it.
Config = {}

-- The freeroam spawn of the eval server (a plaza labelled Badlands). Every POI below is within
-- 45 m of it so a tester reaches everything on foot.
Config.spawn = { x = 381.36, y = -2401.79, z = 181.99 }

-- Garages. `kind = "public"` is open to everybody; `kind = "society"` is reserved for the
-- employees of `society` (rp_jobs) and also lists that society's fleet vehicles.
-- `position` is the POI (ring + E prompt); `spawnPoint` is where a vehicle taken out appears
-- (`yaw` 0 faces +y on this engine). Stored vehicles can be taken out at any public garage.
Config.garages = {
    {
        id = "public",
        label = "Public garage",
        kind = "public",
        position = { x = 370.0, y = -2405.0, z = 182.0 },     -- 12 m west-south-west of the spawn
        spawnPoint = { x = 364.0, y = -2406.0, z = 182.0, yaw = 90.0 },
        color = "#00E5FF",
    },
    {
        id = "mecano",
        label = "Mechanic's garage",
        kind = "society",
        society = "mecano",                                    -- rp_jobs job name
        zone = "mecano_shop",                                  -- rp_zones name, informative
        position = { x = 341.0, y = -2401.0, z = 180.3 },     -- the rp_zones `mecano_shop` centre, 40 m west
        spawnPoint = { x = 347.0, y = -2405.0, z = 180.5, yaw = 90.0 },
        color = "#FF9A1F",
    },
}

-- The dealership POI and where a bought vehicle appears.
Config.dealership = {
    label = "Dealership",
    position = { x = 392.0, y = -2410.0, z = 182.0 },         -- 13 m south-east of the spawn
    spawnPoint = { x = 392.0, y = -2404.0, z = 182.0, yaw = 0.0 },
    color = "#F5D90A",
}

-- Records for sale. Every record was checked against `open77_data vehicles` (game 2.31) and
-- ends in `_player`, the spawnable variants. Prices in eddies.
Config.vehicles = {
    { record = "Vehicle.v_standard2_archer_hella_player",           label = "Archer Hella",              price = 15000 },
    { record = "Vehicle.v_sportbike2_arch_player",                  label = "Arch Nazare",               price = 12000 },
    { record = "Vehicle.v_standard3_thorton_mackinaw_player",       label = "Thorton Mackinaw",          price = 28000 },
    { record = "Vehicle.v_standard2_villefort_cortes_delamain_player", label = "Villefort Cortes Delamain", price = 45000 },
    { record = "Vehicle.v_sport1_quadra_turbo_player",              label = "Quadra Turbo-R",            price = 60000 },
}

-- Money. Purchases and release fees go account -> society through rp_bank:charge; when the
-- account is short the cash wallet (rp_economy) pays and the society is credited afterwards.
Config.society = "garage"          -- rp_bank society that receives the dealership sales
Config.impound = {
    fee = 500,                     -- eddies to get an impounded vehicle back, paid at any garage
    society = "ncpd",              -- rp_bank society that receives the release fee
    lot = "ncpd_hq",               -- rp_zones name of the impound (informative)
    lotPosition = { x = 440.0, y = -2366.0, z = 181.0 },
}

-- Plates: NC-XXXX, four characters from this alphabet (no 0/O, 1/I ambiguity).
Config.plate = { prefix = "NC-", length = 4, alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" }

-- Reaches, in metres.
Config.reach = {
    prompt = 3.0,      -- promptDistance of the three POIs (E only within this distance)
    garage = 6.0,      -- /garage and /concession work within this distance of the POI
    store = 8.0,       -- a vehicle can be stored when it stands within this distance of the player
    lock = 6.0,        -- /verrouiller: nearest keyed vehicle within this distance
    plate = 8.0,       -- /plaque: nearest server vehicle within this distance
    key = 5.0,         -- /cles: the receiving player must be within this distance
    keyVehicle = 8.0,  -- /cles without a plate: nearest owned vehicle within this distance
    height = 4.0,      -- tolerated height error on POI checks (z of a POI is a guess)
}

-- Spawn: a bay is tried up to `spawnTries` times, `spawnStep` metres apart along x, and skipped
-- when another server vehicle stands within `spawnClearance` metres of it.
Config.spawnTries = 3
Config.spawnStep = 4.5
Config.spawnClearance = 3.0

-- Condition. A vehicle that was destroyed or exploded when it was stored or lost comes back
-- rolling: the wreck flags are cleared and the health floor below applies (the body damage,
-- broken glass, lights, tyres and torn-off panels are kept for the mechanic).
Config.minHealthOnTakeOut = 0.2

-- Every `snapshotIntervalMs` the server refreshes, in memory only, the condition and the fuel of
-- every vehicle that is out, so a vehicle removed by something else (admin /dv, an explosion
-- clean-up, a time to live) is put back in the garage in its last known state.
Config.snapshotIntervalMs = 30000

-- The same player entering the driver seat of a vehicle they hold no key for raises
-- rp_garage:stolen at most once per `stolenCooldownS` seconds.
Config.stolenCooldownS = 300

-- Dialog timeouts (ms), within the UI kit's 1 000..120 000.
Config.menuTimeoutMs = 60000
Config.confirmTimeoutMs = 30000
