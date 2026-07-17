# Test Evidence

Historical evidence captured on 2026-07-15 from the isolated release worktree at
commit `ee53940423a87185c2f87329b54c0617da678910`. These counts and artifact hashes
describe that immutable snapshot; they are not the current branch's audit results.

| Area                      | Command                                                                                              | Result                                                                         |
| ------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Node install/audit        | `npm ci`; `npm audit`                                                                                | 433 packages; 0 vulnerabilities                                                |
| Node quality              | `npm run lint`; `npm run format:check`; `npm test`                                                   | clean; 11/11 passing                                                           |
| VSIX                      | `npm run package`                                                                                    | `codebase-combiner-0.0.1.vsix`, 85 files, 193.92 KB                            |
| Swift formatting          | verified SwiftFormat 0.61.1 archive SHA-256, then `swiftformat --lint . --disable redundantSendable` | 0/47 files require formatting                                                  |
| Swift tests               | `cd SwiftExplorerApp && swift test`                                                                  | 109 tests, 0 failures                                                          |
| Swift Release             | `swift build -c release -Xswiftc -warnings-as-errors`                                                | PASS                                                                           |
| Shell contracts           | packaging profile test and `build_and_run_contract_test.sh`                                          | PASS                                                                           |
| App bundle                | `build_app_store_package.sh --skip-signing`                                                          | valid arm64 ad-hoc bundle; Info.plist/entitlements/signature valid             |
| Symbols                   | `dwarfdump --uuid` in packaging flow                                                                 | executable/dSYM UUIDs match                                                    |
| Runtime                   | `./script/build_and_run.sh --verify`                                                                 | exact owned production executable PID verified and reaped                      |
| Signed-path negative test | packaging without profile                                                                            | exit 3 with exact missing-profile blocker                                      |
| Leak sample               | `leaks` against exact PID                                                                            | process restricted; 417 allocations / 20,016 bytes; no app-owned symbols found |

Artifact hashes are recorded in [RELEASE_MANIFEST.json](RELEASE_MANIFEST.json). The App Store bundle and VSIX are local build outputs and are intentionally not committed.

Not verified: macOS 13 runtime, Intel, final Mac App Store signature/package, Apple validation, App Store processing, VoiceOver/keyboard/contrast interaction matrix, and accepted-size screenshots.
