#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodebaseExplorerApp"
APP_BUNDLE="$ROOT_DIR/dist/app-store/Codebase Combiner.app"
E2E_DEFAULTS_SUITE="com.s1korrrr.codebasecombiner.e2e"
E2E_BUNDLE_ID="com.s1korrrr.codebasecombiner.e2ehost"
E2E_FIXTURE="$ROOT_DIR/script/fixtures/e2e-workspace"

cd "$ROOT_DIR"

running_app_pids() {
  pgrep -x "$APP_NAME" 2>/dev/null || true
}

stop_existing_app() {
  local pid
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "$pid" 2>/dev/null || true
  done < <(running_app_pids)

  for _ in {1..20}; do
    [[ -z "$(running_app_pids)" ]] && return 0
    sleep 0.1
  done

  echo "Existing $APP_NAME process did not exit cleanly." >&2
  return 1
}

is_pid_in_list() {
  local candidate="$1"
  local list="$2"
  [[ " $list " == *" $candidate "* ]]
}

wait_for_new_app_pid() {
  local before_pids="$1"
  local pid
  for _ in {1..40}; do
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      if ! is_pid_in_list "$pid" "$before_pids"; then
        echo "$pid"
        return 0
      fi
    done < <(running_app_pids)
    sleep 0.25
  done
  return 1
}

if [[ "$MODE" != "--e2e" && "$MODE" != "e2e" ]]; then
  stop_existing_app
fi

Packaging/AppStore/build_app_store_package.sh --skip-signing >/tmp/codebase-combiner-build.log

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      if pgrep -x "$APP_NAME" >/dev/null; then
        echo "Verified $APP_NAME launched from $APP_BUNDLE"
        exit 0
      fi
      sleep 0.25
    done
    echo "App did not launch. Build log: /tmp/codebase-combiner-build.log" >&2
    exit 1
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --e2e|e2e)
    if [[ ! -d "$E2E_FIXTURE" ]]; then
      echo "E2E fixture is missing: $E2E_FIXTURE" >&2
      exit 1
    fi

    if [[ -n "${CODEBASE_COMBINER_E2E_DATA_DIR:-}" ]]; then
      E2E_DATA_DIR="$CODEBASE_COMBINER_E2E_DATA_DIR"
      mkdir -p "$E2E_DATA_DIR"
    else
      E2E_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codebase-combiner-e2e.XXXXXX")"
      /usr/bin/defaults delete "$E2E_DEFAULTS_SUITE" >/dev/null 2>&1 || true
      /usr/bin/defaults delete "$E2E_BUNDLE_ID" >/dev/null 2>&1 || true
    fi
    E2E_WINDOW_SIZE="${CODEBASE_COMBINER_E2E_WINDOW_SIZE:-960x640}"

    E2E_APP_BUNDLE="$E2E_DATA_DIR/Codebase Combiner E2E.app"
    rm -rf "$E2E_APP_BUNDLE"
    cp -R "$APP_BUNDLE" "$E2E_APP_BUNDLE"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $E2E_BUNDLE_ID" \
      "$E2E_APP_BUNDLE/Contents/Info.plist"
    codesign --force --deep --sign - "$E2E_APP_BUNDLE" >/dev/null

    BEFORE_PIDS="$(running_app_pids | tr '\n' ' ')"
    /usr/bin/open -n -F \
      --env "CODEBASE_COMBINER_E2E_DATA_DIR=$E2E_DATA_DIR" \
      --env "CODEBASE_COMBINER_E2E_WINDOW_SIZE=$E2E_WINDOW_SIZE" \
      --stdout "$E2E_DATA_DIR/stdout.log" \
      --stderr "$E2E_DATA_DIR/stderr.log" \
      "$E2E_APP_BUNDLE"

    if ! E2E_PID="$(wait_for_new_app_pid "$BEFORE_PIDS")"; then
      echo "E2E app did not launch. Build log: /tmp/codebase-combiner-build.log" >&2
      exit 1
    fi

    printf '%s\n' "$E2E_PID" > "$E2E_DATA_DIR/app.pid"
    sleep 1
    kill -0 "$E2E_PID"
    echo "Verified isolated E2E app launch"
    echo "E2E_PID=$E2E_PID"
    echo "E2E_DATA_DIR=$E2E_DATA_DIR"
    echo "E2E_FIXTURE=$E2E_FIXTURE"
    echo "E2E_WINDOW_SIZE=$E2E_WINDOW_SIZE"
    echo "Stop only this audit process with: kill $E2E_PID"
    ;;
  *)
    echo "usage: $0 [run|--verify|--logs|--e2e]" >&2
    exit 2
    ;;
esac
