#!/usr/bin/env python3
"""Fail-closed validation for a decoded Mac App Store provisioning profile."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import plistlib
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise ValueError(message)


def load_plist(path: Path, label: str) -> dict:
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        fail(f"{label} could not be decoded: {error}")
    if not isinstance(value, dict):
        fail(f"{label} root is not a dictionary")
    return value


def normalized_datetime(value: object) -> dt.datetime:
    if not isinstance(value, dt.datetime):
        fail("expiration date is missing or invalid")
    if value.tzinfo is None:
        return value.replace(tzinfo=dt.timezone.utc)
    return value.astimezone(dt.timezone.utc)


def require_true(entitlements: dict, key: str, label: str) -> None:
    if entitlements.get(key) is not True:
        fail(f"profile does not authorize {label}")


def validate(args: argparse.Namespace) -> None:
    profile_path = Path(args.profile_plist)
    certificate_path = Path(args.certificate_der)
    entitlements_path = Path(args.entitlements)

    profile = load_plist(profile_path, "provisioning profile")
    requested_entitlements = load_plist(entitlements_path, "repository entitlements")

    platforms = profile.get("Platform")
    if not isinstance(platforms, list) or "OSX" not in platforms:
        fail("profile is not for the Mac App Store platform (OSX)")

    expiration = normalized_datetime(profile.get("ExpirationDate"))
    if expiration <= dt.datetime.now(dt.timezone.utc):
        fail(f"profile expired at {expiration.isoformat()}")

    team_identifiers = profile.get("TeamIdentifier")
    if not isinstance(team_identifiers, list) or args.team_id not in team_identifiers:
        fail(f"profile Team ID does not match {args.team_id}")

    profile_entitlements = profile.get("Entitlements")
    if not isinstance(profile_entitlements, dict):
        fail("profile entitlements are missing")

    entitlement_team = profile_entitlements.get("com.apple.developer.team-identifier")
    if entitlement_team != args.team_id:
        fail(f"profile entitlement Team ID does not match {args.team_id}")

    prefixes = profile.get("ApplicationIdentifierPrefix")
    if not isinstance(prefixes, list) or not all(isinstance(prefix, str) for prefix in prefixes):
        fail("profile application-identifier prefix is missing")
    permitted_identifiers = {f"{prefix}.{args.bundle_id}" for prefix in prefixes}
    application_identifier = profile_entitlements.get("com.apple.application-identifier")
    if application_identifier is None:
        application_identifier = profile_entitlements.get("application-identifier")
    if application_identifier not in permitted_identifiers:
        fail(f"profile bundle identifier does not match {args.bundle_id}")

    require_true(profile_entitlements, "com.apple.security.app-sandbox", "the app sandbox")
    require_true(
        profile_entitlements,
        "com.apple.security.files.user-selected.read-write",
        "user-selected file read/write access",
    )

    for entitlement_key, entitlement_value in requested_entitlements.items():
        if entitlement_value is True and profile_entitlements.get(entitlement_key) is not True:
            fail(f"profile does not authorize requested entitlement {entitlement_key}")

    try:
        selected_certificate = certificate_path.read_bytes()
    except OSError as error:
        fail(f"selected signing certificate could not be read: {error}")
    if not selected_certificate:
        fail("selected signing certificate is empty")

    profile_certificates = profile.get("DeveloperCertificates")
    if not isinstance(profile_certificates, list) or not any(
        isinstance(certificate, bytes) and certificate == selected_certificate
        for certificate in profile_certificates
    ):
        fail("selected signing certificate is not included in the provisioning profile")

    certificate_digest = hashlib.sha256(selected_certificate).hexdigest()
    if args.output_entitlements:
        signing_entitlements = dict(requested_entitlements)
        signing_entitlements["com.apple.application-identifier"] = application_identifier
        signing_entitlements["com.apple.developer.team-identifier"] = args.team_id
        try:
            with Path(args.output_entitlements).open("wb") as handle:
                plistlib.dump(signing_entitlements, handle, fmt=plistlib.FMT_XML, sort_keys=True)
        except OSError as error:
            fail(f"distribution entitlements could not be written: {error}")

    print(
        "Provisioning profile valid: "
        f"bundle={args.bundle_id} team={args.team_id} "
        f"expires={expiration.date().isoformat()} certificate_sha256={certificate_digest}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile-plist", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--certificate-der", required=True)
    parser.add_argument("--entitlements", required=True)
    parser.add_argument("--output-entitlements")
    return parser.parse_args()


def main() -> int:
    try:
        validate(parse_args())
    except ValueError as error:
        print(f"Invalid provisioning profile: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
