# rp_gangs — territories and criminal life

Gangs for a Night City RP server on Open77 (build `2.31.13+op77.76`): seven gangs, a
membership with three ranks, **influence** per territory (the gang with the most points holds
the zone and its members collect a **tribute**), a street **buyer NPC** per territory who pays
cash for drug packs, the **robbery** of a cuffed or surrendering player, **wars** for a
territory and a **racket** threat that pages the NCPD.

Server-authoritative: membership, influence, holders, tributes, deals, robberies and wars are
decided in `server/main.lua`. The client only draws the `[GANG]` tag over remote members,
offers the ALT+click **Rob** action and keeps the buyer prompt on the buyer NPCs; every request
is re-validated by the server (membership, distance, bucket, target state, cooldowns).

## The seven gangs

| id | label | colour | home territory |
|---|---|---|---|
| `maelstrom` | Maelstrom | red | `scrapyard` |
| `tygerclaws` | Tyger Claws | pink | `afterlife` |
| `valentinos` | Valentinos | gold | `blackmarket` |
| `sixthstreet` | 6th Street | blue | `nomad_camp` |
| `animals` | Animals | purple | `afterlife` |
| `voodooboys` | Voodoo Boys | green | `blackmarket` |
| `scavs` | Scavs | grey | `scrapyard` |

Ranks: `0` member, `1` lieutenant, `2` boss. Everything is `shared/config.lua`
(`RpGangsConfig`): gangs, territories and buyer positions, prices, cooldowns, war length.
Commands accept a gang or a territory by id, label or unambiguous prefix (`mael`, `6th`,
`black`).

## Territories

Territories are `rp_zones` zones (the eval config): `blackmarket` (400, -2390, 182 r10),
`afterlife` (360, -2390, 182 r10), `nomad_camp` (420, -2378, 182 r9), `scrapyard` (462,
-2352, 178 r12). All within 95 m of the freeroam spawn `381.36, -2401.79, 181.99`. The buyer
NPC of each stands a few metres off the zone centre: black market `397, -2393, 182`, Afterlife
`358, -2392, 182`, nomad camp `418, -2380, 182`, scrapyard `460, -2355, 178` (if one lands in
the ground, stand on the spot, `/pos`, paste the height into `Config.territories[].buyer`).

**Influence** (`rp_gangs_influence`, per zone and gang):

| Source | Points | Zone |
|---|---|---|
| a drug pack sold to the buyer (`/gang vendre` or the **E** prompt) | +1 (`dealInfluence`) | where the sale happened |
| `rp_crime` or any resource calling `addInfluence` | as given | as given |
| a gig completed by a member (`rp_fixer:gig` phase `success`) | +2 (`gigInfluence`) | the member's last territory, else the gang's home |
| a member jailed (`rp_ncpd:arrest`) | −5 (`arrestInfluence`, never below 0) | same rule |
| a war won | +10 (`warInfluence`) | the disputed zone |

The gang with **strictly** the most points holds the zone; on a tie the current holder keeps
it. A holder change is announced to everyone. Every `tributeIntervalMs` (10 min) each online
member of the holder gets `tributePerZone` (50 €$) cash **per held zone**
(`rp_economy:add`, reason `gang:tribute:<zone>`).

Note: `blackmarket` and `afterlife` sit inside the `spawn_plaza` safe zone of `rp_zones`,
so nobody takes damage there — wars are decided by presence, not by kills.

## Commands

| Command | Who | Effect |
|---|---|---|
| `/gang` | anyone | Your gang, rank, members (total / online, with ranks), territories held, the running war, the hideout (the boss's `rp_housing` home when the boss is online and owns one). Without a gang: the seven gangs and their head counts. |
| `/gang creer <gang>` | jobless, gang-less | Founds the gang and makes you its **boss** — only while the gang has **no member at all** (`Config.openFounding = true`, the admin-free bootstrap; set it to false and use `/setgang` on a production server). Refused with a day job (`rp_jobs:getJob` not nil). |
| `/gang recruter <playerId>` | boss / lieutenant | Recruits a jobless, gang-less player standing **within 5 m** as a member. |
| `/gang virer <playerId>` | boss / lieutenant | Kicks a member of a lower rank. |
| `/gang promouvoir <playerId>` | boss | member → lieutenant; lieutenant → **boss** (you step down to lieutenant). |
| `/gang quitter` | member | Leaves. A boss with a crew must hand over the seat first; the last member leaving **dissolves** the gang (its influence is cleared). |
| `/gang vendre` | member | Sells **one** `drug_pack` to the buyer of the territory you stand in (within 4 m of the NPC): +80 €$ cash (`dealPrice`), +1 influence, 60 s cooldown. The **E** prompt **Street deal** on the buyer does the same. |
| `/gang depouiller <playerId>` | member | Robs a player within 3 m who is **cuffed by the RP kit** (`open77_rp_basics:state`) **or has hands up** (`handsup` RP profile): 30 % of their cash (`rp_economy:remove` → `add`) and every **illegal** item (`rp_inventory:list` / `remove` / `add`; what you cannot carry stays on them). Pages the NCPD (`rp_ncpd:alert("robbery", ...)`). The same victim cannot be robbed twice in 2 min. ALT+click a player > **Rob** does the same. |
| `/territoire` | anyone (console too) | Every territory with its holder, a running war and the **top-3** influence. |
| `/guerre <zone>` | boss | Declares war on a territory **another** gang holds. Refused when you hold it, when nobody holds it ("deal there and take it"), when the zone is at war or cooling down (10 min), when your gang already fights elsewhere, or when the holder has nobody online. The holder's boss is told, both crews get a toast, the NCPD is paged (`gang_war`). The war lasts `warMinutes` (5 on the eval, 20 in production): **every 30 s the gang with more members inside the zone scores 1**; at the end the higher score wins **+10 influence** (a tie changes nothing). |
| `/racket <playerId>` | member | A **chat threat**: the target (within 5 m) reads that you want 100 €$ protection money and how to pay (`/pay`), gets a toast, and the NCPD is paged (`racket`). 60 s cooldown per victim. **Deliberately not implemented**: the society-payment version (charging a `rp_shops` society member through `rp_bank` with an `open77_player_interactions` consent flow) — the plan allowed skipping it, so this is the threat + alert only, and whether the victim pays is their call. |
| `/setgang <playerId> <gang\|none> [rank 0-2]` | admin (ACL `command.setgang`) or the console | Puts a player in a gang at a rank, or removes them. The escape hatch for a boss-less gang. |

Every refusal is a chat line from `GANG`: no gang, not the boss, too far (with the distance),
has a day job, already in a gang, unknown player, not cuffed nor surrendering, nothing to sell,
wallet / pockets offline, zone at war, and so on. From the server console `/gang`, `/guerre`
and `/racket` answer `run it from the game`; `/territoire` and `setgang` answer in the console.

Jobs and gangs are exclusive both ways: a member who takes a job (`rp_jobs:changed` with a job
name) is cut loose (`Config.dropOnJob`); if that was the boss, the highest-ranked online member
inherits the seat.

Nothing here collides with a platform or delivered command (`gang`, `territoire`, `guerre`,
`racket`, `setgang`).

## ALT+click and the buyer prompt

- **Rob** (`open77_contextmenu`, `registerPlayers`): shown to gang members only (the server
  tells each client its own membership), 3 m; the server re-measures the distance and checks
  the target's hold/hands-up state before touching anything.
- **Street deal** (`open77_interactions`): a server-declared `globalNpc` target with the
  client predicate `rpGangsIsBuyer`, so the card appears on this resource's buyer NPCs only
  (the server pushes their ids to every client). The press comes back as `onNpcInteracted`,
  measured by the server; `Config.buyer.reach` (4 m) is applied on that number.
- **Tag**: while `Config.showTag`, every other client draws a member's nameplate as
  `[MAELSTROM] Vince Rocker` in the gang colour (`Open77.nameplates.set`, 40 m). The nameplate
  API only overrides remote players, so you never see your own tag.

## Exports (server, synchronous — never yield; call inside `pcall`)

```lua
exports.rp_gangs:gangOf(playerId)                        -- "maelstrom" | nil
exports.rp_gangs:isBoss(playerId)                        -- boolean
exports.rp_gangs:rankOf(playerId)                        -- { level = 1, label = "lieutenant" } | nil   (extra)
exports.rp_gangs:influence("blackmarket")                -- { maelstrom = 12, scavs = 3 } | nil, "unknown_zone"
exports.rp_gangs:holderOf("blackmarket")                 -- "maelstrom" | nil                          (extra)
exports.rp_gangs:addInfluence("blackmarket", "maelstrom", 1, "deal")  -- newPoints | nil, reason
```

`addInfluence` reasons: `unknown_zone` (not a territory), `unknown_gang`, `invalid_points`
(not a non-zero integer). Negative points floor at 0. When `reason` is omitted the invoking
resource's name is logged. A resource **with** a client script must not declare
`dependency "rp_gangs"` (this manifest is delivered to clients).

## Events (host bus)

```lua
AddEventHandler("rp_gangs:changed", function(playerId, gang) end)      -- gang is nil when the player left
AddEventHandler("rp_gangs:war", function(zone, attacker, defender, phase, detail) end)
-- phase: "start" | "tick" | "end"
-- detail (tick): { attackerScore, defenderScore, attackerInside, defenderInside, secondsLeft }
-- detail (end):  { attackerScore, defenderScore, winner | nil, reason = "time" | "resource_stopping" }
```

Raised **to** other resources: `rp_ncpd:alert (kind, position, text, byPlayerId)` with kinds
`robbery`, `gang_war`, `racket`. Consumed: `rp_zones:entered`, `rp_ncpd:arrest`,
`rp_fixer:gig`, `rp_jobs:changed`, `onNpcInteracted`.

Internal net events (`rp_gangs:clientReady`, `rp_gangs:self`, `rp_gangs:roster`,
`rp_gangs:buyers`, `rp_gangs:rob`) are this resource's transport, not an API.

## Items

`drug_pack` (Drug pack, 0.2 kg, **illegal**, not usable) is declared in `rp_inventory` through
`exports.rp_inventory:define` from this resource's `onResourceStart` and again whenever
`rp_inventory` restarts. `synthcoke` and `implant_box_*` are `rp_inventory` / `rp_ripperdoc`
items and count as contraband in a robbery because `rp_inventory` flags them `illegal`.

## Persistence

Created inside `Open77.database.ready(...)` with `CREATE TABLE IF NOT EXISTS`, permission
`database.access`, rows keyed by `Open77.players.identifier` (never the session id):

```sql
rp_gangs_members (
    identifier VARCHAR(64) PRIMARY KEY,
    gang       VARCHAR(32) NOT NULL,
    `rank`     TINYINT     NOT NULL DEFAULT 0,   -- 0 member, 1 lieutenant, 2 boss
    joined_at  BIGINT      NOT NULL DEFAULT 0,   -- unix seconds
    INDEX (gang)
)
rp_gangs_influence (
    zone   VARCHAR(32) NOT NULL,
    gang   VARCHAR(32) NOT NULL,
    points INT         NOT NULL DEFAULT 0,
    PRIMARY KEY (zone, gang)
)
```

A member's row is read on `onPlayerReady` (`.await`, in the handler) and for everyone
connected on a hot start; the influence table and the per-gang head counts are read once at
boot. Every change is written through with the callback forms, so the exports never touch the
database. A failed SQL read is never treated as "no gang": the player is told to reconnect.

**No database** (`ready` answers `database_unavailable`, or nothing answers within 15 s):
`Open77.kvp` (`member:<identifier>` = `gang|rank`, `count:<gang>`, `inf:<zone>:<gang>`), and
the log says `[rp_gangs] store=kvp reason=...`.

Wars, cooldowns and the buyer NPCs are in memory only: a resource stop ends every war
(`reason = "resource_stopping"`, the score decides) and removes the buyers.

## Log (grep-able)

```text
[rp_gangs] started: 7 gangs, 4 territories, tribute 50 eddies per zone every 10 min, war 5 min, deal 80 eddies
[rp_gangs] items registered in rp_inventory: 1 (rejected: 0)
[rp_gangs] store=sql tables=rp_gangs_members,rp_gangs_influence
[rp_gangs] territories: blackmarket=none afterlife=none nomad_camp=none scrapyard=none
[rp_gangs] buyer spawned zone=blackmarket npc=... at 397.0 -2393.0 182.0
[rp_gangs] buyer prompt declared (Street deal)
[rp_gangs] player 1 gang=maelstrom rank=2 (founded)
[rp_gangs] deal player=1 zone=blackmarket gang=maelstrom +80 cash=580 via=command
[rp_gangs] influence blackmarket maelstrom +1 -> 1 (deal by player 1)
[rp_gangs] zone blackmarket holder=maelstrom (was nil)
[rp_gangs] tribute player=1 gang=maelstrom zone=blackmarket +50 cash=630
[rp_gangs] robbery robber=1 victim=2 cash=150 items=1
[rp_gangs] war start zone=scrapyard attacker=maelstrom defender=scavs by=1 minutes=5
[rp_gangs] war end zone=scrapyard attacker=maelstrom defender=scavs score=6-4 winner=maelstrom (time)
```

## Manifest

Permissions: `network.events`, `database.access`, `world.npcs`, `players.animations.read`
(the hands-up read; the devkit card lists no permission check for `Open77.animations.current`,
the guide says it needs this one — declared to be safe), `ui.nameplates` (client).
Dependencies: `open77_contextmenu`, `open77_interactions`, `open77_notifications` (all three
ship a client half). `rp_zones`, `rp_jobs`, `rp_inventory`, `rp_economy`, `rp_ncpd`,
`rp_housing`, `rp_identity`, `rp_fixer` and `open77_rp_basics` are server-only and reached
through `pcall`: each degrades to a chat line or a log line when missing.

## Test in 2 minutes (one player)

At the freeroam spawn `381.36, -2401.79, 181.99`, id `1`, jobless; `rp_zones`,
`rp_inventory`, `rp_economy` running (`rp_jobs`, `rp_identity`, `rp_ncpd`, `rp_fixer`,
`open77_rp_basics` optional). Log on start: `started: 7 gangs, 4 territories ...`,
`store=sql ...`, four `buyer spawned` lines and `buyer prompt declared`.

1. `/gang` → `You run with nobody. /gang creer <gang> to found one...` and the seven gangs
   with `0` members.
2. `/gang creer maelstrom` → `You founded the Maelstrom. You are the boss...`, a toast, and
   everyone reads `Word on the street: <name> now runs the Maelstrom.` `/gang creer scavs` now
   answers `You already run with the Maelstrom.`
3. `/gang` → `Maelstrom - boss. 1 member(s), 1 online: <name> [boss]` then `Territories held:
   none. Tribute 50 €$ per zone every 10 min.`
4. `/territoire` → four lines, every one `held by nobody ... no influence yet`.
5. Console: `giveitem 1 drug_pack 2` → `Drug pack x2` in the pockets (`/inv`, flagged illegal).
6. Walk 22 m north-east to the black market ring (400, -2390): a Maelstrom-looking NPC stands
   at 397, -2393 with a **Street deal** marker. Look at him within 2.5 m and press **E** (or
   type `/gang vendre` within 4 m) → `Deal done in Black Market: +80 €$ cash (...). Maelstrom
   influence +1.`, a toast, and everyone reads `Maelstrom now runs Black Market.` Press **E**
   again → `The buyer is counting eddies. Come back in 59 s.` Wait a minute, sell the second
   pack → influence 2. A third press → `Nothing to sell. Bring a drug pack.`
7. `/territoire` → `Black Market (blackmarket): held by Maelstrom. Top: Maelstrom 2`.
   `/gang` → `Territories held: Black Market.`
8. `/guerre blackmarket` → `You already hold Black Market. Nothing to take.`
   `/guerre scrapyard` → `Nobody holds Scrapyard: deal there and take it with influence.`
9. Walk 40 m to the Afterlife ring (360, -2390) and `/gang vendre` without a pack → `Nothing
   to sell.`; walk out of every territory → `No street market here. Find a territory
   (/territoire).`
10. Wait for the tribute tick (10 min, or lower `tributeIntervalMs` in `shared/config.lua`)
    → `Tribute from Black Market: +50 €$ (cash ...)`, log `tribute player=1 ...`.
11. Reconnect → `Welcome back to the Maelstrom, boss.`; `/territoire` still shows the two
    points (SQL).

**Two players** (ids `1` boss, `2` citizen): `/gang recruter 2` from 10 m → `Too far away
(10 m)...`; within 5 m → both told, player 2 sees `[MAELSTROM] <name>` over player 1 and vice
versa. Console `setjob 2 ncpd 0` → player 2 reads `You took a day job (ncpd): the Maelstrom
cut you loose.` For a robbery: player 2 raises hands (`handsup` RP profile) or is cuffed by an
officer with the kit; console `giveitem 2 synthcoke 2`; player 1 holds **ALT**, clicks player
2, **Rob** (or `/gang depouiller 2`) → `You robbed <name>: 150 €$, Synthcoke x2.`, the victim
is told, on-duty officers read `[NCPD DISPATCH] ROBBERY: ...`. Without hands up → `They are
neither cuffed nor surrendering.` For a war: console `setgang 2 scavs 2`, player 2 sells a
pack at the scrapyard (Scavs hold it), player 1 `/guerre scrapyard` → both crews are told,
every 30 s the score line, after 5 min `WAR OVER: the Maelstrom take Scrapyard (10 - 0). +10
influence.` when only player 1 stood in the zone.
