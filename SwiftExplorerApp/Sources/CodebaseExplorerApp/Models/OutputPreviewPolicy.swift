struct OutputPreviewPresentation: Equatable {
    let text: String
    let isTruncated: Bool
    let notice: String?
}

enum OutputPreviewPolicy {
    static let characterLimit = 20000
    private static let characterLimitLabel = "20,000"

    static func presentation(for payload: String) -> OutputPreviewPresentation {
        guard payload.count > characterLimit else {
            return OutputPreviewPresentation(text: payload, isTruncated: false, notice: nil)
        }

        return OutputPreviewPresentation(
            text: String(payload.prefix(characterLimit)),
            isTruncated: true,
            notice: "Preview shows the first \(characterLimitLabel) characters. Copy and Save use the full output."
        )
    }
}
