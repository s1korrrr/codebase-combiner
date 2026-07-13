import SwiftUI

struct ScanningIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.16), lineWidth: 7)
            Circle()
                .trim(from: 0.08, to: 0.72)
                .stroke(
                    AngularGradient(colors: [.accentColor.opacity(0.15), .accentColor, .accentColor.opacity(0.25)], center: .center),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 1.1).repeatForever(autoreverses: false), value: isAnimating)
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
                .scaleEffect(isAnimating && !reduceMotion ? 1.08 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: isAnimating)
        }
        .frame(width: 58, height: 58)
        .onAppear { isAnimating = true }
    }
}

struct EmptyStateSymbol: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 38, weight: .medium))
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
    }
}
