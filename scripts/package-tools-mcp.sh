#!/usr/bin/env bash
# Builds the `tools/mcp/` folder the Open77 server archive ships: the built
# package, its embedded index, the skill, production dependencies, and two
# install scripts that register the bundled copy in the agent clients found on
# the box. Node 20+ is still required on the host; what this removes is the
# need for npm registry access (an offline or firewalled server box).
#
#   scripts/package-tools-mcp.sh <output-dir>      e.g. ../release/tools/mcp
set -euo pipefail

OUT=${1:?output dir}
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

npm ci --no-audit --no-fund >/dev/null
npm run build >/dev/null
node dist/cli.js verify-index --dir index >/dev/null

rm -rf "$OUT"
mkdir -p "$OUT"
cp -r dist index skill package.json README.md LICENSE "$OUT/"
# Production dependencies only, pruned in a scratch copy so the checkout keeps its dev tools.
SCRATCH=$(mktemp -d)
cp package.json package-lock.json "$SCRATCH/"
(cd "$SCRATCH" && npm ci --omit=dev --no-audit --no-fund >/dev/null)
cp -r "$SCRATCH/node_modules" "$OUT/node_modules"
rm -rf "$SCRATCH"

cat > "$OUT/install.sh" <<'EOF'
#!/usr/bin/env bash
# Registers the bundled Open77 Devkit MCP in every agent client on this machine.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
command -v node >/dev/null || { echo "Node 20 or newer is required (https://nodejs.org)"; exit 1; }
node "$HERE/dist/cli.js" init --dev --server-dir "${1:-$(cd "$HERE/../.." && pwd)}"
EOF
chmod +x "$OUT/install.sh"

cat > "$OUT/install.ps1" <<'EOF'
#requires -Version 5.1
# Registers the bundled Open77 Devkit MCP in every agent client on this machine.
param([string]$ServerDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node 20 or newer is required (https://nodejs.org)' }
& node (Join-Path $PSScriptRoot 'dist\cli.js') init --dev --server-dir $ServerDir
EOF

VERSION=$(node -p 'require("./package.json").version')
BUILD=$(node -p 'JSON.parse(require("fs").readFileSync("index/manifest.json","utf8")).build')
printf '{"package":"@open2077/mcp","version":"%s","indexBuild":"%s","packagedAt":"%s"}\n' "$VERSION" "$BUILD" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT/tools-mcp.json"
echo "tools/mcp bundle: @open2077/mcp $VERSION with index $BUILD -> $OUT ($(du -sh "$OUT" | cut -f1))"
