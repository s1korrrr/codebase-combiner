import SwiftUI

enum RecoveredClearDismissalAction: Equatable {
    case cancel
    case preserveConfirmation
}

struct RecoveredClearConfirmationInteraction: Equatable {
    private(set) var isDestructiveActionCommitted = false

    mutating func commitDestructiveAction() {
        isDestructiveActionCommitted = true
    }

    mutating func finishDestructiveAction() {
        isDestructiveActionCommitted = false
    }

    func actionForDismissal() -> RecoveredClearDismissalAction {
        isDestructiveActionCommitted ? .preserveConfirmation : .cancel
    }
}

struct RecoveredOutputView: View {
    @ObservedObject private var store: OutputStore
    @State private var clearInteraction = RecoveredClearConfirmationInteraction()
    private let actionArrangement: InspectorActionArrangement

    init(
        store: OutputStore,
        actionArrangement: InspectorActionArrangement = .adaptive
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.actionArrangement = actionArrangement
    }

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
                clearInteraction.commitDestructiveAction()
                Task {
                    await store.confirmClearRecoveredOutput()
                    clearInteraction.finishDestructiveAction()
                }
            }
            Button("Cancel", role: .cancel) {
                store.cancelClearRecoveredOutput()
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("This removes only Codebase Combiner’s recoverable copy. Source files are not changed.")
        }
    }

    private func recoveredContent(_ draft: ClipboardDraft) -> some View {
        let preview = OutputPreviewPolicy.presentation(for: draft.text)
        return VStack(alignment: .leading, spacing: 10) {
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

            recoveryActions
                .controlSize(.small)

            if store.isRecoveredContentRevealed {
                Divider()
                if let notice = preview.notice {
                    Label(notice, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ScrollView([.vertical, .horizontal]) {
                    Text(preview.text)
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
            Text("Retry loading, or clear only the unreadable app-owned recovery copy.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                Task { await store.loadRecoveredDraft() }
            } label: {
                Label("Retry Loading", systemImage: "arrow.clockwise")
            }
            .help("Retry loading the recoverable output")
            .accessibilityHint("Retries reading only Codebase Combiner’s app-owned recovery copy")
            Button(role: .destructive, action: store.requestClearRecoveredOutput) {
                Label("Clear Saved Output", systemImage: "trash")
            }
            .help("Ask before clearing the unreadable recovery copy")
        }
    }

    @ViewBuilder
    private var recoveryActions: some View {
        if actionArrangement == .compact {
            compactRecoveryActions
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    revealButton(fillsWidth: false)
                    copyButton(fillsWidth: false)
                    Spacer()
                    clearButton(fillsWidth: false)
                }
                compactRecoveryActions
            }
        }
    }

    private var compactRecoveryActions: some View {
        VStack(spacing: 8) {
            revealButton(fillsWidth: true)
            copyButton(fillsWidth: true)
            clearButton(fillsWidth: true)
        }
    }

    private func revealButton(fillsWidth: Bool) -> some View {
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
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        }
        .help(store.isRecoveredContentRevealed ? "Hide the recovered source content" : "Reveal the recovered source content")
        .accessibilityHint(store.isRecoveredContentRevealed ? "Conceals the recovered source content" : "Displays potentially sensitive recovered source content")
    }

    private func copyButton(fillsWidth: Bool) -> some View {
        Button(action: store.copyRecovered) {
            Label("Copy Last", systemImage: "doc.on.clipboard")
                .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .help("Copy the last recoverable output without revealing it")
        .accessibilityHint("Copies the recovered output without changing whether it is visible")
    }

    private func clearButton(fillsWidth: Bool) -> some View {
        Button(role: .destructive, action: store.requestClearRecoveredOutput) {
            Label("Clear Saved Output", systemImage: "trash")
                .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        }
        .help("Ask before clearing Codebase Combiner’s recoverable copy")
        .accessibilityHint("Opens a confirmation before removing the app-owned recovery copy")
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
                if !isPresented, clearInteraction.actionForDismissal() == .cancel {
                    store.cancelClearRecoveredOutput()
                }
            }
        )
    }
}
