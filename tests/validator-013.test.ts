/**
 * The 0.1.3 fixes, each measured by an MCP-only agent on 2026-09-18 against
 * the index for 2.31.13+op77.76:
 *   - `Open77.database.*.await` and the `MySQL` alias read as unknown natives;
 *   - `open77_api client:<name>` was refused while `server:` worked;
 *   - `server:exports` / `server:print` answered "missing" although the
 *     server-exports guide uses both;
 *   - a command name another loaded resource already registers went unnoticed.
 */

import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { GUIDE_ONLY_GLOBALS, NAMESPACE_ALIASES, guideOnlyGlobals, resolveNamespaceAlias, stripAwaitForm } from "../src/index/conventions.js";
import { loadIndex } from "../src/index/loader.js";
import type { ServerContext } from "../src/server.js";
import { detectWorkspace, findResourceDir } from "../src/workspace/detect.js";
import { commandCollisions, registeredCommands, validateResource } from "../src/workspace/validate.js";

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

async function mcpClient(ctx: ServerContext) {
  const { Client } = await import("@modelcontextprotocol/sdk/client/index.js");
  const { InMemoryTransport } = await import("@modelcontextprotocol/sdk/inMemory.js");
  const { createMcpServer } = await import("../src/server.js");
  const server = createMcpServer(ctx);
  const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
  await server.connect(serverSide);
  const client = new Client({ name: "test", version: "0" });
  await client.connect(clientSide);
  const ask = async (name: string, args: Record<string, unknown>) => {
    const result = await client.callTool({ name, arguments: args });
    return (result.content as { type: string; text: string }[]).map((c) => c.text).join("\n");
  };
  const close = async () => {
    await client.close();
    await server.close();
  };
  return { ask, close };
}

const BANK_SERVER = [
  "MySQL.ready(function()",
  "    MySQL.query.await([[CREATE TABLE IF NOT EXISTS bank (id BIGINT PRIMARY KEY, money INT NOT NULL)]])",
  "end)",
  "CreateThread(function()",
  '    local rows = Open77.database.query.await("SELECT id, money FROM bank WHERE id = ?", { 1 })',
  '    Open77.database.update.await("UPDATE bank SET money = ? WHERE id = ?", { 10, 1 })',
  "    local ready = MySQL.isReady()",
  '    MySQL.update("DELETE FROM bank WHERE id = ?", { 1 }, function(affected) print(affected) end)',
  "    local single = MySQL.single.await",
  "end)",
  "",
].join("\n");

test("the conventions table is backed by the index it is used with", async () => {
  const ctx = await context();
  const bySlug = new Map(ctx.index.guides.map((g) => [g.slug, g]));
  const sectionText = (ref: string) => {
    const [slug, anchor] = ref.split("#");
    const section = bySlug.get(slug!)?.sections.find((s) => s.anchor === anchor);
    assert.ok(section, `${ref} is a section of the embedded index`);
    return section.text;
  };
  for (const alias of NAMESPACE_ALIASES) {
    const text = sectionText(alias.guide);
    assert.ok(text.includes(`\`${alias.alias}\``), `${alias.guide} names ${alias.alias}`);
    assert.ok(text.includes(`\`${alias.target}\``), `${alias.guide} names ${alias.target}`);
    assert.ok(ctx.index.cards.some((c) => c.namespace === alias.target && c.runtime === alias.runtime), `${alias.target} has ${alias.runtime} cards`);
  }
  for (const global of GUIDE_ONLY_GLOBALS) {
    assert.ok(global.guides.length, `${global.name} points at a guide`);
    assert.ok(sectionText(global.guides[0]!).includes(global.name), `${global.guides[0]} mentions ${global.name}`);
  }
  // Dormant as soon as a card exists: the client `exports` has one.
  assert.ok(!guideOnlyGlobals(ctx.index, "client").some((g) => g.name === "exports"));
  assert.deepEqual(guideOnlyGlobals(ctx.index, "server").map((g) => g.name).sort(), ["exports", "print"]);

  const namespaces = new Set(ctx.index.cards.map((c) => c.namespace));
  assert.equal(resolveNamespaceAlias("MySQL.query.await", namespaces), "Open77.database.query.await");
  assert.equal(resolveNamespaceAlias("MySQL", namespaces), "Open77.database");
  assert.equal(resolveNamespaceAlias("Open77.chat.send", namespaces), "Open77.chat.send");
  assert.equal(resolveNamespaceAlias("MySQL.query", new Set(["Open77.chat"])), "MySQL.query", "no alias on an index without the target namespace");
  const has = (n: string) => n === "Open77.database.query";
  assert.deepEqual(stripAwaitForm("Open77.database.query.await", has), { qualified: "Open77.database.query", awaited: true });
  assert.deepEqual(stripAwaitForm("Open77.database.query", has), { qualified: "Open77.database.query", awaited: false });
  assert.deepEqual(stripAwaitForm("Open77.nope.await", has), { qualified: "Open77.nope.await", awaited: false });
});

test("validate accepts the database .await forms and the MySQL alias, and still enforces database.access", async () => {
  const ctx = await context("2.31.13+op77.76");
  const root = await mkdtemp(path.join(os.tmpdir(), "open77-db-"));
  try {
    const bank = path.join(root, "bank_res");
    await mkdir(path.join(bank, "server"), { recursive: true });
    await writeFile(path.join(bank, "open77.lua"), 'resource "bank_res"\npermissions { "database.access" }\nserver_script "server/main.lua"\n', "utf8");
    await writeFile(path.join(bank, "server/main.lua"), BANK_SERVER, "utf8");
    const clean = await validateResource(bank, ctx);
    assert.deepEqual(clean.filter((f) => f.severity !== "note"), [], JSON.stringify(clean, null, 1));
    assert.ok(!clean.some((f) => /declared but no catalogued native/.test(f.message)), "database.access is seen as used");

    // The same scripts without the permission: one error naming the calls as written.
    await writeFile(path.join(bank, "open77.lua"), 'resource "bank_res"\nserver_script "server/main.lua"\n', "utf8");
    const denied = await validateResource(bank, ctx);
    const errors = denied.filter((f) => f.severity === "error").map((f) => f.message);
    assert.equal(errors.length, 1, errors.join("\n"));
    assert.match(errors[0]!, /^permission database\.access is required by MySQL\.ready, MySQL\.query\.await, Open77\.database\.query\.await/);

    // Unknown members and undocumented .await forms are still caught, under the written name.
    const odd = path.join(root, "odd_res");
    await mkdir(path.join(odd, "server"), { recursive: true });
    await mkdir(path.join(odd, "client"), { recursive: true });
    await writeFile(path.join(odd, "open77.lua"), 'resource "odd_res"\npermissions { "database.access" }\nserver_script "server/main.lua"\nclient_script "client/main.lua"\n', "utf8");
    await writeFile(path.join(odd, "server/main.lua"), 'MySQL.nonsense("x")\nlocal z = MySQL.zzz.yyy\nOpen77.chat.send.await(1, "hi")\n', "utf8");
    await writeFile(path.join(odd, "client/main.lua"), 'MySQL.query.await("SELECT 1")\n', "utf8");
    const findings = (await validateResource(odd, ctx)).map((f) => `${f.severity} ${f.file}:${f.line ?? 0} ${f.message}`);
    assert.ok(findings.some((m) => /^error server\/main.lua:1 MySQL.nonsense \(Open77.database.nonsense\) is not in the catalogue/.test(m)), findings.join("\n"));
    assert.ok(findings.some((m) => /^error server\/main.lua:2 MySQL.zzz \(Open77.database.zzz\) is not in the catalogue/.test(m)), findings.join("\n"));
    assert.ok(findings.some((m) => /^warning server\/main.lua:3 Open77.chat.send.await: the server card of Open77.chat.send documents no .await form/.test(m)), findings.join("\n"));
    assert.ok(findings.some((m) => /^error client\/main.lua:1 MySQL.query.await \(Open77.database.query\) is a server native used in a client script/.test(m)), findings.join("\n"));

    // On a build older than the database table the alias resolves and the since check speaks.
    const old = await validateResource(bank, await context("2.31.13+op77.44"));
    assert.ok(old.some((f) => /MySQL.query.await \(Open77.database.query\) \(server\) needs 2.31.13\+op77.45/.test(f.message)), old.map((f) => f.message).join("\n"));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("open77_api takes client: as the mirror of server:", async () => {
  const ctx = await context();
  const both = ctx.index.cards.find((c) => c.runtime === "server" && ctx.index.cards.some((o) => o.runtime === "client" && o.qualified === c.qualified))!;
  const { ask, close } = await mcpClient(ctx);
  try {
    assert.match(await ask("open77_api", { name: `client:${both.qualified}` }), /^# client /);
    assert.doesNotMatch(await ask("open77_api", { name: `client:${both.qualified}` }), /\n# server /);
    assert.match(await ask("open77_api", { name: `server:${both.qualified}` }), /^# server /);
    assert.match(await ask("open77_api", { name: `CLIENT:${both.qualified}` }), /^# client /, "the prefix is case-insensitive");
    assert.match(await ask("open77_api", { name: `client:${both.qualified}`, runtime: "client" }), /^# client /);
    assert.match(await ask("open77_api", { name: `client:${both.qualified}`, runtime: "server" }), /names the client side but runtime=server/);
    assert.match(await ask("open77_api", { name: "client:NoSuchNative" }), /^No native named client:NoSuchNative/);
  } finally {
    await close();
  }
});

test("open77_api answers server:exports and server:print from the guides", async () => {
  const ctx = await context();
  const { ask, close } = await mcpClient(ctx);
  try {
    const exportsCard = await ask("open77_api", { name: "server:exports" });
    assert.match(exportsCard, /^# server exports\(name: string, fn: function\)/);
    assert.match(exportsCard, /server-exports#publish-a-service/);
    assert.match(exportsCard, /exports\('add', function\(playerId, points\)/, "the guide's worked example is inlined");
    const printCard = await ask("open77_api", { name: "server:print" });
    assert.match(printCard, /^# server print\(/);
    assert.match(printCard, /server-api#logging/);
    // The bare name renders the client card and the server pointer together.
    const bare = await ask("open77_api", { name: "exports" });
    assert.match(bare, /^# client exports\(/);
    assert.match(bare, /\n# server exports\(name: string, fn: function\)/);
    assert.doesNotMatch(await ask("open77_api", { name: "exports", runtime: "client" }), /\n# server exports/);
    // The listing says the two exist.
    const listing = await ask("open77_namespace", { namespace: "_G", runtime: "server" });
    assert.match(listing, /documented in the guides only.*server exports\(name: string, fn: function\).*server print\(/);
    assert.doesNotMatch(await ask("open77_namespace", { namespace: "_G", runtime: "client" }), /documented in the guides only/);
  } finally {
    await close();
  }
});

test("validate warns when a command name is already registered by a resource the server loads", async () => {
  const ctx = await context();
  const root = await mkdtemp(path.join(os.tmpdir(), "open77-cmd-"));
  try {
    const resources = path.join(root, "resources");
    const write = async (name: string, manifest: string, files: Record<string, string>) => {
      const dir = path.join(resources, name);
      await mkdir(dir, { recursive: true });
      await writeFile(path.join(dir, "open77.lua"), manifest, "utf8");
      for (const [file, body] of Object.entries(files)) {
        await mkdir(path.dirname(path.join(dir, file)), { recursive: true });
        await writeFile(path.join(dir, file), body, "utf8");
      }
      return dir;
    };
    await write("open77_medic", 'resource "open77_medic"\nserver_script "server.lua"\nclient_script "client.lua"\n', {
      "server.lua": 'RegisterCommand("heal", function(source) end, true)\n-- RegisterCommand("ghost", function() end)\nRegisterCommand(\'revive\', function(source) end, true)\n',
      "client.lua": 'Open77.runtime.registerCommand("radio", function() end)\n',
    });
    await write("shared_tools", 'resource "shared_tools"\nshared_script "shared/*.lua"\n', {
      "shared/cmds.lua": 'RegisterCommand("ping", function() end)\n',
    });
    const mine = await write("my_rp", 'resource "my_rp"\nserver_script "server/main.lua"\nclient_script "client/main.lua"\n', {
      "server/main.lua": 'RegisterCommand("heal", function(source) end)\nRegisterCommand("radio", function(source) end)\nRegisterCommand("ping", function(source) end)\nRegisterCommand("ghost", function(source) end)\nRegisterCommand("mine", function(source) end)\n',
      "client/main.lua": 'RegisterCommand("radio", function() end)\nRegisterCommand("revive", function() end)\n',
    });
    await writeFile(path.join(root, "server.jsonc"), '{ "resources": { "root": "./resources" } }', "utf8");

    const registered = await registeredCommands(path.join(resources, "open77_medic"), ctx.index.manifestSchema.directives);
    assert.deepEqual(registered.map((c) => `${c.side}:${c.name}@${c.file}:${c.line}`), ["client:radio@client.lua:1", "server:heal@server.lua:1", "server:revive@server.lua:3"], "commented-out registrations are skipped");

    // What open77_validate does: the workspace's resources become the loaded set.
    const workspace = await detectWorkspace(mine);
    assert.deepEqual(workspace.resources, ["my_rp", "open77_medic", "shared_tools"]);
    const loaded = (await Promise.all(workspace.resources.map((n) => findResourceDir(workspace, n)))).filter((d): d is string => d !== null);
    const findings = await validateResource(mine, ctx, { loadedResources: loaded });
    const warnings = findings.filter((f) => f.severity === "warning" && /already registered/.test(f.message)).map((f) => `${f.file}:${f.line} ${f.message}`);
    assert.deepEqual(warnings.sort(), [
      "client/main.lua:1 command /radio is already registered by open77_medic (client.lua:1, client side); the runtime keeps one handler and never says which",
      "server/main.lua:1 command /heal is already registered by open77_medic (server.lua:1, server side); the runtime keeps one handler and never says which",
      "server/main.lua:3 command /ping is already registered by shared_tools (shared/cmds.lua:1, shared side); the runtime keeps one handler and never says which",
    ].sort());
    assert.ok(!warnings.some((w) => /\/revive/.test(w)), "a client command next to another resource's server command is not a collision");
    assert.ok(!warnings.some((w) => /\/ghost|\/mine/.test(w)), "a commented-out or unique name is not a collision");
    assert.ok(!warnings.some((w) => /server\/main.lua:2/.test(w)), "the server /radio does not collide with a client /radio");
    assert.ok(findings.every((f) => !(f.severity === "error" && /already registered/.test(f.message))), "collisions are warnings, never errors");

    // Without a loaded set (no server next to the session) the check is silent.
    assert.deepEqual(await commandCollisions(mine, [], ctx.index.manifestSchema.directives), []);
    assert.ok(!(await validateResource(mine, ctx)).some((f) => /already registered/.test(f.message)));
    // The validated resource is never compared with itself.
    assert.deepEqual(await commandCollisions(mine, [mine], ctx.index.manifestSchema.directives), []);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
