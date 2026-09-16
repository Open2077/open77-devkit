/**
 * The Open77 Devkit MCP server: every tool, resource and prompt, over any
 * transport. One instance answers for exactly one index build; the CLI
 * decides which index to load (`refresh.ts`) and hands it here.
 *
 * Every tool result carries the build it answered for, so a transcript can
 * always be audited against the server the resource will run on.
 */

import { McpServer, ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import { opNumber } from "./index/builder.js";
import { loadCatalogue, readStub } from "./index/loader.js";
import { IndexSearch, type SearchKind } from "./index/search.js";
import type { ApiCard, DevIndex, Guide, GuideSection } from "./index/types.js";
import type { ResolvedIndex } from "./index/refresh.js";

export interface ServerContext {
  index: DevIndex;
  resolved: ResolvedIndex;
  packageVersion: string;
  skillPath: string;
  /** Extra tool registrars (workspace, Warden, Workshop) the CLI adds when running locally. */
  extensions?: ((server: McpServer, context: ServerContext) => void)[];
}

export const RUNTIME = z.enum(["client", "server"]);

function text(body: string) {
  return { content: [{ type: "text" as const, text: body }] };
}

function buildLine(context: ServerContext): string {
  const { resolved } = context;
  const note = resolved.note ? ` (${resolved.note})` : "";
  return `answering for build ${resolved.build}${note}`;
}

export function cardHeader(card: ApiCard): string {
  const params = card.params.map((p) => `${p.name}${p.optional ? "?" : ""}: ${p.type}`).join(", ");
  return `${card.runtime === "server" ? "server" : "client"} ${card.qualified}(${params})`;
}

export function renderCard(card: ApiCard, context: ServerContext, guides: Guide[]): string {
  const lines: string[] = [];
  lines.push(`# ${cardHeader(card)}`);
  lines.push("");
  lines.push(card.summary);
  if (card.description) lines.push("", card.description);
  lines.push("");
  lines.push(`- runtime: ${card.runtime} (${card.api_set})`);
  lines.push(`- permissions: ${card.permissions.length ? card.permissions.join(", ") : "none checked in the handler"}`);
  lines.push(`- since: ${card.since ?? "not in any published build (main only)"}`);
  if (card.reasons.length) lines.push(`- reasons it can return: ${card.reasons.join(", ")}`);
  if (card.returns.length) lines.push(`- returns: ${card.returns.join("; ")}`);
  if (card.inferred) lines.push("- signature: inferred from the handler, not reviewed");
  const available = availabilityNote(card, context);
  if (available) lines.push(`- ${available}`);
  const related = guides.flatMap((g) => g.sections.filter((s) => s.natives.includes(card.route_id)).map((s) => `${g.slug}#${s.anchor}`)).slice(0, 6);
  if (related.length) lines.push(`- guides: ${related.join(", ")}`);
  if (card.example) lines.push("", "```lua", card.example, "```");
  lines.push("", `_${buildLine(context)}_`);
  return lines.join("\n");
}

/** "not available on op77.54 (since op77.57)" when the served build predates the card. */
export function availabilityNote(card: ApiCard, context: ServerContext): string | null {
  const served = opNumber(context.resolved.build);
  if (!card.since) return `NOT AVAILABLE on ${context.resolved.build}: this native is not in any published build`;
  if (opNumber(card.since) > served) return `NOT AVAILABLE on ${context.resolved.build}: needs ${card.since} or newer`;
  return null;
}

function renderSection(guide: Guide, section: GuideSection): string {
  const head = `${"#".repeat(Math.min(section.level, 3))} ${guide.title} › ${section.heading}`;
  const meta: string[] = [];
  if (section.natives.length) meta.push(`natives: ${section.natives.join(", ")}`);
  if (section.permissions.length) meta.push(`permissions: ${section.permissions.join(", ")}`);
  if (section.events.length) meta.push(`events: ${section.events.join(", ")}`);
  return [head, "", section.text, "", ...(meta.length ? [`_${meta.join(" · ")}_`] : [])].join("\n");
}

export function createMcpServer(context: ServerContext): McpServer {
  const { index } = context;
  const search = new IndexSearch(index);
  const byRoute = new Map(index.cards.map((c) => [c.route_id, c]));
  const byQualified = new Map<string, ApiCard[]>();
  for (const card of index.cards) {
    const list = byQualified.get(card.qualified.toLowerCase()) ?? [];
    list.push(card);
    byQualified.set(card.qualified.toLowerCase(), list);
  }
  const guideBySlug = new Map(index.guides.map((g) => [g.slug, g]));

  const server = new McpServer(
    { name: "open77-devkit", version: context.packageVersion },
    {
      instructions: instructions(context),
    },
  );

  // ---------------------------------------------------------------- docs tools

  server.registerTool(
    "open77_search",
    {
      title: "Search the Open77 API and guides",
      description:
        "Lexical search over the Open77 Lua natives, guides, open77:* events, manifest permissions and FiveM equivalents. " +
        "Use it first; then open77_api / open77_guide for the full text. Returns the build it answers for.",
      inputSchema: {
        query: z.string().min(1).describe("Words, a native name (Open77.vehicles.spawn), a FiveM name, an event or a permission"),
        kind: z.enum(["card", "guide", "event", "permission", "fivem"]).optional().describe("Restrict to one kind"),
        runtime: RUNTIME.optional().describe("Only natives of this runtime"),
        limit: z.number().int().min(1).max(40).optional(),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ query, kind, runtime, limit }) => {
      const hits = search.search(query, { kinds: kind ? [kind as SearchKind] : undefined, runtime, limit: limit ?? 12 });
      if (!hits.length) {
        // A question the index cannot answer is a documentation gap. One JSON
        // line on stderr; the hosted container's log is what the digest reads.
        process.stderr.write(JSON.stringify({ event: "zero_hit", query, kind: kind ?? null, runtime: runtime ?? null, build: context.resolved.build, at: new Date().toISOString() }) + "\n");
      }
      if (!hits.length) return text(`No match for "${query}". ${buildLine(context)}. Try a broader word, a namespace (Open77.vehicles), or open77_fivem_equivalent for a FiveM name.`);
      const lines = hits.map((h) => {
        const card = h.kind === "card" ? byRoute.get(h.ref) : undefined;
        const avail = card ? availabilityNote(card, context) : null;
        const tag = card ? ` [${card.runtime}${card.permissions.length ? ` · ${card.permissions.join(",")}` : ""}${card.since ? ` · since ${card.since}` : " · unreleased"}]` : "";
        return `- (${h.kind}) **${h.title}**${tag} — ${h.snippet}${avail ? ` — ${avail}` : ""}\n  ref: ${h.ref}`;
      });
      return text([`${hits.length} results for "${query}" — ${buildLine(context)}`, "", ...lines].join("\n"));
    },
  );

  server.registerTool(
    "open77_api",
    {
      title: "Read one native's card",
      description:
        "The full card of one Lua native: signature, description, permissions the manifest must declare, reasons it can return, " +
        "the first build that has it, example, related guides. Accepts a qualified name (Open77.map.getWaypoint, TriggerClientEvent) or a route id (server:Open77.vehicles.spawn).",
      inputSchema: {
        name: z.string().min(1),
        runtime: RUNTIME.optional().describe("Disambiguates a name that exists on both runtimes"),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ name, runtime }) => {
      const cards = findCards(name, runtime);
      if (!cards.length) {
        const near = search.search(name, { kinds: ["card"], limit: 5 }).map((h) => h.title);
        return text(`No native named ${name} in the catalogue for ${context.resolved.build}.${near.length ? ` Closest: ${near.join(", ")}.` : ""} Do not call it: a name absent from the catalogue does not exist on this build.`);
      }
      return text(cards.map((c) => renderCard(c, context, index.guides)).join("\n\n---\n\n"));
    },
  );

  server.registerTool(
    "open77_namespace",
    {
      title: "List a namespace",
      description: "Every native under a namespace (Open77.vehicles, Open77.players, _G for globals), one line each with permissions and since. Omit the namespace to list the namespaces.",
      inputSchema: {
        namespace: z.string().optional(),
        runtime: RUNTIME.optional(),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ namespace, runtime }) => {
      if (!namespace) {
        const counts = new Map<string, { client: number; server: number }>();
        for (const c of index.cards) {
          const entry = counts.get(c.namespace) ?? { client: 0, server: 0 };
          entry[c.runtime] += 1;
          counts.set(c.namespace, entry);
        }
        const lines = [...counts.entries()].sort().map(([ns, n]) => `- ${ns}: ${n.client} client, ${n.server} server`);
        return text([`${counts.size} namespaces — ${buildLine(context)}`, ...lines].join("\n"));
      }
      const wanted = namespace.toLowerCase();
      const cards = index.cards.filter((c) => c.namespace.toLowerCase() === wanted && (!runtime || c.runtime === runtime));
      if (!cards.length) return text(`No namespace ${namespace}. Call open77_namespace without arguments for the list.`);
      const lines = cards
        .sort((a, b) => a.runtime.localeCompare(b.runtime) || a.name.localeCompare(b.name))
        .map((c) => {
          const avail = availabilityNote(c, context);
          return `- ${cardHeader(c)} — ${c.summary}${c.permissions.length ? ` [${c.permissions.join(", ")}]` : ""}${c.since ? ` (since ${c.since})` : " (unreleased)"}${avail ? ` — ${avail}` : ""}`;
        });
      return text([`${cards.length} natives in ${namespace} — ${buildLine(context)}`, ...lines].join("\n"));
    },
  );

  server.registerTool(
    "open77_guide",
    {
      title: "Read a guide",
      description: "A guide or one of its sections, as Markdown. Slugs come from open77_search (guide results) or the list returned when slug is omitted.",
      inputSchema: {
        slug: z.string().optional().describe("Guide slug, e.g. native-map, server-resources, fivem-compatibility"),
        section: z.string().optional().describe("Section anchor; omit for the whole guide"),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ slug, section }) => {
      if (!slug) {
        const lines = index.guides.map((g) => `- ${g.slug}: ${g.title} — ${g.summary.slice(0, 140)}`);
        return text([`${index.guides.length} guides — ${buildLine(context)}`, ...lines].join("\n"));
      }
      const guide = guideBySlug.get(slug.replace(/\.md$/, ""));
      if (!guide) return text(`No guide ${slug}. Call open77_guide without arguments for the list.`);
      if (section) {
        const found = guide.sections.find((s) => s.anchor === section.replace(/^#/, ""));
        if (!found) return text(`No section ${section} in ${slug}. Sections: ${guide.sections.map((s) => s.anchor).join(", ")}`);
        return text(renderSection(guide, found));
      }
      const body = guide.sections.map((s) => renderSection(guide, s)).join("\n\n");
      return text(body.length > 60000 ? body.slice(0, 60000) + "\n\n_(truncated; ask for a section)_" : body);
    },
  );

  server.registerTool(
    "open77_events",
    {
      title: "List open77:* events",
      description: "Events by prefix (open77:map, open77:chat) or all of them; each with its sides, documented payload and guide. Also lists the reserved prefixes a resource may not raise.",
      inputSchema: { prefix: z.string().optional(), documentedOnly: z.boolean().optional() },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ prefix, documentedOnly }) => {
      const events = index.events.events.filter((e) => (!prefix || e.name.startsWith(prefix)) && (!documentedOnly || e.documented));
      const lines = events.map((e) => `- ${e.name} [${e.sides.join(", ") || "guide only"}]${e.payload ? ` payload ${e.payload}` : ""}${e.guides.length ? ` — ${e.guides.map((g) => `${g.file.replace(/\.md$/, "")}#${g.anchor}`).slice(0, 2).join(", ")}` : ""}`);
      const reserved = prefix ? [] : index.events.reservedPrefixes.map((p) => p.prefix);
      return text([
        `${events.length} events${prefix ? ` under ${prefix}` : ""} — ${buildLine(context)}`,
        ...lines,
        ...(reserved.length ? ["", `Reserved prefixes (the runtime refuses resource events under them): ${reserved.join(", ")}`] : []),
      ].join("\n"));
    },
  );

  server.registerTool(
    "open77_permissions",
    {
      title: "Manifest permissions",
      description: "One permission (what it gates, which natives, which guides declare it) or the whole list. These are the strings a manifest's permissions { } block declares.",
      inputSchema: { name: z.string().optional() },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ name }) => {
      if (!name) {
        const lines = index.permissions.permissions.map((p) => `- ${p.name} [${p.runtimes.join(", ") || "?"}] — ${p.summary}`);
        return text([`${lines.length} permissions — ${buildLine(context)}`, ...lines].join("\n"));
      }
      const permission = index.permissions.permissions.find((p) => p.name === name);
      if (!permission) return text(`No permission named ${name}. A manifest declaring it would declare nothing the runtime knows.`);
      return text([
        `# ${permission.name}`,
        "",
        permission.summary,
        `- enforced by: ${permission.runtimes.join(", ") || "unknown"}`,
        `- natives: ${permission.natives.length ? permission.natives.join(", ") : "none in the catalogue"}`,
        `- guides declaring it: ${permission.guides.length ? permission.guides.join(", ") : "none"}`,
        `- manifest line: permissions { "${permission.name}" }`,
        "",
        `_${buildLine(context)}_`,
      ].join("\n"));
    },
  );

  server.registerTool(
    "open77_data",
    {
      title: "Game data catalogues",
      description:
        "Look up spawnable names: vehicles, weapons, items (clothing), npc-templates, props, vfx, sfx, animations, animsets. " +
        "Query matches the record/path/name; returns the fields the server itself answers Open77.data.* from.",
      inputSchema: {
        catalogue: z.string().describe("vehicles | weapons | items | npc-templates | props | vfx | sfx | animations | animsets"),
        query: z.string().optional().describe("Substring or words to match; omit for the catalogue summary"),
        limit: z.number().int().min(1).max(100).optional(),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ catalogue, query, limit }) => {
      if (!index.catalogueNames.includes(catalogue)) return text(`Unknown catalogue ${catalogue}. Known: ${index.catalogueNames.join(", ")}`);
      const file = await loadCatalogue(index, catalogue);
      const max = limit ?? 25;
      if (file.names) {
        if (!query) return text(`${catalogue}: ${file.count} names for game build ${file.gameBuild}. Pass a query.`);
        const words = query.toLowerCase().split(/\s+/).filter(Boolean);
        const hits = file.names.filter((n) => words.every((w) => n.toLowerCase().includes(w))).slice(0, max);
        return text([`${hits.length} of ${file.count} ${catalogue} match "${query}" (game ${file.gameBuild})`, ...hits.map((h) => `- ${h}`)].join("\n"));
      }
      const records = file.records ?? [];
      if (!query) {
        const keys = records[0] ? Object.keys(records[0]) : [];
        return text(`${catalogue}: ${file.count} records for game build ${file.gameBuild}; fields: ${keys.join(", ")}. Pass a query.`);
      }
      const words = query.toLowerCase().split(/\s+/).filter(Boolean);
      const hits = records.filter((r) => {
        const hay = Object.values(r).join(" ").toLowerCase();
        return words.every((w) => hay.includes(w));
      }).slice(0, max);
      return text([`${hits.length} ${catalogue} match "${query}" (game ${file.gameBuild})`, ...hits.map((r) => `- ${JSON.stringify(r)}`)].join("\n"));
    },
  );

  server.registerTool(
    "open77_fivem_equivalent",
    {
      title: "FiveM to Open77",
      description: "What an Open77 resource uses in place of a FiveM native or Citizen call, and what is deliberately absent. Falls back to a search when the name is not in the alias table.",
      inputSchema: { name: z.string().min(1) },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ name }) => {
      const key = name.replace(/\(\)$/, "").toLowerCase();
      const exact = index.fivem.filter((m) => m.fivem.replace(/\(\)$/, "").toLowerCase() === key);
      if (exact.length) {
        return text(exact.map((m) => `**${m.fivem}** — ${m.status}${m.status !== "missing" ? ` (client ${m.client ? "yes" : "no"}, server ${m.server ? "yes" : "no"})` : ""}\n${m.open77}\n_guide: fivem-compatibility#${m.guideAnchor}_`).join("\n\n") + `\n\n_${buildLine(context)}_`);
      }
      const hits = search.search(name, { limit: 8 });
      return text([`${name} is not in the FiveM alias table. Closest Open77 matches:`, ...hits.map((h) => `- (${h.kind}) ${h.title} — ${h.snippet}`), "", "Read fivem-compatibility (open77_guide) for the three places Open77 deliberately differs.", `_${buildLine(context)}_`].join("\n"));
    },
  );

  server.registerTool(
    "open77_manifest_schema",
    {
      title: "open77.lua manifest grammar",
      description: "Every directive of the resource manifest with its form, default and rule, plus a complete example.",
      inputSchema: {},
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async () => {
      const schema = index.manifestSchema;
      const lines = schema.directives.map((d) => `- ${d.name}${d.singular ? ` / ${d.singular}` : ""} (${d.form}${d.required ? ", required" : ""}${d.default !== undefined ? `, default ${JSON.stringify(d.default)}` : ""}): ${d.description}`);
      return text([`# ${schema.file}`, "", ...Object.entries(schema.limits).map(([k, v]) => `- ${k}: ${v}`), "", "## Directives", ...lines, "", "## Example", "```lua", schema.example.trim(), "```", "", `_${buildLine(context)}_`].join("\n"));
    },
  );

  server.registerTool(
    "open77_server_config_schema",
    {
      title: "server.jsonc schema",
      description: "The JSON schema the dedicated server validates server.jsonc with. Pass a top-level key (network, resources, warden, voice...) for that section only.",
      inputSchema: { key: z.string().optional() },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ key }) => {
      const schema = index.serverConfigSchema as { properties?: Record<string, unknown> };
      if (!key) return text([`server.jsonc top-level keys: ${Object.keys(schema.properties ?? {}).join(", ")}`, "Pass one as key for its schema.", `_${buildLine(context)}_`].join("\n"));
      const section = schema.properties?.[key];
      if (!section) return text(`No key ${key}. Keys: ${Object.keys(schema.properties ?? {}).join(", ")}`);
      return text("```json\n" + JSON.stringify(section, null, 1).slice(0, 40000) + "\n```");
    },
  );

  server.registerTool(
    "open77_changes",
    {
      title: "Natives added between builds",
      description: "Which natives a newer server build adds compared to an older one, from the since field. Useful to answer 'what do I gain by updating' or 'why does this work on my dev box and not on the owner's server'.",
      inputSchema: {
        from: z.string().describe("Older build, e.g. 2.31.13+op77.54 or just 54"),
        to: z.string().optional().describe("Newer build; default the served build"),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ from, to }) => {
      const fromN = /^\d+$/.test(from) ? Number(from) : opNumber(from);
      const toN = to ? (/^\d+$/.test(to) ? Number(to) : opNumber(to)) : opNumber(context.resolved.build);
      if (fromN < 0 || toN < 0) return text("Builds are written 2.31.13+op77.NN (or just NN).");
      const added = index.cards.filter((c) => c.since && opNumber(c.since) > fromN && opNumber(c.since) <= toN);
      const byBuild = new Map<string, ApiCard[]>();
      for (const c of added) byBuild.set(c.since!, [...(byBuild.get(c.since!) ?? []), c]);
      const lines = [...byBuild.entries()].sort((a, b) => opNumber(a[0]) - opNumber(b[0])).flatMap(([b, cards]) => [`## ${b}`, ...cards.map((c) => `- ${cardHeader(c)} — ${c.summary}`)]);
      const releases = index.releases.releases.filter((r) => opNumber(r.build) > fromN && opNumber(r.build) <= toN).map((r) => r.build);
      return text([`${added.length} natives added after op77.${fromN} up to op77.${toN} (${releases.length} releases)`, ...lines].join("\n"));
    },
  );

  server.registerTool(
    "open77_build",
    {
      title: "Which build this server answers for",
      description: "The index build, where it came from (CDN cache, embedded snapshot), the newest published server build, and the package version.",
      inputSchema: {},
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async () => {
      const newest = [...index.releases.releases].sort((a, b) => opNumber(b.build) - opNumber(a.build))[0];
      return text([
        `index build: ${context.resolved.build} (${context.resolved.origin}${context.resolved.note ? `; ${context.resolved.note}` : ""})`,
        `requested build: ${context.resolved.requestedBuild ?? "latest"}`,
        `newest published server build in the index: ${newest?.build ?? "unknown"} (${newest?.publishedAt ?? ""})`,
        `docs synced: ${index.manifest.docsSyncedAt}; index generated: ${index.manifest.generatedAt}`,
        `cards: ${index.cards.length}; guides: ${index.guides.length}; events: ${index.events.events.length}; permissions: ${index.permissions.permissions.length}`,
        `package: @open2077/mcp ${context.packageVersion}`,
      ].join("\n"));
    },
  );

  // ------------------------------------------------------------- resources

  server.registerResource(
    "skill",
    "open77://skill",
    { title: "Open77 resource development skill", description: "How to build Open77 resources with this MCP: the method, the rules, the loop.", mimeType: "text/markdown" },
    async (uri) => ({ contents: [{ uri: uri.href, text: await readFile(context.skillPath, "utf8"), mimeType: "text/markdown" }] }),
  );

  server.registerResource(
    "guide",
    new ResourceTemplate("open77://guide/{slug}", {
      list: async () => ({ resources: index.guides.map((g) => ({ uri: `open77://guide/${g.slug}`, name: g.title, description: g.summary.slice(0, 200), mimeType: "text/markdown" })) }),
    }),
    { title: "Guides", description: "Open77 documentation guides as Markdown", mimeType: "text/markdown" },
    async (uri, { slug }) => {
      const guide = guideBySlug.get(String(slug));
      if (!guide) throw new Error(`no guide ${String(slug)}`);
      return { contents: [{ uri: uri.href, text: guide.sections.map((s) => renderSection(guide, s)).join("\n\n"), mimeType: "text/markdown" }] };
    },
  );

  server.registerResource(
    "api",
    new ResourceTemplate("open77://api/{runtime}/{namespace}", {
      list: async () => {
        const seen = new Set<string>();
        const resources = [];
        for (const c of index.cards) {
          const key = `${c.runtime}/${c.namespace}`;
          if (seen.has(key)) continue;
          seen.add(key);
          resources.push({ uri: `open77://api/${key}`, name: `${c.runtime} ${c.namespace}`, mimeType: "text/markdown" });
        }
        return { resources };
      },
    }),
    { title: "API namespaces", description: "Every native of one namespace on one runtime", mimeType: "text/markdown" },
    async (uri, { runtime, namespace }) => {
      const cards = index.cards.filter((c) => c.runtime === runtime && c.namespace === namespace);
      return { contents: [{ uri: uri.href, text: cards.map((c) => renderCard(c, context, index.guides)).join("\n\n---\n\n"), mimeType: "text/markdown" }] };
    },
  );

  server.registerResource(
    "stubs",
    new ResourceTemplate("open77://stubs/{runtime}", { list: async () => ({ resources: [
      { uri: "open77://stubs/client", name: "open77-client.d.lua", mimeType: "text/x-lua" },
      { uri: "open77://stubs/server", name: "open77-server.d.lua", mimeType: "text/x-lua" },
    ] }) }),
    { title: "Lua language-server stubs", description: "---@meta stubs generated from the catalogue", mimeType: "text/x-lua" },
    async (uri, { runtime }) => ({ contents: [{ uri: uri.href, text: await readStub(index, runtime === "server" ? "server" : "client"), mimeType: "text/x-lua" }] }),
  );

  // --------------------------------------------------------------- prompts

  server.registerPrompt(
    "new_resource",
    {
      title: "Plan a new Open77 resource",
      description: "Walks the agent through designing a resource for a described feature: which runtime does what, which natives, which permissions, the manifest, the test plan.",
      argsSchema: { feature: z.string().describe("What the resource should do, in a sentence or two"), kind: z.string().optional().describe("blank | gamemode | hud | service") },
    },
    ({ feature, kind }) => ({
      messages: [{
        role: "user",
        content: { type: "text", text: [
          `Design an Open77 resource for: ${feature}${kind ? ` (kind: ${kind})` : ""}.`,
          `Rules: the server is authoritative; clients render and request. Read open77://skill first.`,
          `Steps: 1) open77_search for each capability you need and open77_api on every native you will call; note runtime, permissions and since.`,
          `2) Refuse any native marked NOT AVAILABLE for ${context.resolved.build}; find the alternative.`,
          `3) Write open77.lua with open77_manifest_schema and exactly the permissions the natives require.`,
          `4) Write client and server scripts; never call a client native from a server script or vice versa.`,
          `5) State how to test it in the game (which events, which reasons to expect).`,
        ].join("\n") },
      }],
    }),
  );

  server.registerPrompt(
    "port_fivem_resource",
    {
      title: "Port a FiveM resource",
      description: "Maps a FiveM resource onto Open77: aliases that work as-is, natives to replace, and the parts Open77 deliberately does without.",
      argsSchema: { code: z.string().describe("The FiveM Lua source, or a summary of the natives it uses") },
    },
    ({ code }) => ({
      messages: [{
        role: "user",
        content: { type: "text", text: [
          "Port this FiveM resource to Open77. For every native or Citizen call, use open77_fivem_equivalent, then open77_api on the Open77 replacement.",
          "Keep fxmanifest-style structure but write open77.lua (open77_manifest_schema). Declare only the permissions the replacements need.",
          "List what cannot be ported and why, quoting the guide.",
          "",
          "```lua",
          code,
          "```",
        ].join("\n") },
      }],
    }),
  );

  server.registerPrompt(
    "explain_reason",
    {
      title: "Explain a reason string",
      description: "Why a native returned nil, <reason> or false, <reason>, and what to change.",
      argsSchema: { reason: z.string().describe("e.g. permission_denied:map.read, map_unavailable"), native: z.string().optional() },
    },
    ({ reason, native }) => ({
      messages: [{
        role: "user",
        content: { type: "text", text: `A call${native ? ` to ${native}` : ""} returned the reason "${reason}". Use open77_search (kind card) for the reason string and open77_api on the natives that return it, then explain the cause and the fix. If it is permission_denied:<name>, show the exact manifest line.` },
      }],
    }),
  );

  for (const extension of context.extensions ?? []) extension(server, context);
  return server;

  function findCards(name: string, runtime?: "client" | "server"): ApiCard[] {
    const trimmed = name.trim().replace(/\(.*$/, "");
    // A client route id is the bare qualified name, so a bare name hits the
    // route map first and used to win outright -- `Open77.vehicles.setFrozen`
    // with runtime "server" answered the CLIENT card (measured 2026-09-16 on
    // 0.1.0). Only an explicit route id (`server:` / `client:`) is a direct
    // hit; a bare name goes through the qualified map, where the runtime
    // filter applies and a name both runtimes carry returns both cards.
    if (trimmed.includes(":")) {
      const direct = byRoute.get(trimmed);
      if (direct) return runtime && direct.runtime !== runtime ? [] : [direct];
    }
    const cards = byQualified.get(trimmed.toLowerCase()) ?? [];
    return runtime ? cards.filter((c) => c.runtime === runtime) : cards;
  }
}

export function instructions(context: ServerContext): string {
  return [
    `Open77 Devkit MCP (build ${context.resolved.build}). Open77 turns Cyberpunk 2077 into a server-driven multiplayer platform; gameplay is written as Lua resources with a client and a server side.`,
    "Read the resource open77://skill before writing a resource. Key rules: the server is authoritative; a native exists only if open77_api returns it for this build; declare in open77.lua exactly the permissions the natives you call require; never call a client native from a server script or the reverse; a call answers nil/false plus a reason string on failure — check it.",
    "Workflow: open77_search → open77_api → open77_guide for the how-to → open77_manifest_schema → write → validate (open77_validate when running locally) → reload on the server → read the log.",
    "FiveM developers: the runtime shape (CreateThread, Wait, events, exports, RegisterCommand) is the same; use open77_fivem_equivalent for everything else. Open77 natives are not in your training data: look them up, do not guess.",
  ].join("\n");
}

export function skillPathFor(packageRoot: string): string {
  return path.join(packageRoot, "skill", "SKILL.md");
}
