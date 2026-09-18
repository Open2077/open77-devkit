# Review brief — Night City RP resources (2026-09-18)

You are reviewing Lua resources of an Open77 roleplay server under `C:\Games\cyberm\rp-scripts\`. The goal is
"make sure it all works": find and FIX real bugs in the resources assigned to you, nothing else.

## Hard rules
- Edit ONLY the resource folders assigned to you (their `open77.lua`, `shared/`, `server/`, `client/`, `web/`, `README.md`).
  Never touch another resource, the platform resources, the eval server, the game, any server process, or anything
  under `C:\Games\cyberm\base` / `op77-eval-server` (read them freely, never write).
- Do not restart, deploy, launch or connect anything. The coordinator deploys and replays every path in game after you.
- Keep files UTF-8 without BOM, LF, 4-space indent, Lua 5.4. Player-facing text stays ENGLISH with the cyberpunk tone
  already used (eddies, choom, ripper…). Do not rename commands, exports or events: other resources depend on them.
- After every edit: validate with
  `node C:\Users\Wodman\AppData\Local\Temp\claude\C--Games-cyberm\47b3b407-f916-4dcf-a69e-303889c762ee\scratchpad\devkit-eval2\mcp-call-013-76.mjs "C:/Games/cyberm/rp-scripts" open77_validate '{"resource":"C:/Games/cyberm/rp-scripts/<name>"}'`
  (run it from the PowerShell tool; the first line must start with `OK`; `state.write` being "not enforced" is a known
  validator false positive — the runtime needs it — leave it declared), and lint with
  `& "C:\Games\cyberm\op77-eval-server\server\src\Open77.Server\bin\Release\net10.0\Open77.Server.exe" --lint "C:\Games\cyberm\rp-scripts\<name>"`
  (`"findings": []` is clean).

## What the runtime really is (read these, they are the truth — not the cards)
- Server natives: `C:\Games\cyberm\op77-eval-server\server\src\Open77.Server.Scripting\Runtime\LuaResourceRuntime*.cs`
  (and siblings in that folder). Client natives: `C:\Games\cyberm\op77-eval-server\client\src\scripting\`.
  Platform resources (exports you may call, event names, prompt payload shapes): `C:\Games\cyberm\op77-eval-server\resources\system\<name>\`.
- Guides: `C:\Games\cyberm\op77-eval-server\wiki\*.md`. The other RP resources' contracts: their `README.md` next to yours.
- Measured platform facts this round (do not re-derive):
  * `Open77.players.identifier/name/position(id)` THROW for id ≤ 0 or non-integer and the exception kills the resource VM
    (console actors arrive as id 0 in event payloads; `source` is 0 for console commands). Every player lookup must be guarded.
  * The database bridge refuses a statement with more than 64 positional parameters or 64 KB of SQL (the callback gets nil);
    a `params` array with a nil hole fails (`invalid_parameters`), a trailing nil is `parameter_count_mismatch`.
    `Open77.database.*.await` raises on failure; the callback form gets `nil, reason`.
  * A synchronous export (`exports("name", fn)`) must never yield (no `Wait`, no `.await`) — `export_yielded`.
  * A manifest that reaches the client (any `shared_script`, `client_script`, `web_files`) must not `dependency` a resource
    without a client half: the client rejects the WHOLE resource set. Server-only resources load shared configs as `server_script`.
  * `state.write` is required for `Open77.state.*` writes even though the validator says it does not exist.
  * Connect and every admin `tp` emit a `dead` life phase (`onPlayerLifeStateChanged`, `getLifeState().weapon = "open77_admin:tp"`,
    cause `script`); a death-driven resource must skip those.
  * Client script budget: a resume that reaches 10 000 Lua instructions can be killed; a `CreateThread` loop that raises is
    retired for the session. Client loops must do little per tick and yield (`Wait`) between phases; wrap risky phases in `pcall`.
  * World positions on the eval map: plaza x 340–400 / y −2381..−2410 z≈182 and the NE band to x 460 (z 178–182); cliffs
    west of x 350 at y −2386, north of y −2361, south of y −2415, east of x 400 at y −2401.
  * `promptDistance` on worldui POIs defaults to radius + 0.5 and is measured from the player; labels draw above UI-kit dialogs.

## What to look for (in order of value)
1. Crashes: unguarded player ids, nil indexing on event payloads that can be nil/false/0, `tonumber` on nil, string
   formats with the wrong type (`%d` with a float/nil), yields inside exports or inside synchronous handlers, errors in
   `CreateThread` loops (which retire the loop silently), `pairs` over tables mutated during iteration.
2. Persistence: every write that must survive a restart actually reaches SQL (callback results checked), nil holes in
   params, unbounded batches (> 64 params), KVP fallback only when the DB is unavailable, load-on-start restores the
   state the code later assumes (indexes by identifier vs session id, ids ≥ 1, types).
3. Contracts: exports and events used by other resources exist with the documented signature (compare with the READMEs
   of the callers/callees in `C:\Games\cyberm\rp-scripts\`); `pcall` around every cross-resource call that may be down.
4. Money: no double charge / free item on a failed step (charge after the check, refund on failure), no negative
   balances, cash vs account paths consistent with `rp_economy` / `rp_bank`.
5. Multiplayer correctness: per-player state keyed correctly, cleanup on `onPlayerDisconnected` and on resource stop
   (NPCs, props, vehicles, prompts, timers), nothing global that assumes one player.
6. Client side: prompts/menus reachable, no tight loops, `onClientResourceStop` cleanup, event payload validation.
7. README accuracy: commands, positions, expected chat lines match the code (fix the README, not the code, when the
   code is right).

Do not refactor, do not restyle, do not add features. A fix is the smallest change that makes the path work; add a
one-line comment with the reason when it is not obvious. If something is a platform limit rather than a resource bug,
do not work around it silently — report it.

## Report (final message)
Per resource: (a) bugs found and fixed — file:line, what was wrong, what you changed; (b) bugs found and NOT fixed
(why: platform, design, needs a second player, out of scope) with file:line; (c) validator + lint result after your
edits (verbatim first line). Keep it factual and short; no code dumps.
