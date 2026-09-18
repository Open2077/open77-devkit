# Common rules for the Night City RP build (read fully before starting)

You are writing ONE Lua resource for the Open77 platform (a Cyberpunk 2077 multiplayer
framework, FiveM-like: manifest `open77.lua`, `server_script` / `client_script`, natives under
`Open77.*` plus FiveM-shaped globals). Your ONLY source of truth is the Open77 Devkit MCP,
driven through this harness (one call per invocation, run from any directory):

    node "C:/Users/Wodman/AppData/Local/Temp/claude/C--Games-cyberm/47b3b407-f916-4dcf-a69e-303889c762ee/scratchpad/devkit-eval2/mcp-call-012-76.mjs" "C:/Games/cyberm/rp-scripts" <tool> '<json args>'
    node ... "C:/Games/cyberm/rp-scripts" list
    node ... "C:/Games/cyberm/rp-scripts" open77_search '{"query":"give money to a player","runtime":"server"}'
    node ... "C:/Games/cyberm/rp-scripts" open77_api '{"name":"server:Open77.players.name"}'
    node ... "C:/Games/cyberm/rp-scripts" open77_guide '{"slug":"server-exports"}'
    node ... "C:/Games/cyberm/rp-scripts" open77_validate '{"resource":"C:/Games/cyberm/rp-scripts/<your resource>"}'

Pass JSON args in single quotes; for arguments containing quotes, write the JSON to a file
and pass `@C:/path/args.json`. Each call takes 5-15 s. The MCP answers for server build
**2.31.13+op77.76**, the build the resource runs on. `open77_data` takes `catalogue` (one of
vehicles, weapons, items, npc-templates, props, vfx, sfx, animations, animsets) and `query`.

## Hard rules

1. Do NOT read any file under `C:\Games\cyberm` other than your own resource directory and the
   sibling resources this file names as your dependencies (their README.md and open77.lua only,
   to read their exports). No web search. Do not start, stop or talk to any server or game
   process. Do not run git.
2. Start with `list`, then `open77_guide README`, then search. Read the card (`open77_api`) of
   EVERY native you call: permission, reasons, since, runtime side. Declare in the manifest
   exactly the permissions the cards require. A native the MCP says is unavailable on op77.76
   must not be used.
3. Server-authoritative: the server decides money, items, jobs, spawns; a client only renders
   and requests. Every native that returns `nil, reason` / `false, reason` is checked and the
   player is told why in chat (English, short). Player-facing text in **English**, cyberpunk
   tone (eddies / €$, choom, NCPD, Trauma Team, ripper, chooh2, Delamain, Night City...). Code
   comments in English. UTF-8 without BOM, LF, 4-space indent, Lua 5.4.
4. Persistence: **SQL first**. The server exposes `Open77.database.*` (cards: `open77_api server:Open77.database.query`,
   `.single`, `.scalar`, `.insert`, `.update`, `.ready`, `.isReady`, `.transaction`; the same table is
   the oxmysql-compatible `MySQL` global; guide `server-api#database` and `#waiting-for-the-database`): create your tables inside `MySQL.ready(function() ... end)` with
   `CREATE TABLE IF NOT EXISTS`, use the `.await` forms inside handlers, key rows by the durable
   `Open77.players.identifier(playerId)` (never the session id), declare the permission the
   cards require (`database.access`). Table names are prefixed by your resource name
   (`rp_identity_citizens`). Fall back to `Open77.kvp` ONLY if the database is not ready
   (`MySQL.isReady()` false), and say so in the log. Nothing may crash on a missing row or a
   departed player.
5. Host lifecycle events (`onPlayerReady`, `onPlayerDisconnected`, ...) deliver every argument
   as a STRING: `tonumber` before handing an id to a native that wants a number
   (`Open77.chat.send` refuses strings). In `RegisterCommand` / `RegisterNetEvent` handlers,
   `source` is a number (0 = server console: refuse politely). `args` are strings.
6. `Open77.chat.*` and `TriggerEvent` answer `resource_preparing` at the top level of a script:
   put them in `AddEventHandler("onResourceStart", ...)` (check the name is your own), commands
   or event handlers. Publish chat command suggestions on `chat:ready` (`RegisterNetEvent`,
   `source` is the player, no arguments) and once from `onResourceStart` with `-1`.
   `Open77.notifications.*` and `TriggerClientEvent` work anywhere.
7. Sandbox: no `os`, `io`, `require`, `load`, `debug`. Wall clock `Open77.time.unix()`, elapsed
   `Open77.time.monotonic()`, `math.random` available. `Open77.npcs.create` wants a numeric
   `damagePolicy` (2 = invulnerable) despite what the card shows.
8. Cross-resource calls: server exports, called synchronously as `exports.<resource>:<name>(...)`
   inside `pcall` (they raise when the resource or export is missing). Declare
   `dependency "<resource>"` for every resource whose exports you call — EXCEPT when your
   resource has a `client_script`: a manifest delivered to clients cannot depend on a
   server-only resource (the session fails with `missing_dependency`); then omit the
   dependency and rely on `pcall`.
9. Player-to-player actions (give, search, cuff, heal, show ID, pay...) go through the
   platform's ALT+click context menu when they target another player: `open77_contextmenu`
   client exports `register` (read the `context-menu` guide) and the accept/decline flow of
   `open77_player_interactions` when the target must consent. A slash command with an explicit
   player id is the fallback, always provided too.
10. Command names must not collide with the platform's. Already owned (served silently by the
    first registrant, yours would never run): announce appearance ban barber bring car clear
    deathmatch.* dm dm.* dv elevator.* fly forcedoor freeroam freeroam.* fuel fuel.* fx gender
    god goto gun heal help id kick locations loot loot.* maptp noclip noclip.speed
    notification.test npc.* perspective players playerstate playerstate.* prop props
    pursuit.vehicle refuel revive rp.free rp.held spawn suicide tp tpc uikit.demo unlockdoor
    vehicle.* wardrobe weapon.* weapons weather weather.* — plus every command of the RP
    resources already delivered (see the contracts below). Prefix nothing; pick another word.
11. Run `open77_validate` until OK with 0 errors. Then break the resource once on purpose
    (wrong-side native, unknown native, missing permission) to confirm the validator sees it,
    and restore.
12. Deliverable under `C:\Games\cyberm\rp-scripts\<resource>\`: `open77.lua`, `server/main.lua`,
    optionally `client/main.lua`, and `README.md` in English: what each command does, the
    exports and events, and a "Test in 2 minutes" walkthrough. Hand back a report: (a) commands,
    (b) exports/events, (c) every MCP call (tool + args + one word), (d) where the MCP was wrong,
    ambiguous, missing or made you guess, (e) the final `open77_validate` output verbatim,
    (f) the file contents. Report only; do not test on a server.

## Delivered resources and their contracts (respect the names exactly)

- `rp_economy` (cash): exports `getBalance(playerId)`, `add(playerId, amount, reason)`,
  `remove(playerId, amount, reason) -> newBalance | nil, reason`; event `rp_economy:changed`
  (playerId, newBalance, delta, reason). Commands `money pay givemoney payday`.
- `rp_jobs`: exports `getJob(playerId) -> name|nil`, `hasJob(playerId, name)`; event
  `rp_jobs:changed` (playerId, name|nil). Jobs today: `livreur taxi mecano medecin police`.
  Commands `jobs job mission stopmission`.
- `rp_shop`: `shop buy sell`. `rp_chat`: `me do ooc w dice showid`. `rp_medic`: `soin reanimer
  911 medic`. `eval_taxi`: `taxi`.

## Phase 1 contracts (the resources being written together; use exactly these)

- `rp_identity`: exports `get(playerId) -> { firstName, lastName, birth, sex, origin } | nil`,
  `fullName(playerId) -> string` (falls back to `Open77.players.name`), `isRegistered(playerId)`;
  event `rp_identity:changed` (playerId). Commands `carte civil` ("register" flow is a menu).
- `rp_inventory`: item definitions in a Lua table (`id, label, weight, usable, illegal`);
  exports `has(playerId, itemId, count)`, `add(playerId, itemId, count) -> true|nil, reason`,
  `remove(playerId, itemId, count) -> true|nil, "not_enough"|reason`, `count(playerId, itemId)`,
  `list(playerId)`, `openStash(playerId, stashId, capacity)`; events `rp_inventory:changed`
  (playerId, itemId, delta), `rp_inventory:used` (playerId, itemId). Commands `inv give use
  drop ramasser fouiller`.
- `rp_bank`: exports `getAccount(playerId)`, `deposit(playerId, amount)`, `withdraw(playerId,
  amount)`, `transfer(fromPlayerId, toIdentifier, amount)`, `society(name) -> { balance }`,
  `societyAdd/societyRemove(name, amount, reason)`; event `rp_bank:changed`. Commands `bank
  solde virement`. The payday of `rp_economy` is NOT changed by you.
- `rp_needs`: export `get(playerId) -> { hunger, thirst, fatigue }` (0..100); event
  `rp_needs:changed` (playerId, hunger, thirst, fatigue). No commands beyond `/needs` (debug).
