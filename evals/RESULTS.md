# Eval results, 2026-09-16

Build under test: server built from base `114b6d4d` (release 72, wire 1.34), index `2.31.13+op77.69`.
Resources written by a headless agent with only the Devkit MCP attached (`samples/`).

| Task | Static gate | Server `--lint` | In-game |
|---|---|---|---|
| taxi-job | PASS | OK | command and reason path proven (chat: "Place a waypoint on your map first, then type /taxi"); the ride needs a hand-placed vanilla waypoint the harness cannot inject |
| cuff-escort | PASS | OK | **cuff**: pose on the held body and a 0 m walk under a 1.5 s forward push (probe, `samples/eval_cuff/proof-cuffed-pose.png`); **escort**: tether held at 2.8 m and 3.6 m after the officer walked 4 s (two gate runs) |
| shop-webui | PASS | OK | loads and starts on the server (3 items); page interaction not driven |
| pvp-round | PASS | OK | two players joined one non-default routing bucket (4300) and left it (two gate runs) |
| fivem-port | PASS | OK | loads and starts on the server; menu not driven |

## What the in-game runs found

- **A real resource defect the validator missed**, then caught: the cuff resource called
  `Open77.input.blockAll` without declaring `input.blockAll`; the runtime refused it
  (`permission_denied:input.blockAll`). The guard extractor's permission pattern was
  lowercase-only and hid every camelCase permission (`input.blockAll`,
  `world.clearArea.foreign`). Fixed in base `wiki/tools/api_guards.py`; `open77_validate`
  now reports the missing declaration.
- **Warden's `frozen` flag is not the cuff's evidence**: the resource holds the body through
  the pose plus the client input block, not the movement-lock channel that flag mirrors.
  The gate measures the pose and the position delta.
- **Two-client harness lessons** (all in `op77-eval-server/scripts/`): one 1920x1080 client
  takes ~6.7 GiB of VRAM, so two need 1280x720; a window that just gained focus drops the
  first keystroke (500 ms settle added to `game-input.ps1`); `chat.say` bypasses the chat
  composer so client commands need real keys, and `/` must be the keypad divide on AZERTY;
  every chat send is verified against the server's `executed` line and resent once;
  identities spawn at different places (2.4 km apart once), so B is teleported next to A
  first; a client can fail its pristine load (1 of 9 launches), which is a rerun, not a verdict.

## Not proven

- The taxi ride and the shop and menu pages: they need a human hand (a map click, a mouse on
  a WebUI page) the harness does not have.
- The gate script as one unattended run: the last clean two-client runs proved escort and
  arena, and the cuff separately by probe; a single run with all three green was cut short
  by the GPU being handed back.
