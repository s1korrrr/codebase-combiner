import SwiftUI

struct FilterEditorValues: Equatable {
    var allowList: String
    var excludeList: String
}

enum FilterEditorAction: Equatable {
    case cancel
    case apply
}

enum FilterEditorPolicy {
    static func resolvedValues(
        original: FilterEditorValues,
        draft: FilterEditorValues,
        action: FilterEditorAction
    ) -> FilterEditorValues {
        action == .apply ? draft : original
    }
}

struct FiltersView: View {
    @Binding var allowList: String
    @Binding var excludeList: String
    @Binding var maxFileSizeKB: Double
    @Binding var skipHidden: Bool
    var onApply: () -> Void

    @State private var showFilterSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.headline)
                Spacer()
                Button {
                    showFilterSheet = true
                } label: {
                    Label("Editor", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .help("Open filter editor")
                .accessibilityHint("Opens a larger editor for include and exclude extensions")
            }

            ViewThatFits(in: .horizontal) {
                wideFilterLayout
                compactFilterLayout
            }

            Text("Filters auto-apply after a short pause. Use Apply for an immediate refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showFilterSheet) {
            FilterEditorSheet(
                allowList: $allowList,
                excludeList: $excludeList,
                onApply: {
                    onApply()
                }
            )
        }
    }

    // MARK: - Subviews

    private var wideFilterLayout: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow(alignment: .bottom) {
                filterField(
                    title: "Include",
                    placeholder: "swift,js,ts,tsx,jsx,md,txt,py",
                    text: $allowList
                )

                filterField(
                    title: "Exclude",
                    placeholder: "png,jpg,jpeg,gif,mp4,zip,bin,lock",
                    text: $excludeList
                )

                filterActions
            }

            GridRow(alignment: .bottom) {
                sizeCard
                    .gridCellColumns(2)

                Color.clear
                    .frame(width: 210, height: 1)
            }
        }
    }

    private var compactFilterLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            filterField(
                title: "Include",
                placeholder: "swift,js,ts,tsx,jsx,md,txt,py",
                text: $allowList
            )

            filterField(
                title: "Exclude",
                placeholder: "png,jpg,jpeg,gif,mp4,zip,bin,lock",
                text: $excludeList
            )

            sizeCard
            filterActions
                .frame(maxWidth: 260, alignment: .leading)
        }
    }

    private func filterField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onApply)
                .frame(minWidth: 220)
                .accessibilityLabel("\(title) extensions")
                .accessibilityHint("Enter extensions separated by commas or spaces")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sizeCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Max file size")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Slider(value: $maxFileSizeKB, in: 32 ... 8192, step: 32)
                    .frame(minWidth: 220)
                    .accessibilityLabel("Maximum file size")
                    .accessibilityValue("\(Int(maxFileSizeKB)) kilobytes")
                    .accessibilityHint("Files larger than this value are skipped")
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(maxFileSizeKB)) KB")
                        .font(.headline.monospacedDigit())
                    Text(String(format: "%.2f MB", maxFileSizeKB / 1024))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Stepper(value: $maxFileSizeKB, in: 32 ... 8192, step: 64) { EmptyView() }
                    .labelsHidden()
                    .accessibilityLabel("Adjust maximum file size")
                    .accessibilityValue("\(Int(maxFileSizeKB)) kilobytes")
                TextField("KB", value: $maxFileSizeKB, format: .number)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Maximum file size in kilobytes")
                    .accessibilityHint("Enter a value from 32 to 8192")
                Spacer(minLength: 0)
            }

            if case let .invalid(message) = AppPreferences.validate(maxFileSizeKB: maxFileSizeKB) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Invalid maximum file size. \(message)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Skip hidden files")
                Spacer(minLength: 10)
                Toggle("Skip hidden files", isOn: $skipHidden)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Skip hidden files")
            }

            Button(action: onApply) {
                Label("Apply", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(AppPreferences.validate(maxFileSizeKB: maxFileSizeKB) != .valid)
            .help(applyHelp)
            .accessibilityHint(applyHelp)
        }
        .frame(width: 210, alignment: .leading)
    }

    private var applyHelp: String {
        switch AppPreferences.validate(maxFileSizeKB: maxFileSizeKB) {
        case .valid:
            "Apply filters and refresh the workspace"
        case let .invalid(message):
            message
        }
    }
}

// MARK: - Pop-out sheet for reliable text input

private struct FilterEditorSheet: View {
    @Binding var allowList: String
    @Binding var excludeList: String
    var onApply: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FilterEditorValues

    init(
        allowList: Binding<String>,
        excludeList: Binding<String>,
        onApply: @escaping () -> Void
    ) {
        _allowList = allowList
        _excludeList = excludeList
        self.onApply = onApply
        _draft = State(initialValue: FilterEditorValues(
            allowList: allowList.wrappedValue,
            excludeList: excludeList.wrappedValue
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Edit Filters", systemImage: "line.3.horizontal.decrease.circle")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Only include extensions (comma / space separated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.allowList)
                    .frame(minHeight: 70)
                    .font(.body.monospaced())
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.25)))
                    .accessibilityLabel("Included extensions")
                    .accessibilityHint("Enter extensions separated by commas or spaces")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Exclude extensions (comma / space separated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.excludeList)
                    .frame(minHeight: 70)
                    .font(.body.monospaced())
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.25)))
                    .accessibilityLabel("Excluded extensions")
                    .accessibilityHint("Enter extensions separated by commas or spaces")
            }

            HStack {
                Spacer()
                Button("Cancel") { finish(.cancel) }
                Button("Apply") {
                    finish(.apply)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 420)
        .onAppear {
            draft = FilterEditorValues(allowList: allowList, excludeList: excludeList)
        }
    }

    private func finish(_ action: FilterEditorAction) {
        let original = FilterEditorValues(allowList: allowList, excludeList: excludeList)
        let resolved = FilterEditorPolicy.resolvedValues(
            original: original,
            draft: draft,
            action: action
        )
        if action == .apply {
            allowList = resolved.allowList
            excludeList = resolved.excludeList
            onApply()
        }
        dismiss()
    }
}
