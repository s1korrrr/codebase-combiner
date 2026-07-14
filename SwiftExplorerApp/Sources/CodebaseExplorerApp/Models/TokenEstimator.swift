import Foundation

/// Lightweight token estimator tuned for GPT-style models.
/// Uses an empirical ratio of ~4 characters per token as a fast approximation.
struct TokenEstimator {
    func estimateTokens(in text: String) -> Int {
        let scalarCount = text.unicodeScalars.count
        return max(1, Int(Double(scalarCount) / 4.0))
    }
}

enum PromptTokenPolicy {
    static func estimate(in prompt: String) -> Int {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return TokenEstimator().estimateTokens(in: trimmed)
    }
}
