/**
 * A small client for Warden, the dedicated server's admin console, and the
 * MCP tools built on it: status, resources, reload, the log, the console,
 * tunables, and the runtime's own validator.
 *
 * Credentials never enter the agent transcript: `open77-mcp warden-login`
 * prompts in the terminal, the server answers with a session cookie, and only
 * that cookie is kept, in `~/.open77/mcp/warden/<host>.json` with owner-only
 * permissions. When it expires the tools say so and name the command to run.
 *
 * Every mutation carries the exact Warden origin, which the server requires,
 * and is one of the actions Warden itself exposes to a signed-in operator.
 */

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { chmod, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { z } from "zod";
import type { ServerContext } from "../server.js";
import type { Workspace } from "./detect.js";

export const SESSION_ROOT = path.join(process.env["OPEN77_MCP_CACHE"] ?? path.join(os.homedir(), ".open77", "mcp"), "warden");

export interface WardenSession {
  origin: string;
  cookie: string;
  username: string;
  savedAt: string;
}

export class WardenError extends Error {
  constructor(message: string, readonly status?: number) {
    super(message);
  }
}

function hostKey(origin: string): string {
  return origin.replace(/^https?:\/\//, "").replace(/[^a-z0-9.-]/gi, "_");
}

export async function loadSession(origin: string): Promise<WardenSession | null> {
  try {
    return JSON.parse(await readFile(path.join(SESSION_ROOT, `${hostKey(origin)}.json`), "utf8")) as WardenSession;
  } catch {
    return null;
  }
}

export async function saveSession(session: WardenSession): Promise<string> {
  await mkdir(SESSION_ROOT, { recursive: true });
  const file = path.join(SESSION_ROOT, `${hostKey(session.origin)}.json`);
  await writeFile(file, JSON.stringify(session, null, 2), { encoding: "utf8", mode: 0o600 });
  await chmod(file, 0o600).catch(() => undefined);
  return file;
}

export async function clearSession(origin: string): Promise<void> {
  await rm(path.join(SESSION_ROOT, `${hostKey(origin)}.json`), { force: true });
}

export interface LogEntry {
  sequence?: number;
  timestamp?: string;
  level?: string;
  message?: string;
  [key: string]: unknown;
}

export class WardenClient {
  constructor(readonly origin: string, private cookie: string | null = null) {}

  static async fromSession(origin: string): Promise<WardenClient> {
    const session = await loadSession(origin);
    return new WardenClient(origin, session?.cookie ?? null);
  }

  get signedIn(): boolean {
    return this.cookie !== null;
  }

  private async request<T>(method: string, route: string, body?: unknown, auth = true): Promise<{ status: number; data: T; setCookie?: string }> {
    const headers: Record<string, string> = { accept: "application/json", origin: this.origin };
    if (body !== undefined) headers["content-type"] = "application/json";
    if (auth && this.cookie) headers["cookie"] = this.cookie;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch(`${this.origin}${route}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: controller.signal,
        redirect: "manual",
      });
      const text = await response.text();
      let data: unknown = text;
      try {
        data = text ? JSON.parse(text) : {};
      } catch {
        /* plain text stays text */
      }
      const setCookie = response.headers.get("set-cookie") ?? undefined;
      if (response.status === 401 || response.status === 403) {
        throw new WardenError(
          response.status === 401
            ? "Warden session missing or expired. Run `npx -y @open2077/mcp warden-login` in a terminal, then retry."
            : "Warden refused: the signed-in account lacks the permission for this action.",
          response.status,
        );
      }
      return { status: response.status, data: data as T, setCookie };
    } catch (error) {
      if (error instanceof WardenError) throw error;
      throw new WardenError(`Warden at ${this.origin} is unreachable: ${(error as Error).message}`);
    } finally {
      clearTimeout(timer);
    }
  }

  /** The same cookie, origin and error rules, for the Hub client. */
  async raw<T>(method: "GET" | "POST", route: string, body?: unknown): Promise<T> {
    const result = await this.request<T>(method, route, body);
    if (result.status >= 400) {
      const data = result.data as { error?: string; message?: string } | string;
      const detail = typeof data === "string" ? data : `${data.error ?? ""} ${data.message ?? ""}`.trim();
      throw new WardenError(`Warden answered HTTP ${result.status}${detail ? `: ${detail}` : ""}`, result.status);
    }
    return result.data;
  }

  async login(username: string, password: string): Promise<WardenSession> {
    const result = await this.request<{ ok?: boolean; message?: string; username?: string }>("POST", "/api/login", { username, password }, false);
    if (result.status !== 200 || !result.data.ok) throw new WardenError(result.data.message ?? `login failed (HTTP ${result.status})`, result.status);
    if (!result.setCookie) throw new WardenError("Warden answered without a session cookie");
    this.cookie = result.setCookie.split(";")[0]!;
    const session = { origin: this.origin, cookie: this.cookie, username: result.data.username ?? username, savedAt: new Date().toISOString() };
    await saveSession(session);
    return session;
  }

  async session(): Promise<unknown> {
    return (await this.request("GET", "/api/session")).data;
  }

  async dashboard(): Promise<unknown> {
    return (await this.request("GET", "/api/dashboard")).data;
  }

  async resources(): Promise<unknown> {
    return (await this.request("GET", "/api/resources")).data;
  }

  async control(name: string, action: "start" | "stop" | "restart" | "reload"): Promise<{ ok: boolean; output: string }> {
    return (await this.request<{ ok: boolean; output: string }>("POST", `/api/resources/${encodeURIComponent(name)}/${action}`, {})).data;
  }

  async validate(name: string): Promise<unknown> {
    const result = await this.request<unknown>("POST", `/api/resources/${encodeURIComponent(name)}/validate`, {});
    if (result.status === 404) throw new WardenError(`no resource named ${name}, or this server predates the validate endpoint (HTTP 404)`, 404);
    // A server older than the endpoint routes the call to the generic action
    // handler, which answers "unknown resource action". Say what that means.
    const generic = result.data as { ok?: boolean; output?: string } | undefined;
    if (generic && generic.ok === false && /unknown resource action/.test(generic.output ?? "")) {
      throw new WardenError("this server build has no runtime validator (Warden validate arrived with the --lint build); open77_validate still checks the resource against the catalogue", 501);
    }
    return result.data;
  }

  async log(after = 0): Promise<LogEntry[]> {
    const result = await this.request<{ entries?: LogEntry[] }>("GET", `/api/console/log?after=${after}`);
    return result.data.entries ?? [];
  }

  async command(command: string): Promise<{ ok: boolean; output: string }> {
    return (await this.request<{ ok: boolean; output: string }>("POST", "/api/console/command", { command })).data;
  }

  async tunables(): Promise<unknown> {
    return (await this.request("GET", "/api/tunables")).data;
  }

  async setTunable(resource: string, key: string, value: unknown): Promise<{ ok: boolean; output: string; pending?: boolean }> {
    return (await this.request<{ ok: boolean; output: string; pending?: boolean }>("POST", `/api/tunables/${encodeURIComponent(resource)}/keys/${encodeURIComponent(key)}`, { value })).data;
  }
}

function text(body: string) {
  return { content: [{ type: "text" as const, text: body }] };
}

function pretty(value: unknown, limit = 12000): string {
  const json = typeof value === "string" ? value : JSON.stringify(value, null, 1);
  return json.length > limit ? json.slice(0, limit) + "\n…(truncated)" : json;
}

export function registerWardenTools(server: McpServer, context: ServerContext, workspace: () => Workspace): void {
  const client = async () => {
    const origin = process.env["OPEN77_WARDEN_ORIGIN"] ?? workspace().wardenUrl;
    if (!origin) throw new WardenError("Warden is not enabled in server.jsonc (warden.enabled) and OPEN77_WARDEN_ORIGIN is not set.");
    const c = await WardenClient.fromSession(origin);
    if (!c.signedIn) throw new WardenError(`No Warden session for ${origin}. Run \`npx -y @open2077/mcp warden-login\` in a terminal (it asks for the Warden username and password there, never here).`);
    return c;
  };
  const guarded = async (run: (c: WardenClient) => Promise<string>) => {
    try {
      return text(await run(await client()));
    } catch (error) {
      return { ...text(error instanceof WardenError ? error.message : `Warden call failed: ${(error as Error).message}`), isError: true };
    }
  };

  server.registerTool(
    "open77_server_status",
    {
      title: "Live server status",
      description: "Warden's dashboard for the server next to this session: build, uptime, players, resources, load. Needs a Warden session (open77-mcp warden-login).",
      inputSchema: {},
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async () => guarded(async (c) => `dashboard from ${c.origin}:\n${pretty(await c.dashboard())}`),
  );

  server.registerTool(
    "open77_resources",
    {
      title: "Resources on the live server",
      description: "The resources the running server discovered, with their state, as Warden reports them.",
      inputSchema: {},
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async () => guarded(async (c) => pretty(await c.resources())),
  );

  server.registerTool(
    "open77_resource",
    {
      title: "Start, stop, restart, reload or validate a resource",
      description:
        "Runs one resource action on the live server through Warden. `reload` republishes an edited resource to the running session (the usual step after an edit); " +
        "`validate` runs the server's own parser and Lua compiler over the resource's files without running them. Read the log afterwards with open77_console_tail.",
      inputSchema: {
        name: z.string().min(1),
        action: z.enum(["start", "stop", "restart", "reload", "validate"]),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async ({ name, action }) => guarded(async (c) => {
      if (action === "validate") return `runtime validation of ${name}:\n${pretty(await c.validate(name))}`;
      const result = await c.control(name, action);
      return `${action} ${name}: ${result.ok ? "ok" : "FAILED"}\n${result.output}`;
    }),
  );

  server.registerTool(
    "open77_console_tail",
    {
      title: "Server log",
      description: "Recent server log entries, optionally filtered by a regex and a resource name. Use after a reload to read what the server said; errors carry the resource in brackets.",
      inputSchema: {
        pattern: z.string().optional().describe("Regex on the message (case-insensitive)"),
        resource: z.string().optional().describe("Only lines mentioning this resource"),
        lines: z.number().int().min(1).max(500).optional().describe("How many of the newest entries (default 80)"),
        after: z.number().int().min(0).optional().describe("Only entries after this sequence number, for paging"),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ pattern, resource, lines, after }) => guarded(async (c) => {
      let entries = await c.log(after ?? 0);
      const regex = pattern ? new RegExp(pattern, "i") : null;
      if (regex) entries = entries.filter((e) => regex.test(String(e.message ?? JSON.stringify(e))));
      if (resource) entries = entries.filter((e) => String(e.message ?? "").includes(resource));
      const tail = entries.slice(-(lines ?? 80));
      const last = tail[tail.length - 1];
      const rendered = tail.map((e) => `${e.timestamp ?? ""} ${e.level ?? ""} ${e.message ?? JSON.stringify(e)}`.trim());
      return [`${tail.length} of ${entries.length} entries${last?.sequence !== undefined ? ` (last sequence ${last.sequence})` : ""}`, ...rendered].join("\n");
    }),
  );

  server.registerTool(
    "open77_console_command",
    {
      title: "Run a server console command",
      description: "Runs one line at the server console with operator authority (e.g. `resources`, `ensure my_res`, `help`, or a command a resource registered). Output comes back inline; resource-claimed commands answer in the log a tick later.",
      inputSchema: { command: z.string().min(1).max(512) },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
    },
    async ({ command }) => guarded(async (c) => {
      const result = await c.command(command);
      return `${result.ok ? "ok" : "FAILED"}: ${command}\n${result.output}`;
    }),
  );

  server.registerTool(
    "open77_tunables",
    {
      title: "Tunables",
      description: "Read the live tunables every resource declared, or set one (resource + key + value). A set is applied live when the resource accepts it; the server answers whether it is pending a restart.",
      inputSchema: {
        resource: z.string().optional(),
        key: z.string().optional(),
        value: z.union([z.string(), z.number(), z.boolean()]).optional().describe("Provide to set; omit to read"),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async ({ resource, key, value }) => guarded(async (c) => {
      if (value !== undefined) {
        if (!resource || !key) return "setting a tunable needs resource and key";
        const result = await c.setTunable(resource, key, value);
        return `${resource}.${key} = ${JSON.stringify(value)}: ${result.ok ? "ok" : "FAILED"} ${result.output}${result.pending ? " (pending restart)" : ""}`;
      }
      const all = await c.tunables();
      if (resource && Array.isArray(all)) {
        const group = (all as { resource?: string; name?: string }[]).filter((g) => g.resource === resource || g.name === resource);
        return pretty(group.length ? group : `no tunables for ${resource}`);
      }
      return pretty(all);
    }),
  );

  void context;
}
