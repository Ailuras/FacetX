import SwiftUI

struct ShortcutsSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var keyboard: KeyboardActionRouter

    var body: some View {
        SettingsPage(title: "Shortcuts",
                     subtitle: "Keyboard shortcuts for common actions",
                     systemImage: "keyboard",
                     warning: nil) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsCard(title: "Global Shortcut", systemImage: "globe") {
                    HStack {
                        Text("Quick Capture (⌃⌥Space)")
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

                shortcutGroup(title: "Navigation",
                              systemImage: "arrow.left.arrow.right",
                              rows: [
                                ("Today", "⌘T"),
                                ("All", "⌘1"),
                                ("Week", "⌘2"),
                                ("Month", "⌘3"),
                                ("Git", "⌘4"),
                                ("Previous Project", "⌘↑"),
                                ("Next Project", "⌘↓")
                              ])

                shortcutGroup(title: "Items",
                              systemImage: "checklist",
                              rows: [
                                ("New Item", "⌘N"),
                                ("Toggle Complete", "Space"),
                                ("Open Detail", "↵"),
                                ("Delete", "⌘⌫"),
                                ("Show / Hide Completed", "⌘⇧H")
                              ])

                shortcutGroup(title: "View",
                              systemImage: "eye",
                              rows: [
                                ("Search", "⌘F"),
                                ("Refresh", "⌘R"),
                                ("Close Detail Pane", "Esc")
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
