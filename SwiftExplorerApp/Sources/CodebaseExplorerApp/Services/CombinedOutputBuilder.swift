import Foundation

enum CombinedOutputFormat: String, Codable, Sendable {
    case markdown
    case plainText
}

struct CombinedOutputBuilder {
    func build(promptPrefix: String, files: [FileNode], format: CombinedOutputFormat) -> String {
        guard !Task.isCancelled else { return "" }
        var blocks: [String] = []
        let prefix = promptPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prefix.isEmpty {
            blocks.append(prefix)
        }

        for file in files {
            guard !Task.isCancelled else { return "" }
            guard let content = file.content else { continue }
            switch format {
            case .markdown:
                let fence = markdownFence(for: content)
                blocks.append("## \(markdownHeading(for: file.relativePath))\n\n\(fence)\(languageHint(for: file))\n\(content)\n\(fence)\n")
            case .plainText:
                blocks.append("// File: \(singleLinePath(file.relativePath))\n\(content)\n")
            }
        }

        return blocks.joined(separator: "\n")
    }

    func languageHint(for file: FileNode) -> String {
        switch file.fileExtension {
        case "swift": "swift"
        case "js": "javascript"
        case "ts": "typescript"
        case "tsx": "typescriptreact"
        case "jsx": "javascriptreact"
        case "json": "json"
        case "py": "python"
        case "rb": "ruby"
        case "rs": "rust"
        case "go": "go"
        case "kt": "kotlin"
        case "java": "java"
        case "php": "php"
        case "sh", "zsh", "bash": "bash"
        case "yml", "yaml": "yaml"
        case "md": "markdown"
        default: ""
        }
    }

    private func markdownFence(for content: String) -> String {
        var longestRun = 0
        var currentRun = 0
        for character in content {
            if character == "`" {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        return String(repeating: "`", count: max(3, longestRun + 1))
    }

    private func markdownHeading(for path: String) -> String {
        singleLinePath(path).replacingOccurrences(
            of: #"([\\`*_\[\]<>#])"#,
            with: #"\\$1"#,
            options: .regularExpression
        )
    }

    private func singleLinePath(_ path: String) -> String {
        path.replacingOccurrences(of: #"[\r\n\u{2028}\u{2029}]+"#, with: " ", options: .regularExpression)
    }
}
