import SwiftUI

struct RecoveredOutputView: View {
    @ObservedObject var store: OutputStore

    var body: some View {
        Group {
            if let draft = store.recoveredDraft {
                recoveredContent(draft)
            } else if store.canClearRecoveredOutput {
                recoveryErrorState
            }
        }
        .confirmationDialog(
            "Clear saved output?",
            isPresented: clearConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Clear Saved Output", role: .destructive) {
                Task {
                    await store.confirmClearRecoveredOutput()
                }
            }
            Button("Cancel", role: .cancel) {
                store.cancelClearRecoveredOutput()
            }
        } message: {
            Text("This removes only Codebase Combiner’s recoverable copy. Source files are not changed.")
        }
    }

    private func recoveredContent(_ draft: ClipboardDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Saved Output", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Text("Recovered content stays hidden until you reveal it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(draft.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                metadata("Files", value: "\(draft.fileCount)")
                metadata("Format", value: draft.formatLabel)
                metadata("Tokens", value: "\(draft.tokenCount)")
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                Button {
                    if store.isRecoveredContentRevealed {
                        store.hideRecoveredOutput()
                    } else {
                        store.revealRecoveredOutput()
                    }
                } label: {
                    Label(
                        store.isRecoveredContentRevealed ? "Hide Last Output" : "Reveal Last Output",
                        systemImage: store.isRecoveredContentRevealed ? "eye.slash" : "eye"
                    )
                }
                .help(store.isRecoveredContentRevealed ? "Hide the recovered source content" : "Reveal the recovered source content")
                .accessibilityHint(store.isRecoveredContentRevealed ? "Conceals the recovered source content" : "Displays potentially sensitive recovered source content")

                Button(action: store.copyRecovered) {
                    Label("Copy Last", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .help("Copy the last recoverable output without revealing it")
                .accessibilityHint("Copies the recovered output without changing whether it is visible")

                Spacer()

                Button(role: .destructive, action: store.requestClearRecoveredOutput) {
                    Label("Clear Saved Output", systemImage: "trash")
                }
                .help("Ask before clearing Codebase Combiner’s recoverable copy")
                .accessibilityHint("Opens a confirmation before removing the app-owned recovery copy")
            }
            .controlSize(.small)

            if store.isRecoveredContentRevealed {
                Divider()
                ScrollView([.vertical, .horizontal]) {
                    Text(draft.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 120)
                .accessibilityLabel("Recovered Output Content")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var recoveryErrorState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Saved output could not be read", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text("You can retry by relaunching, or clear only the unreadable app-owned recovery copy.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(role: .destructive, action: store.requestClearRecoveredOutput) {
                Label("Clear Saved Output", systemImage: "trash")
            }
            .help("Ask before clearing the unreadable recovery copy")
        }
    }

    private func metadata(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
        }
    }

    private var clearConfirmationBinding: Binding<Bool> {
        Binding(
            get: { store.isClearConfirmationPresented },
            set: { isPresented in
                if !isPresented {
                    store.cancelClearRecoveredOutput()
                }
            }
        )
    }
}
