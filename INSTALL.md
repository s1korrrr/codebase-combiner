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
- Node.js 18+ and npm (for the VS Code extension).

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

1. Open Terminal and `cd` to the app directory:
   ```sh
   cd SwiftExplorerApp
   ```
2. Build and launch:
   ```sh
   swift run
   ```
   The SwiftUI window opens. Pick a folder, adjust filters, select files, then copy/save the combined prompt.

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

## Optional: create a local .app bundle

For local App Store-style bundle validation:

```sh
Packaging/AppStore/build_app_store_package.sh --skip-signing
open "dist/app-store/Codebase Combiner.app"
```

This creates a sandbox-entitled, ad-hoc signed app bundle for local validation only. It is not uploadable to App Store Connect until it is signed with Apple distribution assets.

## Mac App Store packaging

The repo includes a packaging pipeline under `Packaging/AppStore/`.

Prerequisites for the real upload path:

- Apple Developer Program membership.
- Bundle ID registered as `com.s1korrrr.codebasecombiner`.
- Mac App Store provisioning profile for that bundle ID.
- App signing identity such as `Apple Distribution: <Name> (<TEAMID>)` or `3rd Party Mac Developer Application: <Name> (<TEAMID>)`.
- Installer signing identity such as `3rd Party Mac Developer Installer: <Name> (<TEAMID>)` or `Mac Installer Distribution: <Name> (<TEAMID>)`.

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

The signed package, when produced, is written to:

```sh
dist/app-store/CodebaseCombiner-AppStore.pkg
```

Upload the signed package with Apple Transporter, Xcode, `xcrun altool`, or the App Store Connect API.

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
- If macOS blocks execution, right-click the binary once and choose “Open” to approve it.
