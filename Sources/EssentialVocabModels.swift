import Foundation

// MARK: - List language

enum EssentialListLanguage: String, Codable, CaseIterable, Identifiable {
    case zh
    case en

    var id: String { rawValue }

    var listId: String {
        switch self {
        case .zh: return "essential_zh"
        case .en: return "essential_en"
        }
    }

    var resourceBaseName: String {
        switch self {
        case .zh: return "essential_zh_v1"
        case .en: return "essential_en_v1"
        }
    }

    func displayName(uiLanguage: AppLanguage) -> String {
        switch self {
        case .zh:
            return uiLanguage == .zh ? "中文常用词" : "Chinese"
        case .en:
            return uiLanguage == .zh ? "英文常用词" : "English"
        }
    }
}

// MARK: - Catalog files

struct EssentialVocabManifest: Codable, Equatable {
    let schemaVersion: Int
    let lists: [EssentialVocabListMeta]
}

struct EssentialVocabListMeta: Codable, Equatable, Identifiable {
    let id: String
    let version: Int
    let language: String
    let title: [String: String]
    let entryCount: Int
    let sourceNote: String?
    let license: String?

    var languageCode: EssentialListLanguage? {
        EssentialListLanguage(rawValue: language)
    }
}

struct EssentialVocabListFile: Codable, Equatable {
    let listId: String
    let listVersion: Int
    let language: String
    let entries: [EssentialVocabEntry]
}

struct EssentialVocabEntry: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let rank: Int
    let front: String
    let back: String
    let phonics: String?
    let pos: String?
    let tags: [String]?

    var isFunctionWord: Bool {
        tags?.contains("function") == true
    }
}

// MARK: - Progress

enum EssentialVocabStatus: String, Codable, Equatable {
    case added
    case dismissed
}

struct EssentialProgressRow: Equatable {
    let listId: String
    let entryId: String
    var status: EssentialVocabStatus
    var flashcardId: String?
    var updatedAt: Date
}

enum EssentialFilter: String, CaseIterable, Identifiable {
    case pending
    case added
    case dismissed
    case all

    var id: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .pending: return L10n.essentialFilterPending(lang)
        case .added: return L10n.essentialFilterAdded(lang)
        case .dismissed: return L10n.essentialFilterKnown(lang)
        case .all: return L10n.essentialFilterAll(lang)
        }
    }
}

// MARK: - Preferences

enum EssentialVocabPreferences {
    static let listLanguageKey = "essentialVocab.listLanguage"
    static let rankCapKey = "essentialVocab.rankCap"

    static var listLanguage: EssentialListLanguage? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: listLanguageKey) else { return nil }
            return EssentialListLanguage(rawValue: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: listLanguageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: listLanguageKey)
            }
        }
    }

    static var rankCap: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: rankCapKey)
            if value == 100 || value == 500 { return value }
            return 500
        }
        set {
            let capped = (newValue == 100) ? 100 : 500
            UserDefaults.standard.set(capped, forKey: rankCapKey)
        }
    }
}

// MARK: - Catalog validation

enum EssentialVocabCatalogError: Error, Equatable, LocalizedError {
    case missingResource(String)
    case decodeFailed(String)
    case validationFailed([String])

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "Essential word list missing from app bundle: \(name)"
        case .decodeFailed(let detail):
            return "Failed to decode essential word list: \(detail)"
        case .validationFailed(let issues):
            return "Invalid essential word list: \(issues.joined(separator: "; "))"
        }
    }
}

enum EssentialVocabValidation {
    /// Fail-closed catalog checks used at load time and in tests.
    static func validate(_ file: EssentialVocabListFile) -> [String] {
        var issues: [String] = []
        var seenIds = Set<String>()
        var seenFronts = Set<String>()
        var seenRanks = Set<Int>()

        if file.entries.isEmpty {
            issues.append("entries empty")
        }

        for entry in file.entries {
            let front = entry.front.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = entry.back.trimmingCharacters(in: .whitespacesAndNewlines)
            if front.isEmpty {
                issues.append("empty front for id \(entry.id)")
            }
            if back.isEmpty {
                issues.append("empty back for id \(entry.id)")
            }
            if entry.rank <= 0 {
                issues.append("non-positive rank for id \(entry.id)")
            }
            if !seenIds.insert(entry.id).inserted {
                issues.append("duplicate id \(entry.id)")
            }
            if !seenFronts.insert(front).inserted {
                issues.append("duplicate front \(front)")
            }
            if !seenRanks.insert(entry.rank).inserted {
                issues.append("duplicate rank \(entry.rank)")
            }
        }
        return issues
    }
}
