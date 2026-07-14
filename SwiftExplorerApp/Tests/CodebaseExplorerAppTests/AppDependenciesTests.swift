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

    func testE2EEnvironmentUsesNamedDefaultsSuiteAndIsolatedDraftDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let key = "e2e-isolation-\(UUID().uuidString)"
        UserDefaults.standard.removeObject(forKey: key)

        let dependencies = AppDependencies(environment: [
            AppDependencies.e2eDataDirectoryEnvironmentKey: root.path,
        ])
        dependencies.defaults.set("isolated", forKey: key)

        XCTAssertFalse(dependencies.defaults === UserDefaults.standard)
        XCTAssertNil(UserDefaults.standard.string(forKey: key))
        XCTAssertEqual(dependencies.defaults.string(forKey: key), "isolated")
        XCTAssertEqual(dependencies.draftBaseDirectory?.standardizedFileURL, root.standardizedFileURL)

        dependencies.defaults.removeObject(forKey: key)
    }

    func testE2EWindowSizeParsesOnlyValidPositiveDimensions() {
        let valid = AppDependencies(environment: [
            AppDependencies.e2eWindowSizeEnvironmentKey: "960x640",
        ])
        let invalid = AppDependencies(environment: [
            AppDependencies.e2eWindowSizeEnvironmentKey: "960xzero",
        ])

        XCTAssertEqual(valid.initialWindowSize, CGSize(width: 960, height: 640))
        XCTAssertNil(invalid.initialWindowSize)
    }
}
