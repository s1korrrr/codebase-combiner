# Security Status

- Standard Codex Security scan: completed and indexed on 2026-07-15.
- Scan ID: `5cfbf753-28e5-427a-90f3-144d1afafbad`.
- Snapshot digest: `codex-security-snapshot/v1:sha256:708f8f44d31b072dcd863c9be9922db08d1b4ec1affd9824e4a575c247ccfff2`.
- Coverage: all ranked rows and the required full-file reviews have completion receipts; nine candidates validated and attack-path analyzed.
- Reportable findings: **0** critical, high, medium, or low.

The scan correctly classified several self-only reliability/release-safety issues as non-reportable security findings. They were still fixed:

- release metadata is allowlisted before path derivation or deletion;
- provisioning profiles must pass the protected-object signer trust policy;
- app and installer signing certificates must share the Team ID;
- macOS and VSIX scans have aggregate file, byte, and depth bounds;
- VSIX traversal is cancellable;
- recovered drafts are size-bounded;
- file saves are structured, serialized, and cancellation-aware.

Supply-chain evidence: `npm audit` reports zero vulnerabilities; the VSIX packages only the runtime `minimatch` dependency family; SwiftPM declares no third-party package dependency; SwiftFormat 0.61.1 is version- and SHA-256-pinned in CI.

Residual security risk is low and local-only. Final distribution trust still depends on Apple’s signing/profile/validation pipeline, which is blocked by the missing profile.
