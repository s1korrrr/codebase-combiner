import Combine
import Foundation

@MainActor
final class OutputStore: ObservableObject {
    @Published var promptPrefix = ""
    @Published var format: CombinedOutputFormat = .markdown
    @Published private(set) var currentPayload: String?
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

    func rebuild(files: [FileNode], rootPath: String?) async {
        let buildRevision = beginBuildOperation()
        isClearConfirmationPresented = false

        guard !files.isEmpty else {
            currentPayload = nil
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

        do {
            try await persistence.save(output.draft)
            guard isCurrentRecovery(recoveryRevision) else { return }
            recoveredDraft = output.draft
            isRecoveredContentRevealed = false
            canClearRecoveredOutput = true
            status = "Saved recoverable output."
        } catch {
            guard isCurrentRecovery(recoveryRevision) else { return }
            status = "Could not save the recoverable output. Check storage access and try again: \(error.localizedDescription)"
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
        } catch {
            guard isCurrentRecovery(recoveryRevision) else { return }
            recoveredDraft = nil
            isRecoveredContentRevealed = false
            canClearRecoveredOutput = true
            isClearConfirmationPresented = false
            status = "Could not load the recovered output. Try again or clear it: \(error.localizedDescription)"
        }
    }

    func revealRecoveredOutput() {
        guard recoveredDraft != nil else { return }
        isRecoveredContentRevealed = true
    }

    func copyCurrent() {
        guard let currentPayload else {
            status = "There is no current output to copy. Select at least one file and try again."
            return
        }

        do {
            try clipboard.write(currentPayload)
            status = "Copied the current output."
        } catch {
            status = "Could not copy the current output. Check clipboard access and try again: \(error.localizedDescription)"
        }
    }

    func copyRecovered() {
        guard let text = recoveredDraft?.text else {
            status = "There is no recovered output to copy."
            return
        }

        do {
            try clipboard.write(text)
            status = "Copied the recovered output."
        } catch {
            status = "Could not copy the recovered output. Check clipboard access and try again: \(error.localizedDescription)"
        }
    }

    func saveCurrent(to url: URL) async {
        guard let currentPayload else {
            status = "There is no current output to save. Select at least one file and try again."
            return
        }

        do {
            try await saver.save(currentPayload, to: url)
            status = "Saved the current output to \(url.lastPathComponent)."
        } catch {
            status = "Could not save the current output. Check the destination and try again: \(error.localizedDescription)"
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
        } catch {
            guard isCurrentRecovery(recoveryRevision) else { return }
            status = "Could not clear the recovered output. Check file access and try again: \(error.localizedDescription)"
        }
    }

    private func beginBuildOperation() -> Int {
        buildGeneration &+= 1
        return buildGeneration
    }

    private func beginRecoveryOperation(cancelPendingBuild: Bool) -> Int {
        if cancelPendingBuild {
            buildGeneration &+= 1
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
