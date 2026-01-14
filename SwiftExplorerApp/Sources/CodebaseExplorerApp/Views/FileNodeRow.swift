import SwiftUI

struct FileNodeRow: View {
    let node: FileNode
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { isSelected }, set: { onToggle($0) })) {
                HStack(spacing: 8) {
                    Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
                        .foregroundStyle(node.isDirectory ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.headline.weight(.medium))
                        Text(node.relativePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .buttonStyle(.plain)

            Spacer()

            if !node.isDirectory {
                Text("\(node.tokenCount) tkn")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(node.displaySize)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
