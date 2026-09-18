/**
 * Static validation of one resource directory against the served build.
 *
 * What it catches, in the order it costs the most at runtime:
 *   - a manifest the server would refuse (missing `resource`, name not
 *     matching the directory, unknown directive, script not found);
 *   - Lua that does not parse (luaparse in 5.3 mode: close to 5.4, so a
 *     failure is reported as a warning and the exact verdict is the server's
 *     own `--lint`, when that build has it);
 *   - an `Open77.*` call the catalogue does not know -- on this build it does
 *     not exist, whatever it looks like. `X.await(...)` is the native `X`
 *     called in its await form, and the global `MySQL` is `Open77.database`
 *     (`conventions.ts`), so neither reads as unknown;
 *   - a client native in a server script, or the reverse; a shared script
 *     using a one-sided native;
 *   - a native whose permission the manifest does not declare;
 *   - a native newer than the served build, or in no published build;
 *   - when the resources the server loads are known (open77_workspace), a
 *     command name another loaded resource already registers on the same
 *     side -- the second registration is silent at runtime, so it is a
 *     warning here.
 *
 * Findings are facts about the files and the catalogue; the tool never
 * rewrites anything.
 */

import { execFile } from "node:child_process";
import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import luaparse from "luaparse";
import { opNumber } from "../index/builder.js";
import { NAMESPACE_ALIASES, documentsAwaitForm, namespacesOf, resolveNamespaceAlias, stripAwaitForm } from "../index/conventions.js";
import type { ApiCard, ManifestDirective } from "../index/types.js";
import type { ServerContext } from "../server.js";

export interface Finding {
  severity: "error" | "warning" | "note";
  file?: string;
  line?: number;
  message: string;
  fix?: string;
}

export interface ParsedManifest {
  scalars: Record<string, string>;
  booleans: Record<string, boolean>;
  lists: Record<string, string[]>;
  unknown: { name: string; line: number }[];
}

const RE_COMMENT_BLOCK = /--\[(=*)\[[\s\S]*?\]\1\]/g;
const RE_COMMENT_LINE = /--(?!\[=*\[).*$/gm;

/** Reads `open77.lua` the way the server's parser does: line-anchored directives. */
export function parseManifest(source: string, directives: ManifestDirective[]): ParsedManifest {
  const known = new Map<string, ManifestDirective & { plural: string }>();
  for (const d of directives) {
    known.set(d.name, { ...d, plural: d.name });
    if (d.singular) known.set(d.singular, { ...d, plural: d.name });
  }
  const stripped = source.replace(RE_COMMENT_BLOCK, (m) => m.replace(/[^\n]/g, " ")).replace(RE_COMMENT_LINE, "");
  const result: ParsedManifest = { scalars: {}, booleans: {}, lists: {}, unknown: [] };
  const lines = stripped.split("\n");
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i]!;
    const head = /^\s*([a-z_][a-z0-9_]*)\b/.exec(line);
    if (!head) continue;
    const name = head[1]!;
    const directive = known.get(name);
    if (!directive) {
      if (/^\s*[a-z_][a-z0-9_]*\s*(\(|["'{]|true|false)/.test(line)) result.unknown.push({ name, line: i + 1 });
      continue;
    }
    const rest = line.slice(head[0].length);
    if (directive.form === "boolean") {
      const value = /^\s*\(?\s*(true|false)\s*\)?\s*$/.exec(rest);
      if (value) result.booleans[directive.plural] = value[1] === "true";
      continue;
    }
    const scalar = /^\s*\(?\s*(['"])(.*?)\1\s*\)?\s*$/.exec(rest);
    if (directive.form === "scalar") {
      if (scalar) result.scalars[directive.plural] = scalar[2]!;
      continue;
    }
    const list = result.lists[directive.plural] ?? [];
    if (scalar) list.push(scalar[2]!);
    else {
      // `permissions { "a", "b" }` possibly spread over several lines
      let block = rest;
      let j = i;
      while (!block.includes("}") && j + 1 < lines.length) {
        j += 1;
        block += "\n" + lines[j]!;
      }
      const inner = /\{([\s\S]*?)\}/.exec(block);
      if (inner) {
        for (const item of inner[1]!.matchAll(/(['"])(.*?)\1/g)) list.push(item[2]!);
        i = j;
      }
    }
    result.lists[directive.plural] = list;
  }
  return result;
}

async function expandGlob(root: string, pattern: string): Promise<string[]> {
  const normalised = pattern.replace(/\\/g, "/");
  if (!/[*?]/.test(normalised)) {
    const file = path.join(root, normalised);
    try {
      return (await stat(file)).isFile() ? [normalised] : [];
    } catch {
      return [];
    }
  }
  const regex = new RegExp("^" + normalised.split("/").map((part) => part.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*\*/g, "\0").replace(/\*/g, "[^/]*").replace(/\?/g, "[^/]").replace(/\0/g, ".*")).join("/") + "$");
  const found: string[] = [];
  const walk = async (dir: string, prefix: string) => {
    for (const entry of await readdir(dir, { withFileTypes: true }).catch(() => [])) {
      const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.isDirectory()) await walk(path.join(dir, entry.name), relative);
      else if (regex.test(relative)) found.push(relative);
    }
  };
  await walk(root, "");
  return found.sort();
}

// The heads a dotted native can start with: the catalogued namespaces' roots
// and the globals that alias one of them (`MySQL` for `Open77.database`).
const ALIAS_HEADS = NAMESPACE_ALIASES.map((a) => a.alias);
const RE_NATIVE = new RegExp(`\\b((?:${["Open77", "WebUI", "Citizen", ...ALIAS_HEADS].join("|")})(?:\\.[A-Za-z_]\\w*)+)\\s*\\(`, "g");
const RE_GLOBAL = /(?<![\w.:])([A-Z][A-Za-z0-9]*)\s*\(/g;
// `Open77.vehicles.flags.locked`, `local send = Open77.chat.send`: a dotted
// reference that is not a call. Resolved to the longest catalogued prefix, so a
// constant table's member is checked against the table's card.
const RE_NATIVE_REF = new RegExp(`(?<![\\w.:])((?:${["Open77", "WebUI", ...ALIAS_HEADS].join("|")})(?:\\.[A-Za-z_]\\w*)+)(?![\\w.(]|\\s*\\()`, "g");
// `RegisterCommand("heal", ...)` / `Open77.runtime.registerCommand('heal', ...)`
// with a literal name: what a collision scan can see without running anything.
const RE_REGISTER_COMMAND = /\b(?:RegisterCommand|Open77\.runtime\.registerCommand)\s*\(\s*(['"])([^'"\n]+)\1/g;
// What neither sandbox has (measured on op77.75: each is nil): the libraries
// the runtimes never open and the base functions they retract.
const RE_SANDBOX_LIBRARY = /(?<![\w.:])(os|io|debug|package)\s*[.[]/g;
const RE_SANDBOX_FUNCTION = /(?<![\w.:])(require|load|loadfile|dofile|collectgarbage)\s*\(/g;
// The client removes two more base functions and the raw coroutine constructors.
const RE_CLIENT_SANDBOX = /(?<![\w.:])(getmetatable|setmetatable)\s*\(|\b(coroutine\.(?:create|resume|wrap)|string\.dump)\s*\(/g;

export interface ValidateOptions {
  /**
   * Absolute directories of the other resources the server loads (what
   * open77_workspace lists), for the command-name collision check. The
   * validated directory itself is skipped. Without it the check is off: the
   * validator has no other way to know what else the server runs.
   */
  loadedResources?: string[];
}

export async function validateResource(dir: string, context: ServerContext, options: ValidateOptions = {}): Promise<Finding[]> {
  const findings: Finding[] = [];
  const { index, resolved } = context;
  const served = opNumber(resolved.build);
  const manifestFile = path.join(dir, "open77.lua");
  let source: string;
  try {
    source = await readFile(manifestFile, "utf8");
  } catch {
    return [{ severity: "error", file: "open77.lua", message: "missing open77.lua manifest" }];
  }
  if (Buffer.byteLength(source, "utf8") > 262144) findings.push({ severity: "error", file: "open77.lua", message: "manifest exceeds 256 KiB" });
  if (source.charCodeAt(0) === 0xfeff) findings.push({ severity: "error", file: "open77.lua", message: "manifest starts with a UTF-8 BOM; the Lua loader rejects it", fix: "save the file as UTF-8 without BOM" });

  const manifest = parseManifest(source, index.manifestSchema.directives);
  const name = manifest.scalars["resource"];
  const dirName = path.basename(dir);
  if (!name) findings.push({ severity: "error", file: "open77.lua", message: "`resource \"<name>\"` is required" });
  else if (!/^[a-z][a-z0-9_]{2,63}$/.test(name)) findings.push({ severity: "error", file: "open77.lua", message: `resource name ${name} is not a lowercase slug (letters, digits, underscores, 3-64 chars, starting with a letter)` });
  else if (name.toLowerCase() !== dirName.toLowerCase()) findings.push({ severity: "error", file: "open77.lua", message: `resource name ${name} does not match the directory ${dirName}`, fix: `rename the directory to ${name} or the directive to "${dirName}"` });
  for (const unknown of manifest.unknown) findings.push({ severity: "error", file: "open77.lua", line: unknown.line, message: `unknown manifest directive ${unknown.name}`, fix: "see open77_manifest_schema" });
  const reloadPolicy = manifest.scalars["reload_policy"];
  if (reloadPolicy && reloadPolicy !== "transactional") findings.push({ severity: "warning", file: "open77.lua", message: `reload_policy ${reloadPolicy} is not the documented transactional policy` });

  const declared = new Set(manifest.lists["permissions"] ?? []);
  const knownPermissions = new Set(index.permissions.permissions.map((p) => p.name));
  for (const permission of declared) {
    if (!knownPermissions.has(permission)) findings.push({ severity: "error", file: "open77.lua", message: `permission ${permission} is not one the runtime enforces`, fix: "open77_permissions lists the real names" });
  }
  for (const dependency of manifest.lists["dependencies"] ?? []) {
    // The runtime grammar (ServerResourceHost.ValidateDependency): a name, then
    // optional constraints separated by spaces -- `open77_notifications >=1.0.0`.
    const [depName, ...constraints] = dependency.trim().split(/\s+/);
    if (!depName || !/^[a-z][a-z0-9_]{2,63}$/.test(depName)) findings.push({ severity: "warning", file: "open77.lua", message: `dependency ${dependency}: ${depName ?? dependency} is not a resource slug` });
    for (const constraint of constraints) {
      if (!/^(?:>=|<=|==|=|>|<)\d+(?:\.\d+){0,2}$/.test(constraint)) {
        findings.push({ severity: "error", file: "open77.lua", message: `dependency ${dependency}: constraint ${constraint} is not <op><version> with op in >=, <=, >, <, =, == and a 1-3 part version`, fix: `dependency "${depName} >=1.0.0"` });
      }
    }
  }

  type Side = "client" | "server" | "shared";
  const scripts: { side: Side; file: string }[] = [];
  for (const [key, side] of [["client_scripts", "client"], ["server_scripts", "server"], ["shared_scripts", "shared"]] as const) {
    for (const pattern of manifest.lists[key] ?? []) {
      const files = await expandGlob(dir, pattern);
      if (!files.length) findings.push({ severity: "error", file: "open77.lua", message: `${key.replace(/s$/, "")} ${pattern} matches no file` });
      for (const file of files) {
        if (!file.endsWith(".lua")) findings.push({ severity: "error", file, message: `${key} entries must be .lua files` });
        else scripts.push({ side, file });
      }
    }
  }
  for (const key of ["files", "web_files", "preload_mods"] as const) {
    for (const pattern of manifest.lists[key] ?? []) {
      if (!(await expandGlob(dir, pattern)).length) findings.push({ severity: key === "preload_mods" ? "error" : "warning", file: "open77.lua", message: `${key} ${pattern} matches no file` });
    }
  }
  if (!scripts.length) {
    // A passive library publishes modules under `files` for a dependant's
    // require('@name/...') and needs no script of its own; both hosts accept
    // it. With neither scripts nor files the manifest is refused on both sides
    // (client `no_client_scripts`, server "Resource contains no scripts or files.").
    if ((manifest.lists["files"] ?? []).length) findings.push({ severity: "note", file: "open77.lua", message: "no client_script, server_script or shared_script: a passive library; its files are served to dependants through require('@" + (name ?? "name") + "/...')" });
    else findings.push({ severity: "error", file: "open77.lua", message: "no client_script, server_script, shared_script or files: the server and the client both refuse this manifest", fix: "add a script, or publish modules under files { ... } for a passive library" });
  }

  const byQualified = new Map<string, ApiCard[]>();
  for (const card of index.cards) {
    const list = byQualified.get(card.qualified) ?? [];
    list.push(card);
    byQualified.set(card.qualified, list);
  }
  const globalsBySide = { client: new Set<string>(), server: new Set<string>() };
  for (const card of index.cards) if (card.namespace === "_G") globalsBySide[card.runtime].add(card.name);
  const namespaces = namespacesOf(index.cards);
  const usedPermissions = new Map<string, Set<string>>();

  for (const script of scripts) {
    const file = path.join(dir, script.file);
    const code = await readFile(file, "utf8").catch(() => null);
    if (code === null) continue;
    if (code.charCodeAt(0) === 0xfeff) findings.push({ severity: "error", file: script.file, message: "file starts with a UTF-8 BOM; the resource dies silently on load", fix: "save as UTF-8 without BOM" });
    try {
      luaparse.parse(code.replace(/^﻿/, ""), { luaVersion: "5.3", comments: false, locations: false });
    } catch (error) {
      const err = error as { message: string; line?: number };
      findings.push({ severity: "warning", file: script.file, line: err.line, message: `does not parse (Lua 5.3 parser): ${err.message}`, fix: "if this is Lua 5.4-only syntax (<const>, <close>) ignore; otherwise fix the syntax. The server's --lint is exact." });
    }
    const stripped = code.replace(RE_COMMENT_BLOCK, (m) => m.replace(/[^\n]/g, " ")).replace(RE_COMMENT_LINE, "");
    const lines = stripped.split("\n");
    // A script that defines its own `load` or `os` is not reaching for the
    // absent library; the sandbox checks skip names it declares as locals.
    const localNames = new Set<string>();
    for (const m of stripped.matchAll(/\blocal\s+(?:function\s+)?([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)/g)) {
      for (const n of m[1]!.split(",")) localNames.add(n.trim());
    }
    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i]!;
      // `written` is the name as the script spells it; `qualified` is the card
      // it resolves to once the namespace alias (`MySQL.` -> `Open77.database.`)
      // and the `.await` sub-form are folded away. Messages show both when they
      // differ, so the line is findable and the card is nameable.
      const check = (written: string, isGlobal: boolean) => {
        const aliased = resolveNamespaceAlias(written, namespaces);
        const { qualified, awaited } = stripAwaitForm(aliased, (n) => byQualified.has(n));
        const shown = qualified === written ? written : `${written} (${qualified})`;
        const cards = byQualified.get(qualified) ?? [];
        if (!cards.length) {
          if (!isGlobal) findings.push({ severity: "error", file: script.file, line: i + 1, message: `${shown} is not in the catalogue for ${resolved.build}: it does not exist on this build`, fix: `open77_search "${qualified.split(".").slice(-1)[0]}" for the real name` });
          return;
        }
        const sides = new Set(cards.map((c) => c.runtime));
        const wanted: ("client" | "server")[] = script.side === "shared" ? ["client", "server"] : [script.side];
        const missing = wanted.filter((s) => !sides.has(s));
        if (missing.length && script.side !== "shared") {
          findings.push({ severity: "error", file: script.file, line: i + 1, message: `${shown} is a ${[...sides].join("/")} native used in a ${script.side} script`, fix: `move the call to a ${[...sides][0]}_script, or use the ${script.side} equivalent (open77_api ${qualified})` });
          return;
        }
        if (missing.length) findings.push({ severity: "warning", file: script.file, line: i + 1, message: `${shown} exists only on ${[...sides].join("/")}; a shared script runs on both`, fix: "guard with IsDuplicityVersion() or move to a one-sided script" });
        for (const card of cards.filter((c) => wanted.includes(c.runtime))) {
          if (!card.since) findings.push({ severity: "error", file: script.file, line: i + 1, message: `${shown} (${card.runtime}) is in no published server build`, fix: "wait for a release or use another native" });
          else if (opNumber(card.since) > served) findings.push({ severity: "error", file: script.file, line: i + 1, message: `${shown} (${card.runtime}) needs ${card.since}; this build is ${resolved.build}`, fix: `open77_changes ${resolved.build} ${card.since} lists what the update brings` });
          if (awaited && !documentsAwaitForm(card)) findings.push({ severity: "warning", file: script.file, line: i + 1, message: `${written}: the ${card.runtime} card of ${qualified} documents no .await form on ${resolved.build}`, fix: `open77_api ${card.route_id} shows the forms it has; a native returning an Open77.Promise is awaited with :await() on the promise` });
          for (const permission of card.permissions) {
            if (!usedPermissions.has(permission)) usedPermissions.set(permission, new Set());
            usedPermissions.get(permission)!.add(written);
          }
        }
      };
      for (const match of line.matchAll(RE_NATIVE)) check(match[1]!, false);
      for (const match of line.matchAll(RE_GLOBAL)) {
        const global = match[1]!;
        if (globalsBySide.client.has(global) || globalsBySide.server.has(global)) check(global, true);
      }
      for (const match of line.matchAll(RE_NATIVE_REF)) {
        const written = match[1]!;
        const aliased = resolveNamespaceAlias(written, namespaces);
        const segments = aliased.split(".");
        // Longest catalogued prefix with at least a namespace and a member.
        let hit: string | null = null;
        for (let n = segments.length; n >= 3; n -= 1) {
          const candidate = segments.slice(0, n).join(".");
          if (byQualified.has(candidate)) { hit = candidate; break; }
        }
        // The alias only rewrites the head, so the written prefix is the written
        // name minus the same tail the hit dropped.
        if (hit) check(written.slice(0, written.length - (aliased.length - hit.length)), false);
        else if (segments.length >= 3 && namespaces.has(segments.slice(0, 2).join("."))) {
          // A member of a real namespace that no card describes: as unknown as a call would be.
          const member = segments.slice(0, 3).join(".");
          const shown = written.startsWith(member) ? member : `${written.split(".").slice(0, 2).join(".")} (${member})`;
          findings.push({ severity: "error", file: script.file, line: i + 1, message: `${shown} is not in the catalogue for ${resolved.build}: it does not exist on this build`, fix: `open77_namespace ${segments.slice(0, 2).join(".")} lists the members` });
        }
      }
      for (const match of line.matchAll(RE_SANDBOX_LIBRARY)) {
        if (!localNames.has(match[1]!)) findings.push({ severity: "error", file: script.file, line: i + 1, message: `${match[1]} is nil in the ${script.side === "shared" ? "client and server" : script.side} sandbox (no os, io, debug or package library)`, fix: match[1] === "os" ? "time: Open77.time.unix() / GetUnixTime() (wall clock), Open77.time.monotonic() / GetGameTimer() (elapsed); persistence: Open77.kvp or the database API" : "the sandbox has math, string, table, utf8, coroutine and json only" });
      }
      for (const match of line.matchAll(RE_SANDBOX_FUNCTION)) {
        if (!localNames.has(match[1]!)) findings.push({ severity: "error", file: script.file, line: i + 1, message: `${match[1]} is nil in the sandbox (no require, load, loadfile, dofile or collectgarbage)`, fix: match[1] === "require" ? "list every file in the manifest (server_script / client_script / shared_script) instead; a later file sees the globals of an earlier one" : "there is no code loading at run time" });
      }
      if (script.side !== "server") {
        for (const match of line.matchAll(RE_CLIENT_SANDBOX)) {
          const what = match[1] ?? match[2]!;
          if (!localNames.has(what)) findings.push({ severity: "error", file: script.file, line: i + 1, message: `${what} is nil in the client sandbox`, fix: what.startsWith("coroutine") ? "CreateThread(fn) / Wait(ms) are the client's coroutines" : "metatables are not reachable from a resource" });
        }
      }
    }
  }

  for (const [permission, callers] of usedPermissions) {
    if (!declared.has(permission)) findings.push({ severity: "error", file: "open77.lua", message: `permission ${permission} is required by ${[...callers].slice(0, 4).join(", ")}${callers.size > 4 ? "…" : ""} but not declared`, fix: `add "${permission}" to permissions { }` });
  }
  for (const permission of declared) {
    if (!usedPermissions.has(permission)) findings.push({ severity: "note", file: "open77.lua", message: `permission ${permission} is declared but no catalogued native in the scripts checks it (it may gate a service, an event or a WebUI feature)` });
  }
  findings.push(...(await commandCollisions(dir, options.loadedResources ?? [], index.manifestSchema.directives)));
  return findings;
}

export interface RegisteredCommand {
  name: string;
  side: "client" | "server" | "shared";
  file: string;
  line: number;
}

/**
 * Every `RegisterCommand("<literal>", ...)` in the scripts a resource's
 * manifest lists, with the side the script runs on. Names built at run time
 * (`RegisterCommand(prefix .. "x", ...)`) are invisible to this scan, which
 * is why its findings are warnings.
 */
export async function registeredCommands(dir: string, directives: ManifestDirective[]): Promise<RegisteredCommand[]> {
  const source = await readFile(path.join(dir, "open77.lua"), "utf8").catch(() => null);
  if (source === null) return [];
  const manifest = parseManifest(source, directives);
  const found: RegisteredCommand[] = [];
  for (const [key, side] of [["client_scripts", "client"], ["server_scripts", "server"], ["shared_scripts", "shared"]] as const) {
    for (const pattern of manifest.lists[key] ?? []) {
      for (const file of await expandGlob(dir, pattern)) {
        if (!file.endsWith(".lua")) continue;
        const code = await readFile(path.join(dir, file), "utf8").catch(() => null);
        if (code === null) continue;
        const stripped = code.replace(RE_COMMENT_BLOCK, (m) => m.replace(/[^\n]/g, " ")).replace(RE_COMMENT_LINE, "");
        const lines = stripped.split("\n");
        for (let i = 0; i < lines.length; i += 1) {
          for (const match of lines[i]!.matchAll(RE_REGISTER_COMMAND)) found.push({ name: match[2]!.trim(), side, file, line: i + 1 });
        }
      }
    }
  }
  return found;
}

const sameSide = (a: RegisteredCommand["side"], b: RegisteredCommand["side"]) => a === b || a === "shared" || b === "shared";

/**
 * A command the validated resource registers under a name another loaded
 * resource already registers on the same side. The client and the server
 * keep separate command registries, so a client `/heal` next to a server
 * `/heal` is not a collision; two server `/heal` are, and the runtime does
 * not say so -- the second handler simply never runs.
 */
export async function commandCollisions(dir: string, loadedResources: string[], directives: ManifestDirective[]): Promise<Finding[]> {
  if (!loadedResources.length) return [];
  const mine = await registeredCommands(dir, directives);
  if (!mine.length) return [];
  const self = path.resolve(dir).toLowerCase();
  const findings: Finding[] = [];
  for (const other of loadedResources) {
    if (path.resolve(other).toLowerCase() === self) continue;
    const theirs = await registeredCommands(other, directives);
    if (!theirs.length) continue;
    const label = path.basename(other);
    for (const command of mine) {
      for (const taken of theirs) {
        if (taken.name !== command.name || !sameSide(taken.side, command.side)) continue;
        findings.push({
          severity: "warning",
          file: command.file,
          line: command.line,
          message: `command /${command.name} is already registered by ${label} (${taken.file}:${taken.line}, ${taken.side} side); the runtime keeps one handler and never says which`,
          fix: `rename the command, or drop the duplicate if ${label} is the owner`,
        });
      }
    }
  }
  return findings;
}


interface RuntimeReport {
  version?: string;
  reports?: { directory: string; resource: string | null; ok: boolean; scripts: number; findings: { severity: string; file?: string | null; line?: number | null; message: string }[] }[];
}

/**
 * The runtime's own verdict, from `Open77.Server --lint <dir>`: the server's
 * manifest parser and its embedded Lua 5.4 compiler, nothing executed. Null
 * when the binary is not next to this session or predates the flag; the
 * caller then says the exact check is unavailable rather than pretending.
 */
export async function runtimeLint(serverBinary: string | null, dir: string): Promise<Finding[] | null> {
  if (!serverBinary) return null;
  const run = promisify(execFile);
  const isDll = serverBinary.toLowerCase().endsWith(".dll");
  const command = isDll ? "dotnet" : serverBinary;
  const args = isDll ? [serverBinary, "--lint", dir] : ["--lint", dir];
  let stdout = "";
  try {
    const result = await run(command, args, { timeout: 30000, maxBuffer: 4 * 1024 * 1024, windowsHide: true });
    stdout = result.stdout;
  } catch (error) {
    const failed = error as { stdout?: string; code?: number | string };
    // Exit code 1 means findings; anything else means the flag is not there.
    if (failed.code !== 1 || !failed.stdout) return null;
    stdout = failed.stdout;
  }
  let parsed: RuntimeReport;
  try {
    parsed = JSON.parse(stdout) as RuntimeReport;
  } catch {
    return null;
  }
  const report = parsed.reports?.[0];
  if (!report) return null;
  const findings: Finding[] = report.findings.map((f) => ({
    severity: f.severity === "error" ? "error" : "warning",
    file: f.file ?? undefined,
    line: f.line ?? undefined,
    message: `[runtime ${parsed.version ?? ""}] ${f.message}`.replace(/\s+\]/, "]"),
  }));
  findings.push({ severity: "note", message: `runtime lint (${parsed.version ?? "server"}): ${report.ok ? "manifest and every script compile" : "see errors above"}; ${report.scripts} scripts compiled with the server's own Lua` });
  return findings;
}
