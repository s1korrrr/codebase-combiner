# SwiftUI Polish Audit: Codebase Combiner

Date: 2026-06-29

## Scope

- App: Codebase Combiner macOS SwiftUI app.
- Target: SwiftPM executable `CodebaseExplorerApp`, packaged as `dist/app-store/Codebase Combiner.app`.
- Audit focus: native macOS polish, animation/runtime performance, persistence recovery, packaging readiness, logs, tests, and visual correctness.
- References checked: Apple SwiftUI performance guidance, Xcode app responsiveness guidance, XCTest guidance, and AppKit window restoration headers from the local macOS SDK.

## Readiness Call

Repo-side status: polish-ready for local release candidate testing.

Mac App Store status: not upload-ready yet. The local package, sandbox entitlements, privacy manifest, tests, and launch smoke pass, but final App Store submission still needs a matching provisioning profile, installer signing identity/package upload path, App Store Connect app record, and a distribution-signed smoke test.

## Issues Found And Fixed

| Area | Finding | Fix |
| --- | --- | --- |
| Visual state | The top-bar Copy action looked primary even when no files were selected. | Disabled Copy now renders with the same subdued bordered style as other unavailable actions. |
| Launch focus | The prompt editor could become first responder on launch, showing a text cursor in an otherwise idle app. | Prompt focus is explicitly cleared after launch and the empty editor no longer scrolls. |
| Layout polish | The prompt editor stretched too tall in the idle layout. | Prompt editor height is now stable at 120 points, keeping the dashboard balanced. |
| Idle performance | The empty-state symbol used an infinite floating animation, which kept SwiftUI rendering while idle. | Empty-state symbol is now static; scanning still uses a scoped progress animation. |
| Window restoration | macOS/SwiftUI attempted to restore prior window state. | App delegate now opts out of secure and non-secure state restoration, sets the app default not to keep windows, and marks created windows non-restorable. Unified logs still show AppKit restoration diagnostics, but the visible launch state is clean. |

## Verification Evidence

| Check | Result |
| --- | --- |
| `cd SwiftExplorerApp && swiftformat --lint . && swift build && swift test` | Passed, 8 XCTest tests. |
| `npm test && npm run lint && npm run format:check` | Passed, 4 Mocha tests plus lint/format checks. |
| `./script/build_and_run.sh --verify` | Passed, packaged app launched from `dist/app-store/Codebase Combiner.app`. |
| `Packaging/AppStore/build_app_store_package.sh --skip-signing` | Passed through the launch-smoke path; local ad-hoc package is valid on disk. |
| Privacy manifest inspection | Passed; declares UserDefaults API reason `CA92.1`, no collected data, no tracking. |
| Entitlements inspection | Passed; sandbox and user-selected read/write entitlement are present. |
| Idle process sample | Passed; packaged app sampled at 0.0% CPU and about 45 MB memory after idle launch. |
| Visual proof | Passed; window-scoped screenshot captured at `docs/audit/codebase-combiner-polish-audit-final-window-2026-06-29.png`. |

## Workflow Coverage

| Workflow | Coverage |
| --- | --- |
| Fresh app launch | Live packaged launch verified. |
| Empty workspace state | Live screenshot verified; no wrong foreground capture, no prompt cursor, disabled actions are visually subdued. |
| Last ready payload recovery | Live screenshot verified; persisted payload banner exposes Copy Last and Clear. |
| File scanning and filters | Covered by `TreeLoaderTests`; live picker interaction was not automated in this pass. |
| Combined output formatting | Covered by `CombinedOutputBuilderTests` for Markdown and plain text. |
| Draft persistence | Covered by `ClipboardDraftStoreTests`; live restore state visible in packaged app. |
| Copy/save actions | Formatting and persistence covered by tests; live Save dialog was not exercised to avoid creating user-facing files during audit. |
| Settings/support entry points | Static review and visible UI coverage; support URL remains `https://buymeacoffee.com/s1korrrr`. |

## Performance Notes

- Removed the only idle infinite animation found in the SwiftUI surface.
- Retained short, user-triggered animation paths: scan indicator, hover lift, transitions, and copy toast.
- Current idle sample from the packaged app: 0.0% CPU, about 45 MB memory in `top`.
- The app still uses macOS 13-compatible SwiftUI APIs, so newer Liquid Glass-only APIs remain intentionally out of compiled code.

## App Store Blockers

- Create/verify App Store Connect record for bundle ID `com.s1korrrr.codebasecombiner`.
- Install or select a matching Mac App Store provisioning profile.
- Verify the installer signing identity and product package creation/upload path.
- Re-run `Packaging/AppStore/build_app_store_package.sh --provisioning-profile /path/to/profile.provisionprofile` without `--skip-signing`.
- Smoke-test the distribution-signed app before upload.
- Reconfirm the support/donation CTA is acceptable for the final App Review positioning; remove or de-emphasize it for the store build if needed.

## Final Notes

No blocking repo-side UI, runtime, persistence, or test issue remains from this audit. The remaining blockers are Apple distribution/account artifacts and one signed-build smoke test.
