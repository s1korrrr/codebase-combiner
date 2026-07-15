# Developer ID direct distribution

This lane builds Codebase Combiner for download outside the Mac App Store. It is intentionally separate from `Packaging/AppStore` because the identities, package format, and release gates differ.

## Local structural validation

```sh
Packaging/DeveloperID/build_release.sh --skip-signing
```

This creates an ad-hoc signed app and DMG under `dist/developer-id/`. They prove bundle structure only and are not public distributables.

## Developer ID release candidate

Install a `Developer ID Application` identity with its private key, then run:

```sh
Packaging/DeveloperID/build_release.sh \
  --signing-identity "Developer ID Application: Rafal Sikora (2NY8A789TN)"
```

The script requires Hardened Runtime, a secure timestamp, the sandbox entitlements, strict signature verification, a matching dSYM, and an explicit architecture. Version 0.1.0 is deliberately Apple-silicon-only until an Intel build is separately produced and tested.

If `security find-identity` lists the certificate but `codesign` returns `errSecInternalComponent`, the private key is not authorized for the non-interactive signer. Fix its access locally in Keychain Access, or import the certificate into a dedicated ephemeral Keychain and grant the standard `apple-tool:,apple:,codesign:` partitions. Never pass a login-Keychain password through a script, shell history, CI log, or support message.

## Notarization

Store App Store Connect API-key credentials in the login Keychain without writing them to the repository:

```sh
xcrun notarytool store-credentials "codebase-combiner-notary" \
  --key "/secure/path/AuthKey_KEYID.p8" \
  --key-id "KEYID" \
  --issuer "ISSUER_UUID"
```

After explicit approval for the Apple submission:

```sh
Packaging/DeveloperID/notarize_release.sh \
  --dmg "dist/developer-id/Codebase-Combiner-0.1.0-arm64.dmg" \
  --keychain-profile "codebase-combiner-notary"
```

The notarization script requires Apple status `Accepted`, retrieves the log, staples and validates the ticket, runs Gatekeeper against the DMG and mounted app, and then writes the final checksum. It never publishes to GitHub.
