import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
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
