# Developer ID Open-Source Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Codebase Combiner outside the Mac App Store as a Developer ID-signed, Apple-notarized DMG whose exact source and release process are public under MIT.

**Architecture:** Preserve the Store package lane and add an independent `Packaging/DeveloperID` orchestration boundary. Pure release metadata and verification logic is tested without credentials; signing, notarization, and publication are explicit opt-in gates using Keychain or protected GitHub environments.

**Tech Stack:** SwiftPM, Bash, Python 3 standard library, Node/npm, GitHub Actions, Apple `codesign`, `notarytool`, `stapler`, `spctl`, and `hdiutil`.

## Global Constraints

- Distribution is outside the Mac App Store using Developer ID Application signing and Apple notarization.
- The complete application source and release pipeline are public under MIT.
- App Sandbox and user-selected read/write access remain enabled.
- No Apple credential, private key, password, Keychain file, or secret-bearing log enters Git.
- Pull-request jobs never receive release signing credentials.
- The Mac App Store packaging lane remains intact and explicitly separate.
- Notarization submission, remote repository mutations, push, tag, PR, and release publication require explicit approval.

---

### Task 1: Integrate the release-hardening baseline

**Files:**

- Modify: Git branch `feat/andrzej_open_source_release`
- Maintain: `PLAN.md`, `TODO.md`, `MEMORY.md`

**Interfaces:**

- Consumes: `feat/andrzej_release_hardening_2026_07_15` at its verified head.
- Produces: one clean baseline for direct-distribution work.

- [x] Verify the open-source branch is an ancestor and the worktree is clean.
- [x] Fast-forward to the release-hardening head.
- [x] Run the existing Node and Swift suites.
- [x] Record the baseline head and results.

### Task 2: Developer ID packaging contract

**Files:**

- Create: `Packaging/DeveloperID/tests/run_tests.sh`
- Create: `Packaging/DeveloperID/tests/build_release_contract_test.sh`
- Create: `Packaging/DeveloperID/DeveloperID.entitlements`
- Create: `Packaging/DeveloperID/build_release.sh`
- Create: `Packaging/DeveloperID/README.md`

**Interfaces:**

- Consumes: SwiftPM app target and existing bundle assets.
- Produces: `dist/developer-id/Codebase Combiner.app`, DMG, hashes, SBOM, and machine-readable evidence.

- [x] Write contract tests for help, validation, skip-signing, signing identity selection, notarization opt-in, and secret-safe logs.
- [x] Run the tests and confirm failure because the Developer ID script is absent.
- [x] Implement the smallest fail-closed build/sign/package interface.
- [x] Run the tests and unsigned dry-run until green.
- [x] Refactor only after the green state is preserved.

### Task 3: Open-source release and CI boundary

**Files:**

- Create: `RELEASING.md`
- Create: `THIRD_PARTY_NOTICES.md`
- Modify: `README.md`
- Modify: `INSTALL.md`
- Modify: `SECURITY.md`
- Create: `.github/workflows/release.yml`
- Modify: `.gitignore`

**Interfaces:**

- Consumes: Task 2 CLI and artifact layout.
- Produces: contributor-facing release procedure and protected tag workflow.

- [x] Add contract checks for required workflow permissions, protected environment, and absence of PR signing.
- [x] Confirm checks fail before the workflow/docs exist.
- [x] Document reproducible public build steps and the private credential boundary.
- [x] Add checksum, SBOM, and provenance steps without adding runtime dependencies.
- [x] Run format/lint and workflow/static contract checks.

### Task 4: Release-candidate verification

**Files:**

- Generate only: `dist/developer-id/**` (ignored)
- Update: `PLAN.md`, `TODO.md`, `MEMORY.md`

**Interfaces:**

- Consumes: Tasks 2 and 3 plus the local Developer ID identity.
- Produces: local release evidence and exact remaining external blockers.

- [x] Run all Node, Swift, formatting, and contract tests freshly.
- [ ] Build the architecture target and inspect slices.
- [ ] Sign with hardened runtime and secure timestamp if the identity is available.
- [ ] Verify bundle signatures, entitlements, and local runtime behavior.
- [x] Inspect the final diff for secrets and unintended Store regressions.
- [x] Update task records with exact evidence.

### Task 5: Notarize and publish after approval

**Files:**

- External: Apple notary service and GitHub repository/release.
- Generate: notarization log, stapled DMG, checksums, SBOM, GitHub release assets.

**Interfaces:**

- Consumes: approved external-action scope, protected credentials, and the verified local candidate.
- Produces: notarized public download and source tag.

- [ ] Obtain explicit approval for Apple submission and GitHub mutations.
- [ ] Submit asynchronously with `notarytool`, retain the submission ID immediately, and wait with a bounded timeout.
- [ ] Require `Accepted`, staple, validate, and assess with Gatekeeper.
- [ ] Enable the agreed repository security settings and push the reviewed branch.
- [ ] Create the signed version tag and release from the same commit.
- [ ] Download the public DMG, verify its hash, and run the quarantined install smoke.
