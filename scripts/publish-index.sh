#!/usr/bin/env bash
# Publishes an index directory to the CDN as dev-index/<build>/ and updates
# dev-index/latest.json. The directory is uploaded as one tarball, unpacked
# next to its final place and moved into it, so a reader never sees a
# half-written build. latest.json lists every build the CDN carries, newest
# first, so a client can pick the newest at or below its server build.
#
#   publish-index.sh <index-dir> <build> <user@host> [identity-file] [cdn-root]
set -euo pipefail

INDEX_DIR=${1:?index dir}
BUILD=${2:?build}
TARGET=${3:?user@host}
IDENTITY=${4:-}
CDN_ROOT=${5:-/opt/op77-cdn}
REMOTE="$CDN_ROOT/dev-index"

SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
[ -n "$IDENTITY" ] && SSH+=(-i "$IDENTITY")

test -f "$INDEX_DIR/manifest.json" || { echo "no manifest.json in $INDEX_DIR"; exit 1; }
MANIFEST_SHA=$(sha256sum "$INDEX_DIR/manifest.json" | cut -d' ' -f1)
STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "uploading $INDEX_DIR as $REMOTE/$BUILD"
tar -C "$INDEX_DIR" -czf - . | "${SSH[@]}" "$TARGET" "set -e; mkdir -p '$REMOTE'; rm -rf '$REMOTE/$BUILD.tmp'; mkdir -p '$REMOTE/$BUILD.tmp'; tar -C '$REMOTE/$BUILD.tmp' -xzf -; rm -rf '$REMOTE/$BUILD'; mv '$REMOTE/$BUILD.tmp' '$REMOTE/$BUILD'"

# The build list, newest op77 number first, written by the remote side from
# what is actually there.
"${SSH[@]}" "$TARGET" "cd '$REMOTE' && ls -1d */ | sed 's#/##' | grep '+op77\.' | sort -t. -k4 -n -r | tr '\n' ' '" > builds.txt
BUILDS=$(python3 - "$BUILD" "$MANIFEST_SHA" "$STAMP" <<'PY'
import json, sys
builds = open("builds.txt").read().split()
builds.sort(key=lambda b: int(b.split("+op77.")[1]), reverse=True)
print(json.dumps({"build": sys.argv[1], "manifestSha256": sys.argv[2], "publishedAt": sys.argv[3], "builds": builds}, separators=(",", ":")))
PY
)
rm -f builds.txt
echo "$BUILDS" | "${SSH[@]}" "$TARGET" "cat > '$REMOTE/latest.json.tmp' && mv '$REMOTE/latest.json.tmp' '$REMOTE/latest.json'"
echo "published: $BUILDS"

# Verify by reading back through the CDN, not through ssh.
if command -v curl >/dev/null; then
  HOST_URL=${OPEN77_CDN_BASE:-https://cdn.open2077.net}
  REMOTE_SHA=$(curl -fsS "$HOST_URL/dev-index/$BUILD/manifest.json" | sha256sum | cut -d' ' -f1)
  if [ "$REMOTE_SHA" != "$MANIFEST_SHA" ]; then echo "manifest read back from the CDN does not match"; exit 1; fi
  echo "verified $HOST_URL/dev-index/$BUILD/manifest.json"
fi
