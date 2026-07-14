# App E2E Audit Report: Codebase Combiner

## Outcome

- Audit date: 2026-07-14. The filename retains the implementation-plan date.
- Audited artifact: `dist/app-store/Codebase Combiner E2E.app`, built from the Release product and signed with `Packaging/AppStore/AppStore.entitlements`.
- Audited platform: macOS 27 beta with a macOS 13 deployment target.
- Readiness label: **interaction-clean for the audited local core workflow, with explicit blocked variants**.
- Release boundary: this is not an App Store or release-candidate claim. Distribution signing, notarization, upload, and owner-account work remain separate gates.

The final sandboxed host completed the primary workflow: real open panel, fixture scan, selection, copy, save panel, relaunch recovery, menus, Settings, and repeated pane transitions. The audit also found a macOS 27 beta AppKit constraint crash. The final implementation avoids the crashing structural split/inspector and stateful toolbar-preference transitions; one exact sandbox PID then survived 20 combined pane transitions with empty stderr and no new crash report.

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

The retained design keeps both panes mounted at constant size and shows or hides them with transform, opacity, hit testing, and accessibility state. Toolbar pane controls are static buttons with static labels/help, so pane changes do not mutate toolbar preferences. The focused tests guard against `NavigationSplitView`, `HSplitView`, native `.inspector`, geometry callbacks, and stateful pane toolbar toggles.

Final runtime proof used sandbox PID `25766`: after the real fixture loaded, five cycles of inspector hide, sidebar hide/show, and inspector restore completed. The automation checked the foreground wrapper PID file after every action and would stop before any relaunch. The same exact command remained alive after a two-second stability check, stderr was zero bytes, and no new crash report appeared.

## Complete Scenario Matrix

`Verified — corrected host` means the action or state was exercised on the final signed, sandboxed implementation. `Carried forward — signed sandbox` is used only where the behavior was already exercised in the signed sandbox and subsequent corrections were confined to pane presentation, window sizing, process ownership, or telemetry; current-code tests remained green. Blocked rows are not promoted by adjacent evidence.

| Surface       | Scenario                                                         | Result and evidence                                                                                                                                                                      | Status                                                                                      |
| ------------- | ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Launch        | Fresh first launch                                               | Fresh E2E `Data` reset produced the empty workspace, disabled Refresh/Copy/Save, explicit prerequisite help, and no recovery payload. Effective entitlements were asserted before UI.    | Verified — corrected host; PID `51225`, first-launch AX                                     |
| Launch        | Relaunch with saved state                                        | Recovery metadata loaded from the E2E container while content remained concealed.                                                                                                        | Verified — corrected host; wide recovery AX and `02-sandbox-wide-recovery-concealed.png`    |
| Workspace     | Real open panel                                                  | Real `NSOpenPanel` selected both synthetic fixtures only under `/private/tmp`; no user source directory was opened.                                                                      | Verified — corrected host; OpenPanel AX                                                     |
| Scan          | Partial functional scan                                          | Functional fixture accepted README and Swift source and reported two skips without revealing skipped paths.                                                                              | Verified — corrected host; AX, metadata-only scan log, `01-sandbox-compact-loaded.png`      |
| Filters       | Editor Cancel                                                    | A draft allow-list change to `txt` was canceled; the committed list and 1,500-file selection remained unchanged.                                                                         | Verified — corrected host; filter sheet and post-Cancel AX                                  |
| Filters       | Editor Apply                                                     | Applying an allow list of `swift` committed the field, triggered a new accepted scan, and retained all 1,500 synthetic Swift files.                                                      | Verified — corrected host; post-Apply AX and scan log                                       |
| Selection     | Root toggle, Clear Selection, Select All                         | Clear changed the root checkbox to off, selected count to zero, and disabled Copy/Save with specific help; Select All restored 1,500/1,500.                                              | Verified — corrected host; AX before/after                                                  |
| Prompt        | Empty and realistic prefix                                       | Empty prompt built normally; setting `Summarize the synthetic architecture.` rebuilt output and remained editable without losing selection.                                              | Verified — corrected host; prompt AX and recovery-save telemetry                            |
| Format        | Markdown and Plain Text                                          | Both segmented values were selected in turn and Markdown was restored; metadata followed the selected format.                                                                            | Verified — corrected host; format-control AX                                                |
| Copy          | Current output and Copy Last                                     | Current and concealed-recovery copy lengths matched the synthetic output checks; clipboard backup was restored after each check.                                                         | Carried forward — signed sandbox; copy AX, metadata-only length logs, `OutputStoreTests`    |
| Save          | Real save panel                                                  | Real `NSSavePanel` wrote the 639-byte functional-fixture export only below `/private/tmp`; copy/save payload metadata matched.                                                           | Carried forward — signed sandbox; SavePanel AX, file metadata, `OutputStoreTests`           |
| Recovery      | Concealed state                                                  | Relaunch displayed file count, format, token count, and timestamp without displaying payload content.                                                                                    | Verified — corrected host; `02-sandbox-wide-recovery-concealed.png` and AX                  |
| Recovery      | Reveal then Hide                                                 | Reveal made synthetic content available and Hide concealed it again without mutating the draft. No revealed screenshot was retained.                                                     | Carried forward — signed sandbox; reveal/hide AX and `AdaptiveWorkspaceSmokeTests`          |
| Recovery      | Copy while concealed                                             | Copy Last succeeded without changing the concealed state; clipboard was restored.                                                                                                        | Carried forward — signed sandbox; AX and typed telemetry test                               |
| Recovery      | Clear confirmation Cancel                                        | The confirmation opened with Cancel as the safe default; Cancel preserved the recovery draft.                                                                                            | Carried forward — signed sandbox; dialog AX and confirmation tests                          |
| Recovery      | Confirm destructive clear                                        | The destructive UI confirmation was not clicked; isolated store tests cover confirmed clear and failure/retry semantics.                                                                 | Blocked — destructive Computer Use action required action-time confirmation                 |
| Menus         | File, Edit, View, Support                                        | Real menu inventory exposed Choose, Refresh, Save, Copy, filters, inspector, sidebar, Settings, and Support with coherent enablement.                                                    | Carried forward — signed sandbox; menu AX; final pane controls reverified on corrected host |
| Shortcuts     | Cmd-O, Cmd-R, Cmd-Shift-C, Cmd-S, Cmd-,                          | Canonical commands invoked the same open, refresh, copy, save, and Settings operations.                                                                                                  | Carried forward — signed sandbox; panel/Settings AX and command-state tests                 |
| Context       | Workspace row secondary click                                    | Secondary click on the synthetic root produced no contextual menu; there is no context-only product action to verify.                                                                    | Verified — corrected host; post-secondary-click AX contained only the menu bar              |
| Help          | Tooltips and disabled prerequisites                              | Empty launch and cleared selection explicitly named the missing workspace/selection/output prerequisites for Refresh, Copy, Save, Select All, and Clear Selection.                       | Verified — corrected host; first-launch and cleared-selection AX                            |
| Settings      | General and Support tabs                                         | Exactly one standard Settings scene opened and both tabs were inspected; the preference surface remained synchronized.                                                                   | Carried forward — signed sandbox; Settings AX and `AppPreferencesTests`                     |
| Support       | External destination                                             | The app action launched the browser, but destination inspection was unavailable in the browser-control runtime.                                                                          | Blocked beyond app launch — destination not independently inspected                         |
| Panes         | Sidebar and inspector visibility                                 | Both constant-size panes hid and restored without losing workspace/recovery state.                                                                                                       | Verified — corrected host; AX and stable-host source tests                                  |
| Panes         | Stress sequence                                                  | Five cycles of inspector hide, sidebar hide/show, and inspector restore completed on one exact PID: 20 transitions, empty stderr, no crash delta.                                        | Verified — corrected host; PID `25766`, wrapper checks after every action                   |
| Window        | Compact                                                          | Compact-width loaded workflow kept selection, filters, and output actions reachable.                                                                                                     | Verified — corrected host; `01-sandbox-compact-loaded.png` and AX                           |
| Window        | Regular                                                          | E2E window configuration logged exact outer frame `1180x760`; 1,500-file scan and post-scan interaction completed there.                                                                 | Verified — corrected host; lifecycle log, performance AX, `03-sandbox-performance-1500.png` |
| Window        | Wide                                                             | Runtime preference recorded exact outer frame `36 24 1440 900`; all three work areas remained usable. Computer Use normalized the screenshot to 1229x768.                                | Verified runtime; native-pixel screenshot blocked — capture normalization                   |
| Appearance    | Current dark appearance                                          | All retained final screenshots were visually inspected in the current dark appearance.                                                                                                   | Verified — corrected host; three retained screenshots                                       |
| Accessibility | Increased contrast, Reduce Motion, larger text, light appearance | These variants require changing user system settings and were not forced. Code-level fallback and accessibility-name tests pass.                                                         | Blocked — system-setting mutation outside audit authority                                   |
| Persistence   | Sandbox container                                                | Preferences and `LastReadyClipboard.json` resolved inside the distinct E2E container Application Support directory; production state was untouched.                                      | Verified — corrected host; on-disk container inspection and dependency tests                |
| Logs          | Structured telemetry and privacy                                 | Scan, persistence, copy, save, clear, accepted/rejected/failed/stale outcomes use typed metadata only; no payload, prompt, root, or destination is interpolated.                         | Verified — corrected host; unified log plus `AppTelemetryTests`                             |
| Performance   | 1,500-file Release fixture                                       | 14,055,000 source bytes and 3,513,000 file tokens: scan accepted in 330 ms; output/recovery ready in 611 ms; peak CPU 88.6%; peak RSS 252,368 KB; post-scan pane response 878 ms.        | Verified — corrected host; exact PID `51225`, logs, 601 samples, AX                         |
| Cleanup       | Processes, container data, fixtures, export                      | The wrapper reaped its exact child. E2E `Data`, runtime files, functional/performance fixtures, export and sampler output were removed; OS-owned container metadata shell was preserved. | Verified after final cleanup; exact-PID and filesystem checks                               |

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

- `docs/audit/codebase-combiner-e2e-2026-07-14/01-sandbox-compact-loaded.png` shows the synthetic `/private/tmp` fixture, scan summary, selected counts, and output actions after the final pane fix.
- `docs/audit/codebase-combiner-e2e-2026-07-14/02-sandbox-wide-recovery-concealed.png` shows the exact-frame wide run with recovery metadata concealed. The capture service normalized the file to 1229x768, so it is not claimed as native 1440x900 pixel evidence.
- `docs/audit/codebase-combiner-e2e-2026-07-14/03-sandbox-performance-1500.png` shows the corrected regular-width sandbox host with 1,500 synthetic files selected after the bounded Release scan; the output inspector is intentionally hidden to avoid retaining generated payload content.
- No retained screenshot contains `/Users/s1kor` or user source content.
- The wide recovery body is concealed by product behavior. Concealment/redaction is privacy evidence only; it is not cited as visual proof of the hidden payload.

## Automated Gates

| Check                 | Command                                                                                                                     | Result                                               |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| Swift formatting      | `cd SwiftExplorerApp && swiftformat --lint .`                                                                               | 43 files checked; 0 require formatting               |
| Swift tests           | `cd SwiftExplorerApp && swift test`                                                                                         | 86 tests; 0 failures                                 |
| Release warnings      | `cd SwiftExplorerApp && swift build -c release -Xswiftc -warnings-as-errors`                                                | Passed                                               |
| Node behavior         | `npm test`                                                                                                                  | 4 tests; 0 failures                                  |
| Node lint             | `npm run lint`                                                                                                              | Passed                                               |
| Repository formatting | `npm run format:check`                                                                                                      | Passed                                               |
| Script contract       | `script/tests/build_and_run_contract_test.sh`                                                                               | Passed                                               |
| Script syntax         | `bash -n script/build_and_run.sh Packaging/AppStore/build_app_store_package.sh script/tests/build_and_run_contract_test.sh` | Passed                                               |
| Package               | `Packaging/AppStore/build_app_store_package.sh --skip-signing`                                                              | Passed with strict signature verification            |
| Installed-app smoke   | `./script/build_and_run.sh --verify`                                                                                        | Exact PID launched, verified, terminated, and reaped |

## TDD And Failure Evidence

- Telemetry/outcome RED: missing typed recorder and `WorkspaceScanOutcome`; focused GREEN ended with 18 tests and no failures.
- Inspector-host RED: source still used native `.inspector`; GREEN removed native inspector and nested split usage.
- Constant-layout RED: hidden panes changed layout width; GREEN retains constant pane size and changes only transform/accessibility state.
- Toolbar RED: sidebar and inspector used stateful toolbar toggles; GREEN uses static controls.
- Wide-frame RED: restored window state overrode requested E2E geometry; GREEN adds an E2E-only exact outer-frame policy while production ignores the environment.
- Crash reports `030709`, `031512`, `032005`, and `032349` are retained only as local diagnostic evidence and are not product artifacts.

## Scope Boundary

No signing identity, provisioning profile, notarization, upload, purchase, public write, user-source mutation, or system-setting mutation was performed. Final readiness remains limited to the audited local sandbox workflow.
