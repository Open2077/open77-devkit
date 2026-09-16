# Eval results, 2026-09-16

Build under test: server built from base `167dfbc9` (av-fix-merge, wire 1.35, the commit of the
deployed client DLL), index `2.31.13+op77.69`. Resources written by a headless agent with only
the Devkit MCP attached (`samples/`).

| Task | Static gate | Server `--lint` | In-game |
|---|---|---|---|
| taxi-job | PASS | OK | command and reason path proven (chat: "Place a waypoint on your map first, then type /taxi"); the ride needs a hand-placed vanilla waypoint the harness cannot inject |
| cuff-escort | PASS | OK | **one unattended two-client run, 07:55–07:58**: cuff held (`serverFrozen=yes movementHeld=yes`, pose `stand__2h_up__03__look_around__01`, 0 m under a 1.5 s forward push after a 5.45 m control walk); escort tether kept B at 1.73 m after the officer walked 14.07 m in 4 s |
| shop-webui | PASS | OK | loads and starts on the server (3 items); page interaction not driven |
| pvp-round | PASS | OK | same run: both players joined one non-default routing bucket (4300) and left it |
| fivem-port | PASS | OK | loads and starts on the server; menu not driven |

The run log is `harness/gate-run-2026-09-16.log`; the gate script and its two probes are in
`harness/`, with the eval server config (`server.eval.jsonc`, `<eval-run-dir>` is where the
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
- **Two-client harness lessons** (all in `harness/`): one 1920x1080 client takes ~6.7 GiB of
  VRAM, so two need 1280x720; a window that just gained focus drops the first keystroke
  (500 ms settle); `chat.say` bypasses the chat composer so client commands need real keys,
  `/` must be the keypad divide on AZERTY, and `-`/`.` cannot be typed at all; every chat send
  is verified against the server's `executed` line and resent once; the chat box closes itself
  on a send (an extra `esc` opens the Open77 pause menu); an escort verdict must check that
  the officer actually moved.

## Not proven

- The taxi ride and the shop and menu pages: they need a human hand (a map click, a mouse on
  a WebUI page) the harness does not have.
