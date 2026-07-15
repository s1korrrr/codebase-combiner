@testable import CodebaseExplorerApp
import Foundation
import XCTest

final class ClipboardDraftStoreTests: XCTestCase {
    func testLoadRejectsDraftLargerThanRecoveryLimitBeforeDecoding() throws {
        try withTemporaryDirectory { root in
            let draftURL = root.appendingPathComponent("LastReadyClipboard.json")
            try Data(repeating: 0x61, count: 33).write(to: draftURL)
            let store = ClipboardDraftStore(baseDirectory: root, maximumDraftBytes: 32)

            XCTAssertThrowsError(try store.load()) { error in
                XCTAssertTrue(error.localizedDescription.contains("recovery size limit"))
            }
        }
    }

    func testSaveRejectsDraftLargerThanRecoveryLimit() throws {
        try withTemporaryDirectory { root in
            let store = ClipboardDraftStore(baseDirectory: root, maximumDraftBytes: 32)
            let draft = ClipboardDraft(
                text: String(repeating: "x", count: 128),
                format: .plainText,
                fileCount: 1,
                tokenCount: 32,
                byteCount: 128,
                rootPath: nil,
                generatedAt: Date(timeIntervalSince1970: 1_800_000_002)
            )

            XCTAssertThrowsError(try store.save(draft)) { error in
                XCTAssertTrue(error.localizedDescription.contains("recovery size limit"))
            }
        }
    }

    func testSaveLoadAndClearDraft() throws {
        try withTemporaryDirectory { root in
            let store = ClipboardDraftStore(baseDirectory: root)
            let draft = ClipboardDraft(
                text: "ready payload",
                format: .markdown,
                fileCount: 2,
                tokenCount: 12,
                byteCount: 128,
                rootPath: "/tmp/project",
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )

            try store.save(draft)
            XCTAssertEqual(try store.load(), draft)

            try store.clear()
            XCTAssertNil(try store.load())
        }
    }

    @MainActor
    func testAsyncPersistenceBoundaryPreservesTheExistingJSONSchema() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let persistence: any DraftPersisting = ClipboardDraftStore(baseDirectory: root)
        let draft = ClipboardDraft(
            text: "ready payload",
            format: .plainText,
            fileCount: 3,
            tokenCount: 21,
            byteCount: 256,
            rootPath: "/tmp/project",
            generatedAt: Date(timeIntervalSince1970: 1_800_000_001)
        )

        try await persistence.save(draft)
        let data = try Data(contentsOf: root.appendingPathComponent("LastReadyClipboard.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            Set(json.keys),
            Set(["text", "format", "fileCount", "tokenCount", "byteCount", "rootPath", "generatedAt"])
        )
        let loadedDraft = try await persistence.load()
        XCTAssertEqual(loadedDraft, draft)

        try await persistence.clear()
        let clearedDraft = try await persistence.load()
        XCTAssertNil(clearedDraft)
    }
}

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let resolvedRoot = root.resolvingSymlinksInPath()
    defer {
        try? FileManager.default.removeItem(at: resolvedRoot)
    }
    try body(resolvedRoot)
}
