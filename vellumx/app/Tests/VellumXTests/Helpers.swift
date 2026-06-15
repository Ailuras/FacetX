import Foundation
import XCTest
@testable import VellumX

// MARK: - AppConfig factory

extension AppConfig {
    static func forTesting(
        venues: [VenuePref] = [],
        venueBlacklist: [String] = [],
        tiers: [String: ScoringTier] = [:],
        breakpoints: [CitationBreakpoint] = [
            CitationBreakpoint(up_to: 10,  points_per_citation: 0.5),
            CitationBreakpoint(up_to: 50,  points_per_citation: 0.2),
            CitationBreakpoint(up_to: nil, points_per_citation: 0.05)
        ],
        maxCitationPoints: Int = 40,
        dailyCount: Int = 3,
        qualitySlots: Int = 1,
        highScoreThreshold: Int = 10,
        recentDays: Int = 30
    ) -> AppConfig {
        AppConfig(
            openalex: OpenAlexConfig(
                base_url: "https://api.openalex.org/works",
                mailto: "test@example.com",
                per_page: 100,
                default_days: 45,
                default_max_results: 1000,
                topic_filter: ""
            ),
            tracks: [:],
            filters: FiltersConfig(
                title_blacklist: [],
                source_blacklist: [],
                venue_blacklist: venueBlacklist
            ),
            scoring: ScoringConfig(
                tiers: tiers,
                citation_breakpoints: breakpoints,
                max_citation_points: maxCitationPoints
            ),
            recommendation: RecommendationConfig(
                daily_count: dailyCount,
                quality_slots: qualitySlots,
                high_score_threshold: highScoreThreshold,
                recent_days: recentDays
            ),
            translate: TranslateConfig(
                provider: .deepseek,
                enabled: false,
                target_language: "Chinese",
                model: "deepseek-chat",
                base_url: "https://api.deepseek.com"
            )
        )
    }
}

// MARK: - Paper factory

func makePaper(
    id: String = UUID().uuidString,
    title: String = "Test Paper",
    status: PaperStatus = .pending,
    score: Double = 0,
    publicationDate: String = "2020-01-01",
    isRecommended: Bool = false
) -> Paper {
    Paper(
        id: id,
        title: title,
        publicationDate: publicationDate,
        score: score,
        status: status,
        isRecommended: isRecommended
    )
}

// MARK: - Date helper

/// Returns an ISO date string N days before today, used for "recent paper" tests.
func dateString(daysAgo: Int) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    return formatter.string(from: date)
}

func temporaryDatabaseURL(_ testCase: XCTestCase) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("VellumXTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    testCase.addTeardownBlock {
        try? FileManager.default.removeItem(at: dir)
    }
    return dir.appendingPathComponent("vellumx.db")
}
