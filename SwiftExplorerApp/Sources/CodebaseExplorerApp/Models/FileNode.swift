import Foundation

struct FileNode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let relativePath: String
    let url: URL
    let isDirectory: Bool
    var children: [FileNode] = []
    let tokenCount: Int
    let sizeBytes: Int
    let content: String?

    var childrenOrNil: [FileNode]? {
        children.isEmpty ? nil : children
    }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }

    var flattened: [FileNode] {
        if children.isEmpty { return [self] }
        return children.flatMap(\.flattened) + [self]
    }
}
