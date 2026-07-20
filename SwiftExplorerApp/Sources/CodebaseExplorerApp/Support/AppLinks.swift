import AppKit
import Foundation

enum AppLinks {
    static let supportURL = URL(
        string: "https://github.com/rsitech-ai/codebase-combiner/blob/main/docs/support.md"
    )!
    static let privacyPolicyURL = URL(
        string: "https://github.com/rsitech-ai/codebase-combiner/blob/main/docs/privacy-policy.md"
    )!

    @MainActor
    static func openSupportPage() {
        NSWorkspace.shared.open(supportURL)
    }

    @MainActor
    static func openPrivacyPolicy() {
        NSWorkspace.shared.open(privacyPolicyURL)
    }
}
