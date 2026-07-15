#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VALIDATOR="$ROOT_DIR/Packaging/AppStore/validate_provisioning_profile.py"
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codebase-combiner-profile-tests.XXXXXX")"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

CERTIFICATE_A="$FIXTURE_DIR/certificate-a.der"
CERTIFICATE_B="$FIXTURE_DIR/certificate-b.der"
printf 'certificate-a' > "$CERTIFICATE_A"
printf 'certificate-b' > "$CERTIFICATE_B"
CERTIFICATE_A_BASE64="$(base64 < "$CERTIFICATE_A" | tr -d '[:space:]')"

write_profile() {
  local output="$1"
  local platform="$2"
  local expiration="$3"
  local team_id="$4"
  local application_identifier="$5"
  local sandbox="$6"
  local file_access="$7"

  cat > "$output" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Platform</key>
  <array><string>$platform</string></array>
  <key>ExpirationDate</key>
  <date>$expiration</date>
  <key>TeamIdentifier</key>
  <array><string>$team_id</string></array>
  <key>ApplicationIdentifierPrefix</key>
  <array><string>$team_id</string></array>
  <key>DeveloperCertificates</key>
  <array><data>$CERTIFICATE_A_BASE64</data></array>
  <key>Entitlements</key>
  <dict>
    <key>com.apple.application-identifier</key>
    <string>$application_identifier</string>
    <key>com.apple.developer.team-identifier</key>
    <string>$team_id</string>
    <key>com.apple.security.app-sandbox</key>
    <$sandbox/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <$file_access/>
  </dict>
</dict>
</plist>
PLIST
}

expect_success() {
  local label="$1"
  shift
  if ! output="$("$@" 2>&1)"; then
    echo "FAIL: $label should succeed" >&2
    echo "$output" >&2
    exit 1
  fi
}

expect_failure() {
  local label="$1"
  local expected="$2"
  shift 2
  if output="$("$@" 2>&1)"; then
    echo "FAIL: $label should fail" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected"* ]]; then
    echo "FAIL: $label did not report '$expected'" >&2
    echo "$output" >&2
    exit 1
  fi
}

run_validator() {
  xcrun python3 "$VALIDATOR" \
    --profile-plist "$1" \
    --bundle-id "com.s1korrrr.codebasecombiner" \
    --team-id "TEAM123456" \
    --certificate-der "$2" \
    --entitlements "$ROOT_DIR/Packaging/AppStore/AppStore.entitlements"
}

VALID_PROFILE="$FIXTURE_DIR/valid.plist"
write_profile \
  "$VALID_PROFILE" \
  "OSX" \
  "2099-01-01T00:00:00Z" \
  "TEAM123456" \
  "TEAM123456.com.s1korrrr.codebasecombiner" \
  "true" \
  "true"

expect_success "valid profile" run_validator "$VALID_PROFILE" "$CERTIFICATE_A"

MALFORMED_PROFILE="$FIXTURE_DIR/malformed.plist"
printf 'not a plist' > "$MALFORMED_PROFILE"
expect_failure "malformed profile" "could not be decoded" run_validator "$MALFORMED_PROFILE" "$CERTIFICATE_A"

EXPIRED_PROFILE="$FIXTURE_DIR/expired.plist"
write_profile "$EXPIRED_PROFILE" "OSX" "2000-01-01T00:00:00Z" "TEAM123456" "TEAM123456.com.s1korrrr.codebasecombiner" "true" "true"
expect_failure "expired profile" "expired" run_validator "$EXPIRED_PROFILE" "$CERTIFICATE_A"

IOS_PROFILE="$FIXTURE_DIR/ios.plist"
write_profile "$IOS_PROFILE" "iOS" "2099-01-01T00:00:00Z" "TEAM123456" "TEAM123456.com.s1korrrr.codebasecombiner" "true" "true"
expect_failure "iOS profile" "Mac App Store platform" run_validator "$IOS_PROFILE" "$CERTIFICATE_A"

WRONG_TEAM_PROFILE="$FIXTURE_DIR/wrong-team.plist"
write_profile "$WRONG_TEAM_PROFILE" "OSX" "2099-01-01T00:00:00Z" "OTHERTEAM1" "OTHERTEAM1.com.s1korrrr.codebasecombiner" "true" "true"
expect_failure "wrong team" "Team ID" run_validator "$WRONG_TEAM_PROFILE" "$CERTIFICATE_A"

WRONG_BUNDLE_PROFILE="$FIXTURE_DIR/wrong-bundle.plist"
write_profile "$WRONG_BUNDLE_PROFILE" "OSX" "2099-01-01T00:00:00Z" "TEAM123456" "TEAM123456.com.example.other" "true" "true"
expect_failure "wrong bundle" "bundle identifier" run_validator "$WRONG_BUNDLE_PROFILE" "$CERTIFICATE_A"

NO_SANDBOX_PROFILE="$FIXTURE_DIR/no-sandbox.plist"
write_profile "$NO_SANDBOX_PROFILE" "OSX" "2099-01-01T00:00:00Z" "TEAM123456" "TEAM123456.com.s1korrrr.codebasecombiner" "false" "true"
expect_failure "missing sandbox" "app sandbox" run_validator "$NO_SANDBOX_PROFILE" "$CERTIFICATE_A"

NO_FILE_ACCESS_PROFILE="$FIXTURE_DIR/no-file-access.plist"
write_profile "$NO_FILE_ACCESS_PROFILE" "OSX" "2099-01-01T00:00:00Z" "TEAM123456" "TEAM123456.com.s1korrrr.codebasecombiner" "true" "false"
expect_failure "missing user-selected file access" "user-selected file" run_validator "$NO_FILE_ACCESS_PROFILE" "$CERTIFICATE_A"

expect_failure "certificate mismatch" "signing certificate" run_validator "$VALID_PROFILE" "$CERTIFICATE_B"

if ! grep -F 'validate_provisioning_profile.py' "$ROOT_DIR/Packaging/AppStore/build_app_store_package.sh" >/dev/null; then
  echo "FAIL: packaging script does not invoke the profile validator" >&2
  exit 1
fi
if grep -E 'pkgutil --check-signature .*\|\| true' "$ROOT_DIR/Packaging/AppStore/build_app_store_package.sh" >/dev/null; then
  echo "FAIL: package signature failures must not be swallowed" >&2
  exit 1
fi
if ! grep -F 'swift build -c release --arch "$ARCHITECTURE"' "$ROOT_DIR/Packaging/AppStore/build_app_store_package.sh" >/dev/null; then
  echo "FAIL: packaging must build the declared release architecture deterministically" >&2
  exit 1
fi
if ! grep -F 'dwarfdump --uuid' "$ROOT_DIR/Packaging/AppStore/build_app_store_package.sh" >/dev/null; then
  echo "FAIL: packaging must preserve and verify matching release symbols" >&2
  exit 1
fi
if ! grep -F 'security cms -D -u 9' "$ROOT_DIR/Packaging/AppStore/build_app_store_package.sh" >/dev/null; then
  echo "FAIL: provisioning profiles must use the protected-object signer trust policy" >&2
  exit 1
fi
if ! grep -F 'Installer certificate Team ID' "$ROOT_DIR/Packaging/AppStore/build_app_store_package.sh" >/dev/null; then
  echo "FAIL: installer identity must be bound to the app signing Team ID" >&2
  exit 1
fi

expect_invalid_package_input() {
  local label="$1"
  local variable="$2"
  local value="$3"
  local sentinel="$ROOT_DIR/dist/release-hardening-sentinel"
  mkdir -p "$(dirname "$sentinel")"
  printf 'preserve-me' > "$sentinel"
  if output="$(env "$variable=$value" "$ROOT_DIR/Packaging/AppStore/build_app_store_package.sh" --skip-signing 2>&1)"; then
    echo "FAIL: $label should be rejected" >&2
    exit 1
  fi
  if [[ "$output" != *"Invalid release metadata"* ]]; then
    echo "FAIL: $label did not produce the release metadata error" >&2
    echo "$output" >&2
    exit 1
  fi
  [[ "$(cat "$sentinel")" == "preserve-me" ]] || {
    echo "FAIL: $label mutated files before validation" >&2
    exit 1
  }
  rm -f "$sentinel"
}

expect_invalid_package_input "traversal app name" APPSTORE_APP_NAME "../outside"
expect_invalid_package_input "traversal executable" APPSTORE_EXECUTABLE_NAME "../../outside"
expect_invalid_package_input "traversal version" APPSTORE_MARKETING_VERSION "../../outside"
expect_invalid_package_input "invalid build number" APPSTORE_BUILD_NUMBER "1/../../outside"
expect_invalid_package_input "invalid architecture" APPSTORE_ARCHITECTURE "../../outside"

echo "provisioning-profile and signed-package contracts passed"
