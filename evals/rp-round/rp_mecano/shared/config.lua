-- rp_mecano configuration. Shared with the client (nothing secret in here).
-- Every world position lives in this file so the owner can move it.
Config = {
    -- rp_jobs job name and rp_bank society name of the garage.
    job = "mecano",
    society = "mecano",

    -- The freeroam spawn of the eval server: everything a tester needs is within 80 m.
    spawn = { x = 381.36, y = -2401.79, z = 181.99 },

    -- /reparer
    repair = {
        reach = 4.0,            -- metres from the mechanic to the vehicle (or seated in it)
        durationMs = 15000,     -- progress bar length
        components = 2,         -- rp_inventory `component` units consumed
        requireToolkit = true,  -- a `toolkit` must be in the pockets (not consumed)
        scope = "full",         -- Open77.vehicles.repair scope
    },

    -- /remorquer
    tow = {
        reach = 8.0,            -- metres from the mechanic's truck to the vehicle to hook
        tickMs = 2000,          -- the towed vehicle is moved every tick
        distance = 6.0,         -- metres behind the truck
        minMove = 0.3,          -- skip the tick when the truck moved less than this
        -- Forward vector from the yaw: x = yawSign * sin(yaw), y = cos(yaw). Yaw 0 faces +y
        -- on this engine; the rotation sign is calibrated at runtime against the truck's
        -- velocity, this is only the starting guess.
        yawSign = -1,
    },

    -- /peindre
    paint = {
        reach = 6.0,
        price = 250,            -- eddies billed to the driver through the invoice flow
        colours = {
            black = "#0B0B0D", white = "#F2F2F2", grey = "#7A7F86", silver = "#C0C6CC",
            chrome = "#D9DDE2", red = "#C8102E", crimson = "#7D0A1E", orange = "#FF6A00",
            yellow = "#F5D000", gold = "#C9A227", green = "#1F7A3A", lime = "#7CFC00",
            teal = "#00A99D", cyan = "#00D8FF", blue = "#1F5FBF", navy = "#0F2A5A",
            purple = "#6A0DAD", pink = "#FF4FA3", magenta = "#E0119D", brown = "#5A3A1E",
            sand = "#D2B48C", arasaka = "#A00000", militech = "#2F4F2F", samurai = "#FF2B2B",
        },
    },

    -- /facture and the `bill` export
    bill = {
        reach = 10.0,           -- metres between mechanic and customer for a slash-command bill
        timeoutMs = 60000,      -- the customer has this long to answer
        max = 50000,            -- eddies, per invoice
        mechanicShare = 0.7,    -- 70 % to the mechanic, the rest to the society
    },

    -- /fourriere
    impound = {
        zone = "mecano_shop",   -- rp_zones name; the owner moves the zone in rp_zones/shared/config.lua
        reach = 8.0,            -- metres to the vehicle to impound
        fee = 100,              -- eddies credited to the society per impound
        -- Used only when rp_zones is not running: the shipped mecano_shop circle.
        fallbackCenter = { x = 341.0, y = -2401.0, z = 180.3 },
        fallbackRadius = 10.0,
        -- Config.impoundAnywhereForTesting: /fourriere also works within `testingReach`
        -- metres of one of these spots (the spawn plaza and the employment agency).
        testingReach = 6.0,
        testingSpots = {
            { label = "spawn plaza", x = 381.36, y = -2401.79, z = 181.99 },
            { label = "employment agency", x = 396.0, y = -2388.0, z = 181.99 },
        },
    },
    impoundAnywhereForTesting = false,

    -- /plein
    fuel = {
        reach = 4.0,
        litresPerCan = false,   -- false = fill the tank; a number = litres added per CHOOH2 can
    },
}
