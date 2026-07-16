@testable import CodebaseExplorerApp
import XCTest

@MainActor
final class AppCommandStateTests: XCTestCase {
    func testSidebarCommandAndToolbarShareControllerVisibilityState() throws {
        let defaultsName = "sidebar-command-state.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let controller = AppController(
            preferences: AppPreferences(defaults: defaults),
            workspace: WorkspaceStore(),
            output: OutputStore(drafts: ControllerDraftStore(), clipboard: ControllerClipboard()),
            folderPicker: { nil },
            saveDestinationPicker: { _ in nil }
        )

        XCTAssertTrue(controller.isSidebarPresented)
        XCTAssertEqual(controller.sidebarCommandTitle, "Hide Workspace Sidebar")

        controller.toggleSidebar()

        XCTAssertFalse(controller.isSidebarPresented)
        XCTAssertEqual(controller.sidebarCommandTitle, "Show Workspace Sidebar")
    }

    func testCommandsNameMissingPrerequisites() {
        let empty = AppCommandState(hasWorkspace: false, isScanning: false, hasSelection: false, hasFreshOutput: false)
        XCTAssertFalse(empty.canRefresh)
        XCTAssertFalse(empty.canCopyRecovered)
        XCTAssertEqual(empty.copyHelp, "Select at least one file to copy the combined output.")
        XCTAssertEqual(empty.copyRecoveredHelp, "There is no recovered output to copy.")

        let ready = AppCommandState(hasWorkspace: true, isScanning: false, hasSelection: true, hasFreshOutput: true)
        XCTAssertTrue(ready.canRefresh)
        XCTAssertTrue(ready.canExport)
    }

    func testRefreshHelpNamesWhetherWorkspaceOrScanIsBlocking() {
        let missingWorkspace = AppCommandState(hasWorkspace: false, isScanning: false, hasSelection: false, hasFreshOutput: false)
        XCTAssertEqual(missingWorkspace.refreshHelp, "Choose a folder before refreshing the workspace.")

        let scanning = AppCommandState(hasWorkspace: true, isScanning: true, hasSelection: true, hasFreshOutput: true)
        XCTAssertEqual(scanning.refreshHelp, "Wait for the current workspace scan to finish.")

        let ready = AppCommandState(hasWorkspace: true, isScanning: false, hasSelection: true, hasFreshOutput: true)
        XCTAssertEqual(ready.refreshHelp, "Refresh workspace")
    }

    func testSaveHelpNamesMissingSelection() {
        let empty = AppCommandState(hasWorkspace: true, isScanning: false, hasSelection: false, hasFreshOutput: false)
        XCTAssertEqual(empty.saveHelp, "Select at least one file to save the combined output.")

        let ready = AppCommandState(hasWorkspace: true, isScanning: false, hasSelection: true, hasFreshOutput: true)
        XCTAssertEqual(ready.saveHelp, "Save combined output")
    }

    func testCopyAndSaveHelpNamePendingOutputBuild() {
        let building = AppCommandState(
            hasWorkspace: true,
            isScanning: false,
            hasSelection: true,
            hasFreshOutput: false
        )

        XCTAssertFalse(building.canExport)
        XCTAssertEqual(building.copyHelp, "Wait for the combined output to finish building.")
        XCTAssertEqual(building.saveHelp, "Wait for the combined output to finish building.")
    }

    func testRecoveredOutputCopyCapabilityIgnoresCurrentSelectionAndPayload() async throws {
        let clipboard = ControllerClipboard()
        let recoveredDraft = ClipboardDraft(
            text: "recovered source",
            format: .markdown,
            fileCount: 1,
            tokenCount: 2,
            byteCount: 16,
            rootPath: "/recovered-command",
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let output = OutputStore(
            drafts: ControllerDraftStore(draft: recoveredDraft),
            clipboard: clipboard
        )
        let controller = try AppController(
            preferences: AppPreferences(defaults: XCTUnwrap(UserDefaults(suiteName: "recovered-command-tests"))),
            workspace: WorkspaceStore(loader: RecordingControllerWorkspaceLoader(result: controllerTreeResult(
                rootURL: URL(fileURLWithPath: "/recovered-command")
            ))),
            output: output,
            folderPicker: { nil },
            saveDestinationPicker: { _ in nil }
        )

        await controller.start()

        XCTAssertTrue(controller.workspace.selectedFiles.isEmpty)
        XCTAssertNil(output.currentPayload)
        XCTAssertFalse(controller.commandState.canExport)
        XCTAssertTrue(controller.commandState.canCopyRecovered)
        XCTAssertEqual(controller.commandState.copyRecoveredHelp, "Copy the last recoverable output")

        controller.copyRecovered()

        XCTAssertEqual(clipboard.writtenTexts, ["recovered source"])
    }

    func testControllerScansWithPreferenceSnapshotAndRebuildsForSharedInputs() async throws {
        let defaultsName = "AppCommandStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.values.allowList = "swift,md"
        preferences.values.maxFileSizeKB = 768

        let rootURL = URL(fileURLWithPath: "/controller-workspace")
        let file = FileNode(
            name: "App.swift",
            relativePath: "App.swift",
            url: rootURL.appendingPathComponent("App.swift"),
            isDirectory: false,
            tokenCount: 2,
            sizeBytes: 8,
            content: "let app = true"
        )
        let result = TreeLoadResult(
            root: FileNode(
                name: "controller-workspace",
                relativePath: "controller-workspace",
                url: rootURL,
                isDirectory: true,
                children: [file],
                tokenCount: file.tokenCount,
                sizeBytes: file.sizeBytes,
                content: nil
            ),
            summary: ScanSummary()
        )
        let loader = RecordingControllerWorkspaceLoader(result: result)
        let workspace = WorkspaceStore(loader: loader)
        let output = OutputStore(
            drafts: ControllerDraftStore(),
            clipboard: ControllerClipboard()
        )
        let controller = AppController(
            preferences: preferences,
            workspace: workspace,
            output: output,
            folderPicker: { nil },
            saveDestinationPicker: { _ in nil }
        )

        await controller.scan(rootURL: rootURL)
        await waitUntilController { output.currentPayload?.contains("let app = true") == true }

        let receivedPreferences = await loader.receivedPreferences
        XCTAssertEqual(receivedPreferences?.allowList, "swift,md")
        XCTAssertEqual(receivedPreferences?.maxFileSizeKB, 768)
        XCTAssertTrue(controller.commandState.canExport)

        output.promptPrefix = "Review this workspace."
        await waitUntilController { output.currentPayload?.contains("Review this workspace.") == true }

        output.format = .plainText
        await waitUntilController { output.currentPayload?.contains("// File: App.swift") == true }

        workspace.clearSelection()
        await waitUntilController { output.currentPayload == nil }
        XCTAssertFalse(controller.commandState.canExport)
    }

    func testExportStaysDisabledUntilTheLatestOutputBuildCompletes() async throws {
        let rootURL = URL(fileURLWithPath: "/pending-build")
        let file = FileNode(
            name: "Current.swift",
            relativePath: "Current.swift",
            url: rootURL.appendingPathComponent("Current.swift"),
            isDirectory: false,
            tokenCount: 2,
            sizeBytes: 8,
            content: "let revision = 1"
        )
        let result = TreeLoadResult(
            root: FileNode(
                name: "pending-build",
                relativePath: "pending-build",
                url: rootURL,
                isDirectory: true,
                children: [file],
                tokenCount: file.tokenCount,
                sizeBytes: file.sizeBytes,
                content: nil
            ),
            summary: ScanSummary()
        )
        let builder = ControlledControllerOutputBuilder()
        let clipboard = ControllerClipboard()
        let savePicker = SavePickerRecorder()
        let workspace = WorkspaceStore(loader: RecordingControllerWorkspaceLoader(result: result))
        let output = OutputStore(
            drafts: ControllerDraftStore(),
            clipboard: clipboard,
            builder: builder
        )
        let controller = try AppController(
            preferences: AppPreferences(defaults: XCTUnwrap(UserDefaults(suiteName: "pending-build-tests"))),
            workspace: workspace,
            output: output,
            folderPicker: { nil },
            saveDestinationPicker: savePicker.destination
        )

        await controller.scan(rootURL: rootURL)
        await builder.waitForRequest(count: 1)

        XCTAssertTrue(workspace.selectedFiles.isEmpty == false)
        XCTAssertTrue(output.isBuilding)
        XCTAssertFalse(controller.commandState.canExport)
        XCTAssertNil(output.currentPayload)
        controller.copy()
        controller.save()
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
        XCTAssertEqual(savePicker.requestCount, 0)

        await builder.completeRequest(at: 0)
        await waitUntilController { controller.commandState.canExport }
        let acceptedPayload = output.currentPayload
        XCTAssertFalse(output.isBuilding)
        XCTAssertNotNil(acceptedPayload)

        output.promptPrefix = "Use the new revision."
        await builder.waitForRequest(count: 2)

        XCTAssertTrue(output.isBuilding)
        XCTAssertFalse(controller.commandState.canExport)
        XCTAssertNil(output.currentPayload)
        controller.copy()
        controller.save()
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
        XCTAssertEqual(savePicker.requestCount, 0)

        await builder.completeRequest(at: 1)
        await waitUntilController { controller.commandState.canExport }
        XCTAssertFalse(output.isBuilding)
        XCTAssertNotEqual(output.currentPayload, acceptedPayload)
        XCTAssertTrue(output.currentPayload?.contains("Use the new revision.") == true)
    }

    func testLatestWorkspaceFailureOverridesPriorOutputSuccessStatus() async throws {
        let rootURL = URL(fileURLWithPath: "/status-recency")
        let result = controllerTreeResult(rootURL: rootURL)
        let loader = FailingRefreshControllerWorkspaceLoader(firstResult: result)
        let output = OutputStore(
            drafts: ControllerDraftStore(),
            clipboard: ControllerClipboard()
        )
        let controller = try AppController(
            preferences: AppPreferences(defaults: XCTUnwrap(UserDefaults(suiteName: "status-recency-tests"))),
            workspace: WorkspaceStore(loader: loader),
            output: output,
            folderPicker: { nil },
            saveDestinationPicker: { _ in nil }
        )

        await controller.scan(rootURL: rootURL)
        await waitUntilController { output.status == "Saved recoverable output." }

        await controller.scan(rootURL: rootURL)

        XCTAssertEqual(output.status, "Saved recoverable output.")
        XCTAssertEqual(controller.displayStatus, "Refresh failed")
    }

    func testLatestMaximumSizeValidationOverridesPriorOutputSuccessStatus() async throws {
        let rootURL = URL(fileURLWithPath: "/validation-recency")
        let output = OutputStore(
            drafts: ControllerDraftStore(),
            clipboard: ControllerClipboard()
        )
        let defaultsName = "validation-recency-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let preferences = AppPreferences(defaults: defaults)
        let controller = AppController(
            preferences: preferences,
            workspace: WorkspaceStore(loader: RecordingControllerWorkspaceLoader(result: controllerTreeResult(rootURL: rootURL))),
            output: output,
            folderPicker: { nil },
            saveDestinationPicker: { _ in nil }
        )

        await controller.scan(rootURL: rootURL)
        await waitUntilController { output.status == "Saved recoverable output." }

        preferences.values.maxFileSizeKB = 31
        await controller.scan(rootURL: rootURL)

        XCTAssertEqual(output.status, "Saved recoverable output.")
        XCTAssertEqual(controller.displayStatus, "Correct the maximum file size before scanning.")
    }

    func testHiddenAndMaximumSizePreferenceChangesRescanWithoutFeedbackLoops() async throws {
        let defaultsName = "preference-rescan-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let rootURL = URL(fileURLWithPath: "/preference-rescan")
        let loader = RecordingControllerWorkspaceLoader(result: controllerTreeResult(rootURL: rootURL))
        let preferences = AppPreferences(defaults: defaults)
        let output = OutputStore(
            drafts: ControllerDraftStore(),
            clipboard: ControllerClipboard()
        )
        let controller = AppController(
            preferences: preferences,
            workspace: WorkspaceStore(loader: loader),
            output: output,
            folderPicker: { nil },
            saveDestinationPicker: { _ in nil }
        )
        await controller.scan(rootURL: rootURL)
        var loadCount = await loader.loadCount
        XCTAssertEqual(loadCount, 1)

        preferences.values.skipHidden = false
        var didRescan = await loader.waitForLoadCount(2)
        var receivedPreferences = await loader.receivedPreferences
        XCTAssertTrue(didRescan)
        XCTAssertEqual(receivedPreferences?.skipHidden, false)

        preferences.values.maxFileSizeKB = 1024
        didRescan = await loader.waitForLoadCount(3)
        receivedPreferences = await loader.receivedPreferences
        XCTAssertTrue(didRescan)
        XCTAssertEqual(receivedPreferences?.maxFileSizeKB, 1024)

        output.format = .plainText
        preferences.values.showFilters.toggle()
        try await Task.sleep(for: .milliseconds(500))
        loadCount = await loader.loadCount
        XCTAssertEqual(loadCount, 3)
    }

    func testAllowAndExcludeChangesEachScheduleExactlyOneDebouncedRescan() async throws {
        let defaultsName = "filter-rescan-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let rootURL = URL(fileURLWithPath: "/filter-rescan")
        let loader = RecordingControllerWorkspaceLoader(result: controllerTreeResult(rootURL: rootURL))
        let preferences = AppPreferences(defaults: defaults)
        let controller = AppController(
            preferences: preferences,
            workspace: WorkspaceStore(loader: loader),
            output: OutputStore(drafts: ControllerDraftStore(), clipboard: ControllerClipboard()),
            folderPicker: { nil },
            saveDestinationPicker: { _ in nil }
        )
        await controller.scan(rootURL: rootURL)
        var loadCount = await loader.loadCount
        XCTAssertEqual(loadCount, 1)

        preferences.values.allowList = "swift,md"
        var didRescan = await loader.waitForLoadCount(2)
        XCTAssertTrue(didRescan)
        try await Task.sleep(for: .milliseconds(500))
        loadCount = await loader.loadCount
        var receivedPreferences = await loader.receivedPreferences
        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(receivedPreferences?.allowList, "swift,md")

        preferences.values.excludeList = "png,zip"
        didRescan = await loader.waitForLoadCount(3)
        XCTAssertTrue(didRescan)
        try await Task.sleep(for: .milliseconds(500))
        loadCount = await loader.loadCount
        receivedPreferences = await loader.receivedPreferences
        XCTAssertEqual(loadCount, 3)
        XCTAssertEqual(receivedPreferences?.excludeList, "png,zip")
    }

    func testRepeatedSuccessfulRebuildReplacesBuildingStatusWithSuccess() async throws {
        let rootURL = URL(fileURLWithPath: "/repeated-success-status")
        let builder = ControlledControllerOutputBuilder()
        let output = OutputStore(
            drafts: ControllerDraftStore(),
            clipboard: ControllerClipboard(),
            builder: builder
        )
        let defaultsName = "repeated-success-status-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let controller = AppController(
            preferences: AppPreferences(defaults: defaults),
            workspace: WorkspaceStore(loader: RecordingControllerWorkspaceLoader(result: controllerTreeResult(rootURL: rootURL))),
            output: output,
            folderPicker: { nil },
            saveDestinationPicker: { _ in nil }
        )

        await controller.scan(rootURL: rootURL)
        await builder.waitForRequest(count: 1)
        await builder.completeRequest(at: 0)
        await waitUntilController { controller.displayStatus == "Saved recoverable output." }

        output.promptPrefix = "Use the latest prompt."
        await builder.waitForRequest(count: 2)
        XCTAssertEqual(controller.displayStatus, "Building combined output…")

        await builder.completeRequest(at: 1)
        await waitUntilController { controller.commandState.canExport }
        await Task.yield()

        XCTAssertEqual(controller.displayStatus, "Saved recoverable output.")
    }

    func testSuccessfulRecoveryRetryClearsTheControllerFailureStatus() async throws {
        let drafts = RecoveringControllerDraftStore()
        let output = OutputStore(drafts: drafts, clipboard: ControllerClipboard())
        let defaultsName = "recovery-status-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let controller = AppController(
            preferences: AppPreferences(defaults: defaults),
            workspace: WorkspaceStore(),
            output: output,
            folderPicker: { nil },
            saveDestinationPicker: { _ in nil }
        )

        await controller.start()
        XCTAssertTrue(controller.displayStatus.contains("Could not load the recovered output"))
        await drafts.allowLoads()

        await output.loadRecoveredDraft()
        await Task.yield()

        XCTAssertEqual(controller.displayStatus, controller.workspace.status)
    }

    func testSaveCommitsTheExactPayloadShownWhenThePanelOpened() async throws {
        let rootURL = URL(fileURLWithPath: "/save-snapshot")
        let saver = RecordingControllerPayloadSaver()
        let output = OutputStore(
            drafts: ControllerDraftStore(),
            clipboard: ControllerClipboard(),
            saver: saver
        )
        let defaultsName = "save-snapshot-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let destination = URL(fileURLWithPath: "/tmp/save-snapshot.md")
        let controller = AppController(
            preferences: AppPreferences(defaults: defaults),
            workspace: WorkspaceStore(loader: RecordingControllerWorkspaceLoader(result: controllerTreeResult(rootURL: rootURL))),
            output: output,
            folderPicker: { nil },
            saveDestinationPicker: { _ in
                output.invalidateCurrentOutput()
                return destination
            }
        )

        await controller.scan(rootURL: rootURL)
        await waitUntilController { controller.commandState.canExport }
        let payloadAtPanelOpen = try XCTUnwrap(output.currentPayload)

        controller.save()
        let didWrite = await saver.waitUntilWritten()

        let write = await saver.lastWrite
        XCTAssertTrue(didWrite)
        XCTAssertEqual(write?.text, payloadAtPanelOpen)
        XCTAssertEqual(write?.url, destination)
    }
}

private func controllerTreeResult(rootURL: URL) -> TreeLoadResult {
    let file = FileNode(
        name: "App.swift",
        relativePath: "App.swift",
        url: rootURL.appendingPathComponent("App.swift"),
        isDirectory: false,
        tokenCount: 2,
        sizeBytes: 8,
        content: "let app = true"
    )
    return TreeLoadResult(
        root: FileNode(
            name: rootURL.lastPathComponent,
            relativePath: rootURL.lastPathComponent,
            url: rootURL,
            isDirectory: true,
            children: [file],
            tokenCount: file.tokenCount,
            sizeBytes: file.sizeBytes,
            content: nil
        ),
        summary: ScanSummary()
    )
}

private actor RecordingControllerWorkspaceLoader: WorkspaceLoading {
    private(set) var receivedPreferences: AppPreferences.Values?
    private let result: TreeLoadResult
    private(set) var loadCount = 0

    init(result: TreeLoadResult) {
        self.result = result
    }

    func load(rootURL _: URL, preferences: AppPreferences.Values) async throws -> TreeLoadResult {
        loadCount += 1
        receivedPreferences = preferences
        return result
    }

    func waitForLoadCount(_ expectedCount: Int) async -> Bool {
        for _ in 0 ..< 800 {
            if loadCount >= expectedCount { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

private actor FailingRefreshControllerWorkspaceLoader: WorkspaceLoading {
    private let firstResult: TreeLoadResult
    private var loadCount = 0

    init(firstResult: TreeLoadResult) {
        self.firstResult = firstResult
    }

    func load(rootURL _: URL, preferences _: AppPreferences.Values) async throws -> TreeLoadResult {
        loadCount += 1
        guard loadCount == 1 else { throw ControllerLoaderError.refreshFailed }
        return firstResult
    }
}

private enum ControllerLoaderError: LocalizedError {
    case refreshFailed

    var errorDescription: String? {
        "Refresh failed"
    }
}

private actor ControllerDraftStore: DraftPersisting {
    private var draft: ClipboardDraft?

    init(draft: ClipboardDraft? = nil) {
        self.draft = draft
    }

    func load() async throws -> ClipboardDraft? {
        draft
    }

    func save(_ draft: ClipboardDraft) async throws {
        self.draft = draft
    }

    func clear() async throws {
        draft = nil
    }
}

private actor RecoveringControllerDraftStore: DraftPersisting {
    private var shouldFailLoads = true

    func load() async throws -> ClipboardDraft? {
        if shouldFailLoads { throw ControllerDraftError.loadDenied }
        return nil
    }

    func save(_: ClipboardDraft) async throws {}

    func clear() async throws {}

    func allowLoads() {
        shouldFailLoads = false
    }
}

private enum ControllerDraftError: LocalizedError {
    case loadDenied

    var errorDescription: String? {
        "Draft load denied"
    }
}

private actor RecordingControllerPayloadSaver: PayloadSaving {
    private(set) var lastWrite: (text: String, url: URL)?

    func save(_ text: String, to url: URL) async throws {
        lastWrite = (text, url)
    }

    func waitUntilWritten() async -> Bool {
        for _ in 0 ..< 10000 {
            if lastWrite != nil { return true }
            await Task.yield()
        }
        return false
    }
}

@MainActor
private final class ControllerClipboard: ClipboardWriting {
    private(set) var writtenTexts: [String] = []

    func write(_ text: String) throws {
        writtenTexts.append(text)
    }
}

@MainActor
private final class SavePickerRecorder {
    private(set) var requestCount = 0

    func destination(format _: CombinedOutputFormat) -> URL? {
        requestCount += 1
        return URL(fileURLWithPath: "/tmp/combined.md")
    }
}

private actor ControlledControllerOutputBuilder: OutputBuilding {
    private var inputs: [OutputBuildInput] = []
    private var continuations: [CheckedContinuation<BuiltOutput, Never>?] = []

    func build(_ input: OutputBuildInput) async -> BuiltOutput {
        await withCheckedContinuation { continuation in
            inputs.append(input)
            continuations.append(continuation)
        }
    }

    func waitForRequest(count: Int) async {
        while inputs.count < count {
            await Task.yield()
        }
    }

    func completeRequest(at index: Int) {
        let input = inputs[index]
        let payload = CombinedOutputBuilder().build(
            promptPrefix: input.promptPrefix,
            files: input.files,
            format: input.format
        )
        let draft = ClipboardDraft(
            text: payload,
            format: input.format,
            fileCount: input.files.count,
            tokenCount: input.files.reduce(0) { $0 + $1.tokenCount },
            byteCount: input.files.reduce(0) { $0 + $1.sizeBytes },
            rootPath: input.rootPath,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        continuations[index]?.resume(returning: BuiltOutput(payload: payload, draft: draft))
        continuations[index] = nil
    }
}

@MainActor
private func waitUntilController(
    _ condition: @escaping @MainActor () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0 ..< 10000 {
        if condition() { return }
        await Task.yield()
    }
    XCTFail("Condition did not become true", file: file, line: line)
}
