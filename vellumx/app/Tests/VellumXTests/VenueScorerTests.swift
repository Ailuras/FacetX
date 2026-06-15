import XCTest
@testable import VellumX

final class VenueScorerTests: XCTestCase {

    // MARK: - Venue matching

    func testExactMatchWins() {
        let venues: [VenuePref] = [
            VenuePref(abbr: "AIJ-EXACT", phrase: "artificial intelligence", tier: 2, field: nil, exact: true),
            VenuePref(abbr: "AI-SUB",    phrase: "artificial intelligence", tier: 1, field: nil, exact: false)
        ]
        let scorer = VenueScorer(config: .forTesting(venues: venues, tiers: ["1": ScoringTier(points: 10), "2": ScoringTier(points: 7)]), venues: venues)
        let result = scorer.evaluate(venue: "Artificial Intelligence", citations: 0)
        XCTAssertEqual(result.abbr, "AIJ-EXACT")
        XCTAssertEqual(result.tier, 2)
    }

    func testLongestSubstringWins() {
        let venues: [VenuePref] = [
            VenuePref(abbr: "ICSE", phrase: "international conference on software engineering", tier: 2, field: nil),
            VenuePref(abbr: "SE",   phrase: "software engineering",                              tier: 1, field: nil)
        ]
        let scorer = VenueScorer(config: .forTesting(venues: venues, tiers: ["1": ScoringTier(points: 10), "2": ScoringTier(points: 7)]), venues: venues)
        let result = scorer.evaluate(venue: "ACM/IEEE International Conference on Software Engineering", citations: 0)
        XCTAssertEqual(result.abbr, "ICSE")
        XCTAssertEqual(result.tier, 2)
    }

    func testTieBreakByTier() {
        // Equal-length phrases: lower tier number (stronger venue) wins.
        let venues: [VenuePref] = [
            VenuePref(abbr: "WEAK",   phrase: "machine learning", tier: 2, field: nil),
            VenuePref(abbr: "STRONG", phrase: "machine learning", tier: 1, field: nil)
        ]
        let scorer = VenueScorer(config: .forTesting(venues: venues, tiers: ["1": ScoringTier(points: 10), "2": ScoringTier(points: 7)]), venues: venues)
        let result = scorer.evaluate(venue: "Conference on Machine Learning 2024", citations: 0)
        XCTAssertEqual(result.abbr, "STRONG")
        XCTAssertEqual(result.tier, 1)
    }

    func testUnknownVenueDefaults() {
        let scorer = VenueScorer(config: .forTesting(), venues: [])
        let result = scorer.evaluate(venue: "Some Unknown Workshop", citations: 0)
        XCTAssertEqual(result.tier, 0)
        XCTAssertEqual(result.abbr, "Others")
    }

    func testEmptyVenueDefaults() {
        let scorer = VenueScorer(config: .forTesting(), venues: [])
        let result = scorer.evaluate(venue: "", citations: 0)
        XCTAssertEqual(result.tier, 0)
        XCTAssertEqual(result.abbr, "Others")
    }

    func testExactMatchDuplicateKeepsLowestTier() {
        // Two exact rules with same phrase: lower tier (stronger) should survive init dedup.
        let venues: [VenuePref] = [
            VenuePref(abbr: "WEAK",   phrase: "science", tier: 3, field: nil, exact: true),
            VenuePref(abbr: "STRONG", phrase: "science", tier: 1, field: nil, exact: true)
        ]
        let scorer = VenueScorer(config: .forTesting(venues: venues, tiers: ["1": ScoringTier(points: 10), "3": ScoringTier(points: 3)]), venues: venues)
        let result = scorer.evaluate(venue: "Science", citations: 0)
        XCTAssertEqual(result.abbr, "STRONG")
        XCTAssertEqual(result.tier, 1)
    }

    // MARK: - Blacklist

    func testBlacklistForcesZeroTier() {
        let venues: [VenuePref] = [
            VenuePref(abbr: "IEEE-J", phrase: "ieee transactions", tier: 1, field: nil)
        ]
        let config = AppConfig.forTesting(
            venues: venues,
            venueBlacklist: ["ieee"],
            tiers: ["1": ScoringTier(points: 10)]
        )
        let scorer = VenueScorer(config: config, venues: venues)
        let result = scorer.evaluate(venue: "IEEE Transactions on Computers", citations: 0)
        XCTAssertEqual(result.tier, 0)
        XCTAssertEqual(result.abbr, "IEEE-J")    // abbr preserved even when blacklisted
        XCTAssertEqual(result.score, 0, accuracy: 0.001)
    }

    // MARK: - Citation scoring

    func testZeroCitations() {
        let scorer = VenueScorer(config: .forTesting(
            breakpoints: [CitationBreakpoint(up_to: nil, points_per_citation: 1.0)],
            maxCitationPoints: 100
        ), venues: [])
        XCTAssertEqual(scorer.evaluate(venue: "", citations: 0).score, 0.0, accuracy: 0.001)
    }

    func testCitationFirstBracketOnly() {
        // 5 citations × 1.0 = 5.0 (stays within first bracket of 10)
        let scorer = VenueScorer(config: .forTesting(
            breakpoints: [
                CitationBreakpoint(up_to: 10,  points_per_citation: 1.0),
                CitationBreakpoint(up_to: nil, points_per_citation: 0.1)
            ], maxCitationPoints: 100
        ), venues: [])
        XCTAssertEqual(scorer.evaluate(venue: "", citations: 5).score, 5.0, accuracy: 0.001)
    }

    func testCitationMultipleBrackets() {
        // 15 citations: 10×1.0 + 5×0.5 = 12.5
        let scorer = VenueScorer(config: .forTesting(
            breakpoints: [
                CitationBreakpoint(up_to: 10,  points_per_citation: 1.0),
                CitationBreakpoint(up_to: nil, points_per_citation: 0.5)
            ], maxCitationPoints: 100
        ), venues: [])
        XCTAssertEqual(scorer.evaluate(venue: "", citations: 15).score, 12.5, accuracy: 0.001)
    }

    func testCitationCapApplied() {
        // 1000 citations at 1.0/citation would be 1000, but cap is 5.
        let scorer = VenueScorer(config: .forTesting(
            breakpoints: [CitationBreakpoint(up_to: nil, points_per_citation: 1.0)],
            maxCitationPoints: 5
        ), venues: [])
        XCTAssertEqual(scorer.evaluate(venue: "", citations: 1000).score, 5.0, accuracy: 0.001)
    }

    func testTotalScoreComposition() {
        // Tier 1 venue (10 pts) + 5 citations × 1.0 = 15.0
        let venues: [VenuePref] = [
            VenuePref(abbr: "TOP", phrase: "top journal", tier: 1, field: nil)
        ]
        let config = AppConfig.forTesting(
            venues: venues,
            tiers: ["1": ScoringTier(points: 10)],
            breakpoints: [CitationBreakpoint(up_to: nil, points_per_citation: 1.0)],
            maxCitationPoints: 100
        )
        let scorer = VenueScorer(config: config, venues: venues)
        let result = scorer.evaluate(venue: "Top Journal of Everything", citations: 5)
        XCTAssertEqual(result.tier, 1)
        XCTAssertEqual(result.score, 15.0, accuracy: 0.001)
    }
}
