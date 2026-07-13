@testable import CodebaseExplorerApp
import Foundation
import XCTest

final class TreeLoaderTests: XCTestCase {
    func testLoadReportsWhyFilesWereSkipped() throws {
        try withTemporaryDirectory { root in
            try writeData(at: root.appendingPathComponent("binary.bin"), data: Data([0, 1, 2]))
            try writeData(at: root.appendingPathComponent("invalid.swift"), data: Data([0xFF, 0xFE]))
            try writeFile(at: root.appendingPathComponent("large.swift"), contents: String(repeating: "x", count: 2048))
            try writeFile(at: root.appendingPathComponent(".hidden.swift"), contents: "hidden")
            try writeFile(at: root.appendingPathComponent("excluded.log"), contents: "excluded")
            try writeFile(at: root.appendingPathComponent("disallowed.txt"), contents: "disallowed")

            let result = try TreeLoader().load(
                rootURL: root,
                allowList: ["swift", "bin"],
                excludeList: ["log"],
                maxFileSizeKB: 1,
                skipHidden: true
            )

            XCTAssertEqual(result.summary.count(for: .binary), 1)
            XCTAssertEqual(result.summary.count(for: .unreadable), 1)
            XCTAssertEqual(result.summary.count(for: .oversized), 1)
            XCTAssertEqual(result.summary.count(for: .hidden), 1)
            XCTAssertEqual(result.summary.count(for: .excluded), 1)
            XCTAssertEqual(result.summary.count(for: .disallowed), 1)
            XCTAssertEqual(result.summary.skippedCount, 6)
        }
    }

    func testLoadTreeAppliesFiltersAndSkipsBinaryAndLargeFiles() throws {
        try withTemporaryDirectory { root in
            try writeFile(at: root.appendingPathComponent("app.js"), contents: "console.log('ok')")
            try writeFile(at: root.appendingPathComponent("notes.txt"), contents: "notes")
            try writeFile(at: root.appendingPathComponent("ignore.log"), contents: "nope")
            try writeData(at: root.appendingPathComponent("binary.txt"), data: Data([0x00, 0x01, 0x02]))
            try writeData(at: root.appendingPathComponent("large.txt"), data: Data(repeating: 0x41, count: 2048))
            try writeFile(at: root.appendingPathComponent(".hidden.txt"), contents: "hidden")

            let loader = TreeLoader()
            let tree = try loader.loadTree(
                rootURL: root,
                allowList: ["txt", "js"],
                excludeList: ["log"],
                maxFileSizeKB: 1,
                skipHidden: true
            )

            let files = tree.flattened.filter { !$0.isDirectory }.map(\.relativePath).sorted()
            XCTAssertEqual(files, ["app.js", "notes.txt"])
        }
    }

    func testLoadTreeIncludesHiddenWhenAllowed() throws {
        try withTemporaryDirectory { root in
            try writeFile(at: root.appendingPathComponent(".hidden.txt"), contents: "hidden")

            let loader = TreeLoader()
            let tree = try loader.loadTree(
                rootURL: root,
                allowList: ["txt"],
                excludeList: [],
                maxFileSizeKB: 512,
                skipHidden: false
            )

            let files = tree.flattened.filter { !$0.isDirectory }.map(\.relativePath)
            XCTAssertEqual(files, [".hidden.txt"])
        }
    }

    func testFileIDsAreStableAcrossReloads() throws {
        try withTemporaryDirectory { root in
            try writeFile(at: root.appendingPathComponent("app.swift"), contents: "print(\"ok\")")

            let loader = TreeLoader()
            let first = try loader.loadTree(
                rootURL: root,
                allowList: ["swift"],
                excludeList: [],
                maxFileSizeKB: 512,
                skipHidden: true
            )
            let second = try loader.loadTree(
                rootURL: root,
                allowList: ["swift"],
                excludeList: [],
                maxFileSizeKB: 512,
                skipHidden: true
            )

            let firstID = first.flattened.first { !$0.isDirectory }?.id
            let secondID = second.flattened.first { !$0.isDirectory }?.id
            XCTAssertEqual(firstID, "app.swift")
            XCTAssertEqual(firstID, secondID)
        }
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

private func writeFile(at url: URL, contents: String) throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
}

private func writeData(at url: URL, data: Data) throws {
    try data.write(to: url)
}
