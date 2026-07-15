#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT_DIR/Packaging/DeveloperID/notarize_release.sh"
VERIFIER="$ROOT_DIR/Packaging/DeveloperID/verify_release_artifact.sh"

for executable in "$SCRIPT" "$VERIFIER"; do
  [[ -x "$executable" ]] || { echo "Release script is missing or not executable: $executable" >&2; exit 1; }
  bash -n "$executable"
done

help_output="$($SCRIPT --help)"
grep -F -- '--keychain-profile' <<< "$help_output" >/dev/null
grep -F -- '  --keychain <path>' <<< "$help_output" >/dev/null
grep -F -- '--submission-id' <<< "$help_output" >/dev/null
grep -F -- '--timeout' "$SCRIPT" >/dev/null
grep -F 'verify_release_artifact.sh' "$SCRIPT" >/dev/null
if grep -Ei 'password|apple-id' "$SCRIPT"; then
  echo "Notarization script must accept only a Keychain profile, never inline account credentials." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codebase-combiner-notary-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN_DIR="$TMP_DIR/bin"
MOUNT_POINT="$TMP_DIR/mount/Codebase Combiner"
MOUNTED_APP="$MOUNT_POINT/Codebase Combiner.app"
MOUNTED_EXECUTABLE="$MOUNTED_APP/Contents/MacOS/CodebaseExplorerApp"
DMG="$TMP_DIR/Codebase-Combiner-0.1.0-arm64.dmg"
SBOM="$TMP_DIR/Codebase-Combiner-0.1.0-arm64.cdx.json"
MANIFEST="$TMP_DIR/release-manifest.json"
ENTITLEMENTS="$TMP_DIR/entitlements.plist"
INFO_PLIST="$MOUNTED_APP/Contents/Info.plist"
LOG="$TMP_DIR/calls.log"
mkdir -p "$BIN_DIR" "$MOUNTED_APP/Contents/MacOS"

cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
</dict></plist>
PLIST

cat > "$INFO_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.s1korrrr.codebasecombiner</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
printf 'fixture executable\n' > "$MOUNTED_EXECUTABLE"
chmod +x "$MOUNTED_EXECUTABLE"
ln -s /Applications "$MOUNT_POINT/Applications"

cat > "$BIN_DIR/xcrun" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'xcrun %s\n' "$*" >> "$CALL_LOG"
case "$1:$2" in
  notarytool:submit)
    if [[ "${NOTARYTOOL_MALFORMED:-0}" == 1 ]]; then
      printf '{"id":"submission-123"}\n'
    elif [[ "${SUBMIT_FAIL_WITH_ID:-0}" == 1 ]]; then
      printf '{"id":"submission-123","status":"In Progress"}\n'
      exit 1
    else
      printf '{"id":"submission-123","status":"%s","message":"test"}\n' "${NOTARYTOOL_STATUS:-Accepted}"
    fi
    ;;
  notarytool:info)
    printf '{"id":"submission-123","status":"%s"}\n' "${INFO_STATUS:-Accepted}"
    ;;
  notarytool:wait)
    printf '{"id":"submission-123","status":"%s"}\n' "${WAIT_STATUS:-Accepted}"
    ;;
  notarytool:log)
    output="${!#}"
    printf '{"id":"submission-123","issues":[]}\n' > "$output"
    ;;
  stapler:staple)
    [[ "${FAIL_GATE:-}" != staple ]] || exit 70
    ;;
  stapler:validate)
    [[ "${FAIL_GATE:-}" != stapler-validate ]] || exit 71
    ;;
  *)
    echo "Unexpected xcrun invocation: $*" >&2
    exit 64
    ;;
esac
STUB

cat > "$BIN_DIR/spctl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'spctl %s\n' "$*" >> "$CALL_LOG"
if [[ "$*" == *"--type open"* && "${FAIL_GATE:-}" == spctl-open ]]; then exit 72; fi
if [[ "$*" == *"--type execute"* && "${FAIL_GATE:-}" == spctl-execute ]]; then exit 73; fi
STUB

cat > "$BIN_DIR/codesign" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'codesign %s\n' "$*" >> "$CALL_LOG"
if [[ "$*" == *"--verify"* && "${FAIL_GATE:-}" == codesign-verify ]]; then exit 74; fi
if [[ "$*" == *"-dvvv"* ]]; then
  cat >&2 <<'DETAILS'
Authority=Developer ID Application: Rafal Sikora (2NY8A789TN)
TeamIdentifier=2NY8A789TN
flags=0x10000(runtime)
Timestamp=Jul 15, 2026 at 10:00:00 PM
DETAILS
elif [[ "$*" == *"--entitlements"* ]]; then
  cat "$TEST_ENTITLEMENTS"
fi
STUB

cat > "$BIN_DIR/hdiutil" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'hdiutil %s\n' "$*" >> "$CALL_LOG"
case "$1" in
  attach)
    [[ "${FAIL_GATE:-}" != hdiutil-attach ]] || exit 75
    if [[ "${FAIL_GATE:-}" == wrong-link ]]; then
      rm -f "$TEST_MOUNT_POINT/Applications"
      ln -s /tmp "$TEST_MOUNT_POINT/Applications"
    fi
    printf '/dev/disk42\tApple_HFS\t%s\n' "$TEST_MOUNT_POINT"
    ;;
  detach)
    ;;
  *)
    exit 64
    ;;
esac
STUB

cat > "$BIN_DIR/lipo" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'arm64\n'
STUB
chmod +x "$BIN_DIR/xcrun" "$BIN_DIR/spctl" "$BIN_DIR/codesign" "$BIN_DIR/hdiutil" "$BIN_DIR/lipo"

reset_fixture() {
  rm -rf "$TMP_DIR/notarization" "$TMP_DIR/SHA256SUMS"
  rm -f "$MOUNT_POINT/Applications"
  ln -s /Applications "$MOUNT_POINT/Applications"
  printf 'dmg fixture\n' > "$DMG"
  printf '{"bomFormat":"CycloneDX","specVersion":"1.5"}\n' > "$SBOM"
  local app_hash
  local dmg_hash
  local sbom_hash
  local source_commit
  app_hash="$(shasum -a 256 "$MOUNTED_EXECUTABLE" | awk '{print $1}')"
  dmg_hash="$(shasum -a 256 "$DMG" | awk '{print $1}')"
  sbom_hash="$(shasum -a 256 "$SBOM" | awk '{print $1}')"
  source_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  python3 - "$MANIFEST" "$source_commit" "$app_hash" "$dmg_hash" "$sbom_hash" <<'PY'
import json
import sys

path, commit, app_hash, dmg_hash, sbom_hash = sys.argv[1:]
data = {
    "schemaVersion": 1,
    "product": {
        "name": "Codebase Combiner",
        "executable": "CodebaseExplorerApp",
        "bundleIdentifier": "com.s1korrrr.codebasecombiner",
        "marketingVersion": "0.1.0",
        "buildNumber": "1",
        "minimumSystemVersion": "13.0",
        "architecture": "arm64",
    },
    "sourceCommit": commit,
    "sourceState": "clean",
    "signingMode": "Developer ID Application: Rafal Sikora (2NY8A789TN)",
    "signingTeamId": "2NY8A789TN",
    "certificateFingerprintSHA256": "A" * 64,
    "notarization": {
        "status": "not-submitted",
        "submissionId": None,
        "ticketStapled": False,
        "gatekeeperPassed": False,
    },
    "artifacts": {
        "dmg": "Codebase-Combiner-0.1.0-arm64.dmg",
        "sbom": "Codebase-Combiner-0.1.0-arm64.cdx.json",
        "appExecutableSHA256": app_hash,
        "dmgSHA256": dmg_hash,
        "sbomSHA256": sbom_hash,
    },
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
  (
    cd "$TMP_DIR"
    shasum -a 256 \
      "$(basename "$DMG")" \
      "$(basename "$SBOM")" \
      "$(basename "$MANIFEST")" > SHA256SUMS.pre-notarization
  )
  : > "$LOG"
}

run_notary() {
  CALL_LOG="$LOG" \
    TEST_MOUNT_POINT="$MOUNT_POINT" \
    TEST_ENTITLEMENTS="$ENTITLEMENTS" \
    PATH="$BIN_DIR:$PATH" \
    "$SCRIPT" --dmg "$DMG" --keychain-profile test-notary --keychain "$TMP_DIR/test.keychain-db" --app-name 'Codebase Combiner' "$@"
}

reset_fixture
mkdir -p "$TMP_DIR/.release-operation.lock"
if NOTARYTOOL_STATUS=Accepted run_notary >/dev/null 2>&1; then
  echo "Concurrent release operation unexpectedly entered notarization." >&2
  exit 1
fi
test ! -s "$LOG"
rm -rf "$TMP_DIR/.release-operation.lock"

reset_fixture
NOTARYTOOL_STATUS='In Progress' WAIT_STATUS=Accepted run_notary
grep -F 'notarytool submit' "$LOG" >/dev/null
grep -F -- '--keychain-profile test-notary' "$LOG" >/dev/null
grep -F -- '--keychain '"$TMP_DIR/test.keychain-db" "$LOG" >/dev/null
grep -F 'notarytool wait submission-123' "$LOG" >/dev/null
grep -F 'notarytool log submission-123' "$LOG" >/dev/null
grep -F 'stapler staple' "$LOG" >/dev/null
grep -F 'stapler validate' "$LOG" >/dev/null
grep -F 'spctl --assess --type open' "$LOG" >/dev/null
grep -F 'spctl --assess --type execute' "$LOG" >/dev/null
grep -F 'codesign --verify --deep --strict' "$LOG" >/dev/null
test -f "$TMP_DIR/notarization/submission-123-log.json"
test -f "$TMP_DIR/SHA256SUMS"
python3 - "$MANIFEST" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
assert data["notarization"] == {
    "status": "Accepted",
    "submissionId": "submission-123",
    "ticketStapled": True,
    "gatekeeperPassed": True,
}
PY
(cd "$TMP_DIR" && shasum -a 256 -c SHA256SUMS)
test "$(wc -l < "$TMP_DIR/SHA256SUMS" | tr -d ' ')" = 1
grep -F 'Codebase-Combiner-0.1.0-arm64.dmg' "$TMP_DIR/SHA256SUMS" >/dev/null

reset_fixture
if NOTARYTOOL_STATUS=Invalid run_notary >/dev/null 2>&1; then
  echo "Invalid notarization unexpectedly succeeded." >&2
  exit 1
fi
grep -F 'notarytool log submission-123' "$LOG" >/dev/null
if grep -F 'stapler staple' "$LOG"; then
  echo "Invalid notarization must not staple the artifact." >&2
  exit 1
fi

reset_fixture
if NOTARYTOOL_MALFORMED=1 run_notary >/dev/null 2>&1; then
  echo "Malformed notarization response unexpectedly succeeded." >&2
  exit 1
fi
if grep -F 'stapler staple' "$LOG"; then
  echo "Malformed notarization response must not staple the artifact." >&2
  exit 1
fi

reset_fixture
if SUBMIT_FAIL_WITH_ID=1 run_notary >/dev/null 2>&1; then
  echo "Interrupted submission unexpectedly succeeded." >&2
  exit 1
fi
test -f "$TMP_DIR/notarization/resume-command.txt"
grep -F -- '--submission-id submission-123' "$TMP_DIR/notarization/resume-command.txt" >/dev/null
if grep -F 'stapler staple' "$LOG"; then
  echo "Interrupted submission must not staple the artifact." >&2
  exit 1
fi

reset_fixture
INFO_STATUS='In Progress' WAIT_STATUS=Accepted run_notary --submission-id submission-123
grep -F 'notarytool info submission-123' "$LOG" >/dev/null
grep -F 'notarytool wait submission-123' "$LOG" >/dev/null

for failure_gate in staple stapler-validate spctl-open spctl-execute codesign-verify hdiutil-attach wrong-link; do
  reset_fixture
  if FAIL_GATE="$failure_gate" NOTARYTOOL_STATUS=Accepted run_notary >/dev/null 2>&1; then
    echo "Release gate '$failure_gate' unexpectedly succeeded." >&2
    exit 1
  fi
done

echo "Developer ID notarization contract passed"
