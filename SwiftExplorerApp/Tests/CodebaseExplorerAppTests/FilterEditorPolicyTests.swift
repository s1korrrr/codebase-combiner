@testable import CodebaseExplorerApp
import XCTest

final class FilterEditorPolicyTests: XCTestCase {
    func testCancelKeepsOriginalFilterValues() {
        let original = FilterEditorValues(allowList: "swift,md", excludeList: "bin")
        let draft = FilterEditorValues(allowList: "swift", excludeList: "bin,zip")

        XCTAssertEqual(
            FilterEditorPolicy.resolvedValues(original: original, draft: draft, action: .cancel),
            original
        )
    }

    func testApplyCommitsDraftFilterValues() {
        let original = FilterEditorValues(allowList: "swift,md", excludeList: "bin")
        let draft = FilterEditorValues(allowList: "swift", excludeList: "bin,zip")

        XCTAssertEqual(
            FilterEditorPolicy.resolvedValues(original: original, draft: draft, action: .apply),
            draft
        )
    }
}
