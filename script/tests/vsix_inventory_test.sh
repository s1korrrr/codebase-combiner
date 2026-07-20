#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VSIX_PATH="${1:-}"
EXPECTED_NAME="$(node -p 'require(process.argv[1]).name' "$ROOT_DIR/package.json")"
EXPECTED_VERSION="$(node -p 'require(process.argv[1]).version' "$ROOT_DIR/package.json")"
EXPECTED_PUBLISHER="$(node -p 'require(process.argv[1]).publisher' "$ROOT_DIR/package.json")"
EXPECTED_PATH="$ROOT_DIR/$EXPECTED_NAME-$EXPECTED_VERSION.vsix"

if [[ -z "$VSIX_PATH" ]]; then
  unexpected_candidates="$(find "$ROOT_DIR" -maxdepth 1 -type f -name '*.vsix' ! -path "$EXPECTED_PATH" -print)"
  [[ -f "$EXPECTED_PATH" && -z "$unexpected_candidates" ]] || {
    echo "Expected exactly one current VSIX artifact: $EXPECTED_PATH" >&2
    exit 1
  }
  VSIX_PATH="$EXPECTED_PATH"
fi
[[ -n "$VSIX_PATH" && -f "$VSIX_PATH" ]] || { echo "VSIX artifact not found." >&2; exit 1; }
[[ "$(cd "$(dirname "$VSIX_PATH")" && pwd)/$(basename "$VSIX_PATH")" == "$EXPECTED_PATH" ]] || {
  echo "VSIX path does not match package name/version: $VSIX_PATH" >&2
  exit 1
}

listing="$(unzip -Z1 "$VSIX_PATH")"
for required in \
  extension/package.json \
  extension/extension.js \
  extension/lib/combiner.js \
  extension/LICENSE.txt \
  extension/NOTICE \
  extension/node_modules/minimatch/LICENSE \
  extension/node_modules/brace-expansion/LICENSE \
  extension/node_modules/balanced-match/LICENSE.md; do
  grep -Fx "$required" <<< "$listing" >/dev/null || { echo "VSIX is missing required file: $required" >&2; exit 1; }
done

if grep -E '(^|/)(\.git|\.github|\.worktrees|\.tap|test|tests|coverage)(/|$)|(^|/)eslint[.]config[.]cjs$|\.(p12|p8|key|pem|dmg|pkg|map|d\.ts)$' <<< "$listing"; then
  echo "VSIX contains repository, test, secret, release, source-map, or declaration files." >&2
  exit 1
fi

embedded_manifest="$(unzip -p "$VSIX_PATH" extension/package.json)"
embedded_name="$(node -e 'const fs=require("fs"); process.stdout.write(JSON.parse(fs.readFileSync(0,"utf8")).name)' <<< "$embedded_manifest")"
embedded_version="$(node -e 'const fs=require("fs"); process.stdout.write(JSON.parse(fs.readFileSync(0,"utf8")).version)' <<< "$embedded_manifest")"
embedded_publisher="$(node -e 'const fs=require("fs"); process.stdout.write(JSON.parse(fs.readFileSync(0,"utf8")).publisher)' <<< "$embedded_manifest")"
[[ "$embedded_name" == "$EXPECTED_NAME" && "$embedded_version" == "$EXPECTED_VERSION" && "$embedded_publisher" == "$EXPECTED_PUBLISHER" ]] || {
  echo "VSIX embedded package identity does not match package.json." >&2
  exit 1
}

echo "VSIX inventory contract passed: $VSIX_PATH"
