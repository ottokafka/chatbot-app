import Foundation

/// Constants and pure helpers for the Life Path vocabulary song mini-game.
/// See `docs/design-life-path-vocab-song.md`.
///
/// **Trigger unit:** unique vocabulary **seen** this session (first grade of each card),
/// **not** mastery/stable and **not** re-grade / Again repeats of the same word.
enum LifePathSongConfig {
    /// Offer a song break every N **unique words seen** in the current play session.
    static let songBreakEveryN = 10
    /// Prefetch when `wordsSeenCount % everyN == songPrefetchAtRemainder`.
    static let songPrefetchAtRemainder = 8 // everyN - 2
    /// Bank needs at least this many content fronts to generate (session-seen words count).
    static let minContentWordsForSong = 6
    static let maxContentWordsInPrompt = 40
    static let maxSessionHighlightWords = 10
    static let songDurationSeconds: Double = 12
    static let diffusionSteps = 24
    static let defaultGenre = "pop"
    static let lyricsLineTargetMin = 6
    static let lyricsLineTargetMax = 10
    static let lyricsMaxRetries = 1
    static let musicTimeout: TimeInterval = 120
    /// Soft UI hint: encourage Skip after this wait.
    static let maxPresentWait: TimeInterval = 90
    static let historyLimit = 20
    static let lrcTimestampEpsilon: TimeInterval = 0.5
    static let unknownRatioThreshold: Double = 0.15
    /// v1: allow component unigrams of multi-word fronts (documented trade-off K16).
    static let strictStandaloneUnigrams = false

    static let stylePromptEN =
        "gentle children's nursery pop song, soft vocals, warm and simple, educational"
    static let stylePromptZH =
        "温和的儿童流行歌, 简单温柔人声, 适合幼儿学词"

    // MARK: - Runtime (DEBUG) overrides

    /// Effective every-N (DEBUG can override via UserDefaults).
    static var effectiveBreakEveryN: Int {
        #if DEBUG
        let v = UserDefaults.standard.integer(forKey: "lifePath.songBreakEveryN.debug")
        if v >= 3 { return v }
        #endif
        return songBreakEveryN
    }

    /// Prefetch remainder = max(1, everyN - 2).
    static var effectivePrefetchRemainder: Int {
        let everyN = effectiveBreakEveryN
        return max(1, everyN - 2)
    }

    // MARK: - Trigger helpers (pure, testable)
    //
    // Parameter is unique **words seen** this session (not total grades, not mastered count).

    static func shouldPrefetchSong(
        wordsSeenCount: Int,
        everyN: Int = effectiveBreakEveryN,
        prefetchRemainder: Int? = nil
    ) -> Bool {
        let rem = prefetchRemainder ?? max(1, everyN - 2)
        return wordsSeenCount > 0 && wordsSeenCount % everyN == rem
    }

    static func shouldOfferSongBreak(
        wordsSeenCount: Int,
        everyN: Int = effectiveBreakEveryN
    ) -> Bool {
        wordsSeenCount > 0 && wordsSeenCount % everyN == 0
    }

    /// Floor-ceil decade so prefetch@8 and present@10 share decade 1.
    static func breakDecade(_ wordsSeenCount: Int, everyN: Int = effectiveBreakEveryN) -> Int {
        max(1, (wordsSeenCount + everyN - 1) / everyN)
    }

    /// Remaining unique words to see before the next song break (1…everyN).
    /// At 0 or right after a multiple of everyN, returns `everyN` (next full cycle).
    static func wordsUntilSongBreak(
        wordsSeenCount: Int,
        everyN: Int = effectiveBreakEveryN
    ) -> Int {
        guard everyN > 0 else { return 0 }
        let mod = wordsSeenCount % everyN
        return mod == 0 ? everyN : everyN - mod
    }

    // MARK: - Closed-class glue (never counts toward minContentWords)

    /// English closed-class only — no content verbs (want/like/go/see/have).
    static let englishClosedClassGlue: [String] = [
        "I", "you", "we", "my", "your", "me", "a", "an", "the",
        "is", "are", "am", "was", "were", "to", "and", "or", "but",
        "in", "on", "for", "with", "it", "this", "that", "here", "there",
        "so", "too", "oh", "yes", "no"
    ]

    /// Chinese closed-class / particles — no free content verbs (看/吃/喝/来/去/好).
    static let chineseClosedClassGlue: [String] = [
        "我", "你", "我们", "的", "了", "吗", "吧", "是", "在", "和",
        "有", "这", "那", "很", "也", "都", "啊", "哦", "呀", "呢", "不"
    ]

    static func closedClassGlue(for language: LifePathLanguage) -> [String] {
        switch language {
        case .en: return englishClosedClassGlue
        case .zh: return chineseClosedClassGlue
        }
    }
}

// MARK: - Break UI phase (VM-owned)

enum LifePathSongBreakPhase: Equatable {
    case idle
    case presenting
}
