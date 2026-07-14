# Codebase Combiner Native Adaptive Rebuild Design

## Status

- Approved in conversation on 2026-07-13.
- Implementation has not started.
- Deployment target remains macOS 13.
- The current implementation toolchain is Xcode 26.6 with the macOS 26.5 SDK.
- macOS 27 SDK-only implementation and runtime proof require Xcode 27 and are an explicit toolchain gate, not an implied part of the Xcode 26 build.

## Product Goal

Make the native macOS app feel calm, efficient, privacy-conscious, and thoroughly Mac-like while preserving every supported macOS 13 workflow. The rebuild must remove constrained-layout friction, reduce decorative visual noise, clarify disabled and error states, isolate workflow state from views, and establish one availability-gated styling boundary for modern macOS visual features.

The primary workflow is:

1. Choose a workspace folder.
2. Review the scanned file tree and any skipped-file summary.
3. Apply filters and select the files to include.
4. Add an optional prompt prefix.
5. Review the exact combined payload.
6. Copy or save the payload.

## Scope

### Included

- Replace the fixed manual three-pane shell with a native adaptive three-column workspace compatible with macOS 13.
- Extract workflow, output, and preference state from `ContentView` into focused observable stores and services.
- Make recovered output metadata visible by default while requiring an explicit reveal before showing recovered source contents.
- Add confirmation and cancel behavior for clearing a recovered draft.
- Flatten the visual hierarchy and remove hover movement from static surfaces.
- Add bounded Liquid Glass presentation where supported by the installed SDK and runtime.
- Isolate newer presentation APIs behind a platform visual-style boundary.
- Consolidate Settings into one canonical macOS Settings scene.
- Add shared command handlers and consistent menu, toolbar, button, and shortcut behavior.
- Make disabled states, validation failures, partial scans, persistence errors, and export errors explicit and actionable.
- Complete a real packaged-app E2E interaction sweep and update release evidence.

### Excluded

- Raising the minimum deployment target above macOS 13.
- Duplicating the product into separate legacy and modern UI implementations.
- Adding cloud sync, accounts, AI features, network services, or new third-party dependencies.
- Changing the VS Code extension's product behavior except where shared documentation or release checks must stay accurate.
- Installing Xcode 27, changing Apple Developer account state, uploading a build, submitting for review, or altering App Store Connect.
- Implementing unverified macOS 27 SDK-only symbols with the currently installed macOS 26.5 SDK.

## Compatibility Strategy

The macOS 13 path is a first-class product implementation, not a degraded fallback. Shared behavior, information architecture, accessibility, keyboard commands, error recovery, and persistence are identical on all supported versions.

Presentation changes by availability:

- macOS 13 through 25: semantic system colors, native materials, standard controls, and restrained shadows.
- macOS 26 and later, when compiled with the current SDK: narrowly applied Liquid Glass for floating functional chrome such as a toolbar cluster or output-inspector action surface. Glass must not be nested across cards or used as a decorative background.
- macOS 27 SDK-only additions: confined to the same platform-style boundary after Xcode 27 becomes available. Until then, the release report records this as a separate toolchain-blocked verification gate.

Compile-time availability and runtime availability must both remain truthful. The macOS 13 build must compile without referencing unavailable symbols outside guarded code.

## Information Architecture

### Workspace Window

The main window uses a native adaptive three-column structure:

1. **Workspace sidebar**
   - Current workspace name or a clear empty-state title.
   - Choose Folder and Refresh actions.
   - Selectable file hierarchy.
   - Partial-scan and skipped-file summary when applicable.
   - No prominent donation or support action.

2. **Preparation workspace**
   - Compact status header.
   - Prompt prefix editor.
   - Collapsible filters.
   - Selected-file review.
   - File, token, and byte totals.
   - Primary workflow remains usable when the inspector is collapsed.

3. **Output inspector/detail**
   - Current output format and payload metadata.
   - Exact current combined payload.
   - Copy and Save actions.
   - Honest preview truncation notice while operations continue to use the full payload.
   - Recovered-output summary and explicit reveal policy when no current payload exists.

At narrower widths, the output column collapses behind a toolbar or View-menu toggle. The sidebar is independently collapsible. The layout must not rely on the current 1320-point minimum, and the primary workflow must remain usable without horizontal clipping.

### Settings

Use one canonical `Settings` scene. Remove the parallel custom Settings window. Settings include:

- Default output format.
- Default filter visibility.
- Hidden-file behavior.
- Validated maximum file size.
- Include and exclude extensions.
- A neutral Support section or link that does not compete with the primary workflow.

### Menus And Commands

Named shared actions back both UI controls and commands:

- File: Choose Folder, Refresh Workspace, Copy Combined Output, Save Combined Output.
- View: Show or Hide Sidebar, Filters, and Output Inspector.
- Help or Support: optional support link with neutral presentation.
- Standard Settings command opens the canonical Settings scene.

Shortcuts and disabled logic must match between buttons and menus. A disabled action exposes a help or accessibility explanation naming the missing prerequisite.

## Visual And Motion System

The desired emotional quality is calm confidence for a professional developer utility.

- Prefer native sidebar, list, toolbar, form, and inspector structures over hand-painted panels.
- Use hierarchy through spacing, type weight, alignment, and selection state before adding containers.
- Remove scale and elevated-shadow hover effects from static cards, statistics, and content sections.
- Retain pointer feedback on actual controls through native button behavior.
- Keep iconography semantic and consistent across toolbar, menu, settings, and contextual actions.
- Use monospaced digits for changing counts and monospaced text for payload content.
- Avoid large fixed empty areas in the sidebar and avoid tiny controls caused by over-dense toolbars.
- Keep repeated interactions effectively immediate. Occasional disclosure, inspector, toast, and confirmation transitions should remain brief and orientation-preserving.
- Reduce Motion replaces spatial transitions with short fades or immediate state changes.
- Increased contrast and reduced transparency must preserve legibility; modern glass styling falls back to more opaque semantic materials.

## Recovered Output Privacy Policy

Recovered source payload content is potentially sensitive.

- On relaunch, show only file count, output format, token estimate, and generation time.
- Do not display recovered source content until the user selects **Reveal Last Output**.
- Keep **Copy Last** available without revealing the content.
- **Clear Saved Output** opens a confirmation surface with explicit Cancel and Clear actions.
- Clearing removes only the app-owned recovered draft, not source files or clipboard history.
- A current-session payload may display automatically because it was generated through an active user workflow.
- Logs must never contain prompt text, source contents, recovered contents, or exported payloads.

## Architecture

### `WorkspaceStore`

Owns:

- Selected root URL and workspace identity.
- Scan state and active scan identifier.
- File hierarchy and flattened file snapshots.
- Selection identifiers and selected totals.
- Filter application.
- Skipped-file and partial-scan summary.
- Stale-result rejection.

It depends on a filesystem-loading service and exposes named user actions. Views do not start detached work or calculate file-system results directly.

### `OutputStore`

Owns:

- Prompt prefix.
- Output format.
- Current combined payload.
- Recovered draft metadata and content.
- Whether recovered content is revealed.
- Confirmation state for clearing recovered output.
- Copy, save, persistence, and recovery outcomes.

It depends on output building, persistence, pasteboard, and save-panel boundaries. The stores may coordinate through explicit input snapshots rather than reading each other's private state.

### `AppPreferences`

Owns validated persistent preferences:

- Include extensions.
- Exclude extensions.
- Maximum file size.
- Hidden-file behavior.
- Output format default.
- Filter visibility default.

Views edit validated bindings or draft values. Invalid values remain visible for correction but cannot silently trigger a scan.

### Views

Split the current root responsibilities into focused components:

- App entry and scene configuration.
- App commands.
- Workspace root.
- Workspace sidebar.
- Preparation workspace.
- Output inspector.
- Recovered-output summary and confirmation.
- Settings.
- Platform visual-style modifiers.

Views render observable state and invoke named actions. The AppKit delegate remains limited to launch policy or window behavior that SwiftUI cannot express cleanly.

## Data Flow

1. Choosing a folder gives `WorkspaceStore` a security-scoped user-selected URL.
2. `WorkspaceStore` starts a scan with a unique identifier and validated preferences.
3. The loader returns a hierarchy plus a structured summary of unreadable, excluded, hidden, binary, and oversized files.
4. `WorkspaceStore` accepts results only when their identifier still matches the active scan.
5. Selection and prompt changes produce an immutable output input snapshot.
6. `OutputStore` builds the current payload and metadata from that snapshot.
7. Copy and Save operate on the full payload even when the UI preview is truncated.
8. Successful current output is persisted atomically as the recoverable draft.
9. Relaunch loads recovered metadata and content but keeps the content concealed until explicitly revealed.

## Error And Recovery Behavior

- Folder cancellation is a no-op and does not erase the current workspace.
- Folder access or scan failure names the failed operation and offers retry or Choose Another Folder.
- Unreadable files are counted and summarized instead of silently disappearing.
- A partially readable workspace remains usable.
- Invalid filters or maximum-size values show inline validation and prevent automatic scanning until corrected.
- A superseded scan cannot replace newer state.
- Persistence failure preserves the current in-memory output and offers retry.
- Pasteboard and save failures show actionable feedback and remain available for another attempt.
- A missing recovered-draft file is treated as an empty recovered state; malformed or unreadable app-owned draft data is surfaced as a recoverable error and can be cleared with confirmation.
- No error path silently substitutes different user data or a stale payload.

## Accessibility And Input

- Every icon-only or ambiguous control has a meaningful `.help`, accessibility label, and hint where needed.
- Disabled actions explain why they are disabled.
- Menu commands, shortcuts, toolbar controls, and visible buttons share names and handlers.
- Keyboard navigation reaches the file hierarchy, prompt editor, filters, selected-file review, inspector, and confirmation actions in a predictable order.
- Dynamic Type and increased contrast must not clip or overlap core controls.
- Reduce Motion and reduced transparency produce usable equivalent states.
- Destructive confirmation defaults focus to Cancel, not Clear.

## Test Strategy

### Test-First Automated Coverage

Add failing tests before behavior implementation for:

- Preference and filter validation.
- Structured scan summaries for skipped and unreadable inputs.
- Stale scan-result rejection.
- Adaptive layout policy at compact, regular, and wide widths.
- Current-output versus recovered-output visibility policy.
- Recovered draft reveal and clear-confirmation state transitions.
- Persistence and export failure recovery.
- Shared command availability rules.

Retain and extend the existing tests for `TreeLoader`, `CombinedOutputBuilder`, `ClipboardDraftStore`, and `TokenEstimator`. Node extension tests must remain green.

### Static And Package Gates

- SwiftFormat lint.
- Swift warnings-as-errors build where supported by the package/toolchain.
- Focused and complete Swift test suites.
- Node tests, ESLint, and Prettier check.
- Shell syntax checks for build and packaging scripts.
- Privacy manifest and entitlement inspection.
- Unsigned/ad-hoc App Store bundle assembly and signature validation.
- Git diff and secret-sensitive output review.

### Real Packaged-App E2E Matrix

Use a disposable fixture and the actual packaged app to verify:

- First launch and relaunch.
- Empty state and workspace selection.
- Successful and partial scans.
- Filter validation, editing, apply, and cancellation.
- File selection, Select All, and Clear Selection.
- Prompt editing and output-format changes.
- Exact output preview and truncation notice.
- Copy and Save, including safe failure/recovery paths where reproducible.
- Recovered-output summary, Reveal, Copy Last, and Clear confirmation/cancel.
- Settings, menus, shared shortcuts, context menus, tooltips, and disabled explanations.
- Sidebar and output-inspector collapse and restoration.
- Minimum, typical, and large window sizes.
- Light and Dark appearance, Reduce Motion, increased contrast, and reduced transparency where controllable.
- Unified logs after storage, scan, copy, save, and recovery workflows.
- Quit and relaunch persistence.

Do not clear real recovered data or overwrite the user's clipboard during E2E. Tests must use an isolated Application Support location, disposable fixture data, and a preserved/restored pasteboard strategy where interaction tooling permits it.

## Release And Readiness Gates

Implementation completion is not equivalent to App Store submission readiness.

- `interaction-clean` requires the reachable-control matrix to pass or explicitly record blocked/not-applicable actions.
- `polish-ready` additionally requires consistency, accessibility descriptions, appearance, motion, logs, and targeted performance checks.
- `package-ready` additionally requires fresh unsigned/ad-hoc bundle validation and release documentation.
- Final App Store upload remains externally blocked until current Apple distribution and installer identities, provisioning profile, App Store Connect record, metadata, privacy labels, screenshots, and owner-controlled declarations are verified.
- macOS 27 SDK-only enhancements and proof remain a separate toolchain gate until Xcode 27 is installed.

The final report uses the weakest truthful label and separates repository, package, toolchain, Apple-account, and manual-review gates.

## Rollback

Work is implemented in cohesive commits on `feat/andrzej_agent_sota_lab`.

- Store extraction and behavior changes remain separable from visual restructuring.
- The platform visual-style boundary can fall back entirely to macOS 13 semantic materials without reverting workflow logic.
- Packaging inputs, persisted draft schema compatibility, user source files, and the protected `main` branch remain unchanged unless a tested migration is explicitly planned.
- No implementation step deletes user source data, real clipboard history, Apple credentials, or App Store state.

## Acceptance Criteria

- The package still declares macOS 13 as its minimum version.
- The app builds and tests with the installed Xcode 26.6/macOS 26.5 toolchain.
- The primary workflow is usable at the approved compact window width without clipping.
- Sidebar and output inspector independently collapse and restore.
- Recovered payload contents are concealed until explicitly revealed.
- Clearing recovered output has a verified confirmation and cancel path.
- Support no longer competes visually with primary workflow actions.
- One Settings scene and shared command handlers remain.
- Static surfaces no longer animate or elevate on hover.
- Modern presentation is bounded, availability-gated, and has a semantic-material fallback.
- Explicit validation and recovery replace silent failure for changed boundaries.
- Automated tests, package gates, packaged-app interaction checks, and the audit report contain fresh evidence.
- Remaining macOS 27 SDK and App Store account blockers are named without weakening the completed macOS 13+ result.
