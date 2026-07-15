# Privacy Data Map

Repository inspection supports a **Data Not Collected** implementation claim, subject to owner confirmation in App Store Connect.

| Data or operation            | Source                                       | Purpose                               | Storage / retention                               | Recipient / tracking                   | Deletion                                              |
| ---------------------------- | -------------------------------------------- | ------------------------------------- | ------------------------------------------------- | -------------------------------------- | ----------------------------------------------------- |
| User-selected source files   | macOS open panel / security-scoped selection | Build a combined local output         | Read in memory during scan                        | None; no network code or analytics SDK | Released when workspace/output changes or app exits   |
| Combined output and metadata | selected local files                         | Preview, copy, export, crash recovery | Local Application Support JSON; bounded to 72 MiB | None                                   | User can clear recovered output; file removed locally |
| Preferences                  | user settings                                | Preserve filters/layout choices       | UserDefaults, until reset/uninstall               | None                                   | Reset/uninstall                                       |
| Exported output              | explicit save panel                          | User-requested local file             | User-chosen location until user deletes           | None                                   | User-controlled                                       |

- App Sandbox: enabled.
- File entitlement: `com.apple.security.files.user-selected.read-write` only.
- Network client/server entitlements: none.
- ATT/tracking: not used.
- Accounts, authentication, payments, ads, analytics, crash-reporting SDKs, backend, cloud sync: absent.
- Privacy manifest: `Packaging/AppStore/PrivacyInfo.xcprivacy`, declares no tracking, collected data, or accessed API categories.
- Public privacy policy: [docs/privacy-policy.md](../../privacy-policy.md); linked in-app and from README.

Owner blocker: confirm that no out-of-repository service, future telemetry, support intake, or distribution-layer collection changes these answers before selecting “Data Not Collected.”
