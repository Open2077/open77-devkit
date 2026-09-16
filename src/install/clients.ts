/**
 * Registers or removes the `open77` MCP entry in every agent client found on
 * this machine. Idempotent: an entry that already says the same thing is
 * left alone; an entry that says something else is reported and kept unless
 * `--force`. Never writes a credential, a Warden origin or a server path into
 * a client config -- the server directory is passed as a plain argument only
 * when the user asked for it, and the default is "the current directory".
 *
 * Client config formats, as of September 2026:
 *   Claude Code      `claude mcp add` when the CLI exists, else ~/.claude.json { mcpServers }
 *   Codex CLI        ~/.codex/config.toml  [mcp_servers.open77] command/args
 *   Cursor           ~/.cursor/mcp.json (or ./.cursor/mcp.json with --project) { mcpServers }
 *   VS Code          user mcp.json (Code/User/mcp.json) { servers: { open77: { type: "stdio" } } }
 *   Claude Desktop   claude_desktop_config.json { mcpServers }
 *   Windsurf         ~/.codeium/windsurf/mcp_config.json { mcpServers }
 *   Gemini CLI       ~/.gemini/settings.json { mcpServers }
 */

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";

export const SERVER_KEY = "open77";

export interface InstallSpec {
  command: string;
  args: string[];
}

export interface ClientTarget {
  name: string;
  file: string;
  /** Whether the client is present on this machine (its config directory or binary exists). */
  detected: boolean;
  kind: "json-mcpServers" | "json-servers" | "toml-mcp_servers";
}

export interface InstallResult {
  name: string;
  file: string;
  action: "added" | "updated" | "unchanged" | "kept-different" | "removed" | "absent" | "skipped";
  detail?: string;
}

function home(...parts: string[]): string {
  return path.join(os.homedir(), ...parts);
}

function vscodeUserDir(): string {
  if (process.platform === "win32") return path.join(process.env["APPDATA"] ?? home("AppData", "Roaming"), "Code", "User");
  if (process.platform === "darwin") return home("Library", "Application Support", "Code", "User");
  return home(".config", "Code", "User");
}

function claudeDesktopFile(): string {
  if (process.platform === "win32") return path.join(process.env["APPDATA"] ?? home("AppData", "Roaming"), "Claude", "claude_desktop_config.json");
  if (process.platform === "darwin") return home("Library", "Application Support", "Claude", "claude_desktop_config.json");
  return home(".config", "Claude", "claude_desktop_config.json");
}

export function targets(options: { project?: string } = {}): ClientTarget[] {
  const cursorFile = options.project ? path.join(options.project, ".cursor", "mcp.json") : home(".cursor", "mcp.json");
  const list: ClientTarget[] = [
    { name: "Claude Code", file: home(".claude.json"), detected: existsSync(home(".claude")) || existsSync(home(".claude.json")), kind: "json-mcpServers" },
    { name: "Codex CLI", file: home(".codex", "config.toml"), detected: existsSync(home(".codex")), kind: "toml-mcp_servers" },
    { name: "Cursor", file: cursorFile, detected: existsSync(home(".cursor")) || Boolean(options.project), kind: "json-mcpServers" },
    { name: "VS Code", file: path.join(vscodeUserDir(), "mcp.json"), detected: existsSync(vscodeUserDir()), kind: "json-servers" },
    { name: "Claude Desktop", file: claudeDesktopFile(), detected: existsSync(path.dirname(claudeDesktopFile())), kind: "json-mcpServers" },
    { name: "Windsurf", file: home(".codeium", "windsurf", "mcp_config.json"), detected: existsSync(home(".codeium", "windsurf")), kind: "json-mcpServers" },
    { name: "Gemini CLI", file: home(".gemini", "settings.json"), detected: existsSync(home(".gemini")), kind: "json-mcpServers" },
  ];
  return list;
}

export function defaultSpec(serverDir?: string): InstallSpec {
  const args = ["-y", "@open2077/mcp"];
  if (serverDir) args.push("--server-dir", serverDir);
  return { command: "npx", args };
}

async function readJsonFile(file: string): Promise<Record<string, unknown>> {
  try {
    const text = await readFile(file, "utf8");
    return text.trim() ? (JSON.parse(text) as Record<string, unknown>) : {};
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return {};
    throw new Error(`${file} is not valid JSON: ${(error as Error).message}`);
  }
}

async function writeJsonFile(file: string, data: unknown): Promise<void> {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(data, null, 2) + "\n", "utf8");
}

function sameSpec(existing: unknown, spec: InstallSpec): boolean {
  if (!existing || typeof existing !== "object") return false;
  const entry = existing as { command?: string; args?: string[] };
  return entry.command === spec.command && JSON.stringify(entry.args ?? []) === JSON.stringify(spec.args);
}

async function installJson(target: ClientTarget, spec: InstallSpec, force: boolean): Promise<InstallResult> {
  const root = await readJsonFile(target.file);
  const key = target.kind === "json-servers" ? "servers" : "mcpServers";
  const servers = ((root[key] as Record<string, unknown> | undefined) ?? {});
  const entry = target.kind === "json-servers" ? { type: "stdio", command: spec.command, args: spec.args } : { command: spec.command, args: spec.args };
  const current = servers[SERVER_KEY];
  if (current && sameSpec(current, spec)) return { name: target.name, file: target.file, action: "unchanged" };
  if (current && !force) return { name: target.name, file: target.file, action: "kept-different", detail: JSON.stringify(current) };
  servers[SERVER_KEY] = entry;
  root[key] = servers;
  await writeJsonFile(target.file, root);
  return { name: target.name, file: target.file, action: current ? "updated" : "added" };
}

async function removeJson(target: ClientTarget): Promise<InstallResult> {
  if (!existsSync(target.file)) return { name: target.name, file: target.file, action: "absent" };
  const root = await readJsonFile(target.file);
  const key = target.kind === "json-servers" ? "servers" : "mcpServers";
  const servers = root[key] as Record<string, unknown> | undefined;
  if (!servers || !(SERVER_KEY in servers)) return { name: target.name, file: target.file, action: "absent" };
  delete servers[SERVER_KEY];
  await writeJsonFile(target.file, root);
  return { name: target.name, file: target.file, action: "removed" };
}

const TOML_HEADER = `[mcp_servers.${SERVER_KEY}]`;

function tomlBlock(spec: InstallSpec): string {
  return `${TOML_HEADER}\ncommand = ${JSON.stringify(spec.command)}\nargs = ${JSON.stringify(spec.args)}\n`;
}

function splitToml(text: string): { before: string; block: string | null; after: string } {
  const start = text.indexOf(TOML_HEADER);
  if (start < 0) return { before: text, block: null, after: "" };
  const rest = text.slice(start + TOML_HEADER.length);
  const next = rest.search(/^\s*\[/m);
  const end = next < 0 ? text.length : start + TOML_HEADER.length + next;
  return { before: text.slice(0, start), block: text.slice(start, end), after: text.slice(end) };
}

async function installToml(target: ClientTarget, spec: InstallSpec, force: boolean): Promise<InstallResult> {
  let text = "";
  try {
    text = await readFile(target.file, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
  const parts = splitToml(text);
  const wanted = tomlBlock(spec);
  if (parts.block !== null) {
    const normalise = (s: string) => s.replace(/\s+/g, " ").trim();
    if (normalise(parts.block) === normalise(wanted)) return { name: target.name, file: target.file, action: "unchanged" };
    if (!force) return { name: target.name, file: target.file, action: "kept-different", detail: parts.block.trim() };
  }
  const before = parts.before.replace(/\s*$/, "");
  const after = parts.after.replace(/^\s*/, "");
  const assembled = [before, wanted.trim(), after].filter(Boolean).join("\n\n") + "\n";
  await mkdir(path.dirname(target.file), { recursive: true });
  await writeFile(target.file, assembled, "utf8");
  return { name: target.name, file: target.file, action: parts.block !== null ? "updated" : "added" };
}

async function removeToml(target: ClientTarget): Promise<InstallResult> {
  if (!existsSync(target.file)) return { name: target.name, file: target.file, action: "absent" };
  const text = await readFile(target.file, "utf8");
  const parts = splitToml(text);
  if (parts.block === null) return { name: target.name, file: target.file, action: "absent" };
  const assembled = [parts.before.replace(/\s*$/, ""), parts.after.replace(/^\s*/, "")].filter(Boolean).join("\n\n") + "\n";
  await writeFile(target.file, assembled.trim() ? assembled : "", "utf8");
  return { name: target.name, file: target.file, action: "removed" };
}

/** Claude Code prefers its own CLI, which handles scopes and its config layout. */
function claudeCli(): string | null {
  const candidates = process.platform === "win32" ? ["claude.cmd", "claude.exe", "claude"] : ["claude"];
  for (const candidate of candidates) {
    try {
      execFileSync(candidate, ["--version"], { stdio: "ignore", timeout: 8000 });
      return candidate;
    } catch {
      /* try the next spelling */
    }
  }
  return null;
}

export interface InstallOptions {
  serverDir?: string;
  project?: string;
  force?: boolean;
  only?: string[];
  /** Skip clients that were not detected (default true). */
  detectedOnly?: boolean;
}

export async function installAll(options: InstallOptions): Promise<InstallResult[]> {
  const spec = defaultSpec(options.serverDir);
  const results: InstallResult[] = [];
  for (const target of targets({ project: options.project })) {
    if (options.only && !options.only.some((n) => target.name.toLowerCase().includes(n.toLowerCase()))) continue;
    if ((options.detectedOnly ?? true) && !target.detected) {
      results.push({ name: target.name, file: target.file, action: "skipped", detail: "not detected on this machine" });
      continue;
    }
    try {
      if (target.name === "Claude Code") {
        const cli = claudeCli();
        if (cli) {
          const existing = await readJsonFile(target.file);
          const current = (existing["mcpServers"] as Record<string, unknown> | undefined)?.[SERVER_KEY];
          if (current && sameSpec(current, spec)) {
            results.push({ name: target.name, file: target.file, action: "unchanged" });
            continue;
          }
          if (current && !options.force) {
            results.push({ name: target.name, file: target.file, action: "kept-different", detail: JSON.stringify(current) });
            continue;
          }
          if (current) execFileSync(cli, ["mcp", "remove", "-s", "user", SERVER_KEY], { stdio: "ignore", timeout: 20000 });
          execFileSync(cli, ["mcp", "add", "-s", "user", SERVER_KEY, "--", spec.command, ...spec.args], { stdio: "ignore", timeout: 20000 });
          results.push({ name: target.name, file: `claude mcp add -s user ${SERVER_KEY}`, action: current ? "updated" : "added" });
          continue;
        }
      }
      results.push(target.kind === "toml-mcp_servers" ? await installToml(target, spec, Boolean(options.force)) : await installJson(target, spec, Boolean(options.force)));
    } catch (error) {
      results.push({ name: target.name, file: target.file, action: "skipped", detail: (error as Error).message });
    }
  }
  return results;
}

export async function uninstallAll(options: { project?: string; only?: string[] } = {}): Promise<InstallResult[]> {
  const results: InstallResult[] = [];
  for (const target of targets({ project: options.project })) {
    if (options.only && !options.only.some((n) => target.name.toLowerCase().includes(n.toLowerCase()))) continue;
    try {
      if (target.name === "Claude Code") {
        const cli = claudeCli();
        if (cli) {
          try {
            execFileSync(cli, ["mcp", "remove", "-s", "user", SERVER_KEY], { stdio: "ignore", timeout: 20000 });
            results.push({ name: target.name, file: `claude mcp remove ${SERVER_KEY}`, action: "removed" });
          } catch {
            results.push({ name: target.name, file: target.file, action: "absent" });
          }
          continue;
        }
      }
      results.push(target.kind === "toml-mcp_servers" ? await removeToml(target) : await removeJson(target));
    } catch (error) {
      results.push({ name: target.name, file: target.file, action: "skipped", detail: (error as Error).message });
    }
  }
  return results;
}
