-- rp_ncpd configuration. Shared by the server and the client (both read Config.*).
-- Every world position lives here so the owner can move the precinct without touching code.
Config = {
    -- The rp_zones zone the precinct lives in (informative: the cell and entrance below are
    -- absolute positions inside it, the server never asks rp_zones where to teleport).
    zone = "ncpd_hq",

    -- Holding cell, inside `ncpd_hq` (rp_zones centre 440, -2366, 181, radius 12).
    -- If a prisoner lands in the ground, stand on the spot, /pos, and paste the height.
    cell = { x = 436.0, y = -2362.0, z = 181.5, heading = 180.0, radius = 6.0 },

    -- Where a released prisoner is put, still inside the zone (10 m from the centre).
    entrance = { x = 430.0, y = -2369.0, z = 182.0, heading = 90.0 },

    -- Officer-to-suspect distance for cuff / search / seize / fine / jail (metres).
    -- open77_rp_basics applies its own 3 m rule on top for cuff and escort.
    actionDistance = 3.0,
    -- Camera-ray distance the ALT+click actions accept (metres).
    menuDistance = 3.5,

    vehicle = {
        range = 5.0,        -- the officer must be within this of a server vehicle (or seated in it)
        lockExit = true,    -- a seated suspect cannot open the door until taken out
        preferRear = true,  -- back seats first, like a real cruiser
    },

    prison = {
        minMinutes = 1,
        maxMinutes = 120,
        notifyEverySeconds = 60,    -- "x minutes left" toast cadence
        leashCheckMs = 5000,        -- how often a prisoner's distance to the cell is checked
        persistEverySeconds = 60,   -- remaining time written to SQL this often (and on disconnect)
    },

    fine = {
        min = 1,
        max = 100000,
        inviteTimeoutMs = 30000,    -- the citizen has this long to /interaction accept
        autoWarrantLevel = 1,       -- warrant level for a declined or unpaid fine
    },

    warrant = {
        -- Mirror the warrant level into the native NCPD heat of the wanted player's own game
        -- (Open77.players.setWanted). Off by default: native police are local AI that shoot
        -- the player on their own client, which an RP server with real officers rarely wants.
        nativeHeat = false,
    },

    alert = {
        blipMs = 60000,             -- how long the temporary map pin of an alert lives
        sprite = "danger",          -- Open77.blips alias
    },

    voice = {
        enabled = true,
        channelName = "NCPD dispatch",
        effect = { highPassHz = 220.0, lowPassHz = 4800.0, distortion = 0.08, radioNoise = 0.04, spatialBlend = 0.0 },
    },

    -- Hand the RP kit's rights (rp.cuff, rp.escort, rp.search) to an officer while on duty and
    -- take them back off duty, through Open77.acl.grant / revoke. Needs the scoped manifest
    -- permission "acl.grant:rp.*" (see open77.lua), which the devkit validator rejects as of
    -- 0.1.x although the ACL guide documents it - so it ships OFF: the operator grants rp.cuff,
    -- rp.escort and rp.search to the police accounts in acl.jsonc once (README, "Setup").
    grantKitRights = false,
    kitRights = { "rp.cuff", "rp.escort", "rp.search" },

    record = { maxLines = 20 },

    colors = {
        ncpd = { 64, 140, 255 },
        radio = { 90, 180, 255 },
        alert = { 255, 120, 0 },
        warn = { 255, 80, 80 },
    },
}
