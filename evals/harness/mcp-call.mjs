// Calls one Open77 Devkit MCP tool through the published package, the way an agent's MCP client does.
//   node mcp-call.mjs <serverDir> list
//   node mcp-call.mjs <serverDir> <tool> '<json args>'        (or @path/to/args.json)
import { pathToFileURL } from "node:url";
import { readFileSync } from "node:fs";
const sdk = "C:/Games/cyberm/devkit/node_modules/@modelcontextprotocol/sdk/dist/esm/client/";
const { Client } = await import(pathToFileURL(sdk + "index.js").href);
const { StdioClientTransport } = await import(pathToFileURL(sdk + "stdio.js").href);
const [serverDir, tool, rawArgs] = process.argv.slice(2);
if (!serverDir || !tool) { console.error("usage: mcp-call.mjs <serverDir> list | <tool> '<json>' | <tool> @file.json"); process.exit(2); }
const transport = new StdioClientTransport({ command: "npx", args: ["-y", "@open2077/mcp@0.1.0"], cwd: serverDir, stderr: "pipe" });
const client = new Client({ name: "devkit-eval2", version: "0" });
await client.connect(transport);
try {
  if (tool === "list") {
    for (const t of (await client.listTools()).tools) console.log(`${t.name}: ${t.description.split("\n")[0]}`);
  } else {
    const args = !rawArgs ? {} : rawArgs.startsWith("@") ? JSON.parse(readFileSync(rawArgs.slice(1), "utf8")) : JSON.parse(rawArgs);
    const result = await client.callTool({ name: tool, arguments: args });
    console.log(result.content.map((c) => c.text ?? JSON.stringify(c)).join("\n"));
    if (result.isError) process.exitCode = 1;
  }
} finally { await client.close(); }
