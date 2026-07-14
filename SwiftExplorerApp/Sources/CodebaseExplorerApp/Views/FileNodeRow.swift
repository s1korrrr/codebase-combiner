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
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.body.weight(node.isDirectory ? .semibold : .regular))
                            .lineLimit(1)
                        Text(node.relativePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .buttonStyle(.plain)
            .accessibilityLabel(node.isDirectory ? "Select folder \(node.name)" : "Select file \(node.name)")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint(node.isDirectory ? "Changes the selection for every file in this folder" : "Changes whether this file is included")

            Spacer()

            if !node.isDirectory {
                Text("\(node.tokenCount) tkn")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}
