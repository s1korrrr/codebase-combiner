import AppKit
import SwiftUI

struct PromptEditor: View {
    @FocusState private var isPromptFocused: Bool

    @Binding var prompt: String
    let tokenCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Prompt Prefix", systemImage: "rectangle.and.pencil.and.ellipsis")
                    .font(.headline)
                Spacer()
                Text("~\(tokenCount) tokens")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $prompt)
                    .frame(minHeight: 90, idealHeight: 110)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(prompt.isEmpty)
                    .focused($isPromptFocused)
                    .accessibilityLabel("Prompt Prefix")
                    .accessibilityHint("Optional instructions placed before the selected file contents")

                if prompt.isEmpty {
                    Text("Optional instructions to place above the selected files...")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 17)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 90, idealHeight: 110)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.45))
            }
        }
        .onAppear {
            isPromptFocused = false
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPromptFocused = false
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }
}
