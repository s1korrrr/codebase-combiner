import SwiftUI

enum WorkspaceControlArrangement: Equatable {
    case compact
    case expanded
}

struct AdaptiveWorkspaceLayout: Equatable {
    let mode: WorkspaceLayoutMode

    var controlArrangement: WorkspaceControlArrangement {
        mode == .wide ? .expanded : .compact
    }

    var preparationMinimumWidth: Double {
        switch mode {
        case .compact:
            360
        case .regular:
            430
        case .wide:
            520
        }
    }

    var inspectorMinimumWidth: Double {
        mode == .wide ? 320 : 280
    }

    var inspectorIdealWidth: Double {
        switch mode {
        case .compact:
            320
        case .regular:
            360
        case .wide:
            430
        }
    }
}

enum WorkspaceAccessibility {
    static func selectAllHelp(hasWorkspace: Bool) -> String {
        hasWorkspace ? "Select all files" : "Choose a workspace before selecting all files."
    }

    static func clearSelectionHelp(hasSelection: Bool) -> String {
        hasSelection ? "Clear the current file selection" : "Select at least one file before clearing the selection."
    }

    static func partialScanSummary(skippedCount: Int) -> String {
        let noun = skippedCount == 1 ? "file was" : "files were"
        return "\(skippedCount) \(noun) skipped during the scan. Review counts by reason; file paths stay private."
    }
}

struct FunctionalChrome: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency, contrast != .increased {
            content
                .padding(8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if reduceTransparency || contrast == .increased {
            content
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                }
        } else {
            content
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

extension View {
    func functionalChrome() -> some View {
        modifier(FunctionalChrome())
    }
}
