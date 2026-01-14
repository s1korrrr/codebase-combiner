import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var sidebarWidth: CGFloat = 320
    @State private var isResizingSidebar = false
    @State private var rootURL: URL?
    @State private var rootNode: FileNode?
    @State private var selectedIDs: Set<UUID> = []
    @State private var promptPrefix: String = ""
    @AppStorage("cc_allowListString") private var allowListString: String = "swift,js,ts,tsx,jsx,md,txt,py"
    @AppStorage("cc_excludeListString") private var excludeListString: String = "png,jpg,jpeg,gif,mp4,zip,bin,lock"
    @State private var maxFileSizeKB: Double = 512
    @State private var skipHidden = true
    @State private var outputMarkdown = true
    @State private var isLoading = false
    @State private var status: String = "Pick a folder to start."
    @State private var showFilters = true
    @State private var showToast = false
    @State private var reloadDebounce: DispatchWorkItem?

    private let loader = TreeLoader()
    private let estimator = TokenEstimator()

    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.12), .teal.opacity(0.12), .pink.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)
                    .background(.ultraThickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                sidebarGrabber

                VStack(spacing: 12) {
                    header
                    controlBar
                    promptEditor
                    if showFilters { filters }
                    selectedPreview
                    statsBar
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(18)
        }
        .frame(minWidth: 1100, minHeight: 760)
        .onChange(of: maxFileSizeKB) { _ in scheduleReload() }
        .onChange(of: skipHidden) { _ in scheduleReload() }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codebase Explorer & Combiner")
                    .font(.largeTitle.weight(.semibold))
                Text("Curate files, count tokens, and ship a ready-to-paste prompt.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(status)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Workspace", systemImage: "folder")
                    .font(.headline)
                Spacer()
                Button(action: pickFolder) {
                    Image(systemName: "plus.circle")
                }
                .help("Choose folder")
            }
            explorer
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Label(rootURL?.lastPathComponent ?? "No folder", systemImage: "externaldrive")
                .foregroundStyle(rootURL == nil ? .secondary : .primary)
                .lineLimit(1)
            Button(action: reloadTree) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(rootURL == nil || isLoading)

            Divider().frame(height: 18)

            Button(action: selectAll) {
                Label("Select all", systemImage: "checkmark.circle")
            }
            .disabled(rootNode == nil)
            Button(action: clearSelection) {
                Label("Clear", systemImage: "xmark.circle")
            }
            .disabled(selectedIDs.isEmpty)

            Divider().frame(height: 18)

            Button(action: copyCombined) {
                Label("Copy combined", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedFiles.isEmpty)

            Button(action: saveCombined) {
                Label("Save…", systemImage: "square.and.arrow.down")
            }
            .disabled(selectedFiles.isEmpty)

            Spacer()

            Toggle("Markdown", isOn: $outputMarkdown)
                .toggleStyle(.switch)
            Toggle("Filters", isOn: $showFilters)
                .toggleStyle(.switch)
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
                ProgressView("Scanning files…")
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
                .animation(.spring(response: 0.25), value: selectedIDs)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No folder selected")
                        .font(.title3.weight(.semibold))
                    Text("Pick a folder to view files and token counts.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var statsBar: some View {
        StatsBar(
            totalFiles: fileNodes.count,
            selectedFiles: selectedFiles.count,
            tokenCount: selectedTokenCount + estimator.estimateTokens(in: promptPrefix),
            bytes: selectedBytes
        )
    }

    private var selectedPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Selected files", systemImage: "checkmark.circle")
                    .font(.headline)
                Spacer()
                Button("Copy") { copyCombined() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedFiles.isEmpty)
                Button("Save…") { saveCombined() }
                    .disabled(selectedFiles.isEmpty)
            }

            if selectedFiles.isEmpty {
                Text("Choose files from the left to preview your payload.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(selectedFiles.sorted { $0.relativePath < $1.relativePath }, id: \.id) { file in
                            HStack {
                                Text(file.relativePath)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(file.tokenCount) tkn")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(.quaternary.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(12)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Live reload helpers

    private func scheduleReload() {
        guard rootURL != nil else { return }
        reloadDebounce?.cancel()
        let work = DispatchWorkItem { reloadTree() }
        reloadDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
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
    }

    private func gatherFileIDs(_ node: FileNode) -> [UUID] {
        if node.isDirectory {
            return node.children.flatMap { gatherFileIDs($0) }
        }
        return [node.id]
    }

    private func selectAll() {
        selectedIDs = Set(fileNodes.map(\.id))
    }

    private func clearSelection() {
        selectedIDs.removeAll()
    }

    // MARK: - Data helpers

    private var fileNodes: [FileNode] {
        guard let root = rootNode else { return [] }
        return flatten(root).filter { !$0.isDirectory }
    }

    private var selectedFiles: [FileNode] {
        fileNodes.filter { selectedIDs.contains($0.id) }
    }

    private var selectedBytes: Int {
        selectedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    private var selectedTokenCount: Int {
        selectedFiles.reduce(0) { $0 + $1.tokenCount }
    }

    private func flatten(_ node: FileNode) -> [FileNode] {
        [node] + node.children.flatMap { flatten($0) }
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
        isLoading = true
        status = "Scanning…"

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
                DispatchQueue.main.async {
                    rootNode = tree
                    selectedIDs = Set(fileNodesIDs(from: tree))
                    isLoading = false
                    status = "Loaded \(tree.flattened.count(where: { !$0.isDirectory })) files"
                }
            } catch {
                DispatchQueue.main.async {
                    isLoading = false
                    status = error.localizedDescription
                }
            }
        }
    }

    private func fileNodesIDs(from root: FileNode) -> [UUID] {
        flatten(root).filter { !$0.isDirectory }.map(\.id)
    }

    private func copyCombined() {
        let text = combinedText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "Copied to clipboard"
        showToast = true
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
                status = "Saved to \(url.lastPathComponent)"
            } catch {
                status = "Failed to save: \(error.localizedDescription)"
            }
        }
    }

    private func combinedText() -> String {
        var blocks: [String] = []
        let prefix = promptPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prefix.isEmpty {
            blocks.append(prefix)
        }

        let sortedFiles = selectedFiles.sorted { $0.relativePath.lowercased() < $1.relativePath.lowercased() }

        for file in sortedFiles {
            guard let content = file.content else { continue }
            if outputMarkdown {
                blocks.append("## \(file.relativePath)\n\n```\(languageHint(for: file))\n\(content)\n```\n")
            } else {
                blocks.append("// File: \(file.relativePath)\n\(content)\n")
            }
        }

        return blocks.joined(separator: "\n")
    }

    private func languageHint(for file: FileNode) -> String {
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

    private var sidebarGrabber: some View {
        Rectangle()
            .fill(isResizingSidebar ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.25))
            .frame(width: 6)
            .padding(.vertical, 10)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isResizingSidebar = true
                        let newWidth = sidebarWidth + value.translation.width
                        sidebarWidth = min(max(220, newWidth), 600)
                    }
                    .onEnded { _ in
                        isResizingSidebar = false
                    }
            )
            .overlay(
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 1),
                alignment: .trailing
            )
            .padding(.horizontal, 6)
    }
}

// MARK: - App entry

@main
struct CodebaseExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        // Ensure the app accepts keyboard input even when launched as a plain executable.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
