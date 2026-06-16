import Foundation

extension AppConfig {
    static var builtin: AppConfig {
        AppConfig(
            openalex: OpenAlexConfig(
                base_url: "https://api.openalex.org/works",
                mailto: "",
                per_page: 100,
                default_days: 45,
                default_max_results: 1000,
                topic_filter: "topics.field.id:17"
            ),
            tracks: [:],
            filters: FiltersConfig(
                title_blacklist: [],
                source_blacklist: [],
                venue_blacklist: []
            ),
            scoring: ScoringConfig(
                tiers: builtinTiers,
                citation_breakpoints: [
                    CitationBreakpoint(up_to: 10, points_per_citation: 0.5),
                    CitationBreakpoint(up_to: 50, points_per_citation: 0.2),
                    CitationBreakpoint(up_to: nil, points_per_citation: 0.05)
                ],
                max_citation_points: 40
            ),
            recommendation: RecommendationConfig(
                daily_count: 3,
                quality_slots: 1,
                high_score_threshold: 5,
                recent_days: 30
            ),
            translate: TranslateConfig(
                provider: .deepseek,
                enabled: true,
                target_language: "中文",
                model: "deepseek-chat",
                base_url: "https://api.deepseek.com"
            )
        )
    }

    private static var builtinTiers: [String: ScoringTier] { [:] }
}
