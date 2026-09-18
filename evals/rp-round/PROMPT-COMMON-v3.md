# Common rules for the Night City RP build — phase 2 (read fully before starting)

You are writing ONE Lua resource for the Open77 platform (a Cyberpunk 2077 multiplayer
framework, FiveM-like: manifest `open77.lua`, `server_script` / `client_script` / `shared_script`,
natives under `Open77.*` plus FiveM-shaped globals). Your ONLY source of truth is the Open77
Devkit MCP, driven through this harness (one call per invocation, run from any directory):

    node "C:/Users/Wodman/AppData/Local/Temp/claude/C--Games-cyberm/47b3b407-f916-4dcf-a69e-303889c762ee/scratchpad/devkit-eval2/mcp-call-013-76.mjs" "C:/Games/cyberm/rp-scripts" <tool> '<json args>'
    node ... "C:/Games/cyberm/rp-scripts" list
    node ... "C:/Games/cyberm/rp-scripts" open77_search '{"query":"cuff a player","runtime":"server"}'
    node ... "C:/Games/cyberm/rp-scripts" open77_api '{"name":"server:Open77.players.name"}'
    node ... "C:/Games/cyberm/rp-scripts" open77_guide '{"slug":"server-exports"}'
    node ... "C:/Games/cyberm/rp-scripts" open77_guide '{"slug":"resource-exports#open77rpbasics"}'
    node ... "C:/Games/cyberm/rp-scripts" open77_validate '{"resource":"C:/Games/cyberm/rp-scripts/<your resource>"}'

Pass JSON args in single quotes; for arguments containing quotes, write the JSON to a file
and pass `@C:/path/args.json`. Each call takes 5-15 s. The MCP answers for server build
**2.31.13+op77.76**, the build the resource runs on. `open77_data` takes `catalogue` (one of
vehicles, weapons, items, npc-templates, props, vfx, sfx, animations, animsets) and `query`.
`open77_api` accepts a `server:` prefix; for a client card use the unqualified name (it returns
both sides).

## Hard rules

1. Do NOT read any file under `C:\Games\cyberm` other than your own resource directory and the
   sibling resources this file names as your dependencies (their README.md and open77.lua only,
   to read their exports and events). No web search. Do not start, stop or talk to any server or
   game process. Do not run git.
2. Start with `list`, then `open77_guide README`, then the guides named in your task, then
   search. Read the card (`open77_api`) of EVERY native you call: permission, reasons, since,
   runtime side. Declare in the manifest exactly the permissions the cards require. A native the
   MCP says is unavailable on op77.76 must not be used.
3. Server-authoritative: the server decides money, items, jobs, spawns; a client only renders
   and requests. Every native that returns `nil, reason` / `false, reason` is checked and the
   player is told why in chat (English, short). Player-facing text in **English**, cyberpunk
   tone (eddies / €$, choom, NCPD, Trauma Team, ripper, chooh2, Delamain, Night City...). Code
   comments in English. UTF-8 without BOM, LF, 4-space indent, Lua 5.4.
4. Persistence: **SQL first** through `Open77.database.*` (cards `server:Open77.database.query`,
   `.single`, `.scalar`, `.insert`, `.update`, `.ready`, `.isReady`; guide `server-api#database`).
   Create your tables inside `Open77.database.ready(function() ... end)` with
   `CREATE TABLE IF NOT EXISTS`, table names prefixed by your resource name, rows keyed by the
   durable `Open77.players.identifier(playerId)` (never the session id), permission
   `database.access`. Use the `.await` forms (`Open77.database.query.await(sql, params)`, or the
   oxmysql-compatible `MySQL.query.await`) inside handlers and threads only — never inside an
   export: a synchronous export that yields fails with `export_yielded`. Exports must never
   yield: keep an in-memory cache written through to SQL with the callback forms.
   Fall back to `Open77.kvp` ONLY if the database is not
   ready, and say so in the log.
5. Host lifecycle events (`onPlayerReady`, `onPlayerDisconnected`, ...) deliver every argument
   as a STRING: `tonumber` before handing an id to a native that wants a number
   (`Open77.chat.send` refuses strings). In `RegisterCommand` / `RegisterNetEvent` handlers,
   `source` is a number (0 = server console: refuse politely unless the command is an admin
   tool, then answer with `print`). `args` are strings.
6. `Open77.chat.*` and `TriggerEvent` answer `resource_preparing` at the top level of a script:
   put them in `AddEventHandler("onResourceStart", ...)` (check the name is your own), commands
   or event handlers. Publish chat command suggestions on `chat:ready` (`RegisterNetEvent`,
   `source` is the player, no arguments) and once from `onResourceStart` with `-1`.
   `Open77.notifications.*` and `TriggerClientEvent` work anywhere.
7. Sandbox: no `os`, `io`, `require`, `load`, `debug`. Wall clock `Open77.time.unix()`, elapsed
   `Open77.time.monotonic()`, `math.random` available. `Open77.npcs.create` wants a numeric
   `damagePolicy` (2 = invulnerable) despite what the card shows. `players.all()` returns
   integers.
8. Cross-resource calls: server exports, called synchronously as `exports.<resource>:<name>(...)`
   inside `pcall` (they raise when the resource or export is missing). Declare
   `dependency "<resource>"` for every resource whose exports you call — EXCEPT when your
   resource has a `client_script`: a manifest delivered to clients cannot depend on a
   server-only resource (the session fails with `missing_dependency`); then omit the
   dependency and rely on `pcall`. Every `rp_*` resource is server-only for this purpose unless
   its open77.lua has a `client_script`.
9. Player-to-player actions (cuff, escort, search, fine, heal, show ID, pay...) go through the
   platform's ALT+click context menu when they target another player: `open77_contextmenu`
   client export `register` (guide `context-menu`), and the accept/decline flow of
   `open77_player_interactions` when the target must consent (a fine, a bill, a quote). A slash
   command with an explicit player id is the fallback, always provided too.
10. World prompts: `open77_worldui` (guide `worldui`) gives a ring + map pin + E prompt per
    point. The prompt is only pressable within `promptDistance` (default `radius + 0.5` m —
    pass `promptDistance = 3.0`) and while the player looks at it. Ground circles:
    `open77_groundcircle`. Zones: read the `polyzone` and `open77_zones` guides before choosing.
11. Command names must not collide with the platform's. Already owned (served silently by the
    first registrant, yours would never run): announce appearance avcleanup.now ban barber
    bring car clear client.exec deathmatch.* dm dm.* dv elevator.* fly forcedoor freeroam
    freeroam.* fuel fuel.* fx fx.* gender god goto gun guns heal help hud hudtest id kick
    light.* locations loot loot.* maptp noclip noclip.speed notification.test npc.* perspective
    players playerstate playerstate.* prop prop.* props pursuit.vehicle pvp pvp.* race race.*
    refuel revive rp.free rp.held spawn suicide tp tpc uikit.demo unlockdoor vehicle.* wardrobe
    weapon.* weapons weather weather.* — plus every command of the RP resources already
    delivered (listed below). Prefix nothing; pick another word.
12. Run `open77_validate` until OK with 0 errors. Then break the resource once on purpose
    (wrong-side native, unknown native, missing permission) to confirm the validator sees it,
    and restore.
13. Deliverable under `C:\Games\cyberm\rp-scripts\<resource>\`: `open77.lua`, `server/main.lua`,
    optionally `client/main.lua`, `shared/*.lua` for config, and `README.md` in English: what
    each command does, the exports and events, the SQL tables, and a "Test in 2 minutes"
    walkthrough that a tester can follow at the freeroam spawn. Hand back a report: (a)
    commands, (b) exports/events, (c) every MCP call (tool + args + one word), (d) where the MCP
    was wrong, ambiguous, missing or made you guess, (e) the final `open77_validate` output
    verbatim, (f) the file contents. Report only; do not test on a server.

## The map you can use (world coordinates, metres)

The eval server spawns everyone at the **freeroam spawn** `381.36, -2401.79, 181.99` (a plaza
labelled Badlands; flat road around it, an ATM ring at the spawn itself). Everything a tester
must reach on foot goes within 80 m of that point (state the coordinates in your README).
Other safe landing spots (from the freeroam `/goto` list): Open77 laboratory `1669.75, -739.12,
49.86` (East); City west `-667.14, -382.61, 9.16` (City Center); Vehicle dealership `-1442.2,
127.4, 18.0` and race grid `-1450.2, 119.9, 14.8` (Westbrook); Northwest heights `-1441.0,
1269.0, 123.0` (North Oak); King Stoop forecourt `-410.22, 722.73, 115.0`, North promenade
`-469.47, 930.99, 56.45`, Lower Watson junction `-644.91, 1019.37, 36.56`, Lower Watson
underpass `-701.49, 1033.97, 35.71` (Watson); Southwest coast `-1716.38, -2421.28, 62.59`
(Badlands). Put every position in a `shared/config.lua` table so the owner can move it.

## Delivered resources and their contracts (respect the names exactly)

- `rp_economy` (cash): exports `getBalance(playerId)`, `add(playerId, amount, reason)`,
  `remove(playerId, amount, reason) -> newBalance | nil, reason`; event `rp_economy:changed`
  (playerId, newBalance, delta, reason). Commands `money pay givemoney payday`. Payday +200 €$
  cash every 10 min for everyone (unchanged).
- `rp_jobs` v1 (being replaced by v2 in this phase — see below): exports `getJob(playerId) ->
  name|nil`, `hasJob(playerId, name)`; event `rp_jobs:changed` (playerId, name|nil).
- `rp_shop`: `shop buy sell`. `rp_chat`: `me do ooc w dice showid`. `rp_medic`: `soin reanimer
  911 medic` (absorbed by `rp_trauma` in this phase). `eval_taxi`: `taxi` (NPC Delamain cab,
  export none; `rp_delamain` falls back to it by sending the `/taxi` command flow described in
  its README).
- `rp_identity`: exports `get(playerId) -> { firstName, lastName, birth, sex, origin } | nil`,
  `fullName(playerId) -> string`, `isRegistered(playerId)`; event `rp_identity:changed`
  (playerId). Commands `carte civil`. Table `rp_identity_citizens`.
- `rp_inventory`: items in `rp_inventory/shared/items.lua` (`id, label, weight, usable,
  illegal`): water burrito nicola chooh2 bandage maxdoc bounceback phone radio lockpick scrap
  component chip cigarettes synthcoke(illegal) implant_box(illegal unless `medecin`) crate;
  exports `has(playerId, itemId, count)`, `add(playerId, itemId, count) -> true|nil, reason`,
  `remove(playerId, itemId, count) -> true|nil, "not_enough"|reason`, `count(playerId, itemId)`,
  `list(playerId) -> entries, totalWeight, capacity`, `openStash(playerId, stashId, capacity)`;
  events `rp_inventory:changed` (playerId, itemId, delta), `rp_inventory:used` (playerId,
  itemId). Commands `inv use drop ramasser give fouiller saisir giveitem`. New item kinds you
  need (a crowbar, a boxed implant grade, a quickhack, a drink...) are declared in YOUR
  `shared/items.lua`-style table (`id = { label, weight, usable, illegal, effect? }`, ids
  `^[a-z0-9_]+$`) and registered through the export `exports.rp_inventory:define(itemTable) ->
  registered, rejected`, called (in pcall) from your `onResourceStart` AND again from an
  `AddEventHandler("onResourceStart", ...)` that sees `rp_inventory` restart (its VM comes back
  with the built-in items only). A defined item owns its effect: `/use` debits one unit, applies
  an optional `effect = { needs = { thirst = 25 }, text = "..." }` through `rp_needs:apply`, and
  raises `rp_inventory:used (playerId, itemId)` for you to act on.
- `rp_bank`: exports `getAccount(playerId) -> {identifier, balance, createdAt}|nil, reason`,
  `deposit(playerId, amount)`, `withdraw(playerId, amount)`, `transfer(fromPlayerId,
  toIdentifier, amount[, fee]) -> newBalance|nil, reason`, `society(name) -> {name, balance}`,
  `societyAdd(name, amount, reason)`, `societyRemove(name, amount, reason) -> newBalance|nil,
  reason` (`insufficient_funds` when the society is dry), `charge(playerId, amount, society,
  reason) -> newAccountBalance|nil, reason` (account → society in one move: fines, bills,
  subscriptions; `insufficient_funds` when the account is short — then take what you can from
  cash with `rp_economy:remove` and keep a debt row in your own table); event `rp_bank:changed` (playerId|nil,
  identifier, newBalance, delta, kind). Commands `bank solde virement societe`. Society names
  are lower-case job names (`ncpd`, `trauma`, ...).
- `rp_needs`: exports `get(playerId) -> { hunger, thirst, fatigue }`, `consume(playerId,
  itemId) -> true|nil, reason` (knows water burrito nicola cigarettes synthcoke; anything else
  answers `not_consumable`), `apply(playerId, { hunger=, thirst=, fatigue= }, label) -> true|nil,
  reason` (generic restore/drain for YOUR consumables, -100..100 each, toast with `label`);
  event `rp_needs:changed`. Commands `needs setneeds`.

## Phase 2 contracts (resources being written together; use exactly these)

- `rp_jobs` v2 (replaces v1 in place, keeps `getJob` / `hasJob` / `rp_jobs:changed`): jobs
  `ncpd trauma delamain mecano ripper nomade ferrailleur barman fixer netrunner vigile`
  (+ `gang` later). Grades 0..3 (`recruit employee senior boss`). Exports `getJob(playerId) ->
  name|nil`, `hasJob(playerId, name)` (aliases: `police`→`ncpd`, `medecin`→`trauma`,
  `taxi`→`delamain`), `getGrade(playerId) -> { level, label } | nil`, `isBoss(playerId)`,
  `onDuty(playerId) -> boolean`, `setJob(playerId, name|nil, grade) -> true|nil, reason`,
  `listOnDuty(name) -> { playerId, ... }`, `salary(name, level) -> integer`. Events
  `rp_jobs:changed` (playerId, name|nil), `rp_jobs:duty` (playerId, name, onDuty:boolean).
  Commands `jobs job service embaucher virer promouvoir agence setjob`. Payroll: every 10 min
  the society pays each on-duty employee the salary of its grade in CASH:
  `exports.rp_bank:societyRemove(job, amount, "payroll")` then
  `exports.rp_economy:add(playerId, amount, "salary")`; a dry society pays nothing and tells
  the employee. `/service` also recolours the nameplate (client: `Open77.nameplates`).
  Tables `rp_jobs_employees`.
- `rp_zones`: exports `zoneOf(playerId) -> { name, label, kind } | nil`, `isIn(playerId,
  name)`, `list() -> { {name, label, kind}, ... }`, `playersIn(name) -> { playerId, ... }`;
  events `rp_zones:entered` (playerId, name, kind), `rp_zones:left` (playerId, name, kind).
  Kinds: `safe ncpd hospital badlands camp scrapyard blackmarket bar garage`. Commands `zones
  zone`. Zone names used by the other resources: `spawn_plaza` (safe, around the spawn),
  `ncpd_hq`, `hospital`, `nomad_camp`, `scrapyard`, `afterlife` (bar), `mecano_shop`,
  `badlands` (large), `blackmarket`.
- `rp_ncpd`: exports `isOnDuty(playerId)`, `wanted(playerId) -> { level, reason } | nil`,
  `setWanted(playerId, level, reason)`, `record(playerId) -> { entries }`, `addRecord(playerId,
  kind, text, byPlayerId)`; events `rp_ncpd:alert` (kind, position, text, byPlayerId) consumed
  by this resource (other resources raise it), `rp_ncpd:arrest` (playerId, byPlayerId, minutes).
  Commands `menotter demenotter escorter fouille amende embarquer prison liberer casier mandat
  ncpd`. Tables `rp_ncpd_records`, `rp_ncpd_warrants`.
- `rp_trauma` (absorbs `rp_medic`; the old `soin reanimer 911 medic` commands move here with
  the same names once `rp_medic` is unloaded — register them): exports `isDown(playerId)`,
  `revive(playerId, byPlayerId) -> true|nil, reason`, `heal(playerId, byPlayerId)`,
  `hasContract(playerId)`; events `rp_trauma:down` (playerId, position), `rp_trauma:revived`
  (playerId, byPlayerId|nil). Commands `soin reanimer 911 medic respawn trauma contrat`.
  Tables `rp_trauma_contracts`, `rp_trauma_bills`.
- `rp_delamain`: exports `call(playerId, destination|nil) -> rideId|nil, reason`,
  `activeRide(playerId)`; events `rp_delamain:ride` (rideId, phase, driverId, clientId).
  Commands `taxi` is owned by `eval_taxi` — use `delamain accepter course fin note`
  (`/delamain` = call a driver; `/taxi` stays the NPC cab).
- `rp_mecano`: exports `repair(vehicleId, byPlayerId)`, `bill(fromPlayerId, toPlayerId,
  amount, reason)`; commands `reparer remorquer peindre facture fourriere`.
