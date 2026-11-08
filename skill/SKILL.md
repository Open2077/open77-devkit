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

`open77_version ">=x"` and a dependency's version constraint (`dependency "name >=1.2.0"`) are
**advisory** on the client from 2.50.0-unstable+op77.207: a mismatch is logged as
`ignored (advisory)` and the resource loads. Unstable op77.206 enforced them and refused such a
resource with `resource_activation_failed`. A missing dependency still blocks, and Warden's
Workshop planner still refuses an install whose `open77_version` the server does not meet
(`manifest_build_requirement`). Write the constraint you need, but do not count on it to stop a
resource from loading.

## Runtime shape (same as FiveM)

`CreateThread`, `Wait`, `SetTimeout`, `AddEventHandler`, `TriggerEvent`, `RegisterNetEvent`,
`TriggerServerEvent` / `TriggerClientEvent`, `RegisterCommand`, `exports`, `GetCurrentResourceName`,
`json.encode/decode`. Network events accept 32 arguments in a 48 KiB envelope. During a server net
handler `source` is the authenticated player, never client data.

Porting from FiveM: `open77_fivem_equivalent <name>` for every native; the compatibility guide
lists the three places Open77 deliberately answers differently.

## Vehicle customization

Liveries, neon and its animation, lamp colours, rims and body parts, plate, window tint, stickers,
performance stages and engine sounds are **server** natives on `Open77.vehicles`, published from
**2.50.0-unstable+op77.205** (their cards say `since: 2.50.0-unstable+op77.205`); on the Stable
channel they arrive with the first Stable after 2.50.0+op77.204. On an older build `open77_api`
reports them NOT AVAILABLE. (A card with `since: null` and no `release: "next"` marker is a shipped
native whose first build the index does not record; it is available.) Paint, the lights hue,
factory trims and the property table (`setPaint`, `setLightsHue`, `setHeadlightColor`,
`setAppearance`, `getProperties`, `setProperties`) are older; from op77.205 the headlights take the
lights hue and the property table carries `visual`, while before it the hue is stored without
colouring the headlights and the table has no `visual` field. Read
`open77_guide vehicle-customization` first, then the topic pages it lists:
`vehicle-customization-natives`, `-packs`, `-models`, `-persistence`, `-fivem` and `-examples`.
Where those pages still say "coming in the next Open77 release", that release is op77.205.

- **Permissions.** A call that changes the look (trim, livery, neon, lamp colours, parts, rims,
  plate, tint, stickers) needs `world.vehicles` **and** `world.vehicles.appearance`; the same
  value again needs only `world.vehicles`, so a garage restoring onto a fresh car needs both.
  `register*` calls need none; `list*` calls need none given a record name and `world.vehicles`
  given a vehicle id.
- **Part ids are namespaced** `<resource>:<id>` by the resource that **calls** `registerParts`, a
  server native. The kit's asset resource only registers prop models from a client script, so a
  server resource beside it registers the parts and owns their ids. A bare id names a part of the
  calling resource, so a shop that sells another resource's rims passes the qualified ids
  `listParts` returns, or gets `unknown_part`.
- **Coverage is data.** A part fits only the records its `fit` lists (`part_not_for_model`), a
  livery or sticker only its records, a stage only the records the pack generated. Offer what the
  `list*` functions answer for that car, never an id or record name a client sent.
- **Stages and engine sounds rebuild the car** (`respawnAs`, `setEngineSound`): it must be empty
  (`vehicle_occupied`). The server cannot see which records a pack generated.
- **Feature-detect** these natives (`if type(Open77.vehicles.setWheels) == "function" then`)
  so a resource still loads on a server older than op77.205, and read client `customizationAvailable(id).skipped`
  (permission `vehicles.read`) to tell a player what their game cannot draw. The list only grows
  while the car exists on that client: check what the car wears now before warning.
- **Persist** with `getProperties(id)` stored by the resource and `setProperties(id, stored)` on
  the new car; Open77 writes no vehicle to disk. On a fresh car every stored part, livery and
  sticker is a new choice: one whose pack is not running is refused (`unknown_part`,
  `invalid_profile`, `unknown_sticker`) and the whole call applies nothing. Declare the packs as
  `dependency`, and on such a refusal retry without `visual`. Only a choice the car already holds
  stays dormant while its pack is stopped.
- **FiveM:** `SetVehicleLivery`, `SetVehicleNeonLight*`, `SetVehicleMod`, `SetVehicleWheelType`
  and `SetVehicleWindowTint` (with their getters) are server globals; `SetVehicleNumberPlateText`
  is `setPlate`, the custom colours are `setPaint`. Ask `open77_fivem_equivalent` for each.

## Testing

For RP jobs and inventory actions, read `open77_guide rp-animations` before choosing
an animation or spawning a prop. The sections `upper-body-actions-for-jobs-and-inventory`,
`animation-owned-items-one-server-call` and `hold-drink-then-hold-again` cover native
default items, item suppression/custom records, input transitions and timed sequences.
Use the server `Open77.animations` API for authoritative actions. Inventory checks,
consumption, needs and rewards remain the job resource's responsibility.

Choose a `kind=layer` profile for walking/running. Workspots are stationary; an
`upperBody=true` option does not adapt arbitrary clips. `open77_data animations`
and the public discovery downloads are not allowlists: use the installed profile
catalogue and handle `unknown_clip`. An API's `since` identifies the original native,
not the first build supporting every newer option. Match client, server and archives
before relying on native animation-owned items; first-person support remains experimental.

When the local MCP is attached to a server (`open77_workspace` says so), validate, reload and read
the log yourself. When it is not, give the owner the exact commands: `reload <resource>` at the
server console, then what to look for in the log, and which in-game action proves the feature.
Never claim a resource works because it parses. From 2.50.0-unstable+op77.206 a reload is
targeted: only that resource and the running resources that depend on it are republished, a
manifest or syntax error is refused before anything stops, and a failed start is restored to the
previous scripts where possible and still reported as a failure, so read the log for the refusal
rather than assuming the new code runs.

## Reporting

Say which build you answered for. Quote the card for every native you relied on when the owner
asks why. If a capability does not exist on their build, say so plainly and name the first build
that has it (`open77_changes`).
