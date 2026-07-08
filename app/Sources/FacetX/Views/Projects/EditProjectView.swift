import SwiftUI

struct EditProjectView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var toast: ToastController

    let project: Project
    let onClose: () -> Void

    @State private var name = ""
    @State private var prefix = ""
    @State private var tagline = ""
    @State private var reminderListName = ""
    @State private var calendarName = ""
    @State private var noteCalendarName = ""
    @State private var weekGoalCalendarName = ""
    @State private var literatureListName = ""
    @State private var githubRepo = ""
    @State private var colorName = ProjectAppearance.defaultColorName
    @State private var iconName = ProjectAppearance.defaultIconName
    @State private var reminderLists: [String] = []
    @State private var calendars: [String] = []
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            ProjectEditorHeader(title: L10n.pick("Edit Project", "编辑项目"),
                                subtitle: project.archived ? L10n.pick("Archived project", "已归档项目")
                                                           : L10n.pick("Project settings", "项目设置"),
                                initial: projectInitial,
                                tint: ProjectAppearance.color(for: colorName),
                                systemImage: ProjectAppearance.iconName(for: iconName))
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
                if project.archived {
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
                    .disabled(trimmedName.isEmpty || !hasDistinctItemSaveLocations)
            }
            .controlSize(.small)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(FacetTheme.canvas)
        .frame(width: 500, height: 650)
        .onAppear(perform: loadFields)
        .alert(L10n.pick("Delete project?", "删除项目？"), isPresented: $confirmDelete) {
            Button(L10n.pick("Cancel", "取消"), role: .cancel) { }
            Button(L10n.pick("Delete", "删除"), role: .destructive) {
                delete()
            }
        } message: {
            Text(L10n.pick("“\(project.name)” will be removed. Its items remain in Calendar/Reminders.",
                           "将移除“\(project.name)”。其条目仍保留在日历/提醒事项中。"))
        }
    }

    private var identityCard: some View {
        ProjectEditorCard(title: L10n.pick("Identity", "标识"), systemImage: "folder") {
            ProjectEditorTextField(title: L10n.pick("Name", "名称"), text: $name, placeholder: L10n.pick("Project name", "项目名称"))
            ProjectEditorTextField(title: L10n.pick("Prefix", "前缀"), text: $prefix, placeholder: L10n.pick("Prefix", "前缀"))
            ProjectEditorHelp(L10n.pick("Items whose title starts with “\(effectivePrefix):” belong to this project.",
                                        "标题以“\(effectivePrefix):”开头的条目属于该项目。"))
            if prefixWillChange {
                ProjectEditorWarning(L10n.pick("Existing Calendar and Reminder items will keep the old “\(project.prefix):” prefix and will no longer appear here unless renamed.",
                                               "已有的日历和提醒事项条目会保留旧的“\(project.prefix):”前缀，除非重命名，否则将不再显示在此处。"))
            }
            ProjectEditorTextField(title: L10n.pick("Tagline", "标语"), text: $tagline, placeholder: L10n.pick("Short description", "简短描述"))
        }
    }

    private var appearanceCard: some View {
        ProjectEditorCard(title: L10n.pick("Appearance", "外观"), systemImage: "paintpalette") {
            ProjectEditorAppearancePicker(colorName: $colorName, iconName: $iconName, initial: projectInitial)
        }
    }

    private var saveLocationsCard: some View {
        ProjectEditorCard(title: L10n.pick("Save Locations", "保存位置"), systemImage: "tray.and.arrow.down") {
            ProjectEditorPicker(title: L10n.pick("Reminders", "提醒事项"), selection: $reminderListName, options: reminderLists.filter { $0 != literatureListName })
            ProjectEditorPicker(title: L10n.pick("Calendar", "日历"), selection: $calendarName, options: calendars.filter { $0 != noteCalendarName })
            ProjectEditorPicker(title: L10n.pick("Note Calendar", "笔记日历"), selection: $noteCalendarName, options: calendars.filter { $0 != calendarName })
            ProjectEditorPicker(title: L10n.pick("Goal Calendar", "目标日历"), selection: $weekGoalCalendarName, options: calendars)
            ProjectEditorPicker(title: L10n.pick("Paper List", "文献列表"), selection: $literatureListName, options: reminderLists.filter { $0 != reminderListName })
            if !hasDistinctItemSaveLocations {
                ProjectEditorWarning(L10n.pick("Tasks, events, papers and notes need separate default save targets.",
                                               "任务、事件、文献和笔记需要使用互不相同的默认保存位置。"))
            }
        }
    }

    private var integrationsCard: some View {
        ProjectEditorCard(title: L10n.pick("Integrations", "集成"), systemImage: "curlybraces") {
            ProjectEditorGitHubRepoPicker(selection: $githubRepo)
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
        effectivePrefix != project.prefix
    }

    private var projectInitial: String {
        trimmedName.first.map { String($0).uppercased() } ?? "F"
    }

    private func loadFields() {
        reminderLists = ek.reminderListNames(enabled: settings.effectiveReminderListNames)
        calendars = ek.calendarNames(enabled: settings.effectiveCalendarNames)
        name = project.name
        prefix = project.prefix
        tagline = project.tagline
        githubRepo = project.githubRepo ?? ""
        colorName = project.colorName ?? ProjectAppearance.defaultColorName
        iconName = project.iconName ?? ProjectAppearance.defaultIconName
        reminderListName = firstAvailable(project.reminderListName,
                                          settings.defaultReminderListName,
                                          in: reminderLists)
        calendarName = firstAvailable(project.calendarName,
                                      settings.defaultCalendarName,
                                      in: calendars)
        noteCalendarName = firstAvailable(project.noteCalendarName,
                                          settings.defaultNoteCalendarName,
                                          in: calendars)
        weekGoalCalendarName = firstAvailable(project.weekGoalCalendarName,
                                             settings.weekGoalCalendarName,
                                             in: calendars)
        literatureListName = firstAvailable(project.literatureListName,
                                               settings.defaultLiteratureListName,
                                               in: reminderLists)
    }

    private func save() {
        var updated = project
        updated.name = trimmedName
        updated.prefix = trimmedPrefix.isEmpty ? trimmedName : trimmedPrefix
        updated.tagline = tagline.trimmingCharacters(in: .whitespaces)
        updated.reminderListName = reminderListName.isEmpty ? nil : reminderListName
        updated.calendarName = calendarName.isEmpty ? nil : calendarName
        updated.noteCalendarName = noteCalendarName.isEmpty ? nil : noteCalendarName
        updated.weekGoalCalendarName = weekGoalCalendarName.isEmpty ? nil : weekGoalCalendarName
        updated.literatureListName = literatureListName.isEmpty ? nil : literatureListName
        updated.colorName = colorName
        updated.iconName = iconName
        let repo = githubRepo.trimmingCharacters(in: .whitespaces)
        updated.githubRepo = repo.isEmpty ? nil : repo
        store.update(updated)
        onClose()
    }

    private func firstAvailable(_ preferred: String?, _ fallback: String, in options: [String]) -> String {
        if let preferred, options.contains(preferred) { return preferred }
        if options.contains(fallback) { return fallback }
        return options.first ?? ""
    }

    private var hasDistinctItemSaveLocations: Bool {
        !reminderListName.isEmpty
            && !calendarName.isEmpty
            && !noteCalendarName.isEmpty
            && !literatureListName.isEmpty
            && reminderListName != literatureListName
            && calendarName != noteCalendarName
    }

    private func archive() {
        store.archive(project)
        toast.show(L10n.pick("Project archived", "项目已归档"), type: .info)
        onClose()
    }

    private func unarchive() {
        var updated = project
        updated.archived = false
        store.update(updated)
        toast.show(L10n.pick("Project unarchived", "项目已取消归档"), type: .success)
        onClose()
    }

    private func delete() {
        store.delete(project)
        toast.show(L10n.pick("Project deleted", "项目已删除"), type: .success)
        onClose()
    }
}
