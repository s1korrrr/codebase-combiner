# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- JS unit tests with Mocha/Chai and Swift XCTest coverage.
- ESLint/Prettier and SwiftFormat configuration.
- CI workflow for linting, formatting, and tests.
- Open-source documentation (README, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY).
- GitHub issue templates and PR template.
- README preview image and badges.
- VS Code packaging rules via `.vscodeignore`.
- Focused macOS preference, workspace, output, dependency, command, and telemetry stores with injectable boundaries and behavioral tests.
- Structured scan outcomes and skipped-file summaries.
- An isolated sandboxed E2E host with synthetic fixtures, exact-PID ownership, deterministic window sizing, and scoped cleanup.
- Current native audit screenshots and a complete interaction/performance report under `docs/audit/`.

### Changed

- Rebuilt the macOS app as an adaptive three-workarea utility that remains usable at 960×640 and independently hides the workspace sidebar and output inspector.
- Consolidated app actions into shared menu, shortcut, toolbar, and button handlers and reduced Settings to one canonical macOS scene.
- Kept macOS 13 as the deployment floor while confining macOS 26 presentation to a bounded availability-gated style boundary.
- Reworked recovery so saved payload metadata is visible on relaunch while payload content stays concealed until Reveal; Copy Last does not reveal it, and Clear requires confirmation.
- Replaced content-bearing logging with typed metadata-only telemetry for scan, persistence, copy, save, and recovery outcomes.

### Fixed

- Prevented stale scans and asynchronous output/recovery completions from overwriting newer state.
- Avoided macOS 27 beta AppKit constraint crashes by keeping sidebar and inspector hosts structurally stable during visibility transitions.
- Corrected the VS Code publisher identifier and excluded app bundles, E2E evidence, agent artifacts, and other non-extension files from the VSIX.

## [0.0.1] - 2026-01-14

### Added

- VS Code extension to combine a workspace or folder into a single file.
- SwiftUI macOS app for visual selection and prompt generation.
