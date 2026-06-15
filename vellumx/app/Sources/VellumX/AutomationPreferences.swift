import Foundation
import Observation

@MainActor
@Observable
final class AutomationPreferences {
    static let shared = AutomationPreferences()

    var automationEnabled: Bool { didSet { save(automationEnabled, key: Keys.automationEnabled) } }
    var autoFetchEnabled: Bool { didSet { save(autoFetchEnabled, key: Keys.autoFetchEnabled) } }
    var autoRecommendEnabled: Bool { didSet { save(autoRecommendEnabled, key: Keys.autoRecommendEnabled) } }
    var lastAutoFetchAt: Date? { didSet { save(lastAutoFetchAt, key: Keys.lastAutoFetchAt) } }
    var lastAutoRecommendAt: Date? { didSet { save(lastAutoRecommendAt, key: Keys.lastAutoRecommendAt) } }

    /// Only hour / minute matter; the date part is a fixed reference.
    var recommendTime: Date { didSet { save(recommendTime, key: Keys.recommendTime) } }
    /// Day of month (1–28) for the monthly fetch.
    var fetchDay: Int { didSet { save(fetchDay, key: Keys.fetchDay) } }
    /// Only hour / minute matter for the monthly fetch.
    var fetchTime: Date { didSet { save(fetchTime, key: Keys.fetchTime) } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        automationEnabled = defaults.object(forKey: Keys.automationEnabled) as? Bool ?? false
        autoFetchEnabled = defaults.object(forKey: Keys.autoFetchEnabled) as? Bool ?? true
        autoRecommendEnabled = defaults.object(forKey: Keys.autoRecommendEnabled) as? Bool ?? true
        lastAutoFetchAt = defaults.object(forKey: Keys.lastAutoFetchAt) as? Date
        lastAutoRecommendAt = defaults.object(forKey: Keys.lastAutoRecommendAt) as? Date
        recommendTime = Self.readDate(defaults, key: Keys.recommendTime, calendar: calendar) ?? Self.defaultTime(calendar)
        fetchDay = defaults.object(forKey: Keys.fetchDay) as? Int ?? 1
        fetchTime = Self.readDate(defaults, key: Keys.fetchTime, calendar: calendar) ?? Self.defaultTime(calendar)
    }

    private func save(_ value: Bool, key: String) {
        defaults.set(value, forKey: key)
    }

    private func save(_ value: Int, key: String) {
        defaults.set(value, forKey: key)
    }

    private func save(_ value: Date?, key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func save(_ value: Date, key: String) {
        defaults.set(value, forKey: key)
    }

    private static func readDate(_ defaults: UserDefaults, key: String, calendar: Calendar) -> Date? {
        defaults.object(forKey: key) as? Date
    }

    private static func defaultTime(_ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    }

    private enum Keys {
        static let automationEnabled = "automation.enabled"
        static let autoFetchEnabled = "automation.fetch.monthly.enabled"
        static let autoRecommendEnabled = "automation.recommend.daily.enabled"
        static let lastAutoFetchAt = "automation.fetch.monthly.lastRun"
        static let lastAutoRecommendAt = "automation.recommend.daily.lastRun"
        static let recommendTime = "automation.recommend.daily.time"
        static let fetchDay = "automation.fetch.monthly.day"
        static let fetchTime = "automation.fetch.monthly.time"
    }
}
