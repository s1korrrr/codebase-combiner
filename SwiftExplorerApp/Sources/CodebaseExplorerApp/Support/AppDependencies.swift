import AppKit
import Foundation

protocol DraftPersisting: Sendable {
    func load() async throws -> ClipboardDraft?
    func save(_ draft: ClipboardDraft) async throws
    func clear() async throws
}

protocol ClipboardWriting: AnyObject {
    @MainActor func write(_ text: String) throws
}

protocol PayloadSaving: Sendable {
    func save(_ text: String, to url: URL) async throws
}

struct OutputBuildInput: Sendable {
    let promptPrefix: String
    let files: [FileNode]
    let format: CombinedOutputFormat
    let rootPath: String?
}

struct BuiltOutput: Sendable {
    let payload: String
    let draft: ClipboardDraft
}

protocol OutputBuilding: Sendable {
    func build(_ input: OutputBuildInput) async -> BuiltOutput
}

struct BackgroundOutputBuilder: OutputBuilding {
    private let onBuild: @Sendable () -> Void

    init(onBuild: @escaping @Sendable () -> Void = {}) {
        self.onBuild = onBuild
    }

    func build(_ input: OutputBuildInput) async -> BuiltOutput {
        let onBuild = onBuild
        return await Task.detached(priority: .userInitiated) {
            onBuild()
            let payload = CombinedOutputBuilder().build(
                promptPrefix: input.promptPrefix,
                files: input.files,
                format: input.format
            )
            let trimmedPrefix = input.promptPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            let promptTokens = trimmedPrefix.isEmpty
                ? 0
                : TokenEstimator().estimateTokens(in: trimmedPrefix)
            let draft = ClipboardDraft(
                text: payload,
                format: input.format,
                fileCount: input.files.count,
                tokenCount: promptTokens + input.files.reduce(0) { $0 + $1.tokenCount },
                byteCount: input.files.reduce(0) { $0 + $1.sizeBytes },
                rootPath: input.rootPath,
                generatedAt: Date()
            )
            return BuiltOutput(payload: payload, draft: draft)
        }.value
    }
}

actor OrderedDraftPersistence {
    private let drafts: any DraftPersisting
    private var isExecuting = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(drafts: any DraftPersisting) {
        self.drafts = drafts
    }

    func load() async throws -> ClipboardDraft? {
        await acquire()
        defer { release() }
        return try await drafts.load()
    }

    func save(_ draft: ClipboardDraft) async throws {
        await acquire()
        defer { release() }
        try await drafts.save(draft)
    }

    func clear() async throws {
        await acquire()
        defer { release() }
        try await drafts.clear()
    }

    private func acquire() async {
        guard isExecuting else {
            isExecuting = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isExecuting = false
            return
        }
        waiters.removeFirst().resume()
    }
}

struct FilePayloadSaver: PayloadSaving {
    func save(_ text: String, to url: URL) async throws {
        try await Task.detached(priority: .utility) {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }.value
    }
}

@MainActor
final class SystemClipboardWriter: ClipboardWriting {
    func write(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw ClipboardWriteError.rejected
        }
    }
}

private enum ClipboardWriteError: LocalizedError {
    case rejected

    var errorDescription: String? {
        "The system clipboard rejected the output."
    }
}
