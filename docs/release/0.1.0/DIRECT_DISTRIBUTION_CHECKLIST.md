# Codebase Combiner 0.1.0 Direct Distribution Checklist

> Historical checklist captured on 2026-07-15 for source commit
> `ee53940423a87185c2f87329b54c0617da678910`. Re-run every unchecked external
> gate and regenerate artifact evidence for any newer candidate.

- [x] Public MIT-licensed source repository.
- [x] Separate Developer ID and Mac App Store packaging lanes.
- [x] App Sandbox and user-selected read/write entitlements reviewed.
- [x] Node and Swift unit-test baselines green.
- [x] Ad-hoc app and mounted-DMG structural validation green.
- [x] Exact source-state, artifact-hash, metadata, entitlement, architecture, and dSYM binding implemented.
- [x] Notarization Accepted/Invalid/malformed/interrupted/resume/final-gate contract tests green.
- [x] Clean tracked source commit created for the release implementation (`ee53940`).
- [ ] Developer ID Application signature, Hardened Runtime, Team ID, and timestamp verified on the final candidate.
- [ ] Apple notarization status is `Accepted` and the log is retained.
- [ ] Ticket stapling and validation pass.
- [ ] Gatekeeper accepts the DMG and mounted app.
- [ ] macOS 13 minimum-runtime smoke passes on a clean standard account or VM.
- [ ] Draft GitHub Release assets, SBOM, checksums, provenance, and source tag agree.
- [ ] Downloaded GitHub asset hash and quarantine/Gatekeeper smoke pass.
- [ ] Draft release is explicitly approved for publication.

Current local blocker: the Developer ID certificate is discoverable, but direct login-Keychain private-key authorization fails with `errSecInternalComponent`. The owner must repair only the local `/usr/bin/codesign` authorization. Do not export, copy, repackage, or import the private key. The `codebase-combiner-notary` Keychain profile is installed and validated.

Current CI signing status: `blocked:external` until the owner deliberately provisions a separate CI credential. The local Developer ID private key must never be exported for CI.

Current GitHub blockers: the `release` environment and repository rulesets do not exist, `main` is unprotected, private vulnerability reporting is disabled, and Dependabot security updates plus secret scanning/push protection are disabled. Configure these owner-controlled settings before the release tag is created or Apple credentials are added.
