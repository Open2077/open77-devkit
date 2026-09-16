/**
 * The Dev Index: one directory of JSON the MCP serves from, built from the
 * public documentation content of `Open2077/open77-app` (`content/api` and
 * `content/docs`), which is itself synced from the platform wiki.
 *
 * Format version 1. A consumer refuses a manifest whose `formatVersion` it
 * does not know rather than guessing at the files inside.
 */

export const INDEX_FORMAT_VERSION = 1;

export interface IndexManifest {
  formatVersion: number;
  /** The published server build the index answers for by default, e.g. `2.31.13+op77.69`. */
  build: string;
  /** Protocol of that build when known. */
  protocol?: { major: number; minor: number };
  generatedAt: string;
  /** When the platform wiki was last synced into the public content. */
  docsSyncedAt: string;
  source: { repository: string; commit?: string };
  counts: Record<string, number>;
  files: Record<string, { sha256: string; bytes: number }>;
}

export interface ApiParam {
  name: string;
  type: string;
  optional: boolean;
  default: string | null;
}

/** One card of `api.json`, as the wiki extractor emits it. */
export interface ApiCard {
  namespace: string;
  name: string;
  handler: string;
  summary: string;
  description: string;
  params: ApiParam[];
  returns: string[];
  /** `shared` works anywhere, `game` needs a live game instance, `network` uses the transport. */
  api_set: string;
  runtime: "client" | "server";
  source: string;
  example?: string;
  inferred: boolean;
  source_line?: number;
  qualified: string;
  route_id: string;
  /** Manifest permissions the call checks; empty when the enforcing body could not be read. */
  permissions: string[];
  /** Reason strings the call can hand back (`nil, reason` / `false, reason`). */
  reasons: string[];
  /** First published server build registering the call; null when no release has it. */
  since: string | null;
  /** A public constant table (`Open77.vehicles.seats`): read, never called. Absent on older indexes. */
  constant?: boolean;
}

export interface GuideSection {
  anchor: string;
  heading: string;
  level: number;
  text: string;
  /** Route ids of cards this section's code fences call. */
  natives: string[];
  /** Permissions the section's `permissions { ... }` blocks declare. */
  permissions: string[];
  /** `open77:*` events the section names. */
  events: string[];
}

export interface Guide {
  slug: string;
  file: string;
  title: string;
  summary: string;
  sections: GuideSection[];
}

export interface EventRecord {
  name: string;
  sides: string[];
  payload: string | null;
  guides: { file: string; anchor: string }[];
  sources: { side: string; file: string; line: number }[];
  documented: boolean;
  inCode: boolean;
}

export interface EventsFile {
  events: EventRecord[];
  reservedPrefixes: { prefix: string; sources: { side: string; file: string; line: number }[] }[];
}

export interface PermissionRecord {
  name: string;
  runtimes: string[];
  summary: string;
  curated: boolean;
  natives: string[];
  guides: string[];
  sources: { file: string; line: number }[];
}

export interface PermissionsFile {
  permissions: PermissionRecord[];
}

export interface ReleaseRecord {
  build: string;
  publishedAt: string;
}

export interface ReleasesFile {
  releases: ReleaseRecord[];
}

export interface FivemMapping {
  /** The FiveM name as written in a resource (`GetPlayerPed`, `Citizen.CreateThread`). */
  fivem: string;
  /** `alias` (same call works), `partial` (one side only or a caveat), `missing` (deliberately absent). */
  status: "alias" | "partial" | "missing";
  client: boolean;
  server: boolean;
  /** What to use on Open77, in the guide's words. */
  open77: string;
  guideAnchor: string;
}

export interface ManifestDirective {
  name: string;
  singular?: string;
  form: "scalar" | "boolean" | "list";
  required?: boolean;
  default?: string | boolean;
  description: string;
}

export interface ManifestSchema {
  file: string;
  limits: Record<string, string | number>;
  directives: ManifestDirective[];
  example: string;
}

export interface CatalogueFile {
  gameBuild: string;
  count: number;
  records?: Record<string, unknown>[];
  names?: string[];
}

/** Everything the server loads, in memory. */
export interface DevIndex {
  manifest: IndexManifest;
  cards: ApiCard[];
  guides: Guide[];
  events: EventsFile;
  permissions: PermissionsFile;
  releases: ReleasesFile;
  fivem: FivemMapping[];
  manifestSchema: ManifestSchema;
  serverConfigSchema: Record<string, unknown>;
  /** Catalogue name -> file, loaded lazily by the tools that need them. */
  catalogueNames: string[];
  /** Absolute directory the index was loaded from, for lazy reads. */
  directory: string;
}
