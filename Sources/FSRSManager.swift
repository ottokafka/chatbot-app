import Foundation
import FSRS

final class FSRSManager {
    static let shared = FSRSManager()

    private let fsrs = FSRS(parameters: .init(w: FSRSDefaults.defaultWv6))

    private init() {}

    func createEmptyCard(now: Date = Date()) -> Card {
        Card(due: now)
    }

    func review(card: Card, grade: Rating, now: Date = Date()) throws -> RecordLogItem {
        try fsrs.next(card: card, now: now, grade: grade)
    }

    func dueCards(from cards: [Flashcard], now: Date = Date()) -> [Flashcard] {
        cards.filter { $0.fsrsCard.due <= now }
    }
}