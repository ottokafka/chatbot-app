import Foundation

/// Pure helper: which **user**-produced target fronts appear in learner text.
/// Not MainActor — unit-testable from any context.
///
/// Do **not** reuse `PracticeScaffoldValidator.diagnose` here — that scores assistant
/// leakage against an allowlist, not “did each target appear in user text.”
enum SpeakingTargetTracker {
    /// Returns the subset of `targets` found in `userText` (order-preserving).
    ///
    /// Matching is **per target front** (not session majority alone):
    /// - **CJK** fronts → Chinese rules: substring; auto-hit only for length > 1
    ///   (avoids false positives on 是 / 在 / 好).
    /// - **Else** → English rules: single token = set membership on letter-run tokens;
    ///   multi-word / hyphenated = contiguous token-sequence match (word boundaries).
    ///
    /// `script` is retained for call-site majority context (content steering, logging);
    /// hit detection does not force every front through one rule set so bilingual
    /// decks still score each chip correctly.
    static func hits(
        in userText: String,
        targets: [String],
        script: SpeakingScript
    ) -> [String] {
        let trimmedUser = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty else { return [] }
        // `script` remains part of the public API (session majority / content steering);
        // chip hits use per-front rules below so mixed decks still score correctly.
        let _ = script

        let normalizedText = PracticeScaffolding.normalizeFrontKey(trimmedUser)
        let tokenList = PracticeScaffoldValidator.englishTokens(from: trimmedUser).map {
            PracticeScaffolding.normalizeFrontKey($0)
        }
        let tokenSet = Set(tokenList)

        var found: [String] = []
        var seenKeys = Set<String>()

        for target in targets {
            let key = PracticeScaffolding.normalizeFrontKey(target)
            guard !key.isEmpty, seenKeys.insert(key).inserted else { continue }

            if PracticeScaffolding.containsCJK(target) {
                // Chinese: length > 1 substring on normalized text.
                // Scan order does not change the hit set (non-exclusive contains);
                // nested fronts (图书馆 + 图书) both credit if both are targets.
                guard key.count > 1 else { continue }
                if normalizedText.contains(key) {
                    found.append(target)
                }
            } else if englishMatches(
                tokenList: tokenList,
                tokenSet: tokenSet,
                targetKey: key
            ) {
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

    /// Hyphen / en-dash / em-dash count as multi-word separators (e.g. `self-study` →
    /// contiguous tokens `self` + `study`). Multi-word keys require a whole-token
    /// contiguous subsequence — not raw substring (`"in the"` ⊄ `"within the"`).
    /// Single tokens use set membership (word-boundary equivalent).
    private static func englishMatches(
        tokenList: [String],
        tokenSet: Set<String>,
        targetKey: String
    ) -> Bool {
        let parts = englishTargetParts(targetKey)
        guard !parts.isEmpty else { return false }
        if parts.count == 1 {
            return tokenSet.contains(parts[0])
        }
        return containsContiguousTokenSequence(haystack: tokenList, needle: parts)
    }

    /// Split a normalized English front on whitespace and hyphen-like dashes.
    private static func englishTargetParts(_ targetKey: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for ch in targetKey {
            if ch.isWhitespace || isHyphenLikeSeparator(ch) {
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            parts.append(current)
        }
        return parts
    }

    private static func isHyphenLikeSeparator(_ ch: Character) -> Bool {
        // ASCII hyphen-minus, en dash, em dash.
        ch == "-" || ch == "\u{2013}" || ch == "\u{2014}"
    }

    private static func containsContiguousTokenSequence(
        haystack: [String],
        needle: [String]
    ) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        let lastStart = haystack.count - needle.count
        for start in 0...lastStart {
            var matched = true
            for offset in 0..<needle.count {
                if haystack[start + offset] != needle[offset] {
                    matched = false
                    break
                }
            }
            if matched { return true }
        }
        return false
    }
}
