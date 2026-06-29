import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @SceneStorage("cc_sidebarWidth") private var sidebarWidth: Double = 320
    @SceneStorage("cc_previewWidth") private var previewWidth: Double = 460
    @State private var sidebarDragStartWidth: Double = 320
    @State private var previewDragStartWidth: Double = 460
    @State private var isResizingSidebar = false
    @State private var isResizingPreview = false
    @State private var rootURL: URL?
    @State private var rootNode: FileNode?
    @State private var allFileNodes: [FileNode] = []
    @State private var selectedFileNodes: [FileNode] = []
    @State private var selectedBytes = 0
    @State private var selectedTokenCount = 0
    @State private var selectedIDs: Set<String> = []
    @State private var promptPrefix: String = ""
    @AppStorage("cc_allowListString") private var allowListString: String = "swift,js,ts,tsx,jsx,md,txt,py"
    @AppStorage("cc_excludeListString") private var excludeListString: String = "png,jpg,jpeg,gif,mp4,zip,bin,lock"
    @AppStorage("cc_maxFileSizeKB") private var maxFileSizeKB: Double = 512
    @AppStorage("cc_skipHidden") private var skipHidden = true
    @AppStorage("cc_outputMarkdown") private var outputMarkdown = true
    @State private var isLoading = false
    @State private var status: String = "Pick a folder to start."
    @AppStorage("cc_showFilters") private var showFilters = true
    @State private var showToast = false
    @State private var reloadDebounce: DispatchWorkItem?
    @State private var toastDismissWorkItem: DispatchWorkItem?
    @State private var draftSaveWorkItem: DispatchWorkItem?
    @State private var activeReloadID: UUID?
    @State private var restoredDraft: ClipboardDraft?

    private let loader = TreeLoader()
    private let estimator = TokenEstimator()
    private let outputBuilder = CombinedOutputBuilder()
    private let draftStore = ClipboardDraftStore()
    private let previewCharacterLimit = 20000

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
                .background(.bar)

            sidebarGrabber

            centerWorkspace

            previewGrabber

            outputPreview
                .frame(width: previewWidth)
                .background(.bar)
        }
        .frame(minWidth: 1320, minHeight: 820)
        .overlay(alignment: .topTrailing) {
            if showToast {
                copyToast
                    .padding(.top, 18)
                    .padding(.trailing, 22)
                    .transition(.opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: showToast)
        .onChange(of: maxFileSizeKB) { _ in scheduleReload() }
        .onChange(of: skipHidden) { _ in scheduleReload() }
        .onChange(of: allowListString) { _ in scheduleReload() }
        .onChange(of: excludeListString) { _ in scheduleReload() }
        .onChange(of: promptPrefix) { _ in scheduleDraftSave() }
        .onChange(of: outputMarkdown) { _ in scheduleDraftSave() }
        .onAppear(perform: loadRestoredDraft)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Codebase Combiner")
                    .font(.title2.weight(.semibold))
                Text(rootURL?.path ?? "Choose a workspace to begin.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Label(status, systemImage: isLoading ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: 280, alignment: .trailing)
                .contentTransition(.opacity)
        }
        .padding(.bottom, 2)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Workspace", systemImage: "sidebar.left")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button(action: pickFolder) {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Choose folder")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            explorer

            sidebarFooter
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 10) {
            Divider()

            HStack(spacing: 8) {
                Button {
                    openWindow(id: "settings")
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    AppLinks.openSupportPage()
                } label: {
                    Label("Support", systemImage: "heart.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
            }
            .controlSize(.small)
        }
        .padding(12)
    }

    private var controlBar: some View {
        ViewThatFits(in: .horizontal) {
            fullControlBar
            compactControlBar
        }
        .padding(10)
        .frame(minHeight: 50)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .hoverLift()
    }

    private var fullControlBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                actionButton("Choose", systemImage: "folder", action: pickFolder)
                    .keyboardShortcut("o", modifiers: [.command])

                actionButton("Refresh", systemImage: "arrow.clockwise", action: reloadTree)
                    .disabled(rootURL == nil || isLoading)
                    .keyboardShortcut("r", modifiers: [.command])
            }
            .frame(minWidth: 220, alignment: .leading)

            Divider()
                .frame(height: 20)

            HStack(spacing: 8) {
                actionButton("All", systemImage: "checkmark.circle", action: selectAll)
                    .disabled(rootNode == nil)
                actionButton("Clear", systemImage: "xmark.circle", action: clearSelection)
                    .disabled(selectedIDs.isEmpty)
            }
            .frame(width: 154, alignment: .leading)

            Divider()
                .frame(height: 20)

            HStack(spacing: 8) {
                if selectedFileNodes.isEmpty {
                    actionButton("Copy", systemImage: "doc.on.doc", action: {})
                        .disabled(true)
                } else {
                    Button(action: copyCombined) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }

                actionButton("Save", systemImage: "square.and.arrow.down", action: saveCombined)
                    .disabled(selectedFileNodes.isEmpty)
                    .keyboardShortcut("s", modifiers: [.command])
            }
            .frame(width: 176, alignment: .leading)

            Spacer()

            HStack(spacing: 10) {
                Picker("Output", selection: $outputMarkdown) {
                    Text("Markdown").tag(true)
                    Text("Plain Text").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .labelsHidden()

                Toggle(isOn: $showFilters) {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .toggleStyle(.button)
                .frame(width: 96)
                .help("Show filters")
            }
            .frame(width: 276, alignment: .trailing)
        }
    }

    private var compactControlBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                actionButton("Choose", systemImage: "folder", action: pickFolder)
                    .keyboardShortcut("o", modifiers: [.command])
                actionButton("Refresh", systemImage: "arrow.clockwise", action: reloadTree)
                    .disabled(rootURL == nil || isLoading)
                    .keyboardShortcut("r", modifiers: [.command])
                actionButton("All", systemImage: "checkmark.circle", action: selectAll)
                    .disabled(rootNode == nil)
                actionButton("Clear", systemImage: "xmark.circle", action: clearSelection)
                    .disabled(selectedIDs.isEmpty)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if selectedFileNodes.isEmpty {
                    actionButton("Copy", systemImage: "doc.on.doc", action: {})
                        .disabled(true)
                } else {
                    Button(action: copyCombined) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }

                actionButton("Save", systemImage: "square.and.arrow.down", action: saveCombined)
                    .disabled(selectedFileNodes.isEmpty)
                    .keyboardShortcut("s", modifiers: [.command])

                Spacer(minLength: 0)

                Picker("Output", selection: $outputMarkdown) {
                    Text("Markdown").tag(true)
                    Text("Plain Text").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .labelsHidden()

                Toggle(isOn: $showFilters) {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .toggleStyle(.button)
                .frame(width: 96)
                .help("Show filters")
            }
        }
    }

    private var promptEditor: some View {
        PromptEditor(prompt: $promptPrefix, tokenCount: estimator.estimateTokens(in: promptPrefix))
    }

    private var filters: some View {
        FiltersView(
            allowList: $allowListString,
            excludeList: $excludeListString,
            maxFileSizeKB: $maxFileSizeKB,
            skipHidden: $skipHidden,
            onApply: reloadTree
        )
    }

    private var explorer: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ScanningIndicator()
                    Text("Scanning files...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let root = rootNode {
                List {
                    OutlineGroup([root], children: \.childrenOrNil) { node in
                        FileNodeRow(
                            node: node,
                            isSelected: isSelected(node),
                            onToggle: { newValue in toggle(node: node, isOn: newValue) }
                        )
                    }
                }
                .listStyle(.sidebar)
                .animation(reduceMotion ? nil : .spring(response: 0.25), value: selectedIDs)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            } else {
                VStack(spacing: 10) {
                    EmptyStateSymbol(systemImage: "folder.badge.questionmark")
                    Text("No folder selected")
                        .font(.title3.weight(.semibold))
                    Text("Pick a folder to view files and token counts.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(action: pickFolder) {
                        Label("Choose Folder", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 6)
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86), value: isLoading)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86), value: rootNode?.id)
    }

    private var statsBar: some View {
        StatsBar(
            totalFiles: allFileNodes.count,
            selectedFiles: selectedFileNodes.count,
            tokenCount: selectedTokenCount + estimator.estimateTokens(in: promptPrefix),
            bytes: selectedBytes
        )
    }

    private var selectedPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Selected Files", systemImage: "checkmark.circle")
                    .font(.headline)
                Spacer()
                Text("\(selectedFileNodes.count) items")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if !selectedFileNodes.isEmpty {
                    Button {
                        copyCombined()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))

                    Button {
                        saveCombined()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }

            if selectedFileNodes.isEmpty {
                VStack(spacing: 8) {
                    EmptyStateSymbol(systemImage: "doc.text.magnifyingglass")
                    Text("No Files Selected")
                        .font(.headline)
                    Text("Choose files from the sidebar to preview the combined payload.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 128)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(selectedFileNodes, id: \.id) { file in
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text(file.relativePath)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text("\(file.tokenCount) tkn")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Text(file.displaySize)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(2)
                }
                .frame(maxHeight: 180)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(12)
        .appSurface(cornerRadius: 12, emphasized: !selectedFileNodes.isEmpty)
        .hoverLift()
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84), value: selectedIDs)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84), value: selectedFileNodes.isEmpty)
    }

    @ViewBuilder
    private var restoredDraftBanner: some View {
        if let draft = restoredDraft {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Last ready copy is saved")
                        .font(.headline)
                    Text("\(draft.fileCount) files • \(draft.formatLabel) • \(draft.tokenCount) tokens • \(formattedDraftDate(draft.generatedAt))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    copyRestoredDraft()
                } label: {
                    Label("Copy Last", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    clearRestoredDraft()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .appSurface(cornerRadius: 12, emphasized: selectedFileNodes.isEmpty)
            .hoverLift()
            .transition(.opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98)))
        }
    }

    private var centerWorkspace: some View {
        VStack(spacing: 12) {
            header
            controlBar
            ScrollView {
                VStack(spacing: 12) {
                    promptEditor
                    if showFilters {
                        filters
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98, anchor: .top)),
                                removal: .opacity.combined(with: .move(edge: .top))
                            ))
                    }
                    selectedPreview
                    restoredDraftBanner
                    statsBar
                }
                .padding(.bottom, 16)
            }
        }
        .padding(16)
        .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: showFilters)
    }

    private var outputPreview: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Label("Output Preview", systemImage: "doc.text.magnifyingglass")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text(outputPreviewSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if rawOutputPreviewText.isEmpty {
                VStack(spacing: 10) {
                    EmptyStateSymbol(systemImage: "doc.plaintext")
                    Text("Nothing selected")
                        .font(.headline)
                    Text("Select files in the workspace to preview the exact payload.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Label(outputPreviewFormatLabel, systemImage: outputPreviewFormatIcon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if selectedFileNodes.isEmpty {
                            Button {
                                copyRestoredDraft()
                            } label: {
                                Label("Copy Last", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Button {
                                copyCombined()
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button {
                                saveCombined()
                            } label: {
                                Label("Save", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)

                    Divider()

                    ScrollView([.vertical, .horizontal]) {
                        Text(outputPreviewText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .lineSpacing(2)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .background(.quaternary.opacity(0.2))
                }
            }
        }
        .frame(minWidth: 300, maxHeight: .infinity)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var copyToast: some View {
        Label("Copied", systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(.primary)
            .appSurface(cornerRadius: 20, emphasized: true)
    }

    // MARK: - Live reload helpers

    private func scheduleReload() {
        guard rootURL != nil else { return }
        reloadDebounce?.cancel()
        let work = DispatchWorkItem { reloadTree() }
        reloadDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func scheduleDraftSave() {
        guard !selectedFileNodes.isEmpty else { return }
        draftSaveWorkItem?.cancel()
        let work = DispatchWorkItem {
            persistCurrentDraft(updateStatus: false)
        }
        draftSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
    }

    private func loadRestoredDraft() {
        do {
            restoredDraft = try draftStore.load()
            if restoredDraft != nil, selectedFileNodes.isEmpty {
                status = "Last ready copy restored"
                AppLog.persistence.info("Restored last ready payload")
            }
        } catch {
            status = "Could not restore last copy: \(error.localizedDescription)"
            AppLog.persistence.error("Failed to restore last ready payload: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistCurrentDraft(updateStatus: Bool) {
        guard !selectedFileNodes.isEmpty else { return }
        let text = combinedText()
        persistDraft(text: text, updateStatus: updateStatus)
    }

    private func persistDraft(text: String, updateStatus: Bool) {
        let draft = ClipboardDraft(
            text: text,
            format: outputMarkdown ? .markdown : .plainText,
            fileCount: selectedFileNodes.count,
            tokenCount: selectedTokenCount + estimator.estimateTokens(in: promptPrefix),
            byteCount: selectedBytes,
            rootPath: rootURL?.path,
            generatedAt: Date()
        )

        let store = draftStore
        DispatchQueue.global(qos: .utility).async {
            do {
                try store.save(draft)
                DispatchQueue.main.async {
                    restoredDraft = draft
                    AppLog.persistence.info("Saved last ready payload with \(draft.fileCount, privacy: .public) files")
                    if updateStatus {
                        status = "Saved last ready copy"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    status = "Could not save last copy: \(error.localizedDescription)"
                    AppLog.persistence.error("Failed to save last ready payload: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func copyRestoredDraft() {
        guard let draft = restoredDraft else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(draft.text, forType: .string)
        status = "Copied last ready payload"
        showCopiedToast()
    }

    private func clearRestoredDraft() {
        do {
            try draftStore.clear()
            restoredDraft = nil
            status = "Cleared saved payload"
            AppLog.persistence.info("Cleared saved payload")
        } catch {
            status = "Could not clear saved payload: \(error.localizedDescription)"
            AppLog.persistence.error("Failed to clear saved payload: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func formattedDraftDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Selection helpers

    private func isSelected(_ node: FileNode) -> Bool {
        if node.isDirectory {
            let childIDs = gatherFileIDs(node)
            guard !childIDs.isEmpty else { return false }
            let selectedChildren = childIDs.filter { selectedIDs.contains($0) }
            return selectedChildren.count == childIDs.count
        }
        return selectedIDs.contains(node.id)
    }

    private func toggle(node: FileNode, isOn: Bool) {
        let ids = gatherFileIDs(node)
        if isOn {
            selectedIDs.formUnion(ids)
        } else {
            selectedIDs.subtract(ids)
        }
        refreshSelectionSnapshot()
    }

    private func gatherFileIDs(_ node: FileNode) -> [String] {
        if node.isDirectory {
            return node.children.flatMap { gatherFileIDs($0) }
        }
        return [node.id]
    }

    private func selectAll() {
        selectedIDs = Set(allFileNodes.map(\.id))
        refreshSelectionSnapshot()
    }

    private func clearSelection() {
        selectedIDs.removeAll()
        refreshSelectionSnapshot(autosave: false)
    }

    // MARK: - Data helpers

    private nonisolated static func flatten(_ node: FileNode) -> [FileNode] {
        [node] + node.children.flatMap { flatten($0) }
    }

    private nonisolated static func flattenFiles(_ node: FileNode) -> [FileNode] {
        flatten(node)
            .filter { !$0.isDirectory }
            .sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
    }

    private func refreshSelectionSnapshot(autosave: Bool = true) {
        let files = allFileNodes.filter { selectedIDs.contains($0.id) }
        selectedFileNodes = files
        selectedBytes = files.reduce(0) { $0 + $1.sizeBytes }
        selectedTokenCount = files.reduce(0) { $0 + $1.tokenCount }
        if autosave {
            scheduleDraftSave()
        }
    }

    private func parseExtensions(_ text: String) -> Set<String> {
        let delimiters = CharacterSet(charactersIn: ",;|\n\t ")
        return Set(text
            .lowercased()
            .components(separatedBy: delimiters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty })
    }

    // MARK: - Actions

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a workspace root"

        if panel.runModal() == .OK, let url = panel.url {
            rootURL = url
            reloadTree()
        }
    }

    private func reloadTree() {
        guard let url = rootURL else { return }
        let reloadID = UUID()
        let previousSelectedIDs = selectedIDs
        let shouldPreserveSelection = rootNode != nil
        activeReloadID = reloadID
        isLoading = true
        status = "Scanning…"
        AppLog.scan.info("Started workspace scan")

        let allow = parseExtensions(allowListString)
        let exclude = parseExtensions(excludeListString)
        let maxSize = Int(maxFileSizeKB)
        let skipHiddenFiles = skipHidden

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tree = try loader.loadTree(
                    rootURL: url,
                    allowList: allow,
                    excludeList: exclude,
                    maxFileSizeKB: maxSize,
                    skipHidden: skipHiddenFiles
                )
                let files = Self.flattenFiles(tree)
                DispatchQueue.main.async {
                    guard activeReloadID == reloadID else { return }
                    let availableIDs = Set(files.map(\.id))
                    let nextSelectedIDs = shouldPreserveSelection
                        ? previousSelectedIDs.intersection(availableIDs)
                        : availableIDs
                    rootNode = tree
                    allFileNodes = files
                    selectedIDs = nextSelectedIDs
                    refreshSelectionSnapshot()
                    isLoading = false
                    status = nextSelectedIDs.isEmpty ? "Loaded \(files.count) files" : "Loaded \(files.count) files, \(nextSelectedIDs.count) selected"
                    AppLog.scan.info("Completed workspace scan with \(files.count, privacy: .public) files")
                }
            } catch {
                DispatchQueue.main.async {
                    guard activeReloadID == reloadID else { return }
                    isLoading = false
                    status = error.localizedDescription
                    AppLog.scan.error("Workspace scan failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func copyCombined() {
        let text = combinedText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "Copied to clipboard"
        AppLog.export.info("Copied combined payload with \(selectedFileNodes.count, privacy: .public) files")
        persistDraft(text: text, updateStatus: false)
        showCopiedToast()
    }

    private func saveCombined() {
        let panel = NSSavePanel()
        let markdownType = UTType(filenameExtension: "md") ?? .plainText
        panel.allowedContentTypes = [outputMarkdown ? markdownType : .plainText]
        panel.nameFieldStringValue = outputMarkdown ? "combined.md" : "combined.txt"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let text = combinedText()
                try text.write(to: url, atomically: true, encoding: .utf8)
                persistDraft(text: text, updateStatus: false)
                status = "Saved to \(url.lastPathComponent)"
                AppLog.export.info("Saved combined payload with \(selectedFileNodes.count, privacy: .public) files")
            } catch {
                status = "Failed to save: \(error.localizedDescription)"
                AppLog.export.error("Failed to save combined payload: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func combinedText() -> String {
        outputBuilder.build(
            promptPrefix: promptPrefix,
            files: selectedFileNodes,
            format: outputMarkdown ? .markdown : .plainText
        )
    }

    private var outputPreviewSubtitle: String {
        if !selectedFileNodes.isEmpty {
            return "\(selectedFileNodes.count) files • \(selectedTokenCount + estimator.estimateTokens(in: promptPrefix)) tokens"
        }
        if let draft = restoredDraft {
            return "\(draft.fileCount) files • last copy"
        }
        return "No selection"
    }

    private var outputPreviewFormatLabel: String {
        if !selectedFileNodes.isEmpty {
            return outputMarkdown ? "Markdown" : "Plain Text"
        }
        return restoredDraft?.formatLabel ?? "Preview"
    }

    private var outputPreviewFormatIcon: String {
        outputPreviewFormatLabel == "Markdown" ? "curlybraces.square" : "text.alignleft"
    }

    private var rawOutputPreviewText: String {
        if !selectedFileNodes.isEmpty {
            return combinedText()
        }
        return restoredDraft?.text ?? ""
    }

    private var outputPreviewText: String {
        let text = rawOutputPreviewText
        guard text.count > previewCharacterLimit else { return text }
        return "\(text.prefix(previewCharacterLimit))\n\n… Preview truncated for speed. Copy or save to use the full output."
    }

    private func showCopiedToast() {
        showToast = true
        toastDismissWorkItem?.cancel()
        let work = DispatchWorkItem {
            showToast = false
        }
        toastDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    private var sidebarGrabber: some View {
        splitGrabber(isActive: isResizingSidebar) { value in
            if !isResizingSidebar {
                sidebarDragStartWidth = sidebarWidth
            }
            isResizingSidebar = true
            let newWidth = sidebarDragStartWidth + Double(value.translation.width)
            sidebarWidth = min(max(220, newWidth), 600)
        } onEnded: { _ in
            isResizingSidebar = false
        }
    }

    private var previewGrabber: some View {
        splitGrabber(isActive: isResizingPreview) { value in
            if !isResizingPreview {
                previewDragStartWidth = previewWidth
            }
            isResizingPreview = true
            let newWidth = previewDragStartWidth - Double(value.translation.width)
            previewWidth = min(max(300, newWidth), 760)
        } onEnded: { _ in
            isResizingPreview = false
        }
    }

    private func splitGrabber(
        isActive: Bool,
        onChanged: @escaping (DragGesture.Value) -> Void,
        onEnded: @escaping (DragGesture.Value) -> Void
    ) -> some View {
        Rectangle()
            .fill(isActive ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.25))
            .frame(width: 1)
            .frame(width: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(onChanged)
                    .onEnded(onEnded)
            )
            .overlay(
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 1),
                alignment: .trailing
            )
    }
}

// MARK: - App entry

@main
struct CodebaseExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Codebase Combiner") {
            ContentView()
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Support") {
                Button("Buy Me a Coffee") {
                    AppLinks.openSupportPage()
                }
            }
        }

        Settings {
            SettingsView()
        }

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        false
    }

    func application(_: NSApplication, shouldSaveSecureApplicationState _: NSCoder) -> Bool {
        false
    }

    func application(_: NSApplication, shouldRestoreSecureApplicationState _: NSCoder) -> Bool {
        false
    }

    func application(_: NSApplication, shouldSaveApplicationState _: NSCoder) -> Bool {
        false
    }

    func application(_: NSApplication, shouldRestoreApplicationState _: NSCoder) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Ensure the app accepts keyboard input even when launched as a plain executable.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppLog.lifecycle.info("Application finished launching")
        DispatchQueue.main.async { self.disableWindowRestoration() }
        DispatchQueue.main.async { self.recenterOffscreenWindowsIfNeeded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.disableWindowRestoration() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.recenterOffscreenWindowsIfNeeded() }
    }

    @MainActor
    private func disableWindowRestoration() {
        for window in NSApp.windows {
            window.isRestorable = false
            window.restorationClass = nil
            window.disableSnapshotRestoration()
        }
    }

    @MainActor
    private func recenterOffscreenWindowsIfNeeded() {
        for window in NSApp.windows where window.isVisible {
            guard !window.frame.isEmpty else { continue }
            let isVisible = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
            if !isVisible, let screen = NSScreen.main {
                window.setFrameOrigin(CGPoint(
                    x: screen.visibleFrame.midX - window.frame.width / 2,
                    y: screen.visibleFrame.midY - window.frame.height / 2
                ))
            }
        }
    }
}
