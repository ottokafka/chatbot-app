import Foundation
import FSRS

/// Shared pure helpers for practice scaffolding (normalize, eligibility, script).
/// No MainActor — safe to call from any context / future unit tests.
enum PracticeScaffolding {
    /// Same semantics as the historical PracticeCardGenerator.normalizeKey — trim + lowercased.
    /// Internal spaces are preserved after lowercasing (`"Good Morning"` → `"good morning"`).
    static func normalizeFrontKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// True if `text` contains any CJK ideograph (Unified + Ext A + Compatibility).
    static func containsCJK(_ text: String) -> Bool {
        text.containsChineseCharacters
    }

    /// Language-aware front length filter for scaffold tokens (K11).
    /// CJK: max character count. Latin: max characters or whitespace tokens.
    static func isEligibleKnownFront(_ front: String) -> Bool {
        let trimmed = front.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if containsCJK(trimmed) {
            return trimmed.count <= PracticeGenerationConfig.maxKnownFrontCharacterCountCJK
        }
        let tokens = trimmed.split { $0.isWhitespace }.map(String.init)
        guard tokens.count <= PracticeGenerationConfig.maxKnownFrontTokenCountLatin else { return false }
        return trimmed.count <= PracticeGenerationConfig.maxKnownFrontCharacterCountLatin
    }

    /// Soft script preference: congruent with majority seed-front script class first.
    /// Ties (equal CJK vs Latin seed counts) leave order unchanged. Incongruent fronts
    /// remain included after congruent ones (not hard-dropped).
    static func preferScriptCongruent(_ cards: [Flashcard], seedFronts: [String]) -> [Flashcard] {
        guard !seedFronts.isEmpty, !cards.isEmpty else { return cards }

        var cjkSeedCount = 0
        var latinSeedCount = 0
        for front in seedFronts {
            if containsCJK(front) {
                cjkSeedCount += 1
            } else {
                latinSeedCount += 1
            }
        }
        guard cjkSeedCount != latinSeedCount else { return cards }

        let preferCJK = cjkSeedCount > latinSeedCount
        var congruent: [Flashcard] = []
        var incongruent: [Flashcard] = []
        congruent.reserveCapacity(cards.count)
        incongruent.reserveCapacity(cards.count)
        for card in cards {
            if containsCJK(card.front) == preferCJK {
                congruent.append(card)
            } else {
                incongruent.append(card)
            }
        }
        return congruent + incongruent
    }
}

/// Resolves a ranked, capped list of known vocabulary fronts for sentence scaffolding.
enum PracticeKnownVocabulary {
    /// Builds known scaffold fronts from the library.
    ///
    /// - Known heuristic: `kind == .vocab` and (`state != .new` OR `reps >= 1`).
    /// - Rank: stability ↓, reps ↓, front length ↑, normalized key α.
    /// - Soft script congruence with `seedFrontsForScriptHint`.
    /// - Dedup by `normalizeFrontKey`; caps by `limit` and cumulative `maxChars`.
    /// - **Does not** exclude seed IDs (multi-seed packs may reuse co-seed fronts).
    static func resolve(
        from flashcards: [Flashcard],
        seedFrontsForScriptHint: [String] = [],
        limit: Int = PracticeGenerationConfig.maxKnownScaffoldWords,
        maxChars: Int = PracticeGenerationConfig.maxKnownScaffoldChars
    ) -> [String] {
        // Custom/test callers may pass limit <= 0; do not emit a free first front.
        guard limit > 0 else { return [] }

        let vocab = flashcards.filter { $0.kind == .vocab }
        let known = vocab.filter { card in
            card.fsrsCard.state != .new || card.fsrsCard.reps >= 1
        }

        let ranked = known.sorted { a, b in
            if a.fsrsCard.stability != b.fsrsCard.stability {
                return a.fsrsCard.stability > b.fsrsCard.stability
            }
            if a.fsrsCard.reps != b.fsrsCard.reps {
                return a.fsrsCard.reps > b.fsrsCard.reps
            }
            // Rank by trimmed length so length order matches emitted scaffold tokens.
            let aLen = a.front.trimmingCharacters(in: .whitespacesAndNewlines).count
            let bLen = b.front.trimmingCharacters(in: .whitespacesAndNewlines).count
            if aLen != bLen {
                return aLen < bLen
            }
            return PracticeScaffolding.normalizeFrontKey(a.front)
                < PracticeScaffolding.normalizeFrontKey(b.front)
        }
        let ordered = PracticeScaffolding.preferScriptCongruent(
            ranked,
            seedFronts: seedFrontsForScriptHint
        )

        var seen = Set<String>()
        var fronts: [String] = []
        var charBudget = 0
        fronts.reserveCapacity(min(limit, ordered.count))

        for card in ordered {
            if fronts.count >= limit { break }
            let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
            guard PracticeScaffolding.isEligibleKnownFront(front) else { continue }
            let key = PracticeScaffolding.normalizeFrontKey(front)
            guard seen.insert(key).inserted else { continue }
            // +1 for JSON separator slack between list items
            let added = front.count + (fronts.isEmpty ? 0 : 1)
            if charBudget + added > maxChars { continue }
            fronts.append(front)
            charBudget += added
        }
        return fronts
    }
}

/// Sparse-escape beginner content words (K5) for prompts; PR3 also uses these in soft validation.
enum PracticeUltraCommonBeginnerContent {
    /// Ultra-high-frequency English content words for a basic SVO frame when known is sparse.
    static let english: [String] = [
        "water", "person", "people", "eat", "go", "want", "like", "see",
        "come", "have", "good", "bad", "big", "small", "day", "home",
        "food", "book", "friend", "time", "make", "say", "know", "think"
    ]

    /// Ultra-high-frequency Chinese content words for a basic SVO frame when known is sparse.
    static let chinese: [String] = [
        "水", "人", "吃", "去", "要", "看", "来", "有", "好", "大",
        "小", "天", "家", "书", "朋友", "说", "会", "很", "不", "在"
    ]

    /// Comma-separated list for interpolating into sparse system-prompt bullets.
    static func promptList(for appLanguage: AppLanguage) -> String {
        let words = appLanguage == .zh ? chinese : english
        return words.joined(separator: appLanguage == .zh ? "、" : ", ")
    }
}
