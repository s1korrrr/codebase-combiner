import Combine
import Foundation

@MainActor
final class OutputStore: ObservableObject {
    @Published var promptPrefix = ""
    @Published var format: CombinedOutputFormat = .markdown
    @Published private(set) var currentPayload: String?
    @Published private(set) var currentFormat: CombinedOutputFormat?
    @Published private(set) var isBuilding = false
    @Published private(set) var recoveredDraft: ClipboardDraft?
    @Published private(set) var isRecoveredContentRevealed = false
    @Published private(set) var canClearRecoveredOutput = false
    @Published private(set) var isClearConfirmationPresented = false
    @Published private(set) var status: String?

    private let persistence: OrderedDraftPersistence
    private let clipboard: any ClipboardWriting
    private let saver: any PayloadSaving
    private let builder: any OutputBuilding
    private var buildGeneration = 0
    private var recoveryGeneration = 0

    init(
        drafts: any DraftPersisting,
        clipboard: any ClipboardWriting,
        saver: any PayloadSaving = FilePayloadSaver(),
        builder: any OutputBuilding = BackgroundOutputBuilder()
    ) {
        persistence = OrderedDraftPersistence(drafts: drafts)
        self.clipboard = clipboard
        self.saver = saver
        self.builder = builder
    }

    var visiblePayload: String? {
        if let currentPayload { return currentPayload }
        guard isRecoveredContentRevealed else { return nil }
        return recoveredDraft?.text
    }

    var hasFreshCurrentPayload: Bool {
        currentPayload != nil && !isBuilding
    }

    func invalidateCurrentOutput() {
        buildGeneration &+= 1
        isBuilding = true
        currentPayload = nil
        currentFormat = nil
    }

    func rebuild(files: [FileNode], rootPath: String?) async {
        let buildRevision = beginBuildOperation()
        isClearConfirmationPresented = false
        isBuilding = true
        currentPayload = nil
        currentFormat = nil

        guard !files.isEmpty else {
            isBuilding = false
            return
        }

        let input = OutputBuildInput(
            promptPrefix: promptPrefix,
            files: files,
            format: format,
            rootPath: rootPath
        )
        let output = await builder.build(input)
        guard isCurrentBuild(buildRevision) else { return }
        let recoveryRevision = beginRecoveryOperation(cancelPendingBuild: false)
        currentPayload = output.payload
        currentFormat = output.draft.format
        isBuilding = false

        do {
            try await persistence.save(output.draft)
            guard isCurrentRecovery(recoveryRevision) else { return }
            recoveredDraft = output.draft
            isRecoveredContentRevealed = false
            canClearRecoveredOutput = true
            status = "Saved recoverable output."
            AppLog.persistence.info(
                "Recovery save succeeded files=\(output.draft.fileCount, privacy: .public) bytes=\(output.draft.byteCount, privacy: .public)"
            )
        } catch {
            guard isCurrentRecovery(recoveryRevision) else { return }
            status = "Could not save the recoverable output. Check storage access and try again: \(error.localizedDescription)"
            AppLog.persistence.error("Recovery save failed")
        }
    }

    func loadRecoveredDraft() async {
        let recoveryRevision = beginRecoveryOperation(cancelPendingBuild: true)
        isClearConfirmationPresented = false
        do {
            let draft = try await persistence.load()
            guard isCurrentRecovery(recoveryRevision) else { return }
            recoveredDraft = draft
            isRecoveredContentRevealed = false
            canClearRecoveredOutput = draft != nil
            status = nil
            AppLog.persistence.info("Recovery load succeeded available=\(draft != nil, privacy: .public)")
        } catch {
            guard isCurrentRecovery(recoveryRevision) else { return }
            recoveredDraft = nil
            isRecoveredContentRevealed = false
            canClearRecoveredOutput = true
            isClearConfirmationPresented = false
            status = "Could not load the recovered output. Try again or clear it: \(error.localizedDescription)"
            AppLog.persistence.error("Recovery load failed")
        }
    }

    func revealRecoveredOutput() {
        guard recoveredDraft != nil else { return }
        isRecoveredContentRevealed = true
    }

    func hideRecoveredOutput() {
        isRecoveredContentRevealed = false
    }

    func copyCurrent() {
        guard let currentPayload else {
            status = "There is no current output to copy. Select at least one file and try again."
            return
        }

        do {
            let characterCount = currentPayload.count
            try clipboard.write(currentPayload)
            status = "Copied the current output."
            AppLog.export.info("Current output copy succeeded characters=\(characterCount, privacy: .public)")
        } catch {
            status = "Could not copy the current output. Check clipboard access and try again: \(error.localizedDescription)"
            AppLog.export.error("Current output copy failed")
        }
    }

    func copyRecovered() {
        guard let text = recoveredDraft?.text else {
            status = "There is no recovered output to copy."
            return
        }

        do {
            let characterCount = text.count
            try clipboard.write(text)
            status = "Copied the recovered output."
            AppLog.export.info("Recovered output copy succeeded characters=\(characterCount, privacy: .public)")
        } catch {
            status = "Could not copy the recovered output. Check clipboard access and try again: \(error.localizedDescription)"
            AppLog.export.error("Recovered output copy failed")
        }
    }

    func saveCurrent(to url: URL) async {
        guard let currentPayload else {
            status = "There is no current output to save. Select at least one file and try again."
            return
        }

        do {
            let characterCount = currentPayload.count
            try await saver.save(currentPayload, to: url)
            status = "Saved the current output to \(url.lastPathComponent)."
            AppLog.export.info("Current output save succeeded characters=\(characterCount, privacy: .public)")
        } catch {
            status = "Could not save the current output. Check the destination and try again: \(error.localizedDescription)"
            AppLog.export.error("Current output save failed")
        }
    }

    func requestClearRecoveredOutput() {
        guard canClearRecoveredOutput else { return }
        isClearConfirmationPresented = true
    }

    func cancelClearRecoveredOutput() {
        isClearConfirmationPresented = false
    }

    func confirmClearRecoveredOutput() async {
        guard isClearConfirmationPresented else { return }
        let recoveryRevision = beginRecoveryOperation(cancelPendingBuild: true)

        do {
            try await persistence.clear()
            guard isCurrentRecovery(recoveryRevision) else { return }
            recoveredDraft = nil
            isRecoveredContentRevealed = false
            canClearRecoveredOutput = false
            isClearConfirmationPresented = false
            status = "Cleared the recovered output."
            AppLog.persistence.info("Recovery clear succeeded")
        } catch {
            guard isCurrentRecovery(recoveryRevision) else { return }
            status = "Could not clear the recovered output. Check file access and try again: \(error.localizedDescription)"
            AppLog.persistence.error("Recovery clear failed")
        }
    }

    private func beginBuildOperation() -> Int {
        buildGeneration &+= 1
        return buildGeneration
    }

    private func beginRecoveryOperation(cancelPendingBuild: Bool) -> Int {
        if cancelPendingBuild {
            buildGeneration &+= 1
            if isBuilding {
                isBuilding = false
                currentPayload = nil
            }
        }
        recoveryGeneration &+= 1
        return recoveryGeneration
    }

    private func isCurrentBuild(_ generation: Int) -> Bool {
        generation == buildGeneration
    }

    private func isCurrentRecovery(_ generation: Int) -> Bool {
        generation == recoveryGeneration
    }
}
