import Foundation
import FSRS

/// Pure Life Path FSRS scheduling helpers (no DB / UI).
/// See `docs/design-life-path-fsrs.md`.
enum LifePathScheduler {

    // MARK: - Status

    /// Derive display/cache status from lock flag + FSRS card.
    static func deriveStatus(isLocked: Bool, card: Card) -> LifePathWordStatus {
        if isLocked { return .locked }
        if card.reps == 0 { return .new }
        switch card.state {
        case .learning, .relearning:
            return .learning
        case .new:
            return .new
        case .review:
            return meetsGraduationCriteria(card: card) ? .stable : .review
        }
    }

    /// v1 graduation: enough reps and not stuck in relearning.
    static func meetsGraduationCriteria(card: Card) -> Bool {
        card.reps >= LifePathGame.graduationMinReps && card.state != .relearning
    }

    static func stageMeetsGraduation(rowsForStage: [LifePathListRow]) -> Bool {
        guard !rowsForStage.isEmpty else { return false }
        // Every card must be unlocked and introduced (reps ≥ 1).
        let unlocked = rowsForStage.filter { $0.status != .locked }
        guard unlocked.count == rowsForStage.count else { return false }
        guard unlocked.allSatisfy({ $0.fsrsCard.reps >= 1 }) else { return false }
        // At least graduationStableRatio of introduced cards must be stable.
        let stable = unlocked.filter { meetsGraduationCriteria(card: $0.fsrsCard) }
        let ratio = Double(stable.count) / Double(unlocked.count)
        return ratio >= LifePathGame.graduationStableRatio
    }

    // MARK: - Session queue (unlimited)

    /// Build a full unlimited play queue: all due (unlocked stages) then all new.
    /// - Parameters:
    ///   - rows: All list rows for the language.
    ///   - entriesById: Catalog entries keyed by entry id.
    ///   - stages: Stage metadata (for order).
    ///   - currentStageId: Player's current stage.
    ///   - now: Clock for due checks.
    /// - Returns: Ordered catalog entries to play (may be empty).
    static func buildSession(
        rows: [LifePathListRow],
        entriesById: [String: LifePathEntry],
        stages: [LifePathStageMeta],
        currentStageId: String,
        now: Date = Date()
    ) -> [LifePathEntry] {
        let currentOrder = LifePathGame.stageOrderIndex(currentStageId, stages: stages)
        let unlockedRows = rows.filter { row in
            guard row.status != .locked else { return false }
            return LifePathGame.stageOrderIndex(row.stageId, stages: stages) <= currentOrder
        }

        let dueRows = unlockedRows
            .filter { $0.fsrsCard.reps > 0 && $0.fsrsCard.due <= now }
            .sorted { a, b in
                if a.fsrsCard.due != b.fsrsCard.due {
                    return a.fsrsCard.due < b.fsrsCard.due
                }
                let oa = LifePathGame.stageOrderIndex(a.stageId, stages: stages)
                let ob = LifePathGame.stageOrderIndex(b.stageId, stages: stages)
                if oa != ob { return oa < ob }
                return rank(a.entryId, entriesById) < rank(b.entryId, entriesById)
            }

        let newRows = unlockedRows.filter { $0.fsrsCard.reps == 0 }
        let newCurrent = newRows
            .filter { $0.stageId == currentStageId }
            .sorted { rank($0.entryId, entriesById) < rank($1.entryId, entriesById) }
        let newBacklog = newRows
            .filter { $0.stageId != currentStageId }
            .sorted { a, b in
                let oa = LifePathGame.stageOrderIndex(a.stageId, stages: stages)
                let ob = LifePathGame.stageOrderIndex(b.stageId, stages: stages)
                if oa != ob { return oa < ob }
                return rank(a.entryId, entriesById) < rank(b.entryId, entriesById)
            }

        let orderedNew: [LifePathListRow]
        if LifePathGame.preferCurrentStageNew {
            orderedNew = newCurrent + newBacklog
        } else {
            orderedNew = (newCurrent + newBacklog).sorted { a, b in
                let oa = LifePathGame.stageOrderIndex(a.stageId, stages: stages)
                let ob = LifePathGame.stageOrderIndex(b.stageId, stages: stages)
                if oa != ob { return oa < ob }
                return rank(a.entryId, entriesById) < rank(b.entryId, entriesById)
            }
        }

        let queueRows = dueRows + orderedNew
        return queueRows.compactMap { entriesById[$0.entryId] }
    }

    static func dueCount(rows: [LifePathListRow], stages: [LifePathStageMeta], currentStageId: String, now: Date = Date()) -> Int {
        let currentOrder = LifePathGame.stageOrderIndex(currentStageId, stages: stages)
        return rows.filter { row in
            guard row.status != .locked else { return false }
            guard LifePathGame.stageOrderIndex(row.stageId, stages: stages) <= currentOrder else { return false }
            return row.fsrsCard.reps > 0 && row.fsrsCard.due <= now
        }.count
    }

    static func newCount(rows: [LifePathListRow], stages: [LifePathStageMeta], currentStageId: String) -> Int {
        let currentOrder = LifePathGame.stageOrderIndex(currentStageId, stages: stages)
        return rows.filter { row in
            guard row.status != .locked else { return false }
            guard LifePathGame.stageOrderIndex(row.stageId, stages: stages) <= currentOrder else { return false }
            return row.fsrsCard.reps == 0
        }.count
    }

    static func stableCount(rows: [LifePathListRow], stageId: String) -> Int {
        rows.filter { $0.stageId == stageId && meetsGraduationCriteria(card: $0.fsrsCard) }.count
    }

    static func nextDueDate(rows: [LifePathListRow], stages: [LifePathStageMeta], currentStageId: String, now: Date = Date()) -> Date? {
        let currentOrder = LifePathGame.stageOrderIndex(currentStageId, stages: stages)
        return rows
            .filter { row in
                guard row.status != .locked else { return false }
                guard LifePathGame.stageOrderIndex(row.stageId, stages: stages) <= currentOrder else { return false }
                return row.fsrsCard.reps > 0 && row.fsrsCard.due > now
            }
            .map(\.fsrsCard.due)
            .min()
    }

    /// Per-stage due counts among unlocked stages (for home breakdown).
    static func dueCountByStage(
        rows: [LifePathListRow],
        stages: [LifePathStageMeta],
        currentStageId: String,
        now: Date = Date()
    ) -> [String: Int] {
        let currentOrder = LifePathGame.stageOrderIndex(currentStageId, stages: stages)
        var counts: [String: Int] = [:]
        for row in rows {
            guard row.status != .locked else { continue }
            guard LifePathGame.stageOrderIndex(row.stageId, stages: stages) <= currentOrder else { continue }
            guard row.fsrsCard.reps > 0, row.fsrsCard.due <= now else { continue }
            counts[row.stageId, default: 0] += 1
        }
        return counts
    }

    // MARK: - Migration credit

    /// Credit a legacy pre-FSRS row into a reasonable FSRS card (policy B).
    static func migrateLegacyScheduling(
        status: LifePathWordStatus,
        correctCount: Int,
        existingCard: Card,
        now: Date = Date()
    ) -> Card {
        // Already has real FSRS history — leave it.
        if existingCard.reps > 0 || existingCard.state != .new || existingCard.stability > 0 {
            return existingCard
        }

        switch status {
        case .locked, .new:
            return FSRSManager.shared.createEmptyCard(now: now)
        case .learning:
            return Card(
                due: now,
                stability: 0,
                difficulty: 0,
                elapsedDays: 0,
                scheduledDays: 0,
                learningSteps: 0,
                reps: max(1, correctCount),
                lapses: 0,
                state: .learning,
                lastReview: now
            )
        case .review, .stable:
            // Mild review card so words reappear as carry-over without full re-intro.
            return Card(
                due: now.addingTimeInterval(86_400),
                stability: 2.5,
                difficulty: 5,
                elapsedDays: 0,
                scheduledDays: 1,
                learningSteps: 0,
                reps: max(LifePathGame.graduationMinReps, correctCount),
                lapses: 0,
                state: .review,
                lastReview: now
            )
        }
    }

    // MARK: - Helpers

    private static func rank(_ entryId: String, _ entriesById: [String: LifePathEntry]) -> Int {
        entriesById[entryId]?.rankInStage ?? Int.max
    }
}
