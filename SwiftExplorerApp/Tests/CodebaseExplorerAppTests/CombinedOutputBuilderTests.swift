@testable import CodebaseExplorerApp
import Foundation
import XCTest

final class CombinedOutputBuilderTests: XCTestCase {
    func testCancelledBuildReturnsWithoutProcessingFiles() async {
        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return CombinedOutputBuilder().build(
                promptPrefix: "Do not retain partial output.",
                files: [FileNode(
                    name: "App.swift",
                    relativePath: "App.swift",
                    url: URL(fileURLWithPath: "/tmp/App.swift"),
                    isDirectory: false,
                    tokenCount: 3,
                    sizeBytes: 11,
                    content: "print(\"no\")"
                )],
                format: .markdown
            )
        }.value

        XCTAssertEqual(result, "")
    }

    func testBuildsMarkdownWithPromptAndLanguageHint() {
        let builder = CombinedOutputBuilder()
        let file = FileNode(
            name: "App.swift",
            relativePath: "Sources/App.swift",
            url: URL(fileURLWithPath: "/tmp/Sources/App.swift"),
            isDirectory: false,
            tokenCount: 3,
            sizeBytes: 12,
            content: "print(\"ok\")"
        )

        let text = builder.build(
            promptPrefix: "Review this code.",
            files: [file],
            format: .markdown
        )

        XCTAssertTrue(text.contains("Review this code."))
        XCTAssertTrue(text.contains("## Sources/App.swift"))
        XCTAssertTrue(text.contains("```swift"))
        XCTAssertTrue(text.contains("print(\"ok\")"))
    }

    func testBuildsPlainTextWithoutEmptyPrompt() {
        let builder = CombinedOutputBuilder()
        let file = FileNode(
            name: "notes.txt",
            relativePath: "notes.txt",
            url: URL(fileURLWithPath: "/tmp/notes.txt"),
            isDirectory: false,
            tokenCount: 1,
            sizeBytes: 5,
            content: "hello"
        )

        let text = builder.build(promptPrefix: "   ", files: [file], format: .plainText)

        XCTAssertEqual(text, "// File: notes.txt\nhello\n")
    }

    func testMarkdownUsesABoundedFenceAndSanitizesHeadingNewlines() {
        let file = FileNode(
            name: "unsafe.md",
            relativePath: "docs/unsafe\n# heading.md",
            url: URL(fileURLWithPath: "/tmp/unsafe.md"),
            isDirectory: false,
            tokenCount: 3,
            sizeBytes: 32,
            content: "before\n```swift\ninside\n````\nafter"
        )

        let text = CombinedOutputBuilder().build(promptPrefix: "", files: [file], format: .markdown)

        XCTAssertTrue(text.contains("`````markdown"))
        XCTAssertTrue(text.contains("\n`````\n"))
        XCTAssertFalse(text.contains("unsafe\n# heading"))
    }
}
