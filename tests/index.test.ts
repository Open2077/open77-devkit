import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { chunkGuide, opNumber, parseFivemGuide } from "../src/index/builder.js";
import { loadIndex } from "../src/index/loader.js";
import { IndexSearch } from "../src/index/search.js";
import type { ApiCard } from "../src/index/types.js";
import type { ServerContext } from "../src/server.js";
import { availabilityNote } from "../src/server.js";
import { detectWorkspace } from "../src/workspace/detect.js";
import { scaffold } from "../src/workspace/scaffold.js";
import { parseManifest, validateResource } from "../src/workspace/validate.js";

const INDEX_DIR = path.resolve("index");

async function context(build?: string): Promise<ServerContext> {
  const index = await loadIndex(INDEX_DIR);
  return {
    index,
    resolved: { directory: INDEX_DIR, build: build ?? index.manifest.build, origin: "embedded" },
    packageVersion: "test",
    skillPath: path.resolve("skill/SKILL.md"),
  };
}

test("opNumber reads the op77 build number", () => {
  assert.equal(opNumber("2.31.13+op77.69"), 69);
  assert.equal(opNumber("nonsense"), -1);
});

test("chunkGuide splits by heading, dedupes anchors and finds natives", () => {
  const card = { qualified: "Open77.map.getWaypoint", route_id: "Open77.map.getWaypoint" } as ApiCard;
  const guide = chunkGuide("x.md", [
    "# Title",
    "Intro paragraph.",
    "## Read",
    "```lua",
    "permissions { \"map.read\" }",
    "local w = Open77.map.getWaypoint()",
    "```",
    "## Read",
    "again `open77:map:opened`",
  ].join("\n"), new Map([["Open77.map.getWaypoint", [card]]]));
  assert.equal(guide.title, "Title");
  assert.equal(guide.summary, "Intro paragraph.");
  assert.deepEqual(guide.sections.map((s) => s.anchor), ["title", "read", "read-2"]);
  assert.deepEqual(guide.sections[1]!.natives, ["Open77.map.getWaypoint"]);
  assert.deepEqual(guide.sections[1]!.permissions, ["map.read"]);
  assert.deepEqual(guide.sections[2]!.events, ["open77:map:opened"]);
});

test("parseFivemGuide reads alias tables", () => {
  const rows = parseFivemGuide([
    "## Availability",
    "| Name | Client | Server | Open77 |",
    "|---|---|---|---|",
    "| `Citizen.Wait` / `Citizen.CreateThread` | yes | yes | the same function |",
    "| `Citizen.CreateThreadNow` | **no** | **no** | see missing |",
  ].join("\n"));
  assert.equal(rows.length, 3);
  assert.equal(rows[0]!.status, "alias");
  assert.equal(rows[2]!.status, "missing");
  assert.equal(rows[2]!.guideAnchor, "availability");
});

test("the embedded index loads, verifies and searches", async () => {
  const ctx = await context();
  assert.ok(ctx.index.cards.length > 1000);
  assert.ok(ctx.index.cards.every((c) => "permissions" in c && "since" in c));
  const search = new IndexSearch(ctx.index);
  const hits = search.search("Open77.map.getWaypoint", { kinds: ["card"], limit: 3 });
  assert.equal(hits[0]!.title, "Open77.map.getWaypoint");
  const fivem = search.search("GetPlayerPed", { limit: 5 });
  assert.ok(fivem.length > 0);
});

test("open77_api honours the runtime for a name both runtimes carry", async () => {
  // A client route id is the bare qualified name, so a bare name used to hit
  // the route map first and answer the client card whatever `runtime` said.
  const { Client } = await import("@modelcontextprotocol/sdk/client/index.js");
  const { InMemoryTransport } = await import("@modelcontextprotocol/sdk/inMemory.js");
  const { createMcpServer } = await import("../src/server.js");
  const ctx = await context();
  const both = ctx.index.cards.find((c) => c.runtime === "server" && ctx.index.cards.some((o) => o.runtime === "client" && o.qualified === c.qualified))!;
  assert.ok(both, "the embedded index has a name shared by both runtimes");
  const server = createMcpServer(ctx);
  const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
  await server.connect(serverSide);
  const client = new Client({ name: "test", version: "0" });
  await client.connect(clientSide);
  const ask = async (args: Record<string, unknown>) => {
    const result = await client.callTool({ name: "open77_api", arguments: args });
    return (result.content as { type: string; text: string }[]).map((c) => c.text).join("\n");
  };
  const head = (runtime: string) => `# ${runtime} ${both.qualified}(`;
  assert.ok((await ask({ name: both.qualified, runtime: "server" })).startsWith(head("server")), "server card for runtime=server");
  assert.ok((await ask({ name: both.qualified, runtime: "client" })).startsWith(head("client")), "client card for runtime=client");
  const bare = await ask({ name: both.qualified });
  assert.match(bare, /^# client /);
  assert.match(bare, /\n# server /);
  assert.match(await ask({ name: `server:${both.qualified}` }), /^# server /);
  await client.close();
  await server.close();
});

test("search puts cards next to guides for a question in words", async () => {
  // Measured 2026-09-16 (four eval agents): "spawn vehicle" and "player in
  // vehicle" answered guide sections only; the cards were found by dumping a
  // 115-line namespace. camelCase-aware tokens and card/guide interleaving.
  const ctx = await context();
  const search = new IndexSearch(ctx.index);
  const spawn = search.search("spawn vehicle", { limit: 12 });
  assert.ok(spawn.some((h) => h.kind === "card" && /Open77\.vehicles\.create$/.test(h.title)), "vehicles.create among the hits");
  assert.ok(spawn.slice(0, 4).some((h) => h.kind === "card"), "a card in the top four");
  const seat = search.search("player in vehicle", { limit: 12 });
  assert.ok(seat.some((h) => h.kind === "card" && /isInVehicle|getPlayerSeat|getVehicleSeat|occupantInSeat|PlayerIntoVehicle/.test(h.title)), "a seat native among the hits");
});

test("open77_guide accepts a search ref, a heading and a loose anchor", async () => {
  const { Client } = await import("@modelcontextprotocol/sdk/client/index.js");
  const { InMemoryTransport } = await import("@modelcontextprotocol/sdk/inMemory.js");
  const { createMcpServer } = await import("../src/server.js");
  const ctx = await context();
  const guide = ctx.index.guides.find((g) => g.sections.length > 2)!;
  const section = guide.sections[1]!;
  const server = createMcpServer(ctx);
  const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
  await server.connect(serverSide);
  const client = new Client({ name: "test", version: "0" });
  await client.connect(clientSide);
  const ask = async (name: string, args: Record<string, unknown>) => {
    const result = await client.callTool({ name, arguments: args });
    return (result.content as { type: string; text: string }[]).map((c) => c.text).join("\n");
  };
  const byRef = await ask("open77_guide", { slug: `${guide.slug}#${section.anchor}` });
  assert.ok(!byRef.startsWith("No guide"), "slug#anchor is accepted");
  assert.ok(byRef.includes(section.heading), "the section came back");
  const byHeading = await ask("open77_guide", { slug: guide.slug, section: section.heading });
  assert.ok(byHeading.includes(section.heading), "a heading is accepted as the section");
  const loose = await ask("open77_guide", { slug: guide.slug, section: `#${section.anchor.toUpperCase()}` });
  assert.ok(loose.includes(section.heading), "case and a leading # are ignored");
  // paging on the data catalogues
  const first = await ask("open77_data", { catalogue: "vehicles", query: "v_", limit: 5 });
  assert.match(first, /more: pass offset=5/);
  const second = await ask("open77_data", { catalogue: "vehicles", query: "v_", limit: 5, offset: 5 });
  assert.match(second, /from 5/);
  // a FiveM native absent from the alias table still answers with cards
  const port = await ask("open77_fivem_equivalent", { name: "GetVehiclePedIsIn" });
  assert.match(port, /getPlayerSeat|getVehicleSeat|isInVehicle|occupantInSeat/);
  await client.close();
  await server.close();
});

test("availabilityNote refuses natives newer than the served build", async () => {
  const ctx = await context("2.31.13+op77.54");
  const newer = ctx.index.cards.find((c) => c.since && opNumber(c.since) > 54)!;
  assert.match(availabilityNote(newer, ctx)!, /NOT AVAILABLE/);
  const older = ctx.index.cards.find((c) => c.since && opNumber(c.since) <= 54)!;
  assert.equal(availabilityNote(older, ctx), null);
});

test("parseManifest reads scalars, booleans and lists like the server", async () => {
  const ctx = await context();
  const parsed = parseManifest([
    "-- comment",
    'resource "demo"',
    "auto_start false",
    'permissions { "network.events",',
    '  "world.vehicles" }',
    "client_script 'client/main.lua'",
    'bogus "x"',
  ].join("\n"), ctx.index.manifestSchema.directives);
  assert.equal(parsed.scalars["resource"], "demo");
  assert.equal(parsed.booleans["auto_start"], false);
  assert.deepEqual(parsed.lists["permissions"], ["network.events", "world.vehicles"]);
  assert.deepEqual(parsed.lists["client_scripts"], ["client/main.lua"]);
  assert.equal(parsed.unknown[0]!.name, "bogus");
});

test("a scaffolded resource validates clean; a broken one does not", async () => {
  const ctx = await context();
  const root = await mkdtemp(path.join(os.tmpdir(), "open77-devkit-"));
  try {
    const good = path.join(root, "demo_mode");
    await scaffold(good, "demo_mode", "gamemode", ctx, "a test gamemode");
    const clean = await validateResource(good, ctx);
    assert.deepEqual(clean.filter((f) => f.severity === "error"), []);
    const hud = path.join(root, "demo_hud");
    await scaffold(hud, "demo_hud", "hud", ctx, "a test hud");
    const hudClient = await readFile(path.join(hud, "client", "main.lua"), "utf8");
    assert.match(hudClient, /Open77\.webui\.create/);
    assert.deepEqual((await validateResource(hud, ctx)).filter((f) => f.severity === "error"), []);

    const bad = path.join(root, "bad_res");
    await mkdir(path.join(bad, "server"), { recursive: true });
    await writeFile(path.join(bad, "open77.lua"), 'resource "other"\nserver_script "server/main.lua"\n', "utf8");
    await writeFile(path.join(bad, "server/main.lua"), "Open77.camera.attach(1)\nOpen77.nope.thing()\nTriggerClientEvent('x', -1)\n", "utf8");
    const findings = await validateResource(bad, ctx);
    const messages = findings.filter((f) => f.severity === "error").map((f) => f.message);
    assert.ok(messages.some((m) => /does not match the directory/.test(m)), messages.join("\n"));
    assert.ok(messages.some((m) => /Open77.nope.thing is not in the catalogue/.test(m)), messages.join("\n"));
    assert.ok(messages.some((m) => /Open77.camera.attach is a client native used in a server script/.test(m)), messages.join("\n"));
    assert.ok(messages.some((m) => /network.events is required by TriggerClientEvent/.test(m)), messages.join("\n"));

    // Eval 3: the sandbox, the dependency grammar and references that are not calls.
    const sand = path.join(root, "sand_res");
    await mkdir(path.join(sand, "server"), { recursive: true });
    await mkdir(path.join(sand, "client"), { recursive: true });
    await writeFile(path.join(sand, "open77.lua"), [
      'resource "sand_res"',
      'dependency "open77_notifications >=1.0.0"',
      'dependency "open77_zones >=abc"',
      'server_script "server/main.lua"',
      'client_script "client/main.lua"',
      "",
    ].join("\n"), "utf8");
    await writeFile(path.join(sand, "server/main.lua"), [
      "local when = os.time()",
      'local helper = require("helper")',
      "local ghost = Open77.vehicles.nothing.here",
      "local send = Open77.chat.send",
      "local ns = Open77.vehicles",
      "local function load(x) return x end",
      "print(load(1))",
      "",
    ].join("\n"), "utf8");
    await writeFile(path.join(sand, "client/main.lua"), "local t = setmetatable({}, {})\nlocal co = coroutine.create(function() end)\n", "utf8");
    const sandbox = await validateResource(sand, ctx);
    const errors = sandbox.filter((f) => f.severity === "error").map((f) => `${f.file}:${f.line ?? 0} ${f.message}`);
    assert.ok(errors.some((m) => /^server\/main.lua:1 os is nil/.test(m)), errors.join("\n"));
    assert.ok(errors.some((m) => /^server\/main.lua:2 require is nil/.test(m)), errors.join("\n"));
    assert.ok(errors.some((m) => /^server\/main.lua:3 Open77.vehicles.nothing is not in the catalogue/.test(m)), errors.join("\n"));
    assert.ok(!errors.some((m) => /Open77.chat.send|Open77.vehicles is not|load is nil/.test(m)), errors.join("\n"));
    assert.ok(errors.some((m) => /^client\/main.lua:1 setmetatable is nil in the client sandbox/.test(m)), errors.join("\n"));
    assert.ok(errors.some((m) => /^client\/main.lua:2 coroutine.create is nil in the client sandbox/.test(m)), errors.join("\n"));
    assert.ok(errors.some((m) => /constraint >=abc is not/.test(m)), errors.join("\n"));
    assert.ok(!sandbox.some((f) => /open77_notifications >=1.0.0/.test(f.message)), "the runtime's dependency grammar is accepted");
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("detectWorkspace finds a server by server.jsonc and reads its config", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "open77-server-"));
  try {
    await mkdir(path.join(root, "resources", "hello"), { recursive: true });
    await writeFile(path.join(root, "resources", "hello", "open77.lua"), 'resource "hello"\n', "utf8");
    await writeFile(path.join(root, "server.jsonc"), '{ "resources": { "root": "./resources" }, "warden": { "enabled": true, "listenUrl": "http://0.0.0.0:11780" } }', "utf8");
    await writeFile(path.join(root, "Open77.Server.dll"), Buffer.concat([Buffer.alloc(100), Buffer.from("2.31.13+op77.61", "utf8"), Buffer.alloc(100)]));
    const workspace = await detectWorkspace(path.join(root, "resources", "hello"));
    assert.equal(workspace.serverDir, root);
    assert.equal(workspace.build, "2.31.13+op77.61");
    assert.equal(workspace.buildSource, "binary");
    assert.equal(workspace.wardenUrl, "http://127.0.0.1:11780");
    assert.deepEqual(workspace.resources, ["hello"]);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("runtimeLint reads the server's own verdict when a binary is given", { skip: !process.env["OPEN77_TEST_SERVER_DLL"] }, async () => {
  const { runtimeLint } = await import("../src/workspace/validate.js");
  const root = await mkdtemp(path.join(os.tmpdir(), "open77-lint-"));
  try {
    const bad = path.join(root, "lint_bad");
    await mkdir(path.join(bad, "server"), { recursive: true });
    await writeFile(path.join(bad, "open77.lua"), 'resource "lint_bad"\nserver_script "server/main.lua"\n', "utf8");
    await writeFile(path.join(bad, "server/main.lua"), "local x = = 1\n", "utf8");
    const findings = await runtimeLint(process.env["OPEN77_TEST_SERVER_DLL"]!, bad);
    assert.ok(findings, "no runtime report");
    assert.ok(findings.some((f) => f.severity === "error" && /unexpected symbol/.test(f.message)), JSON.stringify(findings));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
