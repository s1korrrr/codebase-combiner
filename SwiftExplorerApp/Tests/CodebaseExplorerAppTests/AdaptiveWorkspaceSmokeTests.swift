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
        XCTAssertEqual(regular.inspectorContentWidthAtMinimum, 248)
        XCTAssertEqual(regular.inspectorActionArrangement, .compact)
        XCTAssertLessThanOrEqual(
            220 + regular.preparationMinimumWidth + regular.inspectorMinimumWidth + 10,
            960
        )
        XCTAssertEqual(wide.controlArrangement, .expanded)
        XCTAssertEqual(wide.preparationMinimumWidth, 520)
        XCTAssertEqual(wide.inspectorActionArrangement, .adaptive)
    }

    func testVisiblePanesNeverOverlapPreparationAtSupportedWidths() {
        for width in [WindowContentSizePolicy.minimumWidth, 959.0, 960.0, 1180.0, 1320.0, 1680.0] {
            let layout = AdaptiveWorkspaceLayout(mode: WorkspaceLayoutPolicy.mode(for: width))
            for sidebarPresented in [false, true] {
                for inspectorPresented in [false, true] {
                    let frames = WorkspacePaneGeometry.frames(
                        totalWidth: width,
                        layout: layout,
                        isSidebarPresented: sidebarPresented,
                        isInspectorPresented: inspectorPresented
                    )

                    XCTAssertGreaterThanOrEqual(frames.preparation.width, layout.preparationMinimumWidth)
                    if sidebarPresented {
                        XCTAssertFalse(frames.sidebar.intersects(frames.preparation))
                    }
                    if inspectorPresented {
                        XCTAssertFalse(frames.inspector.intersects(frames.preparation))
                    }
                }
            }
        }
    }

    func testMinimumWindowWidthMakesCompactLayoutReachableWithoutOverlappingPanes() {
        let width = WindowContentSizePolicy.minimumWidth
        let layout = AdaptiveWorkspaceLayout(mode: WorkspaceLayoutPolicy.mode(for: width))
        let frames = WorkspacePaneGeometry.frames(
            totalWidth: width,
            layout: layout,
            isSidebarPresented: true,
            isInspectorPresented: true
        )

        XCTAssertEqual(layout.mode, .compact)
        XCTAssertGreaterThanOrEqual(frames.preparation.width, layout.preparationMinimumWidth)
    }

    func testAccessibilityCopyNamesSelectionPrerequisitesAndKeepsScanSummaryPrivate() {
        XCTAssertEqual(
            WorkspaceAccessibility.selectAllHelp(hasWorkspace: false, hasIncludableFiles: false),
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

    func testSelectAllHelpDistinguishesAnEmptyAcceptedWorkspaceFromNoWorkspace() {
        XCTAssertEqual(
            WorkspaceAccessibility.selectAllHelp(hasWorkspace: true, hasIncludableFiles: false),
            "This workspace has no includable files to select."
        )
        XCTAssertEqual(
            WorkspaceAccessibility.selectAllHelp(hasWorkspace: true, hasIncludableFiles: true),
            "Select all files"
        )
    }

    func testInspectorFormatPrefersCurrentPayloadMetadataThenRecoveredMetadata() {
        let recovered = ClipboardDraft(
            text: "recovered",
            format: .markdown,
            fileCount: 1,
            tokenCount: 2,
            byteCount: 9,
            rootPath: nil,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(
            OutputInspectorPresentation.formatLabel(currentFormat: .plainText, recoveredDraft: recovered),
            "Plain Text"
        )
        XCTAssertEqual(
            OutputInspectorPresentation.formatLabel(currentFormat: nil, recoveredDraft: recovered),
            "Markdown"
        )
        XCTAssertEqual(
            OutputInspectorPresentation.formatLabel(currentFormat: nil, recoveredDraft: nil),
            "Output"
        )
    }

    func testOutputStoreCapturesAndInvalidatesCurrentPayloadFormatMetadata() async {
        let output = OutputStore(
            drafts: SmokeDraftStore(draft: nil),
            clipboard: SmokeClipboard()
        )
        output.format = .plainText
        let file = FileNode(
            name: "App.swift",
            relativePath: "Sources/App.swift",
            url: URL(fileURLWithPath: "/tmp/Sources/App.swift"),
            isDirectory: false,
            tokenCount: 2,
            sizeBytes: 12,
            content: "print(\"ok\")"
        )

        await output.rebuild(files: [file], rootPath: "/tmp")

        XCTAssertEqual(output.currentFormat, .plainText)

        output.invalidateCurrentOutput()

        XCTAssertNil(output.currentFormat)
    }

    func testAdaptiveViewsConstructForEveryPolicyWhileRecoveredPayloadStaysConcealed() async throws {
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
        let controller = try AppController(
            preferences: AppPreferences(defaults: XCTUnwrap(UserDefaults(suiteName: #function))),
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
            _ = OutputInspector(controller: controller, layout: layout)
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

    func testCommittedRecoveredClearSurvivesPresentationDismissalUntilAsyncConfirmationStarts() {
        var interaction = RecoveredClearConfirmationInteraction()

        XCTAssertEqual(interaction.actionForDismissal(), .cancel)

        interaction.commitDestructiveAction()

        XCTAssertEqual(interaction.actionForDismissal(), .preserveConfirmation)

        interaction.finishDestructiveAction()

        XCTAssertEqual(interaction.actionForDismissal(), .cancel)
    }

    func testCommittedDismissalPolicyLeavesStoreConfirmationAvailableForDestructiveAction() async {
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
        output.requestClearRecoveredOutput()
        var interaction = RecoveredClearConfirmationInteraction()
        interaction.commitDestructiveAction()

        if interaction.actionForDismissal() == .cancel {
            output.cancelClearRecoveredOutput()
        }

        XCTAssertTrue(output.isClearConfirmationPresented)

        await output.confirmClearRecoveredOutput()

        XCTAssertNil(output.recoveredDraft)
        XCTAssertFalse(output.isClearConfirmationPresented)
    }

    func testClearConfirmationSourceCommitsBeforeAsyncConfirmAndDefaultsFocusToCancel() throws {
        let source = try sourceFile(named: "RecoveredOutputView.swift")
        let commit = try XCTUnwrap(source.range(of: "clearInteraction.commitDestructiveAction()"))
        let task = try XCTUnwrap(source.range(of: "Task {", range: commit.upperBound ..< source.endIndex))
        let confirm = try XCTUnwrap(source.range(
            of: "await store.confirmClearRecoveredOutput()",
            range: task.upperBound ..< source.endIndex
        ))

        XCTAssertLessThan(commit.lowerBound, task.lowerBound)
        XCTAssertLessThan(task.lowerBound, confirm.lowerBound)
        XCTAssertTrue(source.contains("clearInteraction.actionForDismissal() == .cancel"))
        XCTAssertTrue(source.contains(".keyboardShortcut(.defaultAction)"))
    }

    func testInspectorActionSourcesProvideCompactAndAdaptiveArrangements() throws {
        let current = try sourceFile(named: "OutputInspector.swift")
        let recovered = try sourceFile(named: "RecoveredOutputView.swift")

        XCTAssertTrue(current.contains("layout.inspectorActionArrangement == .compact"))
        XCTAssertTrue(current.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(current.contains("compactCurrentActions"))
        XCTAssertTrue(current.contains("copyButton(fillsWidth: true)"))
        XCTAssertTrue(current.contains("saveButton(fillsWidth: true)"))

        XCTAssertTrue(recovered.contains("actionArrangement == .compact"))
        XCTAssertTrue(recovered.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(recovered.contains("compactRecoveryActions"))
        XCTAssertTrue(recovered.contains("clearButton(fillsWidth: true)"))
    }

    func testInspectorHeaderSourceUsesCapturedCurrentThenRecoveredMetadata() throws {
        let source = try sourceFile(named: "OutputInspector.swift")

        XCTAssertTrue(source.contains("currentFormat: output.currentFormat"))
        XCTAssertTrue(source.contains("recoveredDraft: output.recoveredDraft"))
        XCTAssertFalse(source.contains("Label(output.format"))
    }

    func testWorkspaceDoesNotMutatePaneVisibilityDuringGeometryLayout() throws {
        let source = try sourceFile(named: "ContentView.swift")

        XCTAssertFalse(source.contains("collapseInspectorIfNeeded"))
        XCTAssertFalse(source.contains(".onChange(of: proxy.size.width)"))
    }

    func testInspectorPanePresentationKeepsLayoutSizeConstantWhileCollapsed() {
        let layout = AdaptiveWorkspaceLayout(mode: .regular)

        XCTAssertEqual(InspectorPanePresentation.width(layout: layout), layout.inspectorMinimumWidth)
        XCTAssertEqual(InspectorPanePresentation.offset(isPresented: true, layout: layout), 0)
        XCTAssertEqual(
            InspectorPanePresentation.offset(isPresented: false, layout: layout),
            layout.inspectorMinimumWidth + 1
        )
    }

    func testWorkspaceUsesAStableNonStructuralInspectorHost() throws {
        let source = try sourceFile(named: "ContentView.swift")

        XCTAssertTrue(source.contains("InspectorPaneHost("))
        XCTAssertTrue(source.contains("SidebarPaneHost("))
        XCTAssertTrue(source.contains("ZStack(alignment: .leading)"))
        XCTAssertTrue(source.contains("WorkspacePaneGeometry.frames("))
        XCTAssertTrue(source.contains(".accessibilityHidden(!isPresented)"))
        XCTAssertFalse(source.contains(".inspector(isPresented:"))
        XCTAssertFalse(source.contains("HSplitView"))
        XCTAssertFalse(source.contains("NavigationSplitView"))
    }

    func testSidebarPresentationAlsoAvoidsLayoutSizeMutation() {
        let compact = AdaptiveWorkspaceLayout(mode: .compact)
        let regular = AdaptiveWorkspaceLayout(mode: .regular)
        let wide = AdaptiveWorkspaceLayout(mode: .wide)

        XCTAssertEqual(SidebarPanePresentation.width(layout: compact), 220)
        XCTAssertEqual(SidebarPanePresentation.width(layout: regular), 240)
        XCTAssertEqual(SidebarPanePresentation.width(layout: wide), 280)
        XCTAssertEqual(SidebarPanePresentation.offset(isPresented: true, layout: regular), 0)
        XCTAssertEqual(SidebarPanePresentation.offset(isPresented: false, layout: regular), -241)
    }

    func testSidebarToolbarControlDoesNotMutateToolbarPreferences() throws {
        let source = try sourceFile(named: "ContentView.swift")

        XCTAssertTrue(source.contains("Button(action: controller.toggleSidebar)"))
        XCTAssertTrue(source.contains("Label(\"Toggle Workspace Sidebar\""))
        XCTAssertFalse(source.contains("@State private var isSidebarPresented"))
        XCTAssertFalse(source.contains("systemImage: \"sidebar.leading\""))
        XCTAssertTrue(source.contains("Button(action: controller.toggleInspector)"))
        XCTAssertTrue(source.contains("Label(\"Toggle Output Inspector\""))
        XCTAssertFalse(source.contains("Toggle(isOn: inspectorBinding)"))
    }

    func testRecoveryControlsExposeVisibleRetryPaths() throws {
        let sidebar = try sourceFile(named: "WorkspaceSidebar.swift")
        let inspector = try sourceFile(named: "OutputInspector.swift")
        let recovered = try sourceFile(named: "RecoveredOutputView.swift")

        XCTAssertTrue(sidebar.contains("Button(action: controller.retryFailedScan)"))
        XCTAssertTrue(sidebar.contains("Label(\"Choose Another Folder\""))
        XCTAssertTrue(inspector.contains("Button(action: controller.retryPersistence)"))
        XCTAssertTrue(inspector.contains("Your full current output is still available."))
        XCTAssertTrue(recovered.contains("Label(\"Retry Loading\""))
        XCTAssertTrue(recovered.contains("await store.loadRecoveredDraft()"))
    }

    private func sourceFile(named name: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot
            .appendingPathComponent("Sources/CodebaseExplorerApp/Views")
            .appendingPathComponent(name)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

private actor SmokeDraftStore: DraftPersisting {
    private var draft: ClipboardDraft?

    init(draft: ClipboardDraft?) {
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

@MainActor
private final class SmokeClipboard: ClipboardWriting {
    func write(_: String) throws {}
}
