@testable import CodebaseExplorerApp
import XCTest

final class OutputPreviewPolicyTests: XCTestCase {
    func testLargeRecoveredPayloadUsesBoundedHonestPresentation() {
        let fullPayload = String(repeating: "a", count: 25000)

        let presentation = OutputPreviewPolicy.presentation(for: fullPayload)

        XCTAssertEqual(presentation.text.count, 20000)
        XCTAssertTrue(presentation.isTruncated)
        XCTAssertEqual(
            presentation.notice,
            "Preview shows the first 20,000 characters. Copy and Save use the full output."
        )
        XCTAssertEqual(fullPayload.count, 25000)
    }

    func testSmallPayloadNeedsNoTruncationNotice() {
        let presentation = OutputPreviewPolicy.presentation(for: "complete")

        XCTAssertEqual(presentation.text, "complete")
        XCTAssertFalse(presentation.isTruncated)
        XCTAssertNil(presentation.notice)
    }
}
