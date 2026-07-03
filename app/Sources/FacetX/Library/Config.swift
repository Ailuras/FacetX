import Foundation

struct TrackConfig {
    var query: String
    var keywords: [String]
}

struct ScoringTier {
    var points: Int
}

struct CitationBreakpoint: Codable, Identifiable, Equatable {
    var id = UUID()
    var up_to: Int?
    var points_per_citation: Double

    enum CodingKeys: String, CodingKey {
        case up_to
        case points_per_citation
    }

    init(up_to: Int?, points_per_citation: Double) {
        self.up_to = up_to
        self.points_per_citation = points_per_citation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        up_to = try container.decodeIfPresent(Int.self, forKey: .up_to)
        points_per_citation = try container.decode(Double.self, forKey: .points_per_citation)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(up_to, forKey: .up_to)
        try container.encode(points_per_citation, forKey: .points_per_citation)
    }
}

struct ScoringConfig {
    var tiers: [String: ScoringTier]
    var citation_breakpoints: [CitationBreakpoint]
    var max_citation_points: Int
    /// Tier assigned to papers whose venue matches no rule (the "Others" fallback).
    /// 0 means unranked (no tier points).
    var others_tier: Int = 0
}

struct RecommendationConfig {
    var quality_slots: Int
    var recent_slots: Int
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
        case .deepseek:  return "deepseek-v4-flash"
        case .openai:    return "gpt-5.4-mini"
        case .anthropic: return "claude-sonnet-5"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .deepseek:
            return ["deepseek-v4-flash", "deepseek-v4-pro"]
        case .openai:
            return ["gpt-5.4-mini", "gpt-5.4", "gpt-5.5"]
        case .anthropic:
            return ["claude-sonnet-5", "claude-opus-4-8", "claude-haiku-4-5"]
        }
    }

    var supportedAssistantEfforts: [AssistantReasoningEffort] {
        switch self {
        case .deepseek: return [.high, .max]
        case .openai: return [.low, .medium, .high, .xhigh]
        case .anthropic: return [.low, .medium, .high, .xhigh, .max]
        }
    }

    var defaultAssistantEffort: AssistantReasoningEffort {
        switch self {
        case .deepseek: return .high
        case .openai, .anthropic: return .medium
        }
    }

    var modelsEndpoint: String {
        switch self {
        case .deepseek, .openai:
            return "/models"
        case .anthropic:
            return "/models"
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

enum DeepSeekAPIFormat: String, Codable, CaseIterable, Identifiable {
    case openAI = "openai"
    case anthropic = "anthropic"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: return L10n.pick("OpenAI compatible", "OpenAI 兼容（Codex）")
        case .anthropic: return L10n.pick("Anthropic compatible", "Anthropic 兼容（Claude）")
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.deepseek.com"
        case .anthropic: return "https://api.deepseek.com/anthropic"
        }
    }
}

enum AssistantReasoningEffort: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case xhigh
    case max

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return L10n.pick("Low", "低")
        case .medium: return L10n.pick("Medium", "中")
        case .high: return L10n.pick("High", "高")
        case .xhigh: return L10n.pick("Extra High", "很高")
        case .max: return L10n.pick("Max", "最高")
        }
    }
}

struct TranslateConfig {
    var provider: TranslationProvider
    var deepseek_api_format: DeepSeekAPIFormat
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

        // Build tier points for every rank used by a venue rule, the configured
        // "Others" fallback, plus any rank defined in the Tier Points table.
        let ranks = Set(metadata.venues.map(\.tier))
            .union(metadata.tiers.map(\.rank))
            .union([metadata.othersTier])
        if !ranks.isEmpty {
            var tiers: [String: ScoringTier] = [:]
            for tier in ranks where tier != 0 {
                let points = metadata.tiers.first(where: { $0.rank == tier })?.points
                    ?? MetadataStore.tierPoints[tier]
                    ?? max(1, 12 - 2 * tier)
                tiers[String(tier)] = ScoringTier(points: points)
            }
            cfg.scoring.tiers = tiers
        }

        cfg.scoring.citation_breakpoints = metadata.citationBreakpoints
        cfg.scoring.max_citation_points = metadata.maxCitationPoints
        cfg.scoring.others_tier = metadata.othersTier

        cfg.recommendation = RecommendationConfig(
            quality_slots: s.qualitySlots,
            recent_slots: s.recentSlots,
            high_score_threshold: s.highScoreThreshold,
            recent_days: s.recentDays
        )
        cfg.openalex.mailto = s.openAlexMailto
        cfg.openalex.per_page = s.perPage
        cfg.openalex.default_days = s.defaultDays
        cfg.openalex.default_max_results = s.defaultMaxResults
        cfg.openalex.topic_filter = s.topicFilter
        cfg.translate.provider = s.apiProvider
        cfg.translate.deepseek_api_format = s.deepSeekAPIFormat
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
