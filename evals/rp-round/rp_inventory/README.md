# rp_inventory

The pockets of a Night City RP server. Server-authoritative: items live in the
server's memory for every connected player, every change is written straight
through to SQL (`rp_inventory_items`, `rp_inventory_stashes`) or, when the
server has no database, to the resource's `Open77.kvp` store. Clients only
render and request.

- Max carry weight: **40 kg** (`RpInventoryConfig.maxCarryWeight`).
- Items: `shared/items.lua` (`id, label, weight, usable, illegal, effect`).
- Menus: the UI kit (`open77_uikit`), driven from the server through its
  server twins; a chat listing replaces the menu when the kit is unavailable.
- Player-to-player actions: ALT+click a player (`open77_contextmenu`),
  slash commands as the fallback.
- Ground drops: the loot API (`Open77.loot.*`), picked up with the game's own
  prompt or `/ramasser`.

## Commands

| Command | What it does |
|---|---|
| `/inv` | Opens the pockets menu: every item with its count and weight, the total, and per item **Use / Give / Drop**. Falls back to a chat listing when the menu cannot open. |
| `/use <item>` | Uses one unit. A 3 s progress bar (cancellable), then the effect. |
| `/drop <item> [n]` | Removes `n` (default 1) from the pockets and creates a pickable ground drop at the player's feet (30 min TTL). |
| `/ramasser` | Picks up the nearest `rp_inventory` drop within 3 m, for when the native prompt is not convenient. |
| `/give <playerId> <item> [n]` | Hands items to a player within 3 m; the server checks the distance and the receiver's carry weight. ALT+click > **Give item** opens the same thing as a dialog. |
| `/fouiller <playerId>` | Searches a player who is **held by the RP kit** (`open77_rp_basics`) **or has hands up** (`handsup` RP profile). Lists their pockets and names the contraband. ALT+click > **Search pockets** does the same. |
| `/saisir <playerId> <item>` | Seizes every unit of an **illegal** item from a searched player. `implant_box` counts as legal for a `medecin` (rp_jobs). |
| `/giveitem <playerId> <item> [n]` | Admin/console (ACL `command.giveitem`): puts items into a player's pockets. Works from the server console. |

`<item>` accepts the id (`burrito`), the label (`Burrito`) or an unambiguous
prefix (`bur`).

### Items

| id | label | kg | usable | effect |
|---|---|---|---|---|
| `water` | Bottle of water | 0.5 | yes | `rp_needs:consume` (thirst) |
| `burrito` | Burrito | 0.4 | yes | `rp_needs:consume` (hunger) |
| `nicola` | NiCola | 0.4 | yes | `rp_needs:consume` (thirst) |
| `chooh2` | CHOOH2 fuel can | 5.0 | yes | `open77_fuel:refuel(vehicle, 20)` on the vehicle the player sits in |
| `bandage` | Bandage | 0.2 | yes | `Open77.players.heal` +25 |
| `maxdoc` | MaxDoc Mk.1 | 0.3 | yes | heal +60 |
| `bounceback` | Bounce Back Mk.1 | 0.3 | yes | heal +40 and full stamina |
| `phone` | Holophone | 0.3 | no | |
| `radio` | Radio | 0.8 | no | |
| `lockpick` | Lockpick | 0.1 | no | |
| `scrap` | Scrap | 1.0 | no | |
| `component` | Component | 0.5 | no | |
| `chip` | Data chip | 0.05 | no | |
| `cigarettes` | Pack of cigarettes | 0.1 | yes | flavour |
| `synthcoke` | Synthcoke | 0.1 | yes | **illegal**; full stamina |
| `implant_box` | Implant box | 2.0 | no | **illegal** unless the holder has the `medecin` job |
| `crate` | Cargo crate | 25.0 | no | heavy cargo |

A heal is refused at full health, food and drink are refused when `rp_needs`
says so (`nil, reason`), and the fuel can is refused outside a vehicle or when
no fuel system runs. In every case the item stays in the pockets and the
player is told why.

## Exports (server)

Phase 1 contract, all synchronous-safe (nothing yields), so both spellings work:

```lua
exports.rp_inventory:add(playerId, "burrito", 2)             -- true | nil, reason
local ok = exports.rp_inventory:remove(playerId, "burrito", 1) -- true | nil, "not_enough" | reason
exports.rp_inventory:has(playerId, "chooh2", 1)              -- boolean
exports.rp_inventory:count(playerId, "scrap")                -- number
local entries, weight, capacity = exports.rp_inventory:list(playerId)
-- entries = { { id, label, count, weight, total, usable, illegal }, ... } sorted by label
exports.rp_inventory:openStash(playerId, "house_12", 200)    -- true (menu scheduled) | nil, reason
```

Reasons: `invalid_player`, `player_not_found`, `not_loaded` (the pockets are
still being read), `unknown_item`, `invalid_count`, `too_heavy`, `not_enough`,
`invalid_stash`, `invalid_capacity`.

`openStash(playerId, stashId, capacity)` opens the shared-container menu
(**Take** rows for the stash, **Store** rows for the pockets) on the given
player; `capacity` is in kg (default 100). The stash is loaded from
`rp_inventory_stashes` on first use and every move is persisted. Housing and
vehicle trunks call this with their own stash ids.

## Events (host-wide bus)

```lua
AddEventHandler("rp_inventory:changed", function(playerId, itemId, delta) end) -- every credit/debit
AddEventHandler("rp_inventory:used", function(playerId, itemId) end)           -- after a successful /use
```

Client -> server requests (internal): `rp_inventory:giveMenu(targetPlayerId)`,
`rp_inventory:search(targetPlayerId)`, raised by the ALT+click actions.

## Logs

Every change is one grep-able line:

```
[rp_inventory] player 3 +2 burrito total=2 (export add)
[rp_inventory] player 3 -1 burrito total=1 (used)
[rp_inventory] player 3 -1 crate total=0 (dropped as loot 17)
[rp_inventory] player 4 +1 crate total=1 (picked up loot 17)
[rp_inventory] stash house_12 +3 scrap total=3 by player 3
[rp_inventory] player 5 searched player 3
```

## Persistence

```sql
rp_inventory_items   (identifier VARCHAR(64), item_id VARCHAR(32), count INT, PRIMARY KEY (identifier, item_id))
rp_inventory_stashes (stash_id   VARCHAR(64), item_id VARCHAR(32), count INT, PRIMARY KEY (stash_id, item_id))
```

Both tables are created inside `Open77.database.ready` with
`CREATE TABLE IF NOT EXISTS`. Rows are keyed by `Open77.players.identifier`,
never the session id. A player's pockets are read on `onPlayerReady` (the
resource waits up to 10 s for a database that is still connecting) and on a hot
reload for everyone already connected; nothing is written at disconnect because
every change was already written. When the server has **no** database
(`database_unavailable`) the kvp store is used instead and the log says so
(`loaded from kvp: database not ready (...)`). A failed SQL read never marks the
pockets loaded: the player is told to reconnect rather than risk a later write
erasing real rows.

## Ground drops

A drop is an `Open77.loot.create` with the documented `Items.money` /
`Items.MoneyShard` pair (the only record pair the devkit guarantees), the RP
label, and a 30 min TTL. The resource keeps `lootId -> { itemId, count }`, so
`onLootPickup` credits the real RP item, not eddies. A picker who cannot carry
it gets the drop re-created at their feet and a message. Per item,
`record` / `visual` in `shared/items.lua` override the TweakDB records once
verified on your build.

## Manifest permissions

`network.events` (events), `database.access` (SQL), `world.loot` (drops),
`world.vehicles` (the seat read for the fuel can), `players.stats.read` /
`players.stats.apply` (heals), `players.animations.read` (hands-up check).
Dependencies: `open77_uikit`, `open77_contextmenu`, `open77_loot` (all ship a
client half). `rp_needs`, `open77_fuel`, `open77_rp_basics` and `rp_jobs` are
reached through exports inside `pcall` and are optional at runtime.

## Test in 2 minutes

1. Start the server with `rp_inventory`, `open77_uikit`, `open77_contextmenu`
   and `open77_loot` in the load list; connect two players (ids 1 and 2).
2. From the server console: `giveitem 1 burrito 3`, `giveitem 1 maxdoc 1`,
   `giveitem 1 synthcoke 2`, `giveitem 1 crate 1`. Player 1 sees the toasts in
   chat; the log shows `player 1 +3 burrito total=3 (giveitem by 0)`.
3. Player 1: `/inv`. The menu lists four rows with counts and weights, the
   title reads `Pockets - 27.6 / 40 kg`. Pick **Burrito**, then **Use**: a 3 s
   bar, then `You eat the burrito.` (or the `rp_needs` answer). Escape closes
   the menu cleanly.
4. Player 1: `/use maxdoc` at full health: `You are already at full health.`
   Take some damage, use it again: `+60 health`.
5. Player 1: `/drop crate`. A drop appears at the feet; the console
   `giveitem 1 crate 1` again shows `too heavy` only once the pockets exceed
   40 kg. Player 2 walks over and uses the native **Take** prompt, or
   `/ramasser`: `Picked up Cargo crate x1`, log `player 2 +1 crate ... (picked up loot N)`.
6. Player 1 stands next to player 2, holds ALT, clicks them, **Give item**:
   the dialog lists the pockets, pick `Burrito`, count 1, **Give**. Both are
   told. Walk 5 m away and `/give 2 burrito`: `Get closer.`
7. Player 2 raises hands (`handsup` RP profile) or is cuffed by an officer with
   the RP kit. Player 1: `/fouiller 2` lists player 2's pockets and names
   `synthcoke` as contraband; `/saisir 2 synthcoke` moves both units. Without
   hands up: `They are neither cuffed nor surrendering.`
8. Reconnect player 1: the pockets come back from SQL (`loaded from sql`).
9. From another resource: `exports.rp_inventory:openStash(1, "test_stash", 50)`
   opens the Take / Store menu; store two items, reopen, they are still there.
