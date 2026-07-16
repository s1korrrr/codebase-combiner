# Codebase Combiner — Installation Guide

This repo contains two deliverables:

- VS Code extension (Node/JavaScript): `extension.js`, `package.json`
- macOS SwiftUI app (SwiftPM): `SwiftExplorerApp/`

## Prerequisites

- macOS 13 or newer.
- Xcode Command Line Tools (for `swift`); install with:
  ```sh
  xcode-select --install
  ```
- Swift 6.0+ (`swift --version` should show a 6.x toolchain).
- Node.js 20+ and npm (for the VS Code extension packaging toolchain).

## Install an official macOS release

After an official release is published, download the DMG and `SHA256SUMS` from the same [GitHub Release](https://github.com/s1korrrr/codebase-combiner/releases). The planned 0.1.0 package is Apple silicon (`arm64`) and declares a macOS 13 deployment target. Runtime support is not considered proven until the direct-distribution checklist contains a successful macOS 13 clean-account smoke.

Verify the download:

```sh
shasum -a 256 -c SHA256SUMS
```

Open `Codebase-Combiner-<version>-arm64.dmg`, drag **Codebase Combiner** to `/Applications`, and launch it normally from Finder. The official artifact is signed with Apple Developer ID and notarized; do not remove quarantine attributes or bypass Gatekeeper. If verification fails, delete the artifact and report it through `SECURITY.md`.

## VS Code extension (Node/JavaScript)

Install dependencies:

```sh
npm install
```

Run tests:

```sh
npm test
```

Lint:

```sh
npm run lint
```

Format:

```sh
npm run format
```

Package a VSIX:

```sh
npm run package
```

## Build and Run (recommended)

From the repository root, build the local app bundle and verify launch:

```sh
./script/build_and_run.sh --verify
```

For direct SwiftPM development:

1. Open Terminal and `cd` to the app directory:
   ```sh
   cd SwiftExplorerApp
   ```
2. Build and launch:
   ```sh
   swift run
   ```
   The SwiftUI window opens. Pick a folder, review the structured scan summary, adjust filters, select files, then copy or save the combined prompt.

The app targets macOS 13. Newer presentation is availability-gated; the current verified toolchain is Xcode 26.6 with the macOS 26.5 SDK. A macOS 27 host does not add macOS 27 SDK-only symbols to that build.

## Run an existing build

If you've already built once:

```sh
cd SwiftExplorerApp
.build/debug/CodebaseExplorerApp
```

or open it without keeping Terminal in the foreground:

```sh
open .build/debug/CodebaseExplorerApp
```

## Clean rebuild (if needed)

```sh
cd SwiftExplorerApp
swift clean
swift build
```

## Run Swift tests

```sh
cd SwiftExplorerApp
swift test
```

## Swift formatting (SwiftFormat)

Install SwiftFormat (macOS):

```sh
brew install swiftformat
```

Then run:

```sh
swiftformat .
```

## Create a local direct-distribution bundle

For local structural validation without distribution credentials:

```sh
Packaging/DeveloperID/build_release.sh --skip-signing
open "dist/developer-id/Codebase Combiner.app"
```

This creates a sandbox-entitled, ad-hoc signed app and DMG for local validation only. It is not a public distributable. The default package is Apple silicon (`arm64`) only and includes a UUID-matched dSYM under `dist/developer-id/symbols/`.

The script validates the app, mounted DMG contents, entitlements, architecture, hashes, source state, and ad-hoc signature. Gatekeeper rejects an ad-hoc artifact because it has no Developer ID trust chain or notarization ticket; that is expected.

For the production signing and notarization path, see `Packaging/DeveloperID/README.md` and `RELEASING.md`.

## Isolated native E2E host

Use the sandboxed E2E host for a disposable interaction sweep:

```sh
./script/build_and_run.sh --e2e
```

This foreground command builds a separate `com.s1korrrr.codebasecombiner.e2ehost` app, copies only the synthetic fixture into `/private/tmp`, prints the exact owned PID, and reaps only that PID when the wrapper exits. It does not use the production app's preferences or recovered output. Press Control-C in the same terminal to stop it.

For a recovery relaunch, preserve the isolated E2E container for one subsequent run:

```sh
CODEBASE_COMBINER_E2E_RESET=0 ./script/build_and_run.sh --e2e
```

Remove app-owned E2E state, runtime files, fixtures, and exports afterward:

```sh
./script/build_and_run.sh --clean-e2e-state
```

## Alternate Mac App Store packaging

The repository retains a separate optional pipeline under `Packaging/AppStore/`. It is not used for the direct GitHub download and has different identities, profiles, package format, and review requirements.

Prerequisites for the real upload path:

- Apple Developer Program membership.
- Bundle ID registered as `com.s1korrrr.codebasecombiner`.
- Mac App Store provisioning profile for that bundle ID.
- App signing identity such as `Apple Distribution: <Name> (<TEAMID>)` or `3rd Party Mac Developer Application: <Name> (<TEAMID>)`.
- Installer signing identity such as `3rd Party Mac Developer Installer: <Name> (<TEAMID>)` or `Mac Installer Distribution: <Name> (<TEAMID>)`.

The 2026-07-14 local audit detected valid application-distribution and installer identities, but did not find or embed a matching provisioning profile and did not create an uploadable package. Identity availability alone is not App Store Connect readiness.

Build and validate locally:

```sh
Packaging/AppStore/build_app_store_package.sh --skip-signing
```

Build a signed package after the Apple signing assets are installed:

```sh
Packaging/AppStore/build_app_store_package.sh \
  --signing-identity "Apple Distribution: <Name> (<TEAMID>)" \
  --installer-identity "3rd Party Mac Developer Installer: <Name> (<TEAMID>)" \
  --provisioning-profile "/path/to/profile.provisionprofile"
```

The signed path validates the profile platform, expiration, Team ID, exact bundle identifier, entitlements, and selected certificate before building. Any mismatch is a hard failure, as is a failed installer-signature check.

The signed package, when produced, is written to:

```sh
dist/app-store/CodebaseCombiner-AppStore.pkg
```

Only after the signed package, embedded profile, account/app record, metadata, privacy declarations, screenshots, and review inputs are verified should the owner upload it with Apple Transporter, Xcode, or another current Apple-supported upload path.

## Legacy SwiftPM executable copy

If you only need the raw executable:

1. Build with SwiftPM:
   ```sh
   swift build -c release
   ```
2. Copy the product wherever you like:
   ```sh
   cp .build/release/CodebaseExplorerApp /Applications/CodebaseExplorerApp
   ```
   Then launch via Spotlight or:
   ```sh
   open /Applications/CodebaseExplorerApp
   ```

## Troubleshooting

- If `swift run` fails with missing tools, reinstall Xcode Command Line Tools (`xcode-select --install`).
- If local bundle verification fails, rerun `Packaging/AppStore/build_app_store_package.sh --skip-signing` and inspect `codesign --verify --deep --strict --verbose=2 "dist/app-store/Codebase Combiner.app"`.
- For the direct-release bundle, rerun `Packaging/DeveloperID/build_release.sh --skip-signing` and inspect the generated release manifest and checksum evidence under `dist/developer-id/`.
- Do not interpret Gatekeeper rejection of the ad-hoc local bundle as a distribution-signature success or failure; verify the final distribution artifact separately after the matching profile and Apple-controlled assets are available.
