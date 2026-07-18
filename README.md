# Codebase Combiner

[![CI](https://github.com/s1korrrr/codebase-combiner/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/s1korrrr/codebase-combiner/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Codebase Combiner helps you curate files, count tokens, and generate a ready-to-paste prompt from a workspace or folder.

This repo ships two deliverables:

- VS Code extension (Node/JavaScript)
- Native macOS SwiftUI app (SwiftPM)

## Features

- Combine a workspace or folder into a single Markdown or text file.
- Flexible include/exclude filters by glob and extension.
- Token estimation for prompt sizing.
- Adaptive native macOS workspace with independently collapsible workspace and output panes, including a compact 960×640 path.
- Structured scan summaries for hidden, excluded, disallowed, oversized, binary, symbolic-link, and unreadable files without exposing skipped paths or symbolic-link targets.
- A shared 20,000-character current/recovered preview limit with an honest truncation notice; Copy, Copy Last, and Save continue to use the full payload.
- Privacy-conscious “last ready output” recovery: metadata stays visible, content stays concealed until Reveal, and clearing requires confirmation.
- Actionable recovery for failed workspace scans and recoverable-output persistence, including safe Retry and Choose Another Folder paths.
- One native Settings scene for output format, filter visibility, hidden-file handling, extension filters, and validated file-size limits.
- Typed local telemetry for lifecycle, scan, export, and recovery outcomes; logs contain counts and outcomes, not paths or payloads.
- A macOS 13 semantic-material baseline with narrowly availability-gated macOS 26 presentation when the compiled SDK and runtime support it.
- Public support and privacy-policy links in the app menu and Settings.

## Getting started

See `INSTALL.md` for full setup and run instructions.

### Download the macOS app

Official macOS builds are distributed outside the Mac App Store through [GitHub Releases](https://github.com/s1korrrr/codebase-combiner/releases) as Developer ID-signed, Apple-notarized DMGs. Version 0.1.0, once published, is Apple-silicon-only (`arm64`) and requires macOS 13 or later; Intel and universal builds are not provided.

Download all assets from the release into one directory and verify them before opening the DMG:

```sh
shasum -a 256 -c SHA256SUMS
```

Open the DMG and drag **Codebase Combiner** into `/Applications`. Do not use Gatekeeper-bypass commands; the official artifact must open normally.

Quick start (VS Code extension):

```sh
npm install
npm test
npm run package
```

Quick start (Swift app):

```sh
cd SwiftExplorerApp
swift run CodebaseExplorerApp
```

## Usage

### VS Code extension

Commands:

- “Combine Workspace to Single File”
- “Combine This Folder to Single File” (context menu)

Output options are configurable in VS Code settings under “Codebase Combiner”.

### macOS SwiftUI app

- Launch with `swift run CodebaseExplorerApp` from `SwiftExplorerApp/`.
- Choose a folder, adjust filters, select files, then copy or save the combined prompt.
- The app keeps the last ready combined payload in local Application Support storage. Relaunch shows only its metadata until you explicitly reveal the content; revealed previews are bounded, while Copy Last still uses the full payload.
- Use the standard macOS Settings command or the app menu for preferences and support.
- Use the View menu or toolbar to show or hide the workspace sidebar, filters, and output inspector.

## Development

### JavaScript/Node

- Tests: `npm test`
- Lint: `npm run lint`
- Format: `npm run format` (or `npm run format:check` in CI)
- Package a local VSIX: `npm run package`

### Swift

- Build: `cd SwiftExplorerApp && swift build`
- Tests: `cd SwiftExplorerApp && swift test`
- Run: `cd SwiftExplorerApp && swift run CodebaseExplorerApp`
- Bundle launch smoke: `./script/build_and_run.sh --verify`
- Isolated native E2E host: `./script/build_and_run.sh --e2e`
- Remove isolated E2E state: `./script/build_and_run.sh --clean-e2e-state`
- Format (SwiftFormat): `cd SwiftExplorerApp && swiftformat .`
- Format check: `cd SwiftExplorerApp && swiftformat --lint .`

### Developer ID direct distribution

- Local structural validation: `Packaging/DeveloperID/build_release.sh --skip-signing`
- Developer ID, DMG, and notarization flow: see `Packaging/DeveloperID/README.md`
- Public release procedure: see `RELEASING.md`
- Output directory: `dist/developer-id/`

The local `--skip-signing` output is ad-hoc signed and is not a public distributable. Public readiness requires Developer ID signing, Hardened Runtime, a secure timestamp, Apple notarization acceptance, a stapled ticket, Gatekeeper validation, matching checksums/SBOM/source commit, and a clean-download smoke.

### Alternate Mac App Store packaging

- Local bundle validation: `Packaging/AppStore/build_app_store_package.sh --skip-signing`
- App Store signing/package flow: see `Packaging/AppStore/README.md`
- Output directory: `dist/app-store/`

The App Store lane remains available as a separate alternate channel; it is not used for the direct GitHub download.

The current implementation was built with Xcode 26.6 and the macOS 26.5 SDK. Running it on macOS 27 does not prove or include macOS 27 SDK-only features; those remain blocked until Xcode 27 is installed and the availability boundary is revalidated.

## Quality gates

- JS: Node's built-in test runner with Chai assertions, ESLint, and Prettier
- Swift: XCTest + SwiftFormat
- CI: GitHub Actions runs all quality gates on PRs

## Contributing

See `CONTRIBUTING.md`.

## Security

See `SECURITY.md`.

## Support and privacy

- [Support](docs/support.md)
- [Privacy policy](docs/privacy-policy.md)

## License

MIT. See `LICENSE`.
