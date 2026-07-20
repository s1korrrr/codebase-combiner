# Codebase Combiner Privacy Policy

Effective date: July 20, 2026

Codebase Combiner comprises an offline macOS developer tool and a local-file VS Code extension. Neither deliverable creates an account, shows advertising, tracks users, includes analytics SDKs, or transmits source files, prompts, usage data, or identifiers to the developer or another service.

## Data handled on your Mac

The app processes only data needed for features you choose to use:

- Files and paths inside a folder you select, so the app can scan, filter, preview, and combine source text.
- An optional prompt prefix you enter.
- Preferences such as filters, maximum file size, output format, and pane visibility.
- The most recent combined output and recovery metadata, stored in the app's sandboxed Application Support container so it can be recovered after relaunch.
- Combined output placed on the system clipboard when you choose Copy, or written to a location you choose through the macOS save panel.
- Local diagnostic events containing outcomes and numeric counts. These events do not contain file paths, prompt text, source contents, clipboard contents, or save destinations.
- In the VS Code extension, workspace files, configured filters, and a user-selected output path are processed locally. The extension does not retain a recovery copy after the command completes.

## Collection, sharing, and tracking

The app does not send this data off your Mac. The developer therefore does not collect, sell, rent, share, or use it for tracking. The app contains no third-party analytics, advertising, authentication, cloud-sync, or payment SDK.

Opening the Support or Privacy Policy link leaves the app and opens a public GitHub page in your default browser. Normal browser and GitHub policies then apply. The app does not add source content, prompts, paths, or identifiers to those URLs.

## Retention and deletion

Preferences remain until you change them or manually remove the app's local settings. The recoverable combined output remains until it is replaced by a newer output, you use Clear Saved Output, or you manually remove the app's sandbox data. Removing the app does not guarantee that macOS removes this local data. Files saved through the macOS save panel or the VS Code extension remain at the location you chose until you delete them. Clipboard contents remain under macOS pasteboard behavior until replaced or cleared.

Clearing saved output removes only the app-owned recovery copy. It never deletes or changes the source files you selected.

## Security

Both packaged macOS lanes use App Sandbox and request access only to files and folders you choose through standard macOS panels. The VS Code extension works only with a local file-system workspace and declares limited Restricted Mode support. Symbolic links are skipped during workspace scanning. See the repository's [Security Policy](../SECURITY.md) for current vulnerability-reporting guidance.

## Children

The app is a general developer utility and is not directed to children. It does not knowingly collect personal information from anyone.

## Changes and contact

Material policy changes will be published in this document with a revised effective date. For privacy questions or support, use the [Codebase Combiner support page](support.md) or email [info@rsitech.ai](mailto:info@rsitech.ai).
