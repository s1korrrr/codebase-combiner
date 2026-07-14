import Foundation
import XCTest

final class AppTelemetrySourceTests: XCTestCase {
    func testOperationalEventsCoverScanExportAndPersistenceWithoutContentOrPaths() throws {
        let controller = try sourceFile(in: "App", named: "AppController.swift")
        let output = try sourceFile(in: "Stores", named: "OutputStore.swift")

        XCTAssertTrue(controller.contains("AppLog.scan.info"))
        XCTAssertTrue(output.contains("AppLog.export.info"))
        XCTAssertTrue(output.contains("AppLog.persistence.info"))

        let eventLines = (controller + "\n" + output)
            .split(separator: "\n")
            .filter { $0.contains("AppLog.") }
        for line in eventLines {
            XCTAssertFalse(line.contains("currentPayload"), String(line))
            XCTAssertFalse(line.contains("promptPrefix"), String(line))
            XCTAssertFalse(line.contains("rootURL"), String(line))
            XCTAssertFalse(line.contains("url"), String(line))
            XCTAssertFalse(line.contains("text"), String(line))
        }
    }

    private func sourceFile(in directory: String, named name: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources/CodebaseExplorerApp")
                .appendingPathComponent(directory)
                .appendingPathComponent(name),
            encoding: .utf8
        )
    }
}
