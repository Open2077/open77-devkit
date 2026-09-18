# rp_zones

Named zones for the Night City RP build: an announcement on entry, a server-authoritative
`zoneOf`, safe zones where nobody can be hurt, a map pin per zone and a ground ring around the
small ones. Every job resource (`rp_ncpd`, `rp_trauma`, `rp_mecano`, `rp_delamain`, ...) reads
this resource; it depends on no `rp_*` resource itself.

Build target: **2.31.13+op77.76**. Dependencies: `open77_notifications`, `open77_worldui`.
Permissions: `network.events`, `combat.config`, `ui.vanilla.map`.

## How it works

- **Zones** live in `shared/config.lua` (`Config.zones`): `name`, `label`, `kind`, a shape
  (`circle` = centre + radius + `maxHeight` band, `sphere`, `box`, or `polygon` = points +
  `minZ`/`maxZ`), an optional `announce` text and optional `flags`. Kinds and their flavour
  lines, toast type, blip sprite and ring style are in `Config.kinds`.
- **Detection is server-side.** Every `Config.tickMs` (500 ms) the server reads
  `Open77.players.positions()` once and tests each prepared zone with `Open77.zones.contains`,
  the platform's shared geometry module (planar distance for circles, crossing-number test for
  polygons, the same bytes the client embeds). The exit test carries `Config.hysteresis` metres of
  grace so a player on the boundary does not flap. The client never reports membership.
- **Entry**: a toast (`Open77.notifications.send`) with the zone label and one flavour line per
  kind; `badlands` also writes "Out of NCPD coverage" in chat. **Leaving a safe zone** shows a
  short warning toast.
- **Safe zones** (`kind = "safe"`): a server damage arbiter (`Open77.combat.onDamage`) cancels
  every hit whose victim stands in a safe zone, and — `Config.safe.blockDamageFromInside` — every
  hit whose attacker stands in one. Nothing is toggled on the player, so an admin `/god` is never
  clobbered and nothing leaks when the resource stops.
- **Map**: the client creates one vanilla map pin per zone (`Open77.blips.create`, sprite per kind)
  and, for zones with a radius of at most `Config.ringMaxRadius` (25 m), a native ground ring
  through `open77_worldui` (`create` with no `label`, so no E prompt).
- **No SQL table**: membership is recomputed from live positions every tick; nothing is durable.

## Commands

| Command | What it does |
|---|---|
| `/zones` | Lists every zone with its label, kind and the planar distance from you to its centre, nearest first; the zones you stand in are marked `[HERE]`. |
| `/zone` | The zone you are in (the smallest one, plus the others you overlap), or "Open Night City". |

Both refuse the server console politely.

## Exports (server, synchronous — never yield)

```lua
exports.rp_zones:zoneOf(playerId)   -- { name, label, kind, flags } | nil   (smallest zone first)
exports.rp_zones:isIn(playerId, name)   -- boolean
exports.rp_zones:list()                 -- { { name, label, kind }, ... } in config order
exports.rp_zones:playersIn(name)        -- { playerId, ... } ascending
```

`flags` is an extra field beyond the phase-2 contract (a copy of the zone's `flags` table, empty
when none). Call inside `pcall`: a synchronous export raises when the resource is not running.

```lua
local ok, zone = pcall(function() return exports.rp_zones:zoneOf(source) end)
if ok and zone and zone.kind == "hospital" then ... end
```

## Events (host bus, `TriggerEvent`)

| Event | Arguments | When |
|---|---|---|
| `rp_zones:entered` | `playerId, name, kind` | Raised for **every** zone the player enters (a player can be in several overlapping zones). |
| `rp_zones:left` | `playerId, name, kind` | Raised for every zone the player leaves — including one `left` per zone on disconnect, so consumers' counts stay consistent. |

`playerId` is a number. Handlers registered with `AddEventHandler` receive them.

## Shipped zones

All on the flat band around the freeroam spawn `381.36, -2401.79, 181.99`, measured with
`Open77.world.groundZ` on 2026-09-18 (north of y -2361, south of y -2415 and west of x 335 the
ground drops 20-30 m; east of x 400 at y -2401 there is no ground). Circles, `maxHeight` 15 m.

| Name | Kind | Centre (x, y, z) | Radius | From spawn |
|---|---|---|---|---|
| `spawn_plaza` | safe | 381.36, -2401.79, 182 | 45 m | 0 m (around the spawn) |
| `afterlife` | bar | 360, -2390, 182 | 10 m | 24 m north-west |
| `mecano_shop` | garage | 341, -2401, 180.3 | 10 m | 40 m west |
| `blackmarket` | blackmarket | 400, -2390, 182 | 10 m | 22 m north-east |
| `hospital` | hospital | 400, -2366, 182 | 12 m | 41 m north-north-east |
| `nomad_camp` | camp | 420, -2378, 182 | 9 m | 46 m north-east |
| `ncpd_hq` | ncpd | 440, -2366, 181 | 12 m | 69 m north-east |
| `scrapyard` | scrapyard | 462, -2352, 178 | 12 m | 95 m north-east |
| `badlands` | badlands | 381.36, -2401.79 | 900 m | covers the whole area (no ring) |

Non-overlapping placeholders; the owner moves the city ones to real Night City places by
editing the centres (`/goto` candidates are listed in the config).

## Test in 2 minutes

1. Connect; you spawn inside `spawn_plaza` (and `badlands`). Expect two toasts top-right —
   "Badlands Plaza / No heat in here, choom..." and "Badlands / You're past the city limits..." —
   plus the orange chat line **Out of NCPD coverage**.
2. `/zone` → `You are in Badlands Plaza (spawn_plaza, safe) - also inside: badlands`.
3. `/zones` → nine lines, nearest first; `spawn_plaza` and `badlands` marked `[HERE]`.
4. Open the map: nine pins (a `fast_travel` pin at the spawn, NCPD, meds, bar, tech, junk, black
   market, nomad, outpost around it). Look north-east: rings at the black market (22 m) and the
   hospital (41 m).
5. Walk 45 m in any direction: toast **Leaving Badlands Plaza / You're fair game again, choom**.
6. Walk north-east along the road to 440, -2366 (69 m): toast **NCPD Badlands Outpost / NCPD
   precinct. Badges everywhere...**; `/zone` → `ncpd_hq`. Walk back 15 m: no toast for `ncpd_hq`
   (only safe zones announce their exit).
7. Same with `hospital` (400, -2366), `blackmarket` (400, -2390) and `afterlife` (360, -2390):
   every job zone is reachable on foot.
8. Safe zone check (two players): both stand in the plaza; shoot the other — no health loss. Step
   one player outside the ring, shoot back in — still no damage (victim protected); the inside
   player shooting out — refused too (`blockDamageFromInside`). Both outside — normal damage.
9. Server log shows `9 zone(s) prepared: ...` and `safe-zone damage arbiter installed` at start.
