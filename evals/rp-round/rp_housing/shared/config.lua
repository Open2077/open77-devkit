-- rp_housing configuration. Shared by the client (rings, prompts, pins) and the
-- server (distances, prices, rent). Every position is world metres; the owner
-- moves them by editing this file. The five homes are real Night City flats
-- (AMM interior points, 2026-09-18): `interior` is where entering puts you, the
-- entrance ring is the flat's own front door, found at runtime through
-- open77_doors (see Config.autoDoor) with a static fallback 3 m from the
-- interior point along +x.
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
-- Kabuki Market first; the host has no "spawn point" API, so the move happens
-- once the body is standing (see README, "Respawn at home").
Config.spawnWaitSec = 30

-- The flat's own front door ("auto door"). At start, and every `retrySec`
-- until it works, the server asks open77_doors for the doors discovered within
-- `radius` metres of each interior point and takes the nearest one as the
-- home's `doorId`: the door is then claimed and locked to the owner and the
-- key holders, and the three rings are derived from it along the door ->
-- interior axis: the entrance ring `outside` metres outside the door, the
-- "Front door" (exit) ring `inside` metres inside it, and the stash ring
-- `stashInside` metres beyond the interior point, further from the door (a
-- fixed x offset lands inside the walls: the interior points are AMM points
-- right at the doorstep, and every flat faces its own way). A door is only
-- discovered once a client has streamed it (walked past the flat), so until
-- then the static fallback is what the rings, the E prompts and the teleports
-- use: entrance = interior + `fallback` m along x, exit = the interior point
-- itself (the player arrives standing on it), stash = interior + 1.5 m along
-- x. Per home, `autoDoor = false` keeps the static rings for good; a hand-set
-- `doorId` skips the search (the rings are still derived from that door).
Config.autoDoor = {
    radius = 6.0,
    outside = 1.5,
    inside = 1.2,
    stashInside = 1.2,
    fallback = 3.0,
    retrySec = 60,
}

-- The exit ring is 1.0 m wide (the others 0.6) because in the fallback it
-- stands under the arriving player's feet; open77_interactions measures the
-- prompt distance in 3D from the player to the card anchor 1 m above the ring,
-- so a player standing on it is ~1 m away and promptDistance 3.0 keeps it
-- pressable.
Config.exitRadius = 1.0

-- The real-estate agency: a ring + E prompt + map pin at Kabuki Market, The
-- Crossing (walked), 32 m west of the market centre, with a listings terminal
-- prop 1.1 m off the ring (Open77.props.create on the server, removed on stop;
-- `models` are depot meshes tried in order).
Config.agency = {
    label = "Night City Real Estate",
    description = "Buy or sell a place to crash. Kabuki Market, The Crossing.",
    position = { x = -1218.65, y = 2022.93, z = 7.82 },
    radius = 1.5,
    props = {
        { models = {
              "electronics.monitor.device",
              "electronics.monitor.device",
          },
          position = { x = -1216.05, y = 2022.93, z = 7.82 }, yaw = 90.0 },
    },
}

-- Homes. Fields:
--   id        stable identifier (letters, digits, underscore), also the map/stash key
--             and the rp_config key: kept across the move to the real map so deeds,
--             stashes and overrides survive (the label is what players read)
--   label     what players read
--   district  flavour text for the agency menu
--   zone      optional rp_zones zone name; its label replaces `district` when rp_zones runs
--   price     purchase price in eddies; sold back at Config.sellBackRatio
--   rent      optional per-home rent (defaults to Config.rent)
--   interior  where entering puts you: the flat's floor (AMM point)
--   heading   body yaw applied on arrival (degrees, AMM)
--   entrance  the door ring: the E prompt "Apartment door", and where leaving puts
--             you. Left empty: the auto door fills it (interior + 3 m along x until
--             the front door is discovered)
--   stash     where the "Stash" ring stands (default: interior + 1.5 m along x until the
--             front door is found, then interior + 1.2 m further inside along door -> interior)
--   exit      where the "Front door" (leave) ring stands (default: the interior point itself
--             until the front door is found, then 1.2 m inside the door)
--   doorId    optional open77_doors engine id ("0x..." string). Empty: found by the
--             auto door. When set, the server claims the door and locks it to the
--             owner and the key holders (defaultAccess = false).
--   autoDoor  false = never search for the front door (static entrance)
Config.homes = {
    {
        id = "northside_container",
        label = "Northside Apartment",
        district = "Northside, Watson",
        zone = nil,
        price = 9000,
        interior = { x = -1503.8, y = 2224.9, z = 22.2 },
    },
    {
        id = "badlands_hideout",
        label = "Glen Apartment",
        district = "The Glen, Heywood",
        zone = nil,
        price = 15000,
        interior = { x = -1524.0, y = -992.6, z = 9.1 },
    },
    {
        id = "h10_studio",
        label = "Megabuilding H10 - V's Apartment",
        district = "Little China, Watson",
        zone = "h10",
        price = 25000,
        interior = { x = -1391.9, y = 1271.7, z = 123.1 },
        heading = -99.3,
    },
    {
        id = "kabuki_flat",
        label = "Judy's Apartment",
        district = "Kabuki, Watson",
        zone = nil,
        price = 30000,
        interior = { x = -906.3, y = 1868.7, z = 42.4 },
    },
    {
        id = "japantown_loft",
        label = "Japantown Apartment",
        district = "Japantown, Westbrook",
        zone = nil,
        price = 40000,
        interior = { x = -785.3, y = 992.6, z = 12.0 },
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
    home.entrance = home.entrance or { x = home.interior.x + Config.autoDoor.fallback, y = home.interior.y, z = home.interior.z }
    home.stash = home.stash or { x = home.interior.x + 1.5, y = home.interior.y, z = home.interior.z }
    -- The exit ring waits on the arrival point: `interior - 1.5 m along x` was
    -- inside the flat's wall (measured 2026-09-18, Northside: 3.3-3.6 m from a
    -- player on the arrival point, never pressable).
    home.exit = home.exit or { x = home.interior.x, y = home.interior.y, z = home.interior.z }
    home.doorId = home.doorId or ""
    if home.autoDoor == nil then home.autoDoor = (home.doorId == "") end
end

function Config.home(id)
    for _, home in ipairs(Config.homes) do
        if home.id == id then return home end
    end
    return nil
end
