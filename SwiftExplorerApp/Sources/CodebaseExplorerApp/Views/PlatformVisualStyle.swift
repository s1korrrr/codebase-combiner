import SwiftUI

enum WorkspaceControlArrangement: Equatable {
    case compact
    case expanded
}

enum InspectorActionArrangement: Equatable {
    case compact
    case adaptive
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

    var inspectorContentWidthAtMinimum: Double {
        inspectorMinimumWidth - 32
    }

    var inspectorActionArrangement: InspectorActionArrangement {
        mode == .wide ? .adaptive : .compact
    }
}

enum InspectorPanePresentation {
    static func width(layout: AdaptiveWorkspaceLayout) -> Double {
        layout.mode == .wide ? layout.inspectorIdealWidth : layout.inspectorMinimumWidth
    }

    static func offset(isPresented: Bool, layout: AdaptiveWorkspaceLayout) -> Double {
        isPresented ? 0 : width(layout: layout) + 1
    }
}

enum SidebarPanePresentation {
    static func width(layout: AdaptiveWorkspaceLayout) -> Double {
        switch layout.mode {
        case .compact:
            220
        case .regular:
            240
        case .wide:
            280
        }
    }

    static func offset(isPresented: Bool, layout: AdaptiveWorkspaceLayout) -> Double {
        isPresented ? 0 : -(width(layout: layout) + 1)
    }
}

struct WorkspacePaneFrame: Equatable {
    let x: Double
    let width: Double

    var maxX: Double {
        x + width
    }

    func intersects(_ other: WorkspacePaneFrame) -> Bool {
        x < other.maxX && other.x < maxX
    }
}

struct WorkspacePaneFrames: Equatable {
    let sidebar: WorkspacePaneFrame
    let preparation: WorkspacePaneFrame
    let inspector: WorkspacePaneFrame
}

enum WorkspacePaneGeometry {
    static func frames(
        totalWidth: Double,
        layout: AdaptiveWorkspaceLayout,
        isSidebarPresented: Bool,
        isInspectorPresented: Bool
    ) -> WorkspacePaneFrames {
        let sidebarWidth = SidebarPanePresentation.width(layout: layout) + 1
        let inspectorWidth = InspectorPanePresentation.width(layout: layout) + 1
        let leadingInset = isSidebarPresented ? sidebarWidth : 0
        let trailingInset = isInspectorPresented ? inspectorWidth : 0
        let preparationWidth = max(0, totalWidth - leadingInset - trailingInset)

        return WorkspacePaneFrames(
            sidebar: WorkspacePaneFrame(x: 0, width: sidebarWidth),
            preparation: WorkspacePaneFrame(x: leadingInset, width: preparationWidth),
            inspector: WorkspacePaneFrame(x: totalWidth - inspectorWidth, width: inspectorWidth)
        )
    }
}

enum WorkspaceAccessibility {
    static func selectAllHelp(hasWorkspace: Bool, hasIncludableFiles: Bool) -> String {
        if !hasWorkspace {
            return "Choose a workspace before selecting all files."
        }
        if !hasIncludableFiles {
            return "This workspace has no includable files to select."
        }
        return "Select all files"
    }

    static func clearSelectionHelp(hasSelection: Bool) -> String {
        hasSelection ? "Clear the current file selection" : "Select at least one file before clearing the selection."
    }

    static func partialScanSummary(skippedCount: Int) -> String {
        let noun = skippedCount == 1 ? "item was" : "items were"
        return "\(skippedCount) \(noun) skipped during the scan. Review counts by reason; paths stay private."
    }
}

struct FunctionalChrome: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
