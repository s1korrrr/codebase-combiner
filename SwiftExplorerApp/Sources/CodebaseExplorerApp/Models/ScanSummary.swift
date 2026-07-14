enum ScanSkipReason: String, CaseIterable, Sendable {
    case hidden
    case excluded
    case disallowed
    case oversized
    case binary
    case symbolicLink
    case unreadable
}

struct ScanSummary: Equatable, Sendable {
    private(set) var skipped: [ScanSkipReason: Int] = [:]

    mutating func record(_ reason: ScanSkipReason) {
        skipped[reason, default: 0] += 1
    }

    func count(for reason: ScanSkipReason) -> Int {
        skipped[reason, default: 0]
    }

    var skippedCount: Int {
        skipped.values.reduce(0, +)
    }
}

struct TreeLoadResult: Sendable {
    let root: FileNode
    let summary: ScanSummary
}
