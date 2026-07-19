import XCTest
import FSRS
@testable import DeveloperChatbotCore

final class LifePathSongTriggerTests: XCTestCase {
    func testWorkedTablePrefetchAndOffer_uniqueWordsSeen() {
        let everyN = 10
        // Unique words seen 1…7: nothing
        for g in 1...7 {
            XCTAssertFalse(LifePathSongConfig.shouldPrefetchSong(wordsSeenCount: g, everyN: everyN))
            XCTAssertFalse(LifePathSongConfig.shouldOfferSongBreak(wordsSeenCount: g, everyN: everyN))
        }
        // 8 unique words seen: prefetch only
        XCTAssertTrue(LifePathSongConfig.shouldPrefetchSong(wordsSeenCount: 8, everyN: everyN))
        XCTAssertFalse(LifePathSongConfig.shouldOfferSongBreak(wordsSeenCount: 8, everyN: everyN))
        // 9: nothing
        XCTAssertFalse(LifePathSongConfig.shouldPrefetchSong(wordsSeenCount: 9, everyN: everyN))
        XCTAssertFalse(LifePathSongConfig.shouldOfferSongBreak(wordsSeenCount: 9, everyN: everyN))
        // 10 unique words **seen** (not mastered): offer break
        XCTAssertFalse(LifePathSongConfig.shouldPrefetchSong(wordsSeenCount: 10, everyN: everyN))
        XCTAssertTrue(LifePathSongConfig.shouldOfferSongBreak(wordsSeenCount: 10, everyN: everyN))
        // 11: not offer
        XCTAssertFalse(LifePathSongConfig.shouldOfferSongBreak(wordsSeenCount: 11, everyN: everyN))
        // 18 / 20
        XCTAssertTrue(LifePathSongConfig.shouldPrefetchSong(wordsSeenCount: 18, everyN: everyN))
        XCTAssertTrue(LifePathSongConfig.shouldOfferSongBreak(wordsSeenCount: 20, everyN: everyN))
    }

    func testBreakDecadeSharedBetweenPrefetchAndPresent() {
        let everyN = 10
        XCTAssertEqual(LifePathSongConfig.breakDecade(8, everyN: everyN), 1)
        XCTAssertEqual(LifePathSongConfig.breakDecade(10, everyN: everyN), 1)
        XCTAssertEqual(LifePathSongConfig.breakDecade(18, everyN: everyN), 2)
        XCTAssertEqual(LifePathSongConfig.breakDecade(20, everyN: everyN), 2)
    }

    func testZeroSeenNeverTriggers() {
        XCTAssertFalse(LifePathSongConfig.shouldOfferSongBreak(wordsSeenCount: 0))
        XCTAssertFalse(LifePathSongConfig.shouldPrefetchSong(wordsSeenCount: 0))
    }

    func testWordsUntilSongBreak() {
        XCTAssertEqual(LifePathSongConfig.wordsUntilSongBreak(wordsSeenCount: 0, everyN: 10), 10)
        XCTAssertEqual(LifePathSongConfig.wordsUntilSongBreak(wordsSeenCount: 3, everyN: 10), 7)
        XCTAssertEqual(LifePathSongConfig.wordsUntilSongBreak(wordsSeenCount: 10, everyN: 10), 10)
        XCTAssertEqual(LifePathSongConfig.wordsUntilSongBreak(wordsSeenCount: 12, everyN: 10), 8)
    }
}

final class LRCParserTests: XCTestCase {
    func testParseBasicLines() {
        let raw = """
        [00:02.00]mama mama
        [00:04.50]baby ball
        """
        let lines = LRCParser.parse(raw)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].time, 2.0, accuracy: 0.001)
        XCTAssertEqual(lines[0].text, "mama mama")
        XCTAssertEqual(lines[1].time, 4.5, accuracy: 0.001)
    }

    func testExtractStripsMarkdownFence() {
        let raw = """
        ```lrc
        [00:02.00]hello
        ```
        """
        let lines = LRCParser.parse(raw)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "hello")
    }

    func testTemplateStaysInDuration() {
        let words = ["mama", "dada", "baby", "ball", "milk", "water", "hi", "bye"]
        let lrc = LRCParser.templateLyrics(words: words, duration: 12)
        let lines = LRCParser.parse(lrc)
        XCTAssertFalse(lines.isEmpty)
        for line in lines {
            XCTAssertGreaterThanOrEqual(line.time, 0)
            XCTAssertLessThanOrEqual(line.time, 12.5)
        }
    }
}

final class LyricsAllowlistValidatorTests: XCTestCase {
    private func enBank(fronts: [String]) -> LifePathSongBank.Bank {
        let words = fronts.enumerated().map { i, f in
            LifePathSongBank.Word(
                entryId: "e\(i)",
                front: f,
                back: "译\(i)",
                stageId: "baby",
                tier: .session
            )
        }
        return LifePathSongBank.Bank(
            contentWords: words,
            glueWords: LifePathSongConfig.englishClosedClassGlue,
            language: .en
        )
    }

    private func zhBank(fronts: [String]) -> LifePathSongBank.Bank {
        let words = fronts.enumerated().map { i, f in
            LifePathSongBank.Word(
                entryId: "z\(i)",
                front: f,
                back: "en\(i)",
                stageId: "baby",
                tier: .session
            )
        }
        return LifePathSongBank.Bank(
            contentWords: words,
            glueWords: LifePathSongConfig.chineseClosedClassGlue,
            language: .zh
        )
    }

    func testEnglishMultiWordFrontValidates() {
        let bank = enBank(fronts: ["good morning", "mama", "baby"])
        let lrc = """
        [00:02.00]good morning mama
        [00:04.00]baby baby
        [00:06.00]good morning
        [00:08.00]mama baby
        [00:10.00]the baby
        [00:11.00]mama mama
        """
        let result = LyricsAllowlistValidator.validate(lrc: lrc, bank: bank)
        XCTAssertTrue(result.timestampsInRange)
        XCTAssertLessThan(result.unknownRatio, 0.15, "unknowns: \(result.unknownTokens)")
        XCTAssertTrue(result.isAcceptable)
    }

    func testEnglishUnknownWordsRejected() {
        let bank = enBank(fronts: ["mama", "baby"])
        let lrc = """
        [00:02.00]quantum physics rocket ship explosion
        [00:04.00]another bad line full of junk words
        """
        let result = LyricsAllowlistValidator.validate(lrc: lrc, bank: bank)
        XCTAssertGreaterThanOrEqual(result.unknownRatio, 0.15)
        XCTAssertFalse(result.isAcceptable)
    }

    func testChineseGreedyCoverMama() {
        let bank = zhBank(fronts: ["妈妈", "宝宝", "球"])
        let lrc = """
        [00:02.00]妈妈妈妈
        [00:04.00]宝宝球
        [00:06.00]妈妈宝宝
        [00:08.00]球球
        [00:10.00]妈妈
        [00:11.00]宝宝
        """
        let result = LyricsAllowlistValidator.validate(lrc: lrc, bank: bank)
        XCTAssertTrue(result.isAcceptable, "ratio=\(result.unknownRatio) unk=\(result.unknownTokens)")
    }

    func testChineseBareSyllableNotFullyCoveredForMultiCharOnly() {
        // Bank has 妈妈 only — bare 妈 should leave uncovered chars
        let bank = zhBank(fronts: ["妈妈"])
        let lrc = """
        [00:02.00]妈
        [00:04.00]妈
        """
        let result = LyricsAllowlistValidator.validate(lrc: lrc, bank: bank)
        // 妈 alone is not a key unless expanded from CJK runs of 妈妈 —
        // cjkRuns from "妈妈" yields "妈妈" whole, not 妈. So bare 妈 is unknown.
        XCTAssertGreaterThan(result.unknownRatio, 0.5)
    }

    func testGlueOnlyCannotPassMinContent() {
        let bank = LifePathSongBank.Bank(
            contentWords: [],
            glueWords: LifePathSongConfig.englishClosedClassGlue,
            language: .en
        )
        XCTAssertLessThan(bank.contentWords.count, LifePathSongConfig.minContentWordsForSong)
    }

    func testTimestampOutOfRangeFails() {
        let bank = enBank(fronts: ["mama", "baby", "ball", "milk", "water", "hi"])
        let lrc = """
        [00:02.00]mama baby
        [01:00.00]ball milk
        """
        let result = LyricsAllowlistValidator.validate(lrc: lrc, bank: bank, duration: 12)
        XCTAssertFalse(result.timestampsInRange)
        XCTAssertFalse(result.isAcceptable)
    }
}

final class LifePathSongBankTests: XCTestCase {
    private let stages: [LifePathStageMeta] = [
        LifePathStageMeta(id: "baby", order: 0, title: ["en": "Baby"], subtitle: nil, targetCount: 10),
        LifePathStageMeta(id: "toddler", order: 1, title: ["en": "Toddler"], subtitle: nil, targetCount: 10)
    ]

    private func makeRow(
        entryId: String,
        stage: String,
        front: String,
        reps: Int,
        locked: Bool = false
    ) -> (LifePathEntry, LifePathListRow) {
        let entry = LifePathEntry(
            id: entryId,
            stageId: stage,
            rankInStage: 1,
            front: front,
            back: front,
            phonics: nil,
            tags: nil
        )
        var card = FSRSManager.shared.createEmptyCard()
        card.reps = reps
        if reps >= 2 {
            card.state = .review
        } else if reps == 1 {
            card.state = .learning
        }
        let row = LifePathListRow(
            rowId: UUID().uuidString,
            language: "en",
            entryId: entryId,
            stageId: stage,
            front: front,
            status: locked ? .locked : LifePathScheduler.deriveStatus(isLocked: false, card: card),
            fsrsCard: card
        )
        return (entry, row)
    }

    func testSessionWordsIncludedFirst() {
        let (e1, r1) = makeRow(entryId: "a", stage: "baby", front: "mama", reps: 0)
        let (e2, r2) = makeRow(entryId: "b", stage: "baby", front: "dada", reps: 2)
        // After grade, session includes a even with reps 0 historically — bank uses session list
        var rows = [r1.entryId: r1, r2.entryId: r2]
        // Simulate post-grade: a has reps 1
        var card = r1.fsrsCard
        card.reps = 1
        card.state = .learning
        var updated = r1
        updated.fsrsCard = card
        updated.status = .learning
        rows[r1.entryId] = updated

        let bank = LifePathSongBank.buildBank(
            language: .en,
            rows: rows,
            entriesById: [e1.id: e1, e2.id: e2],
            sessionGradedIds: ["a"],
            stages: stages,
            currentStageId: "baby"
        )
        XCTAssertEqual(bank.contentWords.first?.front, "mama")
        XCTAssertEqual(bank.contentWords.first?.tier, .session)
        XCTAssertTrue(bank.contentWords.contains(where: { $0.front == "dada" && $0.tier == .stable }))
    }

    func testLockedExcluded() {
        let (e1, r1) = makeRow(entryId: "a", stage: "toddler", front: "truck", reps: 3, locked: true)
        let (e2, r2) = makeRow(entryId: "b", stage: "baby", front: "mama", reps: 2)
        let bank = LifePathSongBank.buildBank(
            language: .en,
            rows: [r1.entryId: r1, r2.entryId: r2],
            entriesById: [e1.id: e1, e2.id: e2],
            sessionGradedIds: [],
            stages: stages,
            currentStageId: "baby"
        )
        XCTAssertFalse(bank.contentWords.contains(where: { $0.front == "truck" }))
        XCTAssertTrue(bank.contentWords.contains(where: { $0.front == "mama" }))
    }

    func testNewNeverGradedExcludedWithoutSession() {
        let (e1, r1) = makeRow(entryId: "a", stage: "baby", front: "mama", reps: 0)
        let bank = LifePathSongBank.buildBank(
            language: .en,
            rows: [r1.entryId: r1],
            entriesById: [e1.id: e1],
            sessionGradedIds: [],
            stages: stages,
            currentStageId: "baby"
        )
        XCTAssertTrue(bank.contentWords.isEmpty)
    }
}

final class MusicAPIClientTests: XCTestCase {
    func testWAVHeaderDetection() {
        var data = Data([0x52, 0x49, 0x46, 0x46]) // RIFF
        data.append(contentsOf: [0, 0, 0, 0])
        XCTAssertTrue(MusicAPIClient.isWAVData(data))
        XCTAssertFalse(MusicAPIClient.isWAVData(Data([0x00, 0x01])))
    }
}

final class LyricsGlossBuilderTests: XCTestCase {
    func testEnglishPhraseGlossUnderLine() {
        let bank = LifePathSongBank.Bank(
            contentWords: [
                .init(entryId: "1", front: "good morning", back: "早上好", stageId: "baby", tier: .session),
                .init(entryId: "2", front: "mama", back: "妈妈", stageId: "baby", tier: .session),
            ],
            glueWords: LifePathSongConfig.englishClosedClassGlue,
            language: .en
        )
        let map = LyricsGlossBuilder.translationMap(from: bank)
        let gloss = LyricsGlossBuilder.glossForLine(
            "good morning mama",
            language: .en,
            translationMap: map,
            glueKeys: Set(bank.glueWords.map { PracticeScaffolding.normalizeFrontKey($0) })
        )
        XCTAssertEqual(gloss, "早上好 妈妈")
    }

    func testEnglishSkipsGlue() {
        let bank = LifePathSongBank.Bank(
            contentWords: [
                .init(entryId: "1", front: "mama", back: "妈妈", stageId: "baby", tier: .session),
                .init(entryId: "2", front: "baby", back: "宝宝", stageId: "baby", tier: .session),
            ],
            glueWords: LifePathSongConfig.englishClosedClassGlue,
            language: .en
        )
        let map = LyricsGlossBuilder.translationMap(from: bank)
        let gloss = LyricsGlossBuilder.glossForLine(
            "the mama and baby",
            language: .en,
            translationMap: map,
            glueKeys: Set(bank.glueWords.map { PracticeScaffolding.normalizeFrontKey($0) })
        )
        XCTAssertEqual(gloss, "妈妈 宝宝")
    }

    func testChineseGlossUnderLine() {
        let bank = LifePathSongBank.Bank(
            contentWords: [
                .init(entryId: "1", front: "妈妈", back: "mama", stageId: "baby", tier: .session),
                .init(entryId: "2", front: "宝宝", back: "baby", stageId: "baby", tier: .session),
            ],
            glueWords: LifePathSongConfig.chineseClosedClassGlue,
            language: .zh
        )
        let map = LyricsGlossBuilder.translationMap(from: bank)
        let gloss = LyricsGlossBuilder.glossForLine(
            "妈妈宝宝",
            language: .zh,
            translationMap: map,
            glueKeys: Set(bank.glueWords.map { PracticeScaffolding.normalizeFrontKey($0) })
        )
        XCTAssertEqual(gloss, "mama baby")
    }

    func testGlossLinesAlignWithLRC() {
        let bank = LifePathSongBank.Bank(
            contentWords: [
                .init(entryId: "1", front: "mama", back: "妈妈", stageId: "baby", tier: .session),
            ],
            glueWords: [],
            language: .en
        )
        let lines = [
            LRCLine(index: 0, time: 2, text: "mama mama"),
            LRCLine(index: 1, time: 4, text: "la la"),
        ]
        let gloss = LyricsGlossBuilder.glossLines(for: lines, bank: bank)
        XCTAssertEqual(gloss.count, 2)
        XCTAssertEqual(gloss[0].translation, "妈妈 妈妈")
        XCTAssertEqual(gloss[1].translation, "")
    }
}
