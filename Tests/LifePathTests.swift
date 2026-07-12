import XCTest
@testable import DeveloperChatbotCore

final class LifePathCatalogTests: XCTestCase {
    func testBundledChineseListLoadsAndValidates() throws {
        let file = try LifePathCatalog.loadList(language: .zh)
        XCTAssertEqual(file.listId, "life_path_zh")
        XCTAssertFalse(file.entries.isEmpty)
        XCTAssertTrue(LifePathValidation.validate(file).isEmpty)
        XCTAssertTrue(file.stages.contains(where: { $0.id == "baby" }))
        XCTAssertTrue(file.stages.contains(where: { $0.id == "toddler" }))
        XCTAssertEqual(file.entries.first?.stageId, "baby")
    }

    func testBundledEnglishListLoadsAndValidates() throws {
        let file = try LifePathCatalog.loadList(language: .en)
        XCTAssertEqual(file.listId, "life_path_en")
        XCTAssertFalse(file.entries.isEmpty)
        XCTAssertTrue(LifePathValidation.validate(file).isEmpty)
        let babyCount = file.entries.filter { $0.stageId == "baby" }.count
        XCTAssertEqual(babyCount, 50)
    }

    func testManifestLoads() throws {
        let manifest = try LifePathCatalog.loadManifest()
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.lists.count, 2)
    }

    func testValidationRejectsDuplicateFront() throws {
        let json = """
        {
          "listId": "life_path_en",
          "listVersion": 1,
          "language": "en",
          "stages": [
            {"id":"baby","order":0,"title":{"en":"Baby"},"targetCount":2,"clearReward":{"xp":100,"coins":50}}
          ],
          "entries": [
            {"id":"a","stageId":"baby","rankInStage":1,"front":"mama","back":"妈妈","phonics":null,"tags":[]},
            {"id":"b","stageId":"baby","rankInStage":2,"front":"mama","back":"妈","phonics":null,"tags":[]}
          ]
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try LifePathCatalog.decodeAndValidate(data: json)) { error in
            guard case LifePathCatalogError.validationFailed(let issues) = error else {
                return XCTFail("Expected validationFailed, got \(error)")
            }
            XCTAssertTrue(issues.contains(where: { $0.contains("duplicate front") }))
        }
    }
}

final class LifePathDBTests: XCTestCase {
    func testProfileListAndRewardsCRUD() throws {
        let path = NSTemporaryDirectory() + "life-path-test-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let db = DatabaseManager(databasePath: path)
        let now = Date()

        let profile = LifePathProfile(
            language: "en",
            currentStageId: "baby",
            highestStageId: "baby",
            xp: 10,
            coins: 2,
            lifetimeXp: 10,
            streakDays: 1,
            lastPlayDay: "2026-07-12",
            totalReviews: 1,
            totalMastered: 0,
            stagesCleared: [],
            pendingNotifyJSON: nil,
            createdAt: now,
            updatedAt: now
        )
        db.upsertLifePathProfile(profile)
        let loaded = db.fetchLifePathProfile(language: "en")
        XCTAssertEqual(loaded?.xp, 10)
        XCTAssertEqual(loaded?.currentStageId, "baby")

        let row = LifePathListRow(
            rowId: UUID().uuidString,
            language: "en",
            entryId: "en_baby_001",
            stageId: "baby",
            front: "mama",
            status: .available,
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
        db.insertLifePathListRow(row)
        XCTAssertEqual(db.countLifePathList(language: "en"), 1)

        var updated = row
        updated.status = .mastered
        updated.correctCount = 2
        updated.correctStreak = 1
        updated.masteredAt = now
        updated.updatedAt = now
        db.upsertLifePathListRow(updated)
        let list = db.fetchLifePathList(language: "en")
        XCTAssertEqual(list.first?.status, .mastered)

        let toddler = LifePathListRow(
            rowId: UUID().uuidString,
            language: "en",
            entryId: "en_toddler_001",
            stageId: "toddler",
            front: "hello",
            status: .locked,
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
        db.insertLifePathListRow(toddler)
        db.unlockLifePathStage(language: "en", stageId: "toddler")
        let afterUnlock = db.fetchLifePathList(language: "en").first { $0.entryId == "en_toddler_001" }
        XCTAssertEqual(afterUnlock?.status, .available)

        let reward = LifePathRewardRow(
            id: UUID().uuidString,
            language: "en",
            rewardType: .xp,
            amount: 100,
            reason: "stage_clear",
            stageId: "baby",
            entryId: nil,
            metaJSON: nil,
            createdAt: now
        )
        db.insertLifePathReward(reward)
        let rewards = db.fetchRecentLifePathRewards(language: "en")
        XCTAssertEqual(rewards.count, 1)
        XCTAssertEqual(rewards.first?.amount, 100)
    }
}

@MainActor
final class LifePathViewModelTests: XCTestCase {
    func testSeedAndMasteryProgression() throws {
        let path = NSTemporaryDirectory() + "life-path-vm-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let db = DatabaseManager(databasePath: path)
        LifePathPreferences.language = .en

        let vm = LifePathViewModel(dbManager: db)
        vm.load()

        XCTAssertNil(vm.loadError)
        XCTAssertEqual(vm.profile?.currentStageId, "baby")
        XCTAssertGreaterThan(vm.totalInCurrentStage, 0)
        XCTAssertEqual(vm.masteredInCurrentStage, 0)

        // One correct = mastered
        vm.startRound()
        XCTAssertTrue(vm.isPlaying)
        guard let first = vm.currentCard else {
            return XCTFail("expected current card")
        }
        vm.revealAnswer()
        vm.gradeCorrect()
        let afterOne = db.fetchLifePathList(language: "en").first { $0.entryId == first.id }
        XCTAssertEqual(afterOne?.correctCount, 1)
        XCTAssertEqual(afterOne?.status, .mastered)
        XCTAssertGreaterThanOrEqual(vm.masteredInCurrentStage, 1)
        XCTAssertGreaterThan(vm.profile?.xp ?? 0, 0)
        XCTAssertGreaterThan(vm.profile?.coins ?? 0, 0)

        LifePathPreferences.language = nil
    }
}
