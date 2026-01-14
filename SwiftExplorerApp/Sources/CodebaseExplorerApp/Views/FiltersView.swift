import SwiftUI

struct FiltersView: View {
    @Binding var allowList: String
    @Binding var excludeList: String
    @Binding var maxFileSizeKB: Double
    @Binding var skipHidden: Bool
    var onApply: () -> Void

    @State private var applyDebounce: DispatchWorkItem?
    @State private var showFilterSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Only include extensions")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("swift,js,ts,tsx,jsx,md,txt,py", text: $allowList)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                applyDebounce?.cancel()
                                onApply()
                            }
                            .onChange(of: allowList) { _ in scheduleApply() }
                            .frame(minWidth: 280)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Exclude extensions")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("png,jpg,jpeg,gif,mp4,zip,bin,lock", text: $excludeList)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                applyDebounce?.cancel()
                                onApply()
                            }
                            .onChange(of: excludeList) { _ in scheduleApply() }
                            .frame(minWidth: 260)
                    }

                    sizeCard

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Skip hidden", isOn: $skipHidden)
                            .toggleStyle(.switch)
                        Button(action: onApply) {
                            Label("Apply", systemImage: "line.3.horizontal.decrease.circle")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command])

                        Button("Pop out editor…") {
                            showFilterSheet = true
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                Text("Press Apply to refresh. Filters also auto-apply after a short pause when extensions, size, or hidden change.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var sizeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Max file size")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Slider(value: $maxFileSizeKB, in: 32 ... 8192, step: 32)
                    .frame(width: 200)
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
            }
        }
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
            Text("Edit filters")
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
