import Foundation
import Observation

/// One academic track: an OpenAlex search query plus the keywords used to keep
/// only relevant results. Editable in Settings.
struct TrackPref: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var query: String
    var keywords: [String]
    var color: String? = nil
    /// Optional SF Symbol shown in the sidebar instead of the default dot.
    var icon: String? = nil
    /// Archived topics are hidden from the sidebar and excluded from fetching /
    /// recommendation, but kept in the library and still exported.
    var archived: Bool = false
}

/// One venue rating used for scoring. `phrase` is matched (case-insensitive)
/// against the paper's venue; `abbr` is the short label; `tier` is the rating
/// (1 = strongest). Editable in Settings.
struct VenuePref: Codable, Identifiable, Equatable {
    var id = UUID()
    var abbr: String
    var phrase: String
    var tier: Int
    /// Research field abbreviation this venue belongs to (e.g. "SE", "AI",
    /// "FM", "PL", "AR", "DB"). A paper's field is its venue's field. Short
    /// codes keep manual venue entry consistent.
    var field: String?
    /// When true, `phrase` must equal the whole venue name (case-insensitive),
    /// not just be a substring. Used for short journal names like "Artificial
    /// Intelligence" that would otherwise over-match (AAAI, FLAIRS, …).
    var exact: Bool?
}

/// App-wide user settings, persisted as JSON under this app variant's
/// Application Support directory. This is the thin
/// config file: only global preferences and tuning knobs live here. The paper
/// taxonomy (tracks, venues, fields, tiers, label colors) is owned by
/// `MetadataStore` in the database; rarely-changed values (citation curve, base
/// URLs) come from `AppConfig.builtin`.
///
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    // ── General ──────────────────────────────────────────────────────────
    /// Folder holding `vellumx.db`. Empty = default (see `defaultStorageDirectory`).
    var storageDirectory: String { didSet { save() } }
    var menuBarEnabled: Bool { didSet { save() } }
    /// UI language. "en" or "zh". Default English.
    var language: String { didSet { save() } }

    // ── API (Translation) ────────────────────────────────────────────────
    var translateEnabled: Bool { didSet { save() } }
    var apiProvider: TranslationProvider {
        didSet {
            if oldValue != apiProvider {
                // Swap in the saved key for the newly selected provider instead of
                // clearing — this lets the user switch between providers without
                // re-entering keys they've already saved.
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

    /// Per-provider key backing store — not directly observed by SwiftUI.
    @ObservationIgnored private var apiKeys: [String: String] = [:]

    // ── Recommendation knobs ─────────────────────────────────────────────
    var dailyCount: Int { didSet { save() } }
    var qualitySlots: Int { didSet { save() } }
    var highScoreThreshold: Int { didSet { save() } }
    var recentDays: Int { didSet { save() } }

    // ── OpenAlex fetch params ────────────────────────────────────────────
    var openAlexMailto: String { didSet { save() } }
    var perPage: Int { didSet { save() } }
    var defaultDays: Int { didSet { save() } }
    var defaultMaxResults: Int { didSet { save() } }
    var topicFilter: String { didSet { save() } }

    // ── List sort (persisted) ────────────────────────────────────────────
    var sortKeyRaw: String { didSet { save() } }
    var sortAscending: Bool { didSet { save() } }

    /// Bumped on every `save()` so `ConfigManager` can cache `effectiveConfig`.
    private(set) var configVersion: Int = 0

    private let url: URL
    /// On-disk location of settings.json (the editable developer config).
    var settingsFileURL: URL { url }

    var resolvedStorageDirectory: URL {
        if !storageDirectory.isEmpty {
            return URL(fileURLWithPath: (storageDirectory as NSString).expandingTildeInPath)
        }
        return AppSettings.defaultStorageDirectory
    }

    /// Default home for the database: the conventional macOS application-data
    /// location. Kept local (not iCloud Drive) on purpose — the WAL-mode SQLite
    /// store has `-wal`/`-shm` sidecar files that iCloud would sync out of step
    /// with the main file and corrupt. Users can still point elsewhere.
    static var applicationSupportName: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "VellumXApplicationSupportName") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "VellumX"
    }

    static var defaultStorageDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(applicationSupportName)
    }

    init(filename: String = "settings.json") {
        let dir = Self.defaultStorageDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent(filename)

        let stored = (try? Data(contentsOf: url)).flatMap {
            try? JSONDecoder().decode(Stored.self, from: $0)
        }
        let d = AppConfig.builtin   // pull defaults from the built-in config
        func nonEmpty(_ value: String?, fallback: String) -> String {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return fallback
            }
            return value
        }

        let selectedProvider = stored?.apiProvider ?? d.translate.provider

        storageDirectory   = stored?.storageDirectory ?? ""
        menuBarEnabled     = stored?.menuBarEnabled ?? true
        language           = stored?.language ?? "en"
        translateEnabled   = stored?.translateEnabled ?? d.translate.enabled
        apiProvider        = selectedProvider
        apiBaseURL         = nonEmpty(stored?.apiBaseURL, fallback: d.translate.base_url)
        apiModel           = nonEmpty(stored?.apiModel, fallback: d.translate.model)
        targetLanguage     = nonEmpty(stored?.targetLanguage, fallback: d.translate.target_language)
        dailyCount         = stored?.dailyCount ?? d.recommendation.daily_count
        qualitySlots       = stored?.qualitySlots ?? d.recommendation.quality_slots
        highScoreThreshold = stored?.highScoreThreshold ?? d.recommendation.high_score_threshold
        recentDays         = stored?.recentDays ?? d.recommendation.recent_days
        openAlexMailto     = stored?.openAlexMailto ?? d.openalex.mailto
        perPage            = stored?.perPage ?? d.openalex.per_page
        defaultDays        = stored?.defaultDays ?? d.openalex.default_days
        defaultMaxResults  = stored?.defaultMaxResults ?? d.openalex.default_max_results
        topicFilter        = stored?.topicFilter ?? d.openalex.topic_filter
        sortKeyRaw         = stored?.sortKeyRaw ?? SortKey.score.rawValue
        sortAscending      = stored?.sortAscending ?? false
        // NOTE: didSet does not fire during init, so apiKeys is set directly.
        apiKeys = stored?.apiKeys ?? [:]
        apiKey   = apiKeys[selectedProvider.rawValue] ?? ""

        // Always rewrite through the current schema so retired fields disappear.
        save()
    }

    private struct Stored: Codable {
        var storageDirectory: String?
        var menuBarEnabled: Bool?
        var language: String?
        var translateEnabled: Bool?
        var apiProvider: TranslationProvider?
        var apiBaseURL: String?
        var apiModel: String?
        var targetLanguage: String?
        var dailyCount: Int?
        var qualitySlots: Int?
        var highScoreThreshold: Int?
        var recentDays: Int?
        var openAlexMailto: String?
        var perPage: Int?
        var defaultDays: Int?
        var defaultMaxResults: Int?
        var topicFilter: String?
        var sortKeyRaw: String?
        var sortAscending: Bool?
        var apiKeys: [String: String]?
    }

    private func save() {
        configVersion += 1
        let nonEmptyKeys = apiKeys.filter { !$0.value.isEmpty }
        let stored = Stored(
            storageDirectory: storageDirectory,
            menuBarEnabled: menuBarEnabled,
            language: language,
            translateEnabled: translateEnabled,
            apiProvider: apiProvider,
            apiBaseURL: apiBaseURL,
            apiModel: apiModel,
            targetLanguage: targetLanguage,
            dailyCount: dailyCount,
            qualitySlots: qualitySlots,
            highScoreThreshold: highScoreThreshold,
            recentDays: recentDays,
            openAlexMailto: openAlexMailto,
            perPage: perPage,
            defaultDays: defaultDays,
            defaultMaxResults: defaultMaxResults,
            topicFilter: topicFilter,
            sortKeyRaw: sortKeyRaw,
            sortAscending: sortAscending,
            apiKeys: nonEmptyKeys.isEmpty ? nil : nonEmptyKeys
        )
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(stored).write(to: url, options: .atomic)
    }
}
