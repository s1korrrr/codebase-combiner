# Releasing Codebase Combiner

The intended macOS release channel is a Developer ID-signed and Apple-notarized DMG distributed outside the Mac App Store. The VS Code extension has an independent version and release cadence.

## Version and source policy

- macOS tags use `macos-v<version>`, beginning with `macos-v0.1.0`.
- VS Code extension tags use `vscode-v<version>`.
- A release artifact must be built from the exact immutable tag named by its release manifest.
- The public source, packaging scripts, entitlements, checksums, SBOM, and release evidence must correspond to that tag.
- Apple secure timestamps and notarization tickets mean final signed bytes are not reproducible byte-for-byte; the pre-signing source build remains auditable.

## Local release gates

From a clean release branch:

```sh
npm ci
npm test
npm run lint
npm run format:check
npm audit --omit=dev
npm audit
npm audit signatures
npm run package
script/tests/vsix_inventory_test.sh

cd SwiftExplorerApp
swift test
swift build -c release -Xswiftc -warnings-as-errors
cd ..

swiftformat --lint . --disable redundantSendable
Packaging/DeveloperID/tests/run_tests.sh
```

The checked v0.1.0 artifact is Apple silicon (`arm64`) only. Do not claim Intel or universal support until a separate x86_64 build and runtime smoke have been completed.

## Developer ID candidate

The release machine must contain the private-key-backed `Developer ID Application` identity. This Mac uses the existing identity directly through its login Keychain. Its private key is never exported, copied, repackaged as PKCS#12, imported into a temporary Keychain, copied into release notes, or exposed to pull-request jobs.

```sh
Packaging/DeveloperID/build_release.sh \
  --version 0.1.0 \
  --signing-identity "Developer ID Application: Rafal Sikora (2NY8A789TN)"
```

Require all of these before Apple submission:

- strict `codesign` verification;
- Hardened Runtime and secure timestamp;
- Team ID `2NY8A789TN`;
- reviewed sandbox entitlements;
- arm64 architecture and macOS 13 minimum metadata;
- matching dSYM UUID;
- signed DMG containing the app and `/Applications` link;
- pre-notarization manifest, SBOM, and checksums.

## Notarization

Notarization is an external Apple action and requires explicit owner approval. Use an App Store Connect API key stored through `notarytool` in Keychain under `codebase-combiner-notary`.

```sh
Packaging/DeveloperID/notarize_release.sh \
  --dmg "dist/developer-id/Codebase-Combiner-0.1.0-arm64.dmg" \
  --keychain-profile "codebase-combiner-notary"
```

The release remains blocked unless Apple returns `Accepted`, the ticket staples and validates, and Gatekeeper accepts both the DMG and mounted app. Publish only the post-stapling `SHA256SUMS` value.

## Draft and clean-download proof

After the workflow creates the draft and before publishing it:

1. As an authenticated repository owner, download the DMG from the draft release's actual GitHub asset URL, not from a workflow artifact or local build directory.
2. Verify its SHA-256 against `SHA256SUMS`.
3. Confirm macOS applied the quarantine attribute.
4. In a clean standard macOS account, mount it and drag the app into `/Applications`.
5. Launch normally through Finder without bypassing Gatekeeper.
6. Choose a representative folder, scan it, select files, copy output, save output, relaunch, and verify recovered-output privacy.
7. Record the tested macOS version and architecture. A macOS 13 machine or VM is still required to prove the advertised minimum.

## GitHub publication

CI signing is `blocked:external` until the owner deliberately provisions a separate CI signing credential in the protected `release` environment; the local login-Keychain identity must never be exported for CI. Once that boundary is satisfied, a verified signed annotated `macos-v*` tag at the current `main` commit triggers `.github/workflows/release.yml`, which creates a draft release only. Release notes must exist at `docs/release/<version>/RELEASE_NOTES.md`. Review the notarization log, artifact hashes, SBOM, matched symbols, provenance, source commit, and clean-download evidence before publishing the draft.

If a release is defective, leave its tag immutable, mark the release as withdrawn, remove the affected binary from the recommended-download path, publish a security notice when appropriate, and issue a new patch version. Never replace an existing tagged artifact silently.
