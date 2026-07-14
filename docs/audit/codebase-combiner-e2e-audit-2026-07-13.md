# App E2E Audit Report: Codebase Combiner

## Outcome

- Audit date: 2026-07-14. The filename retains the implementation-plan date.
- Audited artifact: an ad-hoc-signed, isolated copy of the packaged Release app produced from `dist/app-store/Codebase Combiner.app` by `./script/build_and_run.sh --e2e`.
- Audited platform: native macOS SwiftUI, including native menus, Settings, open/save panels, keyboard commands, relaunch recovery, and adaptive window layouts.
- Readiness label: **interaction-clean for the audited local core workflow, with explicit blocked variants**.
- Release boundary: this is not an App Store or release-candidate claim. Signing, notarization, upload, and owner-account work remain separate gates.

The real packaged app completed its primary workflow: choose a workspace, inspect scan results, change selection and filters, add a prompt, switch format, copy, save, relaunch, and operate concealed recovery. Four runtime defects or hardening gaps were found and fixed. The final 79-test Swift suite, warnings-as-errors Release build, Node checks, packaging verification, and isolated launch verification are recorded below.

## Isolation And Safety

- The tracked fixture is `script/fixtures/e2e-workspace`. It contains text, hidden, excluded, and true NUL-byte binary cases.
- `CODEBASE_COMBINER_E2E_DATA_DIR` routes drafts into a temporary directory and preferences into `com.s1korrrr.codebasecombiner.e2e`; production defaults and Application Support drafts are not used.
- The temporary host bundle uses `com.s1korrrr.codebasecombiner.e2ehost`, so window restoration is isolated from the production app.
- `CODEBASE_COMBINER_E2E_WINDOW_SIZE` supplies deterministic compact, regular, and wide launch sizes.
- The script records the exact launched PID and stops processes by exact PID/name enumeration; it no longer uses broad `pkill`.
- Clipboard tests serialized the existing pasteboard, compared only length/hash metadata, and restored it immediately. The initial clipboard contained zero items.
- Saves and generated performance fixtures stayed inside temporary E2E data directories. No user source folder was opened or modified.
- Unified-log messages contain counts and outcomes only. They do not contain source text, prompt text, workspace paths, or destination paths.

## Tool Coverage

| Surface                                           | Tool                                                                                                          | Result                    |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ------------------------- |
| Build, tests, process, package, logs, performance | Terminal and macOS build/test workflow                                                                        | Verified                  |
| Native UI, menus, panels, Settings, screenshots   | Computer Use accessibility tree and real actions                                                              | Verified for audited rows |
| SwiftUI polish and adaptive layout                | Source inspection plus 960×640, 1180×760, and 1440×900 packaged-app runs                                      | Verified                  |
| Browser destination                               | Chrome was launched by the real Support action, but the browser-control runtime reported no available browser | Blocked beyond launch     |
| Embedded/local web                                | The app has no embedded or local web surface                                                                  | Not applicable            |

## Automated Gates

| Check                      | Command                                                                         | Result                                       |
| -------------------------- | ------------------------------------------------------------------------------- | -------------------------------------------- |
| Swift formatting           | `cd SwiftExplorerApp && swiftformat --lint .`                                   | 43 files checked; 0 require formatting       |
| Swift tests                | `cd SwiftExplorerApp && swift test`                                             | 79 tests; 0 failures                         |
| Release warnings           | `cd SwiftExplorerApp && swift build -c release -Xswiftc -warnings-as-errors`    | Passed                                       |
| Node behavior              | `npm test`                                                                      | 4 tests; 0 failures                          |
| Node lint                  | `npm run lint`                                                                  | Passed                                       |
| Repository formatting      | `npm run format:check`                                                          | Passed after formatting this report          |
| Script syntax              | `bash -n script/build_and_run.sh Packaging/AppStore/build_app_store_package.sh` | Passed                                       |
| Package                    | `Packaging/AppStore/build_app_store_package.sh --skip-signing`                  | Passed; bundle signature verification passed |
| Installed-app launch smoke | `./script/build_and_run.sh --verify`                                            | Passed                                       |
| Isolated real launch       | `CODEBASE_COMBINER_E2E_WINDOW_SIZE=<size> ./script/build_and_run.sh --e2e`      | Passed at all three audited sizes            |

The dependency-isolation test was first observed RED because `AppDependencies` did not exist, then GREEN with three tests. The status, filter-cancel, geometry, and telemetry fixes also had focused failing tests or source guards before their fixes, followed by focused and full-suite GREEN runs.

## Scenario Matrix

| Surface       | Scenario                                     | Actual result                                                                                                                         | Status                                              | Evidence                                                                 |
| ------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------ |
| Launch        | First isolated launch                        | Packaged app foregrounded with empty state; isolated bundle, defaults, draft directory, stdout, stderr, and exact PID were recorded   | Verified                                            | `01-first-launch.png`; `AppDependenciesTests`                            |
| Launch        | Relaunch same E2E state                      | Saved draft and format preference reloaded from the isolated domain; recovered source remained concealed                              | Verified                                            | `05-recovery-concealed.png`                                              |
| Workspace     | Choose fixture through `NSOpenPanel` / Cmd-O | Real folder panel accepted only the tracked fixture; scan completed                                                                   | Verified                                            | `04-compact-fixture-partial-scan.png`                                    |
| Workspace     | Default partial scan                         | README and Swift source accepted; hidden and excluded counts surfaced without paths                                                   | Verified                                            | `04-compact-fixture-partial-scan.png`                                    |
| Workspace     | Disclosure and selection                     | Skip reasons expanded; file tree expanded; row toggle, Select All, Clear Selection, and disabled prerequisite help updated coherently | Verified                                            | AX tree and counts                                                       |
| Workspace     | Context action                               | Secondary click offered no context menu; no context-only operation exists                                                             | Acceptable / N/A                                    | Real secondary action                                                    |
| Filters       | Toolbar/menu show and hide                   | Shared filter visibility state and labels remained coherent                                                                           | Verified                                            | AX tree                                                                  |
| Filters       | Include/exclude and hidden input             | Broad allow list plus hidden-files-off accepted three text files and counted the binary as skipped                                    | Verified                                            | `09-filtered-binary-scan.png`; live log accepted=3, skipped=1            |
| Filters       | Editor Cancel and Apply                      | Cancel now preserves committed values; Apply commits once and refreshes                                                               | Verified after fix                                  | `FilterEditorPolicyTests`; real rerun                                    |
| Filters       | Size control                                 | Valid range, field, stepper, slider, and validation semantics present; no large-file UI boundary mutation was needed for the fixture  | Verified by automated boundary tests / UI inventory | `AppPreferencesTests`; AX tree                                           |
| Prompt        | Empty and realistic prompt                   | Rebuild completed, export stayed gated while building, and repeat success status returned correctly                                   | Verified after fix                                  | `AppCommandStateTests`; real rerun                                       |
| Format        | Markdown / Plain Text                        | Main segmented control and Settings preference stayed synchronized; output metadata followed the selected format                      | Verified                                            | `08-settings-support.png`; saved payload metadata                        |
| Copy          | Disabled prerequisite help                   | Copy names the missing selection/output prerequisite                                                                                  | Verified                                            | AX help                                                                  |
| Copy          | Current output via Cmd-Shift-C               | 639 characters were copied; clipboard hash matched the saved output; original clipboard restored                                      | Verified                                            | SHA-256/length metadata only                                             |
| Save          | Current output via Cmd-S                     | `combined.md` written only inside E2E storage; 639 bytes and same payload hash as copy                                                | Verified                                            | Temporary saved-file metadata                                            |
| Recovery      | Concealed relaunch, Reveal, Hide             | Metadata appeared without source content; reveal and hide changed visibility without mutating the draft                               | Verified                                            | `05-recovery-concealed.png`, `06-recovery-revealed.png`                  |
| Recovery      | Copy Last while concealed                    | 238-character recovered payload copied while content remained concealed; clipboard restored                                           | Verified                                            | AX state plus hash/length metadata only                                  |
| Recovery      | Clear then Cancel                            | Confirmation appeared with safe default; Cancel closed it and draft remained                                                          | Verified                                            | Draft existence and AX state                                             |
| Recovery      | Confirm Clear                                | UI confirmation was not clicked because Computer Use requires action-time destructive confirmation                                    | Blocked                                             | Confirm-clear store tests pass                                           |
| Menus         | File, Edit, View, Support                    | Choose, Refresh, Save, Copy, filters, inspector, sidebar, Settings, and Support labels/enablement matched canonical actions           | Verified                                            | Menu AX inventory                                                        |
| Shortcuts     | Cmd-O, Cmd-R, Cmd-Shift-C, Cmd-S, Cmd-,      | Commands used canonical UI operations with correct enablement                                                                         | Verified                                            | Real UI/panel state                                                      |
| Settings      | Standard Settings scene                      | Exactly one Settings window; General and Support tabs usable and synchronized                                                         | Verified                                            | `08-settings-support.png`                                                |
| Support       | External support action                      | Canonical URL was visible and clicking the real control launched Chrome                                                               | Partially verified                                  | Destination navigation inspection blocked by unavailable browser runtime |
| Panels        | Inspector hide/restore                       | Center expanded and inspector returned with recovered state intact                                                                    | Verified                                            | `07-compact-inspector-restored.png`                                      |
| Panels        | Sidebar hide/restore                         | Final Release rerun remained alive with empty stderr and usable inspector                                                             | Verified after fix                                  | `10-sidebar-collapsed.png`, `11-sidebar-restored-after-fix.png`          |
| Window        | Compact 960×640                              | CGWindow width 960; all three panes and scrollable actions remained reachable                                                         | Verified                                            | `03-compact-960x640-deterministic.png`                                   |
| Window        | Regular 1180×760                             | CGWindow bounds exactly 1180×760; clean three-pane layout                                                                             | Verified                                            | `13-regular-1180x760.png`                                                |
| Window        | Wide 1440×900                                | CGWindow bounds exactly 1440×900; settled layout clean with no persistent wrapping/overlap                                            | Verified                                            | `12-wide-1440x900.png`                                                   |
| Appearance    | Current dark appearance                      | Semantic contrast, hierarchy, disabled states, and selection remained readable                                                        | Verified                                            | Screenshot set                                                           |
| Appearance    | Light and increased contrast                 | No app-local override exists; changing system display settings requires action-time confirmation                                      | Blocked                                             | System setting intentionally unchanged                                   |
| Accessibility | Names, roles, help, keyboard                 | Controls exposed descriptive names/roles; icon-only and disabled controls named outcomes/prerequisites                                | Verified                                            | AX tree and `AdaptiveWorkspaceSmokeTests`                                |
| Accessibility | Reduce Motion / larger system text           | Source semantics and policy tests inspected; changing system accessibility settings requires confirmation                             | Blocked for live variant                            | System setting intentionally unchanged                                   |
| Logs          | Privacy and errors                           | Operational lifecycle/scan/export/persistence events present; no content/path leakage; final sidebar rerun stderr empty               | Verified after fix                                  | Live unified log summary below                                           |
| Performance   | 1,500-file disposable scan                   | Completed without runaway CPU or memory; process stayed alive                                                                         | Verified                                            | Bounded metrics below                                                    |

## Findings And Fixes

| Severity | Finding                                                                                                | Runtime proof                                                                                                                          | Fix                                                                                                                                           | Re-verification                                                                                                                                    |
| -------- | ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| High     | Restoring the sidebar at compact width could crash Release with an AppKit update-constraints exception | Real hide/show sequence terminated the first Release process and emitted `NSGenericException` about repeated Update Constraints passes | Removed geometry-time mutation of inspector visibility; pane visibility is now changed only by explicit user action                           | Source guard first failed then passed; exact packaged Release hide/show rerun kept PID alive, restored both panes, and produced 0-byte stderr      |
| Medium   | A second successful rebuild could leave the header at “Building combined output…”                      | Prompt change produced a fresh copy/save payload while the display status remained stale                                               | Removed duplicate suppression from the output-status subscription so a repeated success can replace the controller’s intervening build status | Focused regression test first failed then passed; real prompt/filter/format rerun returned to “Saved recoverable output.”                          |
| Medium   | Filter Editor Cancel mutated live filters and triggered a rescan                                       | Changing the sheet draft then clicking Cancel changed the main include list and accepted-file set                                      | Added explicit draft values and commit policy; only Apply writes bindings and refreshes                                                       | Two policy tests first failed to compile before implementation, then passed; real Cancel preserved `swift`, while Apply committed the broader list |
| Medium   | Core scan/export/persistence workflows lacked useful operational telemetry                             | Unified log during a 1,500-file refresh contained lifecycle only                                                                       | Added privacy-safe count/outcome events for scan, recovery save/load/clear, copy, and save                                                    | Source privacy/category guard first failed then passed; real packaged app emitted the expected events without paths/content                        |

No additional reproducible core-runtime defect remained after the final exact Release reruns.

## Log Evidence

The final packaged-app interaction emitted:

```text
Workspace scan started
Workspace scan finished accepted=3 selected=3 skipped=1
Recovery save succeeded files=3 bytes=648
Current output copy succeeded characters=725
```

The earlier launch also emitted `Recovery load succeeded available=true`. Event payloads deliberately exclude workspace URLs, save destinations, filenames, prompt strings, and source text. Errors use generic operation names rather than interpolating potentially private error details.

## Performance Evidence

The disposable workspace contained 1,500 Swift files (about 5.9 MB on disk, about 2.6 MB accepted content):

- Full open-panel-through-ready interaction: 16,950 ms, including UI automation polling.
- Exact Release refresh completion: 1,318 ms.
- Baseline RSS: 175,616 KB.
- Maximum RSS: 179,760 KB; delta 4,144 KB.
- Peak sampled CPU: 90.2%; CPU returned to 0 after completion.
- Final selection: 1,500/1,500 files, 646,500 file tokens; process remained alive.

The refresh reused the unchanged selected-file snapshot, so it measured scanning and publication rather than forcing an unnecessary output rebuild.

## Blocked Or Out-Of-Scope Rows

| Action                                                                         | Reason                                                                                                                            | Existing evidence / next step                                                                                                                 |
| ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Confirm destructive Clear in the real UI                                       | Computer Use requires action-time confirmation immediately before the destructive click                                           | Cancel path verified; isolated storage proved; store tests verify confirmed clear removes only the recovered draft                            |
| Light, increased contrast, Reduce Motion, and larger system-text live variants | The app has no app-local appearance/accessibility test override; changing macOS system settings requires action-time confirmation | Current dark variant, AX semantics, source inspection, and automated policies passed; run a separate confirmed system-variant pass if desired |
| Support destination browser inspection                                         | The real action launched Chrome, but browser control returned “No browser is available”                                           | Canonical URL and external-launch behavior verified; inspect final destination in a browser-enabled session                                   |
| System Events resize                                                           | Accessibility permission was unavailable to that scripting path                                                                   | Replaced by deterministic E2E launch sizes, CGWindow bounds, Computer Use, and screenshots                                                    |
| Signing, notarization, upload, or store submission                             | External credentials/writes are outside this audit                                                                                | Keep as a separate release gate                                                                                                               |

## Evidence Index

- `docs/audit/codebase-combiner-e2e-2026-07-14/01-first-launch.png`
- `docs/audit/codebase-combiner-e2e-2026-07-14/03-compact-960x640-deterministic.png`
- `docs/audit/codebase-combiner-e2e-2026-07-14/04-compact-fixture-partial-scan.png`
- `docs/audit/codebase-combiner-e2e-2026-07-14/05-recovery-concealed.png`
- `docs/audit/codebase-combiner-e2e-2026-07-14/06-recovery-revealed.png`
- `docs/audit/codebase-combiner-e2e-2026-07-14/07-compact-inspector-restored.png`
- `docs/audit/codebase-combiner-e2e-2026-07-14/08-settings-support.png`
- `docs/audit/codebase-combiner-e2e-2026-07-14/09-filtered-binary-scan.png`
- `docs/audit/codebase-combiner-e2e-2026-07-14/10-sidebar-collapsed.png`
- `docs/audit/codebase-combiner-e2e-2026-07-14/11-sidebar-restored-after-fix.png`
- `docs/audit/codebase-combiner-e2e-2026-07-14/12-wide-1440x900.png`
- `docs/audit/codebase-combiner-e2e-2026-07-14/13-regular-1180x760.png`

Raw stdout/stderr, draft payloads, save output, clipboard serialization, and generated large-workspace files remain untracked in temporary E2E directories because they can contain source-like content and are not needed to reproduce the audited claims.
