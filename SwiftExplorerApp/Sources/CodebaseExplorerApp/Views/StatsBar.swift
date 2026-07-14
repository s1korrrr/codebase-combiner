import SwiftUI

struct StatsBar: View {
    let totalFiles: Int
    let selectedFiles: Int
    let tokenCount: Int
    let bytes: Int

    var body: some View {
        HStack(spacing: 10) {
            stat(label: "Files", value: "\(selectedFiles)/\(totalFiles)", systemImage: "doc.text")
            Divider()
            stat(label: "Tokens", value: "\(tokenCount)", systemImage: "number")
            Divider()
            stat(label: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file), systemImage: "internaldrive")
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private func stat(label: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.monospacedDigit())
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
