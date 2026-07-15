import Foundation

struct ClipboardDraftStore: DraftPersisting, @unchecked Sendable {
    static let standardMaximumDraftBytes = 72 * 1024 * 1024
    private let file: ClipboardDraftFile
    private let asyncFile: AsyncClipboardDraftFile

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        maximumDraftBytes: Int = Self.standardMaximumDraftBytes
    ) {
        let directory = baseDirectory ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Codebase Combiner", isDirectory: true)
        let file = ClipboardDraftFile(
            fileManager: fileManager,
            draftURL: directory.appendingPathComponent("LastReadyClipboard.json"),
            maximumDraftBytes: maximumDraftBytes
        )
        self.file = file
        asyncFile = AsyncClipboardDraftFile(file: file)
    }

    func load() throws -> ClipboardDraft? {
        try file.load()
    }

    func load() async throws -> ClipboardDraft? {
        try await asyncFile.load()
    }

    func save(_ draft: ClipboardDraft) throws {
        try file.save(draft)
    }

    func save(_ draft: ClipboardDraft) async throws {
        try await asyncFile.save(draft)
    }

    func clear() throws {
        try file.clear()
    }

    func clear() async throws {
        try await asyncFile.clear()
    }
}

private actor AsyncClipboardDraftFile {
    private let file: ClipboardDraftFile

    init(file: ClipboardDraftFile) {
        self.file = file
    }

    func load() throws -> ClipboardDraft? {
        try file.load()
    }

    func save(_ draft: ClipboardDraft) throws {
        try file.save(draft)
    }

    func clear() throws {
        try file.clear()
    }
}

private struct ClipboardDraftFile: @unchecked Sendable {
    let fileManager: FileManager
    let draftURL: URL
    let maximumDraftBytes: Int

    func load() throws -> ClipboardDraft? {
        guard fileManager.fileExists(atPath: draftURL.path) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: draftURL.path)
        if let size = attributes[.size] as? NSNumber, size.intValue > maximumDraftBytes {
            throw ClipboardDraftPersistenceError.exceedsRecoverySizeLimit(maximumDraftBytes)
        }
        let data = try Data(contentsOf: draftURL)
        return try JSONDecoder().decode(ClipboardDraft.self, from: data)
    }

    func save(_ draft: ClipboardDraft) throws {
        let directory = draftURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(draft)
        guard data.count <= maximumDraftBytes else {
            throw ClipboardDraftPersistenceError.exceedsRecoverySizeLimit(maximumDraftBytes)
        }
        try data.write(to: draftURL, options: [.atomic])
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: draftURL.path) else { return }
        try fileManager.removeItem(at: draftURL)
    }
}

private enum ClipboardDraftPersistenceError: LocalizedError {
    case exceedsRecoverySizeLimit(Int)

    var errorDescription: String? {
        switch self {
        case let .exceedsRecoverySizeLimit(bytes):
            "Draft exceeds the recovery size limit of \(bytes) bytes."
        }
    }
}
