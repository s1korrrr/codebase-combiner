import AppKit
import Foundation

@MainActor
struct AppDependencies {
    static let e2eDataDirectoryEnvironmentKey = "CODEBASE_COMBINER_E2E_DATA_DIR"
    static let e2eWindowSizeEnvironmentKey = "CODEBASE_COMBINER_E2E_WINDOW_SIZE"
    static let e2eDefaultsSuiteName = "com.s1korrrr.codebasecombiner.e2e"

    let defaults: UserDefaults
    let draftBaseDirectory: URL?
    let initialWindowSize: CGSize?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let path = environment[Self.e2eDataDirectoryEnvironmentKey], !path.isEmpty {
            guard let defaults = UserDefaults(suiteName: Self.e2eDefaultsSuiteName) else {
                preconditionFailure("Unable to create the isolated E2E defaults suite.")
            }
            self.defaults = defaults
            draftBaseDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            defaults = .standard
            draftBaseDirectory = nil
        }
        initialWindowSize = Self.parseWindowSize(environment[Self.e2eWindowSizeEnvironmentKey])
    }

    private static func parseWindowSize(_ value: String?) -> CGSize? {
        guard let value else { return nil }
        let dimensions = value.lowercased().split(separator: "x", omittingEmptySubsequences: false)
        guard dimensions.count == 2,
              let width = Double(dimensions[0]), width > 0,
              let height = Double(dimensions[1]), height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }
}

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
