import SwiftUI

struct WorkspaceSidebar: View {
    @ObservedObject private var controller: AppController
    @ObservedObject private var workspace: WorkspaceStore
    @State private var isShowingScanDetails = false

    init(controller: AppController) {
        _controller = ObservedObject(wrappedValue: controller)
        _workspace = ObservedObject(wrappedValue: controller.workspace)
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider()
            sidebarContent
        }
        .navigationTitle("Workspace")
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.rootURL?.lastPathComponent ?? "No Workspace")
                        .font(.headline)
                        .lineLimit(1)
                    Text(workspace.rootURL?.path ?? "Choose a folder to begin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                Button(action: controller.chooseFolder) {
                    Label("Choose Folder", systemImage: "folder.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .help("Choose a workspace folder")
                .accessibilityLabel("Choose Folder")
                .accessibilityHint("Choose a workspace folder")

                Button(action: controller.refresh) {
                    Label("Refresh Workspace", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .disabled(!controller.commandState.canRefresh)
                .help(controller.commandState.refreshHelp)
                .accessibilityLabel("Refresh Workspace")
                .accessibilityHint(controller.commandState.refreshHelp)
            }

            if workspace.summary.skippedCount > 0 {
                scanSummary
            }

            if let failure = workspace.scanFailure {
                scanFailure(failure)
            }
        }
        .padding(12)
    }

    private var scanSummary: some View {
        DisclosureGroup(isExpanded: $isShowingScanDetails) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ScanSkipReason.allCases, id: \.self) { reason in
                    let count = workspace.summary.count(for: reason)
                    if count > 0 {
                        HStack {
                            Text(reason.label)
                            Spacer()
                            Text("\(count)")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 5)
        } label: {
            Label(
                WorkspaceAccessibility.partialScanSummary(skippedCount: workspace.summary.skippedCount),
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .help("Show skipped-item counts by reason. Paths are not shown.")
        .accessibilityHint("Shows skipped-item counts by reason without revealing paths")
    }

    private func scanFailure(_ failure: WorkspaceScanFailure) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Workspace scan failed", systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
            Text(failure.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                Button(action: controller.retryFailedScan) {
                    Label("Retry Scan", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(!workspace.canRetryFailedScan)
                .help(workspace.canRetryFailedScan ? "Retry the failed workspace scan" : "Wait for the current scan to finish")
                .accessibilityHint("Retries the failed scan with the same folder and validated filters")

                Button(action: controller.chooseFolder) {
                    Label("Choose Another Folder", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .help("Choose a different workspace folder")
                .accessibilityHint("Opens a folder picker without changing source files")
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var sidebarContent: some View {
        if workspace.isScanning {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning workspace…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if let root = workspace.rootNode {
            List {
                OutlineGroup([root], children: \.childrenOrNil) { node in
                    FileNodeRow(
                        node: node,
                        isSelected: isSelected(node),
                        onToggle: { workspace.toggle(node: node, isOn: $0) }
                    )
                }
            }
            .listStyle(.sidebar)
            .accessibilityLabel("Workspace Files")
        } else {
            VStack(spacing: 10) {
                EmptyStateSymbol(systemImage: "folder.badge.questionmark")
                Text("No folder selected")
                    .font(.headline)
                Text("Choose a folder to review its files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Choose Folder", action: controller.chooseFolder)
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func isSelected(_ node: FileNode) -> Bool {
        let fileIDs = gatherFileIDs(node)
        return !fileIDs.isEmpty && fileIDs.allSatisfy(workspace.selectedIDs.contains)
    }

    private func gatherFileIDs(_ node: FileNode) -> [String] {
        node.isDirectory ? node.children.flatMap { gatherFileIDs($0) } : [node.id]
    }
}

private extension ScanSkipReason {
    var label: String {
        switch self {
        case .hidden:
            "Hidden"
        case .excluded:
            "Excluded"
        case .disallowed:
            "Not included"
        case .oversized:
            "Too large"
        case .binary:
            "Binary"
        case .symbolicLink:
            "Symbolic links"
        case .unreadable:
            "Unreadable"
        case .workspaceLimit:
            "Workspace limit"
        }
    }
}
