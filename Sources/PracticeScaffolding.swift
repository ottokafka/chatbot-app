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

    /// Majority seed-front script class (K12).
    /// - `true` when CJK seeds strictly outnumber Latin
    /// - `false` when Latin seeds strictly outnumber CJK
    /// - `nil` when `seedFronts` is empty or counts are tied (mixed / ambiguous)
    static func majoritySeedFrontsPreferCJK(_ seedFronts: [String]) -> Bool? {
        guard !seedFronts.isEmpty else { return nil }
        var cjkSeedCount = 0
        var latinSeedCount = 0
        for front in seedFronts {
            if containsCJK(front) {
                cjkSeedCount += 1
            } else {
                latinSeedCount += 1
            }
        }
        guard cjkSeedCount != latinSeedCount else { return nil }
        return cjkSeedCount > latinSeedCount
    }

    /// Soft script preference: congruent with majority seed-front script class first.
    /// Ties (equal CJK vs Latin seed counts) leave order unchanged. Incongruent fronts
    /// remain included after congruent ones (not hard-dropped).
    static func preferScriptCongruent(_ cards: [Flashcard], seedFronts: [String]) -> [Flashcard] {
        guard !cards.isEmpty, let preferCJK = majoritySeedFrontsPreferCJK(seedFronts) else {
            return cards
        }

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

    /// Sparse-escape beginner examples keyed by **majority seed-front script** (K12), not UI language.
    ///
    /// - CJK-majority seeds → Chinese list
    /// - Latin-majority seeds → English list
    /// - Empty / tied (mixed) → both lists (separated by ` · `)
    ///
    /// `appLanguage` only controls list-separator style in the prompt wrapper language
    /// (、vs `, `). PR3 allowlists can still use `english` / `chinese` sets directly.
    static func promptList(forSeedFronts seedFronts: [String], appLanguage: AppLanguage) -> String {
        let sep = appLanguage == .zh ? "、" : ", "
        switch PracticeScaffolding.majoritySeedFrontsPreferCJK(seedFronts) {
        case .some(true):
            return chinese.joined(separator: sep)
        case .some(false):
            return english.joined(separator: sep)
        case .none:
            // Mixed or empty: expose both sets so the model can pick script-congruent words.
            return english.joined(separator: sep) + " · " + chinese.joined(separator: sep)
        }
    }
}

// MARK: - Soft post-generation coverage diagnostics (PR3)

/// Soft coverage result for one practice sentence. Log-only in v1 — never drops cards or retries.
struct PracticeSentenceDiagnostics: Equatable {
    let sentence: String
    /// 0...1 — higher means more of the sentence is explained by known/seed/function/ultra-common pieces.
    let coverageEstimate: Double
    let flagged: Bool
}

/// Soft scaffold coverage: English whitespace/letter tokens + Chinese greedy longest-match CJK.
/// Allowlist shape matches generation legal set (K5 / K7) so obedient model output is not false-flagged.
enum PracticeScaffoldValidator {
    static let coverageFlagThreshold: Double = 0.5

    static let englishFunctionWords: Set<String> = [
        "a", "an", "the", "i", "you", "he", "she", "it", "we", "they", "me", "my", "your", "his", "her", "its",
        "our", "their", "is", "are", "am", "was", "were", "be", "do", "does", "did", "not", "no", "yes",
        "to", "of", "in", "on", "at", "for", "with", "and", "or", "but", "this", "that", "what", "where",
        "when", "who", "how", "can", "will", "want", "have", "has", "had", "from", "by", "as", "if", "so"
    ]

    /// Common apostrophe contractions (straight `'`). Curly `’` tokens are normalized before lookup.
    static let englishContractions: Set<String> = [
        "don't", "doesn't", "didn't", "isn't", "aren't", "wasn't", "weren't",
        "can't", "won't", "shouldn't", "couldn't", "wouldn't", "mustn't",
        "i'm", "you're", "he's", "she's", "it's", "we're", "they're",
        "i've", "you've", "we've", "they've", "i'll", "you'll", "he'll", "she'll", "we'll", "they'll",
        "i'd", "you'd", "he'd", "she'd", "we'd", "they'd", "let's",
        "that's", "what's", "who's", "there's", "here's", "where's", "how's"
    ]

    /// Closed-class / ultra-common particles & pronouns for CJK coverage matching.
    static let chineseParticles: Set<String> = [
        "的", "了", "吗", "呢", "吧", "啊", "不", "没", "是", "在", "有",
        "我", "你", "他", "她", "它", "这", "那", "什么", "很", "也",
        "都", "和", "就", "要", "会", "能"
    ]

    /// Shared with sparse-prompt escape — do not duplicate word lists.
    /// Cached once; still single source of truth via `PracticeUltraCommonBeginnerContent`.
    static let ultraCommonBeginnerContentEnglish: Set<String> = Set(
        PracticeUltraCommonBeginnerContent.english.map { $0.lowercased() }
    )

    static let ultraCommonBeginnerContentChinese: Set<String> = Set(
        PracticeUltraCommonBeginnerContent.chinese
    )

    /// Auto-detect: CJK in sentence → Chinese greedy match; else English tokens.
    static func diagnose(
        sentence: String,
        knownFronts: [String],
        seedFronts: [String]
    ) -> PracticeSentenceDiagnostics {
        if PracticeScaffolding.containsCJK(sentence) {
            return diagnoseChinese(
                sentence: sentence,
                knownFronts: knownFronts,
                seedFronts: seedFronts
            )
        }
        return diagnoseEnglish(
            sentence: sentence,
            knownFronts: knownFronts,
            seedFronts: seedFronts
        )
    }

    /// English: lowercase, split on non-letter boundaries; drop empty / pure-digit tokens.
    /// Covered if token is in known ∪ seed (tokenized) ∪ function words ∪ ultra-common beginners.
    static func diagnoseEnglish(
        sentence: String,
        knownFronts: [String],
        seedFronts: [String]
    ) -> PracticeSentenceDiagnostics {
        let tokens = englishTokens(from: sentence)
        guard !tokens.isEmpty else {
            return PracticeSentenceDiagnostics(
                sentence: sentence,
                coverageEstimate: 1.0,
                flagged: false
            )
        }

        var allow = englishFunctionWords
            .union(englishContractions)
            .union(ultraCommonBeginnerContentEnglish)
        for front in knownFronts + seedFronts {
            for token in englishTokens(from: front) {
                allow.insert(normalizeEnglishToken(token))
            }
        }

        let covered = tokens.reduce(0) { count, token in
            count + (allow.contains(normalizeEnglishToken(token)) ? 1 : 0)
        }
        let estimate = Double(covered) / Double(tokens.count)
        return PracticeSentenceDiagnostics(
            sentence: sentence,
            coverageEstimate: estimate,
            flagged: estimate < coverageFlagThreshold
        )
    }

    /// Chinese: CJK runs only; greedy longest-match against known ∪ seed ∪ particles ∪ ultra-common.
    static func diagnoseChinese(
        sentence: String,
        knownFronts: [String],
        seedFronts: [String]
    ) -> PracticeSentenceDiagnostics {
        let runs = cjkRuns(from: sentence)
        let totalCJK = runs.reduce(0) { $0 + $1.count }
        guard totalCJK > 0 else {
            return PracticeSentenceDiagnostics(
                sentence: sentence,
                coverageEstimate: 1.0,
                flagged: false
            )
        }

        var matchKeys = Set<String>()
        matchKeys.formUnion(chineseParticles)
        matchKeys.formUnion(ultraCommonBeginnerContentChinese)
        for front in knownFronts + seedFronts {
            let trimmed = front.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, PracticeScaffolding.containsCJK(trimmed) else { continue }
            // Whole front (for pure-CJK keys) plus pure CJK runs so mixed fronts
            // like "你好！" / "apple苹果" still match sentence CJK runs.
            matchKeys.insert(trimmed)
            for run in cjkRuns(from: trimmed) {
                matchKeys.insert(run)
            }
        }
        // Longest-first is critical (学习 before 学).
        let sortedKeys = matchKeys.sorted { $0.count > $1.count }

        var covered = 0
        for run in runs {
            covered += greedyLongestMatchCoveredCount(run: run, keysLongestFirst: sortedKeys)
        }

        let estimate = Double(covered) / Double(totalCJK)
        return PracticeSentenceDiagnostics(
            sentence: sentence,
            coverageEstimate: estimate,
            flagged: estimate < coverageFlagThreshold
        )
    }

    /// Logs a single low-coverage warning when `diagnostics.flagged`. Never mutates cards.
    static func logIfFlagged(
        _ diagnostics: PracticeSentenceDiagnostics,
        knownFrontsCount: Int,
        onLog: ((String) -> Void)?
    ) {
        guard diagnostics.flagged else { return }
        let sparse = knownFrontsCount < PracticeGenerationConfig.minKnownForRichScaffold
        let sparseTag = sparse ? " sparse=true" : ""
        let snippet = truncatedForLog(diagnostics.sentence)
        // Fixed locale so logs always use `.` decimal separator (not locale-dependent `,`).
        let coverage = String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            diagnostics.coverageEstimate
        )
        onLog?(
            "Practice scaffold warn: low coverage (\(coverage))\(sparseTag) for \"\(snippet)\""
        )
    }

    /// Runs diagnostics on each card and logs warnings only.
    /// - Parameter seedFronts: **All** pack seed fronts for pack path; single seed front for regenerate.
    static func logCoverageForCards(
        _ cards: [PracticeCard],
        knownFronts: [String],
        seedFronts: [String],
        onLog: ((String) -> Void)?
    ) {
        let knownCount = knownFronts.count
        for card in cards {
            let diagnostics = diagnose(
                sentence: card.front,
                knownFronts: knownFronts,
                seedFronts: seedFronts
            )
            logIfFlagged(diagnostics, knownFrontsCount: knownCount, onLog: onLog)
        }
    }

    // MARK: - Token / match helpers

    /// Letter-runs (whitespace + punctuation split). Lowercased. Pure digits never appear.
    /// Apostrophe (`'` / `’`) is intra-token so contractions like "don't" stay one piece.
    static func englishTokens(from text: String) -> [String] {
        let lower = text.lowercased()
        var tokens: [String] = []
        var current = ""
        for ch in lower {
            if ch.isLetter {
                current.append(ch)
            } else if isApostrophe(ch), !current.isEmpty {
                // Keep apostrophe inside the token (don't / don’t).
                current.append(ch)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func isApostrophe(_ ch: Character) -> Bool {
        ch == "'" || ch == "\u{2019}" // straight + right single quotation (curly)
    }

    /// Map curly apostrophes to straight so contraction allowlist matches tokenizer output.
    private static func normalizeEnglishToken(_ token: String) -> String {
        token.replacingOccurrences(of: "\u{2019}", with: "'")
    }

    /// Contiguous CJK runs via shared `Unicode.Scalar.isCJKIdeograph` (same as `containsChineseCharacters`).
    static func cjkRuns(from text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for ch in text {
            if ch.unicodeScalars.contains(where: \.isCJKIdeograph) {
                current.append(ch)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            runs.append(current)
        }
        return runs
    }

    /// Walk one CJK run left-to-right; return count of covered characters.
    private static func greedyLongestMatchCoveredCount(
        run: String,
        keysLongestFirst: [String]
    ) -> Int {
        var covered = 0
        var idx = run.startIndex
        while idx < run.endIndex {
            let rest = run[idx...]
            var matchedLength = 0
            for key in keysLongestFirst {
                if key.isEmpty { continue }
                if rest.hasPrefix(key) {
                    matchedLength = key.count
                    break
                }
            }
            if matchedLength > 0 {
                covered += matchedLength
                idx = run.index(idx, offsetBy: matchedLength)
            } else {
                idx = run.index(after: idx)
            }
        }
        return covered
    }

    private static func truncatedForLog(_ sentence: String, maxChars: Int = 48) -> String {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxChars { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<end]) + "…"
    }
}
