-- rp_ferrailleur configuration (shared: the client places the rings, the server checks the distances).
-- Every world position is here so the owner can move the yard without touching the scripts.
RpFerrailleurConfig = {}
local Config = RpFerrailleurConfig

-- The job name in rp_jobs and the society name in rp_bank.
Config.job = "ferrailleur"
Config.society = "ferrailleur"

-- The yard is the real Rancho Coronado junkyard on the Badlands edge (AMM point 1374.9,
-- -1674.9, 49.3, yaw -173): the `junkyard` zone of rp_zones (same centre, radius 90).
-- It is about 4.5 km south-east of the Kabuki Market spawn: drive.
Config.zone = "junkyard"

-- Wreck collection points: 7 points within 17 m of the yard centre, 6 m or more apart, and
-- clear of the other junkyard spots (rp_crime's fence at 1381,-1668, rp_gangs' buyer at
-- 1370,-1670, rp_mecano's impound at 1370,-1680). z = the AMM ground + 0.1; the yard is not
-- flat, so if a ring is invisible in game, stand on the spot, `/pos`, and paste the real
-- ground height here (the server tolerates 4 m, `heightTolerance`).
Config.points = {
    { x = 1380.0, y = -1682.0, z = 49.4, label = "Burnt-out Thorton" },
    { x = 1386.0, y = -1676.0, z = 49.4, label = "Gutted Quadra" },
    { x = 1388.0, y = -1664.0, z = 49.4, label = "Rusted Mizutani" },
    { x = 1376.0, y = -1660.0, z = 49.4, label = "Crushed Archer" },
    { x = 1366.0, y = -1664.0, z = 49.4, label = "Stripped Makigai" },
    { x = 1362.0, y = -1686.0, z = 49.4, label = "Flipped Villefort" },
    { x = 1372.0, y = -1690.0, z = 49.4, label = "Scorched Chevillon" },
}

-- Decoration spawned by the server at start (Open77.props.create, permission `world.props`)
-- and removed at stop: a trash drum by the dealer, a tyre by the first wreck, a corrugated
-- sheet by the fourth -- each 1.2-1.5 m off its ring. Raw depot `.mesh` paths from the props
-- catalogue; a refused prop is logged, never fatal.
Config.props = {
    { model = "container.barrel",
      position = { x = 1366.6, y = -1674.6, z = 49.4 }, yaw = -173.0 },
    { model = "garbage.industrial_trash",
      position = { x = 1381.4, y = -1683.4, z = 49.4 }, yaw = 20.0 },
    { model = "debris.corrugated_sheet",
      position = { x = 1377.5, y = -1658.6, z = 49.4 }, yaw = -60.0 },
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
    position = { x = 1368.0, y = -1676.0, z = 49.4 },
    yaw = -173.0,                                  -- the yard's own heading (AMM)
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
