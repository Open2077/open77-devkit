/**
 * The CLI commands that need the index or the machine: serve (stdio and
 * HTTP), init / uninstall, types, status.
 */

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { createServer as createHttpServer, type IncomingMessage, type ServerResponse } from "node:http";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { EMBEDDED_INDEX, PACKAGE_ROOT } from "./cli.js";
import { loadIndex, readStub } from "./index/loader.js";
import { resolveIndex, type ResolvedIndex } from "./index/refresh.js";
import type { DevIndex } from "./index/types.js";
import { installAll, uninstallAll, type InstallResult } from "./install/clients.js";
import { createMcpServer, skillPathFor, type ServerContext } from "./server.js";
import { detectWorkspace, type Workspace } from "./workspace/detect.js";
import { registerLocalTools } from "./workspace/tools.js";
import { WardenClient, registerWardenTools } from "./workspace/warden.js";
import { registerWorkshopTools } from "./workspace/workshop.js";
import { createInterface } from "node:readline/promises";

type Flags = Record<string, string | boolean>;

const flag = (flags: Flags, name: string): string | undefined => (typeof flags[name] === "string" ? (flags[name] as string) : undefined);
const on = (flags: Flags, name: string): boolean => flags[name] === true || flags[name] === "true";
const log = (line: string) => process.stderr.write(`open77-mcp: ${line}\n`);

async function packageVersion(): Promise<string> {
  try {
    const pkg = JSON.parse(await readFile(path.join(PACKAGE_ROOT, "package.json"), "utf8")) as { version: string };
    return pkg.version;
  } catch {
    return "0.0.0";
  }
}

async function prepare(flags: Flags): Promise<{ context: ServerContext; workspace: Workspace }> {
  let workspace = await detectWorkspace(process.cwd(), flag(flags, "server-dir"), flag(flags, "config"));
  const wanted = flag(flags, "build") ?? workspace.build ?? undefined;
  const resolved: ResolvedIndex = await resolveIndex({
    build: wanted,
    embeddedDir: EMBEDDED_INDEX,
    offline: on(flags, "offline") || process.env["OPEN77_MCP_OFFLINE"] === "1",
    force: on(flags, "refresh"),
    log,
  });
  const index: DevIndex = await loadIndex(resolved.directory);
  const context: ServerContext = {
    index,
    resolved,
    packageVersion: await packageVersion(),
    skillPath: skillPathFor(PACKAGE_ROOT),
    extensions: [
      (server, ctx) => registerLocalTools(server, ctx, workspace, (next) => { workspace = next; }),
      (server, ctx) => registerWardenTools(server, ctx, () => workspace),
      (server, ctx) => registerWorkshopTools(server, ctx, () => workspace),
    ],
  };
  return { context, workspace };
}

/**
 * Interactive, in the terminal only: the Warden username and password are
 * typed here and sent to the server; what is kept is the session cookie.
 */
async function wardenLogin(flags: Flags): Promise<void> {
  const workspace = await detectWorkspace(process.cwd(), flag(flags, "server-dir"), flag(flags, "config"));
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    const suggested = flag(flags, "origin") ?? process.env["OPEN77_WARDEN_ORIGIN"] ?? workspace.wardenUrl ?? "http://127.0.0.1:11780";
    const originAnswer = flag(flags, "origin") ?? (await rl.question(`Warden origin [${suggested}]: `)).trim();
    const origin = (originAnswer || suggested).replace(/\/$/, "");
    const username = flag(flags, "username") ?? (await rl.question("Warden username: ")).trim();
    const password = await new Promise<string>((resolve) => {
      process.stdout.write("Warden password: ");
      const stdin = process.stdin;
      const wasRaw = stdin.isTTY ? stdin.isRaw : false;
      if (stdin.isTTY) stdin.setRawMode(true);
      let buffer = "";
      const onData = (chunk: Buffer) => {
        for (const char of chunk.toString("utf8")) {
          if (char === "\r" || char === "\n") {
            stdin.off("data", onData);
            if (stdin.isTTY) stdin.setRawMode(Boolean(wasRaw));
            process.stdout.write("\n");
            resolve(buffer);
            return;
          }
          if (char === "\u0003") process.exit(130);
          if (char === "\u007f" || char === "\b") buffer = buffer.slice(0, -1);
          else buffer += char;
        }
      };
      stdin.on("data", onData);
    });
    const client = new WardenClient(origin);
    const session = await client.login(username, password);
    process.stdout.write(`Signed in to ${origin} as ${session.username}; the session cookie is stored under ~/.open77/mcp/warden (owner-only). The MCP's live-server tools now work.\n`);
  } finally {
    rl.close();
  }
}

async function serveStdio(flags: Flags): Promise<void> {
  const { context, workspace } = await prepare(flags);
  log(`serving build ${context.resolved.build} (${context.resolved.origin})${workspace.serverDir ? ` for server at ${workspace.serverDir}` : ""}`);
  const server = createMcpServer(context);
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

/**
 * Stateless Streamable HTTP: one transport per request, no session, which is
 * what a hosted docs endpoint wants (any replica answers any request). The
 * `build` query parameter selects the index; unknown builds fall back to the
 * newest at or below, and the tools say so.
 */
async function serveHttp(flags: Flags): Promise<void> {
  const port = Number(flag(flags, "port") ?? process.env["PORT"] ?? 8787);
  const host = flag(flags, "host") ?? "0.0.0.0";
  const contexts = new Map<string, Promise<ServerContext>>();
  const contextFor = (build: string | undefined) => {
    const key = build ?? "latest";
    let pending = contexts.get(key);
    if (!pending) {
      pending = (async () => {
        const resolved = await resolveIndex({ build, embeddedDir: EMBEDDED_INDEX, log });
        const index = await loadIndex(resolved.directory);
        return { index, resolved, packageVersion: await packageVersion(), skillPath: skillPathFor(PACKAGE_ROOT) } satisfies ServerContext;
      })();
      contexts.set(key, pending);
      // Re-resolve after a day so a new release reaches long-lived replicas.
      setTimeout(() => contexts.delete(key), 24 * 60 * 60 * 1000).unref();
    }
    return pending;
  };
  const http = createHttpServer(async (req: IncomingMessage, res: ServerResponse) => {
    const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
    if (url.pathname === "/healthz") {
      res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ ok: true }));
      return;
    }
    if (url.pathname !== "/mcp") {
      res.writeHead(404, { "content-type": "text/plain" }).end("open77-mcp: POST /mcp (Streamable HTTP); GET /healthz\n");
      return;
    }
    try {
      const context = await contextFor(url.searchParams.get("build") ?? undefined);
      const server = createMcpServer(context);
      const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
      res.on("close", () => {
        void transport.close();
        void server.close();
      });
      await server.connect(transport);
      await transport.handleRequest(req, res);
    } catch (error) {
      log(`request failed: ${(error as Error).message}`);
      if (!res.headersSent) res.writeHead(500, { "content-type": "application/json" });
      res.end(JSON.stringify({ jsonrpc: "2.0", error: { code: -32603, message: "internal error" }, id: null }));
    }
  });
  http.listen(port, host, () => log(`Streamable HTTP on http://${host}:${port}/mcp`));
}

function printResults(results: InstallResult[]): void {
  for (const r of results) {
    const detail = r.detail ? ` — ${r.detail}` : "";
    process.stdout.write(`${r.action.padEnd(15)} ${r.name.padEnd(15)} ${r.file}${detail}\n`);
  }
}

async function init(flags: Flags): Promise<void> {
  const serverDir = flag(flags, "server-dir");
  const workspace = await detectWorkspace(process.cwd(), serverDir);
  // `--dev` registers this checkout (node dist/cli.js) instead of the npm
  // package: what a contributor, or a machine ahead of the npm release, wants.
  const dev = on(flags, "dev");
  const results = await installAll({
    serverDir: serverDir ? path.resolve(serverDir) : undefined,
    project: flag(flags, "project"),
    force: on(flags, "force"),
    only: flag(flags, "only")?.split(","),
    detectedOnly: !on(flags, "all"),
    ...(dev ? { command: process.execPath, args: [path.join(PACKAGE_ROOT, "dist", "cli.js")] } : {}),
  });
  printResults(results);
  const added = results.filter((r) => r.action === "added" || r.action === "updated" || r.action === "unchanged").length;
  process.stdout.write("\n");
  process.stdout.write(workspace.serverDir
    ? `Server detected at ${workspace.serverDir}${workspace.build ? ` (build ${workspace.build})` : " (build unknown; will answer for the latest release)"}.\n`
    : "No Open77 server next to this directory; the MCP answers for the latest published build. Run again inside a server folder, or pass --server-dir.\n");
  process.stdout.write(`${added} client${added === 1 ? "" : "s"} registered. Restart the agent, or reconnect its MCP servers, and ask it: "which Open77 build are you answering for?"\n`);
  if (results.some((r) => r.action === "kept-different")) process.stdout.write("An existing open77-devkit entry with different settings was kept; rerun with --force to replace it.\n");
}

async function uninstall(flags: Flags): Promise<void> {
  printResults(await uninstallAll({ project: flag(flags, "project"), only: flag(flags, "only")?.split(",") }));
}

async function types(flags: Flags): Promise<void> {
  const { context, workspace } = await prepare(flags);
  const out = path.resolve(flag(flags, "out") ?? workspace.resourcesRoot ?? process.cwd());
  await mkdir(out, { recursive: true });
  for (const runtime of ["client", "server"] as const) {
    await writeFile(path.join(out, `open77-${runtime}.d.lua`), await readStub(context.index, runtime), "utf8");
  }
  const luarc = path.join(out, ".luarc.json");
  let existing: Record<string, unknown> = {};
  try {
    existing = JSON.parse(await readFile(luarc, "utf8")) as Record<string, unknown>;
  } catch {
    /* new file */
  }
  const library = new Set<string>((existing["workspace.library"] as string[] | undefined) ?? []);
  library.add("open77-client.d.lua");
  library.add("open77-server.d.lua");
  await writeFile(luarc, JSON.stringify({ ...existing, "runtime.version": "Lua 5.4", "workspace.library": [...library], "diagnostics.globals": ["exports", "source"] }, null, 2) + "\n", "utf8");
  process.stdout.write(`stubs for build ${context.resolved.build} written to ${out} (open77-client.d.lua, open77-server.d.lua, .luarc.json)\n`);
}

async function status(flags: Flags): Promise<void> {
  const { context, workspace } = await prepare(flags);
  const lines = [
    `package        @open2077/mcp ${context.packageVersion}`,
    `index build    ${context.resolved.build} (${context.resolved.origin}${context.resolved.note ? `; ${context.resolved.note}` : ""})`,
    `index dir      ${context.resolved.directory}`,
    `docs synced    ${context.index.manifest.docsSyncedAt}`,
    `server dir     ${workspace.serverDir ?? "none detected"}`,
    `server build   ${workspace.build ?? "unknown"}${workspace.build ? ` (${workspace.buildSource})` : ""}`,
    `config         ${workspace.configFile ?? "none"}`,
    `resources root ${workspace.resourcesRoot ?? "none"}${workspace.resources.length ? ` (${workspace.resources.length} resources)` : ""}`,
    `warden         ${workspace.wardenUrl ?? "not enabled in server.jsonc"}`,
  ];
  process.stdout.write(lines.join("\n") + "\n");
}

export async function runCommand(command: string, flags: Flags, _rest: string[]): Promise<void> {
  switch (command) {
    case "":
      return serveStdio(flags);
    case "serve-http":
      return serveHttp(flags);
    case "init":
      return init(flags);
    case "uninstall":
      return uninstall(flags);
    case "types":
      return types(flags);
    case "status":
      return status(flags);
    case "warden-login":
      return wardenLogin(flags);
    default:
      throw new Error(`unknown command ${command}`);
  }
}
