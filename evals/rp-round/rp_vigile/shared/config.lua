-- rp_vigile: private security contracts for a Night City RP server.
-- Shared configuration (loaded on both runtimes). Every number the owner may
-- want to tune lives here; the server is the only side that decides anything.

VigileConfig = {
    -- Money ------------------------------------------------------------------
    -- What a guarded minute costs the client (a society, the platform or a
    -- citizen's bank account). The guard gets (1 - societyShare) of it in cash,
    -- the `vigile` society keeps the rest.
    ratePerMinute = 20,
    societyShare = 0.20,          -- 0.0 .. 0.9
    societyName = "vigile",       -- rp_bank society that takes the cut / holds the escrow

    -- Contracts --------------------------------------------------------------
    minMinutes = 1,
    maxMinutes = 240,
    bodyguardRange = 15.0,        -- metres: a bodyguard earns only this close to the client
    minuteCoverage = 0.75,        -- share of the samples of one minute that must be covered for it to be paid
    tickMs = 5000,                -- sampling interval (12 samples per minute)
    unpaidWarnAfter = 2,          -- consecutive unpaid minutes before the guard is told why
    offerTimeoutSec = 180,        -- a posted bodyguard offer nobody took expires (and is refunded)
    zoneOfferTimeoutSec = 1800,   -- a zone contract posted by a business/fixer leaves the board after this
    storeFallbackAfterSec = 15,   -- database still silent this long after start: fall back to kvp

    -- Rights inside a guarded zone ------------------------------------------
    escortRange = 3.0,            -- metres: the same reach as open77_rp_basics
    escortHoldMs = 120000,        -- a security escort never lasts longer than this
    expelDistance = 20.0,         -- metres outside the zone edge
    journalSize = 50,             -- camera log entries kept per guarded zone

    -- Which job pays for a zone. A zone missing here is a "corpo" contract: the
    -- platform pays (rp_economy:add only). Society names are rp_jobs job names.
    zoneSociety = {
        afterlife   = "barman",
        mecano_shop = "mecano",
        nomad_camp  = "nomade",
        scrapyard   = "ferrailleur",
        hospital    = "trauma",
        ncpd_hq     = "ncpd",
        -- blackmarket, spawn_plaza, badlands: corpo
    },

    -- Zone geometry used only to compute the expulsion point (centre + radius,
    -- copied from rp_zones/shared/config.lua). Keep it in sync when zones move;
    -- a zone missing here is still guardable, /expulser then pushes the player
    -- 20 m straight away from the guard instead of past the ring.
    zoneGeometry = {
        spawn_plaza = { x = 381.36, y = -2401.79, z = 182.0, radius = 45 },
        afterlife   = { x = 360.0,  y = -2390.0,  z = 182.0, radius = 10 },
        mecano_shop = { x = 341.0,  y = -2401.0,  z = 180.3, radius = 10 },
        blackmarket = { x = 400.0,  y = -2390.0,  z = 182.0, radius = 10 },
        hospital    = { x = 400.0,  y = -2366.0,  z = 182.0, radius = 12 },
        nomad_camp  = { x = 420.0,  y = -2378.0,  z = 182.0, radius = 9 },
        ncpd_hq     = { x = 440.0,  y = -2366.0,  z = 181.0, radius = 12 },
        scrapyard   = { x = 462.0,  y = -2352.0,  z = 178.0, radius = 12 },
    },

    -- The standing zone contracts on the board (always available while nobody
    -- guards that zone). `minutes` is the length of one shift.
    templates = {
        { zone = "afterlife",   minutes = 30 },
        { zone = "blackmarket", minutes = 30 },
        { zone = "mecano_shop", minutes = 20 },
        { zone = "nomad_camp",  minutes = 20 },
        { zone = "scrapyard",   minutes = 20 },
        { zone = "hospital",    minutes = 20 },
    },

    -- Where a tester stands for the README walkthrough (freeroam spawn and the
    -- afterlife ring, 24 m north-west of it).
    testSpots = {
        spawn     = { x = 381.36, y = -2401.79, z = 181.99 },
        afterlife = { x = 360.0,  y = -2390.0,  z = 182.0 },
    },

    -- Chat presentation
    chatAuthor = "SECURITY",
    chatColor = { 176, 196, 222 },    -- steel
}
