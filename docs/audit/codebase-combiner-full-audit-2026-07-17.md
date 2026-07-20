# Codebase Combiner Full Audit — 2026-07-17

## Decision

- Repository implementation: **PASS**, subject to the PR review and hosted CI gates recorded on the resulting commit.
- Local native package: **package-ready for ad-hoc validation**.
- Developer ID distribution: **blocked:external** on a production signing identity, Apple notarization, and publication approval.
- App Store Connect upload: **blocked:external** on the matching provisioning profile, signed installer, app record, metadata, screenshots, upload, and Apple review.

## Scope And Standards

The review covered the VS Code extension, native SwiftUI app, filesystem boundaries, output generation, persistence, telemetry, sandbox packaging, Developer ID scripts, App Store scripts, CI workflows, documentation, and the sandboxed E2E harness.

Primary references used during the audit:

- [VS Code Workspace Trust extension guide](https://code.visualstudio.com/api/extension-guides/workspace-trust)
- [VS Code virtual workspaces extension guide](https://code.visualstudio.com/api/extension-guides/virtual-workspaces)
- [Node.js file system API](https://nodejs.org/api/fs.html)
- [Apple privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Apple describing required-reason API use](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Apple App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [GitHub Actions secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)

Repository standards came from `AGENTS.md`, CI, release contracts, and the existing architecture documents.

## Findings Resolved

| Area                       | Defect                                                                                                                   | Resolution                                                                                                                                                                                                                                |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| VSIX traversal             | A context-selected symbolic-link directory could become the traversal root.                                              | Root selection and collection now use `lstat` and fail closed on symbolic-link roots.                                                                                                                                                     |
| VSIX reporting             | Binary, oversized, unreadable, symbolic-link, and workspace-limit skips were partially silent.                           | Collection publishes a path-free structured skip summary and the completion notice reports nonzero reasons.                                                                                                                               |
| VSIX filters               | Submitting an empty one-run filter restored configured restrictions instead of preserving the explicit empty input.      | Run filter parsing now preserves submitted empties and validates the input kind.                                                                                                                                                          |
| VSIX trust                 | The manifest claimed full untrusted-workspace support while workspace-scoped configuration affected collection.          | Support is now `limited` with all relevant settings declared as restricted configurations.                                                                                                                                                |
| Output integrity           | Plain-text path headers accepted line separators that could forge additional headers.                                    | Display paths strip CR, LF, U+2028, and U+2029 before rendering.                                                                                                                                                                          |
| Native filesystem          | Opening a file replaced by a FIFO could block indefinitely before `fstat`.                                               | Secure opens include `O_NONBLOCK` and reject every non-regular descriptor.                                                                                                                                                                |
| Native traversal           | Directory enumeration errors could silently return partial success.                                                      | Immediate-child enumeration now throws; unreadable subdirectories are reported explicitly.                                                                                                                                                |
| Native preferences         | Malformed persisted `NaN`, infinity, or extreme size values could reach integer conversion.                              | Persisted values are normalized before publication and validation requires a finite value in range.                                                                                                                                       |
| Native root semantics      | “Skip hidden” rejected an explicitly selected dot-prefixed workspace root.                                               | Hidden filtering applies only below the selected root.                                                                                                                                                                                    |
| Determinism                | Localized sorting could change the bounded accepted subset by locale or OS.                                              | Traversal and flattened output use locale-independent UTF-8 lexical ordering.                                                                                                                                                             |
| E2E lifecycle              | A stale host or concurrent reset/build could share the bundle ID and race app-owned cleanup.                             | Exact executable discovery plus an atomic session lock serialize reset, build, runtime, and cleanup across worktrees.                                                                                                                     |
| Release evidence isolation | E2E packaging shared the production App Store output directory and could overwrite its manifest and checksums.           | E2E now owns `dist/app-store-e2e`; cleanup removes that output and legacy E2E residue while production evidence remains unchanged.                                                                                                        |
| Apple privacy              | Distribution manifests omitted the File Timestamp required-reason API category used by `fstat` and file metadata access. | Both manifests declare `3B52.1` for user-granted files and `C617.1` for app-container metadata.                                                                                                                                           |
| App Store evidence         | The package lacked a bundled license, operation lock, and source-bound checksums.                                        | At the time of this audit the bundle included the then-current MIT `LICENSE`; the project switched to Apache-2.0 with `NOTICE` on 2026-07-20. Packaging emits `release-manifest.json` and verified `SHA256SUMS` under a fail-closed lock. |
| Notarization               | Final checksums selected lexicographic artifacts, and generated resume commands lost a custom app name.                  | The script binds exact manifest assets and preserves the effective `--app-name` in resumable commands.                                                                                                                                    |
| CI signing                 | The decoded Developer ID PKCS#12 file did not explicitly establish owner-only permissions.                               | The import step uses `umask 077` and `chmod 600`.                                                                                                                                                                                         |
| Documentation              | Test-runner, privacy, TestFlight, and license statements had drifted.                                                    | Current docs now match the implementation and distinguish repo proof from external release gates.                                                                                                                                         |

No unresolved Critical or Important code finding remained before the final review gate.

## Verification Evidence

| Gate                    | Result                                                                                                                                        |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Node tests              | **29/29 passed** with `node --test`.                                                                                                          |
| Swift tests             | **125/125 passed** with XCTest.                                                                                                               |
| JavaScript lint/format  | ESLint and Prettier passed.                                                                                                                   |
| Swift format            | Exact CI SwiftFormat `0.61.1` reported `0/47` files requiring formatting.                                                                     |
| Release compile         | `swift build -c release -Xswiftc -warnings-as-errors` passed.                                                                                 |
| Dependency audit        | Runtime and full `npm audit` reported zero vulnerabilities; 379 registry signatures and 25 attestations verified.                             |
| VSIX                    | Version `0.0.2`; `vsce package` produced 41 files, 92.33 KB, and the inventory contract passed.                                               |
| Shell/release contracts | Shell syntax, provisioning profile, Developer ID build/notarization, open-source, process lifecycle, and VSIX inventory contracts passed.     |
| App Store package       | Ad-hoc sandboxed bundle passed plist, strict codesign, entitlement, architecture, dSYM UUID, privacy, license, manifest, and checksum checks. |
| Production launch       | Exact packaged PID launched, remained alive for verification, terminated, and reaped; stdout and stderr were empty.                           |
| App-owned errors        | Unified logging returned no error or fault entry for subsystem `com.s1korrrr.codebasecombiner` during the final runtime window.               |

The final local environment was macOS 27.0, Xcode 26.6, macOS SDK 26.5, Apple Swift 6.3.3, with a packaged deployment target of macOS 13.0.

## Native E2E Matrix

The rebuilt sandboxed host ran at 960×640 against `/private/tmp/CodebaseCombinerE2EFixture`:

- selected folder access succeeded under App Sandbox with user-selected read/write entitlement;
- scan accepted 2 UTF-8 files, 571 bytes, and 142 file tokens;
- hidden, excluded, not-included, and binary skip presentations were exercised without revealing skipped paths;
- tree expansion, one-file deselection, Select All, prompt-token updates, Markdown/plain-text switching, and preview rebuilding passed;
- current-output copy passed;
- native save produced a 633-byte exact fixture export with both expected file headers;
- a no-reset relaunch recovered 2-file metadata while keeping content concealed;
- Copy Last succeeded without revealing the recovered content;
- both E2E and production stdout/stderr logs were empty;
- the exact host was reaped and all E2E runtime, fixture, export, and app-owned container data were removed.

## Remaining External Gates

- No production Developer ID identity was used, no request was sent to Apple notarization, and no GitHub release was published.
- No matching Mac App Store provisioning profile or distribution-signed installer was available for this audit.
- No App Store Connect record, privacy answers, metadata, screenshots, TestFlight build, upload, or review state was changed.
- A macOS 13 machine or VM was not available; the binary and plist declare 13.0, but runtime compatibility at the floor remains an external test-lab gate.
- Destructive recovered-output clearing is covered by focused store/UI-policy tests; the final native sweep did not permanently delete it through the UI.

These limitations do not block the repository PR, but they prevent any claim of notarized-distributable or App Store-upload readiness.
