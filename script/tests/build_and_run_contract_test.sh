#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/script/build_and_run.sh"

bash -n "$SCRIPT"

if grep -En '(^|[^[:alnum:]_])(pgrep|pkill)([^[:alnum:]_]|$)|/usr/bin/open' "$SCRIPT"; then
  echo "build_and_run.sh must not discover or terminate apps by process name or LaunchServices." >&2
  exit 1
fi

grep -F 'OWNED_PID=$!' "$SCRIPT" >/dev/null
grep -F 'ps -ww -p "$pid" -o command=' "$SCRIPT" >/dev/null
grep -F 'running_e2e_processes' "$SCRIPT" >/dev/null
grep -F 'ps -axo pid=' "$SCRIPT" >/dev/null
grep -F 'Refusing to reset E2E state while another E2E host is running.' "$SCRIPT" >/dev/null
grep -F 'wait "$pid"' "$SCRIPT" >/dev/null
grep -F -- '--bundle-id "$E2E_BUNDLE_ID"' "$SCRIPT" >/dev/null
grep -F 'E2E_DIST_DIR="$ROOT_DIR/dist/app-store-e2e"' "$SCRIPT" >/dev/null
grep -F 'LEGACY_E2E_APP_BUNDLE="$ROOT_DIR/dist/app-store/$E2E_APP_NAME.app"' "$SCRIPT" >/dev/null
grep -F 'E2E_SESSION_LOCK="/private/tmp/CodebaseCombinerE2ESession.lock"' "$SCRIPT" >/dev/null
grep -F 'acquire_e2e_session_lock' "$SCRIPT" >/dev/null
grep -F 'Another E2E build, run, or cleanup operation is already active.' "$SCRIPT" >/dev/null
grep -F 'APPSTORE_OUTPUT_NAME=app-store-e2e' "$SCRIPT" >/dev/null
grep -F "Print :com.apple.security.app-sandbox" "$SCRIPT" >/dev/null
grep -F "Print :com.apple.security.files.user-selected.read-write" "$SCRIPT" >/dev/null
grep -F 'E2E_FIXTURE="/private/tmp/CodebaseCombinerE2EFixture"' "$SCRIPT" >/dev/null
grep -F 'E2E_EXPORT="/private/tmp/CodebaseCombinerE2EExport"' "$SCRIPT" >/dev/null
grep -F 'rm -rf "$E2E_CONTAINER/Data"' "$SCRIPT" >/dev/null
grep -F 'rm -rf "$E2E_RUNTIME_DIR" "$E2E_FIXTURE" "$E2E_EXPORT"' "$SCRIPT" >/dev/null
grep -F 'rm -rf "$E2E_DIST_DIR"' "$SCRIPT" >/dev/null
grep -F 'rm -rf "$LEGACY_E2E_APP_BUNDLE"' "$SCRIPT" >/dev/null
grep -F 'rm -f "$LEGACY_E2E_SUMMARY"' "$SCRIPT" >/dev/null
if grep -F 'rm -rf "$E2E_CONTAINER"' "$SCRIPT"; then
  echo "E2E cleanup must preserve the OS-owned container metadata shell." >&2
  exit 1
fi

echo "build_and_run process, sandbox, fixture, and export contracts passed"
