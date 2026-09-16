#!/usr/bin/env node
/**
 * `open77-mcp` command line.
 *
 *   open77-mcp                       serve the MCP over stdio (what agents launch)
 *   open77-mcp serve-http [--port]   serve the MCP over Streamable HTTP (the hosted endpoint)
 *   open77-mcp init [--server-dir]   register the server in every detected agent client
 *   open77-mcp uninstall             remove those registrations
 *   open77-mcp build-index           build a Dev Index from open77-app/content
 *   open77-mcp verify-index          check an index directory against its manifest
 *   open77-mcp types [--out]         write the Lua language-server stubs for the current build
 *   open77-mcp status                which index, build and server this package would answer for
 *   open77-mcp warden-login          sign in to Warden for the live-server tools
 */

import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { buildIndex } from "./index/builder.js";
import { verifyIndex } from "./index/loader.js";

export const PACKAGE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const EMBEDDED_INDEX = path.join(PACKAGE_ROOT, "index");

interface Args {
  command: string;
  flags: Record<string, string | boolean>;
  rest: string[];
}

export function parseArgs(argv: string[]): Args {
  const flags: Record<string, string | boolean> = {};
  const rest: string[] = [];
  let command = "";
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]!;
    if (arg.startsWith("--")) {
      const [key, inline] = arg.slice(2).split("=", 2);
      if (inline !== undefined) flags[key!] = inline;
      else if (i + 1 < argv.length && !argv[i + 1]!.startsWith("--")) flags[key!] = argv[++i]!;
      else flags[key!] = true;
    } else if (!command) command = arg;
    else rest.push(arg);
  }
  return { command, flags, rest };
}

function flag(args: Args, name: string, fallback?: string): string | undefined {
  const value = args.flags[name];
  return typeof value === "string" ? value : fallback;
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const log = (line: string) => process.stderr.write(line + "\n");
  switch (args.command) {
    case "build-index": {
      const contentDir = flag(args, "content");
      if (!contentDir) throw new Error("build-index requires --content <open77-app/content>");
      const outDir = flag(args, "out", EMBEDDED_INDEX)!;
      const manifest = await buildIndex({
        contentDir: path.resolve(contentDir),
        outDir: path.resolve(outDir),
        build: flag(args, "build"),
        sourceCommit: flag(args, "commit"),
        log,
      });
      process.stdout.write(JSON.stringify({ build: manifest.build, counts: manifest.counts, out: path.resolve(outDir) }, null, 1) + "\n");
      return;
    }
    case "verify-index": {
      const dir = path.resolve(flag(args, "dir", EMBEDDED_INDEX)!);
      const result = await verifyIndex(dir);
      process.stdout.write(`${result.files} files verified in ${dir}` + (result.extra.length ? `; unlisted: ${result.extra.join(", ")}` : "") + "\n");
      if (result.extra.length) process.exitCode = 1;
      return;
    }
    case "serve-http":
    case "init":
    case "uninstall":
    case "types":
    case "status":
    case "warden-login":
    case "": {
      const { runCommand } = await import("./commands.js");
      await runCommand(args.command, args.flags, args.rest);
      return;
    }
    case "help":
    case "--help":
      process.stdout.write(usage());
      return;
    default:
      throw new Error(`unknown command ${args.command}\n${usage()}`);
  }
}

export function usage(): string {
  return [
    "open77-mcp                       serve the Open77 Devkit MCP over stdio",
    "open77-mcp serve-http [--port N] serve over Streamable HTTP (hosted endpoint)",
    "open77-mcp init [--server-dir D] register the MCP in Claude Code, Codex, Cursor, VS Code, Claude Desktop, Windsurf",
    "open77-mcp uninstall             remove those registrations",
    "open77-mcp types [--out DIR]     write open77-client.d.lua / open77-server.d.lua and a .luarc.json",
    "open77-mcp status                index build, detected server build, cache state",
    "open77-mcp warden-login          sign in to the server's Warden console (asks in the terminal; keeps only the session cookie)",
    "open77-mcp build-index --content <open77-app/content> [--out DIR] [--build B]",
    "open77-mcp verify-index [--dir DIR]",
    "",
  ].join("\n");
}

main().catch((error: Error) => {
  process.stderr.write(`open77-mcp: ${error.message}\n`);
  process.exitCode = 1;
});
