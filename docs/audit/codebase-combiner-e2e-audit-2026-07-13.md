# App E2E Audit Report: Codebase Combiner

## Outcome

- Audit date: 2026-07-14. The filename retains the implementation-plan date.
- Audited artifact: `dist/app-store/Codebase Combiner E2E.app`, built from the Release product and signed with `Packaging/AppStore/AppStore.entitlements`.
- Audited platform: macOS 27 beta host; Xcode 26.6 and macOS 26.5 SDK; macOS 13 deployment target.
- Readiness label: **repository-ready: no, pending holistic re-review and refreshed signed interaction proof**. Local ad-hoc package gates are re-run separately and do not override this review gate.
- Release boundary: this is not ready for App Store Connect upload. The local `.app` is ad-hoc signed; matching provisioning, distribution packaging, App Store Connect declarations, upload, and review remain separate owner-controlled gates.

The earlier sandboxed baseline completed the primary workflow and found a macOS 27 beta AppKit constraint crash. A holistic review then found that the crash-safe overlay panes could cover preparation controls, sidebar visibility was not shared with commands, symbolic links could cross the scan boundary, recovered previews were unbounded, and two failure paths lacked direct retry controls. Those findings are corrected in code and covered by 100 tests, including invalid-request supersession of in-flight scans and retained retries, but the changed pane geometry still requires fresh signed loaded-workspace stress before repository readiness can return to yes.

### Holistic review correction status

- Pure frame assertions prove that visible sidebar and inspector regions do not intersect preparation at 960, 1180, 1320, or 1680 points for every visibility combination.
- Sidebar visibility is owned by `AppController`; the View menu name changes between Show and Hide and the static toolbar button calls the same action.
- Every symbolic-link entry is classified before directory, size, or content access. In-root oversized and out-of-root link targets are both skipped with only an aggregate symbolic-link count.
- Current and revealed recovered previews use one 20,000-character policy; Copy, Copy Last, and Save retain full payloads.
- Typed scan failures retain a safe retry request; persistence failures retain the exact draft for retry without dropping current output. Stale retry completions cannot replace newer scan/build state.
- A fresh signed sandbox launch at 960x640 verified the empty Accessibility tree, `~0 tokens`, dynamic `Hide Workspace Sidebar` menu title, exact PID ownership, zero-byte stderr, and no new crash report. The loaded-workspace click/stress pass was blocked when an unavailable AppleScript route triggered macOS Automation/Admin permission prompts. No prompt was accepted or denied and no system setting was changed.
- The three screenshots retained below predate these geometry corrections and are not current visual proof. No replacement image is claimed until the signed loaded-workspace pass can run without altering system permissions.

## Isolation And Process Ownership

- The E2E bundle identifier is `com.s1korrrr.codebasecombiner.e2ehost`, distinct from production.
- Effective signed entitlements were inspected before UI work. `com.apple.security.app-sandbox` and `com.apple.security.files.user-selected.read-write` were both `true`.
- Preferences use the E2E app's standard sandbox preferences. Recovery storage resolved inside `~/Library/Containers/com.s1korrrr.codebasecombiner.e2ehost/Data/Library/Application Support/Codebase Combiner/`.
- The only opened workspaces were synthetic fixtures under `/private/tmp`: the functional fixture copied to `/private/tmp/CodebaseCombinerE2EFixture` and the disposable 1,500-file performance fixture.
- `script/build_and_run.sh` launches the exact executable directly, captures `$!`, verifies its full command twice, and terminates/reaps only that owned PID. It contains no `pgrep`, `pkill`, or application-name launch/discovery.
- `--verify` owns its launch through cleanup. `--e2e` is a foreground wrapper and removes its PID file only after the child exits or is reaped.
- Clipboard tests backed up and restored the existing pasteboard. Saved output stayed in the standard scoped E2E export directory at `/private/tmp/CodebaseCombinerE2EExport`.

## Runtime Corrections

### Structured outcomes and telemetry

`WorkspaceStore.scan` now returns one explicit result: accepted metadata, invalid-size rejection, failure, or stale completion. `AppController` records that returned result instead of inferring success from mutable state. `OutputStore` and `AppController` share an injected typed telemetry recorder; behavioral tests prove that telemetry carries counts and outcomes without payloads or paths.

The sandboxed live workflow emitted metadata-only events for scan start, accepted counts, recovery save counts, current copy length, and recovery load. No log event exposed source, prompt, root, or destination content.

### macOS 27 pane crash

Three sandbox runs exposed the same AppKit update-constraints failure through different SwiftUI hosts:

1. Nested split view plus sidebar restore.
2. Native `.inspector` after a loaded-workspace toggle.
3. A stateful sidebar toolbar item, whose crash backtrace named `AppKitToolbarStrategy.updatedVendedItems`.

The retained design keeps both panes mounted and shows or hides them with transform, opacity, hit testing, and accessibility state. A pure geometry policy reserves preparation insets without inserting/removing pane hosts. Toolbar pane controls are static buttons with static labels/help, while the View command name is dynamic and controller-owned. The focused tests guard against `NavigationSplitView`, `HSplitView`, native `.inspector`, geometry callbacks, stateful pane toolbar toggles, and all visible frame intersections.

Historical runtime proof used sandbox PID `25766` before the holistic geometry correction: after the real fixture loaded, five cycles of inspector hide, sidebar hide/show, and inspector restore completed with empty stderr and no crash delta. It remains useful crash-history evidence, but it is not treated as proof for the changed frame/inset implementation.

## Complete Scenario Matrix

Every status is one of `verified`, `blocked`, `failed`, or `not applicable`. Where an interaction was exercised before the final pane-only correction, the evidence cell says so and names the current-code regression guard. Blocked rows are not promoted by adjacent evidence.

| Surface       | Scenario                                                         | Result and evidence                                                                                                                                                                   | Status         |
| ------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| Launch        | Fresh first launch                                               | Fresh E2E `Data` reset produced the empty workspace, disabled Refresh/Copy/Save, explicit prerequisite help, and no recovery payload. Effective entitlements were asserted before UI. | verified       |
| Launch        | Relaunch with saved state                                        | Recovery metadata loaded from the E2E container while content remained concealed; see wide recovery AX and `02-sandbox-wide-recovery-concealed.png`.                                  | verified       |
| Workspace     | Real open panel                                                  | Real `NSOpenPanel` selected both synthetic fixtures only under `/private/tmp`; no user source directory was opened.                                                                   | verified       |
| Scan          | Partial functional scan                                          | Functional fixture accepted README and Swift source and reported two skips without revealing skipped paths; see AX, metadata-only scan log, and `01-sandbox-compact-loaded.png`.      | verified       |
| Filters       | Editor Cancel                                                    | A draft allow-list change was canceled; the committed list and 1,500-file selection remained unchanged.                                                                               | verified       |
| Filters       | Editor Apply                                                     | Applying an allow list of `swift` committed the field, triggered a new accepted scan, and retained all 1,500 synthetic Swift files.                                                   | verified       |
| Selection     | Root toggle, Clear Selection, Select All                         | Clear changed the root checkbox to off, selected count to zero, and disabled Copy/Save with specific help; Select All restored 1,500/1,500.                                           | verified       |
| Prompt        | Empty and realistic prefix                                       | Empty and realistic synthetic prefixes both rebuilt output and remained editable without losing selection.                                                                            | verified       |
| Format        | Markdown and Plain Text                                          | Both segmented values were selected in turn and Markdown was restored; metadata followed the selected format.                                                                         | verified       |
| Copy          | Current output and Copy Last                                     | Exercised in the signed sandbox before pane-only corrections; copy lengths matched, the clipboard backup was restored, and current `OutputStoreTests` cover full-payload behavior.    | verified       |
| Save          | Real save panel                                                  | Exercised in the signed sandbox before pane-only corrections; real `NSSavePanel` wrote only below `/private/tmp`, and current `OutputStoreTests` cover full-payload saving.           | verified       |
| Recovery      | Concealed state                                                  | Relaunch displayed file count, format, token count, and timestamp without displaying payload content; see `02-sandbox-wide-recovery-concealed.png`.                                   | verified       |
| Recovery      | Reveal then Hide                                                 | Exercised before pane-only corrections; Reveal made synthetic content available and Hide concealed it without mutating the draft. No revealed screenshot was retained.                | verified       |
| Recovery      | Copy while concealed                                             | Exercised before pane-only corrections; Copy Last succeeded without revealing content and the clipboard backup was restored. Typed telemetry tests guard the current path.            | verified       |
| Recovery      | Clear confirmation Cancel                                        | Exercised before pane-only corrections; the confirmation opened with Cancel as safe default and Cancel preserved the draft. Current confirmation tests guard the path.                | verified       |
| Recovery      | Confirm destructive clear                                        | The destructive UI confirmation was not clicked; isolated store tests cover confirmed clear and failure/retry semantics.                                                              | blocked        |
| Menus         | File, Edit, View, Support                                        | Real menu inventory exposed Choose, Refresh, Save, Copy, filters, inspector, sidebar, Settings, and Support; final pane controls were reverified after correction.                    | verified       |
| Shortcuts     | Cmd-O, Cmd-R, Cmd-Shift-C, Cmd-S, Cmd-,                          | Exercised before pane-only corrections; canonical commands invoked the same open, refresh, copy, save, and Settings operations, with current command-state tests.                     | verified       |
| Context       | Workspace row secondary click                                    | Secondary click on the synthetic root produced no contextual menu; there is no context-only product action.                                                                           | not applicable |
| Help          | Tooltips and disabled prerequisites                              | Empty launch and cleared selection named the missing workspace/selection/output prerequisites for Refresh, Copy, Save, Select All, and Clear Selection.                               | verified       |
| Settings      | General and Support tabs                                         | Exercised before pane-only corrections; exactly one standard Settings scene opened, both tabs were inspected, and current preference tests guard synchronization.                     | verified       |
| Support       | External destination                                             | The app launched the browser, but the destination was not independently inspected in the available browser-control runtime.                                                           | blocked        |
| Panes         | Sidebar and inspector visibility                                 | Pure frame/command tests pass; a fresh signed loaded-workspace interaction rerun is pending after macOS permission prompts blocked UI automation.                                     | blocked        |
| Panes         | Stress sequence                                                  | Historical 20-transition proof predates the inset correction. The required five-cycle exact-PID rerun is pending and is not inferred from unit tests.                                 | blocked        |
| Window        | Compact                                                          | Pure 960-point geometry passes and fresh empty-state AX is unobscured; corrected loaded-workspace screenshot is pending.                                                              | blocked        |
| Window        | Regular                                                          | Pure 1180/1320-point geometry passes; corrected signed loaded-workspace screenshot is pending.                                                                                        | blocked        |
| Window        | Wide                                                             | Pure 1680-point geometry passes; corrected signed loaded-workspace screenshot is pending.                                                                                             | blocked        |
| Appearance    | Current dark appearance                                          | All retained final screenshots were visually inspected in the current dark appearance.                                                                                                | verified       |
| Accessibility | Increased contrast, Reduce Motion, larger text, light appearance | These variants require changing user system settings and were not forced. Code-level fallback and accessibility-name tests pass.                                                      | blocked        |
| Persistence   | Sandbox container                                                | Preferences and the recovery draft resolved inside the distinct E2E container; production state was untouched.                                                                        | verified       |
| Logs          | Structured telemetry and privacy                                 | Typed events cover scan, persistence, copy, save, clear, and stale/failure outcomes; no payload, prompt, root, or destination is interpolated.                                        | verified       |
| Performance   | 1,500-file Release fixture                                       | 14,055,000 source bytes and 3,513,000 file tokens: scan 330 ms; output/recovery 611 ms; peak CPU 88.6%; peak RSS 252,368 KB; pane response 878 ms.                                    | verified       |
| Cleanup       | Processes, container data, fixtures, export                      | The wrapper reaped its exact child; app-owned E2E data, runtime files, fixtures, export, sampler output, and later E2E bundle residue were removed.                                   | verified       |

## Bounded Release Performance

The repository has no published performance SLO. For this audit, the 1,500-file brief was evaluated against explicit local-interaction bounds: accepted scan at or below 2 seconds, output/recovery readiness at or below 3 seconds, peak CPU at or below 100% of one core, peak RSS at or below 300 MiB, a post-scan pane action at or below 2 seconds including AX confirmation, and zero stderr/crash delta. These are audit interpretation thresholds, not a customer-facing product promise.

| Metric                    | Evidence                                                                             | Threshold                                     | Result |
| ------------------------- | ------------------------------------------------------------------------------------ | --------------------------------------------- | ------ |
| Fixture                   | 1,500 synthetic Swift files; 14,055,000 source bytes; 3,513,000 file tokens          | Brief called for about 1,500 disposable files | Pass   |
| Scan wall time            | Scan started `03:53:20.924`; accepted `03:53:21.254`: 330 ms                         | <= 2,000 ms                                   | Pass   |
| Output/recovery readiness | Recovery save completed `03:53:21.535`: 611 ms after scan start                      | <= 3,000 ms                                   | Pass   |
| CPU                       | 601 exact-PID samples at 100 ms; peak 88.6%; settled to 0.0%                         | <= 100% of one core                           | Pass   |
| RSS                       | Baseline 133,808 KB; peak 252,368 KB; peak delta 118,560 KB; settled near 210,144 KB | <= 307,200 KB                                 | Pass   |
| Post-scan response        | Inspector hide plus AX confirmation: 878 ms                                          | <= 2,000 ms                                   | Pass   |
| Stability                 | Exact command still matched PID `51225`; stderr zero bytes; no new diagnostic report | Zero stderr/crash delta                       | Pass   |

The first UI-ready polling timer is intentionally excluded: it waited 85.987 seconds because the automation searched for ungrouped `1500 selected` while the Polish locale exposed `1.500 selected`. Unified-log timestamps and final AX state show that the app had completed; the mismatch was in the audit predicate, not the app. No result above uses that invalid timer.

## Screenshot Evidence

- `docs/audit/codebase-combiner-e2e-2026-07-14/01-sandbox-compact-loaded.png`, `02-sandbox-wide-recovery-concealed.png`, and `03-sandbox-performance-1500.png` are retained as historical baseline evidence only. They predate the non-overlap correction and are not cited as current visual proof.
- No retained screenshot contains a user home-directory path or user source content.
- The wide recovery body is concealed by product behavior. Concealment/redaction is privacy evidence only; it is not cited as visual proof of the hidden payload.

## Automated Gates

| Check                 | Command                                                                                                                     | Result                                                     |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Swift formatting      | `cd SwiftExplorerApp && swiftformat --lint .`                                                                               | 45 files checked; 0 require formatting                     |
| Swift tests           | `cd SwiftExplorerApp && swift test`                                                                                         | 100 tests; 0 failures                                      |
| Release warnings      | `cd SwiftExplorerApp && swift build -c release -Xswiftc -warnings-as-errors`                                                | Passed                                                     |
| Node behavior         | `npm test`                                                                                                                  | 4 tests; 0 failures                                        |
| Node lint             | `npm run lint`                                                                                                              | Passed                                                     |
| Repository formatting | `npm run format:check`                                                                                                      | Passed                                                     |
| VS Code package       | `npm run package`                                                                                                           | Passed; 72 files, 153.15 KB VSIX; root `.gitignore` absent |
| Script contract       | `script/tests/build_and_run_contract_test.sh`                                                                               | Passed                                                     |
| Script syntax         | `bash -n script/build_and_run.sh Packaging/AppStore/build_app_store_package.sh script/tests/build_and_run_contract_test.sh` | Passed                                                     |
| Package               | `Packaging/AppStore/build_app_store_package.sh --skip-signing`                                                              | Passed with strict signature verification                  |
| Installed-app smoke   | `./script/build_and_run.sh --verify`                                                                                        | Exact PID launched, verified, terminated, and reaped       |

## Final Package Evidence

- Host/toolchain: macOS 27.0 beta; Xcode 26.6 (17F113); macOS SDK 26.5; Swift 6.3.3.
- Bundle: `dist/app-store/Codebase Combiner.app`; identifier `com.s1korrrr.codebasecombiner`; version `0.1.0`; build `1`.
- Compatibility: `LSMinimumSystemVersion = 13.0`; Mach-O `LC_BUILD_VERSION` reports minimum 13.0 and SDK 26.5.
- Privacy: manifest parses, UserDefaults reason is `CA92.1`, tracking is false, and collected-data types are empty.
- Signature: strict verification passes; signature is ad-hoc with no team identifier. Gatekeeper rejection is expected for this local artifact and is not a distribution proof.
- Effective entitlements: App Sandbox plus user-selected read/write only.
- Installer/profile: no provisioning profile is embedded and no `.pkg` was created. Valid local application and installer distribution identities were detected, but the matching profile/team/app-record path was not exercised.
- Exact-PID smoke: production PID `76936` was checked twice, terminated, and reaped; its captured stdout and stderr were both zero bytes.
- Privacy log review: typed telemetry carries outcomes, counts, byte/character totals, and E2E window dimensions only. Source review plus `AppTelemetryTests` found no payload, prompt, clipboard, root, or destination field.
- Cleanup: `--clean-e2e-state` completed; E2E runtime, fixture, export, E2E app bundle residue, and matching app processes were absent afterward.

## Readiness Separation

- Repository-ready: **no**, pending holistic re-review plus the fresh signed loaded-workspace pane stress and corrected screenshots.
- Package-ready: verified only for the local ad-hoc `.app`.
- Ready for App Store Connect upload: blocked on matching provisioning, verified team/app record, distribution-signed app and installer package, metadata, screenshots, privacy/legal declarations, and owner-controlled upload.
- Apple review/notarization/account outcomes: external and not performed.
- macOS 27 SDK-only work: blocked on Xcode 27. The audited app runs on macOS 27 but was compiled against SDK 26.5, so no macOS 27 SDK-only feature is claimed.

## TDD And Failure Evidence

- Telemetry/outcome RED: missing typed recorder and `WorkspaceScanOutcome`; focused GREEN ended with 18 tests and no failures.
- Inspector-host RED: source still used native `.inspector`; GREEN removed native inspector and nested split usage.
- Constant-layout RED: hidden panes changed layout width; GREEN retains constant pane size and changes only transform/accessibility state.
- Toolbar RED: sidebar and inspector used stateful toolbar toggles; GREEN uses static controls.
- Wide-frame RED: restored window state overrode requested E2E geometry; GREEN adds an E2E-only exact outer-frame policy while production ignores the environment.
- Crash reports `030709`, `031512`, `032005`, and `032349` are retained only as local diagnostic evidence and are not product artifacts.

## Scope Boundary

No distribution signing, provisioning-profile use, notarization, upload, purchase, public write, user-source mutation, or system-setting mutation was performed. Repository readiness remains no until the blocked changed-UI interaction evidence and holistic re-review pass; local ad-hoc packaging and external gates remain separately labeled.
