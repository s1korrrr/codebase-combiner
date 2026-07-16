#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$TEST_DIR/build_release_contract_test.sh"
bash "$TEST_DIR/notarize_release_contract_test.sh"

echo "Developer ID release contracts passed"
