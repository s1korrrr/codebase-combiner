enum WorkspaceLayoutMode: Equatable {
    case compact
    case regular
    case wide
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
