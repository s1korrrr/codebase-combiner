#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

required_files=(
  LICENSE
  NOTICE
  RELEASING.md
  THIRD_PARTY_NOTICES.md
  .github/dependabot.yml
  .github/workflows/codeql.yml
  .github/workflows/release.yml
  script/tests/vsix_inventory_test.sh
)
for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || { echo "Missing open-source release file: $file" >&2; exit 1; }
done

grep -F 'Apache License' LICENSE >/dev/null
grep -F 'Version 2.0' LICENSE >/dev/null
grep -F 'Copyright 2026 Rafal Sikora' NOTICE >/dev/null
grep -F 'RSI Tech' NOTICE >/dev/null
grep -F 'info@rsitech.ai' SECURITY.md >/dev/null
grep -F 'info@rsitech.ai' CODE_OF_CONDUCT.md >/dev/null
grep -F 'info@rsitech.ai' docs/support.md >/dev/null
grep -F 'RSI Tech' docs/support.md >/dev/null
grep -F '/security/policy' .github/ISSUE_TEMPLATE/config.yml >/dev/null
if grep -F 'security/advisories/new' SECURITY.md docs/support.md .github/ISSUE_TEMPLATE/config.yml; then
  echo "Security guidance must not advertise a disabled private-reporting endpoint." >&2
  exit 1
fi
if grep -F 'private-reporting instructions' docs/support.md; then
  echo "Support guidance must not claim that unavailable private-reporting instructions exist." >&2
  exit 1
fi
if grep -Ei 'open (a )?(public )?(GitHub )?issue|issue titled' SECURITY.md CODE_OF_CONDUCT.md; then
  echo "Sensitive reports must not use a public issue fallback." >&2
  exit 1
fi

for pattern in '*.p12' 'AuthKey_*.p8' '*.keychain-db' '.env.*' '*.dmg' '*.xcarchive'; do
  grep -F "$pattern" .gitignore >/dev/null || { echo "Missing secret/artifact ignore: $pattern" >&2; exit 1; }
done

grep -E 'minimatch[[:space:]]*\|[[:space:]]*9[.]0[.]9[[:space:]]*\|[[:space:]]*ISC' THIRD_PARTY_NOTICES.md >/dev/null
grep -E 'brace-expansion[[:space:]]*\|[[:space:]]*2[.]1[.]2[[:space:]]*\|[[:space:]]*MIT' THIRD_PARTY_NOTICES.md >/dev/null
grep -E 'balanced-match[[:space:]]*\|[[:space:]]*1[.]0[.]2[[:space:]]*\|[[:space:]]*MIT' THIRD_PARTY_NOTICES.md >/dev/null
grep -F 'macos-v0.1.0' RELEASING.md >/dev/null
grep -F 'Developer ID Application' RELEASING.md >/dev/null
grep -F 'clean standard macOS account' RELEASING.md >/dev/null
grep -F 'must never be exported' RELEASING.md >/dev/null

grep -F 'permissions:' .github/workflows/ci.yml >/dev/null
grep -F 'contents: read' .github/workflows/ci.yml >/dev/null
grep -F 'timeout-minutes:' .github/workflows/ci.yml >/dev/null
grep -F 'concurrency:' .github/workflows/ci.yml >/dev/null
grep -F 'npm audit signatures' .github/workflows/ci.yml >/dev/null
grep -F 'Packaging/DeveloperID/tests/run_tests.sh' .github/workflows/ci.yml >/dev/null
grep -F -- '--disable redundantSendable' .swiftformat >/dev/null
for swiftformat_doc in README.md INSTALL.md CONTRIBUTING.md; do
  grep -F 'SwiftFormat 0.61.1' "$swiftformat_doc" >/dev/null || {
    echo "SwiftFormat version is not pinned in $swiftformat_doc" >&2
    exit 1
  }
done

for privacy_manifest in Packaging/AppStore/PrivacyInfo.xcprivacy Packaging/DeveloperID/PrivacyInfo.xcprivacy; do
  plutil -lint "$privacy_manifest" >/dev/null
  grep -F 'NSPrivacyAccessedAPICategoryFileTimestamp' "$privacy_manifest" >/dev/null
  grep -F '<string>3B52.1</string>' "$privacy_manifest" >/dev/null
  grep -F '<string>C617.1</string>' "$privacy_manifest" >/dev/null
done

grep -F 'cp "$ROOT_DIR/LICENSE" "$APP_PATH/Contents/Resources/LICENSE"' Packaging/AppStore/build_app_store_package.sh >/dev/null
grep -F 'cp "$ROOT_DIR/NOTICE" "$APP_PATH/Contents/Resources/NOTICE"' Packaging/AppStore/build_app_store_package.sh >/dev/null
grep -F 'cp "$ROOT_DIR/NOTICE" "$APP_PATH/Contents/Resources/NOTICE"' Packaging/DeveloperID/build_release.sh >/dev/null
grep -F '"$APP_NAME.app/Contents/Resources/NOTICE"' Packaging/AppStore/build_app_store_package.sh >/dev/null
grep -F 'release-manifest.json' Packaging/AppStore/build_app_store_package.sh >/dev/null
grep -F 'SHA256SUMS' Packaging/AppStore/build_app_store_package.sh >/dev/null
grep -F '.app-store-operation.lock' Packaging/AppStore/build_app_store_package.sh >/dev/null
grep -F '"$DIST_DIR/pkg-signature.txt"' Packaging/AppStore/build_app_store_package.sh >/dev/null
grep -F '"$DIST_DIR/codesign-entitlements.plist"' Packaging/AppStore/build_app_store_package.sh >/dev/null
grep -F 'umask 077' .github/workflows/release.yml >/dev/null
grep -F 'chmod 600 "$certificate"' .github/workflows/release.yml >/dev/null
grep -F 'rm -f "$certificate"' .github/workflows/release.yml >/dev/null
test "$(grep -c 'umask 077' .github/workflows/release.yml)" -ge 2
grep -F 'RELEASE_KEYCHAIN=$RUNNER_TEMP/release.keychain-db' .github/workflows/release.yml >/dev/null
python3 - <<'PY'
from pathlib import Path

workflow = Path('.github/workflows/release.yml').read_text(encoding='utf-8')
required_order = [
    'security import "$certificate"',
    'rm -f "$certificate"',
    'Packaging/DeveloperID/notarize_release.sh',
    '- name: Remove signing credentials after notarization',
    'run: security delete-keychain "$RELEASE_KEYCHAIN"',
    '- name: Attest every published release subject',
]
positions = [workflow.index(marker) for marker in required_order]
if positions != sorted(positions):
    raise SystemExit('Release credentials are not removed at the earliest safe point.')
PY

grep -F 'environment: release' .github/workflows/release.yml >/dev/null
grep -F 'Release signing is not provisioned' .github/workflows/release.yml >/dev/null
if grep -F "if: \${{ vars.CI_SIGNING_PROVISIONED == 'true' }}" .github/workflows/release.yml; then
  echo "A release tag must fail explicitly when signing is not provisioned." >&2
  exit 1
fi
grep -F 'CI_DEVELOPER_ID_CERTIFICATE_SHA256' .github/workflows/release.yml >/dev/null
grep -F 'LOCAL_DEVELOPER_ID_CERTIFICATE_SHA256' .github/workflows/release.yml >/dev/null
grep -F 'draft' .github/workflows/release.yml >/dev/null
grep -F 'Packaging/DeveloperID/notarize_release.sh' .github/workflows/release.yml >/dev/null
grep -F -- '--keychain "$RELEASE_KEYCHAIN"' .github/workflows/release.yml >/dev/null
grep -F 'git/tags/' .github/workflows/release.yml >/dev/null
grep -F 'verification.verified' .github/workflows/release.yml >/dev/null
grep -F 'origin/main' .github/workflows/release.yml >/dev/null
grep -F 'check-runs' .github/workflows/release.yml >/dev/null
grep -F 'symbols.zip' .github/workflows/release.yml >/dev/null
grep -F 'docs/release/$version/RELEASE_NOTES.md' .github/workflows/release.yml >/dev/null
grep -F 'dist/developer-id/SHA256SUMS' .github/workflows/release.yml >/dev/null
grep -F 'dist/developer-id/notarization-submission.json' .github/workflows/release.yml >/dev/null
grep -F 'release-assets/notarization-submission.json' .github/workflows/release.yml >/dev/null
grep -F 'DEVELOPER_ID_SOURCE_TAG' .github/workflows/release.yml >/dev/null
if grep -E '\$\{[^}]+\^\^\}' .github/workflows/release.yml; then
  echo "The macOS release workflow uses Bash-4-only uppercase expansion." >&2
  exit 1
fi
grep -F '"licenses": [{"license": {"id": "Apache-2.0"}}]' Packaging/DeveloperID/build_release.sh >/dev/null
grep -F 'Licensed under the Apache License 2.0.' Packaging/DeveloperID/Info.plist.in >/dev/null
grep -F 'Licensed under the Apache License 2.0.' Packaging/AppStore/Info.plist.in >/dev/null
grep -F '[[ "${SOURCE_TAG#macos-v}" == "$MARKETING_VERSION" ]]' Packaging/DeveloperID/build_release.sh >/dev/null
grep -F '[[ "${SOURCE_TAG#macos-v}" == "$MARKETING_VERSION" ]]' Packaging/DeveloperID/verify_release_artifact.sh >/dev/null
for release_doc in Packaging/DeveloperID/README.md RELEASING.md; do
  grep -F 'DEVELOPER_ID_SOURCE_TAG=macos-v0.1.0' "$release_doc" >/dev/null || {
    echo "Production release command is missing its source tag in $release_doc" >&2
    exit 1
  }
done
if grep -F 'pull_request:' .github/workflows/release.yml; then
  echo "Release signing must never run on pull requests." >&2
  exit 1
fi

while IFS= read -r use; do
  [[ "$use" =~ @([0-9a-f]{40})([[:space:]]*#.*)?$ ]] || {
    echo "GitHub Action is not pinned to a full commit SHA: $use" >&2
    exit 1
  }
done < <(grep -RhE '^[[:space:]]*-[[:space:]]+uses:' .github/workflows)

grep -F 'node_modules/**/.tap/**' .vscodeignore >/dev/null
grep -F 'node_modules/**/.github/**' .vscodeignore >/dev/null
grep -F 'node_modules/**/*.map' .vscodeignore >/dev/null
grep -F 'node_modules/**/*.d.ts' .vscodeignore >/dev/null
grep -F '.worktrees/**' .vscodeignore >/dev/null

expected_vsix="$ROOT_DIR/codebase-combiner-$(node -p 'require("./package.json").version').vsix"
test -f "$expected_vsix"
stale_seed="$(mktemp "$ROOT_DIR/.vsix-inventory-contract.XXXXXX")"
stale_candidate="${stale_seed}.vsix"
if [[ -e "$stale_candidate" ]]; then
  rm -f "$stale_seed"
  echo "Unable to allocate a collision-safe stale VSIX fixture." >&2
  exit 1
fi
stale_vsix="$stale_candidate"
cleanup_stale_vsix() {
  rm -f "$stale_seed" "$stale_vsix"
}
trap cleanup_stale_vsix EXIT
mv "$stale_seed" "$stale_vsix"
cp "$expected_vsix" "$stale_vsix"
if script/tests/vsix_inventory_test.sh >/dev/null 2>&1; then
  echo "VSIX inventory accepted an ambiguous stale root artifact." >&2
  exit 1
fi
cleanup_stale_vsix
trap - EXIT

test "$(sips -g format assets/icon.png | awk '/format:/ {print $2}')" = png
grep -F 'No macOS 0.1.0 release is currently published.' README.md >/dev/null
grep -F 'runtime support at the macOS 13 floor remains unverified' docs/release/0.1.0/RELEASE_NOTES.md >/dev/null
grep -F '## [0.1.0] - Release candidate' CHANGELOG.md >/dev/null
grep -F 'Effective date: July 20, 2026' docs/privacy-policy.md >/dev/null
grep -F 'Removing the app does not guarantee that macOS removes this local data.' docs/privacy-policy.md >/dev/null

echo "Open-source release repository contract passed"
