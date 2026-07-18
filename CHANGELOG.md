# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### VS Code extension

- Advanced the candidate version to `0.0.2`; Marketplace publication remains a separate release action.
- Added structured skip summaries and Restricted Mode configuration boundaries while preserving explicitly empty one-run filters.
- Hardened traversal against symbolic-link roots, special-file blocking, recursive-glob denial of service, silent traversal errors, and forged plain-text path headers.
- Excluded local Git worktrees, app bundles, E2E evidence, agent artifacts, and other non-extension files from VSIX packages.

## [0.1.0] - 2026-07-18

### Added

- Swift XCTest coverage and pinned SwiftFormat validation.
- CI workflows for build, test, CodeQL, and gated Developer ID release automation.
- Open-source documentation (README, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY).
- GitHub issue templates and PR template.
- README preview image and badges.
- Focused macOS preference, workspace, output, dependency, command, and telemetry stores with injectable boundaries and behavioral tests.
- Structured scan outcomes and skipped-file summaries.
- Typed scan and persistence retry state with visible recovery controls.
- An isolated sandboxed E2E host with synthetic fixtures, exact-PID ownership, deterministic window sizing, and scoped cleanup.
- A single current interaction, performance, security, packaging, and release audit under `docs/audit/`.

### Changed

- Hardened the native scanner against symbolic-link roots, special-file blocking, malformed persisted size values, locale-dependent bounded selection, and silent traversal errors.
- Declared Apple file-timestamp required-reason APIs, embedded the MIT license in App Store bundles, and added source-bound App Store manifests, checksums, and operation locking.
- Made notarization resolve SBOM and symbols from the release manifest, publish flat checksum-verifiable evidence, and fail closed when hosted signing is not provisioned.
- Prevented concurrent or orphaned E2E hosts from sharing and resetting the same sandbox state.
- Rebuilt the macOS app as an adaptive three-workarea utility that remains usable at 960×640 and independently hides the workspace sidebar and output inspector.
- Consolidated app actions into shared menu, shortcut, toolbar, and button handlers and reduced Settings to one canonical macOS scene.
- Kept macOS 13 as the deployment floor while confining macOS 26 presentation to a bounded availability-gated style boundary.
- Reworked recovery so saved payload metadata is visible on relaunch while payload content stays concealed until Reveal; Copy Last does not reveal it, and Clear requires confirmation.
- Bounded current and recovered previews to 20,000 characters while keeping Copy and Save operations full-payload.
- Replaced content-bearing logging with typed metadata-only telemetry for scan, persistence, copy, save, and recovery outcomes.

### Fixed

- Prevented stale scans and asynchronous output/recovery completions from overwriting newer state.
- Rejected symbolic links before file metadata or content reads so scans cannot follow in-root or escaping link targets.
- Reserved a non-overlapping preparation region for every visible pane combination at compact, regular, and wide widths.
- Avoided macOS 27 beta AppKit constraint crashes by keeping sidebar and inspector hosts structurally stable during visibility transitions.

## [0.0.1] - 2026-01-14

### Added

- VS Code extension to combine a workspace or folder into a single file.
- SwiftUI macOS app for visual selection and prompt generation.
