import SwiftUI

struct StatsBar: View {
    let totalFiles: Int
    let selectedFiles: Int
    let tokenCount: Int
    let bytes: Int

    var body: some View {
        HStack(spacing: 18) {
            stat(label: "Files", value: "\(selectedFiles)/\(totalFiles)")
            stat(label: "Tokens", value: "\(tokenCount)")
            stat(label: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(.bar.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
        }
    }
}
