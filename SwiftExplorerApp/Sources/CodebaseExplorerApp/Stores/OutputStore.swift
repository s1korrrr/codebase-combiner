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

    private let drafts: any DraftPersisting
    private let clipboard: any ClipboardWriting
    private let saver: any PayloadSaving
    private let builder = CombinedOutputBuilder()
    private let tokenEstimator = TokenEstimator()
    private var rebuildRevision = 0

    init(
        drafts: any DraftPersisting,
        clipboard: any ClipboardWriting,
        saver: any PayloadSaving = FilePayloadSaver()
    ) {
        self.drafts = drafts
        self.clipboard = clipboard
        self.saver = saver
    }

    var visiblePayload: String? {
        if let currentPayload { return currentPayload }
        guard isRecoveredContentRevealed else { return nil }
        return recoveredDraft?.text
    }

    func rebuild(files: [FileNode], rootPath: String?) async {
        rebuildRevision &+= 1
        let revision = rebuildRevision

        guard !files.isEmpty else {
            currentPayload = nil
            return
        }

        let text = builder.build(promptPrefix: promptPrefix, files: files, format: format)
        currentPayload = text

        let trimmedPrefix = promptPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptTokens = trimmedPrefix.isEmpty ? 0 : tokenEstimator.estimateTokens(in: trimmedPrefix)
        let draft = ClipboardDraft(
            text: text,
            format: format,
            fileCount: files.count,
            tokenCount: promptTokens + files.reduce(0) { $0 + $1.tokenCount },
            byteCount: files.reduce(0) { $0 + $1.sizeBytes },
            rootPath: rootPath,
            generatedAt: Date()
        )

        do {
            try await drafts.save(draft)
            guard revision == rebuildRevision else { return }
            recoveredDraft = draft
            isRecoveredContentRevealed = false
            canClearRecoveredOutput = true
            status = "Saved recoverable output."
        } catch {
            guard revision == rebuildRevision else { return }
            status = "Could not save the recoverable output. Check storage access and try again: \(error.localizedDescription)"
        }
    }

    func loadRecoveredDraft() async {
        do {
            let draft = try await drafts.load()
            recoveredDraft = draft
            isRecoveredContentRevealed = false
            canClearRecoveredOutput = draft != nil
        } catch {
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

        do {
            try await drafts.clear()
            recoveredDraft = nil
            isRecoveredContentRevealed = false
            canClearRecoveredOutput = false
            isClearConfirmationPresented = false
            status = "Cleared the recovered output."
        } catch {
            status = "Could not clear the recovered output. Check file access and try again: \(error.localizedDescription)"
        }
    }
}
