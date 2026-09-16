/**
 * The tools that only make sense next to a server: workspace detection,
 * resource validation, scaffolding. Registered by the CLI when serving over
 * stdio; the hosted endpoint never gets them (it has no filesystem to read).
 */

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { existsSync } from "node:fs";
import { readdir } from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import type { ServerContext } from "../server.js";
import { detectWorkspace, type Workspace } from "./detect.js";
import { runtimeLint, validateResource, type Finding } from "./validate.js";
import { scaffold, SCAFFOLD_KINDS } from "./scaffold.js";

function text(body: string) {
  return { content: [{ type: "text" as const, text: body }] };
}

export function registerLocalTools(server: McpServer, context: ServerContext, initial: Workspace): void {
  let workspace = initial;

  server.registerTool(
    "open77_workspace",
    {
      title: "Detected server and resources",
      description: "Where the Open77 server next to this session is, its build, its config, its resources root and the resources in it. Re-detects when called.",
      inputSchema: { serverDir: z.string().optional().describe("Override the detected server directory") },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ serverDir }) => {
      workspace = await detectWorkspace(process.cwd(), serverDir);
      const served = context.resolved.build;
      const mismatch = workspace.build && workspace.build !== served
        ? `\nNOTE: the server is ${workspace.build} but this session answers for ${served}${context.resolved.note ? ` (${context.resolved.note})` : ""}. Restart the MCP inside the server directory, or pass --server-dir, to pin it.`
        : "";
      return text([
        `server dir: ${workspace.serverDir ?? "none detected (run inside the server folder or pass serverDir)"}`,
        `server build: ${workspace.build ?? "unknown"}${workspace.build ? ` (${workspace.buildSource})` : ""}`,
        `answering for: ${served}`,
        `config: ${workspace.configFile ?? "none"}`,
        `resources root: ${workspace.resourcesRoot ?? "none"}`,
        `warden: ${workspace.wardenUrl ?? "not enabled in server.jsonc"}`,
        `resources (${workspace.resources.length}): ${workspace.resources.join(", ") || "none"}`,
      ].join("\n") + mismatch);
    },
  );

  server.registerTool(
    "open77_validate",
    {
      title: "Validate a resource",
      description:
        "Static checks of one resource directory against the served build: manifest grammar, script files, Lua syntax (5.3-compatible parser; exact 5.4 via the server's --lint when present), " +
        "unknown Open77.* natives, client natives in server scripts and the reverse, permissions used but not declared, natives newer than the build or unreleased. " +
        "Pass a resource name from open77_workspace or an absolute path.",
      inputSchema: { resource: z.string().describe("Resource name under the resources root, or a directory path") },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ resource }) => {
      const dir = await resolveResourceDir(resource, workspace);
      if (!dir) return text(`No resource ${resource}: not a directory and not under ${workspace.resourcesRoot ?? "an unknown resources root"}.`);
      const findings = await validateResource(dir, context);
      const runtime = await runtimeLint(workspace.serverBinary, dir);
      if (runtime) {
        // The runtime's syntax verdict is exact; drop the approximate parser's
        // syntax warnings when it is available.
        const exact = findings.filter((f) => !/does not parse \(Lua 5\.3 parser\)/.test(f.message));
        exact.push(...runtime);
        return text(renderFindings(dir, exact, context));
      }
      findings.push({ severity: "note", message: "runtime lint unavailable (no Open77.Server binary next to this session, or a build older than --lint); syntax was checked with a Lua 5.3 parser" });
      return text(renderFindings(dir, findings, context));
    },
  );

  server.registerTool(
    "open77_new_resource",
    {
      title: "Scaffold a resource",
      description:
        "Creates a resource that is correct by construction: manifest, lifecycle handlers, and for kinds that need it a WebUI page or the export ownership guard. " +
        "Kinds: blank, gamemode, hud, service. Writes under the resources root (or `directory`) and never overwrites an existing resource.",
      inputSchema: {
        name: z.string().regex(/^[a-z][a-z0-9_]{2,63}$/).describe("Lowercase slug; Open77 resources conventionally use the open77_ prefix, a gamemode may be bare"),
        kind: z.enum(SCAFFOLD_KINDS).default("blank"),
        directory: z.string().optional().describe("Parent directory; default the resources root"),
        summary: z.string().optional().describe("One line for the manifest comment and AGENTS.md"),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async ({ name, kind, directory, summary }) => {
      const parent = directory ? path.resolve(directory) : workspace.resourcesRoot;
      if (!parent) return text("No resources root detected; pass directory.");
      const target = path.join(parent, name);
      if (existsSync(target)) return text(`${target} already exists; not overwriting.`);
      const files = await scaffold(target, name, kind, context, summary);
      return text([`Created ${kind} resource ${name} at ${target}:`, ...files.map((f) => `- ${f}`), "", "Next: open77_validate, then `ensure " + name + "` at the server console (or open77_resource when Warden is connected)."].join("\n"));
    },
  );
}

async function resolveResourceDir(resource: string, workspace: Workspace): Promise<string | null> {
  const direct = path.resolve(resource);
  if (existsSync(path.join(direct, "open77.lua"))) return direct;
  if (!workspace.resourcesRoot) return null;
  const candidates = [path.join(workspace.resourcesRoot, resource)];
  try {
    for (const entry of await readdir(workspace.resourcesRoot, { withFileTypes: true })) {
      if (entry.isDirectory()) candidates.push(path.join(workspace.resourcesRoot, entry.name, resource));
    }
  } catch {
    /* no root */
  }
  for (const candidate of candidates) {
    if (existsSync(path.join(candidate, "open77.lua"))) return candidate;
  }
  return null;
}

export function renderFindings(dir: string, findings: Finding[], context: ServerContext): string {
  const errors = findings.filter((f) => f.severity === "error");
  const warnings = findings.filter((f) => f.severity === "warning");
  const notes = findings.filter((f) => f.severity === "note");
  const line = (f: Finding) => `- ${f.file ? `${f.file}${f.line ? `:${f.line}` : ""}: ` : ""}${f.message}${f.fix ? `\n  fix: ${f.fix}` : ""}`;
  const verdict = errors.length ? `FAIL: ${errors.length} error${errors.length === 1 ? "" : "s"}` : `OK: no errors`;
  return [
    `${verdict}, ${warnings.length} warning${warnings.length === 1 ? "" : "s"} — ${dir} — checked against build ${context.resolved.build}`,
    ...(errors.length ? ["", "Errors:", ...errors.map(line)] : []),
    ...(warnings.length ? ["", "Warnings:", ...warnings.map(line)] : []),
    ...(notes.length ? ["", "Notes:", ...notes.map(line)] : []),
  ].join("\n");
}

