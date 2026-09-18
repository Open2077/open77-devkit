# rp_housing - apartments and hideouts

A roof over your head in Night City, for an Open77 RP server (build `2.31.13+op77.76`).
Five real flats — V's apartment in Megabuilding H10, Judy's, Northside, Japantown, the Glen —
a real-estate agency at Kabuki Market that sells them, keys you can
hand to a choom, a private stash inside, a rent every payday, an eviction when you stop
paying, and the option to wake up at home when you reconnect.

Server-authoritative: the server owns the deeds (`rp_housing_homes`), the keys
(`rp_housing_keys`), the rent clock and the "who is inside" state. The client only draws
rings, E prompts and map pins, and sends the minimum intent (`door <id>`, `stash <id>`,
`exit <id>`, `agency`, `giveKey <playerId>`); every request is re-checked on the server:
distance, life state, ownership, keys, money.

## Real flats, one door each

Every home is a **real Night City apartment**: `interior` is the flat's floor (an AMM interior
point), `heading` the body yaw on arrival. Entering is an `Open77.players.teleport` to the
interior behind a fade (`Config.enterFade`, 400 ms each way); leaving is the same teleport
back to the entrance. Inside, two more rings stand next to the arrival point: **Stash** (E
opens `rp_inventory:openStash(playerId, "home:<id>", 200)`) and **Front door** (E leaves). The
stash refuses anybody who did not come in through the door. Where exactly the three rings
stand is decided by the flat's real front door (next section): the interior points are AMM
points right at the doorstep and every flat faces its own way, so a fixed x offset lands inside
the walls (measured 2026-09-18 at Northside: the old `interior - 1.5 m along x` exit ring stayed
3.3-3.6 m from the arrival point and could never be pressed).

### The auto door

The entrance ring is the flat's **own front door**, found at runtime. On start (once the
registry is loaded) and then every `Config.autoDoor.retrySec` (60 s) while unresolved, the
server calls `exports.open77_doors:near(interior, 0, 6)` (`Open77.exports.call`, awaited in a
thread, wrapped in `pcall`) for each home whose `doorId` is empty: the answer is
`{ doors, total, truncated }`, nearest first, and a door row carries `id` (a `0x...` string),
`bucket`, `position` and the state flags — **no facing**. The nearest door becomes the home's
`doorId` and **the three rings are derived from it** along the door -> interior axis (the
"outside" direction is the door's facing when a row reports one, otherwise from the interior
point towards the door, +x when the door sits on the interior point itself):

| Ring | Rule (`Config.autoDoor`) | Northside, door `0x5AC234B6C1F41703` at `-1503.4, 2227.3` |
|---|---|---|
| **Apartment door** (entrance) | door + `outside` (1.5 m) towards the street | `-1503.2, 2228.8` |
| **Front door** (exit) | door + `inside` (1.2 m) towards the interior | `-1503.6, 2226.1` |
| **Stash** | interior + `stashInside` (1.2 m) further along the same direction, never back towards the door | `-1504.0, 2223.7` |

The interior rings keep the interior's z (the floor the player lands on); the entrance keeps the
door's. A player on the arrival point is ~1.6 m from both interior cards (3D, to the anchor 1 m
above the ring), so both are pressable at once and `open77_interactions` arbitrates by distance:
the nearer one wins, the other takes over as you step towards it. The door is then claimed
through the existing path (`register` / `configure { automatic = true, autoClose = true,
defaultAccess = false }` / `setAccess` for the owner and the key holders, re-applied on every
`onPlayerReady`). The server pushes the resolved rings to every client in the
`rp_housing:state` snapshot (`entrances`, `exits`, `stashes = { [homeId] = {x, y, z} }`): the
client recreates its `door:<id>`, `exit:<id>` and `stash:<id>` POIs there and moves the map pin.
A hand-set `doorId` goes through the same derivation the first time `open77_doors:get` sees the
door.

Until a client has **streamed the flat** (walked past it) `open77_doors` has discovered
nothing there, `near` answers an empty list, and the **static fallback** stays in force: the
entrance is `interior + 3 m along x` (`Config.autoDoor.fallback`), the **Front door** ring is
the **interior point itself** (the player arrives standing on it; the ring is 1.0 m wide,
`Config.exitRadius`, and its card is ~1 m away from a player on it, so `promptDistance 3.0`
keeps it pressable) and the stash is `interior + 1.5 m along x` — drawn, prompted and used by
the teleports exactly like before. Log: `auto door of h10_studio: no door discovered within 6 m
of the interior yet (...); static entrance -1388.9, 1271.7, 123.1 in force, retry every 60 s`,
then `auto door of northside_container: 0x5AC234B6C1F41703 at -1503.4, 2227.3, 22.2; entrance
ring moved to -1503.2, 2228.8, 22.2; exit ring to -1503.6, 2226.1, 22.2; stash ring to -1504.0,
2223.7, 22.2` once found. A hand-set `doorId` in `shared/config.lua` skips the search;
`autoDoor = false` keeps the static rings for good. Without `open77_doors` at all, `near`
answers `nil, reason` and the static rings are simply permanent. A door that was found but could
not be claimed is retried on the same 60 s clock (log line `door ... could not be claimed`).

## Where things are (world metres, real Night City)

| What | Position | Notes |
|---|---|---|
| **Night City Real Estate** (agency) | `-1218.65, 2022.93, 7.82` | Kabuki Market, **The Crossing** (walked), 32 m west of the market centre; ring + E prompt, map pin, and an `electronics.monitor.device` listings terminal prop (curated alias, see `prop.catalog`) 2.6 m east of the ring (`-1216.05, 2022.93`; the config lists the same alias twice as its fallback; spawned on start, removed on stop) |
| Northside Apartment (`northside_container`) | inside `-1503.8, 2224.9, 22.2` | Northside, Watson — **9 000 €$**, the cheapest; 380 m north-west of the market |
| Glen Apartment (`badlands_hideout`) | inside `-1524.0, -992.6, 9.1` | The Glen, Heywood — 15 000 €$; 3 km south |
| Megabuilding H10 — V's Apartment (`h10_studio`) | inside `-1391.9, 1271.7, 123.1`, heading -99.3 | Little China, Watson (`rp_zones` `h10`) — 25 000 €$; 760 m south-west |
| Judy's Apartment (`kabuki_flat`) | inside `-906.3, 1868.7, 42.4` | Kabuki, Watson — 30 000 €$; 320 m east |
| Japantown Apartment (`japantown_loft`) | inside `-785.3, 992.6, 12.0` | Japantown, Westbrook — 40 000 €$; 1.1 km south-east |

The home ids are unchanged from the first build (SQL rows, `home:<id>` stashes and the
`rp_config` keys keep working); the labels are what players read. The entrance of every home
is its front door (see *The auto door* above), or `interior + 3 m along x` until the door is
discovered; the exit and stash rings follow the same door (1.2 m inside it / 1.2 m beyond the
interior point), or stand on the interior point / 1.5 m along x until then. Rent is **500 €$
per payday** (every 10 min) for every home (`Config.rent`, overridable per home). The prompt is
pressable within 3 m (`promptDistance = 3.0`) while looking at the ring; the server tolerates
2.5 m more on every ring (door, front door and stash alike, measured against the same derived
positions).

## Commands

| Command | What it does |
|---|---|
| `/maison` | Your place: label, price paid, rent, next payday, unpaid count, spawn-at-home flag, and who holds keys. Without a home: says so, and lists the keys you hold. |
| `/maison cles <playerId>` | Hands a key to a connected player within 3 m. ALT+click that player > **Give a key** does the same. |
| `/maison retirer <playerId>` / `/maison retirer tous` | Takes a key back (the holder must be connected), or voids every key. A holder standing inside is put back on the street. |
| `/maison spawn` | Toggles **spawn at home**: on your next connection you wake up inside your place instead of Kabuki Market. |
| `/maison vendre` | Sells your place back at **70 %** (`Config.sellBackRatio`), paid in cash. A UI-kit confirmation opens; `/maison vendre oui` confirms in chat when the kit is unavailable. |
| `/maison acheter <homeId>` | Buys a home by id, **at the agency desk only** (within 4 m). Without an id: lists the market in chat. The fallback when the menu cannot open. |
| `/loyer` | Rent status: amount, next payday, unpaid count. |
| `/loyer payer` | Pays now: the arrears when there are any (`unpaid x rent`, keeps the home), otherwise one payday in advance. |
| `/agence_immo` | Opens the agency menu, within 4 m of the desk (the same as pressing E on its ring). |

Every command refuses the server console politely (`run this from the game`). Refusals
are explained in chat as `NC Housing` lines, in English.

### The agency menu

A UI-kit context menu (server twin, `open77_uikit`) with one row per home: price, rent and
district in the metadata, `For sale` / `Owned by X` (disabled) / `Yours - sell it back for
N €$` (pick it to sell). A pick opens a confirmation (`alert`), then the deed is signed:
`rp_bank:charge(playerId, price, "housing", "buy:<id>")`; when the account is short the
**cash wallet** is tried (`rp_economy:remove`), so a tester only needs `givemoney` from the
console. One roof per citizen: a second purchase is refused until the first is sold.

## Money

- Purchases and rents go `account -> society "housing"` through `rp_bank:charge`. The
  society is a sink: it is not a job, nobody withdraws from it; every movement is logged
  (`[rp_housing] player 3 <identifier> paid rent 500 for h10_studio from account`) and
  sits in the `rp_bank` ledger as `society:housing`.
- When the account is short the cash wallet pays (`rp_economy:remove`); when both are
  short, the rent is **unpaid**.
- A sale pays 70 % of the price back **in cash** (`rp_economy:add`), and debits the housing
  society for the ledger when it can.

## Rent and eviction

A server thread checks every 60 s (`Config.rentTickSec`). A **connected** owner whose
`rent_due_at` has passed is charged one rent, and the next payday is scheduled 10 min
later (`Config.rentIntervalSec`). Rent is only collected while the owner is connected: a
long absence costs one rent on return, not one per missed payday. On a failure the unpaid
counter grows and the player is warned (`RENT UNPAID (1/2)`); at **two** consecutive unpaid
rents (`Config.evictAfter`) the owner is evicted: deed deleted, every key voided, anybody
inside is put back on the street, event `evicted`. `/loyer payer` clears the arrears and
resets the counter.

## Respawn at home

There is **no spawn-point API** on this host: `Open77.players.respawn` only works on a
dead player, and the freeroam gamemode places every connecting body at Kabuki Market. So
`/maison spawn` stores a flag, and on `onPlayerReady` the server waits until the player's
life phase is `alive` (`Open77.players.getLifeState`, up to 30 s - a connecting client
reports a `dead` phase once, and a placement on the continue screen crashes the client),
waits 1.5 s more for the spawn placement to settle, then teleports the body to the
interior behind a fade and marks the player inside. Expect a short black hop from the
market to the home; a `settle_superseded` from the gamemode's own placement is reported in
chat (`Could not bring you home (...)`) and logged.

## Exports (server; synchronous-safe, nothing yields)

```lua
exports.rp_housing:homeOf(playerId)        -- { id, label, position = entrance } | nil
exports.rp_housing:hasKey(playerId, homeId) -- boolean (the owner counts as a key holder)
exports.rp_housing:stashOf(homeId)          -- "home:<id>" | nil for an unknown home
exports.rp_housing:isInside(playerId)       -- homeId | nil
```

Call them inside `pcall` from another resource (a synchronous export raises when the
resource is not running). `rp_housing` ships a client script, so a resource that has one
too may declare `dependency "rp_housing"`.

## Events (host bus)

```lua
AddEventHandler("rp_housing:changed", function(identifier, homeId, action) end)
```

`action` is one of `bought`, `sold`, `evicted`, `rent_paid`, `rent_unpaid`, `spawn_on`,
`spawn_off`, `key_given`, `key_revoked`. For the two key actions `identifier` is the **key
holder's** identifier; for every other action it is the owner's.

Internal transport (not an API): client -> server `rp_housing:clientReady`,
`rp_housing:door`, `rp_housing:exit`, `rp_housing:stash`, `rp_housing:agency`,
`rp_housing:giveKey`; server -> client `rp_housing:state` (`{ mine, owned, keys, inside,
entrances, exits, stashes }`, drives the map pins, the three rings per home and the ALT+click
predicate).

## Persistence

Two tables, created inside `Open77.database.ready(...)` with `CREATE TABLE IF NOT EXISTS`,
keyed by the durable `Open77.players.identifier`:

| Table | Columns |
|---|---|
| `rp_housing_homes` | `home_id` (PK), `identifier`, `owner_name`, `paid`, `bought_at`, `rent_due_at`, `unpaid_rent`, `spawn_at_home` |
| `rp_housing_keys` | `home_id`, `identifier` (PK pair), `holder_name`, `granted_by`, `granted_at` |

Everything is cached in memory at start and written through with the callback forms
(`Open77.database.update(sql, params, cb)`); the exports never touch the database. A row
for a `home_id` that is no longer in `shared/config.lua` is kept but ignored (logged).
**No database** (`ready` answers `database_unavailable`, or nothing answers within 20 s):
`Open77.kvp` (`homes`, `keys` as JSON) takes over and the log says
`[rp_housing] store=kvp reason=...`. The choice is made once per boot. The stash content
itself lives in `rp_inventory_stashes` (`rp_inventory`).

## Manifest

Dependencies: `open77_worldui`, `open77_uikit`, `open77_contextmenu`, `open77_notifications`
(all four ship a client half). `rp_inventory`, `rp_bank`, `rp_economy`, `rp_identity`,
`rp_zones` are server-only and reached through `pcall`; `open77_doors` through
`Open77.exports.call` (optional: without it the static entrances are permanent). Permissions:
`network.events`, `database.access`, `players.teleport`, `players.life.read`, `ui.vanilla.map`,
`world.props` (the agency terminal, removed on stop).

## Log lines (grep-able)

```
[rp_housing] started, 5 homes, agency at -1218.6, 2022.9, 7.8
[rp_housing] prop 1044 of agency at -1216.1 2022.9 7.8 (electronics.monitor.device)
[rp_housing] store=sql homes=0 keys=0
[rp_housing] auto door of h10_studio: no door discovered within 6 m of the interior yet (a client must stream the flat); static entrance -1388.9, 1271.7, 123.1 in force, retry every 60 s
[rp_housing] auto door of northside_container: 0x5AC234B6C1F41703 at -1503.4, 2227.3, 22.2; entrance ring moved to -1503.2, 2228.8, 22.2; exit ring to -1503.6, 2226.1, 22.2; stash ring to -1504.0, 2223.7, 22.2
[rp_housing] door 0x5AC234B6C1F41703 locked to the owner and key holders of northside_container
[rp_housing] 16 world prompts created                 (client)
[rp_housing] door ring of northside_container moved to -1503.2, 2228.8, 22.2 (auto door)   (client)
[rp_housing] exit ring of northside_container moved to -1503.6, 2226.1, 22.2 (auto door)   (client)
[rp_housing] stash ring of northside_container moved to -1504.0, 2223.7, 22.2 (auto door)   (client)
[rp_housing] player 3 <identifier> bought northside_container for 9000 from cash
[rp_housing] player 3 entered northside_container
[rp_housing] player 3 opened stash home:northside_container
[rp_housing] player 3 left northside_container
[rp_housing] player 3 gave a key of northside_container to player 4 <identifier>
[rp_housing] player 3 <identifier> paid rent 500 for northside_container from account
[rp_housing] player 3 <identifier> missed rent 500 for northside_container (1/2): insufficient_funds / insufficient_funds
[rp_housing] <identifier> evicted from northside_container: unpaid rent
[rp_housing] player 3 spawn at home northside_container: true
[rp_housing] player 3 spawned at home northside_container
[rp_housing] player 3 <identifier> sold northside_container for 6300 (70%)
```

## Test in 2 minutes (one player, from the Kabuki Market spawn)

1. Start the server with `rp_housing` next to `rp_bank`, `rp_economy`, `rp_inventory`,
   `rp_identity`, `rp_zones`, `open77_doors` and the four `open77_*` packages. Log:
   `[rp_housing] started, 5 homes, agency at -1218.6, 2022.9, 7.8`, `prop <id> of agency at
   -1216.1 2022.9 7.8 (...)`, then `store=sql homes=0 keys=0` (or `store=kvp`) and five `auto
   door of <id>: no door discovered ... static entrance ... in force` lines.
2. Connect. Open the map: a **vendor** pin `Night City Real Estate` at The Crossing (32 m west
   of the spawn) and five **apartment** pins `... - For sale` across Watson, Westbrook and
   Heywood.
3. Console: `givemoney <id> 10000`. `/money` says 10 500.
4. Walk 32 m west to the agency ring at The Crossing (`-1218.65, 2022.93`), the data terminal
   beside it, look at the ring, press **E** (or `/agence_immo`). The `Night City Real Estate`
   menu opens. Pick **Northside Apartment** (9 000 €$, the cheapest), then **Sign**. Chat:
   `Northside Apartment is yours (paid from cash) ...`, toast `Deed signed`. The pin now reads
   `Northside Apartment - Your place`. Log: `player <id> ... bought northside_container for
   9000 from cash`.
5. `/maison` -> `Northside Apartment (northside_container) - bought for 9 000 €$ - rent
   500 €$/payday - next rent in 10 min - unpaid 0/2 - spawn at home: off` and
   `Keys: nobody but you ...`.
6. Go to Northside (380 m north-west; console `tp <id> -1500.8 2224.9 22.2` lands you on the
   static entrance). The door ring stands at `-1500.8, 2224.9` (interior + 3 m) until the flat's
   front door is discovered; once you have walked past the flat with `open77_doors` running, the
   next retry (≤ 60 s) logs `auto door of northside_container: 0x5AC234B6C1F41703 at -1503.4,
   2227.3, 22.2; entrance ring moved to -1503.2, 2228.8, 22.2; exit ring to -1503.6, 2226.1,
   22.2; stash ring to -1504.0, 2223.7, 22.2` and the rings, the pin and the client lines `door
   / exit / stash ring of northside_container moved to ...` follow — the door then opens for you
   alone. Look at the door ring (now 1.5 m outside the real door, on the street side), press
   **E**. Fade to black, you stand on the flat's floor (`-1503.8, 2224.9, 22.2`), the **Front
   door** ring 1.2 m in front of you towards the door (`-1503.6, 2226.1`) and the **Stash** ring
   1.2 m behind you (`-1504.0, 2223.7`), both cards ~1.6 m away: `Welcome home. E on the stash,
   E on the front door to leave.` Log: `player <id> entered northside_container`. From another
   resource, `exports.rp_housing:isInside(<id>)` now answers `northside_container`. (Before the
   door is found: the Front door ring is under your feet on the arrival point and the Stash is
   1.5 m east.)
7. Turn to the **Stash** ring, step towards it so its card is the nearer one, press **E**: the
   `rp_inventory` Take / Store menu opens (200 kg). Store something, close, reopen: it is still
   there.
8. Turn back towards the door: the **Front door** card takes over as soon as it is the nearer
   card (the two rings are 2.4 m apart; `open77_interactions` keeps a latched prompt until you
   leave its range, so step a metre towards the door if the Stash card lingers). Press **E**:
   fade, you are back on the door ring outside: `You step out of Northside Apartment.` Try the
   **Stash** ring from outside (`tp` 6 m away without pressing the door): `Get inside first ...`;
   press it from further than 5.5 m inside the flat: `Too far from the stash.`
9. `/maison spawn` -> `Spawn at home ON ...`. You do **not** need to reconnect to check
   the flag: `/maison` shows `spawn at home: ON` and the row says `spawn_at_home = 1`.
   What a reconnect would do: the server waits for your body to be alive at Kabuki Market,
   then fades and moves it to `-1503.8, 2224.9, 22.2`, chat `Home sweet home: you wake up in
   Northside Apartment.`, log `player <id> spawned at home northside_container`.
   Reconnecting **does** exercise it, if you have a second minute.
10. `/loyer` -> `Northside Apartment: rent 500 €$ per payday (every 10 min), next in N
    min, unpaid 0/2`. `/loyer payer` -> `Paid one payday in advance ...` (cash, since the
    account is empty). Empty the wallet (`/pay <other> <all of it>`) and keep the account
    at 0 to see `RENT UNPAID (1/2)` at the next payday; twice in a row = `EVICTED`.
11. Two players: stand 2 m from the other client, `/maison cles <id2>` (or ALT+click them
    > **Give a key**): both are told; `/maison` lists the holder; the other client's pin
    turns `You hold a key` and their **E** on the door lets them in (`You let yourself into
    ... with <you>'s key`). `/maison retirer <id2>` takes it back.
12. `/maison vendre` -> confirmation -> `Sold Northside Apartment for 6 300 €$ in cash.`
    The pin is `For sale` again, `/maison` says you own nothing. Reconnect: nothing to
    restore; before the sale, a reconnect shows `Welcome back. Northside Apartment is
    waiting for you (rent in order).`
