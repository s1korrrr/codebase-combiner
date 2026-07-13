import Combine
import Foundation

protocol WorkspaceLoading: Sendable {
    func load(rootURL: URL, preferences: AppPreferences.Values) async throws -> TreeLoadResult
}

struct LiveWorkspaceLoader: WorkspaceLoading {
    func load(rootURL: URL, preferences: AppPreferences.Values) async throws -> TreeLoadResult {
        try await Task.detached(priority: .userInitiated) {
            try TreeLoader().load(
                rootURL: rootURL,
                allowList: AppPreferences.extensionSet(from: preferences.allowList),
                excludeList: AppPreferences.extensionSet(from: preferences.excludeList),
                maxFileSizeKB: Int(preferences.maxFileSizeKB),
                skipHidden: preferences.skipHidden
            )
        }.value
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    struct State: Equatable {
        var rootURL: URL?
        var rootNode: FileNode?
        var allFiles: [FileNode] = []
        var selectedIDs: Set<String> = []
        var selectedFiles: [FileNode] = []
        var selectedBytes = 0
        var selectedTokens = 0
        var summary = ScanSummary()
        var isScanning = false
        var status = "Choose a workspace to begin."
    }

    @Published private(set) var state = State()

    var rootURL: URL? { state.rootURL }
    var rootNode: FileNode? { state.rootNode }
    var allFiles: [FileNode] { state.allFiles }
    var selectedIDs: Set<String> { state.selectedIDs }
    var selectedFiles: [FileNode] { state.selectedFiles }
    var selectedBytes: Int { state.selectedBytes }
    var selectedTokens: Int { state.selectedTokens }
    var summary: ScanSummary { state.summary }
    var isScanning: Bool { state.isScanning }
    var status: String { state.status }

    private(set) var activeRequestID: UUID?
    private let loader: any WorkspaceLoading

    init(loader: any WorkspaceLoading = LiveWorkspaceLoader()) {
        self.loader = loader
    }

    func scan(rootURL: URL, preferences: AppPreferences.Values) async {
        guard AppPreferences.validate(maxFileSizeKB: preferences.maxFileSizeKB) == .valid else {
            state.status = "Correct the maximum file size before scanning."
            return
        }

        let requestID = UUID()
        let preserveSelection = rootNode != nil
        activeRequestID = requestID
        var scanningState = state
        scanningState.rootURL = rootURL
        scanningState.isScanning = true
        scanningState.status = "Scanning…"
        state = scanningState

        do {
            let result = try await loader.load(rootURL: rootURL, preferences: preferences)
            accept(result, requestID: requestID, preserveSelection: preserveSelection)
        } catch {
            guard activeRequestID == requestID else { return }
            var failedState = state
            failedState.isScanning = false
            failedState.status = error.localizedDescription
            state = failedState
        }
    }

    func accept(_ result: TreeLoadResult, requestID: UUID, preserveSelection: Bool) {
        guard activeRequestID == requestID else { return }

        let files = Self.flattenFiles(result.root)
        let availableIDs = Set(files.map(\.id))
        let nextSelectedIDs = preserveSelection
            ? state.selectedIDs.intersection(availableIDs)
            : availableIDs
        let selection = Self.selectionSnapshot(files: files, selectedIDs: nextSelectedIDs)

        var acceptedState = state
        acceptedState.rootNode = result.root
        acceptedState.allFiles = files
        acceptedState.selectedIDs = nextSelectedIDs
        acceptedState.selectedFiles = selection.files
        acceptedState.selectedBytes = selection.bytes
        acceptedState.selectedTokens = selection.tokens
        acceptedState.summary = result.summary
        acceptedState.isScanning = false
        acceptedState.status = nextSelectedIDs.isEmpty
            ? "Loaded \(files.count) files"
            : "Loaded \(files.count) files, \(nextSelectedIDs.count) selected"
        state = acceptedState
    }

    func toggle(node: FileNode, isOn: Bool) {
        let availableIDs = Set(state.allFiles.map(\.id))
        let nodeIDs = Set(Self.gatherFileIDs(node)).intersection(availableIDs)

        if isOn {
            setSelectionIDs(state.selectedIDs.union(nodeIDs))
        } else {
            setSelectionIDs(state.selectedIDs.subtracting(nodeIDs))
        }
    }

    func clearSelection() {
        setSelectionIDs([])
    }

    func selectAll() {
        setSelectionIDs(Set(state.allFiles.map(\.id)))
    }

    private nonisolated static func flattenFiles(_ node: FileNode) -> [FileNode] {
        ([node] + node.children.flatMap(flattenFiles))
            .filter { !$0.isDirectory }
            .sorted {
                $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
            }
    }

    private nonisolated static func gatherFileIDs(_ node: FileNode) -> [String] {
        node.isDirectory ? node.children.flatMap(gatherFileIDs) : [node.id]
    }

    private nonisolated static func selectionSnapshot(
        files: [FileNode],
        selectedIDs: Set<String>
    ) -> (files: [FileNode], bytes: Int, tokens: Int) {
        let selectedFiles = files.filter { selectedIDs.contains($0.id) }
        return (
            selectedFiles,
            selectedFiles.reduce(0) { $0 + $1.sizeBytes },
            selectedFiles.reduce(0) { $0 + $1.tokenCount }
        )
    }

    private func setSelectionIDs(_ selectedIDs: Set<String>) {
        let selection = Self.selectionSnapshot(files: state.allFiles, selectedIDs: selectedIDs)
        var selectionState = state
        selectionState.selectedIDs = selectedIDs
        selectionState.selectedFiles = selection.files
        selectionState.selectedBytes = selection.bytes
        selectionState.selectedTokens = selection.tokens
        state = selectionState
    }
}
