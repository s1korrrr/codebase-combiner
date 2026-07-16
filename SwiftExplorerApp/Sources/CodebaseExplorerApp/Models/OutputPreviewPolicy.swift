struct OutputPreviewPresentation: Equatable {
    let text: String
    let isTruncated: Bool
    let notice: String?
}

enum OutputPreviewPolicy {
    static let characterLimit = 20000
    private static let characterLimitLabel = "20,000"

    static func presentation(for payload: String) -> OutputPreviewPresentation {
        guard let previewEnd = payload.index(
            payload.startIndex,
            offsetBy: characterLimit,
            limitedBy: payload.endIndex
        ) else {
            return OutputPreviewPresentation(text: payload, isTruncated: false, notice: nil)
        }

        guard previewEnd != payload.endIndex else {
            return OutputPreviewPresentation(text: payload, isTruncated: false, notice: nil)
        }

        return OutputPreviewPresentation(
            text: String(payload[..<previewEnd]),
            isTruncated: true,
            notice: "Preview shows the first \(characterLimitLabel) characters. Copy and Save use the full output."
        )
    }
}
