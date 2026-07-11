import Foundation
import FSRS

/// Role of a persisted flashcard in the library vs gym model.
/// See `docs/design-library-vs-gym.md` and `/flashcard_system.md`.
enum FlashcardKind: String, CaseIterable, Identifiable, Codable {
    case vocab
    case example

    var id: String { rawValue }
}

struct Flashcard: Identifiable, Equatable, Hashable {
    let id: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    var front: String
    var back: String
    var phonics: String?
    var sourceMessageId: String?
    var sourceConversationId: String?
    /// `vocab` = user library; `example` = saved usage / gym.
    var kind: FlashcardKind
    /// When `kind == .example`, optional link to the source vocab card.
    var parentFlashcardId: String?
    let createdAt: Date
    var fsrsCard: Card

    init(
        id: String = UUID().uuidString,
        front: String,
        back: String,
        phonics: String? = nil,
        sourceMessageId: String? = nil,
        sourceConversationId: String? = nil,
        kind: FlashcardKind = .vocab,
        parentFlashcardId: String? = nil,
        createdAt: Date = Date(),
        fsrsCard: Card? = nil
    ) {
        self.id = id
        self.front = front
        self.back = back
        self.phonics = phonics
        self.sourceMessageId = sourceMessageId
        self.sourceConversationId = sourceConversationId
        self.kind = kind
        self.parentFlashcardId = parentFlashcardId
        self.createdAt = createdAt
        self.fsrsCard = fsrsCard ?? FSRSManager.shared.createEmptyCard(now: createdAt)
    }
}

extension Card {
    static func fromDatabase(
        due: Date,
        stability: Double,
        difficulty: Double,
        elapsedDays: Double,
        scheduledDays: Double,
        learningSteps: Int,
        reps: Int,
        lapses: Int,
        state: CardState,
        lastReview: Date?
    ) -> Card {
        Card(
            due: due,
            stability: stability,
            difficulty: difficulty,
            elapsedDays: elapsedDays,
            scheduledDays: scheduledDays,
            learningSteps: learningSteps,
            reps: reps,
            lapses: lapses,
            state: state,
            lastReview: lastReview
        )
    }
}
