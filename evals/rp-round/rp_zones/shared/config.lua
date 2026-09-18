-- rp_zones: shared configuration (loaded by both runtimes).
-- Every position is world space, metres. The owner moves zones by editing this file only.

Config = {}

-- Server detection tick, in milliseconds. The server is the source of truth for zoneOf.
Config.tickMs = 500

-- Metres of tolerance added to the EXIT test only (hysteresis): a player standing exactly on
-- the boundary does not flap between "entered" and "left" every tick. 0.05..10 is sensible.
Config.hysteresis = 1.0

-- Safe zones (kind "safe"): server-side damage suppression through Open77.combat.onDamage.
Config.safe = {
    blockDamage = true,          -- nobody standing in a safe zone can be damaged
    blockDamageFromInside = true -- and nobody standing in a safe zone can damage anyone outside
}

-- Notification look (open77_notifications definition fields).
Config.notify = {
    position = "top_right",
    durationMs = 5000,
    leaveDurationMs = 3500,
}

-- Client presentation.
Config.ringMaxRadius = 25.0   -- zones with a radius <= this get a ground ring (open77_worldui, no label)
Config.ringMaxDistance = 120.0
Config.blipRange = 0          -- 0 = the pin is always on the map; N = only within N metres

-- One entry per zone kind: flavour line (English, cyberpunk tone), toast type/icon,
-- vanilla blip sprite (Open77.blips sprite alias or exact variant name) and worldui ring style.
-- `chat` is an extra chat line sent on entry (only badlands uses it by contract).
Config.kinds = {
    safe = {
        title = "Safe zone",
        flavour = "No heat in here, choom. Iron stays cold and so do the grudges.",
        leave = "You're fair game again, choom. Watch your six.",
        type = "success", icon = "SAFE", sprite = "fast_travel", style = "spawn",
    },
    ncpd = {
        title = "NCPD",
        flavour = "NCPD precinct. Badges everywhere - keep your record clean and your hands visible.",
        type = "info", icon = "NCPD", sprite = "Zzz06_NCPDGigVariant", style = "objective",
    },
    hospital = {
        title = "Trauma Team",
        flavour = "Trauma Team coverage. Platinum members first, everyone else waits.",
        type = "info", icon = "TT", sprite = "meds", style = "objective",
    },
    badlands = {
        title = "Badlands",
        flavour = "You're past the city limits. Nobody's coming to save you out here.",
        chat = "Out of NCPD coverage",
        type = "warning", icon = "!", sprite = "OutpostVariant", style = "danger",
    },
    camp = {
        title = "Nomad camp",
        flavour = "Nomad camp. Clan rules apply - respect the fire and the family.",
        type = "info", icon = "CAMP", sprite = "LifepathNomadVariant", style = "interaction",
    },
    scrapyard = {
        title = "Scrapyard",
        flavour = "Scrapyard. Everything here was somebody's ride once. Mind the crusher.",
        type = "info", icon = "SCRAP", sprite = "junk", style = "danger",
    },
    blackmarket = {
        title = "Black market",
        flavour = "Black market. No receipts, no questions, no refunds. Eddies talk.",
        type = "warning", icon = "E$", sprite = "Zzz14_ServicePointBlackMarketVariant", style = "danger",
    },
    bar = {
        title = "Bar",
        flavour = "The bar's open. Keep your iron holstered and your tab paid.",
        type = "info", icon = "BAR", sprite = "bar", style = "interaction",
    },
    garage = {
        title = "Garage",
        flavour = "Garage. Chooh2 fumes, spare parts and a mecano who's seen worse.",
        type = "info", icon = "SHOP", sprite = "tech", style = "interaction",
    },
}

-- Zones. Fields:
--   name (unique, ^[a-z0-9_]+$), label, kind (one of Config.kinds)
--   shape = "circle"  : centre { x, y, z }, radius (m), optional maxHeight (m either side of z, default 6)
--   shape = "sphere"  : centre, radius (true 3-D ball)
--   shape = "box"     : centre, size { x, y, z } (FULL extents), optional rotation (degrees)
--   shape = "polygon" : points { {x, y}, ... } (3..512, concave allowed), optional minZ / maxZ
--   optional announce : custom entry text (replaces the kind flavour line)
--   optional flags    : free table handed back by zoneOf (e.g. { noWeapons = true })
--   optional blip = false / ring = false to hide the map pin / ground ring for that zone
--
-- Layout (measured with Open77.world.groundZ on 2026-09-18): the freeroam spawn is
-- 381.36, -2401.79, 181.99 on a small plateau. North of y -2361 and south of y -2415 the
-- ground drops 20-30 m (a teleport to z 182 there is a fall), west of x 335 it drops too, and
-- east of x 400 at y -2401 there is no ground. The flat band runs from the plaza north-east
-- along the road (x 380-460, y -2355..-2390, z 178-182). Every small zone below sits on that
-- band, non-overlapping, reachable on foot:
--   afterlife 360,-2390   mecano_shop 341,-2401   blackmarket 400,-2390
--   hospital 400,-2366    nomad_camp 420,-2378    ncpd_hq 440,-2366   scrapyard 462,-2352
-- These are placeholders; the owner moves the city ones to real Night City places. /goto
-- candidates: City west -667.14, -382.61, 9.16   Vehicle dealership -1442.2, 127.4, 18.0
--   King Stoop forecourt -410.22, 722.73, 115.0   Lower Watson junction -644.91, 1019.37, 36.56
Config.zones = {
    {
        name = "spawn_plaza", label = "Badlands Plaza", kind = "safe",
        shape = "circle", centre = { x = 381.36, y = -2401.79, z = 181.99 }, radius = 45.0, maxHeight = 15.0,
        flags = { noWeapons = true },
    },
    {
        name = "ncpd_hq", label = "NCPD Badlands Outpost", kind = "ncpd",
        shape = "circle", centre = { x = 440.00, y = -2366.00, z = 181.00 }, radius = 12.0, maxHeight = 15.0,
    },
    {
        name = "hospital", label = "Trauma Team Field Station", kind = "hospital",
        shape = "circle", centre = { x = 400.00, y = -2366.00, z = 182.00 }, radius = 12.0, maxHeight = 15.0,
    },
    {
        name = "afterlife", label = "The Afterlife", kind = "bar",
        shape = "circle", centre = { x = 360.00, y = -2390.00, z = 182.00 }, radius = 10.0, maxHeight = 15.0,
    },
    {
        name = "mecano_shop", label = "Mecano Shop", kind = "garage",
        shape = "circle", centre = { x = 341.00, y = -2401.00, z = 180.30 }, radius = 10.0, maxHeight = 15.0,
    },
    {
        name = "scrapyard", label = "Scrapyard", kind = "scrapyard",
        shape = "circle", centre = { x = 462.00, y = -2352.00, z = 178.00 }, radius = 12.0, maxHeight = 15.0,
    },
    {
        name = "blackmarket", label = "Black Market", kind = "blackmarket",
        shape = "circle", centre = { x = 400.00, y = -2390.00, z = 182.00 }, radius = 10.0, maxHeight = 15.0,
    },
    {
        name = "nomad_camp", label = "Nomad Camp", kind = "camp",
        shape = "circle", centre = { x = 420.00, y = -2378.00, z = 182.00 }, radius = 9.0, maxHeight = 15.0,
    },
    {
        -- Large circle covering the whole spawn area. Tall height band so hills do not drop you out.
        name = "badlands", label = "Badlands", kind = "badlands",
        shape = "circle", centre = { x = 381.36, y = -2401.79, z = 181.99 }, radius = 900.0, maxHeight = 600.0,
        ring = false,
    },
    -- Polygon example (disabled): a concave turf with a height range.
    -- {
    --     name = "turf_example", label = "Example Turf", kind = "camp",
    --     shape = "polygon", minZ = 170.0, maxZ = 200.0,
    --     points = { { x = 300, y = -2300 }, { x = 340, y = -2300 }, { x = 340, y = -2320 }, { x = 320, y = -2320 },
    --                { x = 320, y = -2340 }, { x = 300, y = -2340 } },
    -- },
}

-- Shared helpers (both runtimes).
RpZonesShared = {}

-- Translates one config entry into the definition Open77.zones.* understands.
-- Returns the definition, or nil, reason.
function RpZonesShared.definition(zone)
    if type(zone) ~= "table" then return nil, "invalid_zone" end
    local shape = zone.shape or "circle"
    if shape == "circle" then
        return { shape = "cylinder", position = zone.centre, radius = zone.radius, maxHeight = zone.maxHeight }
    elseif shape == "sphere" then
        return { shape = "sphere", position = zone.centre, radius = zone.radius }
    elseif shape == "box" then
        return { shape = "box", position = zone.centre, size = zone.size, rotation = zone.rotation or 0 }
    elseif shape == "polygon" or shape == "poly" then
        return { shape = "poly", points = zone.points, minZ = zone.minZ, maxZ = zone.maxZ }
    end
    return nil, "unknown_shape"
end

-- The kind entry of a zone, with the zone's own overrides (announce, sprite, style) applied.
function RpZonesShared.kindOf(zone)
    local kind = Config.kinds[zone.kind] or {}
    return {
        title = kind.title or zone.kind or "Zone",
        flavour = zone.announce or kind.flavour or "",
        leave = kind.leave,
        chat = kind.chat,
        type = kind.type or "info",
        icon = kind.icon,
        sprite = zone.sprite or kind.sprite or "objective",
        style = zone.style or kind.style or "objective",
    }
end
