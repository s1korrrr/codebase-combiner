#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

required_files=(
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

grep -F 'security/advisories/new' SECURITY.md >/dev/null
if grep -Ei 'open (a )?(public )?(GitHub )?issue|public issue|issue titled' SECURITY.md CODE_OF_CONDUCT.md; then
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
grep -F 'local login-Keychain identity must never be exported for CI' RELEASING.md >/dev/null

grep -F 'permissions:' .github/workflows/ci.yml >/dev/null
grep -F 'contents: read' .github/workflows/ci.yml >/dev/null
grep -F 'timeout-minutes:' .github/workflows/ci.yml >/dev/null
grep -F 'concurrency:' .github/workflows/ci.yml >/dev/null
grep -F 'npm audit signatures' .github/workflows/ci.yml >/dev/null
grep -F 'Packaging/DeveloperID/tests/run_tests.sh' .github/workflows/ci.yml >/dev/null

grep -F 'environment: release' .github/workflows/release.yml >/dev/null
grep -F "vars.CI_SIGNING_PROVISIONED == 'true'" .github/workflows/release.yml >/dev/null
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
grep -F 'dist/developer-id/notarization/submission.json' .github/workflows/release.yml >/dev/null
grep -F 'release-assets/notarization/submission.json' .github/workflows/release.yml >/dev/null
grep -F 'DEVELOPER_ID_SOURCE_TAG' .github/workflows/release.yml >/dev/null
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

echo "Open-source release repository contract passed"
