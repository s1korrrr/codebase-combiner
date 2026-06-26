import Foundation
import UniformTypeIdentifiers

struct TreeLoader {
    private let estimator = TokenEstimator()

    func loadTree(
        rootURL: URL,
        allowList: Set<String>,
        excludeList: Set<String>,
        maxFileSizeKB: Int,
        skipHidden: Bool
    ) throws -> FileNode {
        let resolvedRoot = rootURL.resolvingSymlinksInPath()

        guard isDirectory(resolvedRoot) else {
            throw NSError(domain: "TreeLoader", code: 0, userInfo: [NSLocalizedDescriptionKey: "Root must be a folder."])
        }

        func walk(_ url: URL, relativeTo root: URL) -> FileNode? {
            let name = url.lastPathComponent

            if skipHidden, name.hasPrefix(".") { return nil }

            if isDirectory(url) {
                guard let childrenURLs = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [.skipsPackageDescendants]) else {
                    return nil
                }
                let children = childrenURLs.compactMap { walk($0, relativeTo: root) }
                let tokenSum = children.reduce(0) { $0 + $1.tokenCount }
                let sizeSum = children.reduce(0) { $0 + $1.sizeBytes }
                return FileNode(
                    name: name,
                    relativePath: relativePath(for: url, root: root),
                    url: url,
                    isDirectory: true,
                    children: children.sorted(by: { $0.name.lowercased() < $1.name.lowercased() }),
                    tokenCount: tokenSum,
                    sizeBytes: sizeSum,
                    content: nil
                )
            } else {
                let ext = url.pathExtension.lowercased()

                if excludeList.contains(ext) { return nil }
                if !allowList.isEmpty, !allowList.contains(ext) { return nil }

                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }

                if size > maxFileSizeKB * 1024 { return nil }

                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
                if isBinary(data: data) { return nil }
                guard let text = String(data: data, encoding: .utf8) else { return nil }

                let tokens = estimator.estimateTokens(in: text)

                return FileNode(
                    name: name,
                    relativePath: relativePath(for: url, root: root),
                    url: url,
                    isDirectory: false,
                    children: [],
                    tokenCount: tokens,
                    sizeBytes: size,
                    content: text
                )
            }
        }

        guard let node = walk(resolvedRoot, relativeTo: resolvedRoot) else {
            throw NSError(domain: "TreeLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read folder contents."])
        }
        return node
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let resolvedURL = url.resolvingSymlinksInPath()
        var path = resolvedURL.path.replacingOccurrences(of: root.path, with: "")
        if path.hasPrefix("/") { path.removeFirst() }
        return path.isEmpty ? url.lastPathComponent : path
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func isBinary(data: Data) -> Bool {
        let sample = data.prefix(1024)
        return sample.contains(0)
    }
}
