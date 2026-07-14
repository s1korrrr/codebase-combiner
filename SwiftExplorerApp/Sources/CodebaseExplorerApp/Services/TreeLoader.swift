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
        try load(
            rootURL: rootURL,
            allowList: allowList,
            excludeList: excludeList,
            maxFileSizeKB: maxFileSizeKB,
            skipHidden: skipHidden
        ).root
    }

    func load(
        rootURL: URL,
        allowList: Set<String>,
        excludeList: Set<String>,
        maxFileSizeKB: Int,
        skipHidden: Bool
    ) throws -> TreeLoadResult {
        let standardizedRoot = rootURL.standardizedFileURL
        var summary = ScanSummary()

        let rootLinkValues = try standardizedRoot.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard rootLinkValues.isSymbolicLink != true else {
            throw NSError(domain: "TreeLoader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Symbolic-link workspace roots are not supported."])
        }
        let rootValues = try standardizedRoot.resourceValues(forKeys: [.isDirectoryKey])
        guard rootValues.isDirectory == true else {
            throw NSError(domain: "TreeLoader", code: 0, userInfo: [NSLocalizedDescriptionKey: "Root must be a folder."])
        }

        func walk(_ url: URL, relativeTo root: URL) -> FileNode? {
            let name = url.lastPathComponent

            if skipHidden, name.hasPrefix(".") {
                summary.record(.hidden)
                return nil
            }

            guard let linkValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else {
                summary.record(.unreadable)
                return nil
            }
            if linkValues.isSymbolicLink == true {
                summary.record(.symbolicLink)
                return nil
            }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
                summary.record(.unreadable)
                return nil
            }

            if values.isDirectory == true {
                guard let childrenURLs = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsPackageDescendants]) else {
                    summary.record(.unreadable)
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

                if excludeList.contains(ext) {
                    summary.record(.excluded)
                    return nil
                }
                if !allowList.isEmpty, !allowList.contains(ext) {
                    summary.record(.disallowed)
                    return nil
                }

                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                    summary.record(.unreadable)
                    return nil
                }

                if size > maxFileSizeKB * 1024 {
                    summary.record(.oversized)
                    return nil
                }

                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                    summary.record(.unreadable)
                    return nil
                }
                if isBinary(data: data) {
                    summary.record(.binary)
                    return nil
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    summary.record(.unreadable)
                    return nil
                }

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

        guard let node = walk(standardizedRoot, relativeTo: standardizedRoot) else {
            throw NSError(domain: "TreeLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read folder contents."])
        }
        return TreeLoadResult(root: node, summary: summary)
    }

    private func relativePath(for url: URL, root: URL) -> String {
        var path = url.standardizedFileURL.path.replacingOccurrences(of: root.path, with: "")
        if path.hasPrefix("/") { path.removeFirst() }
        return path.isEmpty ? url.lastPathComponent : path
    }

    private func isBinary(data: Data) -> Bool {
        let sample = data.prefix(1024)
        return sample.contains(0)
    }
}
