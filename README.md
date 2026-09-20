# Open77 Devkit MCP

`@open2077/mcp` gives coding agents the whole Open77 Lua surface, pinned to the server build you run:
every native with its permissions, reasons and first build, the guides, the `open77:*` events, the
manifest grammar, the game-data names, and a validator that catches a client native in a server
script before the server does.

Open77 turns Cyberpunk 2077 into a server-driven multiplayer platform; gameplay is written as Lua
resources. Its natives are not in any model's training data, which is why an assistant without this
server writes FiveM code with Open77 names. This is the fix.

## Install

One line, from inside your server folder so the build is detected:

```bash
npx -y @open2077/mcp init
```

`init` registers the server in every agent it finds: Claude Code, Codex CLI, Cursor, VS Code,
Claude Desktop, Windsurf, Gemini CLI. It never overwrites a different existing entry unless you pass
`--force`, and `npx -y @open2077/mcp uninstall` reverses it.

Without Node, or from a browser client, use the hosted docs-only endpoint:

```
https://mcp.open2077.net/mcp
```

Claude Code: `claude mcp add --transport http open77-devkit https://mcp.open2077.net/mcp`. In claude.ai,
add it under Settings › Connectors. The hosted endpoint answers for the latest published build, or
the build you pass as `?build=2.31.13+op77.54`.

## What the agent gets

| Tool | Answers |
|---|---|
| `open77_search` | natives, guide sections, events, permissions, FiveM aliases |
| `open77_api` | one card: signature, permissions, reasons, since, example, related guides |
| `open77_namespace`, `open77_guide`, `open77_events`, `open77_permissions` | the catalogue by facet |
| `open77_data` | vehicles, weapons, items, NPC templates, props, VFX, SFX, animations |
| `open77_fivem_equivalent` | what to use on Open77, and what is deliberately absent |
| `open77_manifest_schema`, `open77_server_config_schema` | `open77.lua` and `server.jsonc` |
| `open77_changes`, `open77_build` | what a build adds; which build this session answers for |
| `open77_workspace`, `open77_validate`, `open77_new_resource` | local only: detect the server, validate a resource (the server's own `--lint` verdict when the binary is next to you; command names another loaded resource already registers), scaffold one |
| `open77_server_status`, `open77_resources`, `open77_resource`, `open77_console_tail`, `open77_console_command`, `open77_tunables` | local only, through Warden: status, start/stop/restart/reload/validate, the log, the console, tunables |
| `open77_workshop_search`, `open77_workshop_release`, `open77_workshop_plan`, `open77_workshop_install`, `open77_workshop_job` | local only, through Warden: browse the Workshop, plan, install with the human's consent, follow the job |

Resources: `open77://skill` (the method), `open77://guide/{slug}`, `open77://api/{runtime}/{namespace}`,
`open77://stubs/{runtime}`. Prompts: `new_resource`, `port_fivem_resource`, `explain_reason`.

Every answer states the build it answers for. A native newer than that build, or in no published
build, is reported as **NOT AVAILABLE**, never silently served.

## What's new

**0.1.4** — refreshed RP animation guidance: walking upper-body profiles, native
animation-owned items, custom item permissions, hold/drink transitions and timed
sequences. `open77_data` identifies animation inventories as discovery data, with
public downloads and guidance for finding playable profiles. API cards include
the server animation permissions. Match the runtime and archives before using newer
item options; the original native's `since` is not a per-option version guarantee.
First-person presentation remains experimental. Includes the 0.1.3 fixes below.

For RP jobs, start with `open77_guide rp-animations`, then
`open77_api server:Open77.animations.play`. The public examples are at
[open77-rp-examples/docs/held-actions.md](https://github.com/Open2077/open77-rp-examples/blob/main/docs/held-actions.md).

**0.1.3** -- fixes measured by four MCP-only agents on 2026-09-18 against the index for
2.31.13+op77.76:

- `open77_validate` accepts the documented `.await` forms (`Open77.database.query.await(sql, params)`
  and the other database methods) and the global `MySQL`, which is `Open77.database` on every build
  that has the table; both still go through the permission check, so `database.access` is required
  as before. A name whose card documents no `.await` form gets a warning instead of a false
  "not in the catalogue". The alias table lives in `src/index/conventions.ts`, each entry pointing at
  the guide section that documents it, and the test suite checks those sections still say so.
- `open77_api client:<name>` works as the mirror of `server:<name>`; a prefix contradicting
  `runtime` says so instead of "does not exist".
- `open77_api server:exports` and `server:print` answer from the guides (`server-exports#publish-a-service`,
  `server-api#logging`) until the index carries their cards; `open77_namespace _G` lists them as a footnote.
- `open77_validate` warns when a literal `RegisterCommand("<name>")` reuses a name another resource
  under the detected server already registers on the same side; the runtime keeps one handler
  silently. Only when a server is detected (`open77_workspace`): a session with no server next to it
  has nothing to compare against.

## Editor completion

```bash
npx -y @open2077/mcp types
```

writes `open77-client.d.lua`, `open77-server.d.lua` and a `.luarc.json` into your resources root, so
the Lua language server in VS Code or Cursor completes `Open77.*` from the same catalogue.

## Where the knowledge comes from

The index is built from the public documentation content of
[open77-app](https://github.com/Open2077/open77-app) (`content/api`, `content/docs`), which is
synced from the platform wiki, itself generated from the client and server source. Nothing here is
hand-written knowledge: cards, permissions, reasons, `since`, events and catalogues are extracted
from code; guides are chunked as published.

Index builds are published to `https://cdn.open2077.net/dev-index/<build>/` with a hashed manifest.
The package ships a snapshot of the latest index and refreshes from the CDN at most once a day,
verifying every file against the manifest; offline, it serves the cache or the snapshot and says so.

## Commands

```
open77-mcp                       serve over stdio (what agents launch)
open77-mcp serve-http --port N   serve over Streamable HTTP
open77-mcp init [--server-dir D] [--project P] [--only cursor,codex] [--force]
open77-mcp uninstall
open77-mcp types [--out DIR]
open77-mcp status
open77-mcp warden-login          sign in to Warden in the terminal; only the session cookie is kept (~/.open77/mcp/warden)
open77-mcp build-index --content <open77-app/content> [--out DIR]
open77-mcp verify-index [--dir DIR]
```

Environment: `OPEN77_INDEX_DIR` (serve this index directory), `OPEN77_MCP_OFFLINE=1`,
`OPEN77_MCP_CACHE` (default `~/.open77/mcp`), `OPEN77_CDN_BASE`.

## Live server tools

Enable Warden in `server.jsonc` (`warden.enabled: true`), then run `npx -y @open2077/mcp warden-login`
once in a terminal. The username and password are typed there and sent to your server; the MCP keeps
only the session cookie, owner-readable, and never sees the password. Installs from the Workshop need
the plan's own hash plus an explicit `consent: true`, exactly as Warden requires from a human.

## Development

```bash
npm install
npm run index:build -- --content ../open77-app/content   # rebuild index/ from a checkout
npm test
npm run build
node dist/cli.js init --dev        # register this checkout instead of the npm package
```

The MCP is registered under the key `open77-devkit` in every client. `evals/` holds the task suite
an agent must pass with nothing but this MCP attached; see `evals/README.md`.

Licensed MIT. The game data in the index is names and record identifiers extracted from TweakDB,
the same data the website publishes; no game asset is redistributed.
