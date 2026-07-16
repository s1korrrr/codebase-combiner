import SwiftUI

struct EmptyStateSymbol: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 38, weight: .medium))
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
    }
}
