import Foundation

/// Ephemeral practice item derived from a vocabulary seed flashcard.
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
    /// How many vocabulary seed cards were used for generation (legacy name: sourceDueCount).
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

/// How strictly practice sentences should stay simple / scaffolded.
/// v1 / PR2: only `.comprehensible` is used in prompts.
/// `.natural` is a stub for PR4 (full opt-out of baby + known constraints).
enum PracticeSentenceStyle: String, CaseIterable, Equatable {
    /// A0–A1 structure + prefer known vocab (default product behavior).
    case comprehensible
    /// Legacy natural sentences — full opt-out; prompt branch lands in PR4 only.
    case natural
}

enum PracticeGenerationConfig {
    /// Max vocabulary seed cards used for one pack.
    static let maxDueSeeds = 10
    /// Example usages generated per seed card.
    static let examplesPerCard = 2
    /// LLM completion budget for multi-card JSON.
    static let maxTokens = 2500
    /// Smaller budget when regenerating a single practice example.
    static let singleExampleMaxTokens = 500

    /// Max known fronts injected into the prompt (count cap).
    static let maxKnownScaffoldWords = 80
    /// Secondary cap on total characters of known fronts after ranking (input budget).
    static let maxKnownScaffoldChars = 1500
    /// Below this count, prompts emphasize baby language + sparse content-word escape.
    static let minKnownForRichScaffold = 8
    /// CJK front max length (characters).
    static let maxKnownFrontCharacterCountCJK = 12
    /// Latin / non-CJK front max length (characters).
    static let maxKnownFrontCharacterCountLatin = 24
    /// Latin / non-CJK front max whitespace-separated tokens.
    static let maxKnownFrontTokenCountLatin = 3
    /// Soft target length for generated Chinese sentences (prompt interpolation).
    static let babyLanguageMaxCharsChinese = 20
    /// Soft target length for generated English sentences (prompt interpolation).
    static let babyLanguageMaxWordsEnglish = 10
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
