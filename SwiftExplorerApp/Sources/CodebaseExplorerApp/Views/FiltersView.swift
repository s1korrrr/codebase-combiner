import SwiftUI

struct FiltersView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var allowList: String
    @Binding var excludeList: String
    @Binding var maxFileSizeKB: Double
    @Binding var skipHidden: Bool
    var onApply: () -> Void

    @State private var applyDebounce: DispatchWorkItem?
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
            }

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

            Text("Filters auto-apply after a short pause. Use Apply for an immediate refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .appSurface(cornerRadius: 12)
        .hoverLift()
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86), value: skipHidden)
        .sheet(isPresented: $showFilterSheet) {
            FilterEditorSheet(
                allowList: $allowList,
                excludeList: $excludeList,
                onApply: {
                    applyDebounce?.cancel()
                    onApply()
                }
            )
        }
    }

    // MARK: - Subviews

    private func filterField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    applyDebounce?.cancel()
                    onApply()
                }
                .onChange(of: text.wrappedValue) { _ in scheduleApply() }
                .frame(minWidth: 220)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(maxFileSizeKB)) KB")
                        .font(.headline.monospacedDigit())
                    Text(String(format: "%.2f MB", maxFileSizeKB / 1024))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Stepper(value: $maxFileSizeKB, in: 32 ... 8192, step: 64) { EmptyView() }
                    .labelsHidden()
                TextField("KB", value: $maxFileSizeKB, format: .number)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Skip hidden files")
                    .lineLimit(1)
                Spacer(minLength: 10)
                Toggle("Skip hidden files", isOn: $skipHidden)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .frame(height: 24)

            Button(action: onApply) {
                Label("Apply", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .frame(width: 210, alignment: .leading)
    }

    // MARK: - Helpers

    private func scheduleApply() {
        applyDebounce?.cancel()
        let work = DispatchWorkItem { onApply() }
        applyDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}

// MARK: - Pop-out sheet for reliable text input

private struct FilterEditorSheet: View {
    @Binding var allowList: String
    @Binding var excludeList: String
    var onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Edit Filters", systemImage: "line.3.horizontal.decrease.circle")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Only include extensions (comma / space separated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $allowList)
                    .frame(minHeight: 70)
                    .font(.body.monospaced())
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.25)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Exclude extensions (comma / space separated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $excludeList)
                    .frame(minHeight: 70)
                    .font(.body.monospaced())
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.25)))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply") {
                    onApply()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 420)
    }
}
