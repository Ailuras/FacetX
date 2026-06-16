import Foundation

/// Lightweight in-app localization, ported from VellumX.
///
/// Strings are authored as `(English, 中文)` pairs and selected by `language`,
/// which is loaded from `AppSettings.language` (default English) at launch.
/// Lookups go through `L10n.t(_:)`.
///
/// Language is applied at launch only: switching it in Settings persists the
/// choice and prompts a restart, so every view renders consistently in the new
/// language instead of relying on per-view live refresh.
@MainActor
enum L10n {
    /// Current UI language: "en" or "zh". Loaded from `AppSettings.language`.
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
        // Restart prompt
        case restartTitle, restartMessage, restartNow, restartLater
        // Common
        case cancel, delete, archive
        // Sidebar / ContentView
        case sidebarProjects, sidebarTags, editProject
        case projectArchived, projectDeleted
        case newProject, selectProject, selectProjectHint, projectNotFound
        case accessRequired, openSettings
        case deleteProjectTitle, deleteProjectMessage
        case allTags, showAllTags, colorMenu
        case tagItemsUnit, tagClickInclude, tagClickExclude, tagClickClear
        // ProjectDetailView
        case modeAll, modeWeek, modeMonth, modeGit
        case switchViewMode, refreshed, refresh
        case hideTodayPanel, showTodayTimeline
        case deleteItemTitle, paneReminder, paneSchedule
        case searchCommits, searchItems
        // Week / Month / Today views
        case today, noItems, noItemsSearch, noItemsDay
        case tapDayHint, closeTodayPanel
        case prevWeek, nextWeek, currentWeek
        case prevMonth, nextMonth, currentMonth, monthUnit
        case addItemForDay
        case resultsUnit, hiddenUnit, shownUnit
        // Week goal
        case goalPlaceholderTitle, goalPlaceholderBody
        case save, edit, editWeeklyGoal, thisWeeksFocus
        case setWeekFocus, setWeekFocusHint, setWeekGoalHelp
        case goalDeleteError, goalSaveError

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

            case .restartTitle:       return ("Restart required", "需要重启")
            case .restartMessage:     return ("Changing the language takes effect after FacetX restarts.",
                                              "更改语言需要重启 FacetX 后生效。")
            case .restartNow:         return ("Restart Now", "立即重启")
            case .restartLater:       return ("Later", "稍后")

            case .cancel:             return ("Cancel", "取消")
            case .delete:             return ("Delete", "删除")
            case .archive:            return ("Archive", "归档")

            case .sidebarProjects:    return ("Projects", "项目")
            case .sidebarTags:        return ("Tags", "标签")
            case .editProject:        return ("Edit Project", "编辑项目")
            case .projectArchived:    return ("Project archived", "项目已归档")
            case .projectDeleted:     return ("Project deleted", "项目已删除")
            case .newProject:         return ("New Project", "新建项目")
            case .selectProject:      return ("Select a project", "选择一个项目")
            case .selectProjectHint:  return ("Pick a project from the sidebar to get started.",
                                              "从左侧边栏选择一个项目开始。")
            case .projectNotFound:    return ("Project not found", "未找到项目")
            case .accessRequired:     return ("Calendar and Reminders access is required to display items.",
                                              "需要日历与提醒事项权限才能显示项目内容。")
            case .openSettings:       return ("Open Settings", "打开系统设置")
            case .deleteProjectTitle: return ("Delete project?", "删除项目？")
            case .deleteProjectMessage: return ("will be removed. Its items remain in Calendar/Reminders.",
                                                "将被移除。其条目仍保留在日历 / 提醒事项中。")
            case .allTags:            return ("All", "全部")
            case .showAllTags:        return ("Show all tags", "显示全部标签")
            case .colorMenu:          return ("Color", "颜色")
            case .tagItemsUnit:       return ("items", "项")
            case .tagClickInclude:    return ("click to include", "点击包含")
            case .tagClickExclude:    return ("click to exclude", "点击排除")
            case .tagClickClear:      return ("click to clear", "点击清除")

            case .modeAll:            return ("All", "全部")
            case .modeWeek:           return ("Week", "周")
            case .modeMonth:          return ("Month", "月")
            case .modeGit:            return ("Git", "Git")
            case .switchViewMode:     return ("Switch view mode", "切换视图模式")
            case .refreshed:          return ("Refreshed", "已刷新")
            case .refresh:            return ("Refresh", "刷新")
            case .hideTodayPanel:     return ("Hide Today panel", "隐藏 Today 面板")
            case .showTodayTimeline:  return ("Show Today timeline", "显示 Today 时间线")
            case .deleteItemTitle:    return ("Delete item?", "删除条目？")
            case .paneReminder:       return ("Reminder", "提醒事项")
            case .paneSchedule:       return ("Schedule", "日程")
            case .searchCommits:      return ("Search commits…", "搜索提交…")
            case .searchItems:        return ("Search items…", "搜索条目…")

            case .today:              return ("Today", "今天")
            case .noItems:            return ("No items", "暂无条目")
            case .noItemsSearch:      return ("No items match this search.", "没有符合搜索的条目。")
            case .noItemsDay:         return ("No items for this day", "这一天暂无条目")
            case .tapDayHint:         return ("Tap a day to view its items", "点按某天查看其条目")
            case .closeTodayPanel:    return ("Close Today panel", "关闭 Today 面板")
            case .prevWeek:           return ("Previous week", "上一周")
            case .nextWeek:           return ("Next week", "下一周")
            case .currentWeek:        return ("Go to current week", "回到本周")
            case .prevMonth:          return ("Previous month", "上个月")
            case .nextMonth:          return ("Next month", "下个月")
            case .currentMonth:       return ("Go to current month", "回到本月")
            case .monthUnit:          return ("Month", "月份")
            case .addItemForDay:      return ("Add item for this day", "为这一天添加条目")
            case .resultsUnit:        return ("results", "结果")
            case .hiddenUnit:         return ("hidden", "已隐藏")
            case .shownUnit:          return ("shown", "显示")

            case .goalPlaceholderTitle: return ("This week I'm focused on...", "本周我专注于…")
            case .goalPlaceholderBody:  return ("Details and constraints...", "细节与约束…")
            case .save:               return ("Save", "保存")
            case .edit:               return ("Edit", "编辑")
            case .editWeeklyGoal:     return ("Edit weekly goal", "编辑周目标")
            case .thisWeeksFocus:     return ("This Week's Focus", "本周重点")
            case .setWeekFocus:       return ("Set this week's focus", "设定本周重点")
            case .setWeekFocusHint:   return ("Pick one outcome to keep this project's week anchored.",
                                              "选择一个目标,让本项目的这一周保持聚焦。")
            case .setWeekGoalHelp:    return ("Set this week's project goal", "设定本周项目目标")
            case .goalDeleteError:    return ("Could not delete the schedule item. Check Calendar access.",
                                              "无法删除日程项,请检查日历访问权限。")
            case .goalSaveError:      return ("Could not save the schedule item. Check Calendar access and enabled calendars.",
                                              "无法保存日程项,请检查日历访问权限及已启用的日历。")
            }
        }
    }
}
