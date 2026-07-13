@testable import CodebaseExplorerApp
import Foundation
import XCTest

@MainActor
final class OutputStoreTests: XCTestCase {
    func testRecoveredContentStaysHiddenUntilReveal() async {
        let draft = ClipboardDraft.fixture(text: "private source")
        let store = OutputStore(
            drafts: InMemoryDraftStore(draft: draft),
            clipboard: RecordingClipboard()
        )

        await store.loadRecoveredDraft()

        XCTAssertNil(store.visiblePayload)
        XCTAssertEqual(store.recoveredDraft?.fileCount, draft.fileCount)

        store.revealRecoveredOutput()

        XCTAssertEqual(store.visiblePayload, "private source")
    }

    func testClearRequiresConfirmationAndCancelDoesNotMutateDraft() async {
        let drafts = InMemoryDraftStore(draft: .fixture())
        let store = OutputStore(drafts: drafts, clipboard: RecordingClipboard())
        await store.loadRecoveredDraft()

        store.requestClearRecoveredOutput()

        XCTAssertTrue(store.isClearConfirmationPresented)

        store.cancelClearRecoveredOutput()

        let clearCount = await drafts.clearCount
        XCTAssertFalse(store.isClearConfirmationPresented)
        XCTAssertNotNil(store.recoveredDraft)
        XCTAssertEqual(clearCount, 0)
    }

    func testConfirmClearRemovesOnlyTheRecoveredDraftAfterRequest() async {
        let drafts = InMemoryDraftStore(draft: .fixture())
        let store = OutputStore(drafts: drafts, clipboard: RecordingClipboard())
        await store.loadRecoveredDraft()
        store.revealRecoveredOutput()
        store.requestClearRecoveredOutput()

        await store.confirmClearRecoveredOutput()

        let persistedDraft = await drafts.currentDraft
        let clearCount = await drafts.clearCount
        XCTAssertNil(persistedDraft)
        XCTAssertEqual(clearCount, 1)
        XCTAssertNil(store.recoveredDraft)
        XCTAssertNil(store.visiblePayload)
        XCTAssertFalse(store.isRecoveredContentRevealed)
        XCTAssertFalse(store.isClearConfirmationPresented)
    }

    func testRebuildPublishesCurrentPayloadAndPersistsCompleteMetadata() async throws {
        let drafts = InMemoryDraftStore()
        let store = OutputStore(drafts: drafts, clipboard: RecordingClipboard())
        let file = FileNode.fixture(
            relativePath: "Sources/App.swift",
            tokenCount: 3,
            sizeBytes: 12,
            content: "print(\"ok\")"
        )
        store.promptPrefix = "Review carefully."

        await store.rebuild(files: [file], rootPath: "/tmp/project")

        let persistedDraft = await drafts.currentDraft
        let savedDraft = try XCTUnwrap(persistedDraft)
        XCTAssertEqual(store.currentPayload, savedDraft.text)
        XCTAssertEqual(store.visiblePayload, savedDraft.text)
        XCTAssertTrue(savedDraft.text.contains("Review carefully."))
        XCTAssertEqual(savedDraft.fileCount, 1)
        XCTAssertEqual(savedDraft.tokenCount, 7)
        XCTAssertEqual(savedDraft.byteCount, 12)
        XCTAssertEqual(savedDraft.rootPath, "/tmp/project")
    }

    func testCopyRecoveredDoesNotRevealItsContent() async {
        let clipboard = RecordingClipboard()
        let store = OutputStore(
            drafts: InMemoryDraftStore(draft: .fixture(text: "private source")),
            clipboard: clipboard
        )
        await store.loadRecoveredDraft()

        store.copyRecovered()

        XCTAssertEqual(clipboard.writtenTexts, ["private source"])
        XCTAssertFalse(store.isRecoveredContentRevealed)
        XCTAssertNil(store.visiblePayload)
    }

    func testCopyCurrentWritesTheFullCurrentPayload() async throws {
        let clipboard = RecordingClipboard()
        let store = OutputStore(drafts: InMemoryDraftStore(), clipboard: clipboard)
        let file = FileNode.fixture(
            relativePath: "large.txt",
            tokenCount: 2,
            sizeBytes: 10,
            content: "full value"
        )
        await store.rebuild(files: [file], rootPath: nil)

        store.copyCurrent()

        XCTAssertEqual(clipboard.writtenTexts, try [XCTUnwrap(store.currentPayload)])
    }

    func testCopyFailureIsActionableWithoutExposingPayloadInStatus() async {
        let clipboard = RecordingClipboard(error: BoundaryError.denied)
        let store = OutputStore(
            drafts: InMemoryDraftStore(draft: .fixture(text: "top secret source")),
            clipboard: clipboard
        )
        await store.loadRecoveredDraft()

        store.copyRecovered()

        XCTAssertTrue(store.status?.contains("Could not copy the recovered output") == true)
        XCTAssertTrue(store.status?.contains("try again") == true)
        XCTAssertTrue(store.status?.contains("Clipboard access denied") == true)
        XCTAssertFalse(store.status?.contains("top secret source") == true)
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testSaveCurrentWritesTheFullPayloadThroughInjectedBoundary() async throws {
        let saver = RecordingPayloadSaver()
        let store = OutputStore(
            drafts: InMemoryDraftStore(),
            clipboard: RecordingClipboard(),
            saver: saver
        )
        let destination = URL(fileURLWithPath: "/tmp/CombinedOutput.md")
        await store.rebuild(
            files: [.fixture(relativePath: "notes.txt", tokenCount: 1, sizeBytes: 5, content: "hello")],
            rootPath: nil
        )

        await store.saveCurrent(to: destination)

        let persistedWrite = await saver.lastWrite
        let write = try XCTUnwrap(persistedWrite)
        XCTAssertEqual(write.text, store.currentPayload)
        XCTAssertEqual(write.url, destination)
        XCTAssertTrue(store.status?.contains("CombinedOutput.md") == true)
    }

    func testSaveFailureIsActionableWithoutExposingPayloadInStatus() async {
        let saver = RecordingPayloadSaver(error: .diskFull)
        let store = OutputStore(
            drafts: InMemoryDraftStore(),
            clipboard: RecordingClipboard(),
            saver: saver
        )
        await store.rebuild(
            files: [.fixture(relativePath: "secret.txt", tokenCount: 2, sizeBytes: 10, content: "private source")],
            rootPath: nil
        )

        await store.saveCurrent(to: URL(fileURLWithPath: "/tmp/CombinedOutput.txt"))

        let persistedWrite = await saver.lastWrite
        XCTAssertTrue(store.status?.contains("Could not save the current output") == true)
        XCTAssertTrue(store.status?.contains("try again") == true)
        XCTAssertTrue(store.status?.contains("Destination is full") == true)
        XCTAssertFalse(store.status?.contains("private source") == true)
        XCTAssertNil(persistedWrite)
    }

    func testDraftPersistenceFailureKeepsCurrentOutputAndReportsRetry() async {
        let drafts = InMemoryDraftStore(saveError: .persistenceDenied)
        let store = OutputStore(drafts: drafts, clipboard: RecordingClipboard())
        await store.rebuild(
            files: [.fixture(relativePath: "secret.txt", tokenCount: 2, sizeBytes: 10, content: "private source")],
            rootPath: nil
        )

        XCTAssertNotNil(store.currentPayload)
        XCTAssertNil(store.recoveredDraft)
        XCTAssertTrue(store.status?.contains("Could not save the recoverable output") == true)
        XCTAssertTrue(store.status?.contains("try again") == true)
        XCTAssertTrue(store.status?.contains("Draft storage denied") == true)
        XCTAssertFalse(store.status?.contains("private source") == true)
    }

    func testConfirmWithoutARequestedConfirmationDoesNotClear() async {
        let drafts = InMemoryDraftStore(draft: .fixture())
        let store = OutputStore(drafts: drafts, clipboard: RecordingClipboard())
        await store.loadRecoveredDraft()

        await store.confirmClearRecoveredOutput()

        let clearCount = await drafts.clearCount
        XCTAssertEqual(clearCount, 0)
        XCTAssertNotNil(store.recoveredDraft)
    }

    func testClearFailureKeepsDraftAndConfirmationAvailableForRetry() async {
        let drafts = InMemoryDraftStore(draft: .fixture(), clearError: .persistenceDenied)
        let store = OutputStore(drafts: drafts, clipboard: RecordingClipboard())
        await store.loadRecoveredDraft()
        store.revealRecoveredOutput()
        store.requestClearRecoveredOutput()

        await store.confirmClearRecoveredOutput()

        let clearCount = await drafts.clearCount
        XCTAssertEqual(clearCount, 1)
        XCTAssertNotNil(store.recoveredDraft)
        XCTAssertTrue(store.isRecoveredContentRevealed)
        XCTAssertTrue(store.isClearConfirmationPresented)
        XCTAssertTrue(store.status?.contains("Could not clear the recovered output") == true)
        XCTAssertTrue(store.status?.contains("try again") == true)
    }

    func testLoadFailureIsActionableAndDoesNotRevealContent() async {
        let store = OutputStore(
            drafts: InMemoryDraftStore(loadError: .persistenceDenied),
            clipboard: RecordingClipboard()
        )

        await store.loadRecoveredDraft()

        XCTAssertNil(store.recoveredDraft)
        XCTAssertNil(store.visiblePayload)
        XCTAssertFalse(store.isRecoveredContentRevealed)
        XCTAssertTrue(store.status?.contains("Could not load the recovered output") == true)
        XCTAssertTrue(store.status?.contains("clear it") == true)
    }

    func testUnreadableRecoveredDraftCanStillBeClearedAfterConfirmation() async {
        let drafts = InMemoryDraftStore(loadError: .persistenceDenied)
        let store = OutputStore(drafts: drafts, clipboard: RecordingClipboard())
        await store.loadRecoveredDraft()

        store.requestClearRecoveredOutput()

        XCTAssertTrue(store.isClearConfirmationPresented)
        await store.confirmClearRecoveredOutput()

        let clearCount = await drafts.clearCount
        XCTAssertEqual(clearCount, 1)
        XCTAssertFalse(store.isClearConfirmationPresented)
        XCTAssertFalse(store.canClearRecoveredOutput)
    }

    func testFailedReloadCannotLeaveAStaleRecoveredPayloadVisible() async {
        let drafts = InMemoryDraftStore(draft: .fixture(text: "stale private source"))
        let store = OutputStore(drafts: drafts, clipboard: RecordingClipboard())
        await store.loadRecoveredDraft()
        store.revealRecoveredOutput()
        await drafts.failLoads(with: .persistenceDenied)

        await store.loadRecoveredDraft()

        XCTAssertNil(store.recoveredDraft)
        XCTAssertNil(store.visiblePayload)
        XCTAssertFalse(store.isRecoveredContentRevealed)
        XCTAssertFalse(store.status?.contains("stale private source") == true)
    }

    func testOlderPersistenceCompletionCannotReplaceNewerOutputState() async {
        let drafts = ControlledDraftStore()
        let store = OutputStore(drafts: drafts, clipboard: RecordingClipboard())
        let file = FileNode.fixture(
            relativePath: "notes.txt",
            tokenCount: 1,
            sizeBytes: 5,
            content: "hello"
        )

        store.promptPrefix = "first request"
        let firstRebuild = Task { await store.rebuild(files: [file], rootPath: nil) }
        await drafts.waitUntilSaveRequested(containing: "first request")

        store.promptPrefix = "second request"
        let secondRebuild = Task { await store.rebuild(files: [file], rootPath: nil) }
        await drafts.waitUntilSaveRequested(containing: "second request")

        await drafts.completeSave(containing: "second request")
        await secondRebuild.value
        await drafts.completeSave(containing: "first request")
        await firstRebuild.value

        XCTAssertTrue(store.currentPayload?.contains("second request") == true)
        XCTAssertTrue(store.recoveredDraft?.text.contains("second request") == true)
        XCTAssertFalse(store.recoveredDraft?.text.contains("first request") == true)
    }
}

private actor InMemoryDraftStore: DraftPersisting {
    private var draft: ClipboardDraft?
    private(set) var clearCount = 0
    private var loadError: BoundaryError?
    private let saveError: BoundaryError?
    private let clearError: BoundaryError?

    init(
        draft: ClipboardDraft? = nil,
        loadError: BoundaryError? = nil,
        saveError: BoundaryError? = nil,
        clearError: BoundaryError? = nil
    ) {
        self.draft = draft
        self.loadError = loadError
        self.saveError = saveError
        self.clearError = clearError
    }

    func load() async throws -> ClipboardDraft? {
        if let loadError { throw loadError }
        return draft
    }

    func save(_ draft: ClipboardDraft) async throws {
        if let saveError { throw saveError }
        self.draft = draft
    }

    func clear() async throws {
        clearCount += 1
        if let clearError { throw clearError }
        draft = nil
    }

    var currentDraft: ClipboardDraft? {
        draft
    }

    func failLoads(with error: BoundaryError) {
        loadError = error
    }
}

@MainActor
private final class RecordingClipboard: ClipboardWriting {
    private(set) var writtenTexts: [String] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func write(_ text: String) throws {
        if let error { throw error }
        writtenTexts.append(text)
    }
}

private enum BoundaryError: LocalizedError {
    case denied
    case diskFull
    case persistenceDenied

    var errorDescription: String? {
        switch self {
        case .denied:
            "Clipboard access denied"
        case .diskFull:
            "Destination is full"
        case .persistenceDenied:
            "Draft storage denied"
        }
    }
}

private actor RecordingPayloadSaver: PayloadSaving {
    private(set) var lastWrite: (text: String, url: URL)?
    private let error: BoundaryError?

    init(error: BoundaryError? = nil) {
        self.error = error
    }

    func save(_ text: String, to url: URL) async throws {
        if let error { throw error }
        lastWrite = (text, url)
    }
}

private actor ControlledDraftStore: DraftPersisting {
    private var draft: ClipboardDraft?
    private var requestedDrafts: [String: ClipboardDraft] = [:]
    private var saveContinuations: [String: CheckedContinuation<Void, Never>] = [:]

    func load() async throws -> ClipboardDraft? {
        draft
    }

    func save(_ draft: ClipboardDraft) async throws {
        requestedDrafts[draft.text] = draft
        await withCheckedContinuation { continuation in
            saveContinuations[draft.text] = continuation
        }
        self.draft = draft
    }

    func clear() async throws {
        draft = nil
    }

    func waitUntilSaveRequested(containing fragment: String) async {
        while requestedDrafts.keys.contains(where: { $0.contains(fragment) }) == false {
            await Task.yield()
        }
    }

    func completeSave(containing fragment: String) {
        guard let text = saveContinuations.keys.first(where: { $0.contains(fragment) }) else {
            return
        }
        saveContinuations.removeValue(forKey: text)?.resume()
    }
}

private extension ClipboardDraft {
    static func fixture(text: String = "saved payload") -> ClipboardDraft {
        ClipboardDraft(
            text: text,
            format: .markdown,
            fileCount: 2,
            tokenCount: 12,
            byteCount: 128,
            rootPath: "/tmp/project",
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private extension FileNode {
    static func fixture(
        relativePath: String,
        tokenCount: Int,
        sizeBytes: Int,
        content: String
    ) -> FileNode {
        FileNode(
            name: URL(fileURLWithPath: relativePath).lastPathComponent,
            relativePath: relativePath,
            url: URL(fileURLWithPath: "/tmp/\(relativePath)"),
            isDirectory: false,
            tokenCount: tokenCount,
            sizeBytes: sizeBytes,
            content: content
        )
    }
}
