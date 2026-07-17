@testable import CodebaseExplorerApp
import Foundation
import XCTest

final class AppPreferencesTests: XCTestCase {
    func testValidationRejectsSizeOutsideSupportedRange() {
        XCTAssertEqual(AppPreferences.validate(maxFileSizeKB: 31), .invalid("Enter a value from 32 to 8,192 KB."))
        XCTAssertEqual(AppPreferences.validate(maxFileSizeKB: 8193), .invalid("Enter a value from 32 to 8,192 KB."))
        XCTAssertEqual(AppPreferences.validate(maxFileSizeKB: .nan), .invalid("Enter a value from 32 to 8,192 KB."))
        XCTAssertEqual(AppPreferences.validate(maxFileSizeKB: .infinity), .invalid("Enter a value from 32 to 8,192 KB."))
        XCTAssertEqual(AppPreferences.validate(maxFileSizeKB: 512), .valid)
    }

    @MainActor
    func testMalformedPersistedMaximumFileSizeIsNormalizedBeforePublishing() throws {
        for malformedValue in [Double.nan, .infinity, -.infinity, Double.greatestFiniteMagnitude] {
            let suiteName = "AppPreferencesTests.malformed.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(malformedValue, forKey: "cc_maxFileSizeKB")

            XCTAssertEqual(AppPreferences(defaults: defaults).values.maxFileSizeKB, 512)
        }
    }

    func testExtensionParserNormalizesDotsCaseAndDelimiters() {
        XCTAssertEqual(AppPreferences.extensionSet(from: ".Swift, JS;md\nPY"), ["swift", "js", "md", "py"])
    }

    @MainActor
    func testLoadsAndPersistsValuesUsingExistingKeys() throws {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("swift,md", forKey: "cc_allowListString")
        defaults.set("png,zip", forKey: "cc_excludeListString")
        defaults.set(1024.0, forKey: "cc_maxFileSizeKB")
        defaults.set(false, forKey: "cc_skipHidden")
        defaults.set(false, forKey: "cc_outputMarkdown")
        defaults.set(false, forKey: "cc_showFilters")

        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(
            preferences.values,
            AppPreferences.Values(
                allowList: "swift,md",
                excludeList: "png,zip",
                maxFileSizeKB: 1024,
                skipHidden: false,
                outputMarkdown: false,
                showFilters: false
            )
        )

        preferences.values = AppPreferences.Values(
            allowList: "swift,rs",
            excludeList: "gif,bin",
            maxFileSizeKB: 2048,
            skipHidden: true,
            outputMarkdown: true,
            showFilters: true
        )

        XCTAssertEqual(defaults.string(forKey: "cc_allowListString"), "swift,rs")
        XCTAssertEqual(defaults.string(forKey: "cc_excludeListString"), "gif,bin")
        XCTAssertEqual(defaults.double(forKey: "cc_maxFileSizeKB"), 2048)
        XCTAssertTrue(defaults.bool(forKey: "cc_skipHidden"))
        XCTAssertTrue(defaults.bool(forKey: "cc_outputMarkdown"))
        XCTAssertTrue(defaults.bool(forKey: "cc_showFilters"))
    }
}
