# Mac App Store Packaging

This folder contains the Mac App Store packaging path for the SwiftPM macOS app.

## Defaults

- App name: `Codebase Combiner`
- Bundle ID: `com.s1korrrr.codebasecombiner`
- Version: `0.1.0`
- Build: `1`
- Minimum macOS: `13.0`
- Category: `public.app-category.developer-tools`
- Entitlements: App Sandbox plus user-selected file read/write access.
- Privacy manifest: declares no tracking, no collected data, and UserDefaults access for app settings.

## Local validation

Build an unsigned/ad-hoc sandboxed app bundle:

```sh
Packaging/AppStore/build_app_store_package.sh --skip-signing
```

Output:

- `dist/app-store/Codebase Combiner.app`
- `dist/app-store/CodebaseCombiner-AppStore-summary.txt`

## App Store signing

Install the Apple signing assets first:

- Mac App Distribution / Apple Distribution certificate for the app binary.
- Mac Installer Distribution / 3rd Party Mac Developer Installer certificate for the `.pkg`.
- A Mac App Store provisioning profile for bundle ID `com.s1korrrr.codebasecombiner`.

Then run:

```sh
Packaging/AppStore/build_app_store_package.sh \
  --signing-identity "Apple Distribution: <Name> (<TEAMID>)" \
  --installer-identity "3rd Party Mac Developer Installer: <Name> (<TEAMID>)" \
  --provisioning-profile "/path/to/profile.provisionprofile"
```

The script also accepts environment variables:

```sh
APPSTORE_BUNDLE_ID=com.s1korrrr.codebasecombiner
APPSTORE_MARKETING_VERSION=0.1.0
APPSTORE_BUILD_NUMBER=1
APPSTORE_SIGNING_IDENTITY="Apple Distribution: <Name> (<TEAMID>)"
APPSTORE_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: <Name> (<TEAMID>)"
APPSTORE_PROVISIONING_PROFILE="/path/to/profile.provisionprofile"
```

## Upload

After a signed package is created, upload it through Apple Transporter, Xcode Organizer, `xcrun altool`, or the App Store Connect API.

Before submission, validate sandboxed behavior by launching the packaged app and checking:

- choose workspace folder
- scan selected folder
- change include/exclude filters
- copy combined output
- save combined output to a user-selected location
- open Settings
- open Support link

## Current local blocker

This repository can now create the `.app` bundle locally. Final Mac App Store upload still depends on signing assets that are intentionally not committed to git.
