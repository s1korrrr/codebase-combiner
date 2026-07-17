# Codebase Combiner 0.1.0 (1) Release Status

> Historical snapshot from 2026-07-15 at commit
> `ee53940423a87185c2f87329b54c0617da678910`. Current readiness must be evaluated
> from a fresh candidate build and its generated evidence, not from this dossier.

## Final verdict

**BLOCKED (historical)** — repository and local package preparation were green for this snapshot, but a production Mac App Store archive/package could not be created or validated without a matching provisioning profile. Required App Store Connect owner declarations, compliant screenshots, minimum-macOS runtime evidence, and accessibility interaction evidence also remained unverified.

- Date checked: 2026-07-15 (Europe/Warsaw)
- Shipping targets: macOS SwiftPM app and VS Code extension; iOS/iPadOS targets are **NOT APPLICABLE**.
- Production candidate: `com.s1korrrr.codebasecombiner`, version `0.1.0`, build `1`, macOS `13.0+`, `arm64`.
- Production toolchain: Xcode 26.6 (17F113), macOS SDK 26.5, Swift 6.3.3 on macOS 27 beta.
- Apple source check: 2026-07-15. Apple lists Xcode 26 as accepted for uploads; see [Submitting to the App Store](https://developer.apple.com/app-store/submitting/) and [Upcoming Requirements](https://developer.apple.com/news/?id=ueeok6yw). Xcode 27 beta is not used for the production build.
- OS 27 compatibility: PASS for build, unit tests, launch, and exact-PID smoke on macOS 27 beta; this is compatibility evidence, not submission validation.

## Release gates

| Gate                                  | Status         | Command or inspection                                                | Evidence                                                                           | Owner / next action                                                    |
| ------------------------------------- | -------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Repository cleanliness/isolation      | PASS           | `git status`, isolated release worktree                              | release branch and PR                                                              | Release lead                                                           |
| Node dependency resolution            | PASS           | `npm ci`; `npm audit`                                                | [TEST_EVIDENCE.md](TEST_EVIDENCE.md)                                               | Release lead                                                           |
| Node lint/format/tests/package        | PASS           | ESLint, Prettier, 11 tests, `vsce package`                           | [TEST_EVIDENCE.md](TEST_EVIDENCE.md)                                               | Release lead                                                           |
| Swift format/tests/Release build      | PASS           | SwiftFormat 0.61.1; 109 tests; warnings-as-errors                    | [TEST_EVIDENCE.md](TEST_EVIDENCE.md)                                               | Release lead                                                           |
| Production launch                     | PASS           | `./script/build_and_run.sh --verify`                                 | exact owned executable PID verified                                                | Release lead                                                           |
| macOS 27 compatibility                | PASS           | Release build, tests, launch on macOS 27 beta                        | [TEST_EVIDENCE.md](TEST_EVIDENCE.md)                                               | Release lead                                                           |
| macOS 13 minimum-runtime QA           | BLOCKED        | Runtime inventory                                                    | macOS 13 runtime/host unavailable                                                  | Owner: test on macOS 13 hardware/VM                                    |
| Accessibility interaction QA          | BLOCKED        | source/accessibility smoke only                                      | VoiceOver, keyboard-only, contrast variants not interactively swept                | Owner: run manual accessibility matrix                                 |
| Performance/leaks                     | BLOCKED        | `leaks <exact PID>`                                                  | 417 allocations / 20,016 bytes, process restricted; no app-owned symbols in report | Owner: capture Instruments Allocations/Leaks on supported stable macOS |
| Sandbox/entitlements                  | PASS           | `codesign -d --entitlements :-`; `codesign --verify --deep --strict` | sandbox and user-selected read/write only                                          | Release lead                                                           |
| Ad-hoc App Store bundle               | PASS           | packaging script `--skip-signing`                                    | `dist/app-store/Codebase Combiner.app` plus matching dSYM                          | Release lead                                                           |
| Mac App Store profile                 | BLOCKED        | decoded installed profiles                                           | only installed macOS profile is for `com.andrzej.spacelens`                        | Owner: create/download matching profile                                |
| Distribution app/installer identities | PASS           | `security find-identity`                                             | Apple Distribution and 3rd Party Mac Developer Installer for team `2NY8A789TN`     | Release lead                                                           |
| Signed installer/archive              | BLOCKED        | packaging script without `--skip-signing` exits 3                    | missing matching provisioning profile                                              | Owner: supply profile, rerun package script                            |
| App Store validation/upload           | BLOCKED        | no signed `.pkg`; no authorized upload performed                     | [BLOCKERS.md](BLOCKERS.md)                                                         | Owner: validate/upload after signed package                            |
| Security repository scan              | PASS           | Codex Security standard scan                                         | scan `5cfbf753-28e5-427a-90f3-144d1afafbad`, zero reportable findings              | Release lead                                                           |
| Security final diff scan              | BLOCKED        | Codex Security diff workspace opened                                 | setup session waiting for required Start scan confirmation                         | Owner: press Start scan in the Codex Security pane                     |
| Privacy manifest/data map             | PASS (repo)    | plist lint and source/data-flow inspection                           | [PRIVACY_DATA_MAP.md](PRIVACY_DATA_MAP.md)                                         | Owner must attest App Store answers                                    |
| App Review policy mapping             | BLOCKED        | current Apple guidelines reviewed                                    | legal/business declarations unavailable                                            | Owner: approve declarations                                            |
| App Store metadata draft              | PASS (draft)   | length/content review                                                | [APP_STORE_CHECKLIST.md](APP_STORE_CHECKLIST.md)                                   | Owner approval required                                                |
| Screenshots                           | BLOCKED        | dimension inventory vs Apple specification                           | no current capture has an accepted exact macOS size                                | Owner: capture from final signed build                                 |
| iOS/iPadOS release QA                 | NOT APPLICABLE | target/package inspection                                            | no iOS shipping target                                                             | None                                                                   |
| TestFlight                            | BLOCKED        | platform/release-channel inspection                                  | No Mac App Store package has been uploaded; no TestFlight build exists             | Upload an approved App Store candidate before beta distribution        |

## Devices and environments tested

- Apple silicon Mac, macOS 27.0 beta (26A5378j).
- Xcode 26.6, macOS SDK 26.5, arm64 Release product.
- No macOS 13 host, Intel Mac, or physical iOS device is applicable/available.
- Installed iOS runtimes are irrelevant because the repository has no iOS target.

## Accessibility and visual QA

Explicit labels/hints were added for filter, size, privacy, and support controls. Construction/accessibility smoke tests pass. A real VoiceOver order/action sweep, keyboard-only navigation sweep, light/dark/increased-contrast sweep, and final App Store screenshot capture remain external runtime work; therefore accessibility and screenshot gates are not marked ready.

## Security, privacy, signing, and upload

See [SECURITY_STATUS.md](SECURITY_STATUS.md), [PRIVACY_DATA_MAP.md](PRIVACY_DATA_MAP.md), and [BLOCKERS.md](BLOCKERS.md). The local artifact is ad-hoc signed and is not a distributable Mac App Store package. No archive was uploaded, no TestFlight build exists, and no App Store Connect state was mutated.

## Changes, pull request, and CI

- `35c920a` — dependency and release CI hardening.
- `f01a55c` — App Store packaging validation.
- `b1e775f` — bounded processing and privacy surfaces.
- `81e49ff` — blocked 0.1.0 release dossier.
- `33aa5ce` — independent-review traversal and recovery fixes.
- `9c8e20d`, `66f2c3f` — shell-contract CI portability fixes.
- Draft PR: [#4](https://github.com/s1korrrr/codebase-combiner/pull/4).
- GitHub Actions: push and pull-request `build-test` jobs passed for `66f2c3f` (2m28s and 2m33s).
- Main themes: deterministic release CI, signing/profile validation, package path safety, symbols, cancellation/resource bounds, privacy/support surfaces, accessibility semantics, and truthful release documentation.

## Exact next action required to submit

1. In Apple Developer, create/download a non-expired Mac App Store provisioning profile for `com.s1korrrr.codebasecombiner`, team `2NY8A789TN`, containing the installed Apple Distribution certificate.
2. Run `Packaging/AppStore/build_app_store_package.sh --provisioning-profile <path>` and retain its signed `.pkg`, signature report, embedded-profile checks, and symbols.
3. Capture accepted-size screenshots from that final build and complete the owner attestations in [APP_STORE_CHECKLIST.md](APP_STORE_CHECKLIST.md).
4. Validate and upload the signed package through Apple’s supported workflow, inspect processing warnings, and perform a stable-macOS smoke before requesting a new submission verdict.

## Residual risks

- Beta-host compatibility is not a substitute for stable/minimum-version QA.
- The restricted startup `leaks` capture cannot attribute every framework allocation; a clean Instruments capture remains required.
- App Store Connect legal, privacy, age-rating, export, content-rights, DSA, pricing, territory, and release-mode choices are intentionally not inferred.
- Screenshots are not prepared because altering/resizing nonconforming captures could misrepresent the final product.
