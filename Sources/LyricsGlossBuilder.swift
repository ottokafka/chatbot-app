import Foundation

/// Builds under-lyric translations by matching song bank fronts → backs.
/// Pure helpers — no MainActor. See song karaoke UX (gloss under each LRC line).
enum LyricsGlossBuilder {

    /// Display model: timed lyric + catalog-backed translation gloss.
    struct GlossLine: Equatable, Identifiable {
        let index: Int
        var id: Int { index }
        let time: TimeInterval
        let text: String
        /// Translation string shown under the lyric (may be empty if no content words matched).
        let translation: String
    }

    /// Content-only phrase map: normalized front → back (longest phrases preferred at match time).
    static func translationMap(from bank: LifePathSongBank.Bank) -> [String: String] {
        var map: [String: String] = [:]
        for word in bank.contentWords {
            let key = PracticeScaffolding.normalizeFrontKey(word.front)
            guard !key.isEmpty else { continue }
            // First write wins (session tier is listed first in bank build).
            if map[key] == nil {
                let back = word.back.trimmingCharacters(in: .whitespacesAndNewlines)
                if !back.isEmpty {
                    map[key] = back
                }
            }
        }
        return map
    }

    static func glossLines(
        for lines: [LRCLine],
        bank: LifePathSongBank.Bank
    ) -> [GlossLine] {
        let map = translationMap(from: bank)
        let glue = Set(bank.glueWords.map { PracticeScaffolding.normalizeFrontKey($0) })
        return lines.map { line in
            let gloss = glossForLine(
                line.text,
                language: bank.language,
                translationMap: map,
                glueKeys: glue
            )
            return GlossLine(
                index: line.index,
                time: line.time,
                text: line.text,
                translation: gloss
            )
        }
    }

    /// Public for unit tests.
    static func glossForLine(
        _ text: String,
        language: LifePathLanguage,
        translationMap: [String: String],
        glueKeys: Set<String>
    ) -> String {
        switch language {
        case .en:
            return glossEnglish(text, translationMap: translationMap, glueKeys: glueKeys)
        case .zh:
            return glossChinese(text, translationMap: translationMap, glueKeys: glueKeys)
        }
    }

    // MARK: - English

    /// Greedy left-to-right: prefer longest multi-word content front, then single token.
    /// Glue is skipped. Unknown content is skipped (no invented gloss).
    private static func glossEnglish(
        _ text: String,
        translationMap: [String: String],
        glueKeys: Set<String>
    ) -> String {
        let tokens = PracticeScaffoldValidator.englishTokens(from: text)
            .map { $0.replacingOccurrences(of: "\u{2019}", with: "'").lowercased() }
        guard !tokens.isEmpty else { return "" }

        // Phrases sorted by token count desc, then string length.
        let phraseKeys = translationMap.keys.sorted { a, b in
            let ta = a.split(separator: " ").count
            let tb = b.split(separator: " ").count
            if ta != tb { return ta > tb }
            return a.count > b.count
        }

        var i = 0
        var parts: [String] = []
        while i < tokens.count {
            var matched = false
            for key in phraseKeys {
                let partsKey = key.split(separator: " ").map(String.init)
                guard !partsKey.isEmpty, i + partsKey.count <= tokens.count else { continue }
                let slice = Array(tokens[i..<(i + partsKey.count)])
                if slice == partsKey, let back = translationMap[key] {
                    parts.append(back)
                    i += partsKey.count
                    matched = true
                    break
                }
            }
            if matched { continue }

            let tok = tokens[i]
            if glueKeys.contains(tok) {
                i += 1
                continue
            }
            if let back = translationMap[tok] {
                parts.append(back)
            }
            // Unknown: skip (don't pollute gloss with English leftovers)
            i += 1
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Chinese

    /// Greedy longest-match over CJK runs; each matched content key appends its translation.
    /// Glue particles are skipped. Separators between glosses use spaces for readability.
    private static func glossChinese(
        _ text: String,
        translationMap: [String: String],
        glueKeys: Set<String>
    ) -> String {
        // Prefer longer content keys first (学习 before 学).
        let contentKeys = translationMap.keys.sorted { $0.count > $1.count }
        let runs = PracticeScaffoldValidator.cjkRuns(from: text)
        var parts: [String] = []

        for run in runs {
            var idx = run.startIndex
            while idx < run.endIndex {
                let rest = run[idx...]
                var matchedLength = 0
                var matchedBack: String?

                for key in contentKeys {
                    if key.isEmpty { continue }
                    if rest.hasPrefix(key), let back = translationMap[key] {
                        matchedLength = key.count
                        matchedBack = back
                        break
                    }
                }
                if matchedLength == 0 {
                    // Try glue skip (no gloss)
                    for g in glueKeys.sorted(by: { $0.count > $1.count }) {
                        if g.isEmpty { continue }
                        if rest.hasPrefix(g) {
                            matchedLength = g.count
                            matchedBack = nil
                            break
                        }
                    }
                }

                if matchedLength > 0 {
                    if let back = matchedBack {
                        parts.append(back)
                    }
                    idx = run.index(idx, offsetBy: matchedLength)
                } else {
                    idx = run.index(after: idx)
                }
            }
        }
        return parts.joined(separator: " ")
    }
}
