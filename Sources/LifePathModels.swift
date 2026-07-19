import Foundation
import FSRS

// MARK: - Language

enum LifePathLanguage: String, Codable, CaseIterable, Identifiable {
    case zh
    case en

    var id: String { rawValue }

    var listId: String {
        switch self {
        case .zh: return "life_path_zh"
        case .en: return "life_path_en"
        }
    }

    var resourceBaseName: String {
        switch self {
        case .zh: return "life_path_zh_v1"
        case .en: return "life_path_en_v1"
        }
    }

    func displayName(uiLanguage: AppLanguage) -> String {
        switch self {
        case .zh:
            return uiLanguage == .zh ? "中文成长之路" : "Chinese Life Path"
        case .en:
            return uiLanguage == .zh ? "英文成长之路" : "English Life Path"
        }
    }
}

// MARK: - Catalog

struct LifePathManifest: Codable, Equatable {
    let schemaVersion: Int
    let lists: [LifePathListMeta]
}

struct LifePathListMeta: Codable, Equatable, Identifiable {
    let id: String
    let version: Int
    let language: String
    let title: [String: String]
    let entryCount: Int
    let sourceNote: String?
}

struct LifePathStageMeta: Codable, Equatable, Identifiable {
    let id: String
    let order: Int
    let title: [String: String]
    let subtitle: [String: String]?
    let targetCount: Int

    func title(for ui: AppLanguage) -> String {
        title[ui.rawValue] ?? title["en"] ?? id
    }

    func subtitle(for ui: AppLanguage) -> String? {
        guard let subtitle else { return nil }
        return subtitle[ui.rawValue] ?? subtitle["en"]
    }
}

struct LifePathEntry: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let stageId: String
    let rankInStage: Int
    let front: String
    let back: String
    let phonics: String?
    let tags: [String]?
}

struct LifePathListFile: Codable, Equatable {
    let listId: String
    let listVersion: Int
    let language: String
    let stages: [LifePathStageMeta]
    let entries: [LifePathEntry]
}

// MARK: - Progress

/// Cached / display status for a Life Path word. Scheduling authority is `fsrsCard`.
enum LifePathWordStatus: String, Codable, Equatable {
    case locked
    case new
    case learning
    case review
    case stable

    /// Accept legacy DB values from pre-FSRS Life Path.
    static func parse(_ raw: String) -> LifePathWordStatus? {
        if let value = LifePathWordStatus(rawValue: raw) { return value }
        switch raw {
        case "available": return .new
        case "mastered": return .stable
        default: return nil
        }
    }
}

struct LifePathListRow: Equatable, Identifiable {
    /// SQLite primary key (UUID).
    let rowId: String
    var id: String { rowId }
    let language: String
    let entryId: String
    let stageId: String
    let front: String
    /// Derived/cached from FSRS + lock state (not the scheduler itself).
    var status: LifePathWordStatus
    /// Analytics counters (not the scheduler).
    var correctCount: Int
    var wrongCount: Int
    var correctStreak: Int
    /// Full FSRS state for this game-deck card.
    var fsrsCard: Card
    /// When the word first met graduation/stable criteria (analytics).
    var masteredAt: Date?
    var flashcardId: String?
    let createdAt: Date
    var updatedAt: Date

    var dueAt: Date { fsrsCard.due }
    var lastReviewedAt: Date? { fsrsCard.lastReview }

    init(
        rowId: String,
        language: String,
        entryId: String,
        stageId: String,
        front: String,
        status: LifePathWordStatus,
        correctCount: Int = 0,
        wrongCount: Int = 0,
        correctStreak: Int = 0,
        fsrsCard: Card? = nil,
        masteredAt: Date? = nil,
        flashcardId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.rowId = rowId
        self.language = language
        self.entryId = entryId
        self.stageId = stageId
        self.front = front
        self.status = status
        self.correctCount = correctCount
        self.wrongCount = wrongCount
        self.correctStreak = correctStreak
        self.fsrsCard = fsrsCard ?? FSRSManager.shared.createEmptyCard(now: createdAt)
        self.masteredAt = masteredAt
        self.flashcardId = flashcardId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct LifePathProfile: Equatable {
    let language: String
    var currentStageId: String
    var highestStageId: String
    /// Inert DB columns (legacy economy scaffolding). Always write 0; not used by gameplay/UI.
    var xp: Int
    var coins: Int
    var lifetimeXp: Int
    var streakDays: Int
    var lastPlayDay: String?
    var totalReviews: Int
    /// Count of words meeting stable / graduation threshold.
    var totalMastered: Int
    var stagesCleared: [String]
    var pendingNotifyJSON: String?
    let createdAt: Date
    var updatedAt: Date
}

struct LifePathLevelUpNotify: Codable, Equatable {
    let type: String
    let fromStageId: String
    let toStageId: String
    let title: [String: String]
    let body: [String: String]

    func title(for ui: AppLanguage) -> String {
        title[ui.rawValue] ?? title["en"] ?? "You grew up!"
    }

    func body(for ui: AppLanguage) -> String {
        body[ui.rawValue] ?? body["en"] ?? ""
    }
}

// MARK: - Preferences

enum LifePathPreferences {
    static let languageKey = "lifePath.language"
    static let fsrsSchemaKey = "lifePath.fsrsSchemaVersion"
    static let fsrsSchemaVersion = 1
    static let songBreakEnabledKey = "lifePath.songBreakEnabled"

    static var language: LifePathLanguage? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: languageKey) else { return nil }
            return LifePathLanguage(rawValue: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: languageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: languageKey)
            }
        }
    }

    /// Vocab song mini-game break after N **seen** (studied) words in a session — not mastered.
    /// Default **true** so new players get the break without digging for a toggle.
    static var songBreakEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: songBreakEnabledKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: songBreakEnabledKey)
        }
    }
}

// MARK: - Game constants

enum LifePathGame {
    /// Minimum successful reviews (reps) before a word can count toward stage graduation.
    static let graduationMinReps = 2
    /// Fraction of introduced cards that must be stable for stage graduation (carry-forward for the rest).
    static let graduationStableRatio: Double = 0.80
    /// Prefer ordering new cards from the current stage before older-stage backlog.
    static let preferCurrentStageNew = true

    static let stageOrder = ["baby", "toddler", "preschool", "grade1", "grade2", "grade3", "grade4", "grade5", "grade6"]

    static func nextStage(after stageId: String, available: [LifePathStageMeta]) -> LifePathStageMeta? {
        let sorted = available.sorted { $0.order < $1.order }
        guard let idx = sorted.firstIndex(where: { $0.id == stageId }) else {
            return sorted.first
        }
        let next = sorted.index(after: idx)
        return next < sorted.endIndex ? sorted[next] : nil
    }

    static func stageOrderIndex(_ stageId: String, stages: [LifePathStageMeta]) -> Int {
        stages.first(where: { $0.id == stageId })?.order
            ?? stageOrder.firstIndex(of: stageId)
            ?? Int.max
    }
}
