import Foundation

struct ClipboardDraftStore: DraftPersisting, @unchecked Sendable {
    private let file: ClipboardDraftFile
    private let asyncFile: AsyncClipboardDraftFile

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        let directory = baseDirectory ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Codebase Combiner", isDirectory: true)
        let file = ClipboardDraftFile(
            fileManager: fileManager,
            draftURL: directory.appendingPathComponent("LastReadyClipboard.json")
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

    func load() throws -> ClipboardDraft? {
        guard fileManager.fileExists(atPath: draftURL.path) else { return nil }
        let data = try Data(contentsOf: draftURL)
        return try JSONDecoder().decode(ClipboardDraft.self, from: data)
    }

    func save(_ draft: ClipboardDraft) throws {
        let directory = draftURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(draft)
        try data.write(to: draftURL, options: [.atomic])
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: draftURL.path) else { return }
        try fileManager.removeItem(at: draftURL)
    }
}
