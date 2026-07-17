@testable import CodebaseExplorerApp
import Darwin
import Foundation
import XCTest

final class TreeLoaderTests: XCTestCase {
    func testLoadFailsClosedWhenFilteredTraversalExceedsItsBound() throws {
        try withTemporaryDirectory { root in
            try writeFile(at: root.appendingPathComponent("b.swift"), contents: "b")
            try writeFile(at: root.appendingPathComponent("a.swift"), contents: "a")
            try writeFile(at: root.appendingPathComponent("c.log"), contents: "c")

            XCTAssertThrowsError(
                try TreeLoader(
                    limits: .init(maxFiles: 1, maxBytes: 1024, maxDepth: 8, maxVisitedEntries: 2)
                ).load(
                    rootURL: root,
                    allowList: ["swift"],
                    excludeList: [],
                    maxFileSizeKB: 512,
                    skipHidden: true
                )
            ) { error in
                XCTAssertTrue(error.localizedDescription.contains("traversal safety limit"))
            }
        }
    }

    func testLoadSelectsAcceptedSubsetDeterministically() throws {
        try withTemporaryDirectory { root in
            try writeFile(at: root.appendingPathComponent("b.swift"), contents: "b")
            try writeFile(at: root.appendingPathComponent("a.swift"), contents: "a")

            let result = try TreeLoader(
                limits: .init(maxFiles: 1, maxBytes: 1024, maxDepth: 8, maxVisitedEntries: 10)
            ).load(
                rootURL: root,
                allowList: ["swift"],
                excludeList: [],
                maxFileSizeKB: 512,
                skipHidden: true
            )

            XCTAssertEqual(result.root.flattened.filter { !$0.isDirectory }.map(\.relativePath), ["a.swift"])
        }
    }

    func testLoadUsesLocaleIndependentLexicalOrderForBoundedSelection() throws {
        try withTemporaryDirectory { root in
            try writeFile(at: root.appendingPathComponent("a2.swift"), contents: "two")
            try writeFile(at: root.appendingPathComponent("a10.swift"), contents: "ten")

            let result = try TreeLoader(
                limits: .init(maxFiles: 1, maxBytes: 1024, maxDepth: 8, maxVisitedEntries: 10)
            ).load(
                rootURL: root,
                allowList: ["swift"],
                excludeList: [],
                maxFileSizeKB: 512,
                skipHidden: true
            )

            XCTAssertEqual(result.root.flattened.filter { !$0.isDirectory }.map(\.relativePath), ["a10.swift"])
        }
    }

    func testLoadStopsAtAggregateFileAndByteLimits() throws {
        try withTemporaryDirectory { root in
            try writeFile(at: root.appendingPathComponent("a.swift"), contents: "1234")
            try writeFile(at: root.appendingPathComponent("b.swift"), contents: "5678")

            let result = try TreeLoader(limits: .init(maxFiles: 1, maxBytes: 4, maxDepth: 8)).load(
                rootURL: root,
                allowList: ["swift"],
                excludeList: [],
                maxFileSizeKB: 512,
                skipHidden: true
            )

            XCTAssertEqual(result.root.flattened.count(where: { !$0.isDirectory }), 1)
            XCTAssertEqual(result.summary.count(for: .workspaceLimit), 1)
        }
    }

    func testLoadStopsAtMaximumDirectoryDepth() throws {
        try withTemporaryDirectory { root in
            let nested = root.appendingPathComponent("one/two", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try writeFile(at: nested.appendingPathComponent("deep.swift"), contents: "deep")

            let result = try TreeLoader(limits: .init(maxFiles: 10, maxBytes: 1024, maxDepth: 1)).load(
                rootURL: root,
                allowList: ["swift"],
                excludeList: [],
                maxFileSizeKB: 512,
                skipHidden: true
            )

            XCTAssertTrue(result.root.flattened.filter { !$0.isDirectory }.isEmpty)
            XCTAssertEqual(result.summary.count(for: .workspaceLimit), 1)
        }
    }

    func testLoadStopsWhenCurrentTaskIsCancelled() async throws {
        try await withTemporaryDirectory { root in
            try writeFile(at: root.appendingPathComponent("App.swift"), contents: "print(\"no\")")

            let error = await Task {
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    _ = try TreeLoader().load(
                        rootURL: root,
                        allowList: ["swift"],
                        excludeList: [],
                        maxFileSizeKB: 512,
                        skipHidden: true
                    )
                    return nil as Error?
                } catch {
                    return error
                }
            }.value

            XCTAssertTrue(error is CancellationError)
        }
    }

    func testLoadRejectsSymbolicLinkWorkspaceRootWithoutNamingItsTarget() throws {
        try withTemporaryDirectory { container in
            let target = container.appendingPathComponent("private-target", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try writeFile(at: target.appendingPathComponent("secret.swift"), contents: "private source")
            let linkedRoot = container.appendingPathComponent("linked-workspace")
            try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: target)

            XCTAssertThrowsError(
                try TreeLoader().load(
                    rootURL: linkedRoot,
                    allowList: ["swift"],
                    excludeList: [],
                    maxFileSizeKB: 1,
                    skipHidden: true
                )
            ) { error in
                let message = error.localizedDescription
                XCTAssertEqual(message, "Symbolic-link workspace roots are not supported.")
                XCTAssertFalse(message.contains(target.path))
            }
        }
    }

    func testLoadRejectsInRootAndEscapingSymbolicLinksBeforeReadingTargets() throws {
        try withTemporaryDirectory { root in
            let hiddenTargets = root.appendingPathComponent(".targets", isDirectory: true)
            try FileManager.default.createDirectory(at: hiddenTargets, withIntermediateDirectories: true)
            let oversizedTarget = hiddenTargets.appendingPathComponent("oversized.swift")
            try writeFile(at: oversizedTarget, contents: String(repeating: "x", count: 4096))
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("linked-large.swift"),
                withDestinationURL: oversizedTarget
            )

            let outsideTarget = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).swift")
            try writeFile(at: outsideTarget, contents: "private outside source")
            defer { try? FileManager.default.removeItem(at: outsideTarget) }
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("escaping.swift"),
                withDestinationURL: outsideTarget
            )

            let result = try TreeLoader().load(
                rootURL: root,
                allowList: ["swift"],
                excludeList: [],
                maxFileSizeKB: 1,
                skipHidden: true
            )

            XCTAssertEqual(result.summary.count(for: .symbolicLink), 2)
            XCTAssertEqual(result.summary.count(for: .oversized), 0)
            XCTAssertTrue(result.root.flattened.filter { !$0.isDirectory }.isEmpty)
        }
    }

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

    func testUnreadableNestedDirectoryIsReportedInsteadOfReturningSilentPartialSuccess() throws {
        try withTemporaryDirectory { root in
            try writeFile(at: root.appendingPathComponent("App.swift"), contents: "print(\"ok\")")
            let unreadableDirectory = root.appendingPathComponent("Private", isDirectory: true)
            try FileManager.default.createDirectory(at: unreadableDirectory, withIntermediateDirectories: true)
            try writeFile(at: unreadableDirectory.appendingPathComponent("Secret.swift"), contents: "private")
            XCTAssertEqual(chmod(unreadableDirectory.path, 0), 0)
            defer { _ = chmod(unreadableDirectory.path, S_IRWXU) }

            let result = try TreeLoader().load(
                rootURL: root,
                allowList: ["swift"],
                excludeList: [],
                maxFileSizeKB: 512,
                skipHidden: true
            )

            XCTAssertEqual(result.root.flattened.filter { !$0.isDirectory }.map(\.relativePath), ["App.swift"])
            XCTAssertEqual(result.summary.count(for: .unreadable), 1)
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

    func testExplicitHiddenWorkspaceRootRemainsScannableWhenNestedHiddenFilesAreSkipped() throws {
        try withTemporaryDirectory { container in
            let root = container.appendingPathComponent(".workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try writeFile(at: root.appendingPathComponent("App.swift"), contents: "print(\"ok\")")
            try writeFile(at: root.appendingPathComponent(".secret.swift"), contents: "private")

            let result = try TreeLoader().load(
                rootURL: root,
                allowList: ["swift"],
                excludeList: [],
                maxFileSizeKB: 512,
                skipHidden: true
            )

            XCTAssertEqual(result.root.flattened.filter { !$0.isDirectory }.map(\.relativePath), ["App.swift"])
            XCTAssertEqual(result.summary.count(for: .hidden), 1)
        }
    }

    func testFileSwapToFIFOIsRejectedWithoutBlockingForAWriter() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("blocked.swift")
            try writeFile(at: source, contents: "safe source")
            let writerFinished = expectation(description: "delayed FIFO writer completed")

            let loader = TreeLoader(beforeFileOpen: { url in
                guard url.lastPathComponent == source.lastPathComponent else { return }
                try? FileManager.default.removeItem(at: url)
                XCTAssertEqual(mkfifo(url.path, S_IRUSR | S_IWUSR), 0)
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    let descriptor = Darwin.open(url.path, O_WRONLY | O_NONBLOCK)
                    if descriptor >= 0 {
                        Darwin.close(descriptor)
                    }
                    writerFinished.fulfill()
                }
            })

            let started = ContinuousClock.now
            let result = try loader.load(
                rootURL: root,
                allowList: ["swift"],
                excludeList: [],
                maxFileSizeKB: 512,
                skipHidden: true
            )
            let elapsed = started.duration(to: .now)

            XCTAssertLessThan(elapsed, .seconds(1))
            XCTAssertEqual(result.summary.count(for: .unreadable), 1)
            XCTAssertTrue(result.root.flattened.filter { !$0.isDirectory }.isEmpty)
            wait(for: [writerFinished], timeout: 3)
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

    func testRelativePathsRemoveTheRootPrefixExactlyOnce() throws {
        try withTemporaryDirectory { root in
            let repeatedRoot = String(root.path.dropFirst())
            let nested = root.appendingPathComponent(repeatedRoot, isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try writeFile(at: nested.appendingPathComponent("App.swift"), contents: "print(\"ok\")")

            let result = try TreeLoader().load(
                rootURL: root,
                allowList: ["swift"],
                excludeList: [],
                maxFileSizeKB: 512,
                skipHidden: true
            )

            XCTAssertEqual(
                result.root.flattened.first(where: { !$0.isDirectory })?.relativePath,
                "\(repeatedRoot)/App.swift"
            )
        }
    }

    func testFileSwapToSymlinkAfterMetadataCheckIsRejectedWithoutReadingTarget() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("source.swift")
            let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).swift")
            try writeFile(at: source, contents: "safe source")
            try writeFile(at: outside, contents: "private outside source")
            defer { try? FileManager.default.removeItem(at: outside) }

            let loader = TreeLoader(beforeFileOpen: { url in
                guard url.lastPathComponent == source.lastPathComponent else { return }
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
            })
            let result = try loader.load(
                rootURL: root,
                allowList: ["swift"],
                excludeList: [],
                maxFileSizeKB: 512,
                skipHidden: true
            )

            XCTAssertTrue(result.root.flattened.filter { !$0.isDirectory }.isEmpty)
            XCTAssertEqual(result.summary.count(for: .symbolicLink), 1)
            XCTAssertFalse(result.root.flattened.compactMap(\.content).contains("private outside source"))
        }
    }

    func testParentDirectorySwapToSymlinkIsRejectedBeforeReadingEscapingFile() throws {
        try withTemporaryDirectory { root in
            let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
            try writeFile(at: sourceDirectory.appendingPathComponent("App.swift"), contents: "safe source")
            let outsideDirectory = root.deletingLastPathComponent().appendingPathComponent("outside-dir-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
            try writeFile(at: outsideDirectory.appendingPathComponent("App.swift"), contents: "private outside source")
            defer { try? FileManager.default.removeItem(at: outsideDirectory) }

            let loader = TreeLoader(beforeFileOpen: { url in
                guard url.lastPathComponent == "App.swift" else { return }
                try? FileManager.default.removeItem(at: sourceDirectory)
                try? FileManager.default.createSymbolicLink(at: sourceDirectory, withDestinationURL: outsideDirectory)
            })
            let result = try loader.load(
                rootURL: root,
                allowList: ["swift"],
                excludeList: [],
                maxFileSizeKB: 512,
                skipHidden: true
            )

            XCTAssertTrue(result.root.flattened.filter { !$0.isDirectory }.isEmpty)
            XCTAssertEqual(result.summary.count(for: .symbolicLink), 1)
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

private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let resolvedRoot = root.resolvingSymlinksInPath()
    defer {
        try? FileManager.default.removeItem(at: resolvedRoot)
    }
    try await body(resolvedRoot)
}

private func writeFile(at url: URL, contents: String) throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
}

private func writeData(at url: URL, data: Data) throws {
    try data.write(to: url)
}
