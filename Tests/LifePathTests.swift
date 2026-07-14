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
        XCTAssertTrue(file.stages.contains(where: { $0.id == "preschool" }))
        XCTAssertEqual(file.entries.first?.stageId, "baby")
        let preschoolCount = file.entries.filter { $0.stageId == "preschool" }.count
        XCTAssertEqual(preschoolCount, 299)
        XCTAssertEqual(file.stages.first(where: { $0.id == "preschool" })?.order, 2)
        XCTAssertEqual(file.entries.count, 412)
    }

    func testBundledEnglishListLoadsAndValidates() throws {
        let file = try LifePathCatalog.loadList(language: .en)
        XCTAssertEqual(file.listId, "life_path_en")
        XCTAssertFalse(file.entries.isEmpty)
        XCTAssertTrue(LifePathValidation.validate(file).isEmpty)
        let babyCount = file.entries.filter { $0.stageId == "baby" }.count
        XCTAssertEqual(babyCount, 50)
        XCTAssertTrue(file.stages.contains(where: { $0.id == "preschool" }))
        let preschoolCount = file.entries.filter { $0.stageId == "preschool" }.count
        XCTAssertEqual(preschoolCount, 299)
        XCTAssertEqual(file.entries.count, 415)
        let firstPreschool = file.entries.first { $0.stageId == "preschool" }
        XCTAssertEqual(firstPreschool?.front, "teacher")
        XCTAssertEqual(firstPreschool?.back, "老师")
    }

    func testManifestLoads() throws {
        let manifest = try LifePathCatalog.loadManifest()
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.lists.count, 2)
        let en = try XCTUnwrap(manifest.lists.first { $0.id == "life_path_en" })
        let zh = try XCTUnwrap(manifest.lists.first { $0.id == "life_path_zh" })
        XCTAssertEqual(en.entryCount, 415)
        XCTAssertEqual(zh.entryCount, 412)
    }

    func testValidationRejectsDuplicateFront() throws {
        let json = """
        {
          "listId": "life_path_en",
          "listVersion": 1,
          "language": "en",
          "stages": [
            {"id":"baby","order":0,"title":{"en":"Baby"},"targetCount":2}
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
    func testProfileListAndUnlockCRUD() throws {
        let path = NSTemporaryDirectory() + "life-path-test-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let db = DatabaseManager(databasePath: path)
        let now = Date()

        let profile = LifePathProfile(
            language: "en",
            currentStageId: "baby",
            highestStageId: "baby",
            xp: 0,
            coins: 0,
            lifetimeXp: 0,
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
        XCTAssertEqual(loaded?.currentStageId, "baby")
        XCTAssertEqual(loaded?.totalReviews, 1)
        // Economy columns are inert scaffolding — always 0 in product paths.
        XCTAssertEqual(loaded?.xp, 0)
        XCTAssertEqual(loaded?.coins, 0)

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

        db.resetLifePathProgress(language: "en")
        XCTAssertEqual(db.countLifePathList(language: "en"), 0)
        XCTAssertNil(db.fetchLifePathProfile(language: "en"))
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

        LifePathPreferences.language = nil
    }

    func testDevResetClearsLanguageAndShowsPicker() throws {
        let path = NSTemporaryDirectory() + "life-path-reset-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let db = DatabaseManager(databasePath: path)
        LifePathPreferences.language = .en
        defer { LifePathPreferences.language = nil }

        let vm = LifePathViewModel(dbManager: db)
        vm.load()
        XCTAssertEqual(vm.language, .en)
        XCTAssertFalse(vm.showLanguagePicker)
        XCTAssertGreaterThan(db.countLifePathList(language: "en"), 0)

        vm.resetProgressForTesting()

        XCTAssertNil(LifePathPreferences.language)
        XCTAssertNil(vm.language)
        XCTAssertTrue(vm.showLanguagePicker)
        XCTAssertNil(vm.profile)
        XCTAssertEqual(db.countLifePathList(language: "en"), 0)
        XCTAssertNil(db.fetchLifePathProfile(language: "en"))
    }
}

// MARK: - Pronunciation assessment client contracts (v2.2 — word-level only)

final class PronunciationAssessmentTests: XCTestCase {
    func testDecodeAssessResponseWithFeedback() throws {
        let json = """
        {
          "overall_score": 0.78,
          "is_correct": false,
          "predicted_phonemes": ["B","AA1","D","AH0","L"],
          "target_phonemes": ["B","AA1","T","AH0","L"],
          "feedback": "Close — try once more, a bit clearer."
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(PronunciationAssessmentResponse.self, from: json)
        XCTAssertEqual(result.overall_score, 0.78, accuracy: 0.001)
        XCTAssertFalse(result.is_correct)
        XCTAssertNil(result.phonemes)
        XCTAssertEqual(result.feedback, "Close — try once more, a bit clearer.")
        XCTAssertEqual(result.displayFeedback, "Close — try once more, a bit clearer.")
        XCTAssertTrue(result.diagnosticSummary.contains("heard="))
    }

    func testDecodeAssessResponseWithDebugBlock() throws {
        let json = """
        {
          "overall_score": 0.0,
          "is_correct": false,
          "predicted_phonemes": [],
          "target_phonemes": ["B","EY1","B","IY0"],
          "feedback": "No speech detected — try again closer to the mic.",
          "debug": {
            "reason": "silent_audio",
            "audio": {"duration_ms": 400, "samples": 6400, "rms": 0.001, "peak": 0.002, "is_silent": true},
            "target_normalized": ["b","ey","b","iy"],
            "predicted_normalized": []
          }
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(PronunciationAssessmentResponse.self, from: json)
        XCTAssertEqual(result.debug?.reason, "silent_audio")
        XCTAssertEqual(result.debug?.audio?.is_silent, true)
        XCTAssertTrue(result.diagnosticSummary.contains("SILENT") || result.diagnosticSummary.contains("silent=true"))
    }

    func testDecodeAssessResponseWithoutFeedback() throws {
        let json = """
        {
          "overall_score": 0.9,
          "is_correct": true,
          "predicted_phonemes": ["HH","AY1"],
          "target_phonemes": ["HH","AY1"]
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(PronunciationAssessmentResponse.self, from: json)
        XCTAssertTrue(result.is_correct)
        XCTAssertNil(result.feedback)
        XCTAssertNil(result.phonemes)
        XCTAssertEqual(result.displayFeedback, "Great pronunciation!")
    }

    func testDecodeWebSocketResultEnvelope() throws {
        // Server sends {"type":"result", ...fields}. Extra keys must be ignored.
        // v2.2+: no phonemes array; word-level feedback only.
        let json = """
        {
          "type": "result",
          "overall_score": 0.5,
          "is_correct": false,
          "predicted_phonemes": ["K","T"],
          "target_phonemes": ["K","AE1","T"],
          "feedback": "Close — try once more, a bit clearer."
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(PronunciationAssessmentResponse.self, from: json)
        XCTAssertNil(result.phonemes)
        XCTAssertEqual(result.displayFeedback, "Close — try once more, a bit clearer.")
    }

    func testDefaultAssessURL() {
        XCTAssertEqual(
            PronunciationEndpoint.defaultAssessURL,
            "https://pronunciation_assessment.npro.ai/assess"
        )
        XCTAssertEqual(
            PronunciationEndpoint.resolvedAssessURL(nil),
            PronunciationEndpoint.defaultAssessURL
        )
        XCTAssertEqual(
            PronunciationEndpoint.resolvedAssessURL(""),
            PronunciationEndpoint.defaultAssessURL
        )
        XCTAssertEqual(
            PronunciationEndpoint.resolvedAssessURL("   "),
            PronunciationEndpoint.defaultAssessURL
        )
        XCTAssertEqual(
            PronunciationEndpoint.resolvedAssessURL("https://custom.example/assess"),
            "https://custom.example/assess"
        )
    }

    func testWebSocketURLConversion() {
        XCTAssertEqual(
            PronunciationEndpoint.webSocketURL(from: "https://pronunciation_assessment.npro.ai/assess"),
            "wss://pronunciation_assessment.npro.ai/ws/assess"
        )
        XCTAssertEqual(
            PronunciationEndpoint.webSocketURL(from: "http://192.168.1.10:8086/assess"),
            "ws://192.168.1.10:8086/ws/assess"
        )
        XCTAssertEqual(
            PronunciationEndpoint.webSocketURL(from: "wss://pronunciation_assessment.npro.ai/ws/assess"),
            "wss://pronunciation_assessment.npro.ai/ws/assess"
        )
    }

    func testHTTPAssessURLConversion() {
        XCTAssertEqual(
            PronunciationEndpoint.httpAssessURL(from: "wss://pronunciation_assessment.npro.ai/ws/assess"),
            "https://pronunciation_assessment.npro.ai/assess"
        )
        XCTAssertEqual(
            PronunciationEndpoint.httpAssessURL(from: "https://pronunciation_assessment.npro.ai/assess"),
            "https://pronunciation_assessment.npro.ai/assess"
        )
    }

    func testWAVHeaderWrapsFloat32PCM() {
        let samples = [Float32](repeating: 0.1, count: 160)
        let pcm = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let wav = LifePathViewModel.wrapFloat32PCMasWAV(pcm, sampleRate: 16000)
        XCTAssertNotNil(wav)
        guard let wav else { return }
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertEqual(wav.count, 44 + pcm.count)
    }
}
