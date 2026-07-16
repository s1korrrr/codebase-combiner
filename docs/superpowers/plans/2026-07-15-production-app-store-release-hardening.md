# Production App Store Release Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a freshly verified Mac App Store release candidate and complete versioned release dossier, fixing every safe repository-side issue and naming every genuine external blocker.

**Architecture:** Keep the SwiftPM app and existing deterministic packaging script. Treat source verification, runtime proof, signed distribution packaging, metadata/attestations, and App Store Connect mutations as separate gates. Store non-sensitive evidence under `docs/release/0.1.0/`; keep generated bundles, packages, logs, profiles, credentials, and archives out of Git.

**Tech Stack:** Swift 6, SwiftUI for macOS 13+, SwiftPM, XCTest, SwiftFormat 0.61.1, Node 24, Mocha/Chai, ESLint, Prettier, shell packaging, native Apple signing tools.

## Global Constraints

- Release candidate source is `origin/main` commit `5035205ea001bf7a8d12e3f3007c81f0f7382f40` plus intentional commits on `feat/andrzej_release_hardening_2026_07_15`.
- The only discovered Apple shipping platform is macOS; do not create an iOS target.
- Do not upload, submit, distribute TestFlight, merge, tag, publish, alter pricing/storefronts, or make legal/account declarations without exact fresh owner approval.
- Use only current official Apple sources for time-sensitive submission rules.
- Do not commit secrets, profiles, certificates, archives, DerivedData, customer data, or sensitive logs.

---

### Task 1: Freeze the release candidate and current requirements

**Files:**

- Modify: `PLAN.md`
- Modify: `TODO.md`
- Create: `docs/release/0.1.0/RELEASE_STATUS.md`
- Create: `docs/release/0.1.0/RELEASE_MANIFEST.json`

**Interfaces:**

- Consumes: repository HEAD, official Apple submission pages, local Xcode/SDK/signing inventory.
- Produces: dated requirement snapshot and initial gate rows used by all later tasks.

- [ ] Run `git status --short --branch`, `git remote -v`, and `git log -1 --format='%H %cI %s'`; record the exact source coordinate.
- [ ] Run `xcode-select -p`, `xcodebuild -version`, `xcodebuild -showsdks`, `xcrun swift --version`, simulator/device inventory, signing identity inventory, profile inventory, `gh auth status`, and read-only App Store Connect credential discovery.
- [ ] Refresh the official Apple upcoming-requirements, App Review, upload, privacy, accessibility, screenshot, DSA, and export-compliance pages and record retrieval date plus direct URLs.
- [ ] Run the bundled `apple-release doctor` and `inspect --json`; classify any SwiftPM limitation without fabricating Xcode project data.
- [ ] Write the initial matrix with PASS, FAIL, BLOCKED, NOT APPLICABLE, or NOT YET VERIFIED; every non-PASS row names evidence, owner, and next action.

### Task 2: Prove the clean static/build/test baseline

**Files:**

- Create: `docs/release/0.1.0/TEST_EVIDENCE.md`
- Modify if a failure is validated: the smallest affected source/test/config file.

**Interfaces:**

- Consumes: clean isolated worktree and pinned lockfiles/tool versions.
- Produces: exact test counts, build results, warning state, and package results for the gate matrix.

- [ ] Run `npm ci`, `npm run lint`, `npm run format:check`, `npm test`, and `npm run package`.
- [ ] Verify SwiftFormat 0.61.1 and run `swiftformat --lint . --disable redundantSendable`.
- [ ] Run `swift test` and `swift build -c release -Xswiftc -warnings-as-errors` from `SwiftExplorerApp`.
- [ ] Run shell contract tests and `git diff --check`.
- [ ] For each deterministic failure, capture the exact signal, write a regression test that fails for the defect, implement the smallest repair, and re-run focused plus full gates before committing.

### Task 3: Prove the macOS bundle and primary runtime

**Files:**

- Modify if validated: `Packaging/AppStore/*`, `script/build_and_run.sh`, or the smallest affected Swift source/test.
- Update: `docs/release/0.1.0/TEST_EVIDENCE.md`

**Interfaces:**

- Consumes: Release binary and packaging configuration.
- Produces: inspected `.app` evidence, runtime outcomes, accessibility/performance/memory classifications.

- [ ] Run `Packaging/AppStore/build_app_store_package.sh --skip-signing` and retain only non-sensitive summaries/checksums.
- [ ] Inspect the built plist, privacy manifest, architectures, entitlements, signature flags, nested code, profile presence, extended attributes, and bundle resources with native tools.
- [ ] Run `./script/build_and_run.sh --verify`; capture exact PID ownership, launch/termination result, stderr, and crash/hang delta.
- [ ] Use the isolated E2E host for folder selection, scan, filters, selection, preview, copy, save, Settings, recovery, sidebar/inspector visibility, appearance, keyboard, and accessibility variants when local permissions permit.
- [ ] Run bounded Release performance and comparable memory/leak checks for scan/output/recovery; classify unavailable minimum-macOS or macOS 27 SDK proof explicitly.

### Task 4: Prove distribution signing and package readiness

**Files:**

- Modify if validated: `Packaging/AppStore/build_app_store_package.sh`, its tests, and documentation.
- Update: `docs/release/0.1.0/RELEASE_STATUS.md`
- Update: `docs/release/0.1.0/BLOCKERS.md`

**Interfaces:**

- Consumes: exact bundle ID/version/build, installed identities, matching non-secret provisioning profile path.
- Produces: inspected distribution-signed `.app` and installer `.pkg`, or a precise fail-closed blocker.

- [ ] Match profile Team ID, application identifier, platform, expiration, and entitlements to `com.s1korrrr.codebasecombiner` without copying the profile into Git.
- [ ] If matched assets exist, run the signed packaging command and inspect main/nested signatures, Team ID, entitlements, profile, architectures, privacy manifest, dSYM expectations, and installer signature.
- [ ] Run Apple-supported local validation available for the resulting package; do not upload without a separate digest-bound approval.
- [ ] If any required asset or App Store record is unavailable, record exact missing state, owner, and account-side next action.

### Task 5: Close security, privacy, supply-chain, and App Review gates

**Files:**

- Create: `docs/release/0.1.0/SECURITY_STATUS.md`
- Create: `docs/release/0.1.0/PRIVACY_DATA_MAP.md`
- Create: `docs/release/0.1.0/APP_REVIEW_NOTES.md`
- Create: `docs/release/0.1.0/APP_STORE_CHECKLIST.md`
- Modify if validated: the smallest vulnerable source/test/config file.

**Interfaces:**

- Consumes: source, lockfiles, entitlements, privacy manifest, logs, support links, persisted data behavior, official policy.
- Produces: validated findings, data-flow map, factual review notes, and owner-attestation blockers.

- [ ] Inspect secrets, unsafe filesystem/process/network behavior, links, logging, temporary files, persistence, URL handling, sandbox scope, dependencies/licenses, and required-reason APIs.
- [ ] Run the configured standard repository security workflow; use a deeper scan only if risk signals justify it.
- [ ] Fix critical/high and release-blocking medium findings test-first, then run focused and full security verification.
- [ ] Map every local data category through source, purpose, storage, retention, deletion, recipients, tracking, and identity linkage; reconcile source behavior with the privacy manifest and draft labels.
- [ ] Draft factual review notes and metadata, while leaving privacy, age-rating, export, DSA, content-rights, pricing, territory, and release-control answers as explicit owner confirmations.

### Task 6: Assemble metadata/assets and final release evidence

**Files:**

- Create: `docs/release/0.1.0/RELEASE_NOTES.md`
- Update: `docs/release/0.1.0/RELEASE_STATUS.md`
- Update: `docs/release/0.1.0/RELEASE_MANIFEST.json`
- Modify: `PLAN.md`
- Modify: `TODO.md`
- Modify: `MEMORY.md` only for newly learned durable facts.

**Interfaces:**

- Consumes: all earlier gate evidence, current product behavior, final diff, GitHub/CI state.
- Produces: a self-contained release dossier and exact final verdict.

- [ ] Validate icon and screenshot files with current dimensions/formats, generate only truthful captures, and inventory missing localizations/assets.
- [ ] Generate release notes from the actual diff and record version/build consistency.
- [ ] Inspect `git diff origin/main...HEAD`, run the security diff workflow, and request an independent code/release review.
- [ ] Address valid findings, re-run the entire relevant verification matrix, check CI, and update every gate row with fresh evidence.
- [ ] Issue exactly one verdict: READY FOR SUBMISSION, READY FOR TESTFLIGHT ONLY, BLOCKED, or NOT READY; name the exact next action and residual risks.

## Self-Review

- Spec coverage: all eleven mission phases map to Tasks 1-6; iOS-only gates are explicitly not applicable unless target discovery changes.
- Placeholder scan: no implementation step relies on an unspecified fallback; conditional distribution work is bound to actual signing/profile evidence.
- Type consistency: evidence artifacts and version coordinate `0.1.0` are consistent across tasks.
