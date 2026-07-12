import Foundation

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

struct LifePathClearReward: Codable, Equatable {
    let xp: Int
    let coins: Int
}

struct LifePathStageMeta: Codable, Equatable, Identifiable {
    let id: String
    let order: Int
    let title: [String: String]
    let subtitle: [String: String]?
    let targetCount: Int
    let clearReward: LifePathClearReward?

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

enum LifePathWordStatus: String, Codable, Equatable {
    case locked
    case available
    case learning
    case mastered
}

struct LifePathListRow: Equatable, Identifiable {
    /// SQLite primary key (UUID).
    let rowId: String
    var id: String { rowId }
    let language: String
    let entryId: String
    let stageId: String
    let front: String
    var status: LifePathWordStatus
    var correctCount: Int
    var wrongCount: Int
    var correctStreak: Int
    var dueAt: Date?
    var lastReviewedAt: Date?
    var masteredAt: Date?
    var flashcardId: String?
    let createdAt: Date
    var updatedAt: Date
}

struct LifePathProfile: Equatable {
    let language: String
    var currentStageId: String
    var highestStageId: String
    var xp: Int
    var coins: Int
    var lifetimeXp: Int
    var streakDays: Int
    var lastPlayDay: String?
    var totalReviews: Int
    var totalMastered: Int
    var stagesCleared: [String]
    var pendingNotifyJSON: String?
    let createdAt: Date
    var updatedAt: Date
}

enum LifePathRewardType: String, Codable {
    case xp
    case coins
    case title
    case frame
}

struct LifePathRewardRow: Equatable, Identifiable {
    let id: String
    let language: String
    let rewardType: LifePathRewardType
    let amount: Int
    let reason: String
    let stageId: String?
    let entryId: String?
    let metaJSON: String?
    let createdAt: Date
}

struct LifePathLevelUpNotify: Codable, Equatable {
    let type: String
    let fromStageId: String
    let toStageId: String
    let title: [String: String]
    let body: [String: String]
    let rewards: [LifePathNotifyReward]

    struct LifePathNotifyReward: Codable, Equatable {
        let type: String
        let amount: Int?
        let id: String?
    }

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
}

// MARK: - Game constants

enum LifePathGame {
    /// Correct answers in a row required to master a word (1 = first "Got it" masters).
    static let masteryStreak = 1

    static let stageOrder = ["baby", "toddler", "preschool", "grade1", "grade2", "grade3", "grade4", "grade5", "grade6"]

    static func nextStage(after stageId: String, available: [LifePathStageMeta]) -> LifePathStageMeta? {
        let sorted = available.sorted { $0.order < $1.order }
        guard let idx = sorted.firstIndex(where: { $0.id == stageId }) else {
            return sorted.first
        }
        let next = sorted.index(after: idx)
        return next < sorted.endIndex ? sorted[next] : nil
    }
}
