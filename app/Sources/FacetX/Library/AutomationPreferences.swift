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

    /// Day of month (1-28) for the monthly fetch.
    var fetchDay: Int { didSet { save(fetchDay, key: Keys.fetchDay) } }
    /// Only hour/minute matter.
    var fetchTime: Date { didSet { save(fetchTime, key: Keys.fetchTime) } }
    /// Only hour/minute matter.
    var recommendTime: Date { didSet { save(recommendTime, key: Keys.recommendTime) } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        automationEnabled = defaults.object(forKey: Keys.automationEnabled) as? Bool ?? false
        autoFetchEnabled = defaults.object(forKey: Keys.autoFetchEnabled) as? Bool ?? false
        autoRecommendEnabled = defaults.object(forKey: Keys.autoRecommendEnabled) as? Bool ?? false
        lastAutoFetchAt = defaults.object(forKey: Keys.lastAutoFetchAt) as? Date
        lastAutoRecommendAt = defaults.object(forKey: Keys.lastAutoRecommendAt) as? Date
        fetchDay = defaults.object(forKey: Keys.fetchDay) as? Int ?? 1
        fetchTime = Self.readDate(defaults, key: Keys.fetchTime) ?? Self.defaultTime(calendar, hour: 1)
        recommendTime = Self.readDate(defaults, key: Keys.recommendTime) ?? Self.defaultTime(calendar, hour: 8)
    }

    private func save(_ value: Bool, key: String) {
        defaults.set(value, forKey: key)
    }

    private func save(_ value: Int, key: String) {
        defaults.set(min(max(value, 1), 28), forKey: key)
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

    private static func readDate(_ defaults: UserDefaults, key: String) -> Date? {
        defaults.object(forKey: key) as? Date
    }

    private static func defaultTime(_ calendar: Calendar, hour: Int) -> Date {
        calendar.date(from: DateComponents(hour: hour, minute: 0)) ?? Date()
    }

    private enum Keys {
        static let automationEnabled = "literature.automation.enabled"
        static let autoFetchEnabled = "literature.automation.fetch.monthly.enabled"
        static let autoRecommendEnabled = "literature.automation.recommend.daily.enabled"
        static let lastAutoFetchAt = "literature.automation.fetch.monthly.lastRun"
        static let lastAutoRecommendAt = "literature.automation.recommend.daily.lastRun"
        static let fetchDay = "literature.automation.fetch.monthly.day"
        static let fetchTime = "literature.automation.fetch.monthly.time"
        static let recommendTime = "literature.automation.recommend.daily.time"
    }
}
