enum WorkspaceLayoutMode: Equatable {
    case compact
    case regular
    case wide
}

enum WindowContentSizePolicy {
    static let minimumWidth = 864.0
    static let minimumHeight = 520.0
}

enum WorkspaceLayoutPolicy {
    static func mode(for width: Double) -> WorkspaceLayoutMode {
        if width < 960 {
            return .compact
        }
        if width < 1320 {
            return .regular
        }
        return .wide
    }
}
