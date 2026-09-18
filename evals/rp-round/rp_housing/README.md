# rp_housing - apartments and hideouts

A roof over your head in Night City, for an Open77 RP server (build `2.31.13+op77.76`).
Five homes near the freeroam spawn, a real-estate agency that sells them, keys you can
hand to a choom, a private stash inside, a rent every payday, an eviction when you stop
paying, and the option to wake up at home when you reconnect.

Server-authoritative: the server owns the deeds (`rp_housing_homes`), the keys
(`rp_housing_keys`), the rent clock and the "who is inside" state. The client only draws
rings, E prompts and map pins, and sends the minimum intent (`door <id>`, `stash <id>`,
`exit <id>`, `agency`, `giveKey <playerId>`); every request is re-checked on the server:
distance, life state, ownership, keys, money.

## Virtual homes

The eval area has no known native door, so every home is **virtual**: an `entrance`
position (ring + E prompt "Apartment door") and an `interior` position. Entering is an
`Open77.players.teleport` to the interior behind a fade (`Config.enterFade`, 400 ms each
way); leaving is the same teleport back to the entrance. On the shipped config the
interior is a spot 6 m away on the same plateau - the owner maps real interiors by editing
`shared/config.lua`. Inside, two more rings stand next to the arrival point: **Stash**
(E opens `rp_inventory:openStash(playerId, "home:<id>", 200)`) and **Front door** (E
leaves). The stash refuses anybody who did not come in through the door.

A home may also carry a `doorId` (an `open77_doors` engine id such as
`0xFC85EAE29622BAC2`). When set, the server claims the door through `open77_doors`
(`get` / `register` / `configure { automatic = true, autoClose = true, defaultAccess = false }`)
and grants `setAccess` to the owner and to every key holder, connected or arriving later; a
sale, an eviction or a revoked key withdraws the grant. The door then opens for them alone.
This is implemented but **untested**: the eval config has every `doorId` empty, and a door
that is not discovered yet is retried once a minute (log line `door ... is not discovered
yet`). Grants live in `open77_doors`' memory, so they are re-applied on every
`onPlayerReady` and on every restart of this resource.

## Where things are (world metres, z = 182 = the spawn plateau)

Everything is within 45 m of the freeroam spawn `381.36, -2401.79, 181.99`, clear of the
`rp_zones` rings (afterlife, mecano shop, black market), the ATM ring on the spawn and the
ground edge east of x 400.

| What | Position | Notes |
|---|---|---|
| **Real-estate agency** | `365, -2408, 182` | ring + E "Real-estate agency", map pin, 7 m south-west of the spawn |
| Northside container | door `354, -2394` / inside `354, -2388` (z 181.1-181.3, measured) | **9 000 €$** - the cheapest |
| Badlands hideout | door `352, -2404` / inside `352, -2410` | 15 000 €$ |
| Megabuilding H10 studio | door `376, -2380` / inside `376, -2374` | 25 000 €$ |
| Kabuki flat | door `388, -2388` / inside `388, -2382` | 40 000 €$ |
| Japantown loft | door `390, -2399` / inside `384, -2393` (measured; `390, -2405` reports no ground) | 65 000 €$ |

Rent is **500 €$ per payday** (every 10 min) for every home (`Config.rent`, overridable per
home). `z = 182` is the same guess `rp_bank` and `rp_zones` use; a ring drawn inside the
floor is invisible although everything reports success - stand on the spot, `/pos`, paste
the height. The prompt is pressable within 3 m (`promptDistance = 3.0`) while looking at
the ring; the server tolerates 2.5 m more.

## Commands

| Command | What it does |
|---|---|
| `/maison` | Your place: label, price paid, rent, next payday, unpaid count, spawn-at-home flag, and who holds keys. Without a home: says so, and lists the keys you hold. |
| `/maison cles <playerId>` | Hands a key to a connected player within 3 m. ALT+click that player > **Give a key** does the same. |
| `/maison retirer <playerId>` / `/maison retirer tous` | Takes a key back (the holder must be connected), or voids every key. A holder standing inside is put back on the street. |
| `/maison spawn` | Toggles **spawn at home**: on your next connection you wake up inside your place instead of the plaza. |
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
dead player, and the freeroam gamemode places every connecting body at the plaza. So
`/maison spawn` stores a flag, and on `onPlayerReady` the server waits until the player's
life phase is `alive` (`Open77.players.getLifeState`, up to 30 s - a connecting client
reports a `dead` phase once, and a placement on the continue screen crashes the client),
waits 1.5 s more for the plaza placement to settle, then teleports the body to the
interior behind a fade and marks the player inside. Expect a short black hop from the
plaza to the home; a `settle_superseded` from the gamemode's own placement is reported in
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
`rp_housing:giveKey`; server -> client `rp_housing:state` (`{ mine, owned, keys, inside }`,
drives the map pins and the ALT+click predicate).

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
`Open77.exports.call` (optional). Permissions: `network.events`, `database.access`,
`players.teleport`, `players.life.read`, `ui.vanilla.map`.

## Log lines (grep-able)

```
[rp_housing] started, 5 homes, agency at 365.0, -2408.0, 182.0
[rp_housing] store=sql homes=0 keys=0
[rp_housing] 16 world prompts created                 (client)
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

## Test in 2 minutes (one player, at the freeroam spawn)

1. Start the server with `rp_housing` next to `rp_bank`, `rp_economy`, `rp_inventory`,
   `rp_identity`, `rp_zones` and the four `open77_*` packages. Log:
   `[rp_housing] started, 5 homes ...` then `store=sql homes=0 keys=0` (or `store=kvp`).
2. Connect. Open the map: a **vendor** pin `Real-estate agency` 7 m south-west of the
   spawn and five **apartment** pins `... - For sale` around the plaza.
3. Console: `givemoney <id> 10000`. `/money` says 10 500.
4. Walk to the agency ring (`365, -2408`), look at it, press **E** (or `/agence_immo`).
   The `Night City Real Estate` menu opens. Pick **Northside container** (9 000 €$, the
   cheapest), then **Sign**. Chat: `Northside container is yours (paid from cash) ...`,
   toast `Deed signed`. The pin now reads `Northside container - Your place`.
   Log: `player <id> ... bought northside_container for 9000 from cash`.
5. `/maison` -> `Northside container (northside_container) - bought for 9 000 €$ - rent
   500 €$/payday - next rent in 10 min - unpaid 0/2 - spawn at home: off` and
   `Keys: nobody but you ...`.
6. Walk to the door ring at `354, -2394` (28 m west of the spawn), look at it,
   press **E**. Fade to black, you stand 6 m north (`354, -2388`): `Welcome home. E on
   the stash, E on the front door to leave.` Log: `player <id> entered northside_container`.
   From another resource, `exports.rp_housing:isInside(<id>)` now answers
   `northside_container`.
7. Look at the **Stash** ring 1.5 m east, press **E**: the `rp_inventory` Take / Store
   menu opens (200 kg). Store something, close, reopen: it is still there.
8. Look at the **Front door** ring 1.5 m west, press **E**: fade, you are back on the door
   ring: `You step out of Northside container.` Try the **Stash** ring from outside
   (walk 6 m west without pressing the door): `Get inside first ...`.
9. `/maison spawn` -> `Spawn at home ON ...`. You do **not** need to reconnect to check
   the flag: `/maison` shows `spawn at home: ON` and the row says `spawn_at_home = 1`.
   What a reconnect would do: the server waits for your body to be alive at the plaza,
   then fades and moves it to `354, -2388`, chat `Home sweet home: you wake up in
   Northside container.`, log `player <id> spawned at home northside_container`.
   Reconnecting **does** exercise it, if you have a second minute.
10. `/loyer` -> `Northside container: rent 500 €$ per payday (every 10 min), next in N
    min, unpaid 0/2`. `/loyer payer` -> `Paid one payday in advance ...` (cash, since the
    account is empty). Empty the wallet (`/pay <other> <all of it>`) and keep the account
    at 0 to see `RENT UNPAID (1/2)` at the next payday; twice in a row = `EVICTED`.
11. Two players: stand 2 m from the other client, `/maison cles <id2>` (or ALT+click them
    > **Give a key**): both are told; `/maison` lists the holder; the other client's pin
    turns `You hold a key` and their **E** on the door lets them in (`You let yourself into
    ... with <you>'s key`). `/maison retirer <id2>` takes it back.
12. `/maison vendre` -> confirmation -> `Sold Northside container for 6 300 €$ in cash.`
    The pin is `For sale` again, `/maison` says you own nothing. Reconnect: nothing to
    restore; before the sale, a reconnect shows `Welcome back. Northside container is
    waiting for you (rent in order).`
