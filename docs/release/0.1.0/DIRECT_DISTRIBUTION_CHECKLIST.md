# Codebase Combiner 0.1.0 Direct Distribution Checklist

Current candidate checklist refreshed on 2026-07-18. Generated evidence under
`dist/developer-id/` is authoritative for the final tagged commit; do not reuse
hashes or notarization results from an earlier source revision.

- [x] Public Apache-2.0-licensed source repository with Rafal Sikora copyright notice.
- [x] Separate Developer ID and Mac App Store packaging lanes.
- [x] App Sandbox and user-selected read/write entitlements reviewed.
- [x] Node and Swift unit-test baselines green on the audited pre-release source.
- [x] Ad-hoc app and mounted-DMG structural validation green.
- [x] Exact source-state, artifact-hash, metadata, entitlement, architecture, and dSYM binding implemented.
- [x] Notarization Accepted/Invalid/malformed/interrupted/resume/final-gate contract tests green.
- [x] Release automation rejects missing notes, unprovisioned hosted signing, source/tag drift, nested checksum paths, and unprotected credential-file permissions.
- [ ] Signed annotated tag `macos-v0.1.0` resolves to exact merged `main` and GitHub reports its signature as verified.
- [ ] Developer ID Application signature, Hardened Runtime, Team ID, and timestamp verified on the final candidate.
- [ ] Apple notarization status is `Accepted` and the log is retained.
- [ ] Ticket stapling and validation pass.
- [ ] Gatekeeper accepts the DMG and mounted app.
- [ ] macOS 13 minimum-runtime smoke passes on a clean standard account or VM.
- [ ] Draft GitHub Release assets, SBOM, checksums, provenance, and source tag agree.
- [ ] Downloaded GitHub asset hash and quarantine/Gatekeeper smoke pass.
- [ ] Draft release is explicitly approved for publication.

Current local blocker: the Developer ID certificate is discoverable, but a fresh
direct signing probe still fails with `errSecInternalComponent`. The owner must
repair only the local `/usr/bin/codesign` authorization. Do not export, copy,
repackage, or import the private key. The `codebase-combiner-notary` Keychain
profile is installed and currently validates against Apple.

Current CI signing status: `blocked:external`. GitHub has no `release`
environment, release variables, or release secrets. Hosted signing requires a
separate CI credential; the local Developer ID private key must never be
exported for CI. An unprovisioned tag now fails explicitly instead of silently
skipping the release.

Current tag-signing blocker: the local GitHub authentication key is not
registered as a GitHub signing key, and no GPG signing key is configured. Add a
reviewed signing key before creating the immutable release tag.
