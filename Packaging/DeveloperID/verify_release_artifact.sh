#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DMG_PATH=""
MANIFEST_PATH=""
PHASE=""
SIGNING_MODE=""
MOUNT_POINT=""

usage() {
  cat <<'USAGE'
Usage: Packaging/DeveloperID/verify_release_artifact.sh --dmg <path> --manifest <path> --phase <build|pre-submit|final> --signing-mode <ad-hoc|developer-id>
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      DMG_PATH="$2"
      shift 2
      ;;
    --manifest)
      MANIFEST_PATH="$2"
      shift 2
      ;;
    --phase)
      PHASE="$2"
      shift 2
      ;;
    --signing-mode)
      SIGNING_MODE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

[[ -f "$DMG_PATH" ]] || { echo "DMG not found: $DMG_PATH" >&2; exit 2; }
[[ -f "$MANIFEST_PATH" ]] || { echo "Release manifest not found: $MANIFEST_PATH" >&2; exit 2; }
[[ "$PHASE" == build || "$PHASE" == pre-submit || "$PHASE" == final ]] || { echo "Invalid verification phase." >&2; exit 2; }
[[ "$SIGNING_MODE" == ad-hoc || "$SIGNING_MODE" == developer-id ]] || { echo "Invalid signing mode." >&2; exit 2; }

require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 1; }
}
for tool in python3 shasum codesign hdiutil lipo plutil readlink; do
  require_tool "$tool"
done
if [[ "$PHASE" == final ]]; then
  require_tool spctl
fi

manifest_line="$(python3 - "$MANIFEST_PATH" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
    product = data["product"]
    artifacts = data["artifacts"]
    notarization = data["notarization"]
    values = [
        product["name"], product["executable"], product["bundleIdentifier"],
        product["marketingVersion"], product["buildNumber"],
        product["minimumSystemVersion"], product["architecture"],
        data["sourceCommit"], data["sourceState"], data["signingMode"],
        data.get("signingTeamId") or "", artifacts["appExecutableSHA256"],
        artifacts["dmgSHA256"], artifacts["sbom"], artifacts["sbomSHA256"],
        notarization["status"], str(notarization["ticketStapled"]).lower(),
    ]
    if any("\x1f" in str(value) or "\n" in str(value) for value in values):
        raise ValueError("manifest values contain control separators")
    print("\x1f".join(str(value) for value in values))
except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
    print(f"ERROR\t{error}")
PY
)"
IFS=$'\x1f' read -r APP_NAME EXECUTABLE_NAME BUNDLE_IDENTIFIER MARKETING_VERSION BUILD_NUMBER MINIMUM_SYSTEM_VERSION ARCHITECTURE SOURCE_COMMIT SOURCE_STATE EFFECTIVE_SIGNING_IDENTITY TEAM_ID APP_SHA256 EXPECTED_DMG_SHA256 SBOM_BASENAME EXPECTED_SBOM_SHA256 NOTARY_STATUS TICKET_STAPLED <<< "$manifest_line"

[[ "$APP_NAME" != ERROR && -n "$TICKET_STAPLED" ]] || { echo "Malformed release manifest: $MANIFEST_PATH" >&2; exit 6; }
[[ "$APP_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._\ -]*$ ]] || { echo "Unsafe app name in release manifest." >&2; exit 6; }
[[ "$EXECUTABLE_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "Unsafe executable name in release manifest." >&2; exit 6; }
[[ "$ARCHITECTURE" == arm64 || "$ARCHITECTURE" == x86_64 ]] || { echo "Unsupported manifest architecture." >&2; exit 6; }

DIST_DIR="$(cd "$(dirname "$DMG_PATH")" && pwd)"
DMG_PATH="$DIST_DIR/$(basename "$DMG_PATH")"
SBOM_PATH="$DIST_DIR/$SBOM_BASENAME"
[[ -f "$SBOM_PATH" ]] || { echo "SBOM not found: $SBOM_PATH" >&2; exit 6; }

actual_dmg_sha256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
actual_sbom_sha256="$(shasum -a 256 "$SBOM_PATH" | awk '{print $1}')"
[[ "$actual_dmg_sha256" == "$EXPECTED_DMG_SHA256" ]] || { echo "DMG hash does not match the release manifest." >&2; exit 6; }
[[ "$actual_sbom_sha256" == "$EXPECTED_SBOM_SHA256" ]] || { echo "SBOM hash does not match the release manifest." >&2; exit 6; }

if [[ "$PHASE" == build || "$PHASE" == pre-submit ]]; then
  (cd "$DIST_DIR" && shasum -a 256 -c SHA256SUMS.pre-notarization >/dev/null)
fi

codesign --verify --verbose=4 "$DMG_PATH"
if [[ "$SIGNING_MODE" == developer-id ]]; then
  [[ "$SOURCE_STATE" == clean ]] || { echo "Developer ID artifact manifest is not source-clean." >&2; exit 6; }
  [[ "$SOURCE_COMMIT" == "$(git -C "$ROOT_DIR" rev-parse HEAD)" ]] || { echo "Release manifest source commit does not match HEAD." >&2; exit 6; }
  [[ "$EFFECTIVE_SIGNING_IDENTITY" == "Developer ID Application:"* ]] || { echo "Release manifest does not name a Developer ID identity." >&2; exit 6; }
  [[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "Release manifest has no valid signing Team ID." >&2; exit 6; }
  dmg_details="$(mktemp "${TMPDIR:-/tmp}/codebase-combiner-dmg-signature.XXXXXX")"
  codesign -dvvv "$DMG_PATH" >/dev/null 2> "$dmg_details"
  grep -F 'Authority=Developer ID Application:' "$dmg_details" >/dev/null
  grep -F "TeamIdentifier=$TEAM_ID" "$dmg_details" >/dev/null
  grep -F 'Timestamp=' "$dmg_details" >/dev/null
  rm -f "$dmg_details"
fi

cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

attach_output="$(hdiutil attach -readonly -nobrowse "$DMG_PATH")"
MOUNT_POINT="$(printf '%s\n' "$attach_output" | awk -F '\t' 'END {print $NF}')"
[[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]] || { echo "Unable to determine mounted DMG path." >&2; exit 6; }
[[ -L "$MOUNT_POINT/Applications" ]] || { echo "DMG is missing its Applications link." >&2; exit 6; }
[[ "$(readlink "$MOUNT_POINT/Applications")" == /Applications ]] || { echo "DMG Applications link has the wrong target." >&2; exit 6; }

MOUNTED_APP="$MOUNT_POINT/$APP_NAME.app"
MOUNTED_EXECUTABLE="$MOUNTED_APP/Contents/MacOS/$EXECUTABLE_NAME"
INFO_PLIST="$MOUNTED_APP/Contents/Info.plist"
[[ -d "$MOUNTED_APP" && -x "$MOUNTED_EXECUTABLE" ]] || { echo "Mounted app or executable is missing." >&2; exit 6; }
codesign --verify --deep --strict --verbose=4 "$MOUNTED_APP"
plutil -lint "$INFO_PLIST" >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")" == "$BUNDLE_IDENTIFIER" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")" == "$MARKETING_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")" == "$BUILD_NUMBER" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")" == "$MINIMUM_SYSTEM_VERSION" ]]
[[ "$(lipo -archs "$MOUNTED_EXECUTABLE")" == "$ARCHITECTURE" ]]
[[ "$(shasum -a 256 "$MOUNTED_EXECUTABLE" | awk '{print $1}')" == "$APP_SHA256" ]]

entitlements_output="$(mktemp "${TMPDIR:-/tmp}/codebase-combiner-entitlements.XXXXXX")"
codesign -d --entitlements - --xml "$MOUNTED_APP" > "$entitlements_output"
python3 - "$entitlements_output" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    actual = plistlib.load(handle)
expected = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
}
if actual != expected:
    raise SystemExit(f"Unexpected signed entitlements: {actual}")
PY
rm -f "$entitlements_output"

if [[ "$SIGNING_MODE" == developer-id ]]; then
  app_details="$(mktemp "${TMPDIR:-/tmp}/codebase-combiner-app-signature.XXXXXX")"
  codesign -dvvv "$MOUNTED_APP" >/dev/null 2> "$app_details"
  grep -F 'Authority=Developer ID Application:' "$app_details" >/dev/null
  grep -F "TeamIdentifier=$TEAM_ID" "$app_details" >/dev/null
  grep -E '^flags=.*runtime' "$app_details" >/dev/null
  grep -F 'Timestamp=' "$app_details" >/dev/null
  rm -f "$app_details"
fi

if [[ "$PHASE" == final ]]; then
  [[ "$NOTARY_STATUS" == Accepted && "$TICKET_STAPLED" == true ]] || { echo "Final manifest does not record an accepted, stapled artifact." >&2; exit 6; }
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
  spctl --assess --type execute --verbose=4 "$MOUNTED_APP"
fi

hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNT_POINT=""
trap - EXIT
echo "Release artifact verification passed: $PHASE / $SIGNING_MODE"
