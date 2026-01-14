import SwiftUI

struct PromptEditor: View {
    @Binding var prompt: String
    let tokenCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Prompt prefix (will be placed on top)", systemImage: "rectangle.and.pencil.and.ellipsis")
                    .font(.headline)
                Spacer()
                Text("~\(tokenCount) tokens")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            TextEditor(text: $prompt)
                .frame(minHeight: 120)
                .padding(10)
                .background(.ultraThickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
