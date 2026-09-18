-- rp_housing configuration. Shared by the client (rings, prompts, pins) and the
-- server (distances, prices, rent). Every position is world metres; the owner
-- moves them by editing this file. z = 182 is the plateau height around the
-- freeroam spawn (381.36, -2401.79, 181.99), measured by rp_zones; stand on a
-- spot and run /pos to correct a ring that is drawn inside the floor.
Config = {}

-- Money. Rent is charged from the bank account (rp_bank:charge into the
-- "housing" society, a sink nobody can withdraw from); when the account is
-- short the cash wallet (rp_economy) is tried; when both are short the rent is
-- unpaid. evictAfter consecutive unpaid rents = evicted, keys revoked.
Config.society = "housing"        -- rp_bank society that receives rents and purchases
Config.rent = 500                 -- default rent per payday, per home (a home may override it)
Config.rentIntervalSec = 600      -- one payday = 10 minutes, same rhythm as rp_economy
Config.rentTickSec = 60           -- how often the server looks for due rents
Config.evictAfter = 2             -- unpaid rents (in a row) before eviction
Config.sellBackRatio = 0.70       -- /maison vendre pays back this share of the price, in cash

-- Distances (metres). The E prompt is only pressable within promptDistance
-- while looking at the ring; the server re-checks with a little tolerance
-- because its position snapshot can lag a running player by a tick.
Config.promptDistance = 3.0       -- open77_worldui prompt range for every ring
Config.serverTolerance = 2.5      -- added to promptDistance on the server side
Config.agencyRadius = 4.0         -- /agence_immo and the agency prompt: how close to the desk
Config.keyDistance = 3.0          -- /maison cles and ALT+click "Give a key": how close to the receiver
Config.interiorRadius = 8.0       -- further than this from the interior spot = no longer "inside"

-- Screen fade around the teleport in and out (ms, 0..10000). Applied through
-- Open77.players.teleport's own fade option (fadeOutMs / fadeInMs).
Config.enterFade = 400

-- How long the server waits for a freshly connected player to be alive before
-- moving them home (/maison spawn). The freeroam gamemode spawns everybody at
-- the plaza first; the host has no "spawn point" API, so the move happens once
-- the body is standing (see README, "Respawn at home").
Config.spawnWaitSec = 30

-- The real-estate agency: a ring + E prompt + map pin. 7 m south-west of the spawn.
Config.agency = {
    label = "Real-estate agency",
    description = "Buy or sell a place to crash.",
    position = { x = 365.0, y = -2408.0, z = 182.0 },
    radius = 1.5,
}

-- Homes. Fields:
--   id        stable identifier (letters, digits, underscore), also the map/stash key
--   label     what players read
--   district  flavour text for the agency menu
--   zone      optional rp_zones zone name; its label replaces `district` when rp_zones runs
--   price     purchase price in eddies; sold back at Config.sellBackRatio
--   rent      optional per-home rent (defaults to Config.rent)
--   entrance  the door ring: the E prompt "Apartment door", and where leaving puts you
--   interior  where entering puts you (on the eval config: 6 m away on the same plateau;
--             the owner maps real interiors here)
--   stash     where the "Stash" ring stands (defaults to interior + 1.5 m east)
--   exit      where the "Front door" (leave) ring stands (defaults to interior - 1.5 m east)
--   heading   optional body yaw applied on arrival (degrees)
--   doorId    optional open77_doors engine id ("0x..." string). Empty on the eval
--             config: no known door there. When set, the server claims the door and
--             locks it to the owner and the key holders (defaultAccess = false).
-- All five sit on the plateau between the spawn plaza rings: clear of the
-- afterlife (360,-2390 r10), mecano (341,-2401 r10) and black market (400,-2390 r10)
-- zone rings, the ATM ring on the spawn and the agency. East of x 400 at y -2401
-- there is no ground (rp_zones measurement), so nothing goes past x 392; west of x 350 at
-- y -2386 the plateau drops (groundz 18 Sept), so nothing goes past x 352 either.
Config.homes = {
    {
        id = "northside_container",
        label = "Northside container",
        district = "Northside, Watson",
        zone = nil,
        price = 9000,
        -- measured 18 Sept (groundz): 348,-2386 is the cliff slope (176.6) and 342,-2386 the
        -- cliff bottom (159); the container now stands on the west lawn, ground 181.1-181.3
        entrance = { x = 354.0, y = -2394.0, z = 181.3 },
        interior = { x = 354.0, y = -2388.0, z = 181.1 },
        doorId = "",
    },
    {
        id = "badlands_hideout",
        label = "Badlands hideout",
        district = "Badlands, outside the walls",
        zone = "badlands",
        price = 15000,
        entrance = { x = 352.0, y = -2404.0, z = 182.0 },
        interior = { x = 352.0, y = -2410.0, z = 182.0 },
        doorId = "",
    },
    {
        id = "h10_studio",
        label = "Megabuilding H10 studio",
        district = "Little China, Watson",
        zone = nil,
        price = 25000,
        entrance = { x = 376.0, y = -2380.0, z = 182.0 },
        interior = { x = 376.0, y = -2374.0, z = 182.0 },
        doorId = "",
    },
    {
        id = "kabuki_flat",
        label = "Kabuki flat",
        district = "Kabuki, Watson",
        zone = nil,
        price = 40000,
        entrance = { x = 388.0, y = -2388.0, z = 182.0 },
        interior = { x = 388.0, y = -2382.0, z = 182.0 },
        doorId = "",
    },
    {
        id = "japantown_loft",
        label = "Japantown loft",
        district = "Japantown, Westbrook",
        zone = nil,
        price = 65000,
        -- measured 18 Sept (groundz): no ground reported at 390,-2405; the loft interior moved
        -- to the plaza centre, ground 181.87
        entrance = { x = 390.0, y = -2399.0, z = 182.0 },
        interior = { x = 384.0, y = -2393.0, z = 181.9 },
        doorId = "",
    },
}

-- Prompt copy (English, on purpose: it is what every player reads).
Config.text = {
    door = "Apartment door",
    doorDescription = "Enter if you hold the keys.",
    stash = "Stash",
    stashDescription = "Your private stash, 200 kg.",
    exit = "Front door",
    exitDescription = "Step back outside.",
}

-- Stash capacity handed to rp_inventory:openStash, in kg.
Config.stashCapacity = 200

-- Derived helpers shared by both runtimes. Fill the optional positions.
for _, home in ipairs(Config.homes) do
    home.rent = home.rent or Config.rent
    home.stash = home.stash or { x = home.interior.x + 1.5, y = home.interior.y, z = home.interior.z }
    home.exit = home.exit or { x = home.interior.x - 1.5, y = home.interior.y, z = home.interior.z }
    home.doorId = home.doorId or ""
end

function Config.home(id)
    for _, home in ipairs(Config.homes) do
        if home.id == id then return home end
    end
    return nil
end
