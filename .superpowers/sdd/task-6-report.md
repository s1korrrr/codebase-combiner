# Task 6 Report: Adaptive Native Workspace And Platform Visual Style

## Outcome

Task 6 replaces the fixed 1320×820 manual shell with one macOS 13-compatible adaptive workspace:

- `ContentView` now composes a native `NavigationSplitView` sidebar with an `HSplitView` preparation/inspector detail region.
- The root supports the approved 960×640 minimum. `AdaptiveWorkspaceLayout` derives compact, regular, and wide control/column metrics from the existing `WorkspaceLayoutPolicy`; the regular 960-point path uses a 430-point preparation minimum and 280-point inspector minimum instead of the former fixed 1320-point shell.
- The native sidebar and output inspector are independently collapsible: the sidebar uses the standard split-view affordance/command, while the inspector is controlled by the shared `AppController` toggle used by the toolbar and View menu.
- `WorkspaceSidebar` owns only workspace presentation: folder/refresh controls, scanning/empty states, the native outline hierarchy, and a privacy-conscious partial-scan disclosure that reports counts by reason without displaying skipped paths.
- `PreparationWorkspace` keeps prompt, filters, selection review, output format, and totals usable when the inspector is hidden. Its controls reflow between compact and expanded arrangements.
- `OutputInspector` shows exact current output, explicit truncation copy, and shared Copy/Save actions. Preview rendering is capped at 20,000 characters while controller operations continue to use the full payload.
- `RecoveredOutputView` shows only recovery metadata on load, supports Reveal and Hide, copies without revealing, and requests a destructive confirmation before clear. Cancel calls `cancelClearRecoveredOutput`; destructive confirmation calls `confirmClearRecoveredOutput`. Copy and clear status remain owned by `OutputStore`.
- `OutputStore.hideRecoveredOutput()` is the one behavior addition outside the view folder. It restores the existing `visiblePayload` concealment invariant after an explicit Reveal.
- Static hover scaling/elevated shadows were removed from file rows, filters, prompt, selected-file review, stats, and recovery content. Native controls retain platform hover/press behavior.
- The previous custom sidebar/preview drag state, support footer, duplicate selected-output action cards, and broad material-card stack were removed.

## Platform Style Boundary

`PlatformVisualStyle.swift` is the single availability boundary for modern presentation:

- macOS 26 and later use `glassEffect` only on the output action cluster.
- macOS 13 through 25 use a bounded regular-material fallback.
- Reduce Transparency or increased contrast uses an opaque semantic control background with a separator stroke.
- No content card, sidebar, preparation section, recovery surface, or root pane receives glass.
- The package remains declared at macOS 13.0, and both compile-time and runtime availability are guarded.

Apple Design Resources were refreshed on 2026-07-14 from <https://developer.apple.com/design/resources/>. Apple currently lists the macOS 27 UI Kit, SF Symbols 8 beta, SF Symbols 7, and Icon Composer. Task 6 intentionally uses the installed Xcode 26.6/macOS 26.5 SDK boundary and does not reference macOS 27 SDK-only symbols. The implemented glass modifier matches Apple’s documented `glassEffect(_:in:)` API at <https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)>.

## Accessibility And Privacy

- Every toolbar action carries a semantic `Label`, help, and prerequisite hint.
- Sidebar icon-only Choose and Refresh controls add explicit accessibility labels, hints, and help.
- Disabled Refresh, Copy, Save, Select All, Clear Selection, and invalid Apply states name the prerequisite.
- File checkboxes name the file or folder, current selection value, and directory-wide selection behavior.
- Prompt, selected-file review, current output, recovery output, progress, and summary surfaces expose named accessibility elements.
- Filter size validation is visible inline; invalid values disable Apply and preserve the existing store-side scan guard.
- Recovery metadata excludes payload text and root paths. Recovered source content is rendered only while `isRecoveredContentRevealed` is true.
- Partial-scan detail exposes only aggregate reason counts, never skipped file paths.
- Clear confirmation states that only Codebase Combiner’s recoverable copy is removed and source files are unchanged.

## TDD Evidence

Durable RED output is recorded in `.superpowers/sdd/task-6-red-evidence.txt`.

Four vertical cycles were exercised:

1. Adaptive compact/regular/wide metrics failed because `AdaptiveWorkspaceLayout` did not exist, then passed after the smallest policy implementation.
2. Disabled-action and partial-scan accessibility/privacy copy failed because `WorkspaceAccessibility` did not exist, then passed after the pure copy policy was added.
3. The compile-time view contract failed only on missing `WorkspaceSidebar`, `PreparationWorkspace`, `OutputInspector`, and `RecoveredOutputView`, then passed after the adaptive component slice compiled.
4. Re-concealing recovered output failed because the public hide action was absent, then passed with `visiblePayload == nil` after Hide.

The final focused test class covers all three existing layout modes, adaptive metrics, accessibility prerequisite copy, privacy-safe partial-scan copy, construction of every new root component, concealed recovered content on load, and concealment after Reveal.

## Files

- Added `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/WorkspaceSidebar.swift`
- Added `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/PreparationWorkspace.swift`
- Added `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/OutputInspector.swift`
- Added `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/RecoveredOutputView.swift`
- Added `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/PlatformVisualStyle.swift`
- Rebuilt `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/ContentView.swift`
- Updated `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/FileNodeRow.swift`
- Updated `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/FiltersView.swift`
- Updated `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/PromptEditor.swift`
- Updated `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/StatsBar.swift`
- Updated `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/VisualEffects.swift`
- Updated `SwiftExplorerApp/Sources/CodebaseExplorerApp/Stores/OutputStore.swift`
- Added `SwiftExplorerApp/Tests/CodebaseExplorerAppTests/AdaptiveWorkspaceSmokeTests.swift`

Per task authority, `PLAN.md`, `TODO.md`, `MEMORY.md`, and the SDD ledger were not edited.

## Verification

All requested Task 6 gates passed on 2026-07-14:

- Baseline `cd SwiftExplorerApp && swift test` — 59 tests passed before edits.
- `cd SwiftExplorerApp && swift test --filter AdaptiveWorkspaceSmokeTests` — 4 tests passed after the final GREEN cycle.
- `cd SwiftExplorerApp && swiftformat .` — completed; no files required formatting.
- `cd SwiftExplorerApp && swiftformat --lint .` — 0 of 40 files require formatting.
- `cd SwiftExplorerApp && swift test` — 63 tests passed.
- `cd SwiftExplorerApp && swift build -Xswiftc -warnings-as-errors` — Debug build passed.
- `cd SwiftExplorerApp && swift build -c release -Xswiftc -warnings-as-errors` — Release build passed.
- `cd SwiftExplorerApp && swift package dump-package` — minimum platform remains `macos 13.0`.
- `git diff --check` — passed.
- Static visual-style invariant — zero `hoverLift`, `appSurface`, legacy sidebar/preview width storage, or 1320-point root-minimum references remain in the view implementation; the only explicit `glassEffect` call is the guarded functional-chrome boundary.
- `./script/build_and_run.sh --verify` — the worktree bundle built, was ad-hoc signed/validated, and launched from `/Users/s1kor/dev/apps/codebase_combiner/.worktrees/andrzej_agent_sota_lab/dist/app-store/Codebase Combiner.app`.
- A final exact-path smoke launched the current packaged executable as PID `53340`, then terminated only that captured PID. The earlier failed Automation/Accessibility window-bounds probe was also terminated; no Task 6 smoke process remains.

## Scope Boundary

Task 6 provides logic-level adaptive construction tests and a basic exact-binary package/launch smoke. It does not claim the Task 7 interaction matrix, screenshot evidence, isolated Application Support/clipboard fixture, or click-through proof. Those remain explicitly deferred.

The truthful readiness label for this slice is **build-clean with packaged launch smoke**. Runtime interaction-clean, consistency-clean, and polish-ready labels require the Task 7 isolated E2E matrix.
