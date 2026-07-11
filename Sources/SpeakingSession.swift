import Foundation

// MARK: - Script

/// Script class for speaking target-hit rules and content language steering.
/// Majority of seed fronts (same spirit as Practice K12).
enum SpeakingScript: Equatable {
    /// Latin / English word-boundary matching.
    case english
    /// CJK / Chinese greedy longest-first matching.
    case chinese

    /// Resolve from target fronts via majority CJK vs Latin (K12).
    /// Empty or tied → `.english` unless any front is CJK, then `.chinese`.
    static func resolve(from targets: [String]) -> SpeakingScript {
        switch PracticeScaffolding.majoritySeedFrontsPreferCJK(targets) {
        case .some(true):
            return .chinese
        case .some(false):
            return .english
        case .none:
            if targets.contains(where: { PracticeScaffolding.containsCJK($0) }) {
                return .chinese
            }
            return .english
        }
    }
}

// MARK: - Config

/// Configuration frozen at session start (MVP). No mid-session known refresh.
struct SpeakingSessionConfig: Equatable {
    var seedSource: PracticeSeedSource
    /// Resolved seed cards (vocab only), already capped at `PracticeGenerationConfig.maxDueSeeds`.
    var targetCards: [Flashcard]
    /// Ranked known fronts for scaffolding — **snapshot at start only** (MVP).
    var knownFronts: [String]
    /// Optional free-text topic hint (MVP). Empty = AI chooses simple daily topic using targets.
    var topicHint: String
    /// Soft goal: encourage production of target words (not hard fail). Default **true**.
    var encourageTargetCoverage: Bool
    /// Baby-language length: copied from `PracticeGenerationConfig` at launch.
    var maxAssistantCharsChinese: Int
    var maxAssistantWordsEnglish: Int
    /// Copied from `ChatViewModel` at launch and frozen for the session.
    var appLanguage: AppLanguage
    var sttLanguage: STTLanguage
    /// Always true for MVP speaking sessions (no UI to turn off).
    var speechCorrectionEnabled: Bool

    /// Target fronts in seed order (trimmed, non-empty).
    var targetFronts: [String] {
        targetCards
            .map { $0.front.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Script class for tracker / content steering from seed fronts.
    var script: SpeakingScript {
        SpeakingScript.resolve(from: targetFronts)
    }

    init(
        seedSource: PracticeSeedSource,
        targetCards: [Flashcard],
        knownFronts: [String],
        topicHint: String = "",
        encourageTargetCoverage: Bool = true,
        maxAssistantCharsChinese: Int = PracticeGenerationConfig.babyLanguageMaxCharsChinese,
        maxAssistantWordsEnglish: Int = PracticeGenerationConfig.babyLanguageMaxWordsEnglish,
        appLanguage: AppLanguage = .en,
        sttLanguage: STTLanguage = .auto,
        speechCorrectionEnabled: Bool = true
    ) {
        self.seedSource = seedSource
        self.targetCards = targetCards
        self.knownFronts = knownFronts
        self.topicHint = topicHint
        self.encourageTargetCoverage = encourageTargetCoverage
        self.maxAssistantCharsChinese = maxAssistantCharsChinese
        self.maxAssistantWordsEnglish = maxAssistantWordsEnglish
        self.appLanguage = appLanguage
        self.sttLanguage = sttLanguage
        self.speechCorrectionEnabled = speechCorrectionEnabled
    }
}

// MARK: - Turns

enum SpeakingTurnRole: String, Equatable {
    case assistant
    case user
}

struct SpeakingTurn: Identifiable, Equatable {
    /// String id (UUID string) — same style as practice card ids.
    let id: String
    let role: SpeakingTurnRole
    /// Canonical text used for dialogue history (corrected user text, or assistant text).
    var content: String
    /// Raw ASR when user spoke (optional).
    var rawASR: String?
    /// Pronunciation / phrasing tip from SpeechCorrection (optional).
    var tutorFeedback: String?
    /// Optional L1 gloss (filled on-demand in Phase 2 polish; not every-turn JSON).
    var translation: String?
    /// Optional phonics (Phase 2 polish / `FlashcardTranslator.autoFillPhonics`).
    var phonics: String?
    /// Soft target-word hits detected in **this user turn** (assistant turns leave empty).
    var targetHits: [String]
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        role: SpeakingTurnRole,
        content: String,
        rawASR: String? = nil,
        tutorFeedback: String? = nil,
        translation: String? = nil,
        phonics: String? = nil,
        targetHits: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.rawASR = rawASR
        self.tutorFeedback = tutorFeedback
        self.translation = translation
        self.phonics = phonics
        self.targetHits = targetHits
        self.createdAt = createdAt
    }
}

// MARK: - Session

enum SpeakingSessionStatus: Equatable {
    /// Config set; about to open or retry open.
    case ready
    case waitingUser
    case correctingSpeech
    case generatingReply
    case playingTTS
    case ended
}

/// Soft UI limits (Q4). No hard stop in MVP.
enum SpeakingSessionLimits {
    /// Soft length hint around this many turns; conversation can continue.
    static let softLengthHintTurns = 20
}

struct SpeakingSession: Identifiable, Equatable {
    let id: String
    let startedAt: Date
    var config: SpeakingSessionConfig
    var turns: [SpeakingTurn]
    var status: SpeakingSessionStatus
    /// Target fronts not yet observed in **user** turns (learner production only).
    var uncoveredTargetFronts: [String]
    /// Last error message for banner (opening/reply/STT failures).
    var lastError: String?

    init(
        id: String = UUID().uuidString,
        startedAt: Date = Date(),
        config: SpeakingSessionConfig,
        turns: [SpeakingTurn] = [],
        status: SpeakingSessionStatus = .ready,
        uncoveredTargetFronts: [String]? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.config = config
        self.turns = turns
        self.status = status
        self.uncoveredTargetFronts = uncoveredTargetFronts ?? config.targetFronts
        self.lastError = lastError
    }

    /// Target fronts the learner has produced at least once (order-preserving from config seeds).
    var coveredTargetFronts: [String] {
        let uncoveredKeys = Set(
            uncoveredTargetFronts.map { PracticeScaffolding.normalizeFrontKey($0) }
        )
        return config.targetFronts.filter {
            !uncoveredKeys.contains(PracticeScaffolding.normalizeFrontKey($0))
        }
    }
}
