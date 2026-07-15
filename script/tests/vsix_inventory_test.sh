#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VSIX_PATH="${1:-}"

if [[ -z "$VSIX_PATH" ]]; then
  VSIX_PATH="$(find "$ROOT_DIR" -maxdepth 1 -type f -name '*.vsix' -print | sort | tail -n 1)"
fi
[[ -n "$VSIX_PATH" && -f "$VSIX_PATH" ]] || { echo "VSIX artifact not found." >&2; exit 1; }

listing="$(unzip -Z1 "$VSIX_PATH")"
for required in \
  extension/package.json \
  extension/extension.js \
  extension/lib/combiner.js \
  extension/LICENSE.txt \
  extension/node_modules/minimatch/LICENSE \
  extension/node_modules/brace-expansion/LICENSE \
  extension/node_modules/balanced-match/LICENSE.md; do
  grep -Fx "$required" <<< "$listing" >/dev/null || { echo "VSIX is missing required file: $required" >&2; exit 1; }
done

if grep -E '(^|/)(\.git|\.github|\.tap|test|tests|coverage)(/|$)|\.(p12|p8|key|pem|dmg|pkg|map|d\.ts)$' <<< "$listing"; then
  echo "VSIX contains repository, test, secret, release, source-map, or declaration files." >&2
  exit 1
fi

echo "VSIX inventory contract passed: $VSIX_PATH"
