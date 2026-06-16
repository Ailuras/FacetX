import Foundation

/// Lightweight in-app localization, ported from VellumX.
///
/// Strings are authored as `(English, 中文)` pairs and selected by `language`,
/// which is mirrored from `AppSettings.language` (default English) on launch and
/// whenever the user switches it. Lookups go through `L10n.t(_:)`.
///
/// Reactivity: `language` is a plain global, so SwiftUI does not track reads of
/// it directly. Live refresh relies on the calling view holding the
/// `@EnvironmentObject AppSettings` — switching the language mutates a
/// `@Published` property, which re-renders the view, and `L10n.t(_:)` then
/// returns the new string. Views that do not observe `AppSettings` will not
/// refresh until they are rebuilt for another reason.
@MainActor
enum L10n {
    /// Current UI language: "en" or "zh". Mirrored from `AppSettings.language`.
    static var language: String = "en"

    static func t(_ key: Key) -> String {
        let pair = key.pair
        return language == "zh" ? pair.zh : pair.en
    }

    enum Key {
        // Settings tabs
        case tabGeneral, tabDefaults, tabSources, tabIntegrations, tabShortcuts
        // General page
        case generalTitle, generalSubtitle
        case interface, showInMenuBar, language
        case storage, applicationSupport

        var pair: (en: String, zh: String) {
            switch self {
            case .tabGeneral:         return ("General", "通用")
            case .tabDefaults:        return ("Defaults", "默认值")
            case .tabSources:         return ("Sources", "数据源")
            case .tabIntegrations:    return ("Integrations", "集成")
            case .tabShortcuts:       return ("Shortcuts", "快捷键")

            case .generalTitle:       return ("General", "通用")
            case .generalSubtitle:    return ("Interface and local state", "界面与本地状态")
            case .interface:          return ("Interface", "界面")
            case .showInMenuBar:      return ("Show in Menu Bar", "在菜单栏显示")
            case .language:           return ("Language", "语言")
            case .storage:            return ("Storage", "存储")
            case .applicationSupport: return ("Application Support", "Application Support")
            }
        }
    }
}
