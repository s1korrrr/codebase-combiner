import os

enum AppTelemetryEvent: Equatable, Sendable {
    case scanStarted
    case scanFinished(WorkspaceScanOutcome)
    case recoverySaveSucceeded(fileCount: Int, byteCount: Int)
    case recoverySaveFailed
    case recoveryLoadSucceeded(available: Bool)
    case recoveryLoadFailed
    case currentCopySucceeded(characterCount: Int)
    case currentCopyFailed
    case recoveredCopySucceeded(characterCount: Int)
    case recoveredCopyFailed
    case currentSaveSucceeded(characterCount: Int)
    case currentSaveFailed
    case recoveryClearSucceeded
    case recoveryClearFailed
}

@MainActor
protocol AppTelemetryRecording: AnyObject {
    func record(_ event: AppTelemetryEvent)
}

@MainActor
final class LiveAppTelemetry: AppTelemetryRecording {
    static let shared = LiveAppTelemetry()

    private init() {}

    func record(_ event: AppTelemetryEvent) {
        switch event {
        case .scanStarted:
            AppLog.scan.info("Workspace scan started")
        case let .scanFinished(.accepted(fileCount, selectedCount, skippedCount)):
            AppLog.scan.info(
                "Workspace scan accepted files=\(fileCount, privacy: .public) selected=\(selectedCount, privacy: .public) skipped=\(skippedCount, privacy: .public)"
            )
        case .scanFinished(.rejectedInvalidMaximumFileSize):
            AppLog.scan.info("Workspace scan rejected reason=invalid_maximum_file_size")
        case .scanFinished(.failed):
            AppLog.scan.error("Workspace scan failed")
        case .scanFinished(.stale):
            AppLog.scan.info("Workspace scan discarded as stale")
        case let .recoverySaveSucceeded(fileCount, byteCount):
            AppLog.persistence.info(
                "Recovery save succeeded files=\(fileCount, privacy: .public) bytes=\(byteCount, privacy: .public)"
            )
        case .recoverySaveFailed:
            AppLog.persistence.error("Recovery save failed")
        case let .recoveryLoadSucceeded(available):
            AppLog.persistence.info("Recovery load succeeded available=\(available, privacy: .public)")
        case .recoveryLoadFailed:
            AppLog.persistence.error("Recovery load failed")
        case let .currentCopySucceeded(characterCount):
            AppLog.export.info("Current output copy succeeded characters=\(characterCount, privacy: .public)")
        case .currentCopyFailed:
            AppLog.export.error("Current output copy failed")
        case let .recoveredCopySucceeded(characterCount):
            AppLog.export.info("Recovered output copy succeeded characters=\(characterCount, privacy: .public)")
        case .recoveredCopyFailed:
            AppLog.export.error("Recovered output copy failed")
        case let .currentSaveSucceeded(characterCount):
            AppLog.export.info("Current output save succeeded characters=\(characterCount, privacy: .public)")
        case .currentSaveFailed:
            AppLog.export.error("Current output save failed")
        case .recoveryClearSucceeded:
            AppLog.persistence.info("Recovery clear succeeded")
        case .recoveryClearFailed:
            AppLog.persistence.error("Recovery clear failed")
        }
    }
}

enum AppLog {
    private static let subsystem = "com.s1korrrr.codebasecombiner"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let scan = Logger(subsystem: subsystem, category: "scan")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
