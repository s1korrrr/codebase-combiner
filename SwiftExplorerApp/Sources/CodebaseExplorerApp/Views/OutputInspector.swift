import SwiftUI

enum OutputInspectorPresentation {
    static func formatLabel(
        currentFormat: CombinedOutputFormat?,
        recoveredDraft: ClipboardDraft?
    ) -> String {
        if let currentFormat {
            return currentFormat == .markdown ? "Markdown" : "Plain Text"
        }
        return recoveredDraft?.formatLabel ?? "Output"
    }
}

struct OutputInspector: View {
    @ObservedObject private var controller: AppController
    @ObservedObject private var workspace: WorkspaceStore
    @ObservedObject private var output: OutputStore

    private let layout: AdaptiveWorkspaceLayout
    init(controller: AppController, layout: AdaptiveWorkspaceLayout) {
        _controller = ObservedObject(wrappedValue: controller)
        _workspace = ObservedObject(wrappedValue: controller.workspace)
        _output = ObservedObject(wrappedValue: controller.output)
        self.layout = layout
    }

    var body: some View {
        VStack(spacing: 0) {
            inspectorHeader
            Divider()
            inspectorBody
        }
        .accessibilityElement(children: .contain)
    }

    private var inspectorHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Output Inspector")
                    .font(.headline)
                Text(outputSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Label(inspectorFormatLabel, systemImage: inspectorFormatIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    @ViewBuilder
    private var inspectorBody: some View {
        if let payload = output.currentPayload {
            currentOutput(payload)
        } else if output.recoveredDraft != nil || output.canClearRecoveredOutput {
            ScrollView {
                RecoveredOutputView(
                    store: output,
                    actionArrangement: layout.inspectorActionArrangement
                )
                .padding(12)
            }
        } else {
            VStack(spacing: 9) {
                EmptyStateSymbol(systemImage: "doc.plaintext")
                Text("No Output Yet")
                    .font(.headline)
                Text("Select files to build a preview, or restore a saved output on relaunch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func currentOutput(_ payload: String) -> some View {
        let preview = OutputPreviewPolicy.presentation(for: payload)
        return VStack(spacing: 0) {
            currentActions
                .controlSize(.small)
                .functionalChrome()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            if output.canRetryPersistence {
                VStack(alignment: .leading, spacing: 6) {
                    Label("The recoverable copy could not be saved. Your full current output is still available.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: controller.retryPersistence) {
                        Label("Retry Saving Recovery", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .help("Retry saving the recoverable copy without changing the current output")
                    .accessibilityHint("Retries persistence of the same full current output")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            if let notice = preview.notice {
                Label(notice, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            ScrollView([.vertical, .horizontal]) {
                Text(preview.text)
                    .font(.system(.caption, design: .monospaced))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .accessibilityLabel("Current Combined Output")
        }
    }

    private var outputSubtitle: String {
        if output.isBuilding {
            return "Building output…"
        }
        if output.currentPayload != nil {
            return "\(workspace.selectedFiles.count) files • \(workspace.selectedTokens) file tokens"
        }
        if let draft = output.recoveredDraft {
            return "Saved \(draft.fileCount) files • content concealed"
        }
        return "No current selection"
    }

    @ViewBuilder
    private var currentActions: some View {
        if layout.inspectorActionArrangement == .compact {
            compactCurrentActions
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    copyButton(fillsWidth: false)
                    saveButton(fillsWidth: false)
                }
                compactCurrentActions
            }
        }
    }

    private var compactCurrentActions: some View {
        VStack(spacing: 8) {
            copyButton(fillsWidth: true)
            saveButton(fillsWidth: true)
        }
    }

    private func copyButton(fillsWidth: Bool) -> some View {
        Button(action: controller.copy) {
            Label("Copy Combined Output", systemImage: "doc.on.doc")
                .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!controller.commandState.canExport)
        .help(controller.commandState.copyHelp)
        .accessibilityHint(controller.commandState.copyHelp)
    }

    private func saveButton(fillsWidth: Bool) -> some View {
        Button(action: controller.save) {
            Label("Save Combined Output", systemImage: "square.and.arrow.down")
                .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        }
        .disabled(!controller.commandState.canExport)
        .help(controller.commandState.saveHelp)
        .accessibilityHint(controller.commandState.saveHelp)
    }

    private var inspectorFormatLabel: String {
        OutputInspectorPresentation.formatLabel(
            currentFormat: output.currentFormat,
            recoveredDraft: output.recoveredDraft
        )
    }

    private var inspectorFormatIcon: String {
        inspectorFormatLabel == "Markdown" ? "curlybraces.square" : "text.alignleft"
    }
}
