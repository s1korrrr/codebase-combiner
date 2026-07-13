import SwiftUI

struct OutputInspector: View {
    @ObservedObject private var controller: AppController
    @ObservedObject private var workspace: WorkspaceStore
    @ObservedObject private var output: OutputStore

    private let previewCharacterLimit = 20000

    init(controller: AppController) {
        _controller = ObservedObject(wrappedValue: controller)
        _workspace = ObservedObject(wrappedValue: controller.workspace)
        _output = ObservedObject(wrappedValue: controller.output)
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
            Label(output.format == .markdown ? "Markdown" : "Plain Text", systemImage: output.format == .markdown ? "curlybraces.square" : "text.alignleft")
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
                RecoveredOutputView(store: output)
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
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: controller.copy) {
                    Label("Copy Combined Output", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.commandState.canExport)
                .help(controller.commandState.copyHelp)
                .accessibilityHint(controller.commandState.copyHelp)

                Button(action: controller.save) {
                    Label("Save Combined Output", systemImage: "square.and.arrow.down")
                }
                .disabled(!controller.commandState.canExport)
                .help(controller.commandState.saveHelp)
                .accessibilityHint(controller.commandState.saveHelp)
            }
            .controlSize(.small)
            .functionalChrome()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if payload.count > previewCharacterLimit {
                Label(
                    "Preview shows the first \(previewCharacterLimit.formatted()) characters. Copy and Save use the full output.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            ScrollView([.vertical, .horizontal]) {
                Text(previewText(payload))
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

    private func previewText(_ payload: String) -> String {
        guard payload.count > previewCharacterLimit else { return payload }
        return String(payload.prefix(previewCharacterLimit))
    }
}
