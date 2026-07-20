#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUTPUT_NAME="app-store-package-contract-$$"
DIST_DIR="$ROOT_DIR/dist/$OUTPUT_NAME"
APP_PATH="$DIST_DIR/Codebase Combiner.app"
NOTICE_PATH="$APP_PATH/Contents/Resources/NOTICE"

cleanup() {
  rm -rf "$DIST_DIR"
}
trap cleanup EXIT

APPSTORE_OUTPUT_NAME="$OUTPUT_NAME" \
  "$ROOT_DIR/Packaging/AppStore/build_app_store_package.sh" --skip-signing

cmp -s "$ROOT_DIR/LICENSE" "$APP_PATH/Contents/Resources/LICENSE"
cmp -s "$ROOT_DIR/NOTICE" "$NOTICE_PATH"

python3 - "$DIST_DIR/release-manifest.json" "$NOTICE_PATH" <<'PY'
import hashlib
import json
import sys

manifest_path, notice_path = sys.argv[1:]
with open(notice_path, "rb") as handle:
    expected = hashlib.sha256(handle.read()).hexdigest()
with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)
actual = manifest["artifacts"]["noticeSHA256"]
if actual != expected:
    raise SystemExit(f"NOTICE manifest hash mismatch: expected {expected}, got {actual}")
PY

grep -F 'Codebase Combiner.app/Contents/Resources/NOTICE' "$DIST_DIR/SHA256SUMS" >/dev/null
(
  cd "$DIST_DIR"
  shasum -a 256 -c SHA256SUMS >/dev/null
)

printf '\ncontract tamper\n' >> "$NOTICE_PATH"
if (cd "$DIST_DIR" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1); then
  echo "Tampered bundled NOTICE unexpectedly passed SHA256SUMS verification." >&2
  exit 1
fi

echo "App Store package NOTICE/manifest/checksum contract passed"
