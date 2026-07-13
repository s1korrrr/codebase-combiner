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
