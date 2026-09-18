/**
 * What the runtime installs that the cards do not describe as cards.
 *
 * The index is generated from the API cards and the guides; two shapes only
 * exist in the guides' prose and would otherwise read as "not in the
 * catalogue":
 *
 *   - a global that aliases a whole namespace: `MySQL` is `Open77.database`
 *     ("`Open77.database` and the global `MySQL` are the same
 *     oxmysql-compatible table" -- the `Open77.database.query` card and the
 *     `server-api#database` guide);
 *   - the `.await` sub-form of a native: `Open77.database.query.await(sql,
 *     params)` is the same native as `Open77.database.query`, called without a
 *     callback from a managed coroutine (the guide's "Await form" column);
 *   - a global documented by a guide table row that the generator did not
 *     turn into a card: the server `exports(name, fn)` and `print(...)`.
 *
 * Each table entry names the guide section that documents it, and every
 * entry is applied only when the index it is used with still carries the
 * thing it points at: an alias needs its target namespace on the build, a
 * guide-only global is dormant as soon as a real card exists for it. The
 * embedded-index test checks that the guide sections named here exist and
 * mention the name, so a table entry cannot outlive its documentation.
 */

import type { ApiCard, DevIndex } from "./types.js";

export interface NamespaceAlias {
  /** The global as written in a resource (`MySQL`). */
  alias: string;
  /** The catalogued namespace it stands for (`Open77.database`). */
  target: string;
  runtime: "client" | "server";
  /** `slug#anchor` of the guide section that documents the alias. */
  guide: string;
}

export const NAMESPACE_ALIASES: readonly NamespaceAlias[] = [
  { alias: "MySQL", target: "Open77.database", runtime: "server", guide: "server-api#database" },
];

/** The trailing member that turns a callback-form native into its await form. */
export const AWAIT_SUFFIX = ".await";

export interface GuideOnlyGlobal {
  name: string;
  runtime: "client" | "server";
  signature: string;
  summary: string;
  /** `slug#anchor` sections, the most useful first. */
  guides: string[];
}

export const GUIDE_ONLY_GLOBALS: readonly GuideOnlyGlobal[] = [
  {
    name: "exports",
    runtime: "server",
    signature: "exports(name: string, fn: function)",
    summary: "Publishes or replaces a server export of this resource; true, or nil and a reason. Indexed instead of called it is the synchronous proxy: exports.other:name(...) / exports['other-resource']:name(...) runs that export inline.",
    guides: ["server-exports#publish-a-service", "server-api#cross-resource-exports", "server-exports#execution-identity-and-permissions"],
  },
  {
    name: "print",
    runtime: "server",
    signature: "print(...: any)",
    summary: "Writes a resource-prefixed INF entry to the server log; the values are joined with a tab. Citizen.Trace is the debug-level sibling.",
    guides: ["server-api#logging", "server-api#runtime-scheduler-events-commands-and-json"],
  },
];

/**
 * The namespaces the index has cards for. An alias applies only when its
 * target is among them; on an index without `Open77.database` the global
 * `MySQL` is as unknown as any other undeclared name.
 */
export function namespacesOf(cards: readonly ApiCard[]): Set<string> {
  return new Set(cards.map((c) => c.namespace));
}

/**
 * `MySQL.query.await` -> `Open77.database.query.await`; anything else comes
 * back unchanged. The runtime is not checked here: the caller resolves the
 * card and reports a server native in a client script as it does for any
 * other name.
 */
export function resolveNamespaceAlias(qualified: string, namespaces: ReadonlySet<string>): string {
  const dot = qualified.indexOf(".");
  const head = dot < 0 ? qualified : qualified.slice(0, dot);
  for (const alias of NAMESPACE_ALIASES) {
    if (alias.alias === head && namespaces.has(alias.target)) return alias.target + qualified.slice(head.length);
  }
  return qualified;
}

/**
 * `Open77.database.query.await` -> `Open77.database.query` when the shorter
 * name is catalogued; otherwise the name as given. `has` answers for the
 * catalogue the caller resolves against.
 */
export function stripAwaitForm(qualified: string, has: (name: string) => boolean): { qualified: string; awaited: boolean } {
  if (qualified.endsWith(AWAIT_SUFFIX)) {
    const base = qualified.slice(0, -AWAIT_SUFFIX.length);
    if (base.includes(".") && has(base)) return { qualified: base, awaited: true };
  }
  return { qualified, awaited: false };
}

/** Whether a card documents an `.await` form (description, returns or example). */
export function documentsAwaitForm(card: ApiCard): boolean {
  return /\bawait\b/i.test(card.description) || card.returns.some((r) => /\bawait\b/i.test(r)) || /\.await\s*\(/.test(card.example ?? "");
}

/** The guide-only globals that still have no card on this index, for one runtime. */
export function guideOnlyGlobals(index: DevIndex, runtime?: "client" | "server"): GuideOnlyGlobal[] {
  const carded = new Set(index.cards.filter((c) => c.namespace === "_G").map((c) => `${c.runtime}:${c.name}`));
  return GUIDE_ONLY_GLOBALS.filter((g) => (!runtime || g.runtime === runtime) && !carded.has(`${g.runtime}:${g.name}`));
}
