#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$ROOT_DIR/script/disk_image_tools.sh"
SCRIPT="$ROOT_DIR/Packaging/DeveloperID/build_release.sh"
VERIFIER="$ROOT_DIR/Packaging/DeveloperID/verify_release_artifact.sh"
OUTPUT_NAME="developer-id-contract-$$"
DIST_DIR="$ROOT_DIR/dist/$OUTPUT_NAME"
APP="$DIST_DIR/Codebase Combiner.app"
DMG="$DIST_DIR/Codebase-Combiner-0.1.0-arm64.dmg"
mount_point=""

cleanup() {
  if [[ -n "$mount_point" ]]; then
    disk_image_eject "$mount_point" >/dev/null 2>&1 || true
  fi
  rm -rf "$DIST_DIR"
}
trap cleanup EXIT

run_build() {
  DEVELOPER_ID_OUTPUT_NAME="$OUTPUT_NAME" "$SCRIPT" "$@"
}

if [[ ! -x "$SCRIPT" ]]; then
  echo "Developer ID build script is missing or not executable: $SCRIPT" >&2
  exit 1
fi
if [[ ! -x "$VERIFIER" ]]; then
  echo "Developer ID verifier is missing or not executable: $VERIFIER" >&2
  exit 1
fi

bash -n "$SCRIPT"
bash -n "$VERIFIER"
grep -F 'verify_release_artifact.sh' "$SCRIPT" >/dev/null

help_output="$(run_build --help)"
grep -F -- '--skip-signing' <<< "$help_output" >/dev/null
grep -F -- '--signing-identity' <<< "$help_output" >/dev/null
grep -F 'Developer ID Application' <<< "$help_output" >/dev/null

if grep -Ei 'provisioning|productbuild|installer identity|app store' "$SCRIPT"; then
  echo "Developer ID build must not depend on Mac App Store packaging concepts." >&2
  exit 1
fi

grep -F -- '--options runtime' "$SCRIPT" >/dev/null
grep -F -- '--timestamp' "$SCRIPT" >/dev/null
grep -F 'Production signing requires a clean Git worktree' "$SCRIPT" >/dev/null
grep -F 'Pass --signing-identity explicitly' "$SCRIPT" >/dev/null
grep -F 'Another Developer ID build is already running' "$SCRIPT" >/dev/null
grep -F 'guard_release_output_path' "$SCRIPT" >/dev/null
if grep -E 'codesign .*--deep.*--sign|codesign .*--sign.*--deep' "$SCRIPT"; then
  echo "Developer ID signing must enumerate nested code rather than sign with --deep." >&2
  exit 1
fi

external_output="$(mktemp -d "${TMPDIR:-/tmp}/codebase-combiner-external-output.XXXXXX")"
symlink_output_name="$OUTPUT_NAME-symlink"
symlink_output="$ROOT_DIR/dist/$symlink_output_name"
mkdir -p "$ROOT_DIR/dist"
printf 'preserve-external\n' > "$external_output/sentinel"
ln -s "$external_output" "$symlink_output"
if DEVELOPER_ID_OUTPUT_NAME="$symlink_output_name" "$SCRIPT" --skip-signing >/dev/null 2>&1; then
  echo "Symlinked Developer ID output unexpectedly succeeded." >&2
  exit 1
fi
grep -F 'preserve-external' "$external_output/sentinel" >/dev/null
rm -f "$symlink_output"
rm -rf "$external_output"

mkdir -p "$DIST_DIR"
sentinel="$DIST_DIR/path-validation-sentinel"
printf 'preserve\n' > "$sentinel"

if run_build --skip-signing --version '../escape' >/dev/null 2>&1; then
  echo "Unsafe release version unexpectedly succeeded." >&2
  exit 1
fi
grep -F 'preserve' "$sentinel" >/dev/null

if run_build --skip-signing --architecture universal2 >/dev/null 2>&1; then
  echo "Unimplemented universal architecture unexpectedly succeeded." >&2
  exit 1
fi
grep -F 'preserve' "$sentinel" >/dev/null

if run_build --signing-identity 'Apple Development: Example (AAAAAAAAAA)' >/dev/null 2>&1; then
  echo "Non-Developer-ID signing identity unexpectedly succeeded." >&2
  exit 1
fi
grep -F 'preserve' "$sentinel" >/dev/null

mkdir -p "$DIST_DIR/.release-operation.lock"
if run_build --skip-signing >/dev/null 2>&1; then
  echo "Concurrent Developer ID build unexpectedly succeeded." >&2
  exit 1
fi
grep -F 'preserve' "$sentinel" >/dev/null
rm -rf "$DIST_DIR/.release-operation.lock"

if DEVELOPER_ID_MINIMUM_SYSTEM_VERSION=12.0 run_build --skip-signing >/dev/null 2>&1; then
  echo "Mismatched Mach-O deployment target unexpectedly succeeded." >&2
  exit 1
fi
grep -F 'preserve' "$sentinel" >/dev/null

mkdir -p "$DIST_DIR/notarization"
printf 'stale\n' > "$DIST_DIR/notarization/summary.json"
printf 'stale\n' > "$DIST_DIR/SHA256SUMS"
run_build --skip-signing

test -d "$APP"
test -f "$DMG"
test -f "$DIST_DIR/SHA256SUMS.pre-notarization"
test -f "$DIST_DIR/Codebase-Combiner-0.1.0-arm64.cdx.json"
test -f "$DIST_DIR/release-manifest.json"
test -f "$DIST_DIR/symbols/0.1.0-1-arm64/manifest.txt"
test ! -e "$APP/Contents/embedded.provisionprofile"
test ! -e "$DIST_DIR/notarization"
test ! -e "$DIST_DIR/SHA256SUMS"
cmp -s "$ROOT_DIR/LICENSE" "$APP/Contents/Resources/LICENSE"
cmp -s "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"

plutil -lint "$APP/Contents/Info.plist" >/dev/null
plutil -lint "$APP/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --verbose=2 "$DMG"

signed_entitlements="$DIST_DIR/test-entitlements.plist"
codesign -d --entitlements - --xml "$APP" > "$signed_entitlements"
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$signed_entitlements")" = true
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' "$signed_entitlements")" = true

test "$(lipo -archs "$APP/Contents/MacOS/CodebaseExplorerApp")" = arm64
binary_uuid="$(dwarfdump --uuid "$APP/Contents/MacOS/CodebaseExplorerApp" | awk '{print $2}' | sort -u)"
dsym_uuid="$(dwarfdump --uuid "$DIST_DIR/symbols/0.1.0-1-arm64/CodebaseExplorerApp.dSYM" | awk '{print $2}' | sort -u)"
test -n "$binary_uuid"
test "$binary_uuid" = "$dsym_uuid"

grep -F '"bomFormat": "CycloneDX"' "$DIST_DIR/Codebase-Combiner-0.1.0-arm64.cdx.json" >/dev/null
grep -F '"name": "Codebase Combiner"' "$DIST_DIR/Codebase-Combiner-0.1.0-arm64.cdx.json" >/dev/null
grep -F '"signingMode": "ad-hoc local validation"' "$DIST_DIR/release-manifest.json" >/dev/null
grep -E '"sourceState": "(clean|dirty)"' "$DIST_DIR/release-manifest.json" >/dev/null
grep -F '"appExecutableSHA256":' "$DIST_DIR/release-manifest.json" >/dev/null
grep -F '"dmgSHA256":' "$DIST_DIR/release-manifest.json" >/dev/null

attach_output="$(disk_image_attach "$DMG")"
mount_point="$(printf '%s\n' "$attach_output" | awk -F '\t' 'END {print $NF}')"
test "$(readlink "$mount_point/Applications")" = /Applications
codesign --verify --deep --strict --verbose=2 "$mount_point/Codebase Combiner.app"
cmp -s "$ROOT_DIR/LICENSE" "$mount_point/Codebase Combiner.app/Contents/Resources/LICENSE"
cmp -s "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$mount_point/Codebase Combiner.app/Contents/Resources/THIRD_PARTY_NOTICES.md"
source_hash="$(shasum -a 256 "$APP/Contents/MacOS/CodebaseExplorerApp" | awk '{print $1}')"
mounted_hash="$(shasum -a 256 "$mount_point/Codebase Combiner.app/Contents/MacOS/CodebaseExplorerApp" | awk '{print $1}')"
test "$source_hash" = "$mounted_hash"
disk_image_eject "$mount_point"
mount_point=""

(cd "$DIST_DIR" && shasum -a 256 -c SHA256SUMS.pre-notarization)

rm -f "$signed_entitlements"
echo "Developer ID build contract passed"
