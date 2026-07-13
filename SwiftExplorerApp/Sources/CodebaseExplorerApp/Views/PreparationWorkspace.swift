import SwiftUI

struct PreparationWorkspace: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var controller: AppController
    @ObservedObject private var preferences: AppPreferences
    @ObservedObject private var workspace: WorkspaceStore
    @ObservedObject private var output: OutputStore

    let layout: AdaptiveWorkspaceLayout

    private let estimator = TokenEstimator()

    init(controller: AppController, layout: AdaptiveWorkspaceLayout) {
        _controller = ObservedObject(wrappedValue: controller)
        _preferences = ObservedObject(wrappedValue: controller.preferences)
        _workspace = ObservedObject(wrappedValue: controller.workspace)
        _output = ObservedObject(wrappedValue: controller.output)
        self.layout = layout
    }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    workspaceControls
                    PromptEditor(
                        prompt: promptBinding,
                        tokenCount: estimator.estimateTokens(in: output.promptPrefix)
                    )

                    if preferences.values.showFilters {
                        FiltersView(
                            allowList: allowListBinding,
                            excludeList: excludeListBinding,
                            maxFileSizeKB: maxFileSizeBinding,
                            skipHidden: skipHiddenBinding,
                            onApply: controller.refresh
                        )
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    }

                    selectedFiles
                    StatsBar(
                        totalFiles: workspace.allFiles.count,
                        selectedFiles: workspace.selectedFiles.count,
                        tokenCount: workspace.selectedTokens + estimator.estimateTokens(in: output.promptPrefix),
                        bytes: workspace.selectedBytes
                    )
                }
                .padding(16)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: preferences.values.showFilters)
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Prepare Output")
                    .font(.title3.weight(.semibold))
                Text(controller.displayStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if workspace.isScanning || output.isBuilding {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(workspace.isScanning ? "Scanning Workspace" : "Building Output")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var workspaceControls: some View {
        if layout.controlArrangement == .expanded {
            HStack(spacing: 12) {
                selectionActions
                Spacer(minLength: 8)
                outputOptions
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                selectionActions
                outputOptions
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var selectionActions: some View {
        HStack(spacing: 8) {
            Button(action: workspace.selectAll) {
                Label("Select All", systemImage: "checkmark.circle")
            }
            .disabled(workspace.rootNode == nil || workspace.allFiles.isEmpty)
            .help(WorkspaceAccessibility.selectAllHelp(hasWorkspace: workspace.rootNode != nil))
            .accessibilityHint(WorkspaceAccessibility.selectAllHelp(hasWorkspace: workspace.rootNode != nil))

            Button(action: workspace.clearSelection) {
                Label("Clear Selection", systemImage: "xmark.circle")
            }
            .disabled(workspace.selectedIDs.isEmpty)
            .help(WorkspaceAccessibility.clearSelectionHelp(hasSelection: !workspace.selectedIDs.isEmpty))
            .accessibilityHint(WorkspaceAccessibility.clearSelectionHelp(hasSelection: !workspace.selectedIDs.isEmpty))
        }
        .controlSize(.small)
    }

    private var outputOptions: some View {
        HStack(spacing: 10) {
            Picker("Output Format", selection: formatBinding) {
                Text("Markdown").tag(CombinedOutputFormat.markdown)
                Text("Plain Text").tag(CombinedOutputFormat.plainText)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            .accessibilityHint("Changes the format of the combined output")

            Toggle(isOn: filtersBinding) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
            .toggleStyle(.button)
            .help(preferences.values.showFilters ? "Hide filters" : "Show filters")
            .accessibilityHint(preferences.values.showFilters ? "Hide workspace filters" : "Show workspace filters")
        }
        .controlSize(.small)
    }

    private var selectedFiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Selected Files", systemImage: "checkmark.circle")
                    .font(.headline)
                Spacer()
                Text("\(workspace.selectedFiles.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Divider()

            if workspace.selectedFiles.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Select files in the sidebar to build an output.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(workspace.selectedFiles, id: \.id) { file in
                            selectedFileRow(file)
                            if file.id != workspace.selectedFiles.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 190)
                .accessibilityLabel("Selected Files")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func selectedFileRow(_ file: FileNode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(file.relativePath)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text("\(file.tokenCount) tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(file.displaySize)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private var promptBinding: Binding<String> {
        Binding(get: { output.promptPrefix }, set: { output.promptPrefix = $0 })
    }

    private var formatBinding: Binding<CombinedOutputFormat> {
        Binding(get: { output.format }, set: { output.format = $0 })
    }

    private var filtersBinding: Binding<Bool> {
        Binding(
            get: { preferences.values.showFilters },
            set: { newValue in
                if newValue != preferences.values.showFilters {
                    controller.toggleFilters()
                }
            }
        )
    }

    private var allowListBinding: Binding<String> {
        Binding(get: { preferences.values.allowList }, set: { preferences.values.allowList = $0 })
    }

    private var excludeListBinding: Binding<String> {
        Binding(get: { preferences.values.excludeList }, set: { preferences.values.excludeList = $0 })
    }

    private var maxFileSizeBinding: Binding<Double> {
        Binding(get: { preferences.values.maxFileSizeKB }, set: { preferences.values.maxFileSizeKB = $0 })
    }

    private var skipHiddenBinding: Binding<Bool> {
        Binding(get: { preferences.values.skipHidden }, set: { preferences.values.skipHidden = $0 })
    }
}
