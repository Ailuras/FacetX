import SwiftUI

struct EditWorkView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: WorkStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var toast: ToastController

    let work: Work
    let onClose: () -> Void

    @State private var name = ""
    @State private var prefix = ""
    @State private var tagline = ""
    @State private var reminderListName = ""
    @State private var calendarName = ""
    @State private var weekGoalCalendarName = ""
    @State private var githubRepo = ""
    @State private var githubLocalPath = ""
    @State private var colorName = WorkAppearance.defaultColorName
    @State private var iconName = WorkAppearance.defaultIconName
    @State private var reminderLists: [String] = []
    @State private var calendars: [String] = []
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            WorkEditorHeader(title: L10n.pick("Edit Work", "编辑项目"),
                                subtitle: work.archived ? L10n.pick("Archived work", "已归档项目")
                                                           : L10n.pick("Work settings", "项目设置"),
                                initial: workInitial,
                                tint: WorkAppearance.color(for: colorName),
                                systemImage: WorkAppearance.iconName(for: iconName))
            Divider().opacity(0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    identityCard
                    appearanceCard
                    saveLocationsCard
                    integrationsCard
                }
                .padding(18)
            }

            Divider().opacity(0.7)
            HStack {
                if work.archived {
                    Button(L10n.pick("Unarchive", "取消归档")) { unarchive() }
                } else {
                    Button(L10n.pick("Archive", "归档")) { archive() }
                }
                Button(L10n.pick("Delete", "删除"), role: .destructive) { confirmDelete = true }
                Spacer()
                Button(L10n.pick("Cancel", "取消"), action: onClose)
                Button(L10n.pick("Save", "保存")) { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || !hasSaveLocations)
            }
            .controlSize(.small)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(FacetTheme.canvas)
        .frame(width: 500, height: 650)
        .onAppear(perform: loadFields)
        .alert(L10n.pick("Delete work?", "删除项目？"), isPresented: $confirmDelete) {
            Button(L10n.pick("Cancel", "取消"), role: .cancel) { }
            Button(L10n.pick("Delete", "删除"), role: .destructive) {
                delete()
            }
        } message: {
            Text(L10n.pick("“\(work.name)” will be removed. Its items remain in Calendar/Reminders.",
                           "将移除“\(work.name)”。其条目仍保留在日历/提醒事项中。"))
        }
    }

    private var identityCard: some View {
        WorkEditorCard(title: L10n.pick("Identity", "标识"), systemImage: "folder") {
            WorkEditorTextField(title: L10n.pick("Name", "名称"), text: $name, placeholder: L10n.pick("Work name", "项目名称"))
            WorkEditorTextField(title: L10n.pick("Prefix", "前缀"), text: $prefix, placeholder: L10n.pick("Prefix", "前缀"))
            WorkEditorHelp(L10n.pick("Items whose title starts with “\(effectivePrefix):” belong to this work.",
                                        "标题以“\(effectivePrefix):”开头的条目属于该项目。"))
            if prefixWillChange {
                WorkEditorWarning(L10n.pick("Existing Calendar and Reminder items will keep the old “\(work.prefix):” prefix and will no longer appear here unless renamed.",
                                               "已有的日历和提醒事项条目会保留旧的“\(work.prefix):”前缀，除非重命名，否则将不再显示在此处。"))
            }
            WorkEditorTextField(title: L10n.pick("Tagline", "标语"), text: $tagline, placeholder: L10n.pick("Short description", "简短描述"))
        }
    }

    private var appearanceCard: some View {
        WorkEditorCard(title: L10n.pick("Appearance", "外观"), systemImage: "paintpalette") {
            WorkEditorAppearancePicker(colorName: $colorName, iconName: $iconName, initial: workInitial)
        }
    }

    private var saveLocationsCard: some View {
        WorkEditorCard(title: L10n.pick("Save Locations", "保存位置"), systemImage: "tray.and.arrow.down") {
            WorkEditorPicker(title: L10n.pick("Reminders", "提醒事项"), selection: $reminderListName, options: reminderLists)
            WorkEditorPicker(title: L10n.pick("Calendar", "日历"), selection: $calendarName, options: calendars)
            WorkEditorPicker(title: L10n.pick("Goal Calendar", "目标日历"), selection: $weekGoalCalendarName, options: calendars)
        }
    }

    private var integrationsCard: some View {
        WorkEditorCard(title: L10n.pick("Integrations", "集成"), systemImage: "curlybraces") {
            WorkEditorGitHubRepoPicker(selection: $githubRepo, localPath: $githubLocalPath)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedPrefix: String {
        prefix.trimmingCharacters(in: .whitespaces)
    }

    private var effectivePrefix: String {
        trimmedPrefix.isEmpty ? (trimmedName.isEmpty ? "..." : trimmedName) : trimmedPrefix
    }

    private var prefixWillChange: Bool {
        effectivePrefix != work.prefix
    }

    private var workInitial: String {
        trimmedName.first.map { String($0).uppercased() } ?? "F"
    }

    private func loadFields() {
        reminderLists = ek.reminderListNames(enabled: settings.effectiveReminderListNames)
        calendars = ek.calendarNames(enabled: settings.effectiveCalendarNames)
        name = work.name
        prefix = work.prefix
        tagline = work.tagline
        githubRepo = work.githubRepo ?? ""
        githubLocalPath = work.githubLocalPath ?? ""
        colorName = work.colorName ?? WorkAppearance.defaultColorName
        iconName = work.iconName ?? WorkAppearance.defaultIconName
        reminderListName = firstAvailable(work.reminderListName,
                                          settings.defaultReminderListName,
                                          in: reminderLists)
        calendarName = firstAvailable(work.calendarName,
                                      settings.defaultCalendarName,
                                      in: calendars)
        weekGoalCalendarName = firstAvailable(work.weekGoalCalendarName,
                                             settings.weekGoalCalendarName,
                                             in: calendars)
    }

    private func save() {
        var updated = work
        updated.name = trimmedName
        updated.prefix = trimmedPrefix.isEmpty ? trimmedName : trimmedPrefix
        updated.tagline = tagline.trimmingCharacters(in: .whitespaces)
        updated.reminderListName = reminderListName.isEmpty ? nil : reminderListName
        updated.calendarName = calendarName.isEmpty ? nil : calendarName
        updated.weekGoalCalendarName = weekGoalCalendarName.isEmpty ? nil : weekGoalCalendarName
        updated.colorName = colorName
        updated.iconName = iconName
        let repo = githubRepo.trimmingCharacters(in: .whitespaces)
        updated.githubRepo = repo.isEmpty ? nil : repo
        let repoPath = githubLocalPath.trimmingCharacters(in: .whitespaces)
        updated.githubLocalPath = repoPath.isEmpty ? nil : repoPath
        store.update(updated)
        onClose()
    }

    private func firstAvailable(_ preferred: String?, _ fallback: String, in options: [String]) -> String {
        if let preferred, options.contains(preferred) { return preferred }
        if options.contains(fallback) { return fallback }
        return options.first ?? ""
    }

    private var hasSaveLocations: Bool {
        !reminderListName.isEmpty
            && !calendarName.isEmpty
    }

    private func archive() {
        store.archive(work)
        toast.show(L10n.pick("Work archived", "项目已归档"), type: .info)
        onClose()
    }

    private func unarchive() {
        var updated = work
        updated.archived = false
        store.update(updated)
        toast.show(L10n.pick("Work unarchived", "项目已取消归档"), type: .success)
        onClose()
    }

    private func delete() {
        store.delete(work)
        toast.show(L10n.pick("Work deleted", "项目已删除"), type: .success)
        onClose()
    }
}
