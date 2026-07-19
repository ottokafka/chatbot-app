import Foundation

struct LRCValidationResult: Equatable {
    let lines: [LRCLine]
    let unknownTokens: [String]
    let unknownRatio: Double
    let timestampsInRange: Bool

    var isAcceptable: Bool {
        timestampsInRange
            && unknownRatio < LifePathSongConfig.unknownRatioThreshold
            && !lines.isEmpty
    }
}

/// Phrase/char-aware allowlist validation for Life Path song lyrics.
enum LyricsAllowlistValidator {

    // MARK: - Allowlist construction

    static func buildAllowlistKeys(
        contentFronts: [String],
        glue: [String],
        language: LifePathLanguage,
        strictStandaloneUnigrams: Bool = LifePathSongConfig.strictStandaloneUnigrams
    ) -> Set<String> {
        var keys = Set<String>()
        for g in glue {
            let norm = PracticeScaffolding.normalizeFrontKey(g)
            if !norm.isEmpty { keys.insert(norm) }
        }
        for front in contentFronts {
            let norm = PracticeScaffolding.normalizeFrontKey(front)
            guard !norm.isEmpty else { continue }
            keys.insert(norm) // whole phrase

            if language == .en {
                let tokens = PracticeScaffoldValidator.englishTokens(from: front)
                    .map { normalizeEnglishToken($0) }
                if strictStandaloneUnigrams {
                    // Only add unigrams that appear as standalone content fronts.
                    let standalone = Set(contentFronts.map { PracticeScaffolding.normalizeFrontKey($0) })
                    for tok in tokens where standalone.contains(tok) || glueContains(tok, glue: glue) {
                        keys.insert(tok)
                    }
                } else {
                    // v1 trade-off K16: expand multi-word fronts into component unigrams.
                    for tok in tokens {
                        keys.insert(tok)
                    }
                }
            } else {
                // ZH: whole front + CJK runs from front
                for run in PracticeScaffoldValidator.cjkRuns(from: front) {
                    keys.insert(run)
                }
            }
        }
        return keys
    }

    private static func glueContains(_ token: String, glue: [String]) -> Bool {
        glue.contains { PracticeScaffolding.normalizeFrontKey($0) == token }
    }

    private static func normalizeEnglishToken(_ token: String) -> String {
        token.replacingOccurrences(of: "\u{2019}", with: "'").lowercased()
    }

    // MARK: - Validate LRC

    static func validate(
        lrc: String,
        bank: LifePathSongBank.Bank,
        duration: Double = LifePathSongConfig.songDurationSeconds,
        epsilon: TimeInterval = LifePathSongConfig.lrcTimestampEpsilon,
        strictStandaloneUnigrams: Bool = LifePathSongConfig.strictStandaloneUnigrams
    ) -> LRCValidationResult {
        let lines = LRCParser.parse(lrc)
        let keys = bank.allowlistKeys(strictStandaloneUnigrams: strictStandaloneUnigrams)

        let timestampsInRange: Bool
        if lines.isEmpty {
            timestampsInRange = false
        } else {
            timestampsInRange = lines.allSatisfy { line in
                line.time >= 0 && line.time <= duration + epsilon
            }
        }

        let lyricText = lines.map(\.text).joined(separator: " ")
        let (unknown, ratio) = unknownRatio(
            lyricText: lyricText,
            keys: keys,
            language: bank.language
        )

        return LRCValidationResult(
            lines: lines,
            unknownTokens: unknown,
            unknownRatio: ratio,
            timestampsInRange: timestampsInRange
        )
    }

    /// EN: greedy longest phrase match over keys; ZH: CJK greedy cover.
    static func unknownRatio(
        lyricText: String,
        keys: Set<String>,
        language: LifePathLanguage
    ) -> (unknown: [String], ratio: Double) {
        switch language {
        case .en:
            return englishUnknownRatio(lyricText: lyricText, keys: keys)
        case .zh:
            return chineseUnknownRatio(lyricText: lyricText, keys: keys)
        }
    }

    // MARK: - EN

    private static func englishUnknownRatio(
        lyricText: String,
        keys: Set<String>
    ) -> (unknown: [String], ratio: Double) {
        let tokens = PracticeScaffoldValidator.englishTokens(from: lyricText)
            .map { normalizeEnglishToken($0) }
        guard !tokens.isEmpty else {
            return ([], 1.0)
        }

        // Multi-word keys longest first (phrase-aware match for "good morning" etc.)
        let phraseKeys = keys.filter { $0.contains(" ") }.sorted { $0.count > $1.count }

        var i = 0
        var unknown: [String] = []
        var covered = 0
        while i < tokens.count {
            var matched = false
            for phrase in phraseKeys {
                let parts = phrase.split(separator: " ").map { normalizeEnglishToken(String($0)) }
                guard !parts.isEmpty, i + parts.count <= tokens.count else { continue }
                let slice = Array(tokens[i..<(i + parts.count)])
                if slice == parts {
                    covered += parts.count
                    i += parts.count
                    matched = true
                    break
                }
            }
            if matched { continue }

            let tok = tokens[i]
            if keys.contains(tok) {
                covered += 1
            } else {
                unknown.append(tok)
            }
            i += 1
        }

        let ratio = Double(tokens.count - covered) / Double(tokens.count)
        return (unknown, ratio)
    }

    // MARK: - ZH

    private static func chineseUnknownRatio(
        lyricText: String,
        keys: Set<String>
    ) -> (unknown: [String], ratio: Double) {
        let (covered, totalCJK) = PracticeScaffoldValidator.cjkGreedyCoveredCount(
            text: lyricText,
            allowlistKeys: keys
        )
        guard totalCJK > 0 else {
            return ([], 1.0)
        }
        let uncovered = totalCJK - covered
        let ratio = Double(uncovered) / Double(totalCJK)

        // Collect unmatched single chars for repair prompts
        var unknown: [String] = []
        if uncovered > 0 {
            let runs = PracticeScaffoldValidator.cjkRuns(from: lyricText)
            let sortedKeys = keys.sorted { $0.count > $1.count }
            for run in runs {
                var idx = run.startIndex
                while idx < run.endIndex {
                    let rest = run[idx...]
                    var matchedLength = 0
                    for key in sortedKeys {
                        if key.isEmpty { continue }
                        if rest.hasPrefix(key) {
                            matchedLength = key.count
                            break
                        }
                    }
                    if matchedLength > 0 {
                        idx = run.index(idx, offsetBy: matchedLength)
                    } else {
                        unknown.append(String(run[idx]))
                        idx = run.index(after: idx)
                    }
                }
            }
        }
        return (unknown, ratio)
    }
}
