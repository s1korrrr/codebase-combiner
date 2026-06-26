import SwiftUI

struct StatsBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let totalFiles: Int
    let selectedFiles: Int
    let tokenCount: Int
    let bytes: Int

    var body: some View {
        HStack(spacing: 10) {
            stat(label: "Files", value: "\(selectedFiles)/\(totalFiles)", systemImage: "doc.text")
            stat(label: "Tokens", value: "\(tokenCount)", systemImage: "number")
            stat(label: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file), systemImage: "internaldrive")
        }
        .padding(10)
        .appSurface(cornerRadius: 12)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: selectedFiles)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: tokenCount)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: bytes)
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
                    .id(value)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .hoverLift()
    }
}
