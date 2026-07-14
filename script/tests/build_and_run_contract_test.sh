#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/script/build_and_run.sh"

bash -n "$SCRIPT"

if rg -n '(^|[^[:alnum:]_])(pgrep|pkill)([^[:alnum:]_]|$)|/usr/bin/open' "$SCRIPT"; then
  echo "build_and_run.sh must not discover or terminate apps by process name or LaunchServices." >&2
  exit 1
fi

rg -F 'OWNED_PID=$!' "$SCRIPT" >/dev/null
rg -F 'ps -ww -p "$pid" -o command=' "$SCRIPT" >/dev/null
rg -F 'wait "$pid"' "$SCRIPT" >/dev/null
rg -F -- '--bundle-id "$E2E_BUNDLE_ID"' "$SCRIPT" >/dev/null
rg -F "Print :com.apple.security.app-sandbox" "$SCRIPT" >/dev/null
rg -F "Print :com.apple.security.files.user-selected.read-write" "$SCRIPT" >/dev/null
rg -F 'E2E_FIXTURE="/private/tmp/CodebaseCombinerE2EFixture"' "$SCRIPT" >/dev/null
rg -F 'rm -rf "$E2E_CONTAINER/Data"' "$SCRIPT" >/dev/null
if rg -F 'rm -rf "$E2E_CONTAINER"' "$SCRIPT"; then
  echo "E2E cleanup must preserve the OS-owned container metadata shell." >&2
  exit 1
fi

echo "build_and_run process, sandbox, and fixture contracts passed"
