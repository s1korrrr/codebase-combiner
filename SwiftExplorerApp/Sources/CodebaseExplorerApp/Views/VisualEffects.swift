import SwiftUI

struct AppSurface: ViewModifier {
    var cornerRadius: CGFloat = 12
    var isEmphasized = false

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isEmphasized ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isEmphasized ? 0.16 : 0.08), radius: isEmphasized ? 18 : 10, x: 0, y: isEmphasized ? 10 : 5)
    }
}

struct HoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering && !reduceMotion ? 1.004 : 1)
            .shadow(color: .black.opacity(isHovering ? 0.14 : 0.05), radius: isHovering ? 12 : 5, x: 0, y: isHovering ? 5 : 2)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

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

extension View {
    func appSurface(cornerRadius: CGFloat = 12, emphasized: Bool = false) -> some View {
        modifier(AppSurface(cornerRadius: cornerRadius, isEmphasized: emphasized))
    }

    func hoverLift() -> some View {
        modifier(HoverLift())
    }
}
