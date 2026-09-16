/**
 * Lexical search over everything the index knows: cards, guide sections,
 * events, permissions and FiveM aliases. MiniSearch with prefix and fuzzy
 * matching, boosted on the identifier fields so `getWaypoint` lands on the
 * card before it lands on a paragraph that mentions it.
 *
 * Lexical on purpose: it runs offline, it is deterministic, and the corpus is
 * small enough (a few thousand documents) that an embedding index would buy
 * nothing a synonym list does not.
 */

import MiniSearch from "minisearch";
import type { DevIndex } from "./types.js";

export type SearchKind = "card" | "guide" | "event" | "permission" | "fivem";

export interface SearchHit {
  kind: SearchKind;
  id: string;
  title: string;
  runtime?: "client" | "server";
  snippet: string;
  score: number;
  /** Where to read the full thing: a route id, a guide anchor, an event or permission name. */
  ref: string;
}

interface Doc {
  id: string;
  kind: SearchKind;
  title: string;
  name: string;
  runtime: string;
  text: string;
  ref: string;
  snippet: string;
}

/** FiveM names an agent is likely to type, mapped to Open77 search terms. */
const SYNONYMS: Record<string, string> = {
  ped: "character player",
  peds: "npcs",
  playerped: "character",
  getplayerped: "Open77.character",
  entity: "entity vehicle npc prop",
  coords: "position",
  getentitycoords: "position",
  setentitycoords: "teleport",
  teleport: "travel teleport",
  blip: "blips",
  waypoint: "map waypoint",
  notification: "hud notify notifications",
  notify: "hud notify",
  chat: "chat",
  vehicle: "vehicles",
  car: "vehicles spawn",
  spawncar: "vehicles spawn",
  weapon: "weapons",
  ammo: "weapons ammo",
  ace: "acl access",
  aceallowed: "acl",
  kvp: "kvp",
  statebag: "state bags",
  freeze: "freeze player",
  ragdoll: "motion",
  anim: "animations",
  emote: "animations rp",
  scaleform: "webui",
  nui: "webui",
  sendnuimessage: "WebUI.Page",
  marker: "markers",
  zone: "zones polyzone",
  polyzone: "polyzone",
  bucket: "routingBuckets",
  routingbucket: "routingBuckets",
  weather: "environment weather",
  time: "environment time",
  door: "doors",
  elevator: "elevators",
  ped_task: "npcs tasks",
  task: "npcs tasks",
};

function expand(query: string): string {
  const words = query.toLowerCase().split(/[^a-z0-9_.:]+/).filter(Boolean);
  const extra: string[] = [];
  for (const word of words) {
    const key = word.replace(/[._]/g, "");
    if (SYNONYMS[key]) extra.push(SYNONYMS[key]!);
    // `Open77.map.getWaypoint` -> also the bare `getWaypoint` and `map`
    if (word.includes(".")) extra.push(...word.split("."));
    // camelCase -> words
    const split = word.replace(/([a-z])([A-Z])/g, "$1 $2");
    if (split !== word) extra.push(split);
  }
  return [query, ...extra].join(" ");
}

export interface SearchOptions {
  kinds?: SearchKind[];
  runtime?: "client" | "server";
  limit?: number;
}

export class IndexSearch {
  private readonly engine: MiniSearch<Doc>;
  private readonly docs = new Map<string, Doc>();

  constructor(index: DevIndex) {
    this.engine = new MiniSearch<Doc>({
      fields: ["name", "title", "text"],
      storeFields: ["kind", "title", "runtime", "ref", "snippet"],
      searchOptions: {
        boost: { name: 6, title: 3 },
        prefix: true,
        fuzzy: 0.15,
        combineWith: "OR",
      },
      tokenize: (text) => text.toLowerCase().split(/[^a-z0-9_]+/).filter((t) => t.length > 1),
    });
    const docs: Doc[] = [];
    for (const card of index.cards) {
      docs.push({
        id: `card:${card.route_id}`,
        kind: "card",
        title: card.qualified,
        name: `${card.name} ${card.qualified} ${card.namespace}`,
        runtime: card.runtime,
        text: [card.summary, card.description, card.permissions.join(" "), card.reasons.join(" ")].join("\n"),
        ref: card.route_id,
        snippet: card.summary,
      });
    }
    for (const guide of index.guides) {
      for (const section of guide.sections) {
        docs.push({
          id: `guide:${guide.slug}#${section.anchor}`,
          kind: "guide",
          title: `${guide.title} › ${section.heading}`,
          name: `${guide.slug} ${section.heading}`,
          runtime: "",
          text: section.text.slice(0, 6000),
          ref: `${guide.slug}#${section.anchor}`,
          snippet: section.text.replace(/```[\s\S]*?```/g, " ").replace(/\s+/g, " ").slice(0, 220),
        });
      }
    }
    for (const event of index.events.events) {
      docs.push({
        id: `event:${event.name}`,
        kind: "event",
        title: event.name,
        name: event.name.replace(/[:_]/g, " "),
        runtime: "",
        text: [event.payload ?? "", event.sides.join(" "), event.guides.map((g) => g.file).join(" ")].join(" "),
        ref: event.name,
        snippet: event.payload ? `payload ${event.payload}` : event.documented ? "documented" : "seen in code only",
      });
    }
    for (const permission of index.permissions.permissions) {
      docs.push({
        id: `permission:${permission.name}`,
        kind: "permission",
        title: permission.name,
        name: permission.name.replace(/\./g, " "),
        runtime: "",
        text: `${permission.summary} ${permission.natives.slice(0, 40).join(" ")}`,
        ref: permission.name,
        snippet: permission.summary,
      });
    }
    for (const mapping of index.fivem) {
      docs.push({
        id: `fivem:${mapping.fivem}`,
        kind: "fivem",
        title: mapping.fivem,
        name: `${mapping.fivem} ${mapping.fivem.replace(/([a-z])([A-Z])/g, "$1 $2")}`,
        runtime: "",
        text: `${mapping.status} ${mapping.open77}`,
        ref: mapping.fivem,
        snippet: `${mapping.status}: ${mapping.open77}`,
      });
    }
    // An index built by an older builder could carry a duplicate section id;
    // the first wins and the engine is never asked to add it twice.
    for (const doc of docs) if (!this.docs.has(doc.id)) this.docs.set(doc.id, doc);
    this.engine.addAll([...this.docs.values()]);
  }

  search(query: string, options: SearchOptions = {}): SearchHit[] {
    const limit = options.limit ?? 12;
    const expanded = expand(query);
    const raw = this.engine.search(expanded, {
      filter: (result) => {
        if (options.kinds && !options.kinds.includes(result["kind"] as SearchKind)) return false;
        if (options.runtime && result["runtime"] && result["runtime"] !== options.runtime) return false;
        return true;
      },
    });
    // An exact identifier match outranks everything: `Open77.map.getWaypoint`
    // typed verbatim is not a fuzzy question.
    const exact = raw.filter((r) => (r["title"] as string).toLowerCase() === query.trim().toLowerCase());
    const rest = raw.filter((r) => !exact.includes(r));
    return [...exact, ...rest].slice(0, limit).map((r) => ({
      kind: r["kind"] as SearchKind,
      id: r.id as string,
      title: r["title"] as string,
      ...(r["runtime"] ? { runtime: r["runtime"] as "client" | "server" } : {}),
      snippet: r["snippet"] as string,
      score: Math.round(r.score * 100) / 100,
      ref: r["ref"] as string,
    }));
  }
}
