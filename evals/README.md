# Evals

The quality gate of the Devkit MCP is not "the tools answer", it is "an agent with only the tools
ships a resource that works". `tasks.json` holds five tasks that cover what server owners actually
build: a taxi job, cuff and escort, a shop with a WebUI, a PvP round with routing buckets, and a
FiveM port. Each task has a prompt, a **static** gate and an **in-game** gate.

## Running the static gate

Give an agent one task's prompt with nothing but this MCP attached, and let it write the resource
into a directory. Then:

```bash
node evals/run-static.mjs <resources-dir> [--build 2.31.13+op77.69]
```

The gate runs the MCP's validator on every resource (manifest, scripts, unknown natives, wrong
runtime side, undeclared permissions, natives newer than the build) and the task's own checks:
natives or namespaces that must appear, FiveM names that must not, permissions the manifest must
declare. Exit code 1 when any task fails.

## Running the in-game gate

On the Open77 workstation, with the autonomous test loop (`open77-base/docs/agent-autonomous-testing.md`):
copy the resources into the dev server's resource root, `open77_stack_up`, `open77_client_connect`,
then follow each task's `ingame.steps` and record the `proof`. A task passes only when its proof
is observed in the running game; validating and reloading is not passing.

## Reading the result

The release checklist carries two numbers per index publish: static gates passed (from CI) and
in-game gates passed (from the workstation run). A drop in either blocks the release the way the
API audit blocks the wiki.
