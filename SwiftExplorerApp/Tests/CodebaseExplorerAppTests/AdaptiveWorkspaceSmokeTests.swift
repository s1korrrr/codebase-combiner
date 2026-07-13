@testable import CodebaseExplorerApp
import Foundation
import XCTest

@MainActor
final class AdaptiveWorkspaceSmokeTests: XCTestCase {
    func testLayoutMetricsAdaptAcrossCompactRegularAndWidePolicies() {
        let compact = AdaptiveWorkspaceLayout(mode: WorkspaceLayoutPolicy.mode(for: 959))
        let regular = AdaptiveWorkspaceLayout(mode: WorkspaceLayoutPolicy.mode(for: 960))
        let wide = AdaptiveWorkspaceLayout(mode: WorkspaceLayoutPolicy.mode(for: 1320))

        XCTAssertEqual(compact.controlArrangement, .compact)
        XCTAssertEqual(compact.preparationMinimumWidth, 360)
        XCTAssertEqual(regular.controlArrangement, .compact)
        XCTAssertEqual(regular.preparationMinimumWidth, 430)
        XCTAssertLessThanOrEqual(
            220 + regular.preparationMinimumWidth + regular.inspectorMinimumWidth + 10,
            960
        )
        XCTAssertEqual(wide.controlArrangement, .expanded)
        XCTAssertEqual(wide.preparationMinimumWidth, 520)
    }

    func testAccessibilityCopyNamesSelectionPrerequisitesAndKeepsScanSummaryPrivate() {
        XCTAssertEqual(
            WorkspaceAccessibility.selectAllHelp(hasWorkspace: false),
            "Choose a workspace before selecting all files."
        )
        XCTAssertEqual(
            WorkspaceAccessibility.clearSelectionHelp(hasSelection: false),
            "Select at least one file before clearing the selection."
        )
        XCTAssertEqual(
            WorkspaceAccessibility.partialScanSummary(skippedCount: 3),
            "3 files were skipped during the scan. Review counts by reason; file paths stay private."
        )
    }

    func testAdaptiveViewsConstructForEveryPolicyWhileRecoveredPayloadStaysConcealed() async {
        let output = OutputStore(
            drafts: SmokeDraftStore(draft: ClipboardDraft(
                text: "private source",
                format: .markdown,
                fileCount: 1,
                tokenCount: 3,
                byteCount: 14,
                rootPath: nil,
                generatedAt: Date(timeIntervalSince1970: 0)
            )),
            clipboard: SmokeClipboard()
        )
        let controller = AppController(
            preferences: AppPreferences(defaults: UserDefaults(suiteName: #function)!),
            workspace: WorkspaceStore(),
            output: output,
            folderPicker: { nil },
            saveDestinationPicker: { _ in nil }
        )

        await output.loadRecoveredDraft()

        for width in [959.0, 960.0, 1320.0] {
            let layout = AdaptiveWorkspaceLayout(mode: WorkspaceLayoutPolicy.mode(for: width))
            _ = WorkspaceSidebar(controller: controller)
            _ = PreparationWorkspace(controller: controller, layout: layout)
            _ = OutputInspector(controller: controller)
            _ = ContentView(controller: controller)
        }
        _ = RecoveredOutputView(store: output)

        XCTAssertNil(output.visiblePayload)
    }

    func testRecoveredOutputCanBeConcealedAgainAfterReveal() async {
        let output = OutputStore(
            drafts: SmokeDraftStore(draft: ClipboardDraft(
                text: "private source",
                format: .markdown,
                fileCount: 1,
                tokenCount: 3,
                byteCount: 14,
                rootPath: nil,
                generatedAt: Date(timeIntervalSince1970: 0)
            )),
            clipboard: SmokeClipboard()
        )
        await output.loadRecoveredDraft()
        output.revealRecoveredOutput()

        output.hideRecoveredOutput()

        XCTAssertNil(output.visiblePayload)
        XCTAssertFalse(output.isRecoveredContentRevealed)
    }
}

private actor SmokeDraftStore: DraftPersisting {
    private var draft: ClipboardDraft?

    init(draft: ClipboardDraft?) {
        self.draft = draft
    }

    func load() async throws -> ClipboardDraft? { draft }
    func save(_ draft: ClipboardDraft) async throws { self.draft = draft }
    func clear() async throws { draft = nil }
}

@MainActor
private final class SmokeClipboard: ClipboardWriting {
    func write(_: String) throws {}
}
