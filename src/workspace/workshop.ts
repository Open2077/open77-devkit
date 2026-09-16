/**
 * Workshop tools over Warden's Hub API: search the OPEN//77 Workshop, read a
 * release, create an installation plan, install it, follow the job.
 *
 * The consent model is Warden's, unchanged: an install needs the plan's own
 * SHA-256 (which only a client that read the plan can present) *and* an
 * explicit `consent: true` from the caller. The agent is expected to show the
 * plan to the human before either; the tool description says so and the
 * install refuses without both.
 */

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import type { ServerContext } from "../server.js";
import type { Workspace } from "./detect.js";
import { WardenClient, WardenError } from "./warden.js";

function text(body: string) {
  return { content: [{ type: "text" as const, text: body }] };
}

function pretty(value: unknown, limit = 14000): string {
  const json = typeof value === "string" ? value : JSON.stringify(value, null, 1);
  return json.length > limit ? json.slice(0, limit) + "\n…(truncated)" : json;
}

class HubClient {
  constructor(private readonly warden: WardenClient) {}

  private async call<T>(method: "GET" | "POST", route: string, body?: unknown): Promise<T> {
    // WardenClient.request is private by design; go through a thin public
    // surface instead of widening it: the same cookie, origin and error rules.
    return this.warden.raw<T>(method, route, body);
  }

  status() { return this.call<unknown>("GET", "/api/hub/status"); }
  search(query?: string, category?: string, sort?: string, cursor?: string) {
    const params = new URLSearchParams();
    if (query) params.set("query", query);
    if (category) params.set("category", category);
    if (sort) params.set("sort", sort);
    if (cursor) params.set("cursor", cursor);
    return this.call<unknown>("GET", `/api/hub/projects${params.size ? `?${params}` : ""}`);
  }
  resolve(link: string) { return this.call<unknown>("GET", `/api/hub/projects/resolve?link=${encodeURIComponent(link)}`); }
  releases(projectId: string) { return this.call<unknown>("GET", `/api/hub/projects/${projectId}/releases`); }
  plan(request: Record<string, unknown>) { return this.call<unknown>("POST", "/api/hub/plans", request); }
  readPlan(id: string) { return this.call<unknown>("GET", `/api/hub/plans/${id}`); }
  discard(id: string) { return this.call<unknown>("POST", `/api/hub/plans/${id}/discard`, {}); }
  install(id: string, sha256: string) { return this.call<unknown>("POST", `/api/hub/plans/${id}/install`, { sha256 }); }
  job(id: string) { return this.call<unknown>("GET", `/api/hub/jobs/${id}`); }
  installed() { return this.call<unknown>("GET", "/api/hub/installed"); }
}

export function registerWorkshopTools(server: McpServer, context: ServerContext, workspace: () => Workspace): void {
  const hub = async () => {
    const origin = process.env["OPEN77_WARDEN_ORIGIN"] ?? workspace().wardenUrl;
    if (!origin) throw new WardenError("Warden is not enabled in server.jsonc; the Workshop is reached through it.");
    const warden = await WardenClient.fromSession(origin);
    if (!warden.signedIn) throw new WardenError(`No Warden session for ${origin}. Run \`npx -y @open2077/mcp warden-login\` in a terminal first.`);
    return new HubClient(warden);
  };
  const guarded = async (run: (h: HubClient) => Promise<string>) => {
    try {
      return text(await run(await hub()));
    } catch (error) {
      return { ...text(error instanceof WardenError ? error.message : `Workshop call failed: ${(error as Error).message}`), isError: true };
    }
  };

  server.registerTool(
    "open77_workshop_search",
    {
      title: "Search the Workshop",
      description: "Browse the OPEN//77 Workshop (community resources, gamemodes, maps, UI, tools) through this server's Warden, or resolve a pasted link (https://open2077.net/workshop/<name> or workshop:<name>).",
      inputSchema: {
        query: z.string().optional(),
        link: z.string().optional().describe("A Workshop item address; when given, query is ignored"),
        category: z.string().optional().describe("scripts | gamemodes | maps | ui | tools"),
        sort: z.string().optional().describe("trending | newest | downloads"),
        cursor: z.string().optional(),
      },
      annotations: { readOnlyHint: true, openWorldHint: true },
    },
    async ({ query, link, category, sort, cursor }) => guarded(async (h) => pretty(link ? await h.resolve(link) : await h.search(query, category, sort, cursor))),
  );

  server.registerTool(
    "open77_workshop_release",
    {
      title: "Releases of a Workshop project",
      description: "Every release of a project with its state, files, tested builds and declared dependencies; the release id is what a plan needs.",
      inputSchema: { projectId: z.string().uuid() },
      annotations: { readOnlyHint: true, openWorldHint: true },
    },
    async ({ projectId }) => guarded(async (h) => pretty(await h.releases(projectId))),
  );

  server.registerTool(
    "open77_workshop_plan",
    {
      title: "Create or read an installation plan",
      description:
        "Creates an installation plan for one release (Warden inspects the package and lists permissions, dependencies, files it would replace and blockers), or reads an existing plan by id. " +
        "SHOW THE PLAN TO THE HUMAN; the plan's sha256 is what open77_workshop_install needs, together with their consent.",
      inputSchema: {
        planId: z.string().uuid().optional().describe("Read this plan instead of creating one"),
        projectId: z.string().uuid().optional(),
        releaseId: z.string().uuid().optional(),
        allowPrerelease: z.boolean().optional(),
        acknowledgedUntestedReleases: z.array(z.string().uuid()).optional().describe("Release ids the human accepted although they do not list this server build"),
        acknowledgedExternalResources: z.array(z.string()).optional(),
        discard: z.boolean().optional().describe("With planId: discard the plan instead of reading it"),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true },
    },
    async ({ planId, projectId, releaseId, allowPrerelease, acknowledgedUntestedReleases, acknowledgedExternalResources, discard }) => guarded(async (h) => {
      if (planId) return pretty(discard ? await h.discard(planId) : await h.readPlan(planId));
      if (!projectId || !releaseId) return "Creating a plan needs projectId and releaseId (from open77_workshop_release).";
      const request: Record<string, unknown> = { projectId, releaseId };
      if (allowPrerelease !== undefined) request["allowPrerelease"] = allowPrerelease;
      if (acknowledgedUntestedReleases?.length) request["acknowledgedUntestedReleases"] = acknowledgedUntestedReleases;
      if (acknowledgedExternalResources?.length) request["acknowledgedExternalResources"] = acknowledgedExternalResources;
      return `Plan created; show it to the human before installing:\n${pretty(await h.plan(request))}`;
    }),
  );

  server.registerTool(
    "open77_workshop_install",
    {
      title: "Install a reviewed plan",
      description:
        "Installs a plan the human has read and accepted. Requires consent=true and the plan's sha256 exactly as open77_workshop_plan returned it; Warden refuses anything else. " +
        "Returns the job id; follow it with open77_workshop_job. Never call this without the human's explicit yes.",
      inputSchema: {
        planId: z.string().uuid(),
        sha256: z.string().regex(/^[0-9a-f]{64}$/i),
        consent: z.literal(true).describe("The human explicitly accepted this plan"),
      },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true },
    },
    async ({ planId, sha256, consent }) => guarded(async (h) => {
      if (consent !== true) return "Refused: install needs the human's explicit consent.";
      return pretty(await h.install(planId, sha256.toLowerCase()));
    }),
  );

  server.registerTool(
    "open77_workshop_job",
    {
      title: "Installation job status, installed packages",
      description: "Follows an installation job by id (done when it reports committed), or lists the packages installed through the Workshop when no id is given.",
      inputSchema: { jobId: z.string().uuid().optional() },
      annotations: { readOnlyHint: true, openWorldHint: true },
    },
    async ({ jobId }) => guarded(async (h) => pretty(jobId ? await h.job(jobId) : await h.installed())),
  );

  server.registerTool(
    "open77_workshop_status",
    {
      title: "Workshop availability on this server",
      description: "Whether this server can browse, install and publish through the Workshop (masterServer and warden.hubFileGatewayOrigin settings).",
      inputSchema: {},
      annotations: { readOnlyHint: true, openWorldHint: true },
    },
    async () => guarded(async (h) => pretty(await h.status())),
  );

  void context;
}
