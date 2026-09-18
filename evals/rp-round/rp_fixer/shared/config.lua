-- rp_fixer configuration. Shared by the server (rules, pay, NPCs) and the client
-- (office position, prompt copy). Nothing here is a secret.
--
-- Every position is on the measured flat band around the freeroam spawn
-- (381.36, -2401.79, 181.99): x 340..460, y -2401..-2355, z 178..182. The points are
-- the rp_zones centres, so a tester walks the same rings they already know. Move them
-- to real Night City places by editing this table only.

Config = {}

-- The eval config lets anyone open the board. Set it to false and the board only
-- answers while a fixer is clocked in (rp_jobs `listOnDuty("fixer")`), or to the
-- on-duty fixer themselves.
Config.openBoardWithoutFixer = true

-- The fixer's office: the `blackmarket` zone centre. The board ring + E prompt sit here;
-- retrieval and extraction gigs end here.
Config.office = { x = 400.0, y = -2390.0, z = 182.0 }

-- How far from the office `/gigs` and the E prompt still open the board (metres, 3D).
-- 0 = anywhere.
Config.boardReach = 15.0

-- The E prompt on an objective is pressable within promptDistance (client side); the
-- server re-checks the player's distance to the point against interactReach.
Config.promptDistance = 3.0
Config.interactReach = 4.5

-- Escort / extraction: the gig succeeds when the NPC stands within this many metres
-- (planar) of the destination.
Config.arrivalDistance = 5.0

-- Gig points, reused from rp_zones (name -> centre).
Config.points = {
    office     = Config.office,
    scrapyard  = { x = 462.0, y = -2352.0, z = 178.0 },
    nomad_camp = { x = 420.0, y = -2378.0, z = 182.0 },
    hospital   = { x = 400.0, y = -2366.0, z = 182.0 },
    ncpd_hq    = { x = 440.0, y = -2366.0, z = 181.0 },
}

-- Reputation tiers, ascending. A template's `minTier` names one of them.
Config.tiers = {
    { name = "street",  min = 0 },
    { name = "known",   min = 3 },
    { name = "trusted", min = 6 },
}

-- Reputation delta per outcome. A disconnect ("dropped") costs nothing.
Config.reputation = {
    success   = 1,
    abandoned = -1,
    timeout   = -1,
    floor     = 0,     -- the score never goes below this
}

-- The fixer's cut of every gig's gross pay (0..1). The player receives the rest in cash.
Config.commissionRate = 0.15

-- The society (rp_bank) that receives the commission: the lower-case job name.
Config.society = "fixer"

-- Board behaviour.
Config.maxOpenGigs = 20            -- the UI kit context menu takes 64 options; keep it readable
Config.autoPublish = true          -- publish one instance of every `auto` template at start
Config.republishDelaySec = 60      -- ...and again this long after an instance ends
Config.warnBeforeDeadlineSec = 60  -- one chat warning when this much time is left

-- Items registered in rp_inventory through `exports.rp_inventory:define`.
Config.items = {
    gig_package   = { label = "Sealed package",  weight = 1.0,  usable = false, illegal = true },
    gig_datashard = { label = "Encrypted shard", weight = 0.05, usable = false, illegal = true },
}

-- Guards on retrieval / extraction gigs.
Config.guards = {
    -- The one Maelstrom gang record the devkit documents as a spawnable ranged hostile
    -- ("hostile_female_ranged_lab" resolves to it). Any Character.* record works here.
    record = "Character.cpz_maelstrom_grunt1_ranged1_lexington_wa",
    count = 2,
    health = 150,
    damagePolicy = 0,          -- numeric: 0 = mortal, they can be killed
    postRadius = 3.0,          -- metres from the gig point where the guards stand
    guardRadius = 8,           -- the leash of Open77.npcs.tasks.guard (2..100)
    engageDistance = 25.0,     -- the guards are ordered to attack the merc inside this distance
    group = "rp_fixer_guards", -- relationship group: the two guards are allies
}

-- Escorted NPCs and extraction targets.
Config.escort = {
    -- Legacy alias "civilian_female_relaxed_01" = Character.Panam: the devkit's documented
    -- non-hostile human with locomotion; natively invulnerable, which matches damagePolicy 2.
    template = "civilian_female_relaxed_01",
    damagePolicy = 2,          -- numeric: 2 = invulnerable
    followDistance = 2.5,
    followSpeed = "run",
}

-- Gig templates. `kind` is delivery | retrieval | escort | extraction.
--   delivery   : pick `item` up at `from` (E), bring it to `to` (E)
--   retrieval  : take `item` at `at` (E, guarded), bring it back to the office (E)
--   escort     : meet `npcName` at `from` (E), walk them to `to` (arrival = NPC within 5 m)
--   extraction : reach `npcName` at `at` (E, guarded), bring them to the office (arrival)
-- `pay` is the gross pay: the player gets pay minus the fixer's cut. `timeLimitSec` starts
-- on accept. `minTier` is a name from Config.tiers. `auto` templates are published by the
-- board itself; the others only through `/fixer publier <template>` or the postGig export.
Config.templates = {
    delivery_meds = {
        kind = "delivery", title = "Meds run",
        description = "A crate of MaxDoc left the hospital without paperwork. Take it to the scrapyard before Trauma Team notices.",
        from = "hospital", to = "scrapyard", item = "gig_package",
        pay = 600, timeLimitSec = 600, minTier = "street", auto = true,
    },
    escort_witness = {
        kind = "escort", title = "Witness walk",
        description = "A nomad saw something at the camp she should not have. Walk her to the hospital, quietly.",
        from = "nomad_camp", to = "hospital", npcName = "Kess",
        pay = 800, timeLimitSec = 720, minTier = "street", auto = true,
    },
    retrieval_shard = {
        kind = "retrieval", title = "Junkyard shard",
        description = "Two Maelstrom goons are sitting on an encrypted shard at the scrapyard. Bring it back here. How you get it is your business.",
        at = "scrapyard", item = "gig_datashard",
        pay = 1000, timeLimitSec = 720, minTier = "street", auto = true,
    },
    extraction_techie = {
        kind = "extraction", title = "Techie extraction",
        description = "A techie is being held at the nomad camp by Maelstrom. Get him out and bring him to the office.",
        at = "nomad_camp", npcName = "Rho the techie",
        pay = 1500, timeLimitSec = 900, minTier = "street", auto = true,
    },
    delivery_hot = {
        kind = "delivery", title = "Hot package",
        description = "Something walked out of the NCPD evidence room. It needs to be at the scrapyard in six minutes, no questions.",
        from = "ncpd_hq", to = "scrapyard", item = "gig_package",
        pay = 1200, timeLimitSec = 360, minTier = "known", auto = true,
    },
    extraction_vip = {
        kind = "extraction", title = "VIP extraction",
        description = "A corpo defector is stashed at the precinct with a Maelstrom escort that was paid twice. Bring her to the office alive.",
        at = "ncpd_hq", npcName = "the defector",
        pay = 3000, timeLimitSec = 900, minTier = "trusted", auto = true,
    },
}

-- Copy used by both sides.
Config.text = {
    boardLabel = "Fixer's board",
    boardDescription = "Gigs, eddies, reputation. Press E.",
    officeBlip = "Fixer's office",
}
