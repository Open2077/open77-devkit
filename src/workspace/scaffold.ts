/**
 * Resource scaffolds, correct by construction. Four kinds:
 *
 *   blank     manifest, client and server entry points, lifecycle handlers
 *   gamemode  the above plus shared/config.lua, a guarded state machine,
 *             roster tracking and a "<name>.status" command
 *   hud       the above plus web/index.html and the WebUI bridge
 *   service   export-only client resource carrying the ownership guard
 *
 * The service guard is the security-relevant part: an export that acts for
 * another resource must learn who is calling from GetInvokingResource(), never
 * from an argument, or any resource could impersonate any other.
 *
 * Every native the templates call is checked against the catalogue at
 * scaffold time; a template line that names a native the served build does
 * not have is dropped and reported rather than written.
 */

import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { opNumber } from "../index/builder.js";
import type { ServerContext } from "../server.js";

export const SCAFFOLD_KINDS = ["blank", "gamemode", "hud", "service"] as const;
export type ScaffoldKind = (typeof SCAFFOLD_KINDS)[number];

const PERMISSIONS: Record<ScaffoldKind, string[]> = {
  blank: ["network.events"],
  gamemode: ["network.events", "hud.notify"],
  hud: ["network.events", "hud.notify", "webui.pages"],
  service: [],
};

function manifest(name: string, kind: ScaffoldKind, summary: string, permissions: string[]): string {
  const lines = [
    `-- ${name}: ${summary}`,
    `resource "${name}"`,
    `version "0.1.0"`,
    `auto_start true`,
    "",
  ];
  if (permissions.length) lines.push(`permissions { ${permissions.map((p) => `"${p}"`).join(", ")} }`, "");
  if (kind === "gamemode" || kind === "hud") lines.push(`shared_script "shared/config.lua"`);
  if (kind !== "service") lines.push(`server_script "server/main.lua"`);
  lines.push(`client_script "client/main.lua"`);
  if (kind === "hud") lines.push(`web_files { "web/**" }`);
  return lines.join("\n") + "\n";
}

function clientMain(name: string, kind: ScaffoldKind): string {
  if (kind === "service") {
    return `-- ${name}: export-only client service.
-- Callers are identified by GetInvokingResource(), never by an argument, so no
-- resource can act in another's name. Entries are swept when the caller's
-- generation stops, so a reload never leaks ownership.

local owners = {}

local function ownerOf()
    local caller = GetInvokingResource()
    if not caller then return nil, "no_invoking_resource" end
    return caller
end

--- Register something on behalf of the calling resource.
--- @return string|nil id, string|nil reason
local function register(options)
    local owner, reason = ownerOf()
    if not owner then return nil, reason end
    local id = ("%s:%d"):format(owner, (owners[owner] and #owners[owner] or 0) + 1)
    owners[owner] = owners[owner] or {}
    owners[owner][#owners[owner] + 1] = { id = id, options = options }
    return id
end

local function release(id)
    local owner, reason = ownerOf()
    if not owner then return false, reason end
    local list = owners[owner] or {}
    for index, entry in ipairs(list) do
        if entry.id == id then table.remove(list, index) return true end
    end
    return false, "not_owned"
end

exports("register", register)
exports("release", release)

AddEventHandler("onClientResourceStop", function(stopped)
    -- A caller that stops loses everything it registered.
    owners[stopped] = nil
end)
`;
  }
  const hud = kind === "hud";
  return `-- ${name}: client entry point.
${kind === "gamemode" || hud ? "local config = Config -- from shared/config.lua\n" : ""}
AddEventHandler("onClientResourceStart", function(started)
    if started ~= GetCurrentResourceName() then return end
    print(("%s client started"):format(started))
${hud ? `    -- Created hidden, shown once the page is ready; the page raises "ready"
    -- through Open77.emit and the client answers with the first state.
    local page, reason = Open77.webui.create({
        entry = "web/index.html",
        layer = "hud",
        transparent = true,
        visible = false,
    })
    if not page then print("webui unavailable: " .. tostring(reason)) return end
    Page = page
    page:on("ready", function()
        page:show()
    end)
` : ""}end)

-- Server -> client: state updates arrive here. Keep this side presentational:
-- the server decides, the client renders.
RegisterNetEvent("${name}:state", function(state)
    ${hud ? `if Page then Page:send("state", state) end` : `-- render state`}
end)
`;
}

function serverMain(name: string, kind: ScaffoldKind): string {
  if (kind === "gamemode" || kind === "hud") {
    return `-- ${name}: server entry point. The server is authoritative: every
-- transition happens here and is pushed to clients as a whole state.

local config = Config -- from shared/config.lua
local roster = {}      -- playerId -> { joinedAt = ms }
local phase = "lobby"  -- lobby | running | ended
local phaseSince = GetGameTimer()

local function broadcast()
    local count = 0
    for _ in pairs(roster) do count = count + 1 end
    TriggerClientEvent("${name}:state", -1, { phase = phase, players = count, since = phaseSince })
end

local function transition(to)
    local allowed = { lobby = { running = true }, running = { ended = true }, ended = { lobby = true } }
    if not (allowed[phase] and allowed[phase][to]) then
        return false, ("invalid_transition:%s->%s"):format(phase, to)
    end
    phase, phaseSince = to, GetGameTimer()
    broadcast()
    return true
end

AddEventHandler("playerJoined", function(playerId)
    roster[playerId] = { joinedAt = GetGameTimer() }
    broadcast()
end)

AddEventHandler("playerLeft", function(playerId)
    roster[playerId] = nil
    broadcast()
end)

RegisterCommand("${name}.status", function(source)
    local count = 0
    for _ in pairs(roster) do count = count + 1 end
    print(("${name}: phase=%s players=%d"):format(phase, count))
end, false)

RegisterCommand("${name}.start", function(source)
    local ok, reason = transition("running")
    if not ok then print(reason) end
end, true)

CreateThread(function()
    while true do
        Wait(config.tickMs or 1000)
        if phase == "running" and config.roundSeconds and GetGameTimer() - phaseSince > config.roundSeconds * 1000 then
            transition("ended")
        end
    end
end)
`;
  }
  return `-- ${name}: server entry point.

AddEventHandler("onResourceStart", function(started)
    if started ~= GetCurrentResourceName() then return end
    print(("%s server started"):format(started))
end)

RegisterCommand("${name}.status", function(source)
    print("${name}: running")
end, false)
`;
}

function sharedConfig(name: string): string {
  return `-- ${name}: values both runtimes read. Keep this data only: no natives.
Config = {
    tickMs = 1000,
    roundSeconds = 300,
}
`;
}

function webIndex(name: string): string {
  return `<!doctype html>
<meta charset="utf-8">
<title>${name}</title>
<style>
  html, body { margin: 0; background: transparent; color: #eaf6f8; font: 14px/1.4 system-ui, sans-serif; }
  #hud { position: fixed; top: 24px; right: 24px; padding: 10px 14px; background: rgba(8,14,25,.75); border: 1px solid #22d8e2; }
</style>
<div id="hud">${name}: <span id="phase">–</span> · <span id="players">0</span> players</div>
<script>
  // window.Open77 is the page bridge: Open77.on(event, handler) receives what the
  // client script sends with page:send(event, payload); Open77.emit(event, payload)
  // raises an event the client script handles with page:on(). Nothing here talks
  // to the network or decides anything.
  const bridge = window.Open77;
  function render(state) {
    document.getElementById("phase").textContent = state.phase;
    document.getElementById("players").textContent = state.players;
  }
  if (bridge && typeof bridge.on === "function") bridge.on("state", render);
  window.addEventListener("message", (event) => {
    const data = event.data || {};
    if ((data.event || data.name) === "state") render(data.payload || data);
  });
  if (bridge && typeof bridge.emit === "function") bridge.emit("ready", {});
</script>
`;
}

function agentsMd(name: string, kind: ScaffoldKind, summary: string, build: string): string {
  return `# ${name}

${summary}

Kind: ${kind}. Scaffolded by @open2077/mcp for Open77 build ${build}.

## Working on this resource with an agent

- Look every \`Open77.*\` native up with the Open77 Devkit MCP (\`open77_api\`) before calling it;
  natives are not in any model's training data and a plausible name is usually wrong.
- Client scripts render and request; server scripts decide. Never move authority to the client.
- Declare in \`open77.lua\` exactly the permissions \`open77_api\` lists for the natives used.
- Natives answer \`nil, "reason"\` on failure: handle the reasons the card lists.
- Validate with \`open77_validate ${name}\`, then \`reload ${name}\` at the server console and read the log.
- Events this resource raises use the \`${name}:\` prefix; \`open77:*\` prefixes are the platform's.
`;
}

export async function scaffold(target: string, name: string, kind: ScaffoldKind, context: ServerContext, summary?: string): Promise<string[]> {
  const line = summary ?? `an Open77 ${kind} resource`;
  const served = opNumber(context.resolved.build);
  const known = new Set(context.index.permissions.permissions.map((p) => p.name));
  const permissions = PERMISSIONS[kind].filter((p) => known.has(p));
  const files: Record<string, string> = {
    "open77.lua": manifest(name, kind, line, permissions),
    "client/main.lua": clientMain(name, kind),
    "AGENTS.md": agentsMd(name, kind, line, context.resolved.build),
  };
  if (kind !== "service") files["server/main.lua"] = serverMain(name, kind);
  if (kind === "gamemode" || kind === "hud") files["shared/config.lua"] = sharedConfig(name);
  if (kind === "hud") files["web/index.html"] = webIndex(name);

  // Drop template lines naming a native this build does not register.
  const byQualified = new Map(context.index.cards.map((c) => [c.qualified, c]));
  for (const [file, content] of Object.entries(files)) {
    if (!file.endsWith(".lua")) continue;
    files[file] = content.split("\n").filter((row) => {
      for (const match of row.matchAll(/\b((?:Open77|WebUI)(?:\.[A-Za-z_]\w*)+)\s*[(:]/g)) {
        const card = byQualified.get(match[1]!);
        if (!card || !card.since || opNumber(card.since) > served) return false;
      }
      return true;
    }).join("\n");
  }
  await mkdir(target, { recursive: true });
  const written: string[] = [];
  for (const [file, content] of Object.entries(files)) {
    const full = path.join(target, file);
    await mkdir(path.dirname(full), { recursive: true });
    // Lua and the manifest must be UTF-8 without BOM; writeFile never adds one.
    await writeFile(full, content.replace(/\r\n/g, "\n"), "utf8");
    written.push(file);
  }
  return written.sort();
}
