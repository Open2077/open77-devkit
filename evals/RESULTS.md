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
