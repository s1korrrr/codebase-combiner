import Foundation
import XCTest

@testable import CodebaseExplorerApp

@MainActor
final class AppDependenciesTests: XCTestCase {
    func testProductionEnvironmentUsesStandardDefaultsAndApplicationSupportDrafts() {
        let dependencies = AppDependencies(environment: [:])

        XCTAssertTrue(dependencies.defaults === UserDefaults.standard)
        XCTAssertNil(dependencies.draftBaseDirectory)
        XCTAssertNil(dependencies.initialWindowSize)
    }

    func testE2EHostUsesItsStandardSandboxContainerDependencies() {
        let dependencies = AppDependencies(environment: [
            AppDependencies.e2eWindowSizeEnvironmentKey: "960x640",
        ], bundleIdentifier: AppDependencies.e2eBundleIdentifier)

        XCTAssertTrue(dependencies.defaults === UserDefaults.standard)
        XCTAssertNil(dependencies.draftBaseDirectory)
        XCTAssertEqual(dependencies.initialWindowSize, CGSize(width: 960, height: 640))
    }

    func testE2EWindowSizeIsIgnoredOutsideTheE2EHostAndRejectsInvalidDimensions() {
        let production = AppDependencies(environment: [
            AppDependencies.e2eWindowSizeEnvironmentKey: "960x640",
        ], bundleIdentifier: "com.s1korrrr.codebasecombiner")
        let valid = AppDependencies(environment: [
            AppDependencies.e2eWindowSizeEnvironmentKey: "960x640",
        ], bundleIdentifier: AppDependencies.e2eBundleIdentifier)
        let invalid = AppDependencies(environment: [
            AppDependencies.e2eWindowSizeEnvironmentKey: "960xzero",
        ], bundleIdentifier: AppDependencies.e2eBundleIdentifier)

        XCTAssertNil(production.initialWindowSize)
        XCTAssertEqual(valid.initialWindowSize, CGSize(width: 960, height: 640))
        XCTAssertNil(invalid.initialWindowSize)
    }

    func testE2EWindowFrameUsesTheExactRequestedOuterSize() {
        let frame = E2EWindowFramePolicy.frame(
            size: CGSize(width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949)
        )

        XCTAssertEqual(frame.size, CGSize(width: 1440, height: 900))
        XCTAssertEqual(frame.origin, CGPoint(x: 36, y: 24.5))
    }
}
