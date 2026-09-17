# Common rules for the RP resource round (read fully before starting)

You are writing ONE Lua resource for the Open77 platform (a Cyberpunk 2077 multiplayer
framework, FiveM-like: manifest `open77.lua`, `server_script` / `client_script`, natives under
`Open77.*` plus FiveM-shaped globals). Your ONLY source of truth is the Open77 Devkit MCP,
driven through this harness (one call per invocation, run from any directory):

    node "C:/Users/Wodman/AppData/Local/Temp/claude/C--Games-cyberm/47b3b407-f916-4dcf-a69e-303889c762ee/scratchpad/devkit-eval2/mcp-call-012-76.mjs" "C:/Games/cyberm/rp-scripts" <tool> '<json args>'
    node ... "C:/Games/cyberm/rp-scripts" list                       # the tool list
    node ... "C:/Games/cyberm/rp-scripts" open77_search '{"query":"give money to a player"}'
    node ... "C:/Games/cyberm/rp-scripts" open77_api '{"name":"Open77.players.name"}'
    node ... "C:/Games/cyberm/rp-scripts" open77_guide '{"slug":"server-exports"}'
    node ... "C:/Games/cyberm/rp-scripts" open77_validate '{"resource":"C:/Games/cyberm/rp-scripts/<your resource>"}'

Pass JSON args on the command line in single quotes; for arguments containing quotes, write
the JSON to a file and pass `@C:/path/args.json` instead. Each call takes 5-15 s (npx start).
The MCP answers for server build **2.31.13+op77.76**; that is the build the resource runs on.

## Hard rules

1. Do NOT read any file under `C:\Games\cyberm` other than your own resource directory. No
   web search. Do not start, stop or talk to any server or game process. Do not run git.
2. Start with `list`, then `open77_skill` if present (or `open77_guide README`), then search.
   Read the card (`open77_api`) of EVERY native you call: permission, reasons, since, runtime
   side. Declare in the manifest exactly the permissions the cards require. A native the MCP
   says is unavailable on op77.76 must not be used.
3. Server-authoritative design: the server decides money, jobs, spawns; a client only renders
   and requests. Every native that returns `nil, reason` / `false, reason` is checked and the
   player is told why in chat (French, short). Player-facing text in **French**, code comments
   in English, no BOM, LF line endings, 4-space indent, Lua 5.4.
4. Persistence: use the KVP API the MCP documents (`Open77.kvp` or the server equivalent),
   keyed by the player's stable identifier (find the native that gives a stable identity, not
   the session id). Nothing may crash on a missing key or a departed player.
5. Host lifecycle events (`onPlayerReady`, `onPlayerDisconnected`, ...) deliver every argument
   as a STRING; convert with `tonumber` before handing an id to a native that wants a number
   (`Open77.chat.send` refuses strings). Inside `RegisterCommand` / `RegisterNetEvent`
   handlers, `source` is already a number (0 = server console: refuse politely).
6. `Open77.chat.*` and `TriggerEvent` are refused with `resource_preparing` at the top level of
   a script: put them in `AddEventHandler("onResourceStart", ...)` (check the name is your
   own), commands or event handlers. Publish chat command suggestions on `chat:ready`
   (`RegisterNetEvent`, `source` is the player, no arguments) and once from `onResourceStart`
   with `-1`.
7. Sandbox: no `os`, `io`, `require`, `load`, `debug`. Wall clock: `Open77.time.unix()`;
   elapsed: `Open77.time.monotonic()`; `math.random` is available.
8. Cross-resource calls: server exports, called synchronously as
   `exports.<resource>:<name>(...)` (read `open77_guide server-exports` for the exact form,
   the promise/await rules and `GetInvokingResource`). Declare `dependency "<resource>"` in
   the manifest for every resource whose exports you call. If the export is missing at run
   time, degrade gracefully (message in chat), never crash.
9. Run `open77_validate` on your resource until it reports OK with 0 errors; keep warnings
   only when you can explain them. Then break it once on purpose (wrong-side native, unknown
   native, missing permission) to confirm the validator catches it, and restore.
10. Final deliverable, written under `C:\Games\cyberm\rp-scripts\<resource>\`:
    - `open77.lua`, `server/main.lua`, optionally `client/main.lua`, optionally `README.md`
      (French: what each command does, how to test it in 2 minutes).
    Then hand back a report with: (a) the command list and what each does, (b) every MCP
    call in order (tool + args + one word on usefulness), (c) where the MCP was wrong,
    ambiguous, missing or made you guess, (d) the final `open77_validate` output verbatim,
    (e) the final file contents. Report only; do not test on a server.

## Shared contracts between the resources of this round (respect the names exactly)

- `rp_economy` publishes server exports:
  - `getBalance(playerId) -> integer` (0 when unknown)
  - `add(playerId, amount, reason) -> newBalance | nil, reason`
  - `remove(playerId, amount, reason) -> newBalance | nil, "insufficient_funds" | nil, reason`
  and raises the host-wide event `rp_economy:changed` (playerId, newBalance, delta, reason)
  through `TriggerEvent` after every change.
- `rp_jobs` publishes server exports:
  - `getJob(playerId) -> jobName | nil`
  - `hasJob(playerId, jobName) -> boolean`
  and raises `rp_jobs:changed` (playerId, jobName | nil) on every change. Job names are
  lower-case ASCII: `livreur`, `taxi`, `mecano`, `medecin`, `police`.
- Every command name is lower-case, without a prefix, and must not collide with these,
  which other resources of the round own: `money`, `pay`, `givemoney`, `payday` (economy);
  `jobs`, `job`, `mission`, `stopmission` (jobs); `shop`, `buy`, `sell` (shop); `me`, `do`,
  `ooc`, `w`, `showid`, `dice` (chat); `heal`, `revive`, `911`, `medic` (medic).
