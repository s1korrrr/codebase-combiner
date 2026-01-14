@testable import CodebaseExplorerApp
import XCTest

final class TokenEstimatorTests: XCTestCase {
    func testEstimateTokensMinimumOfOne() {
        let estimator = TokenEstimator()
        XCTAssertEqual(estimator.estimateTokens(in: ""), 1)
        XCTAssertEqual(estimator.estimateTokens(in: "a"), 1)
    }

    func testEstimateTokensScalesWithLength() {
        let estimator = TokenEstimator()
        let text = String(repeating: "a", count: 20)
        XCTAssertEqual(estimator.estimateTokens(in: text), 5)
    }
}
