import Foundation

/// Ephemeral practice item derived from a due flashcard.
/// Not stored in the main deck; discarded when the practice pack ends.
struct PracticeCard: Identifiable, Equatable, Hashable {
    let id: String
    var front: String
    var back: String
    var phonics: String?
    /// Source deck card this practice item was generated from.
    var parentFlashcardId: String?
    /// Snapshot of the parent front text for UI badges (survives if parent is edited later).
    var parentFront: String?

    init(
        id: String = UUID().uuidString,
        front: String,
        back: String,
        phonics: String? = nil,
        parentFlashcardId: String? = nil,
        parentFront: String? = nil
    ) {
        self.id = id
        self.front = front
        self.back = back
        self.phonics = phonics
        self.parentFlashcardId = parentFlashcardId
        self.parentFront = parentFront
    }
}

/// In-memory pack of practice cards for one Practice session.
/// Keeps AI examples out of the user's curated deck.
struct PracticePack: Identifiable, Equatable {
    let id: String
    let createdAt: Date
    /// How many due deck cards seeded generation.
    var sourceDueCount: Int
    var cards: [PracticeCard]

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        sourceDueCount: Int,
        cards: [PracticeCard]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceDueCount = sourceDueCount
        self.cards = cards
    }
}

enum PracticeGenerationConfig {
    /// Max due cards used as seeds for one pack.
    static let maxDueSeeds = 10
    /// Example usages generated per seed card.
    static let examplesPerCard = 2
    /// LLM completion budget for multi-card JSON.
    static let maxTokens = 2500
    /// Smaller budget when regenerating a single practice example.
    static let singleExampleMaxTokens = 500
}

/// Result of saving practice cards into the user's main deck.
struct PracticeSaveResult: Equatable {
    var savedCount: Int = 0
    var duplicateCount: Int = 0
    var failedCount: Int = 0
    var skippedEmptyCount: Int = 0

    var didSaveAnything: Bool { savedCount > 0 }

    var totalAttempted: Int {
        savedCount + duplicateCount + failedCount + skippedEmptyCount
    }
}
