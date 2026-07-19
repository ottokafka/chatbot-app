import Foundation
import FSRS

/// Pure helpers for building the known-vocab bank for Life Path songs.
enum LifePathSongBank {

    struct Word: Hashable {
        let entryId: String
        let front: String
        let stageId: String
        let tier: Tier
    }

    enum Tier: Int, Comparable, Hashable {
        case session = 0
        case stable = 1
        case introduced = 2

        static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Bank: Equatable {
        let contentWords: [Word]
        /// Closed-class only. Never counts toward minContentWords.
        let glueWords: [String]
        let language: LifePathLanguage

        var contentFronts: [String] {
            contentWords.map(\.front)
        }

        var sessionFronts: [String] {
            contentWords.filter { $0.tier == .session }.map(\.front)
        }

        /// Keys for validation: normalized whole fronts + EN sub-tokens + glue.
        func allowlistKeys(strictStandaloneUnigrams: Bool = LifePathSongConfig.strictStandaloneUnigrams) -> Set<String> {
            LyricsAllowlistValidator.buildAllowlistKeys(
                contentFronts: contentFronts,
                glue: glueWords,
                language: language,
                strictStandaloneUnigrams: strictStandaloneUnigrams
            )
        }

        /// Stable fingerprint for logging / future bank-diff (v1 join ignores mismatch).
        var fingerprint: String {
            let fronts = contentFronts.map { PracticeScaffolding.normalizeFrontKey($0) }.sorted()
            return fronts.joined(separator: "|") + "#\(language.rawValue)"
        }
    }

    // MARK: - Unlock filter (mirrors LifePathScheduler.buildSession)

    static func isUnlockedRow(
        _ row: LifePathListRow,
        currentStageId: String,
        stages: [LifePathStageMeta]
    ) -> Bool {
        guard row.status != .locked else { return false }
        let currentOrder = LifePathGame.stageOrderIndex(currentStageId, stages: stages)
        return LifePathGame.stageOrderIndex(row.stageId, stages: stages) <= currentOrder
    }

    // MARK: - Build

    static func buildBank(
        language: LifePathLanguage,
        rows: [String: LifePathListRow],
        entriesById: [String: LifePathEntry],
        sessionGradedIds: [String],
        stages: [LifePathStageMeta],
        currentStageId: String,
        maxContentWords: Int = LifePathSongConfig.maxContentWordsInPrompt
    ) -> Bank {
        var content: [Word] = []
        var seenFrontKeys = Set<String>()

        func appendUnique(entry: LifePathEntry, tier: Tier) {
            let key = PracticeScaffolding.normalizeFrontKey(entry.front)
            guard !key.isEmpty, !seenFrontKeys.contains(key) else { return }
            seenFrontKeys.insert(key)
            content.append(Word(
                entryId: entry.id,
                front: entry.front,
                stageId: entry.stageId,
                tier: tier
            ))
        }

        // 1. Session first (first-seen order)
        for id in sessionGradedIds {
            guard let entry = entriesById[id] else { continue }
            // Just-graded rows exist in `rows`; treat as available even mid-session.
            appendUnique(entry: entry, tier: .session)
        }

        // 2. Stable unlocked
        let stableRows = rows.values.filter { row in
            isUnlockedRow(row, currentStageId: currentStageId, stages: stages)
                && LifePathScheduler.meetsGraduationCriteria(card: row.fsrsCard)
        }
        .sorted { a, b in
            if a.fsrsCard.stability != b.fsrsCard.stability {
                return a.fsrsCard.stability > b.fsrsCard.stability
            }
            let oa = LifePathGame.stageOrderIndex(a.stageId, stages: stages)
            let ob = LifePathGame.stageOrderIndex(b.stageId, stages: stages)
            if oa != ob { return oa < ob }
            let ra = entriesById[a.entryId]?.rankInStage ?? Int.max
            let rb = entriesById[b.entryId]?.rankInStage ?? Int.max
            return ra < rb
        }
        for row in stableRows {
            guard let entry = entriesById[row.entryId] else { continue }
            appendUnique(entry: entry, tier: .stable)
        }

        // 3. Introduced non-stable until max
        if content.count < maxContentWords {
            let introduced = rows.values.filter { row in
                isUnlockedRow(row, currentStageId: currentStageId, stages: stages)
                    && row.fsrsCard.reps >= 1
                    && !LifePathScheduler.meetsGraduationCriteria(card: row.fsrsCard)
            }
            .sorted { a, b in
                if a.fsrsCard.reps != b.fsrsCard.reps {
                    return a.fsrsCard.reps > b.fsrsCard.reps
                }
                return a.fsrsCard.stability > b.fsrsCard.stability
            }
            for row in introduced {
                if content.count >= maxContentWords { break }
                guard let entry = entriesById[row.entryId] else { continue }
                appendUnique(entry: entry, tier: .introduced)
            }
        }

        if content.count > maxContentWords {
            content = Array(content.prefix(maxContentWords))
        }

        let glue = LifePathSongConfig.closedClassGlue(for: language)
        return Bank(contentWords: content, glueWords: glue, language: language)
    }
}
