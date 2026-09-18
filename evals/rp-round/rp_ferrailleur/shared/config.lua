-- rp_ferrailleur configuration (shared: the client places the rings, the server checks the distances).
-- Every world position is here so the owner can move the yard without touching the scripts.
RpFerrailleurConfig = {}
local Config = RpFerrailleurConfig

-- The job name in rp_jobs and the society name in rp_bank.
Config.job = "ferrailleur"
Config.society = "ferrailleur"

-- The scrapyard zone of rp_zones (centre 462, -2352, z 178, radius 12). Every point below
-- lies on the flat ground inside it, 95 m north-east of the freeroam spawn (381.36, -2401.79, 181.99).
Config.zone = "scrapyard"

-- Wreck collection points: 7 points on a ring 5.7 to 6.4 m apart, all within 7.2 m of the centre.
-- z is the measured ground height of the yard (178). If a ring is invisible in game, stand on
-- the spot, `/pos`, and paste the real ground height here.
Config.points = {
    { x = 456.0, y = -2356.0, z = 178.0, label = "Burnt-out Thorton" },
    { x = 461.0, y = -2359.0, z = 178.0, label = "Gutted Quadra" },
    { x = 467.0, y = -2357.0, z = 178.0, label = "Rusted Mizutani" },
    { x = 469.0, y = -2351.0, z = 178.0, label = "Crushed Archer" },
    { x = 465.0, y = -2346.0, z = 178.0, label = "Stripped Makigai" },
    { x = 459.0, y = -2346.0, z = 178.0, label = "Flipped Villefort" },
    { x = 455.0, y = -2350.0, z = 178.0, label = "Scorched Chevillon" },
}

-- How close the player must stand to a wreck to search it (planar metres) and the
-- height error the server tolerates (the z above is a measurement, not a promise).
Config.searchReach = 3.5
Config.heightTolerance = 4.0

-- The search: an 8 s progress bar, move + combat disabled, with the RP kneel `examine`.
Config.searchMs = 8000
Config.animation = { profile = "examine" }

-- A searched wreck regenerates after 5 min.
Config.regenMs = 5 * 60 * 1000

-- Loot roll: weights sum to 100. `count` is drawn uniformly in [min, max].
Config.loot = {
    { item = "scrap",     min = 2, max = 4, weight = 60 },
    { item = "component", min = 1, max = 2, weight = 30 },
    { item = "chip",      min = 1, max = 1, weight = 10 },
}

-- The crowbar: declared in rp_inventory through `define`, durability tracked here per scrapper.
Config.crowbar = {
    id = "crowbar",
    label = "Crowbar",
    weight = 1.5,
    durability = 20,     -- searches per crowbar (1 durability per search, breaks at 0)
    price = 250,         -- eddies, sold by the dealer
}

-- The scrap dealer NPC. `record` (a Character.* id) is tried first when set; the documented
-- passive civilian alias is the fallback (Character.Panam, invulnerable by TweakDB).
Config.dealer = {
    position = { x = 462.0, y = -2352.0, z = 178.0 },
    yaw = 200.0,
    record = nil,                                  -- e.g. "Character.Judy"
    template = "civilian_female_relaxed_01",       -- legacy alias, Open77.npcs.templates()
    damagePolicy = 2,                              -- 2 = invulnerable (numeric on op77.76)
    reach = 5.0,                                   -- metres for the prompt and for /vendre
    name = "Rusty",
}

-- Base unit prices in eddies; the dealer's price swings +/- `priceVariation` every `priceIntervalMs`.
Config.basePrices = { scrap = 15, component = 60, chip = 200 }
Config.sellOrder = { "scrap", "component", "chip" }
Config.priceVariation = 0.20
Config.priceIntervalMs = 10 * 60 * 1000

-- Share of every sale that goes to the `ferrailleur` society (rp_bank); the rest is cash for
-- the scrapper. Set to 0 to give the scrapper everything.
Config.societyShare = 0.10

-- Presentation of the rings (open77_worldui styles are fixed presets: interaction, objective,
-- spawn, danger). Only a `ready` wreck carries the E prompt.
Config.ringRadius = 1.2
Config.promptDistance = 3.0
Config.ring = {
    ready    = { style = "interaction" },
    busy     = { style = "objective" },
    depleted = { style = "danger" },
}

-- How long (ms) the server waits for the database before falling back to Open77.kvp.
Config.databaseGraceMs = 15000
