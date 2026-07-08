import XCTest
import FSRS

final class FSRSIntegrationTests: XCTestCase {
    func testReviewGoodAdvancesDueDate() throws {
        let fsrs = FSRS(parameters: .init(w: FSRSDefaults.defaultWv6))
        let now = Date()
        let card = Card(due: now)

        let result = try fsrs.next(card: card, now: now, grade: .good)

        XCTAssertGreaterThan(result.card.due, now)
        XCTAssertEqual(result.card.reps, 1)
    }
}