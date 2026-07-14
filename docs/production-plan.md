# Production Plan: Codebase Combiner

## Product Brief

- Target user: developers who need to package selected code files into one prompt-ready payload.
- Primary job: choose a workspace, filter/select files, add optional instructions, copy or save the combined output.
- Core workflow: pick folder -> scan -> refine selection/filters -> copy or save combined payload -> recover last ready payload later if needed.
- Business model: free developer tool with optional support link.
- Supported macOS versions: macOS 13+.
- Offline behavior: fully local; no network is required for scanning, combining, copying, saving, or restoring the last payload.
- Data handled: user-selected local source files, prompt prefix text, preferences, and the last generated combined payload.
- Privacy posture: local-first, no tracking, no analytics, no collected data; saved payload is user content stored locally in Application Support.
- V1 scope: SwiftPM macOS app, adaptive native workspace, canonical Settings, local recovery, tests, isolated E2E, and ad-hoc App Store-style bundle validation.
- Explicitly out of scope: cloud sync, account system, AI model calls, paid unlocks, automatic upload to App Store Connect.

## Architecture

- Scene model: one `WindowGroup` for the workspace plus one canonical `Settings` scene.
- Window roles: primary workspace window and standard Settings window.
- Layout model: adaptive workspace sidebar, preparation surface, and output inspector. The two outer pane hosts stay structurally mounted and use transform/opacity for visibility because changing AppKit-backed split/toolbar structure crashed the audited macOS 27 beta host. Pure pane geometry reserves a non-overlapping preparation region for every visible combination.
- State ownership: `AppController` coordinates `AppPreferences`, `WorkspaceStore`, `OutputStore`, and shared sidebar/inspector visibility; views retain only local presentation details.
- Persistence: preferences in UserDefaults; the last ready combined payload remains an atomic JSON draft under Application Support with its existing schema.
- Services: `TreeLoader`, `TokenEstimator`, shared prompt/preview policies, `CombinedOutputBuilder`, `ClipboardDraftStore`, injected clipboard/save boundaries, and typed metadata-only telemetry. `TreeLoader` rejects symbolic links before target metadata or content access.
- App Intents / Foundation Models / advanced capabilities: not used in v1.
- Folder/module structure: `App/`, `Models/`, `Stores/`, `Services/`, `Support/`, `Views/`, and focused XCTest targets.

## Build And Run

- Project type: SwiftPM executable plus VS Code extension package.
- Build command: `cd SwiftExplorerApp && swift build`.
- Run command: `cd SwiftExplorerApp && swift run`.
- `script/build_and_run.sh` status: available; `--verify` owns and reaps one exact production PID, `--e2e` runs a separate sandboxed fixture host, and `--clean-e2e-state` removes app-owned E2E state and temporary artifacts.
- Codex Run action status: `.codex/environments/environment.toml` points Run to `./script/build_and_run.sh --verify`.

## Design System

- Native structures: workspace hierarchy, forms, segmented output picker, standard menus/toolbars/buttons, standard Settings, and semantic macOS materials.
- Adaptive states: 960×640 compact, 1180×760 regular, 1440×900 wide, independent sidebar/inspector visibility, empty, scanning, partial scan, no selection, current output, concealed recovery, and settings.
- Visual style: semantic macOS 13 baseline; one bounded `FunctionalChrome` modifier uses macOS 26 glass only when available and falls back to opaque/regular materials for reduced transparency or increased contrast.
- Motion rules: repeated workflow actions remain immediate; pane transitions are non-structural and Reduce Motion-safe.
- Accessibility requirements: named controls, prerequisite help for disabled actions, keyboard/menu parity, safe Cancel focus for destructive recovery clear, and accessibility-hidden collapsed panes.
- Empty/loading/error/offline/permission states: empty, loading, invalid settings, partial scan, typed scan failure with Retry/Choose Another Folder, persistence failure with same-draft retry, copy/save failure, and recovery failure are explicit; offline is normal operation.

## Test Strategy

- Unit tests: preference validation, adaptive/pane policies, token estimation, command state, async workspace/output ordering, recovery privacy, telemetry shape, tree loading, output formatting, and dependency selection.
- Integration tests or mocks: temporary-directory loader/draft tests plus injected filesystem, clipboard, save, output-build, and telemetry boundaries.
- UI/manual smoke: exact-PID `./script/build_and_run.sh --verify` plus the real sandboxed interaction matrix documented in `docs/audit/codebase-combiner-e2e-audit-2026-07-13.md`.
- Release smoke: `Packaging/AppStore/build_app_store_package.sh --skip-signing`, strict signature/plist/privacy/entitlement/minimum-OS inspection, and bounded 1,500-file Release performance.
- Commands: `swiftformat --lint .`, `swift test`, `swift build -c release -Xswiftc -warnings-as-errors`, `npm test`, `npm run lint`, `npm run format:check`, `npm run package`, shell contract/syntax checks, package assembly, and exact-PID launch verification.

## Observability

- Logger subsystem: `com.s1korrrr.codebasecombiner`.
- Categories: lifecycle, scan, export, persistence.
- Key lifecycle/action events: app launch/window setup, typed scan outcome, recovery load/save/clear outcome, and copy/save outcome with counts only.
- Sensitive logging exclusions: no raw file content, prompt text, combined/recovered payload, clipboard content, root/destination path, secret, or credential.

## App Store Readiness

- Bundle ID: `com.s1korrrr.codebasecombiner`.
- Signing team: valid distribution and installer identities were detected locally on 2026-07-14, but the owner team/account path and matching Mac App Store provisioning profile were not verified together.
- Sandbox/entitlements: strict ad-hoc signature verifies with App Sandbox and user-selected read/write only; no profile is embedded.
- Privacy manifest: parses; declares UserDefaults reason `CA92.1`, no tracking, and no collected data.
- Privacy labels: must be entered and owner-confirmed in App Store Connect; they should remain no tracking/no collected data unless the product changes.
- Assets: the bundle contains a generated `.icns`; current local audit screenshots are under `docs/audit/codebase-combiner-e2e-2026-07-14/`, but final App Store sizes/localizations are not prepared.
- Metadata: README/INSTALL are current; App Store Connect name/subtitle/description/keywords, support/privacy URLs, age rating, screenshots, and legal declarations remain owner work.
- Review notes: app is local-first and needs no demo account.
- Known blockers: matching provisioning profile, signed installer package, App Store Connect app record, final metadata/screenshots/privacy/legal declarations, upload, and Apple review. Xcode 27 is separately required before adding or proving macOS 27 SDK-only features.

## Iteration Log

| Date       | Gate                | Change                                                                                                       | Verification                                                                                         | Next blocker                                    |
| ---------- | ------------------- | ------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| 2026-06-29 | Production quality  | Added file-backed last-ready-payload persistence and restore/copy UI.                                        | `swift test` passed 8 tests; `npm test`; `npm run lint`; `npm run format:check`.                     | App Store signing assets.                       |
| 2026-06-29 | Build/run           | Added `script/build_and_run.sh --verify` and Codex Run action.                                               | `./script/build_and_run.sh --verify` launched packaged app.                                          | None for local smoke.                           |
| 2026-07-14 | Native architecture | Extracted focused stores/controller and rebuilt the adaptive workspace with concealed recovery.              | Historical sandbox matrix plus 100 current XCTest cases; changed pane runtime proof remains pending. | Holistic re-review and signed pane stress.      |
| 2026-07-14 | Package evidence    | Validated macOS 13.0 minimum, SDK 26.5, privacy manifest, strict ad-hoc signature, and minimal entitlements. | `build_app_store_package.sh --skip-signing`, `plutil`, `codesign`, and `vtool`.                      | Matching profile and signed installer package.  |
| 2026-07-14 | Extension package   | Corrected the VS Code publisher identifier and excluded non-extension artifacts.                             | `npm run package`: 72 files, 153.15 KB.                                                              | Marketplace ownership/publish remains external. |
