-- rp_gangs configuration. Shared by both runtimes: keep it free of secrets and of
-- anything the client must not know. Every position is in world metres.
RpGangsConfig = {}
local Config = RpGangsConfig

-- The seven gangs. `id` is what the commands, the SQL rows and the exports use;
-- `label` is what players read; `color` is the nameplate / chat colour; `home` is
-- the territory the gang is associated with (informative, and the fallback zone
-- for an influence loss when the member's last territory is unknown).
Config.gangs = {
    maelstrom   = { label = "Maelstrom",   color = "#D7263D", rgb = { 215, 38, 61 },   home = "scrapyard" },
    tygerclaws  = { label = "Tyger Claws", color = "#FF3CAC", rgb = { 255, 60, 172 },  home = "afterlife" },
    valentinos  = { label = "Valentinos",  color = "#F2C14E", rgb = { 242, 193, 78 },  home = "blackmarket" },
    sixthstreet = { label = "6th Street",  color = "#2E86DE", rgb = { 46, 134, 222 },  home = "nomad_camp" },
    animals     = { label = "Animals",     color = "#8E44AD", rgb = { 142, 68, 173 },  home = "afterlife" },
    voodooboys  = { label = "Voodoo Boys", color = "#27AE60", rgb = { 39, 174, 96 },   home = "blackmarket" },
    scavs       = { label = "Scavs",       color = "#7F8C8D", rgb = { 127, 140, 141 }, home = "scrapyard" },
}

-- Display order of the gangs in lists.
Config.gangOrder = { "maelstrom", "tygerclaws", "valentinos", "sixthstreet", "animals", "voodooboys", "scavs" }

-- Ranks 0..2.
Config.ranks = { [0] = "member", [1] = "lieutenant", [2] = "boss" }

-- Territories = rp_zones zone names. `label` mirrors rp_zones; `position` is the zone
-- centre (used for NCPD alerts); `buyer` is where the street buyer NPC stands
-- (inside the zone, a few metres off the centre so it does not overlap the other
-- resources' NPCs / POIs). If a buyer lands in the ground, stand on the spot, /pos,
-- and paste the height.
Config.territories = {
    { name = "blackmarket", label = "Black Market",   position = { x = 400.0, y = -2390.0, z = 182.0 },
      buyer = { x = 397.0, y = -2393.0, z = 182.0, yaw = 45.0 } },
    { name = "afterlife",   label = "Afterlife",      position = { x = 360.0, y = -2390.0, z = 182.0 },
      buyer = { x = 358.0, y = -2392.0, z = 182.0, yaw = 45.0 } },
    { name = "nomad_camp",  label = "Nomad camp",     position = { x = 420.0, y = -2378.0, z = 182.0 },
      buyer = { x = 418.0, y = -2380.0, z = 182.0, yaw = 45.0 } },
    { name = "scrapyard",   label = "Scrapyard",      position = { x = 462.0, y = -2352.0, z = 178.0 },
      buyer = { x = 460.0, y = -2355.0, z = 178.0, yaw = 45.0 } },
}

-- Founding: with `openFounding` the first member of a gang founds it and becomes its
-- boss (`/gang creer`), no admin needed. Set it to false on a server where an admin
-- hands out the boss seats with /setgang.
Config.openFounding = true

-- When a member takes a job (rp_jobs:changed with a job name) they are cut loose from
-- the gang: membership requires being jobless, on both sides of the door.
Config.dropOnJob = true

-- Nameplate tag `[GANG] Name` over a member's body, drawn by every other client.
Config.showTag = true
Config.tagMaxDistance = 40.0

-- Recruiting / firing: the target must stand within this many metres.
Config.recruitReach = 5.0

-- Influence points.
Config.dealInfluence = 1       -- per drug pack sold in the zone (/gang vendre, the buyer prompt, rp_crime)
Config.gigInfluence = 2        -- per rp_fixer gig completed by a member
Config.arrestInfluence = -5    -- per rp_ncpd:arrest of a member (never below 0)

-- Tribute: every online member of the gang holding a zone is paid this much per held
-- zone, every interval.
Config.tributePerZone = 50
Config.tributeIntervalMs = 600000

-- Street deals: the buyer NPC per territory.
Config.buyer = {
    record = "Character.cpz_maelstrom_grunt1_ranged1_lexington_wa", -- proven on 2.31; passive + silent below
    damagePolicy = 2,          -- numeric: 2 = invulnerable
    reach = 4.0,               -- server-measured distance to the buyer for a deal
    promptDistance = 2.5,      -- E prompt activation radius (open77_interactions)
    markerDistance = 15.0,     -- how far the marker is drawn
}
Config.dealItem = "drug_pack"
Config.dealPrice = 80          -- cash per pack
Config.dealCooldownMs = 60000  -- per seller

-- Items this resource declares in rp_inventory (rp_inventory `define` shape).
Config.items = {
    drug_pack = { label = "Drug pack", weight = 0.2, usable = false, illegal = true },
}

-- Robbery of a held player (cuffed by the RP kit, or hands up).
Config.robShare = 0.30         -- share of the victim's cash taken
Config.robReach = 3.0
Config.robCooldownMs = 120000  -- per victim: the same choom is not robbed twice in two minutes

-- War.
Config.warMinutes = 5          -- eval; 20 on production
Config.warTickMs = 30000       -- every tick the gang with more members inside the zone scores 1
Config.warInfluence = 10       -- what the winner gets
Config.warCooldownMs = 600000  -- per zone, after a war ends

-- Racket: a chat threat plus an NCPD alert (see README: the society-payment version is
-- deliberately not implemented).
Config.racketAmount = 100
Config.racketReach = 5.0
Config.racketCooldownMs = 60000

-- Where the wars, deals and robberies are reported: rp_ncpd:alert kinds.
Config.alertKinds = { robbery = "robbery", war = "gang_war", racket = "racket" }

-- Chat author and colour of this resource's lines.
Config.chatAuthor = "GANG"
Config.chatColor = { 255, 128, 48 }
