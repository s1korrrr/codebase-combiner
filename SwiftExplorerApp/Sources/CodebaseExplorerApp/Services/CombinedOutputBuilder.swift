import Foundation

enum CombinedOutputFormat: String, Codable, Sendable {
    case markdown
    case plainText
}

struct CombinedOutputBuilder {
    func build(promptPrefix: String, files: [FileNode], format: CombinedOutputFormat) -> String {
        var blocks: [String] = []
        let prefix = promptPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prefix.isEmpty {
            blocks.append(prefix)
        }

        for file in files {
            guard let content = file.content else { continue }
            switch format {
            case .markdown:
                blocks.append("## \(file.relativePath)\n\n```\(languageHint(for: file))\n\(content)\n```\n")
            case .plainText:
                blocks.append("// File: \(file.relativePath)\n\(content)\n")
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
}
