#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/script/release_path_guard.sh"
PACKAGE_DIR="$ROOT_DIR/SwiftExplorerApp"
PACKAGING_DIR="$ROOT_DIR/Packaging/AppStore"
OUTPUT_NAME="${APPSTORE_OUTPUT_NAME:-app-store}"
DIST_DIR="$ROOT_DIR/dist/$OUTPUT_NAME"
APP_NAME="${APPSTORE_APP_NAME:-Codebase Combiner}"
EXECUTABLE_NAME="${APPSTORE_EXECUTABLE_NAME:-CodebaseExplorerApp}"
BUNDLE_IDENTIFIER="${APPSTORE_BUNDLE_ID:-com.s1korrrr.codebasecombiner}"
MARKETING_VERSION="${APPSTORE_MARKETING_VERSION:-0.1.0}"
BUILD_NUMBER="${APPSTORE_BUILD_NUMBER:-1}"
MINIMUM_SYSTEM_VERSION="${APPSTORE_MINIMUM_SYSTEM_VERSION:-13.0}"
ARCHITECTURE="${APPSTORE_ARCHITECTURE:-arm64}"
COPYRIGHT_YEAR="${APPSTORE_COPYRIGHT_YEAR:-2026}"
SIGNING_IDENTITY="${APPSTORE_SIGNING_IDENTITY:-}"
INSTALLER_IDENTITY="${APPSTORE_INSTALLER_IDENTITY:-}"
PROVISIONING_PROFILE="${APPSTORE_PROVISIONING_PROFILE:-}"
SKIP_SIGNING=0

usage() {
  cat <<USAGE
Usage: Packaging/AppStore/build_app_store_package.sh [options]

Options:
  --skip-signing                         Create an ad-hoc signed local bundle only.
  --bundle-id <id>                       Override bundle identifier.
  --version <version>                    Override CFBundleShortVersionString.
  --build-number <number>                Override CFBundleVersion.
  --architecture <architecture>          Build one declared architecture (default: arm64).
  --signing-identity <identity>          App signing identity.
  --installer-identity <identity>        Installer/package signing identity.
  --provisioning-profile <path>          Mac App Store provisioning profile.
  -h, --help                             Show this help.

Environment overrides:
  APPSTORE_BUNDLE_ID, APPSTORE_MARKETING_VERSION, APPSTORE_BUILD_NUMBER,
  APPSTORE_ARCHITECTURE, APPSTORE_OUTPUT_NAME,
  APPSTORE_SIGNING_IDENTITY, APPSTORE_INSTALLER_IDENTITY,
  APPSTORE_PROVISIONING_PROFILE
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
    --installer-identity)
      [[ $# -ge 2 ]] || { echo "Missing value for --installer-identity" >&2; exit 2; }
      INSTALLER_IDENTITY="$2"
      shift 2
      ;;
    --provisioning-profile)
      [[ $# -ge 2 ]] || { echo "Missing value for --provisioning-profile" >&2; exit 2; }
      PROVISIONING_PROFILE="$2"
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
[[ "$ARCHITECTURE" == "arm64" || "$ARCHITECTURE" == "x86_64" ]] || invalid_metadata "architecture"
[[ "$COPYRIGHT_YEAR" =~ ^[0-9]{4}$ ]] || invalid_metadata "copyright year"
[[ "$OUTPUT_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || invalid_metadata "output name"

is_app_store_app_identity() {
  case "$1" in
    "Apple Distribution:"*|"Mac App Distribution:"*|"3rd Party Mac Developer Application:"*) return 0 ;;
    *) return 1 ;;
  esac
}

is_app_store_installer_identity() {
  case "$1" in
    "Mac Installer Distribution:"*|"3rd Party Mac Developer Installer:"*) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ -n "$SIGNING_IDENTITY" ]] && ! is_app_store_app_identity "$SIGNING_IDENTITY"; then
  echo "Signing identity must be a Mac App Store distribution identity." >&2
  exit 3
fi
if [[ -n "$INSTALLER_IDENTITY" ]] && ! is_app_store_installer_identity "$INSTALLER_IDENTITY"; then
  echo "Installer identity must be a Mac App Store installer distribution identity." >&2
  exit 3
fi

APP_PATH="$DIST_DIR/$APP_NAME.app"
PKG_PATH="$DIST_DIR/${APP_NAME// /}-AppStore.pkg"
SUMMARY_PATH="$DIST_DIR/${APP_NAME// /}-AppStore-summary.txt"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
RELEASE_DIR="$PACKAGE_DIR/.build/${ARCHITECTURE}-apple-macosx/release"
RELEASE_BINARY="$RELEASE_DIR/$EXECUTABLE_NAME"
RELEASE_DSYM="$RELEASE_DIR/$EXECUTABLE_NAME.dSYM"
SYMBOLS_DIR="$DIST_DIR/symbols/$MARKETING_VERSION-$BUILD_NUMBER-$ARCHITECTURE"
SYMBOL_MANIFEST="$SYMBOLS_DIR/manifest.txt"
ENTITLEMENTS="$PACKAGING_DIR/AppStore.entitlements"
INFO_TEMPLATE="$PACKAGING_DIR/Info.plist.in"
PRIVACY_MANIFEST="$PACKAGING_DIR/PrivacyInfo.xcprivacy"
PROFILE_VALIDATOR="$PACKAGING_DIR/validate_provisioning_profile.py"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
ICON_SOURCE="$ROOT_DIR/assets/icon.jpg"
TEMP_DIR=""
EXPECTED_TEAM_ID=""
SIGNING_ENTITLEMENTS="$ENTITLEMENTS"
SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
SOURCE_STATE="clean"
MANIFEST_PATH="$DIST_DIR/release-manifest.json"
CHECKSUM_PATH="$DIST_DIR/SHA256SUMS"
OPERATION_LOCK="$DIST_DIR/.app-store-operation.lock"
OPERATION_LOCK_CREATED=0

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
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
    "$INFO_TEMPLATE" > "$INFO_PLIST"
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
  local identity="$1"
  security find-identity -p codesigning -v | grep -F -- "$identity" >/dev/null
}

installer_identity_exists() {
  local identity="$1"
  security find-identity -p basic -v 2>/dev/null | grep -F -- "$identity" >/dev/null
}

cleanup() {
  local status=$?
  if [[ -n "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
  if [[ "$OPERATION_LOCK_CREATED" -eq 1 ]]; then
    rm -rf "$OPERATION_LOCK"
  fi
  return "$status"
}

prepare_distribution_signing() {
  if [[ -z "$PROVISIONING_PROFILE" ]]; then
    echo "Missing Mac App Store provisioning profile. Pass --provisioning-profile with a profile matching $BUNDLE_IDENTIFIER." >&2
    exit 3
  fi
  if [[ ! -f "$PROVISIONING_PROFILE" ]]; then
    echo "Provisioning profile not found: $PROVISIONING_PROFILE" >&2
    exit 3
  fi
  if [[ -z "$INSTALLER_IDENTITY" ]]; then
    echo "Missing Mac App Store installer identity." >&2
    exit 3
  fi
  if ! installer_identity_exists "$INSTALLER_IDENTITY"; then
    echo "Installer identity not found in keychain: $INSTALLER_IDENTITY" >&2
    exit 3
  fi

  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codebase-combiner-signing.XXXXXX")"
  trap cleanup EXIT
  local decoded_profile="$TEMP_DIR/profile.plist"
  local certificate_pem="$TEMP_DIR/certificate.pem"
  local certificate_der="$TEMP_DIR/certificate.der"
  SIGNING_ENTITLEMENTS="$TEMP_DIR/signing.entitlements"

  if ! security cms -D -u 9 -i "$PROVISIONING_PROFILE" > "$decoded_profile"; then
    echo "Provisioning profile could not be decoded or trusted under the protected-object signer policy." >&2
    exit 3
  fi
  if ! security find-certificate -c "$SIGNING_IDENTITY" -p > "$certificate_pem"; then
    echo "Signing certificate could not be exported for profile matching: $SIGNING_IDENTITY" >&2
    exit 3
  fi
  openssl x509 -in "$certificate_pem" -outform der -out "$certificate_der"
  EXPECTED_TEAM_ID="$(openssl x509 -in "$certificate_pem" -noout -subject -nameopt RFC2253 | tr ',' '\n' | sed -n 's/^[[:space:]]*OU=//p' | head -n 1)"
  if [[ -z "$EXPECTED_TEAM_ID" ]]; then
    echo "Signing certificate does not contain an Organizational Unit Team ID." >&2
    exit 3
  fi

  local installer_certificate_pem="$TEMP_DIR/installer-certificate.pem"
  local installer_team_id
  if ! security find-certificate -c "$INSTALLER_IDENTITY" -p > "$installer_certificate_pem"; then
    echo "Installer certificate could not be exported for Team ID validation: $INSTALLER_IDENTITY" >&2
    exit 3
  fi
  installer_team_id="$(openssl x509 -in "$installer_certificate_pem" -noout -subject -nameopt RFC2253 | tr ',' '\n' | sed -n 's/^[[:space:]]*OU=//p' | head -n 1)"
  if [[ -z "$installer_team_id" || "$installer_team_id" != "$EXPECTED_TEAM_ID" ]]; then
    echo "Installer certificate Team ID '${installer_team_id:-missing}' does not match app signing Team ID '$EXPECTED_TEAM_ID'." >&2
    exit 3
  fi

  xcrun python3 "$PROFILE_VALIDATOR" \
    --profile-plist "$decoded_profile" \
    --bundle-id "$BUNDLE_IDENTIFIER" \
    --team-id "$EXPECTED_TEAM_ID" \
    --certificate-der "$certificate_der" \
    --entitlements "$ENTITLEMENTS" \
    --output-entitlements "$SIGNING_ENTITLEMENTS"
}

maybe_autodetect_identities() {
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -p codesigning -v | sed -n 's/.*"\(Apple Distribution:.*\)".*/\1/p; s/.*"\(Mac App Distribution:.*\)".*/\1/p; s/.*"\(3rd Party Mac Developer Application:.*\)".*/\1/p' | head -n 1)"
  fi
  if [[ -z "$INSTALLER_IDENTITY" ]]; then
    INSTALLER_IDENTITY="$(security find-identity -p basic -v 2>/dev/null | sed -n 's/.*"\(3rd Party Mac Developer Installer:.*\)".*/\1/p; s/.*"\(Mac Installer Distribution:.*\)".*/\1/p' | head -n 1)"
  fi
}

validate_bundle() {
  local signed_entitlements="$DIST_DIR/codesign-entitlements.plist"
  local signature_details="$DIST_DIR/codesign-details.txt"
  plutil -lint "$INFO_PLIST"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  codesign -dvvv "$APP_PATH" > /dev/null 2> "$signature_details"
  codesign -d --entitlements - --xml "$APP_PATH" > "$signed_entitlements"
  plutil -lint "$signed_entitlements"

  if [[ "$SKIP_SIGNING" -eq 0 ]]; then
    local expected_application_identifier
    local actual_application_identifier
    local actual_team_identifier
    expected_application_identifier="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$SIGNING_ENTITLEMENTS")"
    actual_application_identifier="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$signed_entitlements")"
    actual_team_identifier="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$signed_entitlements")"

    grep -F "TeamIdentifier=$EXPECTED_TEAM_ID" "$signature_details" >/dev/null
    grep -E '^Authority=(Apple Distribution|Mac App Distribution|3rd Party Mac Developer Application):' "$signature_details" >/dev/null
    [[ "$actual_application_identifier" == "$expected_application_identifier" ]]
    [[ "$actual_team_identifier" == "$EXPECTED_TEAM_ID" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$signed_entitlements")" == "true" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' "$signed_entitlements")" == "true" ]]
    cmp -s "$PROVISIONING_PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
  fi

  spctl -a -vv "$APP_PATH" > "$DIST_DIR/spctl-app.txt" 2>&1 || true
}

preserve_symbols() {
  local bundle_binary="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
  local copied_dsym="$SYMBOLS_DIR/$EXECUTABLE_NAME.dSYM"
  local copied_dwarf="$copied_dsym/Contents/Resources/DWARF/$EXECUTABLE_NAME"
  local binary_uuid
  local dsym_uuid
  local bundle_architectures

  bundle_architectures="$(lipo -archs "$bundle_binary")"
  if [[ "$bundle_architectures" != "$ARCHITECTURE" ]]; then
    echo "Packaged architectures '$bundle_architectures' do not match declared architecture '$ARCHITECTURE'." >&2
    exit 1
  fi
  if [[ ! -d "$RELEASE_DSYM" ]]; then
    echo "Release dSYM not found: $RELEASE_DSYM" >&2
    exit 1
  fi

  mkdir -p "$SYMBOLS_DIR"
  cp -R "$RELEASE_DSYM" "$copied_dsym"
  binary_uuid="$(dwarfdump --uuid "$bundle_binary" | awk '{print $2}' | sort -u)"
  dsym_uuid="$(dwarfdump --uuid "$copied_dsym" | awk '{print $2}' | sort -u)"
  if [[ -z "$binary_uuid" || "$binary_uuid" != "$dsym_uuid" ]]; then
    echo "Release dSYM UUID does not match the packaged executable." >&2
    exit 1
  fi

  {
    echo "App: $APP_NAME"
    echo "Version: $MARKETING_VERSION"
    echo "Build: $BUILD_NUMBER"
    echo "Architecture: $bundle_architectures"
    echo "Executable UUID: $binary_uuid"
    shasum -a 256 "$bundle_binary" "$copied_dwarf"
  } > "$SYMBOL_MANIFEST"
}

write_release_manifest() {
  local bundle_binary="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
  local bundled_privacy="$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
  local bundled_license="$APP_PATH/Contents/Resources/LICENSE"
  local package_name=""
  local package_sha256=""

  if [[ "$PKG_CREATED" -eq 1 ]]; then
    package_name="$(basename "$PKG_PATH")"
    package_sha256="$(shasum -a 256 "$PKG_PATH" | awk '{print $1}')"
  fi

  python3 - "$MANIFEST_PATH" "$APP_NAME" "$EXECUTABLE_NAME" "$BUNDLE_IDENTIFIER" \
    "$MARKETING_VERSION" "$BUILD_NUMBER" "$ARCHITECTURE" "$SOURCE_COMMIT" "$SOURCE_STATE" \
    "$([[ "$SKIP_SIGNING" -eq 1 ]] && printf 'ad-hoc local validation' || printf '%s' "$SIGNING_IDENTITY")" \
    "$(shasum -a 256 "$bundle_binary" | awk '{print $1}')" \
    "$(shasum -a 256 "$bundled_privacy" | awk '{print $1}')" \
    "$(shasum -a 256 "$bundled_license" | awk '{print $1}')" \
    "$(shasum -a 256 "$SYMBOL_MANIFEST" | awk '{print $1}')" \
    "$package_name" "$package_sha256" <<'PY'
import json
import sys

(
    path, app_name, executable, bundle_identifier, version, build, architecture,
    source_commit, source_state, signing_mode, executable_sha256, privacy_sha256,
    license_sha256, symbols_sha256, package_name, package_sha256,
) = sys.argv[1:]
data = {
    "schemaVersion": 1,
    "product": {
        "name": app_name,
        "executable": executable,
        "bundleIdentifier": bundle_identifier,
        "marketingVersion": version,
        "buildNumber": build,
        "architecture": architecture,
    },
    "sourceCommit": source_commit,
    "sourceState": source_state,
    "signingMode": signing_mode,
    "artifacts": {
        "appExecutableSHA256": executable_sha256,
        "privacyManifestSHA256": privacy_sha256,
        "licenseSHA256": license_sha256,
        "symbolManifestSHA256": symbols_sha256,
        "installerPackage": package_name or None,
        "installerPackageSHA256": package_sha256 or None,
    },
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

write_release_checksums() {
  local assets=(
    "$APP_NAME.app/Contents/MacOS/$EXECUTABLE_NAME"
    "$APP_NAME.app/Contents/Resources/PrivacyInfo.xcprivacy"
    "$APP_NAME.app/Contents/Resources/LICENSE"
    "symbols/$MARKETING_VERSION-$BUILD_NUMBER-$ARCHITECTURE/manifest.txt"
    "$(basename "$MANIFEST_PATH")"
  )
  if [[ "$PKG_CREATED" -eq 1 ]]; then
    assets+=("$(basename "$PKG_PATH")")
  fi
  (
    cd "$DIST_DIR"
    shasum -a 256 "${assets[@]}" > "$(basename "$CHECKSUM_PATH")"
    shasum -a 256 -c "$(basename "$CHECKSUM_PATH")" >/dev/null
  )
}

require_tool swift
require_tool sips
require_tool iconutil
require_tool codesign
require_tool plutil
require_tool productbuild
require_tool lipo
require_tool dwarfdump
require_tool shasum
require_tool xcrun
require_tool python3

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]]; then
  SOURCE_STATE="dirty"
fi

if [[ "$SKIP_SIGNING" -eq 0 ]]; then
  [[ "$SOURCE_STATE" == clean ]] || {
    echo "Production App Store signing requires a clean Git worktree so the package matches its source commit." >&2
    exit 3
  }
  maybe_autodetect_identities
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Missing app signing identity. Install/pass an Apple Distribution, Mac App Distribution, or 3rd Party Mac Developer Application identity, or use --skip-signing for local validation." >&2
    exit 3
  fi
  if ! identity_exists "$SIGNING_IDENTITY"; then
    echo "Signing identity not found in keychain: $SIGNING_IDENTITY" >&2
    exit 3
  fi
  require_tool security
  require_tool openssl
  require_tool xcrun
  require_tool pkgutil
  prepare_distribution_signing
fi

guard_release_output_path "$ROOT_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"
guard_release_output_path "$ROOT_DIR" "$DIST_DIR"
if ! mkdir "$OPERATION_LOCK" 2>/dev/null; then
  echo "Another App Store packaging operation is already running for $DIST_DIR." >&2
  exit 7
fi
OPERATION_LOCK_CREATED=1
printf '%s\n' "$$" > "$OPERATION_LOCK/pid"
trap cleanup EXIT
rm -rf "$APP_PATH" "$PKG_PATH" "$SUMMARY_PATH" "$SYMBOLS_DIR"
rm -rf "$ICONSET_DIR"
rm -f \
  "$MANIFEST_PATH" \
  "$CHECKSUM_PATH" \
  "$DIST_DIR/codesign-entitlements.plist" \
  "$DIST_DIR/codesign-details.txt" \
  "$DIST_DIR/spctl-app.txt" \
  "$DIST_DIR/pkg-signature.txt"

echo "==> Building SwiftPM release product"
swift build -c release --arch "$ARCHITECTURE" --package-path "$PACKAGE_DIR" --product "$EXECUTABLE_NAME"

echo "==> Assembling app bundle: $APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$RELEASE_BINARY" "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
chmod 755 "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
validate_binary_minimum_system_version "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
render_info_plist
make_icon
rm -rf "$ICONSET_DIR"
cp "$PRIVACY_MANIFEST" "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT_DIR/LICENSE" "$APP_PATH/Contents/Resources/LICENSE"

if [[ "$SKIP_SIGNING" -eq 0 ]]; then
  cp "$PROVISIONING_PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
fi

if [[ "$SKIP_SIGNING" -eq 1 ]]; then
  echo "==> Ad-hoc signing for local bundle validation"
  codesign --force --sign - --entitlements "$ENTITLEMENTS" --timestamp=none "$APP_PATH"
else
  echo "==> Signing app with: $SIGNING_IDENTITY"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --entitlements "$SIGNING_ENTITLEMENTS" "$APP_PATH"
fi

echo "==> Validating app bundle"
validate_bundle

echo "==> Preserving matching release symbols"
preserve_symbols

PKG_CREATED=0
if [[ "$SKIP_SIGNING" -eq 0 ]]; then
  echo "==> Building signed installer package: $PKG_PATH"
  productbuild --component "$APP_PATH" /Applications --sign "$INSTALLER_IDENTITY" "$PKG_PATH"
  pkgutil --check-signature "$PKG_PATH" > "$DIST_DIR/pkg-signature.txt" 2>&1
  grep -E '(Mac Installer Distribution|3rd Party Mac Developer Installer):' "$DIST_DIR/pkg-signature.txt" >/dev/null
  PKG_CREATED=1
fi

echo "==> Writing source-bound release manifest and checksums"
write_release_manifest
write_release_checksums

cat > "$SUMMARY_PATH" <<SUMMARY
App Store packaging summary
===========================
App: $APP_PATH
Package: $([[ "$PKG_CREATED" -eq 1 ]] && printf '%s' "$PKG_PATH" || printf 'not created')
Bundle ID: $BUNDLE_IDENTIFIER
Version: $MARKETING_VERSION
Build: $BUILD_NUMBER
Architecture: $ARCHITECTURE
Source commit: $SOURCE_COMMIT
Source state: $SOURCE_STATE
Signing mode: $([[ "$SKIP_SIGNING" -eq 1 ]] && printf 'ad-hoc local validation' || printf '%s' "$SIGNING_IDENTITY")
Installer identity: ${INSTALLER_IDENTITY:-not set}
Provisioning profile: ${PROVISIONING_PROFILE:-not embedded}
Entitlements: $ENTITLEMENTS
Symbols: $SYMBOLS_DIR
Symbol manifest: $SYMBOL_MANIFEST
Release manifest: $MANIFEST_PATH
Checksums: $CHECKSUM_PATH

Next steps:
- Install Mac App Store distribution and installer identities if missing.
- Create/register bundle ID $BUNDLE_IDENTIFIER in Apple Developer/App Store Connect.
- Create a Mac App Store provisioning profile for that bundle ID.
- Re-run this script without --skip-signing and with the provisioning profile.
- Upload the resulting signed package with Transporter, Xcode, altool, or App Store Connect API.
SUMMARY

echo "==> Done"
cat "$SUMMARY_PATH"
