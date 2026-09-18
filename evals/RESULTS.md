# Eval results, 2026-09-16

Build under test: server built from base `167dfbc9` (av-fix-merge, wire 1.35, the commit of the
deployed client DLL), index `2.31.13+op77.69`. Resources written by a headless agent with only
the Devkit MCP attached (`samples/`).

| Task | Static gate | Server `--lint` | In-game |
|---|---|---|---|
| taxi-job | PASS | OK | **driven, one-client probes 08:5x–09:0x**: a real user waypoint placed on the world map (`harness/eval_harness` opens it in pick mode, the vanilla right-click tracks the pin), `/taxi` read it, the server spawned the Delamain, attached the driverless AI, seated the player (`proof-boarded.png`, marker 150 m ahead), elected the client as simulator and ran the drive task; the car never moved (0 km/h) in three placements, so **arrival is not proven**; see below |
| cuff-escort | PASS | OK | **one unattended two-client run, 07:55–07:58**: cuff held (`serverFrozen=yes movementHeld=yes`, pose `stand__2h_up__03__look_around__01`, 0 m under a 1.5 s forward push after a 5.45 m control walk); escort tether kept B at 1.73 m after the officer walked 14.07 m in 4 s |
| shop-webui | PASS | OK | **driven by keyboard, one-client run 08:05**: F6 opened the page, Tab-Tab-Enter pressed the first Buy, the server logged `player 5 bought maxdoc for 250` and the page showed the balance fall from 1000 to 750 E$ (`samples/eval_shop/proof-purchase.png`) |
| pvp-round | PASS | OK | same run: both players joined one non-default routing bucket (4300) and left it |
| fivem-port | PASS | OK | **driven, one-client run 08:10**: `/car hella` delivered a vehicle, `/cars` opened the ported uikit menu listing it at 3 m (`samples/eval_port/proof-menu.png`), Enter picked it and the server placed the player in `seat_front_left` (`char.state vehicle=yes`) |

The run logs are `harness/gate-run-2026-09-16.log` and `harness/pages-run-*.log`; the gate
script and its probes are in `harness/`, with the eval server config (`server.eval.jsonc`, `<eval-run-dir>` is where the
samples are copied). They call the Open77 base checkout's `scripts/agent-play.ps1`,
`game-input.ps1`, `debug-bridge.ps1` and `launch-extra-client.ps1`.

## What the in-game runs found

- **A real resource defect the validator missed**, then caught: the cuff resource called
  `Open77.input.blockAll` without declaring `input.blockAll`; the runtime refused it
  (`permission_denied:input.blockAll`). The guard extractor's permission pattern was
  lowercase-only and hid every camelCase permission (`input.blockAll`,
  `world.clearArea.foreign`). Fixed in base `wiki/tools/api_guards.py`; `open77_validate`
  now reports the missing declaration.
- **Five gate runs failed the cuff for a platform reason, not a resource one.** Freeroam's
  `/goto arena` is a kill-and-respawn onto the join spawn point, and two solid bodies on one
  point are shoved apart by the engine at ~2.6 m/s in lockstep (the stacked-spawn shove
  Pursuit fixed with spawn slots). A server freeze (`GameplayRestriction.NoMovement`) zeroes
  input, not an external push, and the 0.5 m `moved` watchdog cancels the pose; so the
  server logged the cuff as applied while the body kept drifting. The gate now co-locates
  through Warden (`teleport` A 3 m off the spawn, `bring` B to A's side at 1.6 m) and waits
  for both bodies to stand still before any hold. A resource that cuffs right after a
  teleport onto another player will see the same thing in production.
- **Warden's `frozen` flag is not where a server freeze shows**; `movement.lock.state` counts
  only client-side `Open77.character.movementLock` calls. The freeze is a life flag, read on
  the client as `life.state serverFrozen=`.
- **The server's life phase reaches Alive a few seconds after the client does**; a Warden
  teleport asked in that window is refused `player_not_alive`. The gate retries on that reason.
- **Client-side commands are invisible to the server log.** `/cars` is a client
  `RegisterCommand`; a send verified against the server's `executed` line reads as lost and
  the retry's Escape closes the menu it had just opened. Verify those by their effect.
- **Two-client harness lessons** (all in `harness/`): one 1920x1080 client takes ~6.7 GiB of
  VRAM, so two need 1280x720; a window that just gained focus drops the first keystroke
  (500 ms settle); `chat.say` bypasses the chat composer so client commands need real keys,
  `/` must be the keypad divide on AZERTY, and `-`/`.` cannot be typed at all; every chat send
  is verified against the server's `executed` line and resent once; the chat box closes itself
  on a send (an extra `esc` opens the Open77 pause menu); an escort verdict must check that
  the officer actually moved.

## Not proven

- **The taxi's arrival.** Everything the resource does is proven in-game: the waypoint read,
  the vehicle, the AI driver, the boarding, the `driveTo` acceptance, the simulator election
  (`authority vehicle=… owner=<passenger>`) and the `blocked` handling ("Traffic ahead" on the
  arena plaza). What never happened is motion: on this build (167dfbc9, wire 1.35) the
  driverless Hella stayed at 0 km/h for 240 s from the arena plaza, from a city street
  (`taxi-run-city-2026-09-16.log`, destination 150 m ahead on the road) and from the vehicle-AI
  guide's own validated point 430,-2370 (`taxi-run-validated-point-2026-09-16.log`). The guide
  marks networked vehicle AI as a Developer Preview with one validated route; this is a
  platform finding for the base repo, not a defect of the eval resource.
- **Harness lessons from the taxi**: `Open77.map.getWaypoint` reports only a pin the player
  placed on the map UI (CustomPositionVariant); a pin from `Open77.blips.setWaypoint` is
  classified `resource` and is invisible to it by design. `Open77.map.pickPoint` plus the
  vanilla right-click is the one automatable route, and it closes the map itself, which
  matters: a hub menu left open on the passenger's client keeps the vehicle at 0 km/h, the M
  key does not reliably close it and Escape is eaten. Keypad minus (`kpminus` in
  `game-input.ps1`) types `-` where the character path cannot.

## Hosted endpoint from claude.ai (2026-09-16 17:15)

`mcp.open2077.net` resolves through Cloudflare (proxied), `GET /healthz` answers 200 over
HTTPS, and `POST /mcp` answers `initialize` with server `open77-devkit 0.1.0`. Added as a
custom connector on claude.ai (no authentication, auto-detected): claude.ai listed the twelve
read-only tools, and one chat prompt produced, through two approved tool calls, "Build
2.31.13+op77.69" and the `Open77.players.setFrozen` card with its `players.life.freeze`
permission and `since 2.31.13+op77.67` (`harness/proof-claude-ai-hosted.jpg`). One Cloudflare
default rule blocks the `Python-urllib` user agent with a 403; Node, browser and Anthropic
agents pass.

## Round 2, 2026-09-16 18:00–19:30: four agents, the published package, a stock server

Four subagents were given only `@open2077/mcp@0.1.0` from npm (driven over MCP stdio by
`harness/mcp-call.mjs`, pointed at the extracted release-75 archive), no repository, no web,
no server access, and one task each. The resources are in `round2/`.

| Resource | Task | MCP calls | `open77_validate` | On a private stock release-75 server, through the MCP's live tools |
|---|---|---|---|---|
| `eval_whereami` | `/whereami` position + vehicle, F9 client key | 45 | OK first try | started; console refusal correct |
| `eval_skyadmin` | `/settime` `/setweather` `/sky`, ACL-gated, broadcast | 41 | OK first try | started; `/settime 21` → 21:00, `/setweather rain 5` → 4 s transition, `/sky` right |
| `eval_garage` | `/park` `/garage` `/unpark` with real vehicle records | 37 | OK first try | started; console refusals correct |
| `eval_port2` | port of a FiveM heal/dv/ping-pong/F5 resource | 73 | OK first try | added at runtime (`refresh` + `ensure`), generation 2 |

Each agent also broke its resource on purpose three times; the validator named the wrong-side
native, the not-in-build native and the undeclared permission every time, with line and fix.

**What the round found, and what changed because of it** (base #24, app #2, devkit 0.1.1):

- `Open77.notifications.broadcast` answered `permission_denied:network.events` live while its
  card said none and the validator passed it. Prelude natives that emit to clients never named
  the gate. The extractor now reads the exact Lua literal, follows one helper and inherits
  `network.events` (36 cards); expression-bodied C# gates (`CanUseVehicles() => …`) are read,
  so every vehicle/npc/elevator/loot/prop read carries its `world.*` permission (40 cards); the
  hand-carded vehicles namespace goes through the same reader. `open77_validate` on
  `eval_skyadmin` now fails with exactly that missing permission.
- `open77_guide` refused the `slug#section` refs that search and cards print (3 of 4 agents lost
  calls); it accepts them, matches headings loosely and lists sections on a miss.
- `open77_search "spawn vehicle"` returned guides only: camelCase names never matched a word.
  The tokenizer splits identifiers, folds plurals, and cards alternate with guide sections.
- `open77_fivem_equivalent` answered nothing for `SetEntityHealth`, `GetVehiclePedIsIn`,
  `DeleteEntity`, `IsControlJustReleased`; it now searches the words of the name.
- `Open77.vehicles.seats/flags/doors/windows/occupantFlags` "did not exist"; they are constant
  cards now. Lifecycle events (`onPlayerReady`, `onResourceStart`, `playerDropped`, `chat:ready`,
  92 in all) are in the events catalogue (`open77_events prefix=lifecycle`).
- Cards corrected against the source: `RegisterKeyMapping` returns `(true, key)|(false, reason)`;
  `acl.isAllowed/roles` take a player id; chat `color` is a positional array (a keyed table is
  silently ignored by the UI); `players.stats.apply` is the catalogued name; the `create`
  example used a record that does not exist; seat tables list their fields; client-reaching
  calls answer `resource_preparing` at chunk top level (`chat.addSuggestions` at start, seen
  live).
- A stock server lists its resources by name in `resources.load`; `refresh` never re-reads
  `server.jsonc`, so a new name needs a restart (seen live: `Resource 'eval_whereami' was not
  found` after `refresh`). The guide, the skill and `open77_new_resource` say so now.
- The app never sent the `docs-synced` dispatch the index workflow listens for; app #3 adds it
  (needs `DEVKIT_DISPATCH_TOKEN`).

Not changed: `open77_data` has no enum for weather presets (they live in the guide prose), and
the reason lists of `setTime`/`setWeather` differ between card and guide section.

## Round 3, 2026-09-16 20:00–21:40: two agents on 0.1.1, then a probe on the server

Two subagents, `@open2077/mcp@0.1.1` only (`harness/mcp-call.mjs`), one task each; the
resources are in `round3/`. Both validated clean on the first pass and ran on the private stock
release-75 server through the MCP's live tools (`refresh`, `ensure`, `announce`, `motd`, `lock`,
`whosin`; console refusals correct, no runtime error). What they reported wrong or ambiguous was
then **measured** with `round3/probe-op77.75.lua` (a resource that prints what each call answers
at chunk top level, in `onResourceStart` and from a command) before anything was rewritten.

| Resource | Task | MCP calls | `open77_validate` | Live |
|---|---|---|---|---|
| `eval_announce` | admin `/announce` toast + chat, `/motd`, suggestions on `chat:ready` | 44 | OK first try | started; `announce` reached toast + chat, `motd` printed |
| `eval_carlock` | `/lock` `/whosin` on the caller's vehicle, `onPlayerLeftVehicle` | 40 | OK first try | started; console refusals correct |

**Measured on op77.75** (each line is the probe's output, not a reading of the source):

- `Open77.chat.broadcast / addSuggestions / send` at chunk top level → `false, resource_preparing`;
  `Open77.notifications.broadcast` and `TriggerClientEvent` at top level → **work**. The
  0.1.1 cards said the opposite for notifications.
- `Open77.chat.send("1", …)` → `false, invalid_chat_target`: a string id is refused, and every
  host event (`onPlayerReady`, `onPlayerDisconnected`, …) delivers string ids. The identity
  guide's own `onPlayerReady` example did exactly that.
- `os`, `io`, `debug`, `package`, `require`, `load`, `loadfile`, `dofile`, `collectgarbage` →
  nil; `math`, `string`, `table`, `utf8`, `coroutine`, `json` present (`math.type` too).
- `Open77.vehicles.flags.paintApplied` = 512; `occupantInSeat(unknown, "driver")` →
  `nil, "vehicle_not_found"`; `getPlayerSeat(unknown)` → a single `nil`.
- `RegisterCommand` handler: `source` is a number (0 = console), `args` is `table.pack` of
  **string** tokens (`args.n`), `raw` is `name arg arg` without the `/`; the console splits on
  spaces only (quotes stay literal), chat splits shell-style.

**What changed because of it** (base #25, app #4, devkit 0.1.2):

- The constant tables (`Open77.vehicles.seats/flags/…`) read "NOT AVAILABLE on op77.75
  (unreleased)" while every guide used them: the release surface never listed a table of
  scalars. They carry `since op77.45` now, and `open77_validate` checks a dotted reference that
  is not a call (`Open77.vehicles.flags.locked`, `local send = Open77.chat.send`) the same way
  it checks a call — both agents had guarded the tables with `pcall`.
- `TriggerEvent`, `Open77.chat.*`, `Open77.events.emit*` listed none of the bus refusals
  (`resource_preparing`, `event_queue_limit`, `invalid_event_name`, …); the readers follow the
  `EventFailure(...)` helpers, tuple returns, the array-registered bus doors, the
  `local eventTrigger = __open77_trigger_event` aliases, and a member that returns another
  member. `Open77.chat.broadcast` (which "lists no reasons while claiming to be exactly
  send(-1)") now carries `send`'s.
- `open77_events` showed payloads for 4 of 92 lifecycle events, one of them wrong
  (`onResourceStart (resourceName, revision)` was the neighbouring bus row's). 76 of 92 carry a
  payload; a table row feeds only the events in its first cell, prose signatures and handler
  parameter lists fill the rest. `chat:ready` is documented (client net event, no arguments,
  `source` = the player).
- `open77_validate` accepted `os.time()` and `require`; it names each absent library and
  function with the replacement (`Open77.time.unix()`, more `server_script` lines), and on the
  client side `setmetatable` / `coroutine.create`. It warned that the notifications guide's
  `dependency "open77_notifications >=1.0.0"` "is not a resource slug": the runtime grammar
  (`name`, then `>=`/`<=`/`>`/`<`/`=`/`==` constraints) is parsed, and a malformed constraint is
  an error.
- `open77_search "register command admin only restricted"` ranked the client `RegisterCommand`
  above the server one; a side named in the question is now a filter, and the tool says so.
- `open77_changes to=main` lists what exists on main and in no published build; a card prints
  "reasons: none found in the handler" instead of omitting the line, and a description equal to
  the summary is not printed twice (`GetCurrentResourceName`, now `shared`).
- `server-api#resource-lifecycle-events` returned 40 lines of cyberware/dash/reflex prose: the
  guide filed five feature summaries and the namespaced-equivalents table under that heading.
  They have their own headings, and the guide has a "What the sandbox provides" section.
- The manifest schema lacked `exports` / `server_exports` (A20), which made
  `extract-schemas.py` refuse to run.

Not changed: whether a server toast sent at `onPlayerReady` is queued or lost while the client
WebUI is still coming up (the agent waited 3 s by analogy with the identity guide); whether
`tostring(integer id)` equals the event's string id is asserted in the seat card from the host's
`ToString()` and not measured with a real vehicle.

## RP round, 2026-09-17 03:50–04:40: five agents write a roleplay server's basics on 0.1.2

Five subagents, `@open2077/mcp@0.1.2` only, one resource each, with a shared contract for the
cross-resource exports (`rp-round/PROMPT-COMMON.md`): `rp_economy` (wallet, payday, exports),
`rp_jobs` (five jobs, courier mission with a spawned car, GPS waypoints and paid deliveries),
`rp_shop` (consumables, weapons through the `open77_weapons` relay, vehicles, resale), `rp_chat`
(`/me` `/do` `/ooc` `/w` `/dice` `/showid` with proximity audiences), `rp_medic` (paid heal /
revive gated by the job, `/911`, `/medic`). All five validated OK first pass, compile with the
server's own Lua (`--lint`), start on the eval server (op77 3ca1ca66, client 76) and answer every
command from the console; `rp-round/rp_selftest` exercises the exports across VMs (8/8). The
player-side paths wait for a client (the owner's was up all night). 40–49 MCP calls per agent.

What the round found:

- **Command names collide silently**: `/heal` belongs to `open77_admin` and `/revive` to
  freeroam; a name registered by two resources is served by the first, with no error. The medic
  verbs became `/soin` / `/reanimer`. Nothing in the MCP lists the names the platform already
  owns — `open77_validate` should (from the resources the server dir loads).
- `open77_events` said `chat:ready` had no documented payload (events.json predated the chat.md
  row; regenerated, base #28). `Open77.time.monotonic` / `runtime.luaVersion` / `state.clear`
  carried ~50 unrelated reasons (one-line table members read with the indentation reader;
  fixed). The server-exports guide contradicted the `TriggerEvent` card (VM-local vs host bus;
  fixed). Six examples passed a host-event string id to `chat.send` (fixed).
- `open77_data` never named its `catalogue` argument (two agents lost a call); it does now, and
  says which vehicle records are player-spawnable.
- No server card for the `exports` registration global (guide prose only); `players.get().ready`
  and `players.all()` element type undocumented (integers, measured); the `parameters` shape of
  chat suggestions was a FiveM guess (now documented); `players.stats.read` /
  `players.life.read` say "enforced by: client" while gating server natives.
- `since` moved on thirty client cards when the surface history was rebuilt after a reader
  change: main had been fast-forwarded onto a branch that merged main, and the `--first-parent`
  walk no longer resolved release dates to the commits the builds were cut from. Release commits
  are pinned in the history file now (base #28).

## RP phase 1, 2026-09-18 04:40–05:50: four agents on SQL, played end-to-end by a bot client

Four subagents, MCP-only again, one resource each, on a second contract
(`rp-round/PROMPT-COMMON-v2.md`: SQL first through `Open77.database.*`, table prefix per
resource, the client-manifest dependency rule, the context menu for player-to-player actions,
the platform's command names): `rp_identity` (civil registry form, `/carte`, `/civil`, Show ID
context action, RP nameplate), `rp_inventory` (weighted pockets, 17 items in a Lua table, use /
drop as ground loot / pick up / give / search / seize, stashes by export), `rp_bank` (accounts,
ATM POIs with map pins and an E prompt, deposit / withdraw / wire / statement, societies),
`rp_needs` (hunger / thirst / fatigue with effects, `consume` export). A MariaDB container was
provisioned for the eval server first (connection string injected from a local env file, never
in a resource). All four validated OK, lint clean, started together on the eval server with the
schema created by `Open77.database.ready`, and — new this round — were played end-to-end by an
agent-driven client: the registration form typed with SendInput, `/carte`, `/needs`, `/solde`,
the ATM menu (deposit 300, withdraw 100, statement), `/inv` → burrito used (hunger +35 through
`rp_needs`) → water dropped as loot → `/ramasser`, with every step read back from SQL and
surviving a `restart` of the resource. 62–85 MCP calls per agent.

What the round found:

- **The validator contradicts the database cards**: every `Open77.database.*` card and the
  `ready` example use `query.await` / `update.await`, and the guide says `MySQL` is the same
  table, yet `open77_validate` flags `Open77.database.query.await`, `.update.await` and every
  `MySQL.*` spelling as "not in the catalogue" (6 errors on a clean resource). Two agents rebuilt
  the wait from the callback form plus `promise.new()`; one hid the dotted form behind
  `local DB = Open77.database`. The lexical check must accept the documented `.await` sub-forms
  and the `MySQL` alias (0.1.3).
- `open77_api` accepts a `server:` route prefix but not `client:` (the unqualified name returns
  both sides); no server card for `exports(name, fn)` or `print`; `_G` server listing omits
  both; the callback-form failure shape of `Open77.database.update` is unspecified; the
  context-menu guide tells resources to declare `local.events`, which `open77_permissions` says
  does not exist.
- **`open77_worldui` prompts are pressable only within `radius + 0.5 m`** by default
  (`promptDistance`), and only while the projection sits within `focusRadius` of the screen
  centre (`requireLookAt`): the ATM prompt showed at 1.8 m and ignored E until `rp_bank` passed
  `promptDistance = 3`. Neither default is on the worldui card. The prompt's 3D labels also draw
  above UI-kit dialogs (cosmetic, platform).
- `Open77.animations.current` says "requires players.animations.read" in prose and "no
  permission checked" in metadata; the `steps` shape is undocumented (hands-up detection scans
  for the profile id). No consumable catalogue in `open77_data items` (clothing only) — drops
  use the documented `Items.money` record with an RP label, so the native card shows money.
- A DB-enabled server walls every fresh identity in the vanilla character creator, which
  synthetic input cannot finish; seeding one `open77_characters` + `open77_player_appearances`
  row (copied from an existing profile) lets an agent client through — worth a devkit note in the
  database guide.

## RP phase 2, 2026-09-18 05:55–07:45: thirteen job resources, eleven agents, one bot player

Wave A (`rp_jobs` v2, `rp_zones`), wave B (`rp_ncpd`, `rp_trauma`, `rp_delamain`, `rp_mecano`),
wave C (`rp_ferrailleur`, `rp_nomade`, `rp_bar`, `rp_ripperdoc`, `rp_fixer`, `rp_netrunner`,
`rp_vigile`) on the contract `rp-round/PROMPT-COMMON-v3.md` (phase-1 contracts as shipped, the
`rp_inventory:define` / `rp_needs:apply` / `rp_bank:charge` additions, measured map coordinates, the
worldui `promptDistance` rule, the 0.1.3 validator from `C:\Games\cyberm\devkit-013` for waves B/C).
All thirteen validate OK, lint clean with the server binary, and start together on the eval server
with `rp_medic` unloaded. Played by the bot: jobs (setjob → duty → agency menu), zones, NCPD status
+ radio + voice channel, the death flow (down 60 s → hospital respawn billed), mechanic repair /
refuel / paint / tow, the whole scrapper loop (crowbar → wreck → sale), the nomad run up to the
ambush (contract → crate in hand → loaded on the truck → 3 hostile Maelstrom), bar (restock →
mix → drink), fixer board (accept / abandon), netrunner (status, jam), guard (contract, per-minute
pay), Delamain fallback. Two-player paths and the driving legs are left to the owner. 47–111 MCP
calls per agent.

What the round found (platform):

- **Any console or player command with ~50+ tokens killed the dedicated server** (`0xC0000374`,
  no exception, no dump): `LuaResourceRuntime.ExecuteCommand` pushed every token without
  `lua_checkstack`. Reproduced twice with a 24-point `groundz` probe, fixed in base #33
  (`ReserveStack` on every variadic push site, `PushJson` depth reservation, 64-token cap with a
  `WRN`), cherry-picked onto the eval build and re-run: 24 results, server alive.
- **`onPlayerLifeStateChanged` says `dead` on connect and on every admin teleport**: the pristine
  template reports a dead phase 10 ms after the freeroam gate opens, and `open77_admin` `/tp` kills
  with `cause=script`, `weapon=open77_admin:tp` before respawning. A death-driven resource
  (`rp_trauma`) must read `getLifeState().weapon`/`cause` and skip both; the `Open77.players.teleport`
  API moves a living player with no transition. Worth a line in the life guide.
- No vehicle→vehicle attach/tow native; no server-side respawn hold (`onPlayerLifeStateChanged` is
  not cancellable, `open77_death` is read-only); `npcs.tasks.attack` on a player seated in a vehicle
  answers `invocation_failed` (hostile attitude still engages); `Open77.blips` is client-only;
  worldui 3D labels draw above UI-kit dialogs; `open77_interactions` cards resolve at ~4 m but the
  key fired only once the bot stood ~2 m from the vehicle.
- MCP defects (repeated by several agents, for devkit 0.1.4 / base docs): `promptDistance` absent
  from the interactions definition reference; `Open77.playerInteractions.request` says "none
  checked" while requiring `players.interactions.control`; `Open77.players.teleport`,
  `players.wanted`, `database.*` same contradiction; `acl.grant:rp.*` documented by the ACL guide but
  rejected by the validator; seat name vocabulary (`seat_front_left` vs `driver`) contradicts itself
  across cards; `setTransform` transform shape documented two ways; yaw→forward sign undocumented;
  `Open77.notifications.send` card asks for a dependency line no delivered resource needs; no
  AV `_player` record in the catalogue (`Vehicle.av_trauma` spawns fine); the validator ignores
  calls made through a local alias of `Open77.database` (permission check skipped silently);
  `TriggerEvent` nil holes and the callback failure shape remain undocumented.

## RP phases 3–5, 2026-09-18 07:50–09:30: fourteen resources, fourteen agents, the whole server on one eval box

Wave D (`rp_garage`, `rp_shops`, `rp_housing`, `rp_hud`, `rp_radio`, `rp_ambiance`), wave E
(`rp_logs`, `rp_whitelist`, `rp_admin`, `rp_phone`, `rp_gangs`), then `rp_mdt`, `rp_crime`,
`rp_config`, on the contract `rp-round/PROMPT-COMMON-v4.md` (every phase-1/2 export and event as
shipped, the measured plaza coordinates, the client-manifest dependency rule, the 0.1.3 validator).
All fourteen validate OK and lint clean with the server binary; the whole set — 39 RP resources
plus the 45 platform ones — starts together on the eval server on SQL (37 tables). Played by the
bot: dealership purchase → plate → lost vehicle reclaimed → take-out → store (fuel and body state
kept); housing purchase and rent; shop goods, gun licence and a delivered pistol; the HUD; radio
tuning and talk; phone number and UI; gang founding and a black-market deal; the NCPD tablet
(citizen search, card, a record entry written through `rp_ncpd:addRecord`); crime: fencing stolen
parts, jimmying a locked car (NCPD alert + APB), an armed shop robbery (alert + record); ambiance
cycle/weather/extras; admin warn; SQL audit trail; whitelist status; `rp_config` set/get/type
refusal/branch/list/export/unset with a live override applied by `rp_ambiance`. Two-player paths
(keys, SMS, gang war, dealing, crate theft, freeze/spectate, the whitelist gate itself) are the
owner's. 42–103 MCP calls per agent.

What the round found (platform):

- **The client script budget divides by the number of running resources, and platform loops
  die at scale.** `ResourceHost.Tick()` slices 2000 µs by the running-resource count (floor 50 µs);
  the instruction hook fires every 10 000 instructions and kills the resume when the slice is
  spent; a `CreateThread` loop that raises is retired for the session. With ~70 client resources
  `open77_interactions` (every E prompt) and `open77_contextmenu` (ALT+click registration) died
  within seconds of each connect or swap: cards still render from the native anchors, nothing ever
  fires. Base PR in flight (slice floor, phased tick with `Wait(0)` + `pcall`, linear contextmenu
  registry) — opened as base #35; its Lua half was deployed on the eval server the same morning:
  no `budget exceeded` since the swap, `15 context actions registered`, and the housing door /
  stash / front-door prompts fired (the loop is alive at 89 loaded resources). The C++ half (the
  300 µs slice floor) waits for a client rebuild. Until it lands, any RP server past ~40 resources
  loses its prompts.
- **The database bridge caps a statement at 64 positional parameters** (`MySqlMaxParameters`,
  `LuaResourceRuntime.cs`) and 64 KB of SQL, undocumented on the cards: a 50-row batched
  `INSERT` (300 params) answered nil three times and the audit trail dropped 96 rows at every cold
  start. Batches of 10 rows now.
- **A resource whose manifest reaches the client (any `shared_script`) must not `dependency` a
  server-only resource**: the client rejects the *entire* resource set
  (`server resource candidate rejected before swap: rp_crime:missing_dependency:rp_economy`) and
  nothing new is delivered until the manifest is fixed. Loading a shared config as `server_script`
  is the workaround for server-only resources.
- **`refresh` then `restart <name>`**: a `restart` alone re-sends the package the server already
  holds; a client-delivered file change (shared/, client/, web/) only reaches players after
  `refresh`. Any restart swaps the whole set on every client (and re-triggers the budget failure).
- **`Open77.players.identifier(0)` / `name(0)` throw** `id must be positive (Parameter 'value')`
  and kill the resource VM — an audit resource fed a console actor (id 0) by another resource's
  event died and took its dependants down (`dependency_stopped`). Ids must be guarded before every
  player lookup; the natives could answer nil instead.
- **`state.write` is a real permission** (`open77_fuel` declares it, `rp_garage` gets
  `permission_denied:state.write` without it) but `open77_permissions` says it does not exist and
  the validator flags it as unknown. Same family: `local.events` (context-menu guide) does not
  exist on op77.76; `webui.keep_input` (`setFocus` third argument) is not in the list.
- **No webui guide**: `Open77.webui.create` + `WebUI.Page.*` cards only; layer semantics, the
  page-side bridge (`window.Open77.on/emit`), the `visible` contradiction between the card and
  the `open77_new_resource` scaffold, `ui_page` vs `web_ui_page` vs the manifest schema — every
  HUD/MDT/phone agent guessed the same things.
- **No environment-variable API for resources** although the convars guide sends tokens to the
  environment; `rp_logs` had to take its Discord webhook from a convar the operator sets.
- Database: `*.await` and callback failure shapes undocumented (raise vs nil vs never called);
  `LIMIT ?` as a bound parameter undocumented; nil holes in params arrays fail the write silently.
- `open77_data` misses: `npc-templates` answers `.ent` paths with no `Character.*` ids; `vehicles`
  needs the accented display name (`Nazaré`) or the exact record suffix; the VFX alias catalogue
  and the effects guide's 60 aliases are unreachable; `Open77.npcs.speak` takes a voice context, not
  text; the `npcs.create` card shows `damagePolicy = "invulnerable"` while the rules say numeric.
- `Open77.hud.setCinematic` is op77.78+; `open77_vehiclepicker` has no roster guide (unusable for
  a dealership — UI-kit context used); `rp_zones:list()` carries no centres; `Open77.time.monotonic`
  units and `GetResourceState` values unstated; `TriggerClientEvent` card truncated.
- Client E prompts need the card within `distance` of the *player* (not the ring) and the world
  positions must be measured: `groundz` found the cliff under two housing doors and the fence.
