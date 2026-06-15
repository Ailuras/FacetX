import XCTest
@testable import VellumX

final class RecommendEngineTests: XCTestCase {

    // MARK: - Basic edge cases

    func testEmptyPapersReturnsEmpty() {
        let engine = RecommendEngine(config: .forTesting(dailyCount: 3))
        XCTAssert(engine.recommend(papers: []).isEmpty)
    }

    func testAllRecommendedReturnsEmpty() {
        let papers = (0..<5).map { makePaper(id: "p\($0)", isRecommended: true) }
        let engine = RecommendEngine(config: .forTesting(dailyCount: 3))
        XCTAssert(engine.recommend(papers: papers).isEmpty)
    }

    func testAlreadyRecommendedExcluded() {
        let recommended = (0..<4).map { makePaper(id: "rec\($0)", isRecommended: true) }
        let candidate   = makePaper(id: "candidate", isRecommended: false)
        let engine = RecommendEngine(config: .forTesting(dailyCount: 3, qualitySlots: 0))
        let results = engine.recommend(papers: recommended + [candidate])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].paper.id, "candidate")
    }

    // MARK: - Count behaviour

    func testResultCountRespectsDailyCount() {
        let papers = (0..<20).map { makePaper(id: "p\($0)") }
        let engine = RecommendEngine(config: .forTesting(dailyCount: 5, qualitySlots: 2))
        XCTAssertEqual(engine.recommend(papers: papers).count, 5)
    }

    func testPoolExhaustionReturnsPartial() {
        let papers = [makePaper(id: "a"), makePaper(id: "b")]
        let engine = RecommendEngine(config: .forTesting(dailyCount: 5, qualitySlots: 0))
        XCTAssertEqual(engine.recommend(papers: papers).count, 2)
    }

    func testQualitySlotsClampedToDailyCount() {
        // quality_slots=10 > daily_count=3: all 3 slots filled by quality-first logic.
        let papers = (0..<10).map { makePaper(id: "p\($0)", score: 20) }
        let engine = RecommendEngine(config: .forTesting(dailyCount: 3, qualitySlots: 10, highScoreThreshold: 5))
        XCTAssertEqual(engine.recommend(papers: papers).count, 3)
    }

    // MARK: - No duplicates

    func testNoDuplicatesInResult() {
        let papers = (0..<10).map { makePaper(id: "p\($0)") }
        let engine = RecommendEngine(config: .forTesting(dailyCount: 10, qualitySlots: 0))
        let results = engine.recommend(papers: papers)
        let ids = results.map(\.paper.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - Priority: quality slots

    func testQualitySlotPrefersHighScore() {
        // Exactly one high-score paper → quality slot must select it (deterministic).
        let highScore = makePaper(id: "high", score: 50)
        let lowScores = (0..<9).map { makePaper(id: "low\($0)", score: 0) }
        let engine = RecommendEngine(config: .forTesting(
            dailyCount: 1, qualitySlots: 1, highScoreThreshold: 10
        ))
        let results = engine.recommend(papers: [highScore] + lowScores, count: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].paper.id, "high")
    }

    func testZeroQualitySlotsOnlyRecency() {
        // With quality_slots=0, the single recent paper is chosen over an old high-scorer.
        let highOld    = makePaper(id: "highOld",   score: 100, publicationDate: "2000-01-01")
        let lowRecent  = makePaper(id: "lowRecent", score: 0,   publicationDate: dateString(daysAgo: 5))
        let engine = RecommendEngine(config: .forTesting(
            dailyCount: 1, qualitySlots: 0, recentDays: 30
        ))
        let results = engine.recommend(papers: [highOld, lowRecent], count: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].paper.id, "lowRecent")
    }

    // MARK: - Priority: recency slots

    func testRecencySlotPrefersRecent() {
        // Exactly one recent paper → recency slot must select it (deterministic).
        let recentPaper = makePaper(id: "recent", publicationDate: dateString(daysAgo: 5))
        let oldPapers   = (0..<9).map { makePaper(id: "old\($0)", publicationDate: "2020-01-01") }
        let engine = RecommendEngine(config: .forTesting(
            dailyCount: 1, qualitySlots: 0, highScoreThreshold: 100, recentDays: 30
        ))
        let results = engine.recommend(papers: [recentPaper] + oldPapers, count: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].paper.id, "recent")
    }

    // MARK: - Fallback

    func testFallbackPoolUsedWhenPendingEmpty() {
        // All unrecommended papers are starred (non-pending) → fallback pool used.
        let papers = (0..<5).map { makePaper(id: "s\($0)", status: .starred) }
        let engine = RecommendEngine(config: .forTesting(dailyCount: 3, qualitySlots: 0))
        let results = engine.recommend(papers: papers)
        XCTAssertEqual(results.count, 3)
        XCTAssert(results.allSatisfy { $0.paper.status == .starred })
    }
}
