@testable import CodebaseExplorerApp
import Foundation
import XCTest

@MainActor
final class AppTelemetryTests: XCTestCase {
    func testControllerRecordsTheAcceptedScanOutcomeReturnedByTheWorkspace() async throws {
        let telemetry = RecordingTelemetrySink()
        let result = telemetryFixture()
        let controller = makeController(
            loader: TelemetryWorkspaceLoader(result: .success(result)),
            telemetry: telemetry
        )

        let outcome = await controller.scan(rootURL: result.root.url)

        XCTAssertEqual(outcome, .accepted(fileCount: 2, selectedCount: 2, skippedCount: 0))
        XCTAssertEqual(
            telemetry.events.prefix(2),
            [.scanStarted, .scanFinished(.accepted(fileCount: 2, selectedCount: 2, skippedCount: 0))]
        )
    }

    func testControllerRecordsRejectedAndFailedScanOutcomesWithoutCurrentStateCounts() async {
        let rejectedTelemetry = RecordingTelemetrySink()
        let rejectedController = makeController(
            loader: TelemetryWorkspaceLoader(result: .success(telemetryFixture())),
            telemetry: rejectedTelemetry
        )
        rejectedController.preferences.values.maxFileSizeKB = 31

        let rejected = await rejectedController.scan(rootURL: URL(fileURLWithPath: "/rejected"))

        XCTAssertEqual(rejected, .rejectedInvalidMaximumFileSize)
        XCTAssertEqual(rejectedTelemetry.events, [.scanStarted, .scanFinished(.rejectedInvalidMaximumFileSize)])

        let failedTelemetry = RecordingTelemetrySink()
        let failedController = makeController(
            loader: TelemetryWorkspaceLoader(result: .failure(TelemetryError.failed)),
            telemetry: failedTelemetry
        )

        let failed = await failedController.scan(rootURL: URL(fileURLWithPath: "/failed"))

        XCTAssertEqual(failed, .failed)
        XCTAssertEqual(failedTelemetry.events, [.scanStarted, .scanFinished(.failed)])
    }

    func testOutputTelemetryCarriesOnlyTypedMetadataWhileRecoveredContentStaysConcealed() async {
        let telemetry = RecordingTelemetrySink()
        let draft = ClipboardDraft(
            text: "private source",
            format: .plainText,
            fileCount: 1,
            tokenCount: 3,
            byteCount: 14,
            rootPath: "/private/fixture",
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let output = OutputStore(
            drafts: TelemetryDraftStore(draft: draft),
            clipboard: TelemetryClipboard(),
            telemetry: telemetry
        )

        await output.loadRecoveredDraft()
        output.copyRecovered()

        XCTAssertNil(output.visiblePayload)
        XCTAssertEqual(
            telemetry.events,
            [.recoveryLoadSucceeded(available: true), .recoveredCopySucceeded(characterCount: 14)]
        )
        telemetry.events.forEach(assertMetadataOnly)
    }

    private func makeController(
        loader: any WorkspaceLoading,
        telemetry: RecordingTelemetrySink
    ) -> AppController {
        let suiteName = "AppTelemetryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppController(
            preferences: AppPreferences(defaults: defaults),
            workspace: WorkspaceStore(loader: loader),
            output: OutputStore(
                drafts: TelemetryDraftStore(),
                clipboard: TelemetryClipboard(),
                telemetry: telemetry
            ),
            folderPicker: { nil },
            saveDestinationPicker: { _ in nil },
            telemetry: telemetry
        )
    }

    private func assertMetadataOnly(_ event: AppTelemetryEvent) {
        switch event {
        case .scanStarted,
             .scanFinished,
             .recoverySaveFailed,
             .recoveryLoadFailed,
             .currentCopyFailed,
             .recoveredCopyFailed,
             .currentSaveFailed,
             .recoveryClearSucceeded,
             .recoveryClearFailed:
            break
        case let .recoverySaveSucceeded(fileCount, byteCount):
            XCTAssertGreaterThanOrEqual(fileCount, 0)
            XCTAssertGreaterThanOrEqual(byteCount, 0)
        case let .recoveryLoadSucceeded(available):
            XCTAssertTrue(available || !available)
        case let .currentCopySucceeded(characterCount),
             let .recoveredCopySucceeded(characterCount),
             let .currentSaveSucceeded(characterCount):
            XCTAssertGreaterThanOrEqual(characterCount, 0)
        }
    }

    private func telemetryFixture() -> TreeLoadResult {
        let rootURL = URL(fileURLWithPath: "/telemetry-workspace")
        let files = ["a.swift", "b.swift"].map { name in
            FileNode(
                name: name,
                relativePath: name,
                url: rootURL.appendingPathComponent(name),
                isDirectory: false,
                tokenCount: 2,
                sizeBytes: 8,
                content: "let value = true"
            )
        }
        return TreeLoadResult(
            root: FileNode(
                name: "telemetry-workspace",
                relativePath: "telemetry-workspace",
                url: rootURL,
                isDirectory: true,
                children: files,
                tokenCount: 4,
                sizeBytes: 16,
                content: nil
            ),
            summary: ScanSummary()
        )
    }
}

@MainActor
private final class RecordingTelemetrySink: AppTelemetryRecording {
    private(set) var events: [AppTelemetryEvent] = []

    func record(_ event: AppTelemetryEvent) {
        events.append(event)
    }
}

private struct TelemetryWorkspaceLoader: WorkspaceLoading {
    let result: Result<TreeLoadResult, Error>

    func load(rootURL _: URL, preferences _: AppPreferences.Values) async throws -> TreeLoadResult {
        try result.get()
    }
}

private actor TelemetryDraftStore: DraftPersisting {
    private var draft: ClipboardDraft?

    init(draft: ClipboardDraft? = nil) {
        self.draft = draft
    }

    func load() async throws -> ClipboardDraft? { draft }
    func save(_ draft: ClipboardDraft) async throws { self.draft = draft }
    func clear() async throws { draft = nil }
}

@MainActor
private final class TelemetryClipboard: ClipboardWriting {
    func write(_: String) throws {}
}

private enum TelemetryError: Error {
    case failed
}
