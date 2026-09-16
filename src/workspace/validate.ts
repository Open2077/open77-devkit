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
 *     not exist, whatever it looks like;
 *   - a client native in a server script, or the reverse; a shared script
 *     using a one-sided native;
 *   - a native whose permission the manifest does not declare;
 *   - a native newer than the served build, or in no published build.
 *
 * Findings are facts about the files and the catalogue; the tool never
 * rewrites anything.
 */

import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import luaparse from "luaparse";
import { opNumber } from "../index/builder.js";
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

const RE_NATIVE = /\b((?:Open77|WebUI|Citizen|MySQL)(?:\.[A-Za-z_]\w*)+)\s*\(/g;
const RE_GLOBAL = /(?<![\w.:])([A-Z][A-Za-z0-9]*)\s*\(/g;

export async function validateResource(dir: string, context: ServerContext): Promise<Finding[]> {
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
    if (!/^[a-z][a-z0-9_]{2,63}$/.test(dependency)) findings.push({ severity: "warning", file: "open77.lua", message: `dependency ${dependency} is not a resource slug` });
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
  if (!scripts.length) findings.push({ severity: "warning", file: "open77.lua", message: "no client_script, server_script or shared_script: the resource does nothing" });

  const byQualified = new Map<string, ApiCard[]>();
  for (const card of index.cards) {
    const list = byQualified.get(card.qualified) ?? [];
    list.push(card);
    byQualified.set(card.qualified, list);
  }
  const globalsBySide = { client: new Set<string>(), server: new Set<string>() };
  for (const card of index.cards) if (card.namespace === "_G") globalsBySide[card.runtime].add(card.name);
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
    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i]!;
      const check = (qualified: string, isGlobal: boolean) => {
        const cards = byQualified.get(qualified) ?? [];
        if (!cards.length) {
          if (!isGlobal) findings.push({ severity: "error", file: script.file, line: i + 1, message: `${qualified} is not in the catalogue for ${resolved.build}: it does not exist on this build`, fix: `open77_search "${qualified.split(".").slice(-1)[0]}" for the real name` });
          return;
        }
        const sides = new Set(cards.map((c) => c.runtime));
        const wanted: ("client" | "server")[] = script.side === "shared" ? ["client", "server"] : [script.side];
        const missing = wanted.filter((s) => !sides.has(s));
        if (missing.length && script.side !== "shared") {
          findings.push({ severity: "error", file: script.file, line: i + 1, message: `${qualified} is a ${[...sides].join("/")} native used in a ${script.side} script`, fix: `move the call to a ${[...sides][0]}_script, or use the ${script.side} equivalent (open77_api ${qualified})` });
          return;
        }
        if (missing.length) findings.push({ severity: "warning", file: script.file, line: i + 1, message: `${qualified} exists only on ${[...sides].join("/")}; a shared script runs on both`, fix: "guard with IsDuplicityVersion() or move to a one-sided script" });
        for (const card of cards.filter((c) => wanted.includes(c.runtime))) {
          if (!card.since) findings.push({ severity: "error", file: script.file, line: i + 1, message: `${qualified} (${card.runtime}) is in no published server build`, fix: "wait for a release or use another native" });
          else if (opNumber(card.since) > served) findings.push({ severity: "error", file: script.file, line: i + 1, message: `${qualified} (${card.runtime}) needs ${card.since}; this build is ${resolved.build}`, fix: `open77_changes ${resolved.build} ${card.since} lists what the update brings` });
          for (const permission of card.permissions) {
            if (!usedPermissions.has(permission)) usedPermissions.set(permission, new Set());
            usedPermissions.get(permission)!.add(qualified);
          }
        }
      };
      for (const match of line.matchAll(RE_NATIVE)) check(match[1]!, false);
      for (const match of line.matchAll(RE_GLOBAL)) {
        const global = match[1]!;
        if (globalsBySide.client.has(global) || globalsBySide.server.has(global)) check(global, true);
      }
    }
  }

  for (const [permission, callers] of usedPermissions) {
    if (!declared.has(permission)) findings.push({ severity: "error", file: "open77.lua", message: `permission ${permission} is required by ${[...callers].slice(0, 4).join(", ")}${callers.size > 4 ? "…" : ""} but not declared`, fix: `add "${permission}" to permissions { }` });
  }
  for (const permission of declared) {
    if (!usedPermissions.has(permission)) findings.push({ severity: "note", file: "open77.lua", message: `permission ${permission} is declared but no catalogued native in the scripts checks it (it may gate a service, an event or a WebUI feature)` });
  }
  return findings;
}
