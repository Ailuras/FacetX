import Foundation

struct TrackConfig {
    var query: String
    var keywords: [String]
}

struct ScoringTier {
    var points: Int
}

struct CitationBreakpoint: Codable {
    var up_to: Int?
    var points_per_citation: Double
}

struct ScoringConfig {
    var tiers: [String: ScoringTier]
    var citation_breakpoints: [CitationBreakpoint]
    var max_citation_points: Int
}

struct RecommendationConfig {
    var daily_count: Int
    var quality_slots: Int
    var high_score_threshold: Int
    var recent_days: Int
}

enum TranslationProvider: String, Codable, CaseIterable {
    case deepseek = "deepseek"
    case openai = "openai"
    case anthropic = "anthropic"

    var displayName: String {
        switch self {
        case .deepseek:  return "DeepSeek"
        case .openai:    return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepseek:  return "https://api.deepseek.com"
        case .openai:    return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek:  return "deepseek-chat"
        case .openai:    return "gpt-4o-mini"
        case .anthropic: return "claude-3-5-haiku-20241022"
        }
    }

    var modelsEndpoint: String {
        switch self {
        case .deepseek, .openai:
            return "/models"
        case .anthropic:
            return ""
        }
    }

    var chatEndpoint: String {
        switch self {
        case .deepseek, .openai:
            return "/chat/completions"
        case .anthropic:
            return "/messages"
        }
    }

    var authHeaderName: String {
        switch self {
        case .deepseek, .openai:
            return "Authorization"
        case .anthropic:
            return "x-api-key"
        }
    }

    var authHeaderValuePrefix: String {
        switch self {
        case .deepseek, .openai:
            return "Bearer "
        case .anthropic:
            return ""
        }
    }

    var requiresVersionHeader: Bool {
        self == .anthropic
    }
}

struct TranslateConfig {
    var provider: TranslationProvider
    var enabled: Bool
    var target_language: String
    var model: String
    var base_url: String
}

struct FiltersConfig {
    var title_blacklist: [String]?
    var source_blacklist: [String]?
    var venue_blacklist: [String]?
}

struct OpenAlexConfig {
    var base_url: String
    var mailto: String
    var per_page: Int
    var default_days: Int
    var default_max_results: Int
    var topic_filter: String
}

struct AppConfig {
    var openalex: OpenAlexConfig
    var tracks: [String: TrackConfig]
    var filters: FiltersConfig?
    var scoring: ScoringConfig
    var recommendation: RecommendationConfig
    var translate: TranslateConfig
}

@MainActor
class ConfigManager {
    static let shared = ConfigManager()

    private var cached: AppConfig?
    private var cachedVersion: Int = -1

    private init() {}

    var effectiveConfig: AppConfig {
        let version = LibrarySettings.shared.configVersion * 1_000_000 + MetadataStore.shared.metadataVersion
        if let cached, cachedVersion == version { return cached }
        let cfg = buildConfig()
        cached = cfg
        cachedVersion = version
        return cfg
    }

    private func buildConfig() -> AppConfig {
        var cfg = AppConfig.builtin
        let s = LibrarySettings.shared

        let metadata = MetadataStore.shared

        if !metadata.venues.isEmpty {
            var tiers: [String: ScoringTier] = [:]
            for tier in Set(metadata.venues.map(\.tier)) {
                let points = metadata.tiers.first(where: { $0.rank == tier })?.points
                    ?? MetadataStore.tierPoints[tier]
                    ?? max(1, 12 - 2 * tier)
                tiers[String(tier)] = ScoringTier(points: points)
            }
            cfg.scoring.tiers = tiers
        }

        cfg.scoring.citation_breakpoints = metadata.citationBreakpoints
        cfg.scoring.max_citation_points = metadata.maxCitationPoints

        cfg.recommendation = RecommendationConfig(
            daily_count: 3,
            quality_slots: 1,
            high_score_threshold: 5,
            recent_days: 30
        )
        cfg.openalex.mailto = s.openAlexMailto
        cfg.openalex.per_page = s.perPage
        cfg.openalex.default_days = s.defaultDays
        cfg.openalex.default_max_results = s.defaultMaxResults
        cfg.translate.provider = s.apiProvider
        cfg.translate.enabled = s.translateEnabled
        if !s.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cfg.translate.base_url = s.apiBaseURL
        }
        if !s.apiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cfg.translate.model = s.apiModel
        }
        if !s.targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cfg.translate.target_language = s.targetLanguage
        }
        let activeTopics = metadata.topics.filter { !$0.archived }
        if !activeTopics.isEmpty {
            cfg.tracks = Dictionary(uniqueKeysWithValues: activeTopics.map {
                ($0.name, TrackConfig(query: $0.query, keywords: $0.keywords))
            })
        }
        return cfg
    }
}
