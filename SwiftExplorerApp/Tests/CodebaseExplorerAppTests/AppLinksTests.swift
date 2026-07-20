@testable import CodebaseExplorerApp
import XCTest

final class AppLinksTests: XCTestCase {
    func testSupportAndPrivacyLinksUsePublicProjectPages() {
        XCTAssertEqual(AppLinks.supportURL.scheme, "https")
        XCTAssertEqual(AppLinks.supportURL.host, "github.com")
        XCTAssertEqual(
            AppLinks.supportURL.path,
            "/rsitech-ai/codebase-combiner/blob/main/docs/support.md"
        )
        XCTAssertEqual(AppLinks.privacyPolicyURL.scheme, "https")
        XCTAssertEqual(AppLinks.privacyPolicyURL.host, "github.com")
        XCTAssertEqual(
            AppLinks.privacyPolicyURL.path,
            "/rsitech-ai/codebase-combiner/blob/main/docs/privacy-policy.md"
        )
        XCTAssertFalse(AppLinks.supportURL.absoluteString.contains("buymeacoffee"))
    }
}
