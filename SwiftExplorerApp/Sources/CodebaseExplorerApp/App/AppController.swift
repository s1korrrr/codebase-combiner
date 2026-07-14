import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct AppCommandState: Equatable {
    let hasWorkspace: Bool
    let isScanning: Bool
    let hasSelection: Bool
    let hasFreshOutput: Bool
    let hasRecoveredOutput: Bool

    init(
        hasWorkspace: Bool,
        isScanning: Bool,
        hasSelection: Bool,
        hasFreshOutput: Bool,
        hasRecoveredOutput: Bool = false
    ) {
        self.hasWorkspace = hasWorkspace
        self.isScanning = isScanning
        self.hasSelection = hasSelection
        self.hasFreshOutput = hasFreshOutput
        self.hasRecoveredOutput = hasRecoveredOutput
    }

    var canRefresh: Bool { hasWorkspace && !isScanning }
    var canExport: Bool { hasSelection && hasFreshOutput }
    var canCopyRecovered: Bool { hasRecoveredOutput }
    var copyHelp: String {
        if !hasSelection {
            return "Select at least one file to copy the combined output."
        }
        if !hasFreshOutput {
            return "Wait for the combined output to finish building."
        }
        return "Copy combined output"
    }

    var saveHelp: String {
        if !hasSelection {
            return "Select at least one file to save the combined output."
        }
        if !hasFreshOutput {
            return "Wait for the combined output to finish building."
        }
        return "Save combined output"
    }

    var copyRecoveredHelp: String {
        hasRecoveredOutput ? "Copy the last recoverable output" : "There is no recovered output to copy."
    }

    var refreshHelp: String {
        if !hasWorkspace {
            return "Choose a folder before refreshing the workspace."
        }
        if isScanning {
            return "Wait for the current workspace scan to finish."
        }
        return "Refresh workspace"
    }
}

@MainActor
final class AppController: ObservableObject {
    typealias FolderPicker = () -> URL?
    typealias SaveDestinationPicker = (CombinedOutputFormat) -> URL?

    let preferences: AppPreferences
    let workspace: WorkspaceStore
    let output: OutputStore

    @Published var isInspectorPresented = true
    @Published private(set) var displayStatus: String

    private let folderPicker: FolderPicker
    private let saveDestinationPicker: SaveDestinationPicker
    private let telemetry: any AppTelemetryRecording
    private var cancellables: Set<AnyCancellable> = []
    private var scanTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var rebuildTask: Task<Void, Never>?
    private var preferenceRescanTask: Task<Void, Never>?
    private var hasStarted = false

    var commandState: AppCommandState {
        AppCommandState(
            hasWorkspace: workspace.rootURL != nil,
            isScanning: workspace.isScanning,
            hasSelection: !workspace.selectedFiles.isEmpty,
            hasFreshOutput: output.hasFreshCurrentPayload,
            hasRecoveredOutput: output.recoveredDraft != nil
        )
    }

    static func live(dependencies: AppDependencies = AppDependencies()) -> AppController {
        let telemetry = LiveAppTelemetry.shared
        let preferences = AppPreferences(defaults: dependencies.defaults)
        return AppController(
            preferences: preferences,
            workspace: WorkspaceStore(),
            output: OutputStore(
                drafts: ClipboardDraftStore(baseDirectory: dependencies.draftBaseDirectory),
                clipboard: SystemClipboardWriter(),
                telemetry: telemetry
            ),
            folderPicker: Self.presentOpenPanel,
            saveDestinationPicker: Self.presentSavePanel,
            telemetry: telemetry
        )
    }

    init(
        preferences: AppPreferences,
        workspace: WorkspaceStore,
        output: OutputStore,
        folderPicker: @escaping FolderPicker,
        saveDestinationPicker: @escaping SaveDestinationPicker,
        telemetry: any AppTelemetryRecording = LiveAppTelemetry.shared
    ) {
        self.preferences = preferences
        self.workspace = workspace
        self.output = output
        self.folderPicker = folderPicker
        self.saveDestinationPicker = saveDestinationPicker
        self.telemetry = telemetry
        displayStatus = workspace.status
        output.format = preferences.values.outputMarkdown ? .markdown : .plainText
        bindSharedState()
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await output.loadRecoveredDraft()
    }

    func chooseFolder() {
        guard let rootURL = folderPicker() else { return }
        beginScan(rootURL: rootURL)
    }

    func refresh() {
        guard commandState.canRefresh, let rootURL = workspace.rootURL else { return }
        beginScan(rootURL: rootURL)
    }

    func copy() {
        guard commandState.canExport else { return }
        output.copyCurrent()
    }

    func copyRecovered() {
        guard commandState.canCopyRecovered else { return }
        output.copyRecovered()
    }

    func save() {
        guard commandState.canExport,
              let destination = saveDestinationPicker(output.format)
        else { return }

        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let self else { return }
            await output.saveCurrent(to: destination)
        }
    }

    func toggleFilters() {
        preferences.values.showFilters.toggle()
    }

    func toggleInspector() {
        isInspectorPresented.toggle()
    }

    @discardableResult
    func scan(rootURL: URL) async -> WorkspaceScanOutcome {
        preferenceRescanTask?.cancel()
        return await performScan(rootURL: rootURL)
    }

    private func performScan(rootURL: URL) async -> WorkspaceScanOutcome {
        let snapshot = preferences.values
        telemetry.record(.scanStarted)
        let outcome = await workspace.scan(rootURL: rootURL, preferences: snapshot)
        telemetry.record(.scanFinished(outcome))
        return outcome
    }

    private func beginScan(rootURL: URL) {
        preferenceRescanTask?.cancel()
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            _ = await performScan(rootURL: rootURL)
        }
    }

    private func bindSharedState() {
        preferences.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        workspace.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        output.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        workspace.$state
            .map(\.status)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] status in
                self?.displayStatus = status
            }
            .store(in: &cancellables)

        output.$status
            .compactMap(\.self)
            .sink { [weak self] status in
                self?.displayStatus = status
            }
            .store(in: &cancellables)

        preferences.$values
            .map(\.outputMarkdown)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] outputMarkdown in
                guard let self else { return }
                let format: CombinedOutputFormat = outputMarkdown ? .markdown : .plainText
                if output.format.rawValue != format.rawValue {
                    output.format = format
                }
            }
            .store(in: &cancellables)

        output.$format
            .map(\.rawValue)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] rawValue in
                guard let self else { return }
                let outputMarkdown = rawValue == CombinedOutputFormat.markdown.rawValue
                if preferences.values.outputMarkdown != outputMarkdown {
                    preferences.values.outputMarkdown = outputMarkdown
                }
            }
            .store(in: &cancellables)

        preferences.$values
            .map(ScanPreferences.init)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.schedulePreferenceRescan()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            workspace.$state
                .map { RebuildSource(files: $0.selectedFiles, rootPath: $0.rootURL?.path) }
                .removeDuplicates(),
            output.$promptPrefix.removeDuplicates(),
            output.$format.map(\.rawValue).removeDuplicates()
        )
        .dropFirst()
        .sink { [weak self] source, _, _ in
            self?.rebuildOutput(from: source)
        }
        .store(in: &cancellables)
    }

    private func rebuildOutput(from source: RebuildSource) {
        displayStatus = source.files.isEmpty ? workspace.status : "Building combined output…"
        output.invalidateCurrentOutput()
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            guard let self else { return }
            await output.rebuild(files: source.files, rootPath: source.rootPath)
        }
    }

    private func schedulePreferenceRescan() {
        preferenceRescanTask?.cancel()
        guard let rootURL = workspace.rootURL else { return }

        preferenceRescanTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            _ = await performScan(rootURL: rootURL)
        }
    }

    private static func presentOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a workspace root"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func presentSavePanel(format: CombinedOutputFormat) -> URL? {
        let panel = NSSavePanel()
        let markdownType = UTType(filenameExtension: "md") ?? .plainText
        panel.allowedContentTypes = [format == .markdown ? markdownType : .plainText]
        panel.nameFieldStringValue = format == .markdown ? "combined.md" : "combined.txt"
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct RebuildSource: Equatable {
    let files: [FileNode]
    let rootPath: String?
}

private struct ScanPreferences: Equatable {
    let allowList: String
    let excludeList: String
    let maxFileSizeKB: Double
    let skipHidden: Bool

    init(_ values: AppPreferences.Values) {
        allowList = values.allowList
        excludeList = values.excludeList
        maxFileSizeKB = values.maxFileSizeKB
        skipHidden = values.skipHidden
    }
}
