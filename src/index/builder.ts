/**
 * Builds a Dev Index directory from the public documentation content of
 * `Open2077/open77-app` (`content/api` + `content/docs`).
 *
 * Nothing here invents a fact: cards, events, permissions, releases,
 * catalogues and schemas are copied verbatim from the content; the guides are
 * chunked by heading and cross-referenced against the cards; the FiveM table
 * is parsed from the compatibility guide; the Lua stubs are generated from the
 * cards. Every output file is hashed into `manifest.json`.
 */

import { createHash } from "node:crypto";
import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import {
  INDEX_FORMAT_VERSION,
  type ApiCard,
  type FivemMapping,
  type Guide,
  type GuideSection,
  type IndexManifest,
  type ManifestSchema,
  type ReleasesFile,
} from "./types.js";
import { generateStubs } from "./stubs.js";

export interface BuildOptions {
  contentDir: string;
  outDir: string;
  /** Overrides the build the index answers for (default: newest in releases.json). */
  build?: string;
  sourceCommit?: string;
  log?: (line: string) => void;
}

const sha256 = (text: string) => createHash("sha256").update(text).digest("hex");

async function readJson<T>(file: string): Promise<T> {
  return JSON.parse(await readFile(file, "utf8")) as T;
}

function slugify(heading: string): string {
  return heading
    .replace(/[`*_]/g, "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .replace(/\s+/g, "-")
    .replace(/^-+|-+$/g, "");
}

const RE_PERMISSION_BLOCK = /permissions?\s*\{([^}]*)\}/g;
const RE_PERMISSION_NAME = /["']([a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*)+)["']/g;
const RE_EVENT = /["'`](open77:[A-Za-z0-9_:.-]+)["'`]/g;

/**
 * Splits a guide into heading-delimited sections and records which cards,
 * permissions and events each section talks about. The first section (before
 * any `##`) carries the title paragraph and becomes the guide summary.
 */
export function chunkGuide(file: string, markdown: string, cardIndex: Map<string, ApiCard[]>): Guide {
  const lines = markdown.replace(/\r\n/g, "\n").split("\n");
  let title = file.replace(/\.md$/, "");
  const sections: GuideSection[] = [];
  let current: GuideSection | null = null;
  let inFence = false;
  let fenceBuffer: string[] = [];
  const anchors = new Map<string, number>();
  const ensure = (heading: string, level: number) => {
    // Two headings with the same text get `-2`, `-3`, the way GitHub and the
    // website render them, so a section id is unique within its guide.
    const base = slugify(heading) || "section";
    const seen = anchors.get(base) ?? 0;
    anchors.set(base, seen + 1);
    const anchor = seen ? `${base}-${seen + 1}` : base;
    current = { anchor, heading, level, text: "", natives: [], permissions: [], events: [] };
    sections.push(current);
    return current;
  };
  const flushFence = (section: GuideSection, code: string) => {
    for (const match of code.matchAll(/\b((?:Open77|WebUI|Citizen)(?:\.[A-Za-z_]\w*)+|[A-Z][A-Za-z]+)\s*\(/g)) {
      const name = match[1]!;
      const cards = cardIndex.get(name);
      if (cards) for (const card of cards) if (!section.natives.includes(card.route_id)) section.natives.push(card.route_id);
    }
    for (const block of code.matchAll(RE_PERMISSION_BLOCK)) {
      for (const name of block[1]!.matchAll(RE_PERMISSION_NAME)) {
        if (!section.permissions.includes(name[1]!)) section.permissions.push(name[1]!);
      }
    }
  };
  for (const line of lines) {
    if (line.startsWith("```")) {
      if (inFence) {
        const section = current ?? ensure("Introduction", 1);
        flushFence(section, fenceBuffer.join("\n"));
        section.text += fenceBuffer.join("\n") + "\n```\n";
        fenceBuffer = [];
      } else {
        const section = current ?? ensure("Introduction", 1);
        section.text += line + "\n";
      }
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      fenceBuffer.push(line);
      continue;
    }
    const heading = /^(#{1,6})\s+(.*)$/.exec(line);
    if (heading) {
      const level = heading[1]!.length;
      const text = heading[2]!.trim();
      if (level === 1 && sections.length === 0) {
        title = text.replace(/[`*]/g, "");
        ensure(text, 1);
      } else {
        ensure(text, level);
      }
      continue;
    }
    const section = current ?? ensure(title, 1);
    section.text += line + "\n";
  }
  for (const section of sections) {
    section.text = section.text.trim();
    for (const match of section.text.matchAll(RE_EVENT)) {
      const name = match[1]!;
      if (!name.endsWith(":") && !section.events.includes(name)) section.events.push(name);
    }
  }
  const intro = sections[0]?.text ?? "";
  const summary = intro.split("\n\n").find((p) => p && !p.startsWith("```") && !p.startsWith("|"))?.replace(/\s+/g, " ") ?? "";
  return { slug: file.replace(/\.md$/, ""), file, title, summary: summary.slice(0, 400), sections };
}

/**
 * The FiveM compatibility guide is a set of tables `| name(s) | client | server | Open77 |`.
 * Rows are read wherever they appear under the guide; a name cell may list
 * several names separated by ` / `.
 */
export function parseFivemGuide(markdown: string): FivemMapping[] {
  const mappings: FivemMapping[] = [];
  let anchor = "";
  for (const raw of markdown.replace(/\r\n/g, "\n").split("\n")) {
    const heading = /^#{2,6}\s+(.*)$/.exec(raw);
    if (heading) {
      anchor = slugify(heading[1]!);
      continue;
    }
    if (!raw.trim().startsWith("|")) continue;
    const cells = raw.trim().replace(/^\||\|$/g, "").split("|").map((c) => c.trim());
    if (cells.length < 4 || !cells[0]!.includes("`")) continue;
    if (/^-+$/.test(cells[1]!.replace(/\s/g, ""))) continue;
    const names = [...cells[0]!.matchAll(/`([^`]+)`/g)].map((m) => m[1]!);
    if (names.length === 0) continue;
    const yes = (cell: string) => /\byes\b/i.test(cell.replace(/\*/g, ""));
    const client = yes(cells[1]!);
    const server = yes(cells[2]!);
    const open77 = cells.slice(3).join(" | ").replace(/\*\*/g, "");
    const status: FivemMapping["status"] = !client && !server ? "missing" : client && server ? "alias" : "partial";
    for (const fivem of names) mappings.push({ fivem, status, client, server, open77, guideAnchor: anchor });
  }
  return mappings;
}

export async function buildIndex(options: BuildOptions): Promise<IndexManifest> {
  const log = options.log ?? (() => {});
  const { contentDir, outDir } = options;
  const api = path.join(contentDir, "api");
  const docs = path.join(contentDir, "docs");
  await mkdir(outDir, { recursive: true });
  await mkdir(path.join(outDir, "catalogues"), { recursive: true });
  await mkdir(path.join(outDir, "schemas"), { recursive: true });

  const files: IndexManifest["files"] = {};
  const counts: Record<string, number> = {};
  const write = async (name: string, text: string) => {
    const normalised = text.endsWith("\n") ? text : text + "\n";
    await writeFile(path.join(outDir, name), normalised, "utf8");
    files[name] = { sha256: sha256(normalised), bytes: Buffer.byteLength(normalised, "utf8") };
  };
  const copy = async (source: string, name: string) => {
    const text = (await readFile(source, "utf8")).replace(/\r\n/g, "\n");
    JSON.parse(text);
    await write(name, text);
    return text;
  };

  const cardsText = await copy(path.join(api, "api.json"), "cards.json");
  const cards = JSON.parse(cardsText) as ApiCard[];
  for (const card of cards as Partial<ApiCard>[]) {
    if (!("permissions" in card) || !("since" in card)) {
      throw new Error(`api.json card ${card.route_id ?? "?"} lacks the guard fields; sync a newer wiki`);
    }
  }
  counts.cards = cards.length;
  log(`cards: ${cards.length}`);

  const cardIndex = new Map<string, ApiCard[]>();
  for (const card of cards) {
    const list = cardIndex.get(card.qualified) ?? [];
    list.push(card);
    cardIndex.set(card.qualified, list);
  }

  for (const name of ["events.json", "permissions.json", "releases.json"]) {
    await copy(path.join(api, name), name);
  }
  const releases = JSON.parse(await readFile(path.join(outDir, "releases.json"), "utf8")) as ReleasesFile;
  counts.releases = releases.releases.length;
  const newest = [...releases.releases].sort((a, b) => opNumber(b.build) - opNumber(a.build))[0];
  const build = options.build ?? newest?.build;
  if (!build) throw new Error("releases.json names no build; the index cannot say what it answers for");

  const guides: Guide[] = [];
  const manifestPath = path.join(docs, "_manifest.json");
  const docsManifest = JSON.parse(await readFile(manifestPath, "utf8")) as { syncedAt: string; files?: { target: string; slug?: string }[] };
  for (const name of (await readdir(docs)).filter((f) => f.endsWith(".md")).sort()) {
    const markdown = await readFile(path.join(docs, name), "utf8");
    guides.push(chunkGuide(name, markdown, cardIndex));
  }
  counts.guides = guides.length;
  counts.sections = guides.reduce((n, g) => n + g.sections.length, 0);
  await write("guides.json", JSON.stringify(guides));
  log(`guides: ${guides.length} (${counts.sections} sections)`);

  const fivemGuide = guides.find((g) => g.file === "fivem-compatibility.md");
  const fivem = fivemGuide ? parseFivemGuide(await readFile(path.join(docs, fivemGuide.file), "utf8")) : [];
  counts.fivem = fivem.length;
  await write("fivem-map.json", JSON.stringify({ guide: "fivem-compatibility.md", mappings: fivem }, null, 1));
  log(`fivem aliases: ${fivem.length}`);

  for (const folder of ["catalogues", "schemas"]) {
    const dir = path.join(api, folder);
    let names: string[] = [];
    try {
      names = (await readdir(dir)).filter((f) => f.endsWith(".json")).sort();
    } catch {
      throw new Error(`content/api/${folder} is missing; sync a newer wiki`);
    }
    for (const name of names) await copy(path.join(dir, name), `${folder}/${name}`);
    counts[folder] = names.length;
  }
  const manifestSchema = JSON.parse(await readFile(path.join(outDir, "schemas", "manifest.schema.json"), "utf8")) as ManifestSchema;
  counts.directives = manifestSchema.directives.length;

  const stubs = generateStubs(cards);
  await write("open77-client.d.lua", stubs.client);
  await write("open77-server.d.lua", stubs.server);
  log(`stubs: ${stubs.clientCount} client, ${stubs.serverCount} server`);

  const manifest: IndexManifest = {
    formatVersion: INDEX_FORMAT_VERSION,
    build,
    generatedAt: new Date().toISOString(),
    docsSyncedAt: docsManifest.syncedAt,
    source: { repository: "https://github.com/Open2077/open77-app", ...(options.sourceCommit ? { commit: options.sourceCommit } : {}) },
    counts,
    files,
  };
  await writeFile(path.join(outDir, "manifest.json"), JSON.stringify(manifest, null, 1) + "\n", "utf8");
  log(`manifest: build ${build}, ${Object.keys(files).length} files -> ${outDir}`);
  return manifest;
}

export function opNumber(build: string): number {
  const tail = build.split("+op77.")[1];
  return tail && /^\d+$/.test(tail) ? Number(tail) : -1;
}
