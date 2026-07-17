import Darwin
import Foundation
import SecureFileAccessC
import UniformTypeIdentifiers

struct WorkspaceScanLimits: Sendable {
    static let standard = WorkspaceScanLimits(
        maxFiles: 10000,
        maxBytes: 64 * 1024 * 1024,
        maxDepth: 128,
        maxVisitedEntries: 50000
    )

    let maxFiles: Int
    let maxBytes: Int
    let maxDepth: Int
    let maxVisitedEntries: Int

    init(maxFiles: Int, maxBytes: Int, maxDepth: Int, maxVisitedEntries: Int? = nil) {
        self.maxFiles = maxFiles
        self.maxBytes = maxBytes
        self.maxDepth = maxDepth
        self.maxVisitedEntries = maxVisitedEntries ?? maxFiles * 5
    }
}

struct TreeLoader {
    private let estimator = TokenEstimator()
    private let limits: WorkspaceScanLimits
    private let beforeFileOpen: ((URL) -> Void)?

    init(
        limits: WorkspaceScanLimits = .standard,
        beforeFileOpen: ((URL) -> Void)? = nil
    ) {
        self.limits = limits
        self.beforeFileOpen = beforeFileOpen
    }

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
        try Task.checkCancellation()
        let standardizedRoot = rootURL.standardizedFileURL
        let canonicalRoot = standardizedRoot.resolvingSymlinksInPath()
        var summary = ScanSummary()
        var acceptedFileCount = 0
        var acceptedByteCount = 0
        var visitedEntryCount = 0

        func boundedChildren(at url: URL) throws -> [URL] {
            guard visitedEntryCount < limits.maxVisitedEntries else {
                throw TreeLoaderError.workspaceTraversalLimit(limits.maxVisitedEntries)
            }
            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: [.skipsPackageDescendants]
            )

            for _ in children {
                try Task.checkCancellation()
                guard visitedEntryCount < limits.maxVisitedEntries else {
                    throw TreeLoaderError.workspaceTraversalLimit(limits.maxVisitedEntries)
                }
                visitedEntryCount += 1
            }
            return children.sorted { lexicalPathPrecedes($0.lastPathComponent, $1.lastPathComponent) }
        }

        let rootLinkValues = try standardizedRoot.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard rootLinkValues.isSymbolicLink != true else {
            throw NSError(domain: "TreeLoader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Symbolic-link workspace roots are not supported."])
        }
        let rootValues = try standardizedRoot.resourceValues(forKeys: [.isDirectoryKey])
        guard rootValues.isDirectory == true else {
            throw NSError(domain: "TreeLoader", code: 0, userInfo: [NSLocalizedDescriptionKey: "Root must be a folder."])
        }

        func walk(_ url: URL, relativeTo root: URL, depth: Int = 0) throws -> FileNode? {
            try Task.checkCancellation()
            guard depth <= limits.maxDepth else {
                summary.record(.workspaceLimit)
                return nil
            }
            let name = url.lastPathComponent

            if depth > 0, skipHidden, name.hasPrefix(".") {
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
                let childrenURLs: [URL]
                do {
                    childrenURLs = try boundedChildren(at: url)
                } catch let error as TreeLoaderError {
                    throw error
                } catch {
                    summary.record(.unreadable)
                    return nil
                }
                let children = try childrenURLs.compactMap { try walk($0, relativeTo: root, depth: depth + 1) }
                let tokenSum = children.reduce(0) { $0 + $1.tokenCount }
                let sizeSum = children.reduce(0) { $0 + $1.sizeBytes }
                return FileNode(
                    name: name,
                    relativePath: relativePath(for: url, root: root),
                    url: url,
                    isDirectory: true,
                    children: children,
                    tokenCount: tokenSum,
                    sizeBytes: sizeSum,
                    content: nil
                )
            } else {
                guard values.isRegularFile == true else {
                    summary.record(.unreadable)
                    return nil
                }
                let ext = url.pathExtension.lowercased()

                if excludeList.contains(ext) {
                    summary.record(.excluded)
                    return nil
                }
                if !allowList.isEmpty, !allowList.contains(ext) {
                    summary.record(.disallowed)
                    return nil
                }

                beforeFileOpen?(url)
                let readResult = readRegularFileWithoutFollowingSymlinks(
                    at: url,
                    expectedURL: canonicalRoot.appendingPathComponent(relativePath(for: url, root: root)),
                    maximumBytes: maxFileSizeKB * 1024
                )
                let data: Data
                switch readResult {
                case let .success(fileData):
                    data = fileData
                case .symbolicLink:
                    summary.record(.symbolicLink)
                    return nil
                case .oversized:
                    summary.record(.oversized)
                    return nil
                case .unreadable:
                    summary.record(.unreadable)
                    return nil
                }
                let size = data.count
                guard acceptedFileCount < limits.maxFiles,
                      size <= limits.maxBytes - acceptedByteCount
                else {
                    summary.record(.workspaceLimit)
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
                acceptedFileCount += 1
                acceptedByteCount += size

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

        guard let node = try walk(standardizedRoot, relativeTo: standardizedRoot) else {
            throw NSError(domain: "TreeLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read folder contents."])
        }
        return TreeLoadResult(root: node, summary: summary)
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.starts(with: rootComponents) else {
            return url.lastPathComponent
        }
        let relativeComponents = urlComponents.dropFirst(rootComponents.count)
        return relativeComponents.isEmpty ? url.lastPathComponent : relativeComponents.joined(separator: "/")
    }

    private func isBinary(data: Data) -> Bool {
        let sample = data.prefix(1024)
        return sample.contains(0)
    }

    private func readRegularFileWithoutFollowingSymlinks(
        at url: URL,
        expectedURL: URL,
        maximumBytes: Int
    ) -> SecureFileReadResult {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            return errno == ELOOP ? .symbolicLink : .unreadable
        }
        defer { Darwin.close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0
        else { return .unreadable }
        var descriptorPath = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathResult = descriptorPath.withUnsafeMutableBufferPointer { buffer in
            secure_file_descriptor_path(descriptor, buffer.baseAddress, buffer.count)
        }
        guard pathResult == 0 else { return .unreadable }
        let pathBytes = descriptorPath.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let openedPath = URL(
            fileURLWithPath: String(decoding: pathBytes, as: UTF8.self)
        ).standardizedFileURL.path
        guard openedPath == expectedURL.standardizedFileURL.path else { return .symbolicLink }
        guard metadata.st_size <= maximumBytes else { return .oversized }

        var data = Data()
        data.reserveCapacity(min(Int(metadata.st_size), maximumBytes))
        var buffer = [UInt8](repeating: 0, count: 65536)
        while data.count <= maximumBytes {
            let remaining = maximumBytes - data.count + 1
            let bytesRead = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, min(bytes.count, remaining))
            }
            if bytesRead == 0 { return .success(data) }
            guard bytesRead > 0 else {
                if errno == EINTR { continue }
                return .unreadable
            }
            data.append(contentsOf: buffer.prefix(bytesRead))
            if data.count > maximumBytes { return .oversized }
        }
        return .oversized
    }
}

private func lexicalPathPrecedes(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
}

private enum SecureFileReadResult {
    case success(Data)
    case symbolicLink
    case oversized
    case unreadable
}

private enum TreeLoaderError: LocalizedError {
    case workspaceTraversalLimit(Int)

    var errorDescription: String? {
        switch self {
        case let .workspaceTraversalLimit(entries):
            "Workspace exceeds the traversal safety limit of \(entries) entries."
        }
    }
}
