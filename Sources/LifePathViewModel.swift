import Foundation
import SwiftUI
import Combine

@MainActor
final class LifePathViewModel: ObservableObject {
    @Published private(set) var language: LifePathLanguage?
    @Published private(set) var showLanguagePicker = false
    @Published private(set) var stages: [LifePathStageMeta] = []
    @Published private(set) var entries: [LifePathEntry] = []
    @Published private(set) var listRowsByEntryId: [String: LifePathListRow] = [:]
    @Published private(set) var profile: LifePathProfile?
    @Published private(set) var loadError: String?
    @Published var toastMessage: String?
    @Published var actionError: String?

    // Session
    @Published private(set) var isPlaying = false
    @Published private(set) var sessionQueue: [LifePathEntry] = []
    @Published private(set) var sessionIndex = 0
    @Published private(set) var isAnswerRevealed = false
    @Published private(set) var sessionCorrect = 0
    @Published private(set) var sessionWrong = 0
    @Published private(set) var sessionFinished = false
    @Published private(set) var lastGainXP = 0
    @Published private(set) var lastGainCoins = 0

    // Level-up
    @Published var pendingLevelUp: LifePathLevelUpNotify?
    @Published var showLevelUp = false

    private var dbManager: DatabaseManager
    private weak var flashcardVM: FlashcardViewModel?
    private var entriesById: [String: LifePathEntry] = [:]
    private var sessionXPEarnedToday: Int = 0

    var onLog: ((String) -> Void)?

    init(dbManager: DatabaseManager = DatabaseManager(), flashcardVM: FlashcardViewModel? = nil) {
        self.dbManager = dbManager
        self.flashcardVM = flashcardVM
    }

    func attach(flashcardVM: FlashcardViewModel, dbManager: DatabaseManager? = nil) {
        self.flashcardVM = flashcardVM
        if let dbManager {
            self.dbManager = dbManager
        }
    }

    // MARK: - Derived

    var currentStage: LifePathStageMeta? {
        guard let stageId = profile?.currentStageId else { return stages.first }
        return stages.first { $0.id == stageId } ?? stages.first
    }

    var currentStageEntries: [LifePathEntry] {
        guard let stageId = profile?.currentStageId else { return [] }
        return entries.filter { $0.stageId == stageId }.sorted { $0.rankInStage < $1.rankInStage }
    }

    var masteredInCurrentStage: Int {
        guard let stageId = profile?.currentStageId else { return 0 }
        return listRowsByEntryId.values.filter { $0.stageId == stageId && $0.status == .mastered }.count
    }

    var totalInCurrentStage: Int {
        currentStageEntries.count
    }

    var stageProgress: Double {
        guard totalInCurrentStage > 0 else { return 0 }
        return Double(masteredInCurrentStage) / Double(totalInCurrentStage)
    }

    var currentCard: LifePathEntry? {
        guard isPlaying, sessionIndex < sessionQueue.count else { return nil }
        return sessionQueue[sessionIndex]
    }

    func isStageUnlocked(_ stageId: String) -> Bool {
        guard let profile else { return stageId == stages.first?.id }
        if profile.stagesCleared.contains(stageId) { return true }
        if profile.currentStageId == stageId { return true }
        // highest unlocked
        let order = stages.sorted { $0.order < $1.order }
        guard let highestIdx = order.firstIndex(where: { $0.id == profile.highestStageId }),
              let stageIdx = order.firstIndex(where: { $0.id == stageId }) else {
            return stageId == order.first?.id
        }
        return stageIdx <= highestIdx
    }

    func isStageCleared(_ stageId: String) -> Bool {
        profile?.stagesCleared.contains(stageId) == true
    }

    // MARK: - Load

    func load() {
        loadError = nil
        guard let language = LifePathPreferences.language else {
            self.language = nil
            showLanguagePicker = true
            stages = []
            entries = []
            listRowsByEntryId = [:]
            profile = nil
            return
        }
        showLanguagePicker = false
        self.language = language
        do {
            let file = try LifePathCatalog.loadList(language: language)
            stages = file.stages.sorted { $0.order < $1.order }
            entries = file.entries
            entriesById = Dictionary(uniqueKeysWithValues: file.entries.map { ($0.id, $0) })
            seedIfNeeded(language: language, file: file)
            reloadFromDB(language: language)
            restorePendingNotify()
            onLog?("Life Path loaded: \(language.listId) (\(entries.count) entries)")
        } catch {
            loadError = error.localizedDescription
            onLog?("Life Path load failed: \(loadError ?? "unknown")")
        }
    }

    func setLanguage(_ lang: LifePathLanguage) {
        LifePathPreferences.language = lang
        language = lang
        showLanguagePicker = false
        load()
    }

    func cancelLanguagePicker() {
        flashcardVM?.isShowingLifePath = false
    }

    // MARK: - Play

    /// Starts a full-stage session: every unmastered word in the current life stage.
    /// Words that are not yet mastered are re-queued so the player can finish the stage in one go.
    func startRound() {
        guard let profile, language != nil else { return }
        let stageId = profile.currentStageId
        let pool = entries.filter { $0.stageId == stageId }
        let playable = pool.filter { entry in
            guard let row = listRowsByEntryId[entry.id] else { return false }
            return row.status == .available || row.status == .learning
        }
        let queue = playable.sorted { a, b in
            let ra = listRowsByEntryId[a.id]
            let rb = listRowsByEntryId[b.id]
            let da = ra?.dueAt ?? .distantPast
            let db = rb?.dueAt ?? .distantPast
            if da != db { return da < db }
            if a.rankInStage != b.rankInStage { return a.rankInStage < b.rankInStage }
            return (ra?.wrongCount ?? 0) > (rb?.wrongCount ?? 0)
        }
        guard !queue.isEmpty else {
            actionError = "No words left in this stage."
            return
        }
        applyDailyBonusIfNeeded()
        sessionQueue = queue
        sessionIndex = 0
        sessionCorrect = 0
        sessionWrong = 0
        isAnswerRevealed = false
        sessionFinished = false
        lastGainXP = 0
        lastGainCoins = 0
        isPlaying = true
        onLog?("Life Path stage session started (\(queue.count) unmastered cards in \(stageId))")
    }

    /// Cards still ahead in the current full-stage session (including current).
    var sessionRemainingCount: Int {
        max(0, sessionQueue.count - sessionIndex)
    }

    func revealAnswer() {
        isAnswerRevealed = true
    }

    func gradeCorrect() {
        grade(correct: true)
    }

    func gradeWrong() {
        grade(correct: false)
    }

    func endSession() {
        isPlaying = false
        sessionQueue = []
        sessionIndex = 0
        isAnswerRevealed = false
        sessionFinished = false
    }

    func dismissLevelUp() {
        guard var profile else {
            showLevelUp = false
            pendingLevelUp = nil
            return
        }
        profile.pendingNotifyJSON = nil
        profile.updatedAt = Date()
        dbManager.upsertLifePathProfile(profile)
        self.profile = profile
        showLevelUp = false
        pendingLevelUp = nil
    }

    // MARK: - Private game logic

    private func grade(correct: Bool) {
        guard let language,
              let entry = currentCard,
              var row = listRowsByEntryId[entry.id],
              var profile else { return }

        let now = Date()
        var gainedXP = 0
        var gainedCoins = 0
        let wasMastered = row.status == .mastered
        let firstCorrect = correct && row.correctCount == 0

        if correct {
            row.correctCount += 1
            row.correctStreak += 1
            if row.status != .mastered {
                row.status = .learning
            }
            sessionCorrect += 1

            gainedXP += LifePathGame.xpCorrect
            gainedCoins += LifePathGame.coinsCorrect
            if firstCorrect {
                gainedXP += LifePathGame.xpFirstCorrectBonus
            }

            var justMastered = false
            if !wasMastered && row.correctStreak >= LifePathGame.masteryStreak {
                row.status = .mastered
                row.masteredAt = now
                row.correctStreak = LifePathGame.masteryStreak
                gainedXP += LifePathGame.xpMastered
                gainedCoins += LifePathGame.coinsMastered
                profile.totalMastered += 1
                justMastered = true
            }
            row.dueAt = now.addingTimeInterval(wasMastered || row.status == .mastered ? 86400 : 3600)

            // Ledger: base review + optional mastery (no double-count)
            let baseXP = LifePathGame.xpCorrect + (firstCorrect ? LifePathGame.xpFirstCorrectBonus : 0)
            let baseCoins = LifePathGame.coinsCorrect
            if baseXP > 0 {
                grantReward(language: language.rawValue, type: .xp, amount: baseXP, reason: "review_correct", stageId: row.stageId, entryId: row.entryId)
            }
            if baseCoins > 0 {
                grantReward(language: language.rawValue, type: .coins, amount: baseCoins, reason: "review_correct", stageId: row.stageId, entryId: row.entryId)
            }
            if justMastered {
                grantReward(language: language.rawValue, type: .xp, amount: LifePathGame.xpMastered, reason: "word_mastered", stageId: row.stageId, entryId: row.entryId)
                grantReward(language: language.rawValue, type: .coins, amount: LifePathGame.coinsMastered, reason: "word_mastered", stageId: row.stageId, entryId: row.entryId)
            }
        } else {
            row.wrongCount += 1
            row.correctStreak = 0
            if row.status != .mastered {
                row.status = .learning
            } else {
                // Drop mastered back to learning on fail (gentle)
                row.status = .learning
                row.masteredAt = nil
                if profile.totalMastered > 0 {
                    profile.totalMastered -= 1
                }
            }
            sessionWrong += 1
            gainedXP += 2
            row.dueAt = now.addingTimeInterval(300)
            grantReward(language: language.rawValue, type: .xp, amount: 2, reason: "review_wrong", stageId: row.stageId, entryId: row.entryId)
        }

        row.lastReviewedAt = now
        row.updatedAt = now
        dbManager.upsertLifePathListRow(row)
        listRowsByEntryId[entry.id] = row

        // Daily XP cap
        let applyXP = min(gainedXP, max(0, LifePathGame.dailyXpCap - sessionXPEarnedToday))
        sessionXPEarnedToday += applyXP
        profile.xp += applyXP
        profile.lifetimeXp += applyXP
        profile.coins += gainedCoins
        profile.totalReviews += 1
        profile.updatedAt = now

        dbManager.upsertLifePathProfile(profile)
        self.profile = profile
        lastGainXP = applyXP
        lastGainCoins = gainedCoins
        toastMessage = applyXP > 0
            ? "+\(applyXP) XP" + (gainedCoins > 0 ? " · +\(gainedCoins) coins" : "")
            : (gainedCoins > 0 ? "+\(gainedCoins) coins" : nil)

        // Re-queue if not mastered so the player can clear the whole stage in one session.
        let stillNeedsPractice = listRowsByEntryId[entry.id]?.status != .mastered
        if stillNeedsPractice {
            let alreadyAhead = sessionQueue[(sessionIndex + 1)..<sessionQueue.count]
                .contains(where: { $0.id == entry.id })
            if !alreadyAhead {
                sessionQueue.append(entry)
            }
        }

        // Stage clear check before advancing card
        checkStageClear()

        // Level-up ends the session; do not advance further cards.
        if showLevelUp {
            isAnswerRevealed = false
            return
        }

        advanceOrFinish()
    }

    private func advanceOrFinish() {
        isAnswerRevealed = false
        // Drop mastered cards that were already past the cursor? keep simple: only advance.
        if sessionIndex + 1 < sessionQueue.count {
            sessionIndex += 1
            // Skip any cards that became mastered while waiting (shouldn't normally happen)
            while sessionIndex < sessionQueue.count {
                let id = sessionQueue[sessionIndex].id
                if listRowsByEntryId[id]?.status == .mastered {
                    sessionIndex += 1
                    continue
                }
                break
            }
            if sessionIndex >= sessionQueue.count {
                finishRound()
            }
        } else {
            finishRound()
        }
    }

    private func finishRound() {
        sessionFinished = true
        isPlaying = false
        // Perfect round bonus
        if sessionWrong == 0, sessionCorrect > 0, let language, var profile {
            let xp = LifePathGame.xpPerfectRound
            let coins = LifePathGame.coinsPerfectRound
            let applyXP = min(xp, max(0, LifePathGame.dailyXpCap - sessionXPEarnedToday))
            sessionXPEarnedToday += applyXP
            profile.xp += applyXP
            profile.lifetimeXp += applyXP
            profile.coins += coins
            profile.updatedAt = Date()
            dbManager.upsertLifePathProfile(profile)
            self.profile = profile
            if applyXP > 0 {
                grantReward(language: language.rawValue, type: .xp, amount: applyXP, reason: "perfect_round", stageId: profile.currentStageId, entryId: nil)
            }
            grantReward(language: language.rawValue, type: .coins, amount: coins, reason: "perfect_round", stageId: profile.currentStageId, entryId: nil)
            lastGainXP += applyXP
            lastGainCoins += coins
        }
        onLog?("Life Path round finished correct=\(sessionCorrect) wrong=\(sessionWrong)")
    }

    private func checkStageClear() {
        guard let language,
              var profile,
              !profile.stagesCleared.contains(profile.currentStageId) else { return }

        let stageId = profile.currentStageId
        let stageEntries = entries.filter { $0.stageId == stageId }
        guard !stageEntries.isEmpty else { return }
        let allMastered = stageEntries.allSatisfy { listRowsByEntryId[$0.id]?.status == .mastered }
        guard allMastered else { return }

        let stageMeta = stages.first { $0.id == stageId }
        let rewardXP = stageMeta?.clearReward?.xp ?? 100
        let rewardCoins = stageMeta?.clearReward?.coins ?? 50
        let next = LifePathGame.nextStage(after: stageId, available: stages)

        profile.stagesCleared.append(stageId)
        profile.xp += rewardXP
        profile.lifetimeXp += rewardXP
        profile.coins += rewardCoins
        profile.updatedAt = Date()

        grantReward(language: language.rawValue, type: .xp, amount: rewardXP, reason: "stage_clear", stageId: stageId, entryId: nil)
        grantReward(language: language.rawValue, type: .coins, amount: rewardCoins, reason: "stage_clear", stageId: stageId, entryId: nil)
        grantReward(
            language: language.rawValue,
            type: .title,
            amount: 0,
            reason: "stage_clear",
            stageId: stageId,
            entryId: nil,
            metaJSON: "{\"id\":\"\(LifePathGame.titleId(forClearedStage: stageId))\"}"
        )

        let toStageId = next?.id ?? stageId
        if let next {
            dbManager.unlockLifePathStage(language: language.rawValue, stageId: next.id)
            profile.currentStageId = next.id
            profile.highestStageId = next.id
            grantReward(
                language: language.rawValue,
                type: .frame,
                amount: 0,
                reason: "stage_unlock",
                stageId: next.id,
                entryId: nil,
                metaJSON: "{\"id\":\"\(LifePathGame.frameId(forStage: next.id))\"}"
            )
        }

        let notify = LifePathLevelUpNotify(
            type: "stage_clear",
            fromStageId: stageId,
            toStageId: toStageId,
            title: [
                "en": "You grew up!",
                "zh": "你长大了！"
            ],
            body: [
                "en": next != nil
                    ? "\(stageMeta?.title(for: .en) ?? stageId) complete. Welcome to \(next?.title(for: .en) ?? toStageId)!"
                    : "\(stageMeta?.title(for: .en) ?? stageId) complete. You've finished the current path!",
                "zh": next != nil
                    ? "\(stageMeta?.title(for: .zh) ?? stageId) 已完成，欢迎进入\(next?.title(for: .zh) ?? toStageId)！"
                    : "\(stageMeta?.title(for: .zh) ?? stageId) 已完成，当前成长之路已全部通关！"
            ],
            rewards: [
                .init(type: "xp", amount: rewardXP, id: nil),
                .init(type: "coins", amount: rewardCoins, id: nil),
                .init(type: "title", amount: nil, id: LifePathGame.titleId(forClearedStage: stageId)),
                .init(type: "frame", amount: nil, id: LifePathGame.frameId(forStage: toStageId))
            ]
        )
        if let data = try? JSONEncoder().encode(notify),
           let json = String(data: data, encoding: .utf8) {
            profile.pendingNotifyJSON = json
        }

        dbManager.upsertLifePathProfile(profile)
        self.profile = profile
        reloadFromDB(language: language)
        pendingLevelUp = notify
        showLevelUp = true
        // Pause session if mid-round
        isPlaying = false
        sessionFinished = true
        onLog?("Life Path stage cleared: \(stageId) → \(toStageId)")
    }

    private func applyDailyBonusIfNeeded() {
        guard let language, var profile else { return }
        let day = Self.todayString()
        if profile.lastPlayDay == day { return }

        let cal = Calendar.current
        var streak = 1
        if let last = profile.lastPlayDay,
           let lastDate = Self.parseDay(last),
           let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) {
            let y = Self.dayString(yesterday)
            if last == y {
                streak = profile.streakDays + 1
            }
            _ = lastDate
        }
        profile.streakDays = streak
        profile.lastPlayDay = day
        profile.xp += LifePathGame.xpDailyFirst
        profile.lifetimeXp += LifePathGame.xpDailyFirst
        profile.coins += LifePathGame.coinsDailyFirst
        profile.updatedAt = Date()
        sessionXPEarnedToday += LifePathGame.xpDailyFirst
        dbManager.upsertLifePathProfile(profile)
        self.profile = profile
        grantReward(language: language.rawValue, type: .xp, amount: LifePathGame.xpDailyFirst, reason: "daily_first", stageId: profile.currentStageId, entryId: nil)
        grantReward(language: language.rawValue, type: .coins, amount: LifePathGame.coinsDailyFirst, reason: "daily_first", stageId: profile.currentStageId, entryId: nil)

        // Streak milestones
        let milestones = [3, 7, 14]
        if milestones.contains(streak) {
            let xp = streak == 3 ? 20 : (streak == 7 ? 50 : 100)
            let coins = streak == 3 ? 10 : (streak == 7 ? 25 : 50)
            profile.xp += xp
            profile.lifetimeXp += xp
            profile.coins += coins
            profile.updatedAt = Date()
            dbManager.upsertLifePathProfile(profile)
            self.profile = profile
            grantReward(language: language.rawValue, type: .xp, amount: xp, reason: "streak_\(streak)", stageId: profile.currentStageId, entryId: nil)
            grantReward(language: language.rawValue, type: .coins, amount: coins, reason: "streak_\(streak)", stageId: profile.currentStageId, entryId: nil)
        }
        toastMessage = "Daily bonus +\(LifePathGame.xpDailyFirst) XP"
    }

    private func grantReward(
        language: String,
        type: LifePathRewardType,
        amount: Int,
        reason: String,
        stageId: String?,
        entryId: String?,
        metaJSON: String? = nil
    ) {
        let reward = LifePathRewardRow(
            id: UUID().uuidString,
            language: language,
            rewardType: type,
            amount: amount,
            reason: reason,
            stageId: stageId,
            entryId: entryId,
            metaJSON: metaJSON,
            createdAt: Date()
        )
        dbManager.insertLifePathReward(reward)
    }

    private func seedIfNeeded(language: LifePathLanguage, file: LifePathListFile) {
        let existing = dbManager.countLifePathList(language: language.rawValue)
        if existing == 0 {
            let now = Date()
            let firstStage = file.stages.sorted { $0.order < $1.order }.first?.id ?? "baby"
            for entry in file.entries {
                let status: LifePathWordStatus = entry.stageId == firstStage ? .available : .locked
                let row = LifePathListRow(
                    rowId: UUID().uuidString,
                    language: language.rawValue,
                    entryId: entry.id,
                    stageId: entry.stageId,
                    front: entry.front,
                    status: status,
                    correctCount: 0,
                    wrongCount: 0,
                    correctStreak: 0,
                    dueAt: nil,
                    lastReviewedAt: nil,
                    masteredAt: nil,
                    flashcardId: nil,
                    createdAt: now,
                    updatedAt: now
                )
                dbManager.insertLifePathListRow(row)
            }
            let profile = LifePathProfile(
                language: language.rawValue,
                currentStageId: firstStage,
                highestStageId: firstStage,
                xp: 0,
                coins: 0,
                lifetimeXp: 0,
                streakDays: 0,
                lastPlayDay: nil,
                totalReviews: 0,
                totalMastered: 0,
                stagesCleared: [],
                pendingNotifyJSON: nil,
                createdAt: now,
                updatedAt: now
            )
            dbManager.upsertLifePathProfile(profile)
            onLog?("Life Path seeded \(file.entries.count) words for \(language.rawValue)")
        } else {
            // Ensure profile exists
            if dbManager.fetchLifePathProfile(language: language.rawValue) == nil {
                let firstStage = file.stages.sorted { $0.order < $1.order }.first?.id ?? "baby"
                let now = Date()
                let profile = LifePathProfile(
                    language: language.rawValue,
                    currentStageId: firstStage,
                    highestStageId: firstStage,
                    xp: 0,
                    coins: 0,
                    lifetimeXp: 0,
                    streakDays: 0,
                    lastPlayDay: nil,
                    totalReviews: 0,
                    totalMastered: 0,
                    stagesCleared: [],
                    pendingNotifyJSON: nil,
                    createdAt: now,
                    updatedAt: now
                )
                dbManager.upsertLifePathProfile(profile)
            }
            // Seed any new catalog entries missing from DB (content updates)
            let existingRows = dbManager.fetchLifePathList(language: language.rawValue)
            let existingIds = Set(existingRows.map(\.entryId))
            let currentStage = dbManager.fetchLifePathProfile(language: language.rawValue)?.currentStageId
                ?? file.stages.sorted { $0.order < $1.order }.first?.id
            let cleared = Set(dbManager.fetchLifePathProfile(language: language.rawValue)?.stagesCleared ?? [])
            let highest = dbManager.fetchLifePathProfile(language: language.rawValue)?.highestStageId
            let now = Date()
            for entry in file.entries where !existingIds.contains(entry.id) {
                let unlocked = entry.stageId == currentStage
                    || cleared.contains(entry.stageId)
                    || entry.stageId == highest
                let row = LifePathListRow(
                    rowId: UUID().uuidString,
                    language: language.rawValue,
                    entryId: entry.id,
                    stageId: entry.stageId,
                    front: entry.front,
                    status: unlocked ? .available : .locked,
                    correctCount: 0,
                    wrongCount: 0,
                    correctStreak: 0,
                    dueAt: nil,
                    lastReviewedAt: nil,
                    masteredAt: nil,
                    flashcardId: nil,
                    createdAt: now,
                    updatedAt: now
                )
                dbManager.insertLifePathListRow(row)
            }
        }
    }

    private func reloadFromDB(language: LifePathLanguage) {
        profile = dbManager.fetchLifePathProfile(language: language.rawValue)
        let rows = dbManager.fetchLifePathList(language: language.rawValue)
        listRowsByEntryId = Dictionary(uniqueKeysWithValues: rows.map { ($0.entryId, $0) })
    }

    private func restorePendingNotify() {
        guard let json = profile?.pendingNotifyJSON,
              let data = json.data(using: .utf8),
              let notify = try? JSONDecoder().decode(LifePathLevelUpNotify.self, from: data) else {
            return
        }
        pendingLevelUp = notify
        showLevelUp = true
    }

    private static func todayString() -> String {
        dayString(Date())
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func parseDay(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
