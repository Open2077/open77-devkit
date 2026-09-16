-- eval_arena: values both runtimes read. Keep this data only: no natives.
Config = {
    mainBucket = 0,          -- where every participant is returned to
    arenaBucket = 4300,      -- clear of open77_deathmatch's 4100 / 4200-4231 / 4240-4287

    minPlayers = 2,          -- the countdown starts when this many have landed
    maxPlayers = 8,          -- one ring of spawn marks; raise it only after surveying more
    countdownSeconds = 15,   -- from minPlayers reached to live
    roundSeconds = 180,      -- hard cap; two or more alive at expiry is a draw
    spawnProtectionSeconds = 5,
    tickMs = 1000,

    -- PROVISIONAL geometry. The centre is the point the "Moving a player" guide measured
    -- a settled teleport on; the ring around it is computed, not surveyed. Walk the deck
    -- and capture real marks with /arena.mark, then paste them into `spawns` below:
    -- a non-empty `spawns` replaces the ring.
    arenaCenter = { x = 1669.75, y = -739.12, z = 49.86 },
    spawnRadius = 6.0,
    spawnCount = 8,
    spawns = {
        -- { x = 0.0, y = 0.0, z = 0.0, heading = 0.0 },
    },

    -- Fixed kit, identical for everyone. Records are exact TweakDB names from the
    -- weapons catalogue. Ammo is applied once the assignment is confirmed, and only
    -- on the drawn slot: setAmmo answers weapon_not_drawn for a holstered weapon.
    loadout = {
        { record = "Items.Preset_Copperhead_Default", slot = 1, active = true,
          ammo = { reserve = 150, activate = true } },
        { record = "Items.Preset_Lexington_Default", slot = 2 },
        { record = "Items.Preset_Katana_Default", slot = 3 },
    },
}
