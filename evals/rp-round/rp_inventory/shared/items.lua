-- rp_inventory: item definitions and tunables, loaded on both runtimes.
-- id -> { label, weight (kg), usable, illegal, effect }
--
-- `record` / `visual` are optional TweakDB overrides for the ground drop's item
-- card and 3D entity. The devkit documents Items.money + Items.MoneyShard as the
-- only guaranteed pair, so that is the default for every item; set a record here
-- when you have verified it on your build.

RpInventoryConfig = {
    maxCarryWeight = 40.0,          -- kg a player can carry
    defaultStashCapacity = 100.0,   -- kg when openStash is called without a capacity
    interactDistance = 3.0,         -- metres for give / search / seize / pick up
    dropTtlMs = 30 * 60 * 1000,     -- a dropped item evaporates after 30 minutes
    lootRecord = "Items.money",     -- documented default record for a ground drop
    lootVisual = "Items.MoneyShard",-- documented default 3D entity for a ground drop
    useDurationMs = 3000,           -- progress bar while using a consumable
}

RpInventoryItems = {
    water       = { label = "Bottle of water",     weight = 0.5,  usable = true,  illegal = false,
                    effect = { kind = "drink" } },
    burrito     = { label = "Burrito",             weight = 0.4,  usable = true,  illegal = false,
                    effect = { kind = "food" } },
    nicola      = { label = "NiCola",              weight = 0.4,  usable = true,  illegal = false,
                    effect = { kind = "drink" } },
    chooh2      = { label = "CHOOH2 fuel can",     weight = 5.0,  usable = true,  illegal = false,
                    effect = { kind = "fuel", litres = 20 } },
    bandage     = { label = "Bandage",             weight = 0.2,  usable = true,  illegal = false,
                    effect = { kind = "heal", amount = 25 } },
    maxdoc      = { label = "MaxDoc Mk.1",         weight = 0.3,  usable = true,  illegal = false,
                    effect = { kind = "heal", amount = 60 } },
    bounceback  = { label = "Bounce Back Mk.1",    weight = 0.3,  usable = true,  illegal = false,
                    effect = { kind = "heal", amount = 40, stamina = true } },
    phone       = { label = "Holophone",           weight = 0.3,  usable = false, illegal = false },
    radio       = { label = "Radio",               weight = 0.8,  usable = false, illegal = false },
    lockpick    = { label = "Lockpick",            weight = 0.1,  usable = false, illegal = false },
    scrap       = { label = "Scrap",               weight = 1.0,  usable = false, illegal = false },
    component   = { label = "Component",           weight = 0.5,  usable = false, illegal = false },
    chip        = { label = "Data chip",           weight = 0.05, usable = false, illegal = false },
    cigarettes  = { label = "Pack of cigarettes",  weight = 0.1,  usable = true,  illegal = false,
                    effect = { kind = "smoke" } },
    synthcoke   = { label = "Synthcoke",           weight = 0.1,  usable = true,  illegal = true,
                    effect = { kind = "stamina" } },
    -- Illegal unless the holder has the permit job (rp_jobs `medecin` stands in for a ripperdoc licence).
    implant_box = { label = "Implant box",         weight = 2.0,  usable = false, illegal = true,
                    permit = "medecin" },
    crate       = { label = "Cargo crate",         weight = 25.0, usable = false, illegal = false },
}
