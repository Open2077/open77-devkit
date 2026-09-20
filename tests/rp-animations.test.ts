import assert from "node:assert/strict";
import path from "node:path";
import { test } from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { loadIndex } from "../src/index/loader.js";
import { createMcpServer } from "../src/server.js";

test("MCP distinguishes walking RP actions, native items and discovery-only clips", async () => {
  const directory = path.resolve(process.env.OPEN77_INDEX_DIR ?? "index");
  const index = await loadIndex(directory);
  const server = createMcpServer({ index, resolved: { directory, build: index.manifest.build, origin: "embedded" }, packageVersion: "test", skillPath: path.resolve("skill/SKILL.md") });
  const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
  await server.connect(serverSide);
  const client = new Client({ name: "rp-test", version: "0" });
  await client.connect(clientSide);
  try {
    const ask = async (name: string, args: Record<string, unknown>) => {
      const result = await client.callTool({ name, arguments: args });
      return (result.content as { text?: string }[]).map((c) => c.text ?? "").join("\n");
    };
    const play = await ask("open77_api", { name: "server:Open77.animations.play" });
    assert.match(play, /permissions: players\.animations\.control/);
    assert.match(play, /item=false/);
    assert.match(play, /world\.props/);
    assert.doesNotMatch(play, /Options are clip, durationMs and loop only/);
    assert.match(play, /first build supporting every option/);
    const chain = await ask("open77_guide", { slug: "rp-animations#hold-drink-then-hold-again" });
    assert.match(chain, /setDrinkAction/);
    assert.match(chain, /Open77\.animations\.sequence/);
    assert.match(chain, /same prop ID/);
    for (const catalogue of ["animations", "animsets"]) {
      for (const query of [undefined, "smoke"]) {
        const data = await ask("open77_data", { catalogue, ...(query ? { query } : {}), limit: 2 });
        assert.match(data, /Discovery inventory, not a playback allowlist/);
        assert.match(data, /unknown_clip/);
        assert.match(data, /https:\/\/open2077\.net\/data\/rp-workspots\.json/);
      }
    }
    const search = await ask("open77_search", { query: "hold drink then hold", kind: "guide" });
    assert.match(search, /rp-animations#hold-drink-then-hold-again/);
  } finally {
    await client.close();
    await server.close();
  }
});
