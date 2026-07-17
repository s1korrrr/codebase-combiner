# Mac App Store Packaging

This folder contains the Mac App Store packaging path for the SwiftPM macOS app.

## Defaults

- App name: `Codebase Combiner`
- Bundle ID: `com.s1korrrr.codebasecombiner`
- Version: `0.1.0`
- Build: `1`
- Minimum macOS: `13.0`
- Architecture: Apple silicon (`arm64`). Intel Macs are not included in this release artifact.
- Category: `public.app-category.developer-tools`
- Entitlements: App Sandbox plus user-selected file read/write access.
- Privacy manifest: declares no tracking or collected data, UserDefaults access for app settings, and file-timestamp access for user-selected files and app-container metadata.

## Local validation

Build an unsigned/ad-hoc sandboxed app bundle:

```sh
Packaging/AppStore/build_app_store_package.sh --skip-signing
```

Output:

- `dist/app-store/Codebase Combiner.app`
- `dist/app-store/CodebaseCombiner-AppStore-summary.txt`
- `dist/app-store/symbols/0.1.0-1-arm64/` with a UUID-checked dSYM and SHA-256 manifest
- `dist/app-store/release-manifest.json` with source, product, signing-mode, and artifact identities
- `dist/app-store/SHA256SUMS` covering the executable, privacy manifest, bundled license, symbols manifest, release manifest, and signed installer when present

## App Store signing

Install the Apple signing assets first:

- Mac App Distribution / Apple Distribution certificate for the app binary.
- Mac Installer Distribution / 3rd Party Mac Developer Installer certificate for the `.pkg`.
- A Mac App Store provisioning profile for bundle ID `com.s1korrrr.codebasecombiner`.

Then run:

```sh
Packaging/AppStore/build_app_store_package.sh \
  --signing-identity "Apple Distribution: <Name> (<TEAMID>)" \
  --installer-identity "3rd Party Mac Developer Installer: <Name> (<TEAMID>)" \
  --provisioning-profile "/path/to/profile.provisionprofile"
```

Before it builds, the signed path decodes and validates the profile's CMS payload, platform, expiration, Team ID, exact bundle identifier, required entitlements, and inclusion of the selected signing certificate. It stops without producing a package if any check fails. The final package signature is also a fail-closed gate.

Override `--architecture` only when intentionally producing and separately testing another architecture. The default and currently verified release is `arm64`.

The script also accepts environment variables:

```sh
APPSTORE_BUNDLE_ID=com.s1korrrr.codebasecombiner
APPSTORE_MARKETING_VERSION=0.1.0
APPSTORE_BUILD_NUMBER=1
APPSTORE_SIGNING_IDENTITY="Apple Distribution: <Name> (<TEAMID>)"
APPSTORE_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: <Name> (<TEAMID>)"
APPSTORE_PROVISIONING_PROFILE="/path/to/profile.provisionprofile"
```

## Upload

After a signed package is created and independently validated, upload it through Apple Transporter, Xcode Organizer, or the App Store Connect API.

Before submission, validate sandboxed behavior by launching the packaged app and checking:

- choose workspace folder
- scan selected folder
- change include/exclude filters
- copy combined output
- save combined output to a user-selected location
- open Settings
- open Support link

## Current local blocker

This repository can create and validate an ad-hoc `.app` bundle locally. Final Mac App Store packaging is blocked until a non-expired provisioning profile matching `com.s1korrrr.codebasecombiner`, the installed distribution certificate, and the required entitlements is available.
