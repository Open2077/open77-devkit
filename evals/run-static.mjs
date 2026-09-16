#!/usr/bin/env node
/**
 * Static gate of the eval suite: for each task in tasks.json, find the
 * resource an agent produced under <resources-dir>/<resource> and check it
 * with the same validator the MCP exposes, plus the task's own requirements
 * (natives or namespaces that must be used, names that must not appear).
 *
 *   node evals/run-static.mjs <resources-dir> [--build 2.31.13+op77.69]
 *
 * Prints one line per task and exits 1 when any task fails. The in-game gate
 * is a separate step on the workstation (see README.md).
 */

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { loadIndex } from "../dist/index/loader.js";
import { validateResource } from "../dist/workspace/validate.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const tasks = JSON.parse(await readFile(path.join(here, "tasks.json"), "utf8"));
const [resourcesDir, ...rest] = process.argv.slice(2);
if (!resourcesDir) {
  console.error("usage: node evals/run-static.mjs <resources-dir> [--build B]");
  process.exit(2);
}
const buildFlag = rest.indexOf("--build");
const build = buildFlag >= 0 ? rest[buildFlag + 1] : tasks.build;
const index = await loadIndex(process.env.OPEN77_INDEX_DIR ?? path.join(here, "..", "index"));
const context = { index, resolved: { directory: index.directory, build, origin: "embedded" }, packageVersion: "eval", skillPath: path.join(here, "..", "skill", "SKILL.md") };

const resourceName = (task) => `eval_${task.id.replace(/-.*$/, "")}`;
let failed = 0;
for (const task of tasks.tasks) {
  const name = task.resourceName ?? resourceName(task);
  const dir = path.join(resourcesDir, name);
  let files;
  try {
    files = await readdir(dir, { recursive: true });
  } catch {
    console.log(`MISSING  ${task.id}: no resource ${name} under ${resourcesDir}`);
    failed += 1;
    continue;
  }
  const findings = await validateResource(dir, context);
  const errors = findings.filter((f) => f.severity === "error");
  const problems = [];
  if (errors.length > (task.static.maxErrors ?? 0)) problems.push(`${errors.length} validation errors: ${errors.slice(0, 3).map((e) => e.message).join(" | ")}`);
  const sources = (await Promise.all(files.filter((f) => String(f).endsWith(".lua")).map((f) => readFile(path.join(dir, String(f)), "utf8")))).join("\n");
  for (const native of task.static.requiredNatives ?? []) if (!sources.includes(native)) problems.push(`does not use ${native}`);
  for (const ns of task.static.requiredNamespaces ?? []) if (!sources.includes(`${ns}.`) && !sources.includes(`${ns}:`)) problems.push(`does not use ${ns}`);
  for (const name2 of task.static.forbidden ?? []) {
    const [token] = name2.split(" in ");
    if (sources.includes(token)) problems.push(`uses forbidden ${token}`);
  }
  for (const permission of task.static.requiredPermissions ?? []) if (!sources.includes(`"${permission}"`) && !sources.includes(`'${permission}'`)) problems.push(`manifest lacks ${permission}`);
  if (problems.length) {
    failed += 1;
    console.log(`FAIL     ${task.id} (${name}): ${problems.join("; ")}`);
  } else {
    console.log(`PASS     ${task.id} (${name}): ${findings.filter((f) => f.severity === "warning").length} warnings`);
  }
}
console.log(`${tasks.tasks.length - failed}/${tasks.tasks.length} static gates passed for build ${build}`);
process.exit(failed ? 1 : 0);
