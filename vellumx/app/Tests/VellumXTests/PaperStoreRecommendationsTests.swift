import XCTest
@testable import VellumX

@MainActor
final class PaperStoreRecommendationsTests: XCTestCase {
    func testCancelRecommendationClearsReasonAndDate() throws {
        let store = PaperStore(databaseURL: try temporaryDatabaseURL(self))
        _ = store.addOrUpdate(papers: [makePaper(id: "p1", title: "Paper One")])

        store.setPaperRecommended(id: "p1", isRecommended: true, reason: "Quality pick")
        XCTAssertTrue(try XCTUnwrap(store.papers.first).isRecommended)
        XCTAssertEqual(store.papers.first?.recommendationReason, "Quality pick")
        XCTAssertNotNil(store.papers.first?.recommendedAt)

        store.setPaperRecommended(id: "p1", isRecommended: false)
        let paper = try XCTUnwrap(store.papers.first)
        XCTAssertFalse(paper.isRecommended)
        XCTAssertEqual(paper.recommendationReason, "")
        XCTAssertNil(paper.recommendedAt)

        store.loadPapers()
        let reloaded = try XCTUnwrap(store.papers.first)
        XCTAssertFalse(reloaded.isRecommended)
        XCTAssertEqual(reloaded.recommendationReason, "")
        XCTAssertNil(reloaded.recommendedAt)
    }
}
