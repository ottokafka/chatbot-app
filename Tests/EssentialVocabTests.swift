import XCTest
@testable import DeveloperChatbotCore

final class EssentialVocabCatalogTests: XCTestCase {
    func testBundledChineseListLoadsAndValidates() throws {
        let file = try EssentialVocabCatalog.loadList(language: .zh)
        XCTAssertEqual(file.listId, "essential_zh")
        XCTAssertEqual(file.entries.count, 500)
        XCTAssertTrue(EssentialVocabValidation.validate(file).isEmpty)
        XCTAssertEqual(file.entries.first?.front, "的")
        XCTAssertEqual(file.entries.last?.rank, 500)
    }

    func testBundledEnglishListLoadsAndValidates() throws {
        let file = try EssentialVocabCatalog.loadList(language: .en)
        XCTAssertEqual(file.listId, "essential_en")
        XCTAssertEqual(file.entries.count, 500)
        XCTAssertTrue(EssentialVocabValidation.validate(file).isEmpty)
        XCTAssertEqual(file.entries.first?.front, "the")
        XCTAssertEqual(file.entries.last?.rank, 500)
        XCTAssertTrue(file.entries.contains(where: \.isFunctionWord))
    }

    func testValidationRejectsDuplicateFront() throws {
        let json = """
        {
          "listId": "essential_zh",
          "listVersion": 1,
          "language": "zh",
          "entries": [
            {"id":"a","rank":1,"front":"的","back":"x","phonics":"de","pos":null,"tags":[]},
            {"id":"b","rank":2,"front":"的","back":"y","phonics":"de","pos":null,"tags":[]}
          ]
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try EssentialVocabCatalog.decodeAndValidate(data: json)) { error in
            guard case EssentialVocabCatalogError.validationFailed(let issues) = error else {
                return XCTFail("Expected validationFailed, got \(error)")
            }
            XCTAssertTrue(issues.contains(where: { $0.contains("duplicate front") }))
        }
    }

    func testManifestLoads() throws {
        let manifest = try EssentialVocabCatalog.loadManifest()
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.lists.count, 2)
    }
}

final class EssentialVocabProgressDBTests: XCTestCase {
    func testProgressCRUDAndFlashcardLookup() throws {
        let path = NSTemporaryDirectory() + "essential-vocab-test-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let db = DatabaseManager(databasePath: path)

        db.upsertEssentialProgress(
            listId: "essential_zh",
            entryId: "zh_0001",
            status: .dismissed,
            flashcardId: nil
        )
        var progress = db.fetchEssentialProgress(listId: "essential_zh")
        XCTAssertEqual(progress["zh_0001"]?.status, .dismissed)

        let card = Flashcard(front: "的", back: "possessive", phonics: "de", kind: .vocab)
        XCTAssertNotNil(db.insertFlashcard(card))
        XCTAssertNotNil(db.flashcard(forFront: "的"))
        XCTAssertEqual(db.flashcard(id: card.id)?.front, "的")

        db.upsertEssentialProgress(
            listId: "essential_zh",
            entryId: "zh_0001",
            status: .added,
            flashcardId: card.id
        )
        progress = db.fetchEssentialProgress(listId: "essential_zh")
        XCTAssertEqual(progress["zh_0001"]?.status, .added)
        XCTAssertEqual(progress["zh_0001"]?.flashcardId, card.id)

        db.deleteEssentialProgress(listId: "essential_zh", entryId: "zh_0001")
        progress = db.fetchEssentialProgress(listId: "essential_zh")
        XCTAssertNil(progress["zh_0001"])
    }
}

@MainActor
final class EssentialVocabViewModelTests: XCTestCase {
    func testSnapshotBatchDoesNotRefillUntilContinue() throws {
        let path = NSTemporaryDirectory() + "essential-vm-test-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let db = DatabaseManager(databasePath: path)
        let vm = EssentialVocabViewModel(dbManager: db)
        EssentialVocabPreferences.listLanguage = .zh
        EssentialVocabPreferences.rankCap = 500
        defer {
            EssentialVocabPreferences.listLanguage = nil
        }

        vm.load(using: [])
        XCTAssertNil(vm.loadError)
        XCTAssertEqual(vm.batchEntryIds.count, 20)
        let firstBatch = vm.batchEntryIds

        // Triage all 20 in the snapshot
        for id in firstBatch {
            guard let entry = vm.entries.first(where: { $0.id == id }) else {
                return XCTFail("missing entry \(id)")
            }
            vm.dismiss(entry)
        }

        XCTAssertTrue(vm.batchExhaustedWithMorePending)
        XCTAssertTrue(vm.visibleEntries.isEmpty)
        XCTAssertGreaterThan(vm.pendingCount, 0)

        // Without Continue, higher ranks must not slide in
        XCTAssertEqual(vm.batchEntryIds, firstBatch)

        vm.continueBatch()
        XCTAssertEqual(vm.batchEntryIds.count, 20)
        XCTAssertNotEqual(Set(vm.batchEntryIds), Set(firstBatch))
        XCTAssertFalse(vm.batchExhaustedWithMorePending)
    }

    func testReconcileReopensPendingWhenCardDeleted() throws {
        let path = NSTemporaryDirectory() + "essential-reconcile-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let db = DatabaseManager(databasePath: path)
        let vm = EssentialVocabViewModel(dbManager: db)
        EssentialVocabPreferences.listLanguage = .zh
        defer { EssentialVocabPreferences.listLanguage = nil }

        vm.load(using: [])
        let entry = try XCTUnwrap(vm.entries.first)
        XCTAssertTrue(vm.addToDeck(entry))
        XCTAssertEqual(vm.effectiveStatus(entry), .added)

        // Simulate delete: remove card, leave progress with stale flashcard_id
        if let card = db.flashcard(forFront: entry.front) {
            db.deleteFlashcard(id: card.id)
        }
        vm.load(using: db.fetchFlashcards())
        XCTAssertNil(vm.effectiveStatus(entry), "deleted card should re-open pending (D13)")
    }
}
