import Foundation
import FSRS

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
    let createdAt: Date
    var fsrsCard: Card

    init(
        id: String = UUID().uuidString,
        front: String,
        back: String,
        phonics: String? = nil,
        sourceMessageId: String? = nil,
        sourceConversationId: String? = nil,
        createdAt: Date = Date(),
        fsrsCard: Card? = nil
    ) {
        self.id = id
        self.front = front
        self.back = back
        self.phonics = phonics
        self.sourceMessageId = sourceMessageId
        self.sourceConversationId = sourceConversationId
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