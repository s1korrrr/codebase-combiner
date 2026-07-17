#!/usr/bin/env bash
set -euo pipefail

DMG_PATH=""
KEYCHAIN_PROFILE=""
KEYCHAIN_PATH=""
APP_NAME="Codebase Combiner"
RESUME_SUBMISSION_ID=""
WAIT_TIMEOUT="${DEVELOPER_ID_NOTARY_TIMEOUT:-30m}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFIER="$ROOT_DIR/Packaging/DeveloperID/verify_release_artifact.sh"

usage() {
  cat <<'USAGE'
Usage: Packaging/DeveloperID/notarize_release.sh --dmg <path> --keychain-profile <profile> [options]

Options:
  --dmg <path>                   Existing Developer ID-signed DMG.
  --keychain-profile <profile>  notarytool Keychain profile name.
  --keychain <path>             Keychain containing the profile (recommended in CI).
  --app-name <name>             Application name inside the DMG.
  --submission-id <id>          Resume a prior submission without uploading again.
  --timeout <duration>          Bounded notary wait (default: 30m).
  -h, --help                    Show this help.

This command submits to Apple. Run it only after external-action approval.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      [[ $# -ge 2 ]] || { echo "Missing value for --dmg" >&2; exit 2; }
      DMG_PATH="$2"
      shift 2
      ;;
    --keychain-profile)
      [[ $# -ge 2 ]] || { echo "Missing value for --keychain-profile" >&2; exit 2; }
      KEYCHAIN_PROFILE="$2"
      shift 2
      ;;
    --keychain)
      [[ $# -ge 2 ]] || { echo "Missing value for --keychain" >&2; exit 2; }
      KEYCHAIN_PATH="$2"
      shift 2
      ;;
    --app-name)
      [[ $# -ge 2 ]] || { echo "Missing value for --app-name" >&2; exit 2; }
      APP_NAME="$2"
      shift 2
      ;;
    --submission-id)
      [[ $# -ge 2 ]] || { echo "Missing value for --submission-id" >&2; exit 2; }
      RESUME_SUBMISSION_ID="$2"
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 ]] || { echo "Missing value for --timeout" >&2; exit 2; }
      WAIT_TIMEOUT="$2"
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

[[ -n "$DMG_PATH" ]] || { echo "--dmg is required" >&2; exit 2; }
[[ -f "$DMG_PATH" ]] || { echo "DMG not found: $DMG_PATH" >&2; exit 2; }
[[ "$KEYCHAIN_PROFILE" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid or missing Keychain profile name." >&2; exit 2; }
[[ -z "$KEYCHAIN_PATH" || "$KEYCHAIN_PATH" = /* ]] || { echo "--keychain must be an absolute path." >&2; exit 2; }
[[ "$APP_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._\ -]*$ ]] || { echo "Invalid app name." >&2; exit 2; }
[[ -z "$RESUME_SUBMISSION_ID" || "$RESUME_SUBMISSION_ID" =~ ^[A-Za-z0-9-]+$ ]] || { echo "Invalid submission ID." >&2; exit 2; }
[[ "$WAIT_TIMEOUT" =~ ^[1-9][0-9]*[smh]$ ]] || { echo "Invalid timeout. Use a positive value such as 30m." >&2; exit 2; }
[[ -x "$VERIFIER" ]] || { echo "Release verifier is unavailable: $VERIFIER" >&2; exit 1; }

require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 1; }
}

for tool in xcrun python3 shasum; do
  require_tool "$tool"
done

DIST_DIR="$(cd "$(dirname "$DMG_PATH")" && pwd)"
DMG_PATH="$DIST_DIR/$(basename "$DMG_PATH")"
NOTARY_DIR="$DIST_DIR/notarization"
SUBMIT_JSON="$NOTARY_DIR/submission.json"
SUMMARY_JSON="$NOTARY_DIR/summary.json"
FINAL_CHECKSUMS="$DIST_DIR/SHA256SUMS"
MANIFEST_PATH="$DIST_DIR/release-manifest.json"
OPERATION_LOCK="$DIST_DIR/.release-operation.lock"
[[ -f "$MANIFEST_PATH" ]] || { echo "Release manifest not found: $MANIFEST_PATH" >&2; exit 2; }
artifact_names="$(python3 - "$MANIFEST_PATH" <<'PY'
import json
import os
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        manifest = json.load(handle)
    product_name = manifest["product"]["name"]
    artifacts = manifest["artifacts"]
    names = [artifacts["sbom"], artifacts["symbols"]]
    if not isinstance(product_name, str) or not product_name:
        raise ValueError("product name must be a non-empty string")
    if any(not isinstance(name, str) or not name or os.path.basename(name) != name for name in names):
        raise ValueError("artifact names must be non-empty basenames")
    print("\t".join([product_name, *names]))
except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
    print(f"ERROR\t{error}")
PY
)"
IFS=$'\t' read -r manifest_app_name sbom_basename symbols_basename <<< "$artifact_names"
[[ "$manifest_app_name" != ERROR && -n "$manifest_app_name" && -n "$sbom_basename" && -n "$symbols_basename" ]] || {
  echo "Unable to resolve release assets from manifest: ${sbom_basename:-malformed manifest}" >&2
  exit 2
}
[[ "$APP_NAME" == "$manifest_app_name" ]] || {
  echo "Requested app name '$APP_NAME' does not match release manifest product '$manifest_app_name'." >&2
  exit 2
}
SBOM_PATH="$DIST_DIR/$sbom_basename"
SYMBOLS_PATH="$DIST_DIR/$symbols_basename"
[[ -n "$SBOM_PATH" && -f "$SBOM_PATH" ]] || { echo "Release SBOM not found." >&2; exit 2; }
[[ -n "$SYMBOLS_PATH" && -f "$SYMBOLS_PATH" ]] || { echo "Release symbols archive not found." >&2; exit 2; }

if ! mkdir "$OPERATION_LOCK" 2>/dev/null; then
  echo "Another release operation is already running for $DIST_DIR." >&2
  exit 7
fi
printf '%s\n' "$$" > "$OPERATION_LOCK/pid"
trap 'rm -rf "$OPERATION_LOCK"' EXIT

mkdir -p "$NOTARY_DIR"

NOTARY_AUTH=(--keychain-profile "$KEYCHAIN_PROFILE")
if [[ -n "$KEYCHAIN_PATH" ]]; then
  NOTARY_AUTH+=(--keychain "$KEYCHAIN_PATH")
fi

write_resume_command() {
  local submission_id="$1"
  local resume_path="$NOTARY_DIR/resume-command.txt"
  printf 'Packaging/DeveloperID/notarize_release.sh --dmg %q --keychain-profile %q' \
    "$DMG_PATH" "$KEYCHAIN_PROFILE" > "$resume_path"
  printf ' --app-name %q' "$APP_NAME" >> "$resume_path"
  if [[ -n "$KEYCHAIN_PATH" ]]; then
    printf ' --keychain %q' "$KEYCHAIN_PATH" >> "$resume_path"
  fi
  printf ' --timeout %q --submission-id %q\n' "$WAIT_TIMEOUT" "$submission_id" >> "$resume_path"
  echo "$resume_path"
}

parse_response() {
  python3 - "$1" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        response = json.load(handle)
except (OSError, json.JSONDecodeError) as error:
    print(f"ERROR\t{error}")
    raise SystemExit(0)

submission_id = response.get("id")
status = response.get("status")
print(
    f"{submission_id if isinstance(submission_id, str) else ''}\t"
    f"{status if isinstance(status, str) else ''}"
)
PY
}

echo "==> Authenticating signed release candidate before submission"
"$VERIFIER" --dmg "$DMG_PATH" --manifest "$MANIFEST_PATH" --phase pre-submit --signing-mode developer-id

if [[ -n "$RESUME_SUBMISSION_ID" ]]; then
  echo "==> Resuming Apple notarization submission $RESUME_SUBMISSION_ID"
  if ! xcrun notarytool info "$RESUME_SUBMISSION_ID" \
    "${NOTARY_AUTH[@]}" \
    --output-format json > "$SUBMIT_JSON"; then
    echo "Unable to query submission $RESUME_SUBMISSION_ID" >&2
    exit 4
  fi
else
  echo "==> Submitting DMG to Apple notarization"
  set +e
  xcrun notarytool submit "$DMG_PATH" \
    "${NOTARY_AUTH[@]}" \
    --output-format json > "$SUBMIT_JSON"
  submit_status=$?
  set -e
fi

response_line="$(parse_response "$SUBMIT_JSON")"
IFS=$'\t' read -r response_id response_status <<< "$response_line"

if [[ "${response_id:-}" == ERROR || -z "${response_id:-}" ]]; then
  echo "Notarization returned malformed evidence: $SUBMIT_JSON" >&2
  exit 4
fi

if [[ -z "$RESUME_SUBMISSION_ID" && "${submit_status:-0}" -ne 0 ]]; then
  RESUME_PATH="$(write_resume_command "$response_id")"
  echo "Submission interrupted after receiving ID $response_id. Resume command: $RESUME_PATH" >&2
  exit 4
fi

if [[ -z "${response_status:-}" ]]; then
  echo "Notarization returned no status for submission $response_id" >&2
  exit 4
fi

if [[ "$response_status" != Accepted && "$response_status" != Invalid && "$response_status" != Rejected ]]; then
  echo "==> Waiting up to $WAIT_TIMEOUT for submission $response_id"
  if ! xcrun notarytool wait "$response_id" \
    "${NOTARY_AUTH[@]}" \
    --timeout "$WAIT_TIMEOUT" \
    --output-format json > "$SUBMIT_JSON"; then
    RESUME_PATH="$(write_resume_command "$response_id")"
    echo "Submission is still incomplete: $response_id. Resume command: $RESUME_PATH" >&2
    exit 4
  fi
  response_line="$(parse_response "$SUBMIT_JSON")"
  IFS=$'\t' read -r response_id response_status <<< "$response_line"
  if [[ "${response_id:-}" == ERROR || -z "${response_id:-}" || -z "${response_status:-}" ]]; then
    echo "Notarization wait returned malformed evidence: $SUBMIT_JSON" >&2
    exit 4
  fi
fi

SUBMISSION_ID="$response_id"
NOTARY_STATUS="$response_status"
NOTARY_LOG="$NOTARY_DIR/$SUBMISSION_ID-log.json"

if ! xcrun notarytool log "$SUBMISSION_ID" \
  "${NOTARY_AUTH[@]}" \
  "$NOTARY_LOG"; then
  echo "Unable to retrieve notarization log for $SUBMISSION_ID" >&2
  exit 4
fi

if [[ "$NOTARY_STATUS" != Accepted ]]; then
  echo "Notarization status is '$NOTARY_STATUS', not Accepted. Evidence: $NOTARY_LOG" >&2
  exit 4
fi

echo "==> Stapling and validating notarization ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

python3 - "$MANIFEST_PATH" "$SUBMISSION_ID" "$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')" <<'PY'
import json
import sys

path, submission_id, dmg_sha256 = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
data["artifacts"]["dmgSHA256"] = dmg_sha256
data["notarization"] = {
    "status": "Accepted",
    "submissionId": submission_id,
    "ticketStapled": True,
    "gatekeeperPassed": False,
}
temporary = f"{path}.tmp"
with open(temporary, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
import os
os.replace(temporary, path)
PY

echo "==> Verifying stapled DMG and mounted application"
"$VERIFIER" --dmg "$DMG_PATH" --manifest "$MANIFEST_PATH" --phase final --signing-mode developer-id

python3 - "$MANIFEST_PATH" <<'PY'
import json
import os
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
data["notarization"]["gatekeeperPassed"] = True
temporary = f"{path}.tmp"
with open(temporary, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(temporary, path)
PY

python3 - "$SUMMARY_JSON" "$SUBMISSION_ID" "$NOTARY_STATUS" "$(basename "$DMG_PATH")" <<'PY'
import json
import sys

path, submission_id, status, artifact = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "submissionId": submission_id,
            "status": status,
            "artifact": artifact,
            "ticketStapled": True,
            "gatekeeperPassed": True,
        },
        handle,
        indent=2,
        sort_keys=True,
    )
    handle.write("\n")
PY

(
  cd "$DIST_DIR"
  shasum -a 256 \
    "$(basename "$DMG_PATH")" \
    "$(basename "$SBOM_PATH")" \
    "$(basename "$SYMBOLS_PATH")" \
    "$(basename "$MANIFEST_PATH")" \
    "notarization/$(basename "$SUMMARY_JSON")" \
    "notarization/$(basename "$SUBMIT_JSON")" \
    "notarization/$(basename "$NOTARY_LOG")" > "$(basename "$FINAL_CHECKSUMS")"
  shasum -a 256 -c "$(basename "$FINAL_CHECKSUMS")" >/dev/null
)

echo "==> Notarization Accepted, ticket stapled, Gatekeeper passed"
echo "Submission: $SUBMISSION_ID"
echo "Evidence: $NOTARY_DIR"
