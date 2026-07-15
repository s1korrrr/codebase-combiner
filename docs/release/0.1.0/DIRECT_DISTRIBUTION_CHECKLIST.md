# Codebase Combiner 0.1.0 Direct Distribution Checklist

- [x] Public MIT-licensed source repository.
- [x] Separate Developer ID and Mac App Store packaging lanes.
- [x] App Sandbox and user-selected read/write entitlements reviewed.
- [x] Node and Swift unit-test baselines green.
- [x] Ad-hoc app and mounted-DMG structural validation green.
- [x] Exact source-state, artifact-hash, metadata, entitlement, architecture, and dSYM binding implemented.
- [x] Notarization Accepted/Invalid/malformed/interrupted/resume/final-gate contract tests green.
- [ ] Clean tracked source commit created for the release implementation.
- [ ] Developer ID Application signature, Hardened Runtime, Team ID, and timestamp verified on the final candidate.
- [ ] Apple notarization status is `Accepted` and the log is retained.
- [ ] Ticket stapling and validation pass.
- [ ] Gatekeeper accepts the DMG and mounted app.
- [ ] macOS 13 minimum-runtime smoke passes on a clean standard account or VM.
- [ ] Draft GitHub Release assets, SBOM, checksums, provenance, and source tag agree.
- [ ] Downloaded GitHub asset hash and quarantine/Gatekeeper smoke pass.
- [ ] Draft release is explicitly approved for publication.
