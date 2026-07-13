import Foundation

struct ClipboardDraft: Codable, Equatable, Sendable {
    let text: String
    let format: CombinedOutputFormat
    let fileCount: Int
    let tokenCount: Int
    let byteCount: Int
    let rootPath: String?
    let generatedAt: Date

    var formatLabel: String {
        switch format {
        case .markdown:
            "Markdown"
        case .plainText:
            "Plain Text"
        }
    }
}
