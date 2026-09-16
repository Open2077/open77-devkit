/**
 * Where the index comes from, in order of preference:
 *
 * 1. `OPEN77_INDEX_DIR`, an explicit directory (development, CI);
 * 2. the cache under `~/.open77/mcp/index/<build>/`, refreshed from the CDN
 *    (`https://cdn.open2077.net/dev-index/<build>/`) when the manifest's
 *    ETag changed, at most once a day unless forced;
 * 3. the snapshot embedded in the package (`index/`), which is what a first
 *    run and an offline run answer from.
 *
 * The build to fetch is the one the caller asks for (the detected server
 * build, or `latest`). A build the CDN has no index for falls back to the
 * newest index at or below it, and the answer says so: it is never silently
 * the wrong build.
 */

import { createHash } from "node:crypto";
import { mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { opNumber } from "./builder.js";
import { IndexError, readManifest } from "./loader.js";
import type { IndexManifest } from "./types.js";

export const CDN_BASE = process.env["OPEN77_CDN_BASE"] ?? "https://cdn.open2077.net";
export const INDEX_PREFIX = "dev-index";
export const CACHE_ROOT = process.env["OPEN77_MCP_CACHE"] ?? path.join(os.homedir(), ".open77", "mcp");
const REFRESH_INTERVAL_MS = 24 * 60 * 60 * 1000;
const FETCH_TIMEOUT_MS = 8000;

export interface LatestIndex {
  build: string;
  manifestSha256?: string;
  /** Every build the CDN has an index for, newest first. */
  builds?: string[];
}

export interface ResolvedIndex {
  directory: string;
  build: string;
  origin: "env" | "cache" | "embedded";
  /** Set when the requested build differs from the served one. */
  requestedBuild?: string;
  note?: string;
}

interface CacheState {
  etag?: string;
  checkedAt: string;
  manifestSha256: string;
}

async function fetchText(url: string, headers: Record<string, string> = {}): Promise<{ status: number; text: string; etag?: string }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(url, { headers, signal: controller.signal });
    const text = response.status === 200 ? await response.text() : "";
    return { status: response.status, text, etag: response.headers.get("etag") ?? undefined };
  } finally {
    clearTimeout(timer);
  }
}

export async function fetchLatest(): Promise<LatestIndex | null> {
  try {
    const { status, text } = await fetchText(`${CDN_BASE}/${INDEX_PREFIX}/latest.json`);
    if (status !== 200) return null;
    return JSON.parse(text) as LatestIndex;
  } catch {
    return null;
  }
}

async function readState(dir: string): Promise<CacheState | null> {
  try {
    return JSON.parse(await readFile(path.join(dir, ".state.json"), "utf8")) as CacheState;
  } catch {
    return null;
  }
}

/**
 * Downloads `dev-index/<build>/` into the cache, verifying every file against
 * the manifest before the directory is swapped into place. A failed or
 * partial download never replaces a good cache.
 */
export async function downloadIndex(build: string, log: (line: string) => void = () => {}): Promise<string> {
  const base = `${CDN_BASE}/${INDEX_PREFIX}/${encodeURIComponent(build)}`;
  const target = path.join(CACHE_ROOT, "index", build);
  const staging = `${target}.tmp-${process.pid}`;
  const state = await readState(target);
  const headers: Record<string, string> = state?.etag ? { "If-None-Match": state.etag } : {};
  const manifestResponse = await fetchText(`${base}/manifest.json`, headers);
  if (manifestResponse.status === 304 && state) {
    await writeFile(path.join(target, ".state.json"), JSON.stringify({ ...state, checkedAt: new Date().toISOString() }), "utf8");
    return target;
  }
  if (manifestResponse.status !== 200) throw new IndexError(`CDN has no index for build ${build} (HTTP ${manifestResponse.status})`);
  const manifest = JSON.parse(manifestResponse.text) as IndexManifest;
  const manifestSha = createHash("sha256").update(manifestResponse.text).digest("hex");
  if (state && state.manifestSha256 === manifestSha) {
    await writeFile(path.join(target, ".state.json"), JSON.stringify({ ...state, etag: manifestResponse.etag, checkedAt: new Date().toISOString() }), "utf8");
    return target;
  }
  await rm(staging, { recursive: true, force: true });
  await mkdir(staging, { recursive: true });
  await writeFile(path.join(staging, "manifest.json"), manifestResponse.text, "utf8");
  let count = 0;
  for (const [name, expected] of Object.entries(manifest.files)) {
    const file = await fetchText(`${base}/${name}`);
    if (file.status !== 200) throw new IndexError(`CDN index ${build} is missing ${name} (HTTP ${file.status})`);
    const normalised = file.text.replace(/\r\n/g, "\n");
    if (createHash("sha256").update(normalised).digest("hex") !== expected.sha256) {
      throw new IndexError(`CDN index ${build}: ${name} does not match the manifest; download refused`);
    }
    await mkdir(path.dirname(path.join(staging, name)), { recursive: true });
    await writeFile(path.join(staging, name), normalised, "utf8");
    count += 1;
  }
  await writeFile(
    path.join(staging, ".state.json"),
    JSON.stringify({ etag: manifestResponse.etag, checkedAt: new Date().toISOString(), manifestSha256: manifestSha } satisfies CacheState),
    "utf8",
  );
  await rm(target, { recursive: true, force: true });
  await mkdir(path.dirname(target), { recursive: true });
  await rename(staging, target);
  log(`index ${build}: ${count} files cached in ${target}`);
  return target;
}

async function cachedBuilds(): Promise<string[]> {
  try {
    const { readdir } = await import("node:fs/promises");
    const entries = await readdir(path.join(CACHE_ROOT, "index"));
    const builds: string[] = [];
    for (const entry of entries) {
      if (entry.includes(".tmp-")) continue;
      if (await stat(path.join(CACHE_ROOT, "index", entry, "manifest.json")).catch(() => null)) builds.push(entry);
    }
    return builds.sort((a, b) => opNumber(b) - opNumber(a));
  } catch {
    return [];
  }
}

export interface ResolveOptions {
  /** The build the caller wants answers for; `latest` or undefined for the newest published. */
  build?: string;
  embeddedDir: string;
  offline?: boolean;
  force?: boolean;
  log?: (line: string) => void;
}

/**
 * Picks the index directory to serve. Network is consulted at most once a
 * day per build (or when forced), and any network failure degrades to the
 * cache, then to the embedded snapshot, with a note the tools surface.
 */
export async function resolveIndex(options: ResolveOptions): Promise<ResolvedIndex> {
  const log = options.log ?? (() => {});
  const envDir = process.env["OPEN77_INDEX_DIR"];
  if (envDir) {
    const manifest = await readManifest(envDir);
    return { directory: path.resolve(envDir), build: manifest.build, origin: "env" };
  }
  const embedded = await readManifest(options.embeddedDir);
  const wanted = options.build && options.build !== "latest" ? options.build : undefined;

  if (!options.offline) {
    try {
      const latest = await fetchLatest();
      if (latest) {
        const available = latest.builds?.length ? latest.builds : [latest.build];
        const sorted = [...available].sort((a, b) => opNumber(b) - opNumber(a));
        const target = wanted
          ? sorted.find((b) => opNumber(b) <= opNumber(wanted)) ?? sorted[sorted.length - 1]!
          : sorted[0]!;
        const dir = path.join(CACHE_ROOT, "index", target);
        const state = await readState(dir);
        const fresh = state && Date.now() - Date.parse(state.checkedAt) < REFRESH_INTERVAL_MS;
        if (!fresh || options.force) await downloadIndex(target, log);
        const note = wanted && target !== wanted
          ? `no index published for ${wanted}; serving ${target}, the newest at or below it`
          : undefined;
        return { directory: dir, build: target, origin: "cache", ...(wanted ? { requestedBuild: wanted } : {}), ...(note ? { note } : {}) };
      }
    } catch (error) {
      log(`index refresh skipped: ${(error as Error).message}`);
    }
  }

  const cached = await cachedBuilds();
  const candidate = wanted ? cached.find((b) => opNumber(b) <= opNumber(wanted)) : cached[0];
  if (candidate) {
    const note = wanted && candidate !== wanted ? `offline; serving cached ${candidate} for requested ${wanted}` : "offline; serving the cached index";
    return { directory: path.join(CACHE_ROOT, "index", candidate), build: candidate, origin: "cache", ...(wanted ? { requestedBuild: wanted } : {}), note };
  }
  const note = wanted && embedded.build !== wanted
    ? `offline and nothing cached; serving the embedded ${embedded.build} for requested ${wanted}`
    : "serving the embedded index snapshot";
  return { directory: options.embeddedDir, build: embedded.build, origin: "embedded", ...(wanted ? { requestedBuild: wanted } : {}), note };
}
