#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_LOG="/private/tmp/codebase-combiner-build.log"
APP_NAME="Codebase Combiner"
APP_BUNDLE="$ROOT_DIR/dist/app-store/$APP_NAME.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/CodebaseExplorerApp"
APP_ENTITLEMENTS="$ROOT_DIR/Packaging/AppStore/AppStore.entitlements"
E2E_APP_NAME="Codebase Combiner E2E"
E2E_BUNDLE_ID="com.s1korrrr.codebasecombiner.e2ehost"
E2E_APP_BUNDLE="$ROOT_DIR/dist/app-store/$E2E_APP_NAME.app"
E2E_EXECUTABLE="$E2E_APP_BUNDLE/Contents/MacOS/CodebaseExplorerApp"
E2E_CONTAINER="$HOME/Library/Containers/$E2E_BUNDLE_ID"
E2E_PREFERENCES="$HOME/Library/Preferences/$E2E_BUNDLE_ID.plist"
E2E_RUNTIME_DIR="/private/tmp/CodebaseCombinerE2ERuntime"
E2E_FIXTURE_SOURCE="$ROOT_DIR/script/fixtures/e2e-workspace"
E2E_FIXTURE="/private/tmp/CodebaseCombinerE2EFixture"
E2E_EXPORT="/private/tmp/CodebaseCombinerE2EExport"
E2E_PID_FILE="$E2E_RUNTIME_DIR/app.pid"
OWNED_PID=""
OWNED_EXECUTABLE=""

cd "$ROOT_DIR"

usage() {
  cat <<USAGE
usage: $0 [run|--verify|--logs|--e2e|--clean-e2e-state]

  run                 Build and launch the production bundle; print its owned PID.
  --verify            Build, launch, verify, terminate, and reap one exact production PID.
  --logs              Build and launch one exact production PID; stream only its logs until interrupted.
  --e2e               Build and run the sandboxed E2E host in this foreground wrapper.
                      Press Ctrl-C to terminate and reap only the printed E2E PID.
  --clean-e2e-state   Remove E2E app-owned container data, preferences, runtime files, fixture, and export.

Set CODEBASE_COMBINER_E2E_RESET=0 to preserve the E2E container for a recovery relaunch.
Set CODEBASE_COMBINER_E2E_WINDOW_SIZE=960x640 (or another WxH) for deterministic UI proof.
USAGE
}

process_command() {
  local pid="$1"
  ps -ww -p "$pid" -o command= 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

verify_owned_process() {
  local pid="$1"
  local expected_executable="$2"
  local command=""

  for _ in {1..40}; do
    command="$(process_command "$pid")"
    if [[ "$command" == "$expected_executable" ]]; then
      sleep 1
      command="$(process_command "$pid")"
      [[ "$command" == "$expected_executable" ]] && return 0
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 0.25
  done

  echo "Owned process verification failed for PID $pid." >&2
  echo "Expected exact command: $expected_executable" >&2
  echo "Observed command: ${command:-<exited>}" >&2
  return 1
}

terminate_and_reap_owned_process() {
  local pid="$1"
  local expected_executable="$2"
  local command

  if kill -0 "$pid" 2>/dev/null; then
    command="$(process_command "$pid")"
    if [[ "$command" != "$expected_executable" ]]; then
      echo "Refusing to terminate PID $pid because its command is not the owned executable." >&2
      echo "Expected: $expected_executable" >&2
      echo "Observed: ${command:-<unknown>}" >&2
      return 1
    fi
    kill "$pid"
  fi

  wait "$pid" 2>/dev/null || true
}

cleanup_owned_process() {
  local status=$?
  trap - EXIT INT TERM
  if [[ -n "$OWNED_PID" && -n "$OWNED_EXECUTABLE" ]]; then
    terminate_and_reap_owned_process "$OWNED_PID" "$OWNED_EXECUTABLE" || status=1
  fi
  if [[ "$MODE" == "--e2e" || "$MODE" == "e2e" ]]; then
    rm -f "$E2E_PID_FILE"
  fi
  exit "$status"
}

launch_owned_process() {
  local executable="$1"
  local stdout_log="$2"
  local stderr_log="$3"

  "$executable" >"$stdout_log" 2>"$stderr_log" &
  OWNED_PID=$!
  OWNED_EXECUTABLE="$executable"
  verify_owned_process "$OWNED_PID" "$OWNED_EXECUTABLE"
}

build_production_app() {
  Packaging/AppStore/build_app_store_package.sh --skip-signing >"$BUILD_LOG"
}

prepare_e2e_fixture() {
  [[ -d "$E2E_FIXTURE_SOURCE" ]] || {
    echo "E2E fixture source is missing: $E2E_FIXTURE_SOURCE" >&2
    exit 1
  }
  rm -rf "$E2E_FIXTURE"
  mkdir -p "$E2E_FIXTURE"
  cp -R "$E2E_FIXTURE_SOURCE/." "$E2E_FIXTURE/"
}

known_e2e_process_is_running() {
  [[ -f "$E2E_PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$E2E_PID_FILE")"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  [[ "$(process_command "$pid")" == "$E2E_EXECUTABLE" ]]
}

reset_e2e_state() {
  if known_e2e_process_is_running; then
    echo "Refusing to reset E2E state while owned PID $(cat "$E2E_PID_FILE") is running." >&2
    return 1
  fi

  # Container metadata is owned by containermanagerd and may not be removable.
  # Clearing Data resets every app-owned preference, draft, cache, and saved frame.
  rm -rf "$E2E_CONTAINER/Data"
  rm -f "$E2E_PREFERENCES"
  /usr/bin/defaults delete "$E2E_BUNDLE_ID" >/dev/null 2>&1 || true
}

clean_e2e_artifacts() {
  reset_e2e_state
  rm -rf "$E2E_RUNTIME_DIR" "$E2E_FIXTURE" "$E2E_EXPORT"
}

build_sandboxed_e2e_app() {
  APPSTORE_APP_NAME="$E2E_APP_NAME" \
    Packaging/AppStore/build_app_store_package.sh \
      --skip-signing \
      --bundle-id "$E2E_BUNDLE_ID" >"$BUILD_LOG"

  mkdir -p "$E2E_RUNTIME_DIR"
  local effective_entitlements="$E2E_RUNTIME_DIR/effective-entitlements.plist"
  codesign --verify --deep --strict --verbose=2 "$E2E_APP_BUNDLE"
  codesign -d --entitlements :- "$E2E_APP_BUNDLE" >"$effective_entitlements" 2>/dev/null

  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$effective_entitlements")" == "true" ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' "$effective_entitlements")" == "true" ]]

  echo "Verified E2E effective entitlements: sandbox=YES, user-selected.read-write=YES"
  echo "E2E_ENTITLEMENTS=$effective_entitlements"
}

case "$MODE" in
  run)
    build_production_app
    launch_owned_process "$APP_EXECUTABLE" "/private/tmp/codebase-combiner-run.stdout.log" "/private/tmp/codebase-combiner-run.stderr.log"
    echo "Launched exact production executable"
    echo "APP_PID=$OWNED_PID"
    echo "APP_EXECUTABLE=$OWNED_EXECUTABLE"
    ;;
  --verify|verify)
    trap cleanup_owned_process EXIT INT TERM
    build_production_app
    launch_owned_process "$APP_EXECUTABLE" "/private/tmp/codebase-combiner-verify.stdout.log" "/private/tmp/codebase-combiner-verify.stderr.log"
    echo "Verified exact production executable PID $OWNED_PID"
    cleanup_owned_process
    ;;
  --logs|logs)
    trap cleanup_owned_process EXIT INT TERM
    build_production_app
    launch_owned_process "$APP_EXECUTABLE" "/private/tmp/codebase-combiner-logs.stdout.log" "/private/tmp/codebase-combiner-logs.stderr.log"
    echo "Streaming logs for owned PID $OWNED_PID; press Ctrl-C to terminate and reap it."
    /usr/bin/log stream --info --style compact --predicate "processID == $OWNED_PID"
    ;;
  --e2e|e2e)
    trap cleanup_owned_process EXIT INT TERM
    if known_e2e_process_is_running; then
      echo "An owned E2E host is already running as PID $(cat "$E2E_PID_FILE")." >&2
      exit 1
    fi
    mkdir -p "$E2E_RUNTIME_DIR"
    rm -f "$E2E_PID_FILE"
    if [[ "${CODEBASE_COMBINER_E2E_RESET:-1}" == "1" ]]; then
      reset_e2e_state
    fi
    prepare_e2e_fixture
    build_sandboxed_e2e_app

    export CODEBASE_COMBINER_E2E_WINDOW_SIZE="${CODEBASE_COMBINER_E2E_WINDOW_SIZE:-960x640}"
    launch_owned_process "$E2E_EXECUTABLE" "$E2E_RUNTIME_DIR/stdout.log" "$E2E_RUNTIME_DIR/stderr.log"
    printf '%s\n' "$OWNED_PID" >"$E2E_PID_FILE"

    echo "Verified sandboxed E2E host launch"
    echo "E2E_PID=$OWNED_PID"
    echo "E2E_EXECUTABLE=$E2E_EXECUTABLE"
    echo "E2E_CONTAINER=$E2E_CONTAINER"
    echo "E2E_FIXTURE=$E2E_FIXTURE"
    echo "E2E_WINDOW_SIZE=$CODEBASE_COMBINER_E2E_WINDOW_SIZE"
    echo "Press Ctrl-C in this foreground wrapper to terminate and reap only E2E_PID=$OWNED_PID."

    wait "$OWNED_PID"
    OWNED_PID=""
    rm -f "$E2E_PID_FILE"
    ;;
  --clean-e2e-state|clean-e2e-state)
    clean_e2e_artifacts
    echo "Removed E2E app-owned container data, preferences, runtime files, fixture, and export."
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
