# Codebase Combiner Native Adaptive Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the macOS app as an adaptive, privacy-conscious native workspace that remains fully functional on macOS 13 and progressively adopts modern presentation on supported systems.

**Architecture:** Move preference validation, scanning state, output recovery, and command availability into focused testable models and `ObservableObject` stores. Compose the UI from a macOS 13 `NavigationSplitView` plus native `HSplitView`, with one availability-gated visual-style modifier for newer materials. Keep AppKit panels and process/window behavior at the app-controller and app-delegate boundaries.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, Combine, SwiftPM, XCTest, OSLog, Bash, Node.js/Mocha/ESLint/Prettier.

## Global Constraints

- Keep `.macOS(.v13)` in `SwiftExplorerApp/Package.swift`.
- Add no third-party dependency.
- macOS 13 is a first-class path; all behavior and accessibility must work without modern presentation APIs.
- Use only SDK-known modern APIs behind compile-time and runtime availability checks; macOS 27 SDK-only work remains blocked until Xcode 27 is installed.
- Never log source contents, prompt contents, recovered payloads, clipboard contents, credentials, or private fixture data.
- Preserve the existing draft JSON schema and source-file safety unless a tested backward-compatible migration is explicit.
- Use test-first red/green cycles for every behavior change.
- Preserve real user clipboard contents and recovered drafts during E2E by launching with isolated test dependencies.
- Commit only intentional files on `feat/andrzej_agent_sota_lab`.

---

## Planned File Structure

- `Models/AppPreferences.swift`: defaults, validation, parsed extension sets, persistent preference adapter.
- `Models/WorkspaceLayoutPolicy.swift`: pure compact/regular/wide layout decisions.
- `Models/ScanSummary.swift`: structured skipped-file reasons and user-facing summary values.
- `Services/TreeLoader.swift`: filesystem scan returning `TreeLoadResult` instead of silently dropping every failure.
- `Stores/WorkspaceStore.swift`: scan lifecycle, stale-result rejection, file selection, and totals.
- `Stores/OutputStore.swift`: current output, recovered output reveal policy, persistence, copy/save results, and clear confirmation.
- `Support/AppDependencies.swift`: injectable UserDefaults, draft directory, clipboard, and file-output boundaries.
- `App/AppController.swift`: shared actions for views and commands; owns the two stores and AppKit panels.
- `App/CodebaseExplorerApp.swift`: scenes, canonical Settings, commands, and dependency construction.
- `App/AppCommands.swift`: menu commands and consistent enablement.
- `Views/ContentView.swift`: small composition root only.
- `Views/WorkspaceSidebar.swift`, `PreparationWorkspace.swift`, `OutputInspector.swift`, `RecoveredOutputView.swift`: focused workspace surfaces.
- `Views/PlatformVisualStyle.swift`: macOS 13 semantic fallback and bounded newer-system presentation.
- `Views/SettingsView.swift`, `FiltersView.swift`, `PromptEditor.swift`, `FileNodeRow.swift`, `StatsBar.swift`: focused control surfaces without static hover elevation.
- `Tests/...`: focused policy/store/service tests.
- `script/build_and_run.sh`: isolated `--e2e` launch mode in addition to existing run/verify/log modes.
- `docs/audit/codebase-combiner-e2e-audit-2026-07-13.md`: exact scenario matrix and evidence.

---

### Task 1: Preference Validation And Adaptive Layout Policy

**Files:**

- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Models/AppPreferences.swift`
- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Models/WorkspaceLayoutPolicy.swift`
- Create: `SwiftExplorerApp/Tests/CodebaseExplorerAppTests/AppPreferencesTests.swift`
- Create: `SwiftExplorerApp/Tests/CodebaseExplorerAppTests/WorkspaceLayoutPolicyTests.swift`

**Interfaces:**

- Produces: `AppPreferences.Values`, `AppPreferences.Validation`, `AppPreferences.extensionSet(from:)`, `WorkspaceLayoutMode`, and `WorkspaceLayoutPolicy.mode(for:)`.
- Consumes: `UserDefaults` and the existing preference keys recorded in `MEMORY.md`.

- [ ] **Step 1: Write failing validation tests**

```swift
import XCTest
@testable import CodebaseExplorerApp

final class AppPreferencesTests: XCTestCase {
    func testValidationRejectsSizeOutsideSupportedRange() {
        XCTAssertEqual(AppPreferences.validate(maxFileSizeKB: 31), .invalid("Enter a value from 32 to 8,192 KB."))
        XCTAssertEqual(AppPreferences.validate(maxFileSizeKB: 8193), .invalid("Enter a value from 32 to 8,192 KB."))
        XCTAssertEqual(AppPreferences.validate(maxFileSizeKB: 512), .valid)
    }

    func testExtensionParserNormalizesDotsCaseAndDelimiters() {
        XCTAssertEqual(AppPreferences.extensionSet(from: ".Swift, JS;md\nPY"), ["swift", "js", "md", "py"])
    }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `cd SwiftExplorerApp && swift test --filter AppPreferencesTests`

Expected: build failure because `AppPreferences` does not exist.

- [ ] **Step 3: Implement the preference model and persistence adapter**

```swift
import Combine
import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    enum Validation: Equatable { case valid; case invalid(String) }

    struct Values: Equatable, Sendable {
        var allowList = "swift,js,ts,tsx,jsx,md,txt,py"
        var excludeList = "png,jpg,jpeg,gif,mp4,zip,bin,lock"
        var maxFileSizeKB = 512.0
        var skipHidden = true
        var outputMarkdown = true
        var showFilters = true
    }

    @Published var values: Values { didSet { save() } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        values = Values(
            allowList: defaults.string(forKey: "cc_allowListString") ?? Values().allowList,
            excludeList: defaults.string(forKey: "cc_excludeListString") ?? Values().excludeList,
            maxFileSizeKB: defaults.object(forKey: "cc_maxFileSizeKB") as? Double ?? 512,
            skipHidden: defaults.object(forKey: "cc_skipHidden") as? Bool ?? true,
            outputMarkdown: defaults.object(forKey: "cc_outputMarkdown") as? Bool ?? true,
            showFilters: defaults.object(forKey: "cc_showFilters") as? Bool ?? true
        )
    }

    static func validate(maxFileSizeKB: Double) -> Validation {
        (32 ... 8192).contains(maxFileSizeKB) ? .valid : .invalid("Enter a value from 32 to 8,192 KB.")
    }

    static func extensionSet(from text: String) -> Set<String> {
        let delimiters = CharacterSet(charactersIn: ",;|\n\t ")
        return Set(text.lowercased().components(separatedBy: delimiters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty })
    }

    private func save() {
        defaults.set(values.allowList, forKey: "cc_allowListString")
        defaults.set(values.excludeList, forKey: "cc_excludeListString")
        defaults.set(values.maxFileSizeKB, forKey: "cc_maxFileSizeKB")
        defaults.set(values.skipHidden, forKey: "cc_skipHidden")
        defaults.set(values.outputMarkdown, forKey: "cc_outputMarkdown")
        defaults.set(values.showFilters, forKey: "cc_showFilters")
    }
}
```

- [ ] **Step 4: Write and run the layout-policy RED test**

```swift
final class WorkspaceLayoutPolicyTests: XCTestCase {
    func testModeUsesCompactRegularAndWideBreakpoints() {
        XCTAssertEqual(WorkspaceLayoutPolicy.mode(for: 959), .compact)
        XCTAssertEqual(WorkspaceLayoutPolicy.mode(for: 960), .regular)
        XCTAssertEqual(WorkspaceLayoutPolicy.mode(for: 1320), .wide)
    }
}
```

Run: `cd SwiftExplorerApp && swift test --filter WorkspaceLayoutPolicyTests`

Expected: build failure because `WorkspaceLayoutPolicy` does not exist.

- [ ] **Step 5: Implement and verify the pure layout policy**

```swift
enum WorkspaceLayoutMode: Equatable { case compact, regular, wide }

enum WorkspaceLayoutPolicy {
    static func mode(for width: Double) -> WorkspaceLayoutMode {
        if width < 960 { return .compact }
        if width < 1320 { return .regular }
        return .wide
    }
}
```

Run: `cd SwiftExplorerApp && swift test --filter 'AppPreferencesTests|WorkspaceLayoutPolicyTests'`

Expected: all focused tests pass.

- [ ] **Step 6: Commit the independently testable policy slice**

```bash
git add SwiftExplorerApp/Sources/CodebaseExplorerApp/Models/AppPreferences.swift \
  SwiftExplorerApp/Sources/CodebaseExplorerApp/Models/WorkspaceLayoutPolicy.swift \
  SwiftExplorerApp/Tests/CodebaseExplorerAppTests/AppPreferencesTests.swift \
  SwiftExplorerApp/Tests/CodebaseExplorerAppTests/WorkspaceLayoutPolicyTests.swift
git commit -m "Add validated preferences and layout policy"
```

---

### Task 2: Structured Scan Results Without Silent Skips

**Files:**

- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Models/ScanSummary.swift`
- Modify: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Models/FileNode.swift`
- Modify: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Services/TreeLoader.swift`
- Modify: `SwiftExplorerApp/Tests/CodebaseExplorerAppTests/TreeLoaderTests.swift`

**Interfaces:**

- Produces: `TreeLoadResult(root:summary:)`, `ScanSummary.record(_:)`, and `TreeLoader.load(...) throws -> TreeLoadResult`.
- Preserves temporarily: `TreeLoader.loadTree(...) throws -> FileNode` delegates to `load(...).root` until `WorkspaceStore` replaces the legacy caller.

- [ ] **Step 1: Add a failing structured-summary test**

```swift
func testLoadReportsWhyFilesWereSkipped() throws {
    try Data([0, 1, 2]).write(to: root.appendingPathComponent("binary.bin"))
    try Data([0xFF, 0xFE]).write(to: root.appendingPathComponent("invalid.swift"))
    try String(repeating: "x", count: 2048).write(to: root.appendingPathComponent("large.swift"), atomically: true, encoding: .utf8)

    let result = try TreeLoader().load(
        rootURL: root, allowList: ["swift", "bin"], excludeList: [], maxFileSizeKB: 1, skipHidden: true
    )

    XCTAssertEqual(result.summary.count(for: .binary), 1)
    XCTAssertEqual(result.summary.count(for: .unreadable), 1)
    XCTAssertEqual(result.summary.count(for: .oversized), 1)
}
```

- [ ] **Step 2: Run RED**

Run: `cd SwiftExplorerApp && swift test --filter TreeLoaderTests/testLoadReportsWhyFilesWereSkipped`

Expected: build failure because `load`, `TreeLoadResult`, and `ScanSummary` do not exist.

- [ ] **Step 3: Implement scan-summary types and explicit classification**

```swift
enum ScanSkipReason: String, CaseIterable, Sendable { case hidden, excluded, disallowed, oversized, binary, unreadable }

struct ScanSummary: Equatable, Sendable {
    private(set) var skipped: [ScanSkipReason: Int] = [:]
    mutating func record(_ reason: ScanSkipReason) { skipped[reason, default: 0] += 1 }
    func count(for reason: ScanSkipReason) -> Int { skipped[reason, default: 0] }
    var skippedCount: Int { skipped.values.reduce(0, +) }
}

struct TreeLoadResult: Sendable {
    let root: FileNode
    let summary: ScanSummary
}
```

Update `TreeLoader.walk` to call `summary.record(...)` at each existing skip branch, distinguish invalid UTF-8 and failed reads as `.unreadable`, and return `TreeLoadResult`. Add `Sendable` to `FileNode`.

- [ ] **Step 4: Run focused and existing loader tests**

Run: `cd SwiftExplorerApp && swift test --filter TreeLoaderTests`

Expected: the new summary test and all existing loader tests pass.

- [ ] **Step 5: Commit**

```bash
git add SwiftExplorerApp/Sources/CodebaseExplorerApp/Models/ScanSummary.swift \
  SwiftExplorerApp/Sources/CodebaseExplorerApp/Models/FileNode.swift \
  SwiftExplorerApp/Sources/CodebaseExplorerApp/Services/TreeLoader.swift \
  SwiftExplorerApp/Tests/CodebaseExplorerAppTests/TreeLoaderTests.swift
git commit -m "Report skipped files during workspace scans"
```

---

### Task 3: Workspace Store And Stale-Scan Rejection

**Files:**

- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Stores/WorkspaceStore.swift`
- Create: `SwiftExplorerApp/Tests/CodebaseExplorerAppTests/WorkspaceStoreTests.swift`

**Interfaces:**

- Consumes: `TreeLoadResult`, `AppPreferences.Values`, and an injected async `WorkspaceLoading` boundary.
- Produces: `WorkspaceStore.State`, `scan(rootURL:preferences:)`, `accept(_:requestID:preserveSelection:)`, `toggle`, `selectAll`, and `clearSelection`.

- [ ] **Step 1: Write failing tests for selection and stale results**

```swift
@MainActor
final class WorkspaceStoreTests: XCTestCase {
    func testStaleResultCannotReplaceNewerWorkspace() {
        let store = WorkspaceStore(loader: ImmediateWorkspaceLoader())
        let oldID = UUID()
        let newID = UUID()
        store.activeRequestID = newID

        store.accept(.fixture(named: "old"), requestID: oldID, preserveSelection: false)
        XCTAssertNil(store.rootNode)

        store.accept(.fixture(named: "new"), requestID: newID, preserveSelection: false)
        XCTAssertEqual(store.rootNode?.name, "new")
    }

    func testSelectionSnapshotUpdatesCounts() {
        let store = WorkspaceStore(loader: ImmediateWorkspaceLoader())
        store.accept(.twoFileFixture, requestID: store.beginRequestForTesting(), preserveSelection: false)
        store.clearSelection()
        store.toggle(node: store.allFiles[0], isOn: true)
        XCTAssertEqual(store.selectedFiles.count, 1)
        XCTAssertEqual(store.selectedBytes, store.allFiles[0].sizeBytes)
    }
}
```

- [ ] **Step 2: Run RED**

Run: `cd SwiftExplorerApp && swift test --filter WorkspaceStoreTests`

Expected: build failure because `WorkspaceStore` does not exist.

- [ ] **Step 3: Implement the store and loader boundary**

```swift
protocol WorkspaceLoading: Sendable {
    func load(rootURL: URL, preferences: AppPreferences.Values) async throws -> TreeLoadResult
}

struct LiveWorkspaceLoader: WorkspaceLoading {
    func load(rootURL: URL, preferences: AppPreferences.Values) async throws -> TreeLoadResult {
        try await Task.detached(priority: .userInitiated) {
            try TreeLoader().load(
                rootURL: rootURL,
                allowList: AppPreferences.extensionSet(from: preferences.allowList),
                excludeList: AppPreferences.extensionSet(from: preferences.excludeList),
                maxFileSizeKB: Int(preferences.maxFileSizeKB),
                skipHidden: preferences.skipHidden
            )
        }.value
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var rootNode: FileNode?
    @Published private(set) var allFiles: [FileNode] = []
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var selectedFiles: [FileNode] = []
    @Published private(set) var selectedBytes = 0
    @Published private(set) var selectedTokens = 0
    @Published private(set) var summary = ScanSummary()
    @Published private(set) var isScanning = false
    @Published private(set) var status = "Choose a workspace to begin."
    var activeRequestID: UUID?
    private let loader: any WorkspaceLoading

    init(loader: any WorkspaceLoading = LiveWorkspaceLoader()) { self.loader = loader }

    func scan(rootURL: URL, preferences: AppPreferences.Values) async {
        guard AppPreferences.validate(maxFileSizeKB: preferences.maxFileSizeKB) == .valid else {
            status = "Correct the maximum file size before scanning."
            return
        }
        let requestID = UUID()
        let preserveSelection = self.rootNode != nil
        activeRequestID = requestID
        self.rootURL = rootURL
        isScanning = true
        do { accept(try await loader.load(rootURL: rootURL, preferences: preferences), requestID: requestID, preserveSelection: preserveSelection) }
        catch where activeRequestID == requestID { isScanning = false; status = error.localizedDescription }
        catch { }
    }
}
```

Implement pure flattening, selection preservation, totals, status copy, and `accept` exactly once inside the store.

- [ ] **Step 4: Run focused and full Swift tests**

Run: `cd SwiftExplorerApp && swift test --filter WorkspaceStoreTests && swift test`

Expected: all tests pass with no concurrency warnings.

- [ ] **Step 5: Commit**

```bash
git add SwiftExplorerApp/Sources/CodebaseExplorerApp/Stores/WorkspaceStore.swift \
  SwiftExplorerApp/Tests/CodebaseExplorerAppTests/WorkspaceStoreTests.swift
git commit -m "Move scan and selection state into a workspace store"
```

---

### Task 4: Output Store, Recovery Privacy, And Failure Boundaries

**Files:**

- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Support/AppDependencies.swift`
- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Stores/OutputStore.swift`
- Create: `SwiftExplorerApp/Tests/CodebaseExplorerAppTests/OutputStoreTests.swift`
- Modify: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Services/ClipboardDraftStore.swift`

**Interfaces:**

- Consumes: `CombinedOutputBuilder`, `ClipboardDraftStore`, selected file snapshots, prompt prefix, and output format.
- Produces: `OutputStore.currentPayload`, `visiblePayload`, `recoveredDraft`, `revealRecoveredOutput`, `requestClearRecoveredOutput`, `cancelClearRecoveredOutput`, `confirmClearRecoveredOutput`, `copyCurrent`, `copyRecovered`, and `saveCurrent(to:)`.

- [ ] **Step 1: Write failing privacy and confirmation tests**

```swift
@MainActor
final class OutputStoreTests: XCTestCase {
    func testRecoveredContentStaysHiddenUntilReveal() throws {
        let draft = ClipboardDraft.fixture(text: "private source")
        let store = OutputStore(drafts: InMemoryDraftStore(draft: draft), clipboard: RecordingClipboard())
        try store.loadRecoveredDraft()
        XCTAssertNil(store.visiblePayload)
        XCTAssertEqual(store.recoveredDraft?.fileCount, draft.fileCount)
        store.revealRecoveredOutput()
        XCTAssertEqual(store.visiblePayload, "private source")
    }

    func testClearRequiresConfirmationAndSupportsCancel() throws {
        let drafts = InMemoryDraftStore(draft: .fixture())
        let store = OutputStore(drafts: drafts, clipboard: RecordingClipboard())
        try store.loadRecoveredDraft()
        store.requestClearRecoveredOutput()
        XCTAssertTrue(store.isClearConfirmationPresented)
        store.cancelClearRecoveredOutput()
        XCTAssertNotNil(store.recoveredDraft)
        XCTAssertEqual(drafts.clearCount, 0)
    }
}
```

- [ ] **Step 2: Run RED**

Run: `cd SwiftExplorerApp && swift test --filter OutputStoreTests`

Expected: build failure because `OutputStore` and dependency protocols do not exist.

- [ ] **Step 3: Implement dependency protocols and store state machine**

```swift
protocol DraftPersisting: Sendable {
    func load() throws -> ClipboardDraft?
    func save(_ draft: ClipboardDraft) throws
    func clear() throws
}

protocol ClipboardWriting: AnyObject {
    @MainActor func write(_ text: String) throws
}

@MainActor
final class OutputStore: ObservableObject {
    @Published var promptPrefix = ""
    @Published var format: CombinedOutputFormat = .markdown
    @Published private(set) var currentPayload: String?
    @Published private(set) var recoveredDraft: ClipboardDraft?
    @Published private(set) var isRecoveredContentRevealed = false
    @Published var isClearConfirmationPresented = false
    @Published private(set) var status: String?
    private let drafts: any DraftPersisting
    private let clipboard: any ClipboardWriting
    private let builder = CombinedOutputBuilder()

    var visiblePayload: String? {
        if let currentPayload { return currentPayload }
        guard isRecoveredContentRevealed else { return nil }
        return recoveredDraft?.text
    }

    func rebuild(files: [FileNode], rootPath: String?) {
        guard !files.isEmpty else { currentPayload = nil; return }
        let text = builder.build(promptPrefix: promptPrefix, files: files, format: format)
        currentPayload = text
        let draft = ClipboardDraft(text: text, format: format, fileCount: files.count,
            tokenCount: files.reduce(0) { $0 + $1.tokenCount }, byteCount: files.reduce(0) { $0 + $1.sizeBytes },
            rootPath: rootPath, generatedAt: Date())
        do { try drafts.save(draft); recoveredDraft = draft }
        catch { status = "Could not save the recoverable output: \(error.localizedDescription)" }
    }
}
```

Implement copy/save with thrown errors converted to actionable `status`, and make `confirmClearRecoveredOutput` the only method that calls `drafts.clear()`.

- [ ] **Step 4: Run focused tests and regression draft tests**

Run: `cd SwiftExplorerApp && swift test --filter 'OutputStoreTests|ClipboardDraftStoreTests|CombinedOutputBuilderTests'`

Expected: all focused tests pass.

- [ ] **Step 5: Commit**

```bash
git add SwiftExplorerApp/Sources/CodebaseExplorerApp/Support/AppDependencies.swift \
  SwiftExplorerApp/Sources/CodebaseExplorerApp/Stores/OutputStore.swift \
  SwiftExplorerApp/Sources/CodebaseExplorerApp/Services/ClipboardDraftStore.swift \
  SwiftExplorerApp/Tests/CodebaseExplorerAppTests/OutputStoreTests.swift
git commit -m "Add privacy-conscious output recovery state"
```

---

### Task 5: Shared App Controller, Commands, And Canonical Settings

**Files:**

- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/App/AppController.swift`
- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/App/AppCommands.swift`
- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/App/CodebaseExplorerApp.swift`
- Create: `SwiftExplorerApp/Tests/CodebaseExplorerAppTests/AppCommandStateTests.swift`
- Modify: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/SettingsView.swift`
- Modify: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/ContentView.swift`

**Interfaces:**

- Consumes: `WorkspaceStore`, `OutputStore`, `AppPreferences`, `NSOpenPanel`, and `NSSavePanel`.
- Produces: one `AppController`, `AppCommandState`, `AppCommands`, a single `Settings` scene, and shared actions used by menus and views.

- [ ] **Step 1: Write the command-enablement RED test**

```swift
final class AppCommandStateTests: XCTestCase {
    func testCommandsNameMissingPrerequisites() {
        let empty = AppCommandState(hasWorkspace: false, isScanning: false, hasSelection: false)
        XCTAssertFalse(empty.canRefresh)
        XCTAssertEqual(empty.copyHelp, "Select at least one file to copy the combined output.")
        let ready = AppCommandState(hasWorkspace: true, isScanning: false, hasSelection: true)
        XCTAssertTrue(ready.canRefresh)
        XCTAssertTrue(ready.canExport)
    }
}
```

- [ ] **Step 2: Run RED and implement command state**

Run: `cd SwiftExplorerApp && swift test --filter AppCommandStateTests`

Expected: build failure because `AppCommandState` does not exist.

```swift
struct AppCommandState: Equatable {
    let hasWorkspace: Bool
    let isScanning: Bool
    let hasSelection: Bool
    var canRefresh: Bool { hasWorkspace && !isScanning }
    var canExport: Bool { hasSelection }
    var copyHelp: String { hasSelection ? "Copy combined output" : "Select at least one file to copy the combined output." }
}
```

- [ ] **Step 3: Implement the controller and shared menu commands**

`AppController` creates and owns `preferences`, `workspace`, and `output`, presents panels, passes validated preference snapshots into scans, rebuilds output after selection/prompt/format changes, and exposes `chooseFolder`, `refresh`, `copy`, `save`, `toggleFilters`, and `toggleInspector`.

```swift
struct AppCommands: Commands {
    @ObservedObject var controller: AppController
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Choose Folder…", action: controller.chooseFolder).keyboardShortcut("o")
            Button("Refresh Workspace", action: controller.refresh).keyboardShortcut("r")
                .disabled(!controller.commandState.canRefresh)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy Combined Output", action: controller.copy).keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!controller.commandState.canExport)
        }
        CommandGroup(after: .saveItem) {
            Button("Save Combined Output…", action: controller.save).keyboardShortcut("s")
                .disabled(!controller.commandState.canExport)
        }
        CommandGroup(after: .sidebar) {
            Button(controller.preferences.values.showFilters ? "Hide Filters" : "Show Filters",
                   action: controller.toggleFilters)
            Button(controller.isInspectorPresented ? "Hide Output Inspector" : "Show Output Inspector",
                   action: controller.toggleInspector)
        }
    }
}
```

- [ ] **Step 4: Extract the app entry and remove duplicate Settings window**

```swift
@main
struct CodebaseExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AppController.live()

    var body: some Scene {
        WindowGroup("Codebase Combiner") { ContentView(controller: controller) }
            .defaultSize(width: 1180, height: 760)
            .commands { AppCommands(controller: controller) }
        Settings { SettingsView(preferences: controller.preferences) }
    }
}
```

Move `AppDelegate` to the app entry file and delete the old `@main` block and custom `Window("Settings", id: "settings")` from `ContentView.swift`.

- [ ] **Step 5: Run command tests and compile the app**

Run: `cd SwiftExplorerApp && swift test --filter AppCommandStateTests && swift build`

Expected: tests and build pass; the package contains exactly one `@main` declaration.

- [ ] **Step 6: Commit**

```bash
git add SwiftExplorerApp/Sources/CodebaseExplorerApp/App \
  SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/ContentView.swift \
  SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/SettingsView.swift \
  SwiftExplorerApp/Tests/CodebaseExplorerAppTests/AppCommandStateTests.swift
git commit -m "Unify app actions commands and settings"
```

---

### Task 6: Adaptive Native Workspace And Platform Visual Style

**Files:**

- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/WorkspaceSidebar.swift`
- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/PreparationWorkspace.swift`
- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/OutputInspector.swift`
- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/RecoveredOutputView.swift`
- Create: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/PlatformVisualStyle.swift`
- Rewrite: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/ContentView.swift`
- Modify: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/VisualEffects.swift`
- Modify: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/FileNodeRow.swift`
- Modify: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/FiltersView.swift`
- Modify: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/PromptEditor.swift`
- Modify: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Views/StatsBar.swift`

**Interfaces:**

- Consumes: `AppController`, stores, layout policy, and shared commands.
- Produces: a 960×640-capable adaptive workspace, independent sidebar/inspector visibility, concealed recovered content, confirmation dialog, and bounded modern presentation.

- [ ] **Step 1: Add a compile-time view contract test**

Create `AdaptiveWorkspaceSmokeTests.swift` with construction tests for compact/regular/wide policies and `OutputStore.visiblePayload`; these remain logic-level because SwiftPM has no UI-test host.

Run: `cd SwiftExplorerApp && swift test --filter AdaptiveWorkspaceSmokeTests`

Expected: RED until the new root view and presentation state compile.

- [ ] **Step 2: Replace the fixed manual split shell**

```swift
struct ContentView: View {
    @ObservedObject var controller: AppController
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceSidebar(controller: controller)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            HSplitView {
                PreparationWorkspace(controller: controller).frame(minWidth: 520)
                if controller.isInspectorPresented {
                    OutputInspector(controller: controller).frame(minWidth: 320, idealWidth: 430)
                }
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .toolbar {
            ToolbarItemGroup {
                Button(action: controller.chooseFolder) { Label("Choose Folder", systemImage: "folder") }
                    .help("Choose a workspace folder")
                Button(action: controller.refresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(!controller.commandState.canRefresh)
                    .help(controller.refreshHelp)
                Toggle(isOn: $controller.isInspectorPresented) { Label("Output Inspector", systemImage: "sidebar.trailing") }
                    .help("Show or hide the output inspector")
            }
        }
    }
}
```

- [ ] **Step 3: Implement recovered-output UI and safe clear confirmation**

`RecoveredOutputView` always renders metadata, shows Reveal/Hide and Copy Last, and calls only `requestClearRecoveredOutput`. Attach a destructive `confirmationDialog` whose cancel path calls `cancelClearRecoveredOutput` and whose destructive action calls `confirmClearRecoveredOutput`.

```swift
RecoveredOutputView(store: controller.output)
    .confirmationDialog(
        "Clear saved output?",
        isPresented: $controller.output.isClearConfirmationPresented,
        titleVisibility: .visible
    ) {
        Button("Clear Saved Output", role: .destructive) {
            controller.output.confirmClearRecoveredOutput()
        }
        Button("Cancel", role: .cancel) {
            controller.output.cancelClearRecoveredOutput()
        }
    } message: {
        Text("This removes only Codebase Combiner’s recoverable copy. Source files are not changed.")
    }
```

- [ ] **Step 4: Implement platform styling without nested glass**

```swift
struct FunctionalChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency {
            content.padding(8).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        } else {
            content.padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
```

Apply this only to the toolbar/output action cluster. Remove `HoverLift` from `StatsBar`, filter containers, prompt editor, selected-file sections, and recovery surfaces. Preserve native button hover/press behavior.

- [ ] **Step 5: Add accessibility help and explicit state copy**

Every icon-only control gets `.help` and accessibility labels. Disabled Refresh, Copy, Save, Select All, and Clear Selection use the controller's prerequisite copy. Partial scan status names `summary.skippedCount` and offers details without exposing paths containing sensitive data.

```swift
Button(action: controller.copy) { Label("Copy Combined Output", systemImage: "doc.on.doc") }
    .disabled(!controller.commandState.canExport)
    .help(controller.commandState.copyHelp)
    .accessibilityHint(controller.commandState.copyHelp)
```

- [ ] **Step 6: Format, test, build, and launch for first visual proof**

Run:

```bash
cd SwiftExplorerApp
swiftformat .
swiftformat --lint .
swift test
swift build -Xswiftc -warnings-as-errors
cd ..
./script/build_and_run.sh --verify
```

Expected: formatting, tests, warnings-as-errors build, bundle validation, and process launch pass. The app window visibly opens at the adaptive default size.

- [ ] **Step 7: Commit**

```bash
git add SwiftExplorerApp/Sources/CodebaseExplorerApp/Views \
  SwiftExplorerApp/Tests/CodebaseExplorerAppTests/AdaptiveWorkspaceSmokeTests.swift
git commit -m "Rebuild the macOS workspace with adaptive native panes"
```

---

### Task 7: Isolated E2E Launch, Real Interaction Sweep, And Fix Loop

**Files:**

- Modify: `SwiftExplorerApp/Sources/CodebaseExplorerApp/Support/AppDependencies.swift`
- Modify: `script/build_and_run.sh`
- Create: `script/fixtures/e2e-workspace/README.md`
- Create: `script/fixtures/e2e-workspace/Sources/App.swift`
- Create: `script/fixtures/e2e-workspace/Sources/Invalid.bin`
- Create: `docs/audit/codebase-combiner-e2e-audit-2026-07-13.md`
- Update as findings require: relevant source and test files from Tasks 1–6.

**Interfaces:**

- Produces: `./script/build_and_run.sh --e2e`, isolated `UserDefaults` suite and draft directory, disposable fixture, scenario matrix, screenshots, and log evidence.
- Consumes: the packaged app created by the existing App Store packaging script.

- [ ] **Step 1: Add an isolated dependency-selection test**

Test that `AppDependencies(environment:)` selects standard production dependencies when `CODEBASE_COMBINER_E2E_DATA_DIR` is absent and a named UserDefaults suite plus draft directory when it is present.

Run: `cd SwiftExplorerApp && swift test --filter AppDependenciesTests`

Expected: RED before the environment-aware initializer exists.

- [ ] **Step 2: Implement environment-aware isolated dependencies**

```swift
struct AppDependencies {
    let defaults: UserDefaults
    let draftBaseDirectory: URL?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let path = environment["CODEBASE_COMBINER_E2E_DATA_DIR"] {
            defaults = UserDefaults(suiteName: "com.s1korrrr.codebasecombiner.e2e")!
            draftBaseDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            defaults = .standard
            draftBaseDirectory = nil
        }
    }
}
```

- [ ] **Step 3: Add `--e2e` launch mode**

The script creates a temporary data directory, builds the package, launches the actual `.app` with `CODEBASE_COMBINER_E2E_DATA_DIR` set, prints the directory and fixture path, and verifies the process. It must not mutate standard defaults or the production Application Support draft.

- [ ] **Step 4: Create the E2E matrix before interaction**

Use the app-e2e audit template and include every scenario from the design spec: first launch/relaunch, fixture selection, partial scan, filters, selection, prompt, format, copy/save, recovery reveal/clear-cancel, menus, shortcuts, context menus, tooltips, settings, support link, panel visibility, compact/regular/wide resize, appearance/accessibility states, persistence, and logs. Mark risky final actions blocked until safe fixture isolation is confirmed.

- [ ] **Step 5: Run the native interaction sweep with Computer Use**

Launch `./script/build_and_run.sh --e2e`; operate the packaged app through the accessibility tree and screenshots. Preserve the user's current clipboard before copy checks and restore it immediately afterward. Use only the disposable fixture and cancel the first destructive confirmation before confirming clear inside isolated storage.

- [ ] **Step 6: Fix every reproducible finding with a red/green test**

For each failure, add the smallest focused failing test or reproducible layout policy assertion, run it RED, implement the minimal correction, rerun the exact interaction, then rerun its parent workflow. Record before/after evidence in the report.

- [ ] **Step 7: Inspect unified logs and bounded performance**

Run a Release package, inspect launch/scan/export/persistence logs for crashes, repeated errors, and private content, and capture CPU/RSS during a large disposable scan. Do not claim performance readiness from Debug-only data.

- [ ] **Step 8: Commit the verified E2E slice**

```bash
git add script/build_and_run.sh script/fixtures docs/audit \
  SwiftExplorerApp/Sources SwiftExplorerApp/Tests
git commit -m "Add isolated end-to-end verification for the Mac app"
```

---

### Task 8: Release Evidence, Documentation, And Final Verification

**Files:**

- Modify: `README.md`
- Modify: `INSTALL.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/production-plan.md`
- Modify: `docs/app-store-release-checklist.md`
- Modify: `MEMORY.md`
- Modify: `PLAN.md`
- Modify: `TODO.md`
- Modify: `docs/audit/codebase-combiner-e2e-audit-2026-07-13.md`

**Interfaces:**

- Produces: current commands, architecture decisions, exact evidence, truthful readiness label, and remaining toolchain/Apple/manual blockers.

- [ ] **Step 1: Update public and durable documentation**

Document the adaptive workspace, concealed recovered output, isolated E2E command, macOS 13 baseline, bounded newer-system presentation, and current packaging path. Remove claims that depend only on June evidence.

- [ ] **Step 2: Run every fresh verification gate**

```bash
cd SwiftExplorerApp
swiftformat --lint .
swift test
swift build -c release -Xswiftc -warnings-as-errors
cd ..
npm test
npm run lint
npm run format:check
bash -n script/build_and_run.sh Packaging/AppStore/build_app_store_package.sh
Packaging/AppStore/build_app_store_package.sh --skip-signing
./script/build_and_run.sh --verify
git diff --check
```

Expected: every command exits 0. Record exact test counts, toolchain, bundle ID/version, signature mode, and evidence paths.

- [ ] **Step 3: Inspect package privacy and signing evidence**

```bash
plutil -lint 'dist/app-store/Codebase Combiner.app/Contents/Info.plist'
plutil -p 'dist/app-store/Codebase Combiner.app/Contents/Resources/PrivacyInfo.xcprivacy'
codesign --verify --deep --strict --verbose=2 'dist/app-store/Codebase Combiner.app'
codesign -d --entitlements :- 'dist/app-store/Codebase Combiner.app'
```

Expected: plist and privacy manifest parse, bundle signature verifies, and entitlements contain sandbox plus user-selected read/write only.

- [ ] **Step 4: Reconcile the scenario matrix and readiness label**

Every row must be `verified`, `failed`, `blocked`, or `not applicable` with evidence. Use the weakest truthful label. Keep macOS 27 SDK proof, Apple signing identities/profile, App Store Connect metadata/privacy/legal declarations, upload, and review outside repository completion.

- [ ] **Step 5: Close repo plan, TODO, and memory**

Check every completed TODO item, record exact tests and tradeoffs in `PLAN.md`, and add only stable commands/architecture/pitfalls/decisions to `MEMORY.md`. Do not add secrets or private fixture contents.

- [ ] **Step 6: Review and commit only intentional documentation**

```bash
git status --short
git diff --check
git diff --stat
git add README.md INSTALL.md CHANGELOG.md docs MEMORY.md
git commit -m "Document adaptive Mac app readiness"
```

- [ ] **Step 7: Final branch verification**

Re-run the complete commands from Step 2 at final HEAD, inspect `git status --short --branch`, and report the exact repository/package/readiness state without pushing, opening a PR, uploading, or changing Apple account state unless separately authorized.
