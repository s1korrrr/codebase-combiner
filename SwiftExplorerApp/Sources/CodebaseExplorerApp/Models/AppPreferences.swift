import Combine
import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    enum Validation: Equatable {
        case valid
        case invalid(String)
    }

    struct Values: Equatable, Sendable {
        var allowList = "swift,js,ts,tsx,jsx,md,txt,py"
        var excludeList = "png,jpg,jpeg,gif,mp4,zip,bin,lock"
        var maxFileSizeKB = 512.0
        var skipHidden = true
        var outputMarkdown = true
        var showFilters = true
    }

    @Published var values: Values {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        values = Values(
            allowList: defaults.string(forKey: "cc_allowListString") ?? Values().allowList,
            excludeList: defaults.string(forKey: "cc_excludeListString") ?? Values().excludeList,
            maxFileSizeKB: Self.normalizedMaximumFileSize(
                defaults.object(forKey: "cc_maxFileSizeKB") as? Double
            ),
            skipHidden: defaults.object(forKey: "cc_skipHidden") as? Bool ?? true,
            outputMarkdown: defaults.object(forKey: "cc_outputMarkdown") as? Bool ?? true,
            showFilters: defaults.object(forKey: "cc_showFilters") as? Bool ?? true
        )
    }

    nonisolated static func validate(maxFileSizeKB: Double) -> Validation {
        maxFileSizeKB.isFinite && (32 ... 8192).contains(maxFileSizeKB)
            ? .valid
            : .invalid("Enter a value from 32 to 8,192 KB.")
    }

    private nonisolated static func normalizedMaximumFileSize(_ value: Double?) -> Double {
        guard let value, validate(maxFileSizeKB: value) == .valid else { return 512 }
        return value
    }

    nonisolated static func extensionSet(from text: String) -> Set<String> {
        let delimiters = CharacterSet(charactersIn: ",;|\n\t ")
        return Set(
            text.lowercased()
                .components(separatedBy: delimiters)
                .map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                }
                .filter { !$0.isEmpty }
        )
    }

    private func save() {
        defaults.set(values.allowList, forKey: "cc_allowListString")
        defaults.set(values.excludeList, forKey: "cc_excludeListString")
        defaults.set(values.maxFileSizeKB, forKey: "cc_maxFileSizeKB")
        defaults.set(values.skipHidden, forKey: "cc_skipHidden")
        defaults.set(values.outputMarkdown, forKey: "cc_outputMarkdown")
        defaults.set(values.showFilters, forKey: "cc_showFilters")
    }
}
