#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/SwiftExplorerApp"
PACKAGING_DIR="$ROOT_DIR/Packaging/AppStore"
DIST_DIR="$ROOT_DIR/dist/app-store"
APP_NAME="${APPSTORE_APP_NAME:-Codebase Combiner}"
EXECUTABLE_NAME="${APPSTORE_EXECUTABLE_NAME:-CodebaseExplorerApp}"
BUNDLE_IDENTIFIER="${APPSTORE_BUNDLE_ID:-com.s1korrrr.codebasecombiner}"
MARKETING_VERSION="${APPSTORE_MARKETING_VERSION:-0.1.0}"
BUILD_NUMBER="${APPSTORE_BUILD_NUMBER:-1}"
MINIMUM_SYSTEM_VERSION="${APPSTORE_MINIMUM_SYSTEM_VERSION:-13.0}"
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
  --signing-identity <identity>          App signing identity.
  --installer-identity <identity>        Installer/package signing identity.
  --provisioning-profile <path>          Mac App Store provisioning profile.
  -h, --help                             Show this help.

Environment overrides:
  APPSTORE_BUNDLE_ID, APPSTORE_MARKETING_VERSION, APPSTORE_BUILD_NUMBER,
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
      BUNDLE_IDENTIFIER="$2"
      shift 2
      ;;
    --version)
      MARKETING_VERSION="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --signing-identity)
      SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --installer-identity)
      INSTALLER_IDENTITY="$2"
      shift 2
      ;;
    --provisioning-profile)
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

APP_PATH="$DIST_DIR/$APP_NAME.app"
PKG_PATH="$DIST_DIR/${APP_NAME// /}-AppStore.pkg"
SUMMARY_PATH="$DIST_DIR/${APP_NAME// /}-AppStore-summary.txt"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
RELEASE_BINARY="$PACKAGE_DIR/.build/release/$EXECUTABLE_NAME"
ENTITLEMENTS="$PACKAGING_DIR/AppStore.entitlements"
INFO_TEMPLATE="$PACKAGING_DIR/Info.plist.in"
PRIVACY_MANIFEST="$PACKAGING_DIR/PrivacyInfo.xcprivacy"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
ICON_SOURCE="$ROOT_DIR/assets/icon.jpg"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
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

maybe_autodetect_identities() {
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -p codesigning -v | sed -n 's/.*"\(Apple Distribution:.*\)".*/\1/p; s/.*"\(Mac App Distribution:.*\)".*/\1/p; s/.*"\(3rd Party Mac Developer Application:.*\)".*/\1/p' | head -n 1)"
  fi
  if [[ -z "$INSTALLER_IDENTITY" ]]; then
    INSTALLER_IDENTITY="$(security find-identity -p basic -v 2>/dev/null | sed -n 's/.*"\(3rd Party Mac Developer Installer:.*\)".*/\1/p; s/.*"\(Mac Installer Distribution:.*\)".*/\1/p' | head -n 1)"
  fi
}

validate_bundle() {
  plutil -lint "$INFO_PLIST"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  codesign -dvvv --entitlements :- "$APP_PATH" > "$DIST_DIR/codesign-entitlements.txt" 2>&1 || true
  spctl -a -vv "$APP_PATH" > "$DIST_DIR/spctl-app.txt" 2>&1 || true
}

require_tool swift
require_tool sips
require_tool iconutil
require_tool codesign
require_tool plutil
require_tool productbuild

if [[ "$SKIP_SIGNING" -eq 0 ]]; then
  maybe_autodetect_identities
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Missing app signing identity. Install/pass an Apple Distribution, Mac App Distribution, or 3rd Party Mac Developer Application identity, or use --skip-signing for local validation." >&2
    exit 3
  fi
  if ! identity_exists "$SIGNING_IDENTITY"; then
    echo "Signing identity not found in keychain: $SIGNING_IDENTITY" >&2
    exit 3
  fi
fi

mkdir -p "$DIST_DIR"
rm -rf "$APP_PATH" "$PKG_PATH" "$SUMMARY_PATH"

echo "==> Building SwiftPM release product"
swift build -c release --package-path "$PACKAGE_DIR" --product "$EXECUTABLE_NAME"

echo "==> Assembling app bundle: $APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$RELEASE_BINARY" "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
chmod 755 "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
render_info_plist
make_icon
cp "$PRIVACY_MANIFEST" "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"

if [[ -n "$PROVISIONING_PROFILE" ]]; then
  if [[ ! -f "$PROVISIONING_PROFILE" ]]; then
    echo "Provisioning profile not found: $PROVISIONING_PROFILE" >&2
    exit 1
  fi
  cp "$PROVISIONING_PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
fi

if [[ "$SKIP_SIGNING" -eq 1 ]]; then
  echo "==> Ad-hoc signing for local bundle validation"
  codesign --force --sign - --entitlements "$ENTITLEMENTS" --timestamp=none "$APP_PATH"
else
  if [[ -z "$PROVISIONING_PROFILE" ]]; then
    echo "Warning: no provisioning profile supplied. Mac App Store upload usually requires an embedded Mac App Store provisioning profile." >&2
  fi
  echo "==> Signing app with: $SIGNING_IDENTITY"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH"
fi

echo "==> Validating app bundle"
validate_bundle

PKG_CREATED=0
if [[ "$SKIP_SIGNING" -eq 0 && -n "$INSTALLER_IDENTITY" ]]; then
  echo "==> Building signed installer package: $PKG_PATH"
  productbuild --component "$APP_PATH" /Applications --sign "$INSTALLER_IDENTITY" "$PKG_PATH"
  pkgutil --check-signature "$PKG_PATH" > "$DIST_DIR/pkg-signature.txt" 2>&1 || true
  PKG_CREATED=1
elif [[ "$SKIP_SIGNING" -eq 0 ]]; then
  echo "Warning: installer identity missing; signed .pkg was not created." >&2
fi

cat > "$SUMMARY_PATH" <<SUMMARY
App Store packaging summary
===========================
App: $APP_PATH
Package: $([[ "$PKG_CREATED" -eq 1 ]] && printf '%s' "$PKG_PATH" || printf 'not created')
Bundle ID: $BUNDLE_IDENTIFIER
Version: $MARKETING_VERSION
Build: $BUILD_NUMBER
Signing mode: $([[ "$SKIP_SIGNING" -eq 1 ]] && printf 'ad-hoc local validation' || printf '%s' "$SIGNING_IDENTITY")
Installer identity: ${INSTALLER_IDENTITY:-not set}
Provisioning profile: ${PROVISIONING_PROFILE:-not embedded}
Entitlements: $ENTITLEMENTS

Next steps:
- Install Mac App Store distribution and installer identities if missing.
- Create/register bundle ID $BUNDLE_IDENTIFIER in Apple Developer/App Store Connect.
- Create a Mac App Store provisioning profile for that bundle ID.
- Re-run this script without --skip-signing and with the provisioning profile.
- Upload the resulting signed package with Transporter, Xcode, altool, or App Store Connect API.
SUMMARY

echo "==> Done"
cat "$SUMMARY_PATH"
