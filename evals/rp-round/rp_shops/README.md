# rp_shops v2 — shops in the world

Five shops around the freeroam spawn, each with a **vendor NPC** standing at the counter, a
ring + map pin + **E** prompt on them, a UI-kit catalogue, a quantity dialog, and a payment
taken **in cash first, then from the bank account**. Goods land in the pockets
(`rp_inventory`), guns come through the platform relay (`open77_weapons`) behind an **NCPD gun
licence**, the clothes shop charges a styling fee and opens the platform **wardrobe**, and the
**black market** only trades at night (server-world time). A shop can be **player-run**
(`society = "<job>"`): 70 % of its sales go to that society and its shelves are finite. A
`rob()` export lets `rp_crime` hold a vendor up.

Replaces `rp_shop`: `/shop`, `/buy` and `/sell` are gone; the commands are `/boutiques` and
`/acheter`. Build target **2.31.13+op77.76**. Server-authoritative: the client only draws the
prompts and forwards a press; every price, hour, licence, stock count and payment is decided on
the server, which re-checks the distance after every dialog.

## The shops (`shared/config.lua`)

All on the flat band around the spawn `381.36, -2401.79, 181.99`; `z = 181.99` is the spawn's
height — if a vendor stands in the ground, `/pos` on the spot and paste the real height.

| id | Label | Vendor | Position (x, y, z) | From spawn | Sells |
|---|---|---|---|---|---|
| `supermarket` | Badlands Market | Rosa | 370, -2385, 182 | 20 m N | water 10, burrito 25, nicola 15, chooh2 60, cigarettes 20 |
| `pharmacy` | Med-Point Pharmacy | Dr. Osei | 396, -2372, 182 | 33 m NNE (hospital zone) | bandage 40, maxdoc 120, bounceback 90 — **run by `trauma`**, stock 10 each |
| `gunshop` | 2nd Amendment Outpost | Wilson | 410, -2386, 182 | 33 m NE | pistol 400 (`Items.Preset_Lexington_Default`, slot 1), rifle 1 200 (`Items.Preset_Copperhead_Default`, slot 2), katana 900 (`Items.Preset_Katana_Default`, slot 3) — **licence required**, 500 €$ once |
| `clothes` | Jinguji Threads | Kimiko | 352, -2398, 182 | 30 m W | styling session 200 €$ → opens the wardrobe |
| `blackmarket` | Back-alley Dealer | Dex | 402, -2393, 182 | 22 m NE (blackmarket zone) | synthcoke 150, lockpick 80, qh_ping 120 — **22:00–06:00 only** |

Every vendor is `Character.Judy` (`RpShopsConfig.vendor.record`, overridable per shop with
`vendor.record`), invulnerable (`damagePolicy = 2`), combat off, non-persistent (recreated on
every start). When a customer opens the shop the vendor looks at them and plays the `greeting`
voice line; when robbed, `fear_beg` and the `handsup` workspot for 20 s.

Prices, positions, fees, hours, loot and cooldowns are all in `RpShopsConfig`.

## Commands

| Command | Who | Effect |
|---|---|---|
| **E** on a vendor | anyone alive, within 3 m, looking at them | Opens the shop: the vendor's line in chat, then the catalogue (UI kit context menu, one row per item with the price and, for a society shop, the stock). Pick an item → quantity dialog (1–20) → paid → delivered. The menu comes back after each purchase; **Leave** / Escape closes it. |
| `/boutiques` | anyone | Every shop with its distance from you, the black market's open/closed state and the owning society. |
| `/boutiques <shopId>` | anyone | That shop's catalogue in chat (with stock for a society shop, and the licence line for the gun shop). |
| `/boutiques restock <shopId>` | the society **boss** (`rp_jobs:isBoss` + same job) or the console | Refills every shelf of a society shop to its `restockTo`, paid from the society at 50 % of retail per unit (`restockCostRatio`). Refused when the society is dry, with the cost. |
| `/acheter <item> [count]` | anyone alive within 3 m of a vendor | Buys without the menu from the nearest vendor. `<item>` is the id (`water`), the label or an unambiguous prefix; `licence` at the gun shop buys the NCPD licence. |

Refusals are explained in chat: too far (with the distance), dead, position unknown, sold out
(with what is left), not enough eddies (with the price), pockets full, unknown item, black
market closed, no licence, wanted by the NCPD, another screen open, vendor still held up. From
the server console `boutiques` prints the list/catalogue to the log and `boutiques restock
<shopId>` is an admin tool; `acheter` answers "run this from the game".

## Rules the server applies

- **Payment**: `rp_economy:remove` (cash). If `insufficient_funds`, `rp_bank:withdraw` the
  amount to cash and take it (`paid=account`); a failed second step puts the withdrawal back.
  No split between cash and account.
- **Society shops** (`society = "<job>"`): `rp_bank:societyAdd(society, floor(price × 0.70),
  "sale:<shop>:<item>")` after every sale; stock decremented and persisted; the first boot
  seeds every item at `restockTo` (free opening stock). A shop without `society` has unlimited
  stock and pays nobody.
- **Gun licence**: NCPD members (`rp_jobs:hasJob(id, "ncpd")`, `gunLicenceExemptJobs`) need
  none. Everybody else buys one once (`gunLicenceFee` 500 €$): refused when `rp_ncpd:wanted`
  answers a warrant or `rp_ncpd:record(id).warrant` is set. Paid cash (credited to the `ncpd`
  society with `societyAdd`) or by `rp_bank:charge(id, 500, "ncpd", "gun_licence")`. Stored in
  `rp_shops_licences` (kvp `licence:<identifier>` without a database). The NCPD veto is
  re-checked at **every** gun sale, licence or not.
- **Guns**: `Open77.weapons.assign(playerId, record, slot, { active = true })`; the money is
  taken first, the sale is logged and told on `open77:weapons:completed` (`accepted`), refunded
  in cash otherwise or after 15 s without an answer.
- **Clothes**: the styling fee is charged **at once**, then the client runs the platform's
  `wardrobe` command locally (`Open77.runtime.executeCommand("wardrobe")`). The chat line always
  says "if the wardrobe didn't pop, type /wardrobe" — see *Honest limits*.
- **Black market**: `Open77.environment.getState().hour` must be in `[22, 6)`
  (`RpShopsConfig.blackmarket`); by day the dealer plays `rep_ask_to_leave` and answers with
  the `closedLine`. No clock authority (`open77_weather` absent) = never closed, logged once.
  The dealer also checks `rp_zones:isIn(id, "blackmarket")` when `rp_zones` runs.
- A dead player (`Open77.players.isDead`) buys nothing; the position snapshot must be younger
  than 5 s; one shop dialog per player at a time.

## Exports (server, synchronous — never yield)

```lua
exports.rp_shops:openShop(playerId, shopId)   -- true (dialog scheduled, no distance check) | nil, "invalid_player" | "unknown_shop"
exports.rp_shops:stock(shopId)                -- { { itemId, price, count }, ... } | nil, "unknown_shop"   (count = -1: unlimited)
exports.rp_shops:rob(shopId, byPlayerId)      -- loot (cash handed to the robber) | nil, reason
```

`rob` reasons: `unknown_shop`, `invalid_player`, `cooldown` (20 min per shop), `too_far`
(robber more than 5 m from the vendor), `position_stale` / `player_not_found`,
`register_empty` (society shop whose society is dry), `economy_offline`. On success the robber
receives `math.random(200, 600)` €$ in cash (`rp_economy:add`, reason `robbery:<shop>`), a
society shop loses the same from its society (as far as it goes), the vendor raises hands and
begs, `rp_shops:robbed` is raised and `rp_ncpd:alert("robbery", position, "<label> robbed",
byPlayerId)` pages the police. Call it inside `pcall`; a resource **with** a client script must
not declare `dependency "rp_shops"` (this manifest is delivered to clients).

## Events (host bus, `TriggerEvent`)

```lua
AddEventHandler("rp_shops:sale",   function(shopId, playerId, itemId, count, price) end) -- every paid delivery (items, weapons, licence, styling)
AddEventHandler("rp_shops:robbed", function(shopId, byPlayerId, amount) end)
```

Also raised: `rp_ncpd:alert` (robbery). Consumed: `open77:weapons:completed`, `onNpcRemoved`. Internal net
events (`rp_shops:open` client→server, `rp_shops:wardrobe` server→client) are this resource's
transport, not an API.

## Persistence

Created inside `Open77.database.ready(...)` with `CREATE TABLE IF NOT EXISTS`, permission
`database.access`, keyed by `Open77.players.identifier` (never the session id):

| Table | Columns |
|---|---|
| `rp_shops_stock` | `shop_id`, `item_id`, `count` — PK (`shop_id`, `item_id`); society shops only |
| `rp_shops_sales` | `id`, `shop_id`, `kind` (`item` / `weapon` / `licence` / `service`), `item_id`, `count`, `price`, `buyer` (identifier), `buyer_name`, `paid_with` (`cash` / `account`), `created_at` (unix) — every sale; `WHERE kind = 'weapon'` is the NCPD's gun ledger |
| `rp_shops_licences` | `identifier` (PK), `name`, `fee`, `created_at` |

Stock and licences are cached in memory and written through with the callback forms, so the
exports never touch the database; a licence is read on `onPlayerReady` (or lazily at the gun
shop). **No database** (`ready` answers `database_unavailable`, or nothing answers 15 s after
start): stock lives in kvp `stock:<shopId>` (JSON) and licences in `licence:<identifier>`,
the log says `store=kvp reason=...`, and there is no sales ledger (sales are still printed).

## Log (grep-able)

```
[rp_shops] 5 shops open around 381, -2402; gun licence 500, styling 200, black market 22:00-06:00
[rp_shops] store=sql tables=rp_shops_stock,rp_shops_sales,rp_shops_licences stock rows=3
[rp_shops] vendor Rosa of supermarket spawned at 370.0 -2385.0 182.0 (npc 12)
[rp_shops] sale shop=supermarket item=water x2 price=20 player 3 (<identifier>) paid=cash
[rp_shops] society trauma +28 (sale:pharmacy:bandage) balance=50028
[rp_shops] licence issued to player 3 (<identifier>) paid=account
[rp_shops] sale shop=gunshop weapon=pistol x1 price=400 player 3 (<identifier>) paid=cash
[rp_shops] Med-Point Pharmacy restocked: 4 units for 130 €$ from the trauma society. (by 2)
[rp_shops] ROBBERY shop=supermarket by player 4 loot=412
[rp_shops] no clock authority (environment_unavailable): the black market never closes
```

## Manifest

Permissions: `network.events` (net events, `TriggerClientEvent`, `Open77.weapons.assign`),
`database.access`, `world.npcs` (vendors), `players.life.read` (`isDead`),
`world.environment` (`getState` for the hours). Dependencies: `open77_uikit`,
`open77_worldui`, `open77_weapons` — all ship a client half. `rp_economy`, `rp_bank`,
`rp_inventory`, `rp_jobs`, `rp_ncpd`, `rp_zones`, `rp_identity` are reached through `pcall`
and degrade to a chat line: no economy = no sale; no bank = cash only, no society share; no
jobs = nobody is exempt and nobody can restock; no NCPD = no veto; no identity = account names.

## Honest limits

- **The wardrobe opening is best-effort.** `open77_wardrobe`'s exports (`beginPreview` /
  `endPreview`) refuse every caller but `open77_wardrobe_ui`, and no documented native opens
  the wardrobe screen on a player from the server; the platform's `/wardrobe` command is the
  only door. The client runs it against its local command registry — if the command turns out
  to be server-side on this build it answers `unknown_command`, the fee is still charged, and
  the chat line tells the customer to type `/wardrobe` themselves.
- Voice lines (`greeting`, `fear_beg`, `rep_ask_to_leave`) are queued, not proven heard:
  `speak` cannot report a line the record's voiceset lacks. Test by ear on `Character.Judy`.
- `qh_ping` exists only while `rp_netrunner` runs; without it the dealer answers "item unknown"
  and refunds. `synthcoke` and `lockpick` are built-in `rp_inventory` items.
- The exports work on **connected** players (session ids). `Character.Judy` is the platform
  documentation's own shopkeeper record; the devkit catalogue does not list civilian
  `Character.*` ids, so a different look means editing `vendor.record` and testing it.

## Test in 2 minutes

One client at the freeroam spawn `381.36, -2401.79, 181.99`, id `1`; `rp_economy`,
`rp_inventory`, `rp_bank`, `rp_jobs`, `rp_ncpd`, `rp_zones`, `open77_weather`, `open77_uikit`,
`open77_worldui`, `open77_weapons` running. Start with `rp_shop` unloaded. Log on start:
`[rp_shops] 5 shops open ...`, `store=sql ...`, five `vendor ... spawned` lines.

1. `/boutiques` → five lines with distances (`Badlands Market (supermarket) - 20 m - 5 lines`,
   `Back-alley Dealer (blackmarket) - 22 m - 3 lines [closed until 22:00]`, `Med-Point Pharmacy
   ... [trauma]`). Open the map: five pins.
2. Walk 20 m north to Rosa (370, -2385). Ring + prompt **Badlands Market**. Press **E** → chat
   `Rosa: Water, burritos, NiCola...`, the menu opens. **Bottle of water** → quantity `2` →
   **Buy** → `Bought 2 x Bottle of water for 20 €$ (cash). It's in your pockets.`; `/inv` shows
   them. Pick **Leave**. Walk 10 m away and `/acheter water` → `No vendor within 3 m.`
3. Pharmacy (396, -2372): **E** → the rows read `10 in stock`. Buy a bandage → `9 in stock`,
   log `society trauma +28`. Console: `setjob 1 trauma 3` then `/boutiques restock pharmacy` →
   `Med-Point Pharmacy restocked: 1 units for 20 €$ from the trauma society.` (`setjob` seeded
   the society). `/boutiques pharmacy` → `stock 10` again.
4. Gun shop (410, -2386): **E** → the first row is **NCPD gun licence — 500 €$**. Pick
   **M-10AF Lexington** first → `No NCPD gun licence on file. Buy one here for 500 €$
   (/acheter licence).` Pick the licence → `NCPD gun licence issued for 500 €$ (cash)`. Pick the
   pistol → `... delivery in progress...` then `Delivered: M-10AF Lexington (slot 1)`; the gun
   is in hand. Log: two `sale shop=gunshop` lines with your identifier. With an NCPD warrant
   (`/mandat 1 2 test` from an officer) the same purchase answers `NCPD has a warrant on you`.
5. Clothes (352, -2398): **E** → **Styling session** → `Styling fee 200 €$ (cash) paid. The
   racks are yours...` and the wardrobe opens (or type `/wardrobe`).
6. Black market (402, -2393) by day: **E** → `Dex: Not in daylight, choom. Come back after
   22:00...`. Console: `weather.time.set 23:00`. **E** again → the menu; buy a lockpick →
   `Bought 1 x Lockpick for 80 €$`. `/acheter synthcoke 2` at the counter works too.
7. Empty your cash (`/pay` it away or spend it), deposit at an ATM, buy again: the line ends
   with `(account)`.
8. From another resource: `exports.rp_shops:stock("pharmacy")` → three rows with counts;
   `exports.rp_shops:rob("supermarket", 1)` while standing at Rosa → Rosa raises hands, chat
   `Rosa empties the register: 4xx €$ in cash...`, an on-duty officer reads the NCPD dispatch
   line, log `ROBBERY shop=supermarket by player 1 loot=...`; a second call answers `cooldown`.
9. Reconnect: the licence is still on file (no licence row offered at the gun shop).
