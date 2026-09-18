---
name: open77-resource-dev
description: Write, validate and hot-reload Open77 (Cyberpunk 2077 multiplayer) Lua resources with the Open77 Devkit MCP - gamemodes, role-play systems, HUDs, services - against the exact server build the owner runs. Use whenever a task involves an Open77 resource, open77.lua, Open77.* natives, a server.jsonc, Warden, or porting a FiveM script.
---

# Building Open77 resources with the Devkit MCP

Open77 turns Cyberpunk 2077 into a server-driven multiplayer platform. Gameplay is written as
**resources**: a directory with an `open77.lua` manifest, Lua scripts for the client and the
server, declared permissions, optional WebUI files. The shape is FiveM's; the natives are not.

**Open77 natives are not in your training data.** Every `Open77.*` call and every global must be
looked up with the MCP before you write it. A name the MCP does not return does not exist on the
owner's build, however plausible it looks.

## The loop

```
open77_build                       which build you are answering for; say it in your first message
open77_search "<what you need>"    cards, guides, events, permissions, FiveM aliases
open77_api <name>                  the card: runtime, permissions, since, reasons, example (server:<name> / client:<name> pins a side)
open77_guide <slug|slug#section>   the how-to behind the card (a search ref pastes as is)
open77_manifest_schema             before writing open77.lua
   write
open77_validate <resource>         (local MCP) syntax, manifest, unknown natives, wrong side, permissions, build, command names taken by another resource
open77_resource reload <name>      (local MCP, through Warden) then open77_console_tail for the result
```

Prefer a documented card over an inferred one, and a guide example over your own idea of the
shape: the guides were written from measurements in the real game.

## Rules that are not negotiable

1. **The server is authoritative.** A client renders and *requests*; the server decides loot,
   life, vehicles, time, weather, routing. A client-side "give money" is a bug, not a shortcut.
2. **Runtime side is a hard boundary.** A card is `client` or `server`. `Open77.camera` does not
   exist in a `server_script`; `TriggerClientEvent` does not exist in a `client_script`. Shared
   scripts may only use what exists on both sides.
3. **Declare exactly the permissions the natives require.** `open77_api` lists them. A missing one
   answers `permission_denied:<name>` at runtime; an extra one is a needless grant.
4. **Respect `since`.** A card whose `since` is newer than the served build, or is null
   (unreleased), is **not available**. Find another way or tell the owner which build they need.
5. **Check the reason.** Natives answer `value` on success and `nil, "reason"` (or
   `false, "reason"`) on failure. Handle the reasons the card lists; never assume success.
6. **Events under reserved prefixes are the platform's.** `open77_events` lists the prefixes a
   resource may not raise; use your own `myresource:*` names for your events.
7. **Server-side actions on a player who is not alive crash the client.** Check the player's state
   before teleporting, spawning into, or reviving; gamemode guides show the guarded pattern.
8. **The host bus is closed until the resource is running.** `TriggerEvent` and every
   `Open77.chat.*` facade at the top level of a server script answer `false, "resource_preparing"`
   (measured on op77.75): send from `AddEventHandler("onResourceStart", ...)`, a command, an event
   or a later tick. `TriggerClientEvent` and `Open77.notifications.*` work at top level. Lifecycle
   handlers (`onResourceStart`, `onPlayerReady`, `onPlayerDisconnected`) are listed by
   `open77_events` under `prefix=lifecycle`, with their payloads; **every argument of a host event
   is a string**, and `Open77.chat.send` refuses a string id (`invalid_chat_target`), so
   `tonumber(playerId)` before handing one to a native that wants a number.
9. **A new resource must be admitted by `resources.load`.** A server provisioned by the first-run
   wizard lists its resources by name; add yours to `server.jsonc`, then `refresh` + `ensure
   <name>` at the console. `refresh` rescans manifests but never re-reads `server.jsonc`, so a
   name absent from the list at startup needs a restart; `Resource '<name>' was not found` is
   that case, not a broken manifest.
10. **Generation cleanup is automatic, ownership is not.** Handlers, timers and entities a resource
   creates are swept when it stops; exports that act on another resource's behalf must use
   `GetInvokingResource()`, never a name passed as an argument.
11. **The sandbox has `math`, `string`, `table`, `utf8`, `coroutine` and `json` -- nothing else.**
   `os`, `io`, `debug`, `package`, `require`, `load`, `loadfile`, `dofile` and `collectgarbage`
   are nil on both sides (the client also removes `setmetatable`/`getmetatable` and
   `coroutine.create/resume/wrap`; use `CreateThread`). Wall-clock time is `Open77.time.unix()`,
   elapsed time `Open77.time.monotonic()`; more files are more `server_script` lines, not
   `require`. `open77_validate` flags each of these.

## Manifest

```lua
resource "my_taxi"            -- must equal the directory name, lowercase slug
version "1.0.0"
auto_start true

permissions { "network.events", "world.vehicles", "hud.notify" }
dependency "open77_zones"

shared_script "shared/config.lua"
client_script "client/main.lua"
server_script "server/main.lua"
web_files { "web/**" }
```

`open77_manifest_schema` has every directive. Scripts are `.lua` only; globs are allowed.

## Runtime shape (same as FiveM)

`CreateThread`, `Wait`, `SetTimeout`, `AddEventHandler`, `TriggerEvent`, `RegisterNetEvent`,
`TriggerServerEvent` / `TriggerClientEvent`, `RegisterCommand`, `exports`, `GetCurrentResourceName`,
`json.encode/decode`. Network events accept 32 arguments in a 48 KiB envelope. During a server net
handler `source` is the authenticated player, never client data.

Porting from FiveM: `open77_fivem_equivalent <name>` for every native; the compatibility guide
lists the three places Open77 deliberately answers differently.

## Testing

When the local MCP is attached to a server (`open77_workspace` says so), validate, reload and read
the log yourself. When it is not, give the owner the exact commands: `reload <resource>` at the
server console, then what to look for in the log, and which in-game action proves the feature.
Never claim a resource works because it parses.

## Reporting

Say which build you answered for. Quote the card for every native you relied on when the owner
asks why. If a capability does not exist on their build, say so plainly and name the first build
that has it (`open77_changes`).
