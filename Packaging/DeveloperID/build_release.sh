#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/script/release_path_guard.sh"
source "$ROOT_DIR/script/disk_image_tools.sh"
PACKAGE_DIR="$ROOT_DIR/SwiftExplorerApp"
PACKAGING_DIR="$ROOT_DIR/Packaging/DeveloperID"
OUTPUT_NAME="${DEVELOPER_ID_OUTPUT_NAME:-developer-id}"
DIST_DIR="$ROOT_DIR/dist/$OUTPUT_NAME"

APP_NAME="${DEVELOPER_ID_APP_NAME:-Codebase Combiner}"
EXECUTABLE_NAME="${DEVELOPER_ID_EXECUTABLE_NAME:-CodebaseExplorerApp}"
BUNDLE_IDENTIFIER="${DEVELOPER_ID_BUNDLE_ID:-com.s1korrrr.codebasecombiner}"
MARKETING_VERSION="${DEVELOPER_ID_MARKETING_VERSION:-0.1.0}"
BUILD_NUMBER="${DEVELOPER_ID_BUILD_NUMBER:-1}"
MINIMUM_SYSTEM_VERSION="${DEVELOPER_ID_MINIMUM_SYSTEM_VERSION:-13.0}"
ARCHITECTURE="${DEVELOPER_ID_ARCHITECTURE:-arm64}"
COPYRIGHT_YEAR="${DEVELOPER_ID_COPYRIGHT_YEAR:-2026}"
SIGNING_IDENTITY="${DEVELOPER_ID_SIGNING_IDENTITY:-}"
SOURCE_TAG="${DEVELOPER_ID_SOURCE_TAG:-${GITHUB_REF_NAME:-}}"
SKIP_SIGNING=0

usage() {
  cat <<'USAGE'
Usage: Packaging/DeveloperID/build_release.sh [options]

Options:
  --skip-signing                    Create an ad-hoc signed local validation DMG.
  --bundle-id <id>                  Override the bundle identifier.
  --version <version>               Override CFBundleShortVersionString.
  --build-number <number>           Override CFBundleVersion.
  --architecture <arm64|x86_64>     Build one declared architecture (default: arm64).
  --signing-identity <identity>     Developer ID Application identity.
  -h, --help                        Show this help.

Environment overrides use the DEVELOPER_ID_ prefix, including
DEVELOPER_ID_SIGNING_IDENTITY, DEVELOPER_ID_ARCHITECTURE, and the safe
DEVELOPER_ID_OUTPUT_NAME directory name under dist/.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-signing)
      SKIP_SIGNING=1
      shift
      ;;
    --bundle-id)
      [[ $# -ge 2 ]] || { echo "Missing value for --bundle-id" >&2; exit 2; }
      BUNDLE_IDENTIFIER="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || { echo "Missing value for --version" >&2; exit 2; }
      MARKETING_VERSION="$2"
      shift 2
      ;;
    --build-number)
      [[ $# -ge 2 ]] || { echo "Missing value for --build-number" >&2; exit 2; }
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --architecture)
      [[ $# -ge 2 ]] || { echo "Missing value for --architecture" >&2; exit 2; }
      ARCHITECTURE="$2"
      shift 2
      ;;
    --signing-identity)
      [[ $# -ge 2 ]] || { echo "Missing value for --signing-identity" >&2; exit 2; }
      SIGNING_IDENTITY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

invalid_metadata() {
  echo "Invalid release metadata: $1" >&2
  exit 2
}

[[ "$APP_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._\ -]*$ ]] || invalid_metadata "app name"
[[ "$EXECUTABLE_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || invalid_metadata "executable name"
[[ "$BUNDLE_IDENTIFIER" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ && "$BUNDLE_IDENTIFIER" == *.* ]] || invalid_metadata "bundle identifier"
[[ "$MARKETING_VERSION" =~ ^[0-9]+([.][0-9]+){1,2}$ ]] || invalid_metadata "marketing version"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || invalid_metadata "build number"
[[ "$MINIMUM_SYSTEM_VERSION" =~ ^[0-9]+([.][0-9]+){1,2}$ ]] || invalid_metadata "minimum system version"
[[ "$ARCHITECTURE" == arm64 || "$ARCHITECTURE" == x86_64 ]] || invalid_metadata "architecture"
[[ "$COPYRIGHT_YEAR" =~ ^[0-9]{4}$ ]] || invalid_metadata "copyright year"
[[ "$OUTPUT_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || invalid_metadata "output name"

if [[ -n "$SIGNING_IDENTITY" && "$SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
  echo "Signing identity must be a Developer ID Application identity." >&2
  exit 3
fi

APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_BASENAME="Codebase-Combiner-$MARKETING_VERSION-$ARCHITECTURE.dmg"
DMG_PATH="$DIST_DIR/$DMG_BASENAME"
SBOM_BASENAME="Codebase-Combiner-$MARKETING_VERSION-$ARCHITECTURE.cdx.json"
SBOM_PATH="$DIST_DIR/$SBOM_BASENAME"
MANIFEST_PATH="$DIST_DIR/release-manifest.json"
CHECKSUM_PATH="$DIST_DIR/SHA256SUMS.pre-notarization"
FINAL_CHECKSUM_PATH="$DIST_DIR/SHA256SUMS"
NOTARY_DIR="$DIST_DIR/notarization"
PUBLIC_NOTARY_SUMMARY="$DIST_DIR/notarization-summary.json"
PUBLIC_NOTARY_SUBMISSION="$DIST_DIR/notarization-submission.json"
PUBLIC_NOTARY_LOG="$DIST_DIR/notarization-log.json"
SYMBOLS_DIR="$DIST_DIR/symbols/$MARKETING_VERSION-$BUILD_NUMBER-$ARCHITECTURE"
SYMBOL_MANIFEST="$SYMBOLS_DIR/manifest.txt"
SYMBOLS_ARCHIVE_BASENAME="Codebase-Combiner-$MARKETING_VERSION-$ARCHITECTURE-symbols.zip"
SYMBOLS_ARCHIVE_PATH="$DIST_DIR/$SYMBOLS_ARCHIVE_BASENAME"
ENTITLEMENTS="$PACKAGING_DIR/DeveloperID.entitlements"
INFO_TEMPLATE="$PACKAGING_DIR/Info.plist.in"
PRIVACY_MANIFEST="$PACKAGING_DIR/PrivacyInfo.xcprivacy"
ICON_SOURCE="$ROOT_DIR/assets/icon.jpg"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
STAGING_DIR="$DIST_DIR/dmg-root"
OPERATION_LOCK="$DIST_DIR/.release-operation.lock"
EXPECTED_TEAM_ID=""
CERTIFICATE_FINGERPRINT_SHA256=""
SOURCE_STATE="clean"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 1; }
}

validate_binary_minimum_system_version() {
  local binary="$1"
  local binary_minimum
  binary_minimum="$(xcrun vtool -show-build "$binary" | awk '$1 == "minos" { print $2; exit }')"
  [[ -n "$binary_minimum" ]] || { echo "Unable to read the Mach-O deployment target." >&2; exit 1; }
  [[ "$binary_minimum" == "$MINIMUM_SYSTEM_VERSION" ]] || {
    echo "Mach-O deployment target '$binary_minimum' does not match declared minimum '$MINIMUM_SYSTEM_VERSION'." >&2
    exit 1
  }
}

escape_sed() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

render_info_plist() {
  sed \
    -e "s/@APP_NAME@/$(escape_sed "$APP_NAME")/g" \
    -e "s/@EXECUTABLE_NAME@/$(escape_sed "$EXECUTABLE_NAME")/g" \
    -e "s/@BUNDLE_IDENTIFIER@/$(escape_sed "$BUNDLE_IDENTIFIER")/g" \
    -e "s/@MARKETING_VERSION@/$(escape_sed "$MARKETING_VERSION")/g" \
    -e "s/@BUILD_NUMBER@/$(escape_sed "$BUILD_NUMBER")/g" \
    -e "s/@MINIMUM_SYSTEM_VERSION@/$(escape_sed "$MINIMUM_SYSTEM_VERSION")/g" \
    -e "s/@COPYRIGHT_YEAR@/$(escape_sed "$COPYRIGHT_YEAR")/g" \
    "$INFO_TEMPLATE" > "$APP_PATH/Contents/Info.plist"
}

make_icon() {
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  sips -s format png -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -s format png -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -s format png -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -s format png -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -s format png -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -s format png -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -s format png -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -s format png -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -s format png -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -s format png -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
}

identity_exists() {
  security find-identity -p codesigning -v | grep -F -- "\"$1\"" >/dev/null
}

read_team_id() {
  local certificate_pem
  certificate_pem="$(mktemp "${TMPDIR:-/tmp}/codebase-combiner-cert.XXXXXX")"
  if ! security find-certificate -c "$SIGNING_IDENTITY" -p > "$certificate_pem"; then
    rm -f "$certificate_pem"
    echo "Unable to inspect signing certificate: $SIGNING_IDENTITY" >&2
    exit 3
  fi
  EXPECTED_TEAM_ID="$(openssl x509 -in "$certificate_pem" -noout -subject -nameopt RFC2253 | tr ',' '\n' | sed -n 's/^[[:space:]]*OU=//p' | head -n 1)"
  CERTIFICATE_FINGERPRINT_SHA256="$(openssl x509 -in "$certificate_pem" -noout -fingerprint -sha256 | sed 's/^sha256 Fingerprint=//; s/^SHA256 Fingerprint=//; s/://g' | tr '[:lower:]' '[:upper:]')"
  rm -f "$certificate_pem"
  [[ "$EXPECTED_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "Signing certificate has no valid Team ID." >&2; exit 3; }
  [[ "$CERTIFICATE_FINGERPRINT_SHA256" =~ ^[A-F0-9]{64}$ ]] || { echo "Signing certificate fingerprint could not be determined." >&2; exit 3; }
}

validate_app() {
  local entitlements_output="$DIST_DIR/codesign-entitlements.plist"
  local signature_output="$DIST_DIR/codesign-details.txt"
  plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null
  plutil -lint "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  codesign -dvvv "$APP_PATH" > /dev/null 2> "$signature_output"
  codesign -d --entitlements - --xml "$APP_PATH" > "$entitlements_output"
  plutil -lint "$entitlements_output" >/dev/null
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements_output")" == true ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' "$entitlements_output")" == true ]]

  if [[ "$SKIP_SIGNING" -eq 0 ]]; then
    grep -F 'Authority=Developer ID Application:' "$signature_output" >/dev/null
    grep -F "TeamIdentifier=$EXPECTED_TEAM_ID" "$signature_output" >/dev/null
    grep -E '^flags=.*runtime' "$signature_output" >/dev/null
    grep -F 'Timestamp=' "$signature_output" >/dev/null
  fi
}

preserve_symbols() {
  local release_dsym="$1/$EXECUTABLE_NAME.dSYM"
  local copied_dsym="$SYMBOLS_DIR/$EXECUTABLE_NAME.dSYM"
  local copied_dwarf="$copied_dsym/Contents/Resources/DWARF/$EXECUTABLE_NAME"
  local binary_uuid
  local dsym_uuid
  local bundle_architectures

  bundle_architectures="$(lipo -archs "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME")"
  [[ "$bundle_architectures" == "$ARCHITECTURE" ]] || { echo "Packaged architecture '$bundle_architectures' does not match '$ARCHITECTURE'." >&2; exit 1; }
  [[ -d "$release_dsym" ]] || { echo "Release dSYM not found: $release_dsym" >&2; exit 1; }

  mkdir -p "$SYMBOLS_DIR"
  cp -R "$release_dsym" "$copied_dsym"
  binary_uuid="$(dwarfdump --uuid "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" | awk '{print $2}' | sort -u)"
  dsym_uuid="$(dwarfdump --uuid "$copied_dsym" | awk '{print $2}' | sort -u)"
  [[ -n "$binary_uuid" && "$binary_uuid" == "$dsym_uuid" ]] || { echo "Release dSYM UUID does not match the app executable." >&2; exit 1; }

  {
    echo "App: $APP_NAME"
    echo "Version: $MARKETING_VERSION"
    echo "Build: $BUILD_NUMBER"
    echo "Architecture: $bundle_architectures"
    echo "Executable UUID: $binary_uuid"
    shasum -a 256 "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" "$copied_dwarf"
  } > "$SYMBOL_MANIFEST"
}

write_metadata() {
  local signing_mode="$1"
  local source_commit
  local source_timestamp
  local app_sha256
  local dmg_sha256
  local sbom_sha256
  local symbols_sha256
  source_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  source_timestamp="$(git -C "$ROOT_DIR" show -s --format=%cI HEAD)"

  python3 - "$SBOM_PATH" "$APP_NAME" "$MARKETING_VERSION" "$BUNDLE_IDENTIFIER" "$source_commit" "$source_timestamp" "$SOURCE_TAG" <<'PY'
import json
import sys

path, name, version, bundle_id, commit, timestamp, source_tag = sys.argv[1:]
document = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.5",
    "serialNumber": f"urn:uuid:{commit[:8]}-{commit[8:12]}-{commit[12:16]}-{commit[16:20]}-{commit[20:32]}",
    "version": 1,
    "metadata": {
        "timestamp": timestamp,
        "component": {
            "type": "application",
            "name": name,
            "version": version,
            "bom-ref": f"pkg:generic/{bundle_id}@{version}",
            "licenses": [{"license": {"id": "MIT"}}],
            "properties": [
                {"name": "source.commit", "value": commit},
                *([{"name": "source.tag", "value": source_tag}] if source_tag else []),
            ],
        },
    },
    "components": [],
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

  app_sha256="$(shasum -a 256 "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" | awk '{print $1}')"
  dmg_sha256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
  sbom_sha256="$(shasum -a 256 "$SBOM_PATH" | awk '{print $1}')"
  symbols_sha256="$(shasum -a 256 "$SYMBOLS_ARCHIVE_PATH" | awk '{print $1}')"

  python3 - "$MANIFEST_PATH" "$APP_NAME" "$EXECUTABLE_NAME" "$MARKETING_VERSION" "$BUILD_NUMBER" "$BUNDLE_IDENTIFIER" "$MINIMUM_SYSTEM_VERSION" "$ARCHITECTURE" "$signing_mode" "$EXPECTED_TEAM_ID" "$CERTIFICATE_FINGERPRINT_SHA256" "$source_commit" "$SOURCE_TAG" "$SOURCE_STATE" "$DMG_BASENAME" "$SBOM_BASENAME" "$SYMBOLS_ARCHIVE_BASENAME" "$app_sha256" "$dmg_sha256" "$sbom_sha256" "$symbols_sha256" <<'PY'
import json
import sys

(path, name, executable, version, build, bundle_id, minimum_os, architecture,
 signing_mode, team_id, certificate_fingerprint, commit, source_tag, source_state,
 dmg, sbom, symbols, app_sha256, dmg_sha256, sbom_sha256, symbols_sha256) = sys.argv[1:]
document = {
    "schemaVersion": 1,
    "product": {
        "name": name,
        "executable": executable,
        "bundleIdentifier": bundle_id,
        "marketingVersion": version,
        "buildNumber": build,
        "minimumSystemVersion": minimum_os,
        "architecture": architecture,
    },
    "sourceCommit": commit,
    "sourceTag": source_tag or None,
    "sourceState": source_state,
    "signingMode": signing_mode,
    "signingTeamId": team_id or None,
    "certificateFingerprintSHA256": certificate_fingerprint or None,
    "notarization": {
        "status": "not-submitted",
        "submissionId": None,
        "ticketStapled": False,
        "gatekeeperPassed": False,
    },
    "artifacts": {
        "dmg": dmg,
        "sbom": sbom,
        "symbols": symbols,
        "appExecutableSHA256": app_sha256,
        "dmgSHA256": dmg_sha256,
        "sbomSHA256": sbom_sha256,
        "symbolsSHA256": symbols_sha256,
    },
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

cleanup() {
  rm -rf "$ICONSET_DIR" "$STAGING_DIR" "$OPERATION_LOCK"
}

guard_release_output_path "$ROOT_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"
guard_release_output_path "$ROOT_DIR" "$DIST_DIR"
if ! mkdir "$OPERATION_LOCK" 2>/dev/null; then
  echo "Another Developer ID build is already running for $DIST_DIR." >&2
  exit 7
fi
printf '%s\n' "$$" > "$OPERATION_LOCK/pid"
trap cleanup EXIT

for tool in swift sips iconutil codesign plutil lipo dwarfdump shasum python3 xcrun ditto; do
  require_tool "$tool"
done
require_disk_image_tool

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]]; then
  SOURCE_STATE="dirty"
fi

if [[ "$SKIP_SIGNING" -eq 0 ]]; then
  require_tool security
  require_tool openssl
  [[ "$SOURCE_STATE" == clean ]] || { echo "Production signing requires a clean Git worktree so the manifest matches the public source commit." >&2; exit 3; }
  [[ -n "$SIGNING_IDENTITY" ]] || { echo "Pass --signing-identity explicitly for production signing." >&2; exit 3; }
  [[ "$SOURCE_TAG" =~ ^macos-v[0-9]+([.][0-9]+){1,2}$ ]] || { echo "Production signing requires DEVELOPER_ID_SOURCE_TAG=macos-v<version>." >&2; exit 3; }
  source_tag_commit="$(git -C "$ROOT_DIR" rev-list -n 1 "$SOURCE_TAG" 2>/dev/null || true)"
  [[ -n "$source_tag_commit" && "$source_tag_commit" == "$(git -C "$ROOT_DIR" rev-parse HEAD)" ]] || { echo "Release tag does not resolve to the source commit." >&2; exit 3; }
  [[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] || { echo "Signing identity must be a Developer ID Application identity." >&2; exit 3; }
  identity_exists "$SIGNING_IDENTITY" || { echo "Signing identity not found in keychain: $SIGNING_IDENTITY" >&2; exit 3; }
  read_team_id
fi

rm -rf "$APP_PATH" "$DMG_PATH" "$SBOM_PATH" "$MANIFEST_PATH" "$CHECKSUM_PATH" "$FINAL_CHECKSUM_PATH" "$NOTARY_DIR" "$SYMBOLS_DIR" "$SYMBOLS_ARCHIVE_PATH" "$STAGING_DIR" "$ICONSET_DIR"
rm -f "$PUBLIC_NOTARY_SUMMARY" "$PUBLIC_NOTARY_SUBMISSION" "$PUBLIC_NOTARY_LOG"

echo "==> Building SwiftPM release product for $ARCHITECTURE"
swift build -c release --arch "$ARCHITECTURE" --package-path "$PACKAGE_DIR" --product "$EXECUTABLE_NAME"
RELEASE_DIR="$(swift build --show-bin-path -c release --arch "$ARCHITECTURE" --package-path "$PACKAGE_DIR")"
RELEASE_BINARY="$RELEASE_DIR/$EXECUTABLE_NAME"
[[ -x "$RELEASE_BINARY" ]] || { echo "Release executable not found: $RELEASE_BINARY" >&2; exit 1; }

echo "==> Assembling $APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$RELEASE_BINARY" "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
chmod 755 "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
validate_binary_minimum_system_version "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
render_info_plist
make_icon
cp "$PRIVACY_MANIFEST" "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT_DIR/LICENSE" "$APP_PATH/Contents/Resources/LICENSE"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"

unexpected_executables="$(find "$APP_PATH/Contents" -type f -perm -111 ! -path "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" -print)"
[[ -z "$unexpected_executables" ]] || { echo "Unexpected nested executable code must be reviewed and signed explicitly:" >&2; printf '%s\n' "$unexpected_executables" >&2; exit 1; }

if [[ "$SKIP_SIGNING" -eq 1 ]]; then
  echo "==> Ad-hoc signing app for local validation"
  codesign --force --sign - --entitlements "$ENTITLEMENTS" --timestamp=none "$APP_PATH"
  SIGNING_MODE="ad-hoc local validation"
else
  echo "==> Developer ID signing app"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH"
  SIGNING_MODE="$SIGNING_IDENTITY"
fi

validate_app
preserve_symbols "$RELEASE_DIR"
ditto -c -k --sequesterRsrc --keepParent "$DIST_DIR/symbols" "$SYMBOLS_ARCHIVE_PATH"

echo "==> Creating drag-to-Applications DMG"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
disk_image_create "$APP_NAME" "$STAGING_DIR" "$DMG_PATH"

if [[ "$SKIP_SIGNING" -eq 1 ]]; then
  codesign --force --sign - --timestamp=none "$DMG_PATH"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
fi
codesign --verify --verbose=2 "$DMG_PATH"

write_metadata "$SIGNING_MODE"

(
  cd "$DIST_DIR"
  shasum -a 256 \
    "$DMG_BASENAME" \
    "$APP_NAME.app/Contents/MacOS/$EXECUTABLE_NAME" \
    "symbols/$MARKETING_VERSION-$BUILD_NUMBER-$ARCHITECTURE/$EXECUTABLE_NAME.dSYM/Contents/Resources/DWARF/$EXECUTABLE_NAME" \
    "$SBOM_BASENAME" \
    "$SYMBOLS_ARCHIVE_BASENAME" \
    "release-manifest.json" > "$(basename "$CHECKSUM_PATH")"
)

"$PACKAGING_DIR/verify_release_artifact.sh" \
  --dmg "$DMG_PATH" \
  --manifest "$MANIFEST_PATH" \
  --phase build \
  --signing-mode "$([[ "$SKIP_SIGNING" -eq 1 ]] && printf ad-hoc || printf developer-id)"

echo "==> Developer ID release candidate assembled"
echo "App: $APP_PATH"
echo "DMG: $DMG_PATH"
echo "Signing: $SIGNING_MODE"
echo "Notarization: not submitted; use Packaging/DeveloperID/notarize_release.sh after approval"
