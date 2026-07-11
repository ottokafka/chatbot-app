import Foundation

/// Pure helper: which **user**-produced target fronts appear in learner text.
/// Not MainActor — unit-testable from any context.
///
/// Do **not** reuse `PracticeScaffoldValidator.diagnose` here — that scores assistant
/// leakage against an allowlist, not “did each target appear in user text.”
enum SpeakingTargetTracker {
    /// Returns the subset of `targets` found in `userText` (order-preserving).
    ///
    /// - English: multi-word fronts = substring on normalized text; single tokens = word-boundary / token match.
    /// - Chinese: longest-first substring; auto-hit only for fronts with **length > 1**
    ///   (avoids false positives on 是 / 在 / 好).
    static func hits(
        in userText: String,
        targets: [String],
        script: SpeakingScript
    ) -> [String] {
        let trimmedUser = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty else { return [] }

        var found: [String] = []
        var seenKeys = Set<String>()

        switch script {
        case .english:
            let normalizedText = PracticeScaffolding.normalizeFrontKey(trimmedUser)
            let tokens = Set(
                PracticeScaffoldValidator.englishTokens(from: trimmedUser).map {
                    PracticeScaffolding.normalizeFrontKey($0)
                }
            )
            for target in targets {
                let key = PracticeScaffolding.normalizeFrontKey(target)
                guard !key.isEmpty, seenKeys.insert(key).inserted else { continue }
                if englishMatches(normalizedText: normalizedText, tokens: tokens, targetKey: key) {
                    found.append(target)
                }
            }
        case .chinese:
            let normalizedText = PracticeScaffolding.normalizeFrontKey(trimmedUser)
            // Longest-first matching avoids partial credit issues; still report original order.
            let candidates = targets.compactMap { target -> (original: String, key: String)? in
                let key = PracticeScaffolding.normalizeFrontKey(target)
                guard !key.isEmpty else { return nil }
                return (target, key)
            }
            // Prefer longer keys when scanning; emit unique hits in original target order later.
            var hitKeys = Set<String>()
            let longestFirst = candidates.sorted { $0.key.count > $1.key.count }
            for item in longestFirst {
                // Auto-hit only for fronts length > 1 (skip 是/在/好 single-char false positives).
                guard item.key.count > 1 else { continue }
                if normalizedText.contains(item.key) {
                    hitKeys.insert(item.key)
                }
            }
            for target in targets {
                let key = PracticeScaffolding.normalizeFrontKey(target)
                guard !key.isEmpty, hitKeys.contains(key), seenKeys.insert(key).inserted else {
                    continue
                }
                found.append(target)
            }
        }

        return found
    }

    /// Targets not yet covered (order-preserving). Comparison uses `normalizeFrontKey`.
    static func remaining(targets: [String], covered: Set<String>) -> [String] {
        let coveredKeys = Set(covered.map { PracticeScaffolding.normalizeFrontKey($0) })
        var seen = Set<String>()
        var result: [String] = []
        for target in targets {
            let key = PracticeScaffolding.normalizeFrontKey(target)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            if !coveredKeys.contains(key) {
                result.append(target)
            }
        }
        return result
    }

    // MARK: - English matching

    /// Multi-word: substring on normalized text. Single token: exact token match (word boundary).
    private static func englishMatches(
        normalizedText: String,
        tokens: Set<String>,
        targetKey: String
    ) -> Bool {
        let hasWhitespace = targetKey.contains { $0.isWhitespace }
        if hasWhitespace {
            return normalizedText.contains(targetKey)
        }
        return tokens.contains(targetKey)
    }
}
