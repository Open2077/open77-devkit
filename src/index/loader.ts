/**
 * Loads a Dev Index directory into memory and verifies it.
 *
 * Verification is the point: the index is the only thing the MCP knows, so a
 * directory whose files do not match its manifest is refused rather than
 * served. The check is the manifest's own SHA-256 per file; a signature over
 * the manifest is the CDN's job (see `refresh.ts`).
 */

import { createHash } from "node:crypto";
import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import {
  INDEX_FORMAT_VERSION,
  type ApiCard,
  type CatalogueFile,
  type DevIndex,
  type EventsFile,
  type FivemMapping,
  type Guide,
  type IndexManifest,
  type ManifestSchema,
  type PermissionsFile,
  type ReleasesFile,
} from "./types.js";

export class IndexError extends Error {}

const sha256 = (text: string) => createHash("sha256").update(text).digest("hex");

async function readVerified(directory: string, manifest: IndexManifest, name: string): Promise<string> {
  const expected = manifest.files[name];
  if (!expected) throw new IndexError(`index manifest does not list ${name}`);
  let text: string;
  try {
    text = await readFile(path.join(directory, name), "utf8");
  } catch {
    throw new IndexError(`index file missing: ${name}`);
  }
  const normalised = text.replace(/\r\n/g, "\n");
  if (sha256(normalised) !== expected.sha256) {
    throw new IndexError(`index file ${name} does not match its manifest hash; refusing to serve a tampered or partial index`);
  }
  return normalised;
}

export async function readManifest(directory: string): Promise<IndexManifest> {
  let manifest: IndexManifest;
  try {
    manifest = JSON.parse(await readFile(path.join(directory, "manifest.json"), "utf8")) as IndexManifest;
  } catch (error) {
    throw new IndexError(`no readable index manifest in ${directory}: ${(error as Error).message}`);
  }
  if (manifest.formatVersion !== INDEX_FORMAT_VERSION) {
    throw new IndexError(
      `index format ${manifest.formatVersion} is not the ${INDEX_FORMAT_VERSION} this package understands; update @open2077/mcp`,
    );
  }
  return manifest;
}

export async function loadIndex(directory: string): Promise<DevIndex> {
  const resolved = path.resolve(directory);
  const info = await stat(resolved).catch(() => null);
  if (!info?.isDirectory()) throw new IndexError(`index directory not found: ${resolved}`);
  const manifest = await readManifest(resolved);
  const read = (name: string) => readVerified(resolved, manifest, name);

  const cards = JSON.parse(await read("cards.json")) as ApiCard[];
  const guides = JSON.parse(await read("guides.json")) as Guide[];
  const events = JSON.parse(await read("events.json")) as EventsFile;
  const permissions = JSON.parse(await read("permissions.json")) as PermissionsFile;
  const releases = JSON.parse(await read("releases.json")) as ReleasesFile;
  const fivem = (JSON.parse(await read("fivem-map.json")) as { mappings: FivemMapping[] }).mappings;
  const manifestSchema = JSON.parse(await read("schemas/manifest.schema.json")) as ManifestSchema;
  const serverConfigSchema = JSON.parse(await read("schemas/server-config.schema.json")) as Record<string, unknown>;
  const catalogueNames = Object.keys(manifest.files)
    .filter((name) => name.startsWith("catalogues/") && name.endsWith(".json"))
    .map((name) => name.slice("catalogues/".length, -".json".length))
    .sort();

  return {
    manifest,
    cards,
    guides,
    events,
    permissions,
    releases,
    fivem,
    manifestSchema,
    serverConfigSchema,
    catalogueNames,
    directory: resolved,
  };
}

const catalogueCache = new Map<string, CatalogueFile>();

export async function loadCatalogue(index: DevIndex, name: string): Promise<CatalogueFile> {
  const key = `${index.directory}/${name}`;
  const cached = catalogueCache.get(key);
  if (cached) return cached;
  if (!index.catalogueNames.includes(name)) throw new IndexError(`unknown catalogue ${name}; known: ${index.catalogueNames.join(", ")}`);
  const parsed = JSON.parse(await readVerified(index.directory, index.manifest, `catalogues/${name}.json`)) as CatalogueFile;
  catalogueCache.set(key, parsed);
  return parsed;
}

export async function readStub(index: DevIndex, runtime: "client" | "server"): Promise<string> {
  return readVerified(index.directory, index.manifest, `open77-${runtime}.d.lua`);
}

/** Every file the manifest lists exists and matches; used by `build-index --verify` and CI. */
export async function verifyIndex(directory: string): Promise<{ files: number; extra: string[] }> {
  const manifest = await readManifest(directory);
  for (const name of Object.keys(manifest.files)) await readVerified(directory, manifest, name);
  const present: string[] = [];
  for (const entry of await readdir(directory, { recursive: true })) {
    const relative = String(entry).replace(/\\/g, "/");
    if (relative !== "manifest.json" && !relative.endsWith("/") && /\.[a-z]+$/.test(relative)) present.push(relative);
  }
  const extra = present.filter((name) => !manifest.files[name]);
  return { files: Object.keys(manifest.files).length, extra };
}
