# Mac App Store Release Checklist: Codebase Combiner

Statuses are deliberately limited to `verified`, `blocked`, and `not applicable`. Repository/package evidence is not used to promote an owner/account gate.

## Account And App Record

| Item                                                | Status   | Evidence                                                                                                                      |
| --------------------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Apple Developer Program team confirmed for this app | blocked  | Valid local signing identities exist, but current Apple Developer/App Store Connect team access was not inspected or changed. |
| Bundle identifier registered                        | blocked  | The local bundle uses `com.s1korrrr.codebasecombiner`; registration was not checked in Apple Developer.                       |
| App Store Connect app record exists                 | blocked  | No account access or external write was authorized.                                                                           |
| Version and build numbers set                       | verified | Ad-hoc bundle reports version `0.1.0`, build `1`.                                                                             |

## Signing And Sandbox

| Item                                                                   | Status   | Evidence                                                                                                                                     |
| ---------------------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Application distribution identity available locally                    | verified | `security find-identity` detected a valid Apple Distribution identity on 2026-07-14; it was not used for this ad-hoc package.                |
| Installer distribution identity available locally                      | verified | A valid Mac installer distribution identity was detected on 2026-07-14; no installer package was created.                                    |
| Matching Mac App Store provisioning profile valid                      | blocked  | No profile was supplied, embedded, or matched to the bundle/team during this audit.                                                          |
| App Sandbox enabled                                                    | verified | Effective signed entitlement `com.apple.security.app-sandbox = true`.                                                                        |
| Entitlements minimized and reviewed                                    | verified | The only other effective entitlement is `com.apple.security.files.user-selected.read-write = true`.                                          |
| Strict signature inspection captured                                   | verified | `codesign --verify --deep --strict --verbose=2` passes for the ad-hoc `.app`; signature flags identify it as ad-hoc with no team identifier. |
| Distribution signature, hardened runtime, and signed installer package | blocked  | `--skip-signing` intentionally produced no profile or `.pkg`; Gatekeeper rejection of this local ad-hoc artifact is expected.                |

## Privacy

| Item                                                       | Status   | Evidence                                                                                                                                              |
| ---------------------------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Data collection inventory complete for repository behavior | verified | Local source files, prompt prefix, preferences, and one recoverable payload; no app networking, tracking, or analytics.                               |
| Privacy manifest present and valid                         | verified | `PrivacyInfo.xcprivacy` parses; UserDefaults reason `CA92.1`, tracking false, collected-data list empty.                                              |
| Privacy labels confirmed in App Store Connect              | blocked  | Owner must enter and confirm the declarations against the submitted build.                                                                            |
| Permission purpose strings reviewed                        | verified | The app uses user-selected folder/save panels and no camera, microphone, location, contacts, or similar protected service.                            |
| Third-party SDK privacy reviewed                           | verified | The Swift package has no third-party dependency.                                                                                                      |
| Logs exclude sensitive content                             | verified | Typed telemetry contains outcomes, counts, byte/character totals, and window dimensions only; tests and source review found no path or payload field. |

## Product Quality

| Item                                           | Status   | Evidence                                                                                                                                                                  |
| ---------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Unit and boundary tests pass                   | verified | `swift test`: 86 tests, 0 failures; `npm test`: 4 tests, 0 failures.                                                                                                      |
| Format/lint checks pass                        | verified | SwiftFormat checked 43 files; ESLint and Prettier passed.                                                                                                                 |
| Release build succeeds with warnings as errors | verified | `swift build -c release -Xswiftc -warnings-as-errors` passed with Xcode 26.6/SDK 26.5.                                                                                    |
| Ad-hoc App Store-style bundle assembles        | verified | Bundle ID `com.s1korrrr.codebasecombiner`, version `0.1.0` (1), minimum macOS `13.0`; strict signature verifies.                                                          |
| Clean launch of packaged artifact              | verified | `./script/build_and_run.sh --verify` launched, rechecked, terminated, and reaped exact PID `76936`; stdout/stderr were empty.                                             |
| Primary workflow interaction sweep             | verified | Signed sandbox matrix covers open, partial scan, filters, selection, prompt, format, copy, save, recovery, menus, Settings, pane stress, relaunch, and cleanup.           |
| Destructive recovery clear through UI          | blocked  | Cancel was verified; final destructive Computer Use action was not authorized. Store-level confirmed-clear and retry tests pass.                                          |
| Accessibility and appearance variants          | blocked  | Labels/help/dark appearance are verified; VoiceOver plus light, Reduce Motion, increased contrast, larger text, and reduced-transparency system variants were not forced. |
| macOS 13 runtime smoke                         | blocked  | The binary and plist declare 13.0, but this audit ran on macOS 27; a macOS 13 machine/VM was not available.                                                               |
| Bounded Release performance                    | verified | 1,500-file fixture: scan 330 ms, output/recovery 611 ms, peak 88.6% CPU, peak 252,368 KB RSS, pane response 878 ms, no stderr/crash delta.                                |
| E2E residue/process cleanup                    | verified | App-owned E2E state, runtime files, fixtures, exports, E2E bundle residue, and exact app processes were absent after cleanup.                                             |

## App Store Assets

| Item                                          | Status         | Evidence                                                                                                                           |
| --------------------------------------------- | -------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| App icon in local bundle                      | verified       | Packaging generated `AppIcon.icns` from the repository asset.                                                                      |
| App Store screenshots prepared                | blocked        | Local audit screenshots exist, but required App Store dimensions, localization, and final product-page selection are not complete. |
| App name, subtitle, description, and keywords | blocked        | Must be finalized in App Store Connect.                                                                                            |
| Category and age rating                       | blocked        | Bundle category is Developer Tools; owner must complete the App Store Connect age rating and confirm category.                     |
| Support and privacy URLs                      | blocked        | An in-app support destination exists; final public support/privacy URLs were not owner-confirmed for the product page.             |
| Marketing URL                                 | not applicable | Optional for v1 unless the owner chooses to add one.                                                                               |
| Review notes and demo credentials             | blocked        | No demo credentials are needed; review notes must still explain local-only folder access and recovery storage.                     |
| macOS 27 SDK-only assets/features             | blocked        | Installed Xcode 26.6 contains the macOS 26.5 SDK. Xcode 27 is required before implementation or proof of SDK-only macOS 27 work.   |

## Release Decision

- Repository-ready: **yes**, subject to the checked-in branch and fresh gates listed in the audit report.
- Package-ready: **yes for local ad-hoc validation only**; the `.app` has a strict-valid ad-hoc signature, macOS 13 minimum, privacy manifest, and minimal sandbox entitlements.
- Ready for App Store Connect upload: **no**.
- External blockers: matching provisioning profile, verified team/app record, distribution-signed app and installer package, metadata, screenshots, privacy/legal declarations, upload, and Apple review.
- Toolchain blocker: true macOS 27 SDK-only work requires Xcode 27; running the SDK 26.5 build on macOS 27 does not satisfy this gate.
- Submission owner: the user with Apple Developer and App Store Connect authority.
- Next action: obtain and verify the matching provisioning profile and app record, then run the distribution packaging path and re-inspect the resulting signed `.app` and `.pkg` before upload.
