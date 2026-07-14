@testable import CodebaseExplorerApp
import XCTest

final class WorkspaceLayoutPolicyTests: XCTestCase {
    func testModeUsesCompactRegularAndWideBreakpoints() {
        XCTAssertEqual(WorkspaceLayoutPolicy.mode(for: 959), .compact)
        XCTAssertEqual(WorkspaceLayoutPolicy.mode(for: 960), .regular)
        XCTAssertEqual(WorkspaceLayoutPolicy.mode(for: 1320), .wide)
    }
}
