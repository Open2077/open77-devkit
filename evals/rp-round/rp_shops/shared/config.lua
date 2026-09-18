-- rp_shops v2: shops placed in the world, each with a talking vendor.
-- Shared by the server (authority: prices, stock, payment, delivery) and the
-- client (presentation only: one ring + E prompt per vendor).
--
-- Every position sits on the measured flat band around the freeroam spawn
-- (381.36, -2401.79, 181.99): x 340..460, y -2355..-2401, z = 182. Move a shop by
-- editing its `position`; `yaw` is the vendor's facing (0 = +y, counter-clockwise),
-- roughly towards the spawn. z is the spawn's own height: if a vendor stands in
-- the ground, `/pos` on the spot and paste the real height.

RpShopsConfig = {
    -- Reach of a vendor, in metres (planar). The E prompt is pressable within
    -- `promptDistance`; the server re-checks every request against `reach`, a
    -- little wider to tolerate a lagging position snapshot.
    reach = 3.5,
    promptDistance = 3.0,
    -- Reject a player position snapshot older than this (ms).
    positionMaxAgeMs = 5000,

    -- Society shops: share of every sale credited to the society (rp_bank).
    societyShare = 0.70,
    -- Restock cost per unit, as a share of the retail price, paid from the society.
    restockCostRatio = 0.5,

    -- Gun licence: one-off fee, paid cash then account, credited to the NCPD society.
    gunLicenceFee = 500,
    gunLicenceSociety = "ncpd",
    -- Jobs whose members buy guns without a licence (aliases accepted by rp_jobs).
    gunLicenceExemptJobs = { "ncpd" },

    -- Clothes shop: flat styling fee charged before the wardrobe opens.
    stylingFee = 200,

    -- Black market opening hours, server-world time (open77_weather), [open, close).
    -- 22 -> 6 means 22:00 to 05:59. Set both to 0 to never close.
    blackmarket = { openHour = 22, closeHour = 6 },

    -- Robbery (rp_crime calls exports.rp_shops:rob): loot range, cooldown per shop,
    -- how close the robber must stand, how long the vendor keeps their hands up.
    robLoot = { min = 200, max = 600 },
    robCooldownSeconds = 20 * 60,
    robDistance = 5.0,
    robHandsUpMs = 20000,
    -- A society shop loses the loot from its society account (as far as it goes).
    robTakesFromSociety = true,

    -- Maximum units per purchase (quantity dialog).
    maxCountPerPurchase = 20,

    -- Weapon delivery: refund if the client never confirms (ms).
    weaponFallbackMs = 15000,

    -- Vendor NPC defaults. `record` is a `Character.*` TweakDB id that must exist
    -- on every client; Character.Judy is the record the platform's own docs use
    -- for a shopkeeper. Per-shop `vendor.record` overrides it.
    vendor = {
        record = "Character.Judy",
        streamingRadius = 120,
        greeting = "greeting",     -- voContext name for Open77.npcs.speak
        robbed = "fear_beg",
    },
}

-- Shops. Fields:
--   id        ^[a-z0-9_]+$, unique; also the world POI id and the /acheter target
--   label     shown on the prompt, the menu title and /boutiques
--   kind      "items" (rp_inventory goods) | "weapons" | "clothes" | "blackmarket"
--   position  vendor position (x, y, z); yaw = facing
--   society   optional lower-case job name: 70 % of sales go to that society and
--             the shop keeps a finite stock in rp_shops_stock
--   catalogue list of { id, label, price[, slot][, record][, restockTo] }
--             items: `id` is an rp_inventory item id; weapons: `record` is the
--             TweakDB weapon and `slot` 1..3; clothes: a single service line.
--   restockTo default stock level per item for a society shop (restock fills to it)
--   welcome   the vendor's line in chat when the shop opens
--   closedLine (blackmarket) the line by day
RpShopsConfig.shops = {
    {
        id = "supermarket",
        label = "Badlands Market",
        kind = "items",
        position = { x = 370.0, y = -2385.0, z = 181.99 },
        yaw = 214.0,
        vendor = { name = "Rosa" },
        welcome = "Rosa: Water, burritos, NiCola. Real food's extra, choom.",
        catalogue = {
            { id = "water",      label = "Bottle of water",    price = 10 },
            { id = "burrito",    label = "Burrito",            price = 25 },
            { id = "nicola",     label = "NiCola",             price = 15 },
            { id = "chooh2",     label = "CHOOH2 fuel can",    price = 60 },
            { id = "cigarettes", label = "Pack of cigarettes", price = 20 },
        },
    },
    {
        id = "pharmacy",
        label = "Med-Point Pharmacy",
        kind = "items",
        position = { x = 396.0, y = -2372.0, z = 181.99 },
        yaw = 154.0,
        vendor = { name = "Dr. Osei" },
        welcome = "Dr. Osei: No Trauma Team card? Then you pay retail.",
        -- Player-run: Trauma Team owns it. 70 % of every sale lands on the
        -- `trauma` society, the shelves are finite (rp_shops_stock, opening
        -- stock = restockTo, free once) and the Trauma boss restocks them with
        -- /boutiques restock pharmacy, paid from the society.
        society = "trauma",
        restockTo = 10,
        catalogue = {
            { id = "bandage",    label = "Bandage",          price = 40 },
            { id = "maxdoc",     label = "MaxDoc Mk.1",      price = 120 },
            { id = "bounceback", label = "Bounce Back Mk.1", price = 90 },
        },
    },
    {
        id = "gunshop",
        label = "2nd Amendment Outpost",
        kind = "weapons",
        position = { x = 410.0, y = -2386.0, z = 181.99 },
        yaw = 119.0,
        vendor = { name = "Wilson" },
        welcome = "Wilson: Licence first, iron second. NCPD reads my ledger.",
        catalogue = {
            { id = "pistol", label = "M-10AF Lexington (pistol)", price = 400,  record = "Items.Preset_Lexington_Default",  slot = 1 },
            { id = "rifle",  label = "D5 Copperhead (rifle)",     price = 1200, record = "Items.Preset_Copperhead_Default", slot = 2 },
            { id = "katana", label = "Katana",                    price = 900,  record = "Items.Preset_Katana_Default",     slot = 3 },
        },
    },
    {
        id = "clothes",
        label = "Jinguji Threads",
        kind = "clothes",
        position = { x = 352.0, y = -2398.0, z = 181.99 },
        yaw = 263.0,
        vendor = { name = "Kimiko" },
        welcome = "Kimiko: A styling session, then the racks are yours.",
        catalogue = {
            { id = "styling", label = "Styling session (opens the wardrobe)", price = 200 },
        },
    },
    {
        id = "blackmarket",
        label = "Back-alley Dealer",
        kind = "blackmarket",
        position = { x = 402.0, y = -2393.0, z = 181.99 },
        yaw = 113.0,
        vendor = { name = "Dex" },
        welcome = "Dex: Keep your voice down. Eddies first, questions never.",
        closedLine = "Dex: Not in daylight, choom. Come back after 22:00, when the NCPD drones go blind.",
        zone = "blackmarket",
        catalogue = {
            { id = "synthcoke", label = "Synthcoke",        price = 150 },
            { id = "lockpick",  label = "Lockpick",         price = 80 },
            { id = "qh_ping",   label = "Ping (quickhack)", price = 120 },
        },
    },
}
