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

## Optional: create a distributable .app bundle

1. Archive with SwiftPM:
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
