@testable import CodebaseExplorerApp
import Foundation
import XCTest

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    func testFailedScanRetainsTypedRetryRequestAndRetryCanRecover() async {
        let rootURL = URL(fileURLWithPath: "/retry-workspace")
        let preferences = AppPreferences.Values(allowList: "swift", maxFileSizeKB: 256)
        let loader = RetryWorkspaceLoader(result: .fileFixture(rootURL: rootURL, names: ["Recovered.swift"]))
        let store = WorkspaceStore(loader: loader)

        let failedOutcome = await store.scan(rootURL: rootURL, preferences: preferences)

        XCTAssertEqual(failedOutcome, .failed)
        XCTAssertEqual(store.scanFailure?.kind, .scanFailed)
        XCTAssertEqual(store.scanFailure?.message, "Current scan failed")
        XCTAssertTrue(store.canRetryFailedScan)

        let retryOutcome = await store.retryFailedScan()

        XCTAssertEqual(retryOutcome, .accepted(fileCount: 1, selectedCount: 1, skippedCount: 0))
        XCTAssertNil(store.scanFailure)
        XCTAssertFalse(store.canRetryFailedScan)
        XCTAssertEqual(store.rootURL, rootURL)
        let attemptCount = await loader.attemptCount
        let lastPreferences = await loader.lastPreferences
        XCTAssertEqual(attemptCount, 2)
        XCTAssertEqual(lastPreferences, preferences)
    }

    func testFailedScanRetryCannotReplaceANewerChosenWorkspace() async {
        let failedRoot = URL(fileURLWithPath: "/failed-retry")
        let newerRoot = URL(fileURLWithPath: "/newer-workspace")
        let loader = RetryRaceWorkspaceLoader(
            failedRoot: failedRoot,
            failedResult: .fileFixture(rootURL: failedRoot, names: ["old.swift"]),
            newerRoot: newerRoot,
            newerResult: .fileFixture(rootURL: newerRoot, names: ["new.swift"])
        )
        let store = WorkspaceStore(loader: loader)
        _ = await store.scan(rootURL: failedRoot, preferences: .init())

        let retry = Task { await store.retryFailedScan() }
        await loader.waitUntilRetryRequested()
        let newerOutcome = await store.scan(rootURL: newerRoot, preferences: .init())
        await loader.completeRetry()
        let retryOutcome = await retry.value

        XCTAssertEqual(newerOutcome, .accepted(fileCount: 1, selectedCount: 1, skippedCount: 0))
        XCTAssertEqual(retryOutcome, .stale)
        XCTAssertEqual(store.rootURL, newerRoot)
        XCTAssertEqual(store.allFiles.map(\.name), ["new.swift"])
        XCTAssertNil(store.scanFailure)
    }

    func testStaleResultCannotReplaceNewerWorkspace() async {
        let loader = ControlledWorkspaceLoader()
        let store = WorkspaceStore(loader: loader)
        let oldURL = URL(fileURLWithPath: "/old")
        let newURL = URL(fileURLWithPath: "/new")

        let oldScan = Task { await store.scan(rootURL: oldURL, preferences: .init()) }
        await loader.waitUntilRequested(oldURL)
        let newScan = Task { await store.scan(rootURL: newURL, preferences: .init()) }
        await loader.waitUntilRequested(newURL)

        await loader.succeed(newURL, with: .fixture(named: "new"))
        _ = await newScan.value
        await loader.succeed(oldURL, with: .fixture(named: "old"))
        let oldOutcome = await oldScan.value

        XCTAssertEqual(store.rootNode?.name, "new")
        XCTAssertEqual(store.rootURL, newURL)
        XCTAssertEqual(oldOutcome, .stale)
    }

    func testStaleFailureCannotReplaceNewerWorkspaceStatus() async {
        let loader = ControlledWorkspaceLoader()
        let store = WorkspaceStore(loader: loader)
        let oldURL = URL(fileURLWithPath: "/old")
        let newURL = URL(fileURLWithPath: "/new")

        let oldScan = Task { await store.scan(rootURL: oldURL, preferences: .init()) }
        await loader.waitUntilRequested(oldURL)
        let newScan = Task { await store.scan(rootURL: newURL, preferences: .init()) }
        await loader.waitUntilRequested(newURL)

        await loader.succeed(newURL, with: .fileFixture(names: ["new.swift"]))
        _ = await newScan.value
        await loader.fail(oldURL, with: LoaderError.oldScanFailed)
        let oldOutcome = await oldScan.value

        XCTAssertEqual(store.rootNode?.name, "workspace")
        XCTAssertEqual(store.status, "Loaded 1 files, 1 selected")
        XCTAssertFalse(store.isScanning)
        XCTAssertEqual(oldOutcome, .stale)
    }

    func testCurrentFailurePublishesErrorAndStopsScanning() async {
        let loader = ControlledWorkspaceLoader()
        let store = WorkspaceStore(loader: loader)
        let rootURL = URL(fileURLWithPath: "/unreadable")

        let scan = Task { await store.scan(rootURL: rootURL, preferences: .init()) }
        await loader.waitUntilRequested(rootURL)
        XCTAssertNil(store.rootURL)
        XCTAssertEqual(store.status, "Scanning…")
        XCTAssertTrue(store.isScanning)

        await loader.fail(rootURL, with: LoaderError.currentScanFailed)
        let outcome = await scan.value

        XCTAssertEqual(store.status, "Current scan failed")
        XCTAssertFalse(store.isScanning)
        XCTAssertNil(store.rootNode)
        XCTAssertEqual(outcome, .failed)
    }

    func testInvalidMaximumFileSizeRejectsScanWithoutReplacingWorkspace() async {
        let result = TreeLoadResult.twoFileFixture
        let store = WorkspaceStore(loader: ImmediateWorkspaceLoader(result: result))

        let outcome = await store.scan(
            rootURL: result.root.url,
            preferences: AppPreferences.Values(maxFileSizeKB: 31)
        )

        XCTAssertEqual(store.status, "Correct the maximum file size before scanning.")
        XCTAssertNil(store.rootURL)
        XCTAssertNil(store.rootNode)
        XCTAssertFalse(store.isScanning)
        XCTAssertEqual(outcome, .rejectedInvalidMaximumFileSize)
    }

    func testInvalidRequestSupersedesInFlightScanAndPreservesAcceptedWorkspace() async {
        let loader = ControlledWorkspaceLoader()
        let store = WorkspaceStore(loader: loader)
        let acceptedRoot = URL(fileURLWithPath: "/accepted")
        let inFlightRoot = URL(fileURLWithPath: "/in-flight")
        let invalidRoot = URL(fileURLWithPath: "/invalid")

        let acceptedScan = Task { await store.scan(rootURL: acceptedRoot, preferences: .init()) }
        await loader.waitUntilRequested(acceptedRoot)
        await loader.succeed(
            acceptedRoot,
            with: .fileFixture(rootURL: acceptedRoot, names: ["accepted.swift"])
        )
        _ = await acceptedScan.value
        let acceptedState = store.state

        let inFlightScan = Task { await store.scan(rootURL: inFlightRoot, preferences: .init()) }
        await loader.waitUntilRequested(inFlightRoot)

        let invalidOutcome = await store.scan(
            rootURL: invalidRoot,
            preferences: AppPreferences.Values(maxFileSizeKB: 31)
        )

        XCTAssertEqual(invalidOutcome, .rejectedInvalidMaximumFileSize)
        XCTAssertNil(store.activeRequestID)
        XCTAssertFalse(store.isScanning)
        XCTAssertEqual(store.status, "Correct the maximum file size before scanning.")
        XCTAssertEqual(store.rootURL, acceptedState.rootURL)
        XCTAssertEqual(store.rootNode, acceptedState.rootNode)
        XCTAssertEqual(store.selectedIDs, acceptedState.selectedIDs)

        await loader.succeed(
            inFlightRoot,
            with: .fileFixture(rootURL: inFlightRoot, names: ["stale.swift"])
        )
        let inFlightOutcome = await inFlightScan.value

        XCTAssertEqual(inFlightOutcome, .stale)
        XCTAssertNil(store.activeRequestID)
        XCTAssertEqual(store.status, "Correct the maximum file size before scanning.")
        XCTAssertEqual(store.rootURL, acceptedState.rootURL)
        XCTAssertEqual(store.rootNode, acceptedState.rootNode)
        XCTAssertEqual(store.selectedIDs, acceptedState.selectedIDs)
    }

    func testInvalidRequestClearsRetainedFailedScanRetry() async {
        let rootURL = URL(fileURLWithPath: "/retry-workspace")
        let loader = RetryWorkspaceLoader(
            result: .fileFixture(rootURL: rootURL, names: ["Recovered.swift"])
        )
        let store = WorkspaceStore(loader: loader)
        _ = await store.scan(rootURL: rootURL, preferences: .init())
        XCTAssertTrue(store.canRetryFailedScan)
        XCTAssertNotNil(store.scanFailure)

        let invalidOutcome = await store.scan(
            rootURL: rootURL,
            preferences: AppPreferences.Values(maxFileSizeKB: 31)
        )

        XCTAssertEqual(invalidOutcome, .rejectedInvalidMaximumFileSize)
        XCTAssertNil(store.activeRequestID)
        XCTAssertFalse(store.canRetryFailedScan)
        XCTAssertNil(store.scanFailure)
        XCTAssertFalse(store.isScanning)
        XCTAssertEqual(store.status, "Correct the maximum file size before scanning.")

        let retryOutcome = await store.retryFailedScan()
        let attemptCount = await loader.attemptCount
        XCTAssertEqual(retryOutcome, .failed)
        XCTAssertEqual(attemptCount, 1)
    }

    func testFirstAcceptedScanSelectsAllAvailableFilesAndUpdatesTotals() async {
        let result = TreeLoadResult.twoFileFixture
        let store = WorkspaceStore(loader: ImmediateWorkspaceLoader(result: result))

        let outcome = await store.scan(rootURL: result.root.url, preferences: .init())

        XCTAssertEqual(store.allFiles.map(\.name), ["a.swift", "b.swift"])
        XCTAssertEqual(store.selectedIDs, Set(store.allFiles.map(\.id)))
        XCTAssertEqual(store.selectedFiles, store.allFiles)
        XCTAssertEqual(store.selectedBytes, 30)
        XCTAssertEqual(store.selectedTokens, 12)
        XCTAssertEqual(store.status, "Loaded 2 files, 2 selected")
        XCTAssertEqual(outcome, .accepted(fileCount: 2, selectedCount: 2, skippedCount: 0))
    }

    func testAcceptedFilesUseLocaleIndependentLexicalOrder() async {
        let result = TreeLoadResult.fileFixture(names: ["a2.swift", "a10.swift"])
        let store = WorkspaceStore(loader: ImmediateWorkspaceLoader(result: result))

        _ = await store.scan(rootURL: result.root.url, preferences: .init())

        XCTAssertEqual(store.allFiles.map(\.name), ["a10.swift", "a2.swift"])
    }

    func testAcceptedScanPublishesStructuredSummary() async {
        let fixture = TreeLoadResult.twoFileFixture
        var summary = ScanSummary()
        summary.record(.hidden)
        summary.record(.oversized)
        let result = TreeLoadResult(root: fixture.root, summary: summary)
        let store = WorkspaceStore(loader: ImmediateWorkspaceLoader(result: result))

        await store.scan(rootURL: result.root.url, preferences: .init())

        XCTAssertEqual(store.summary, summary)
    }

    func testClearAndToggleUpdateTheSelectionSnapshot() async {
        let result = TreeLoadResult.twoFileFixture
        let store = WorkspaceStore(loader: ImmediateWorkspaceLoader(result: result))
        await store.scan(rootURL: result.root.url, preferences: .init())

        store.clearSelection()
        XCTAssertTrue(store.selectedFiles.isEmpty)
        XCTAssertEqual(store.selectedBytes, 0)
        XCTAssertEqual(store.selectedTokens, 0)

        store.toggle(node: store.allFiles[0], isOn: true)
        XCTAssertEqual(store.selectedFiles, [store.allFiles[0]])
        XCTAssertEqual(store.selectedBytes, store.allFiles[0].sizeBytes)
        XCTAssertEqual(store.selectedTokens, store.allFiles[0].tokenCount)
    }

    func testSelectAllRestoresEveryAvailableFile() async {
        let result = TreeLoadResult.twoFileFixture
        let store = WorkspaceStore(loader: ImmediateWorkspaceLoader(result: result))
        await store.scan(rootURL: result.root.url, preferences: .init())
        store.clearSelection()

        store.selectAll()

        XCTAssertEqual(store.selectedFiles, store.allFiles)
        XCTAssertEqual(store.selectedBytes, 30)
        XCTAssertEqual(store.selectedTokens, 12)
    }

    func testTogglingTheRootUpdatesEveryDescendantFile() async {
        let result = TreeLoadResult.twoFileFixture
        let store = WorkspaceStore(loader: ImmediateWorkspaceLoader(result: result))
        await store.scan(rootURL: result.root.url, preferences: .init())
        store.clearSelection()

        store.toggle(node: result.root, isOn: true)
        XCTAssertEqual(store.selectedFiles, store.allFiles)

        store.toggle(node: result.root, isOn: false)
        XCTAssertTrue(store.selectedFiles.isEmpty)
    }

    func testRefreshPreservesOnlySelectedFilesThatRemainAvailable() async {
        let first = TreeLoadResult.twoFileFixture
        let refreshed = TreeLoadResult.fileFixture(names: ["a.swift", "c.swift"])
        let store = WorkspaceStore(loader: SequenceWorkspaceLoader(results: [first, refreshed]))
        await store.scan(rootURL: first.root.url, preferences: .init())
        store.clearSelection()
        store.toggle(node: store.allFiles[0], isOn: true)

        await store.scan(rootURL: refreshed.root.url, preferences: .init())

        XCTAssertEqual(store.allFiles.map(\.name), ["a.swift", "c.swift"])
        XCTAssertEqual(store.selectedFiles.map(\.name), ["a.swift"])
        XCTAssertEqual(store.status, "Loaded 2 files, 1 selected")
    }

    func testSwitchingRootsSelectsEveryFileInTheNewWorkspace() async throws {
        let rootA = URL(fileURLWithPath: "/workspace-a")
        let rootB = URL(fileURLWithPath: "/workspace-b")
        let first = TreeLoadResult.fileFixture(rootURL: rootA, names: ["a-only.swift", "shared.swift"])
        let second = TreeLoadResult.fileFixture(rootURL: rootB, names: ["b-new.swift", "shared.swift"])
        let store = WorkspaceStore(loader: SequenceWorkspaceLoader(results: [first, second]))
        await store.scan(rootURL: rootA, preferences: .init())
        store.clearSelection()
        let sharedFile = try XCTUnwrap(store.allFiles.first { $0.name == "shared.swift" })
        store.toggle(node: sharedFile, isOn: true)

        await store.scan(rootURL: rootB, preferences: .init())

        XCTAssertEqual(store.rootURL, rootB)
        XCTAssertEqual(store.selectedFiles, store.allFiles)
        XCTAssertEqual(store.selectedIDs, Set(store.allFiles.map(\.id)))
    }

    func testFailedRootSwitchKeepsTheAcceptedWorkspaceCoherent() async throws {
        let loader = ControlledWorkspaceLoader()
        let store = WorkspaceStore(loader: loader)
        let rootA = URL(fileURLWithPath: "/workspace-a")
        let rootB = URL(fileURLWithPath: "/workspace-b")
        let acceptedResult = TreeLoadResult.fileFixture(
            rootURL: rootA,
            names: ["a-only.swift", "shared.swift"]
        )

        let firstScan = Task { await store.scan(rootURL: rootA, preferences: .init()) }
        await loader.waitUntilRequested(rootA)
        await loader.succeed(rootA, with: acceptedResult)
        _ = await firstScan.value
        store.clearSelection()
        let selectedFile = try XCTUnwrap(store.allFiles.first { $0.name == "shared.swift" })
        store.toggle(node: selectedFile, isOn: true)
        let acceptedState = store.state

        let failedScan = Task { await store.scan(rootURL: rootB, preferences: .init()) }
        await loader.waitUntilRequested(rootB)
        XCTAssertEqual(store.rootURL, rootA)
        await loader.fail(rootB, with: LoaderError.currentScanFailed)
        _ = await failedScan.value

        XCTAssertEqual(store.rootURL, rootA)
        XCTAssertEqual(store.rootNode, acceptedState.rootNode)
        XCTAssertEqual(store.allFiles, acceptedState.allFiles)
        XCTAssertEqual(store.selectedFiles, acceptedState.selectedFiles)
        XCTAssertEqual(store.selectedIDs, acceptedState.selectedIDs)
        XCTAssertEqual(store.selectedBytes, acceptedState.selectedBytes)
        XCTAssertEqual(store.selectedTokens, acceptedState.selectedTokens)
        XCTAssertEqual(store.summary, acceptedState.summary)
        XCTAssertEqual(store.status, "Current scan failed")
        XCTAssertFalse(store.isScanning)
    }
}

private struct ImmediateWorkspaceLoader: WorkspaceLoading {
    let result: TreeLoadResult

    func load(rootURL _: URL, preferences _: AppPreferences.Values) async throws -> TreeLoadResult {
        result
    }
}

private actor SequenceWorkspaceLoader: WorkspaceLoading {
    private var results: [TreeLoadResult]

    init(results: [TreeLoadResult]) {
        self.results = results
    }

    func load(rootURL _: URL, preferences _: AppPreferences.Values) async throws -> TreeLoadResult {
        results.removeFirst()
    }
}

private actor RetryWorkspaceLoader: WorkspaceLoading {
    private let result: TreeLoadResult
    private(set) var attemptCount = 0
    private(set) var lastPreferences: AppPreferences.Values?

    init(result: TreeLoadResult) {
        self.result = result
    }

    func load(rootURL _: URL, preferences: AppPreferences.Values) async throws -> TreeLoadResult {
        attemptCount += 1
        lastPreferences = preferences
        guard attemptCount > 1 else { throw LoaderError.currentScanFailed }
        return result
    }
}

private actor RetryRaceWorkspaceLoader: WorkspaceLoading {
    private let failedRoot: URL
    private let failedResult: TreeLoadResult
    private let newerRoot: URL
    private let newerResult: TreeLoadResult
    private var failedRootAttempts = 0
    private var retryWasRequested = false
    private var retryContinuation: CheckedContinuation<TreeLoadResult, Never>?

    init(failedRoot: URL, failedResult: TreeLoadResult, newerRoot: URL, newerResult: TreeLoadResult) {
        self.failedRoot = failedRoot
        self.failedResult = failedResult
        self.newerRoot = newerRoot
        self.newerResult = newerResult
    }

    func load(rootURL: URL, preferences _: AppPreferences.Values) async throws -> TreeLoadResult {
        if rootURL == failedRoot {
            failedRootAttempts += 1
            guard failedRootAttempts > 1 else { throw LoaderError.currentScanFailed }
            retryWasRequested = true
            return await withCheckedContinuation { continuation in
                retryContinuation = continuation
            }
        }
        if rootURL == newerRoot {
            return newerResult
        }
        return failedResult
    }

    func waitUntilRetryRequested() async {
        while !retryWasRequested {
            await Task.yield()
        }
    }

    func completeRetry() {
        retryContinuation?.resume(returning: failedResult)
        retryContinuation = nil
    }
}

private actor ControlledWorkspaceLoader: WorkspaceLoading {
    private var continuations: [URL: CheckedContinuation<TreeLoadResult, any Error>] = [:]
    private var requestedURLs: Set<URL> = []

    func load(rootURL: URL, preferences _: AppPreferences.Values) async throws -> TreeLoadResult {
        requestedURLs.insert(rootURL)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[rootURL] = continuation
        }
    }

    func waitUntilRequested(_ rootURL: URL) async {
        while !requestedURLs.contains(rootURL) {
            await Task.yield()
        }
    }

    func succeed(_ rootURL: URL, with result: TreeLoadResult) {
        continuations.removeValue(forKey: rootURL)?.resume(returning: result)
    }

    func fail(_ rootURL: URL, with error: LoaderError) {
        continuations.removeValue(forKey: rootURL)?.resume(throwing: error)
    }
}

private enum LoaderError: LocalizedError, Sendable {
    case oldScanFailed
    case currentScanFailed

    var errorDescription: String? {
        switch self {
        case .oldScanFailed:
            "Old scan failed"
        case .currentScanFailed:
            "Current scan failed"
        }
    }
}

private extension TreeLoadResult {
    static func fixture(named name: String) -> TreeLoadResult {
        TreeLoadResult(
            root: FileNode(
                name: name,
                relativePath: name,
                url: URL(fileURLWithPath: "/\(name)"),
                isDirectory: true,
                tokenCount: 0,
                sizeBytes: 0,
                content: nil
            ),
            summary: ScanSummary()
        )
    }

    static var twoFileFixture: TreeLoadResult {
        let rootURL = URL(fileURLWithPath: "/workspace")
        return TreeLoadResult(
            root: FileNode(
                name: "workspace",
                relativePath: "workspace",
                url: rootURL,
                isDirectory: true,
                children: [
                    FileNode(
                        name: "b.swift",
                        relativePath: "b.swift",
                        url: rootURL.appendingPathComponent("b.swift"),
                        isDirectory: false,
                        tokenCount: 7,
                        sizeBytes: 20,
                        content: "bbbb"
                    ),
                    FileNode(
                        name: "a.swift",
                        relativePath: "a.swift",
                        url: rootURL.appendingPathComponent("a.swift"),
                        isDirectory: false,
                        tokenCount: 5,
                        sizeBytes: 10,
                        content: "aaaa"
                    ),
                ],
                tokenCount: 12,
                sizeBytes: 30,
                content: nil
            ),
            summary: ScanSummary()
        )
    }

    static func fileFixture(
        rootURL: URL = URL(fileURLWithPath: "/workspace"),
        names: [String]
    ) -> TreeLoadResult {
        let files = names.enumerated().map { index, name in
            FileNode(
                name: name,
                relativePath: name,
                url: rootURL.appendingPathComponent(name),
                isDirectory: false,
                tokenCount: index + 1,
                sizeBytes: (index + 1) * 10,
                content: name
            )
        }
        return TreeLoadResult(
            root: FileNode(
                name: "workspace",
                relativePath: "workspace",
                url: rootURL,
                isDirectory: true,
                children: files,
                tokenCount: files.reduce(0) { $0 + $1.tokenCount },
                sizeBytes: files.reduce(0) { $0 + $1.sizeBytes },
                content: nil
            ),
            summary: ScanSummary()
        )
    }
}
