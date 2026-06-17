import Foundation
import Observation

struct TrackPref: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var query: String
    var keywords: [String]
    var color: String? = nil
    var icon: String? = nil
    var archived: Bool = false
}

struct VenuePref: Codable, Identifiable, Equatable {
    var id = UUID()
    var abbr: String
    var phrase: String
    var tier: Int
    var field: String?
    var exact: Bool?
}

@MainActor
@Observable
final class LibrarySettings {
    static let shared = LibrarySettings()

    // Storage
    var storageDirectory: String { didSet { save() } }

    // Translation API
    var translateEnabled: Bool { didSet { save() } }
    var apiProvider: TranslationProvider {
        didSet {
            if oldValue != apiProvider {
                apiKey = apiKeys[apiProvider.rawValue] ?? ""
            }
            save()
        }
    }
    var apiBaseURL: String { didSet { save() } }
    var apiModel: String { didSet { save() } }
    var targetLanguage: String { didSet { save() } }
    var apiKey: String {
        didSet {
            apiKeys[apiProvider.rawValue] = apiKey.isEmpty ? nil : apiKey
            save()
        }
    }

    @ObservationIgnored private var apiKeys: [String: String] = [:]

    // OpenAlex fetch params
    var openAlexMailto: String { didSet { save() } }
    var perPage: Int { didSet { save() } }
    var defaultDays: Int { didSet { save() } }
    var defaultMaxResults: Int { didSet { save() } }
    var topicFilter: String { didSet { save() } }

    // Daily recommendation params
    var qualitySlots: Int { didSet { save() } }
    var recentSlots: Int { didSet { save() } }
    var highScoreThreshold: Int { didSet { save() } }
    var recentDays: Int { didSet { save() } }

    // Sort
    var sortKeyRaw: String { didSet { save() } }
    var sortAscending: Bool { didSet { save() } }

    private(set) var configVersion: Int = 0

    private let url: URL
    var settingsFileURL: URL { url }

    var resolvedStorageDirectory: URL {
        if !storageDirectory.isEmpty {
            return URL(fileURLWithPath: (storageDirectory as NSString).expandingTildeInPath)
        }
        return AppSupport.directory()
    }

    init(filename: String = "library_settings.json") {
        let dir = AppSupport.directory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent(filename)

        let stored = (try? Data(contentsOf: url)).flatMap {
            try? JSONDecoder().decode(Stored.self, from: $0)
        }
        let d = AppConfig.builtin
        func nonEmpty(_ value: String?, fallback: String) -> String {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return fallback
            }
            return value
        }

        let selectedProvider = stored?.apiProvider ?? d.translate.provider

        storageDirectory   = stored?.storageDirectory ?? ""
        translateEnabled   = stored?.translateEnabled ?? d.translate.enabled
        apiProvider        = selectedProvider
        apiBaseURL         = nonEmpty(stored?.apiBaseURL, fallback: d.translate.base_url)
        apiModel           = nonEmpty(stored?.apiModel, fallback: d.translate.model)
        targetLanguage     = nonEmpty(stored?.targetLanguage, fallback: d.translate.target_language)
        openAlexMailto     = stored?.openAlexMailto ?? d.openalex.mailto
        perPage            = stored?.perPage ?? d.openalex.per_page
        defaultDays        = stored?.defaultDays ?? d.openalex.default_days
        defaultMaxResults  = stored?.defaultMaxResults ?? d.openalex.default_max_results
        topicFilter        = stored?.topicFilter ?? d.openalex.topic_filter
        qualitySlots       = stored?.qualitySlots ?? d.recommendation.quality_slots
        recentSlots        = stored?.recentSlots ?? d.recommendation.recent_slots
        highScoreThreshold = stored?.highScoreThreshold ?? d.recommendation.high_score_threshold
        recentDays         = stored?.recentDays ?? d.recommendation.recent_days
        sortKeyRaw         = stored?.sortKeyRaw ?? SortKey.score.rawValue
        sortAscending      = stored?.sortAscending ?? false
        apiKeys = stored?.apiKeys ?? [:]
        apiKey   = apiKeys[selectedProvider.rawValue] ?? ""

        save()
    }

    private struct Stored: Codable {
        var storageDirectory: String?
        var translateEnabled: Bool?
        var apiProvider: TranslationProvider?
        var apiBaseURL: String?
        var apiModel: String?
        var targetLanguage: String?
        var openAlexMailto: String?
        var perPage: Int?
        var defaultDays: Int?
        var defaultMaxResults: Int?
        var topicFilter: String?
        var qualitySlots: Int?
        var recentSlots: Int?
        var highScoreThreshold: Int?
        var recentDays: Int?
        var sortKeyRaw: String?
        var sortAscending: Bool?
        var apiKeys: [String: String]?
    }

    private func save() {
        configVersion += 1
        let nonEmptyKeys = apiKeys.filter { !$0.value.isEmpty }
        let stored = Stored(
            storageDirectory: storageDirectory,
            translateEnabled: translateEnabled,
            apiProvider: apiProvider,
            apiBaseURL: apiBaseURL,
            apiModel: apiModel,
            targetLanguage: targetLanguage,
            openAlexMailto: openAlexMailto,
            perPage: perPage,
            defaultDays: defaultDays,
            defaultMaxResults: defaultMaxResults,
            topicFilter: topicFilter,
            qualitySlots: qualitySlots,
            recentSlots: recentSlots,
            highScoreThreshold: highScoreThreshold,
            recentDays: recentDays,
            sortKeyRaw: sortKeyRaw,
            sortAscending: sortAscending,
            apiKeys: nonEmptyKeys.isEmpty ? nil : nonEmptyKeys
        )
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(stored).write(to: url, options: .atomic)
    }
}
