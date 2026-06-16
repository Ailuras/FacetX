import SwiftUI

struct ShortcutsSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var keyboard: KeyboardActionRouter

    var body: some View {
        SettingsPage(title: L10n.pick("Shortcuts", "快捷键"),
                     subtitle: L10n.pick("Keyboard shortcuts for common actions", "常用操作的键盘快捷键"),
                     systemImage: "keyboard",
                     warning: nil) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsCard(title: L10n.pick("Global Shortcut", "全局快捷键"), systemImage: "globe",
                             subtitle: L10n.pick("Works system-wide, even when FacetX is in the background.",
                                                 "全局生效，即使 FacetX 在后台也可触发。")) {
                    HStack {
                        Text(L10n.pick("Quick Capture (⌃⌥Space)", "快速捕获 (⌃⌥Space)"))
                            .font(SettingsUI.rowFont)
                        Spacer()
                        Toggle("", isOn: .init(
                            get: { settings.globalShortcutEnabled },
                            set: { newValue in
                                settings.globalShortcutEnabled = newValue
                                keyboard.setGlobalShortcutEnabled(newValue)
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }
                    .padding(.vertical, 3)
                }

                shortcutGroup(title: L10n.pick("Navigation", "导航"),
                              systemImage: "arrow.left.arrow.right",
                              rows: [
                                (L10n.pick("Today", "今天"), "⌘T"),
                                (L10n.pick("All", "全部"), "⌘1"),
                                (L10n.pick("Week", "周"), "⌘2"),
                                (L10n.pick("Month", "月"), "⌘3"),
                                (L10n.pick("Git", "Git"), "⌘4"),
                                (L10n.pick("Previous Project", "上一个项目"), "⌘↑"),
                                (L10n.pick("Next Project", "下一个项目"), "⌘↓")
                              ])

                shortcutGroup(title: L10n.pick("Items", "条目"),
                              systemImage: "checklist",
                              rows: [
                                (L10n.pick("New Item", "新建条目"), "⌘N"),
                                (L10n.pick("Toggle Complete", "切换完成"), "Space"),
                                (L10n.pick("Open Detail", "打开详情"), "↵"),
                                (L10n.pick("Delete", "删除"), "⌘⌫"),
                                (L10n.pick("Show / Hide Completed", "显示 / 隐藏已完成"), "⌘⇧H")
                              ])

                shortcutGroup(title: L10n.pick("View", "视图"),
                              systemImage: "eye",
                              rows: [
                                (L10n.pick("Search", "搜索"), "⌘F"),
                                (L10n.pick("Refresh", "刷新"), "⌘R"),
                                (L10n.pick("Close Detail Pane", "关闭详情面板"), "Esc")
                              ])
            }
        }
    }

    private func shortcutGroup(title: String,
                               systemImage: String,
                               rows: [(label: String, keys: String)]) -> some View {
        SettingsCard(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack {
                        Text(rows[i].label)
                            .font(SettingsUI.rowFont)
                        Spacer()
                        KeyBadge(text: rows[i].keys)
                    }
                    if i < rows.count - 1 {
                        SettingsDivider()
                    }
                }
            }
        }
    }
}

struct KeyBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(badges), id: \.self) { badge in
                Text(badge)
                    .font(.system(size: 11, weight: .medium))
                    .frame(minWidth: 20, minHeight: 20)
                    .padding(.horizontal, 4)
                    .background(FacetTheme.quietPanel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }

    /// Splits "⌘⇧H" into ["⌘", "⇧", "H"], "⌃⌥Space" into ["⌃", "⌥", "Space"], etc.
    private var badges: [String] {
        var result: [String] = []
        var remainder = text
        let modifiers = ["⌃", "⌥", "⇧", "⌘"]
        for mod in modifiers {
            if remainder.hasPrefix(mod) {
                result.append(mod)
                remainder.removeFirst(mod.count)
            }
        }
        if !remainder.isEmpty {
            result.append(remainder)
        }
        return result
    }
}
