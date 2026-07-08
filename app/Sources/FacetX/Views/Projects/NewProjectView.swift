import SwiftUI

struct NewProjectView: View {
    let draft: ProjectDraft
    let onCreate: (String, String?, String, String?, String?, String?, String?, String?, String?, String, String, String?) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var prefix: String
    @State private var tagline: String
    @State private var reminderListName: String
    @State private var calendarName: String
    @State private var noteCalendarName: String
    @State private var weekGoalCalendarName: String
    @State private var literatureListName: String
    @State private var dataDirectory: String
    @State private var githubRepo: String
    @State private var colorName: String
    @State private var iconName: String

    init(draft: ProjectDraft,
         onCreate: @escaping (String, String?, String, String?, String?, String?, String?, String?, String?, String, String, String?) -> Void,
         onCancel: @escaping () -> Void) {
        self.draft = draft
        self.onCreate = onCreate
        self.onCancel = onCancel
        _name = State(initialValue: draft.name)
        _prefix = State(initialValue: draft.prefix)
        _tagline = State(initialValue: draft.tagline)
        _reminderListName = State(initialValue: draft.reminderListName)
        _calendarName = State(initialValue: draft.calendarName)
        _noteCalendarName = State(initialValue: draft.noteCalendarName)
        _weekGoalCalendarName = State(initialValue: draft.weekGoalCalendarName)
        _literatureListName = State(initialValue: draft.literatureListName)
        _dataDirectory = State(initialValue: draft.dataDirectory)
        _githubRepo = State(initialValue: draft.githubRepo)
        _colorName = State(initialValue: draft.colorName)
        _iconName = State(initialValue: draft.iconName)
    }

    var body: some View {
        VStack(spacing: 0) {
            ProjectEditorHeader(title: L10n.pick("New Project", "新建项目"),
                                subtitle: L10n.pick("Create a facet over Calendar and Reminders",
                                                    "为日历与提醒事项创建一个分面"),
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
                Spacer()
                Button(L10n.pick("Cancel", "取消"), action: onCancel)
                    .controlSize(.small)
                Button(L10n.pick("Create", "创建")) { create() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || !hasDistinctItemSaveLocations)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(FacetTheme.canvas)
        .frame(width: 500, height: 650)
    }

    private var identityCard: some View {
        ProjectEditorCard(title: L10n.pick("Identity", "标识"), systemImage: "folder") {
            ProjectEditorTextField(title: L10n.pick("Name", "名称"), text: $name, placeholder: L10n.pick("Project name", "项目名称"))
            ProjectEditorTextField(title: L10n.pick("Prefix", "前缀"), text: $prefix, placeholder: L10n.pick("Prefix", "前缀"))
            ProjectEditorHelp(L10n.pick("Items whose title starts with “\(effectivePrefix):” belong to this project.",
                                        "标题以“\(effectivePrefix):”开头的条目属于该项目。"))
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
            ProjectEditorPicker(title: L10n.pick("Reminders", "提醒事项"), selection: $reminderListName, options: draft.reminderLists.filter { $0 != literatureListName })
            ProjectEditorPicker(title: L10n.pick("Calendar", "日历"), selection: $calendarName, options: draft.calendars.filter { $0 != noteCalendarName })
            ProjectEditorPicker(title: L10n.pick("Note Calendar", "笔记日历"), selection: $noteCalendarName, options: draft.calendars.filter { $0 != calendarName })
            ProjectEditorPicker(title: L10n.pick("Goal Calendar", "目标日历"), selection: $weekGoalCalendarName, options: draft.calendars)
            ProjectEditorPicker(title: L10n.pick("Paper List", "文献列表"), selection: $literatureListName, options: draft.reminderLists.filter { $0 != reminderListName })
            if !hasDistinctItemSaveLocations {
                ProjectEditorWarning(L10n.pick("Tasks, events, papers and notes need separate default save targets.",
                                               "任务、事件、文献和笔记需要使用互不相同的默认保存位置。"))
            }
            Divider().opacity(0.42)
            ProjectEditorDirectoryPicker(title: L10n.pick("Data Folder", "数据目录"), path: $dataDirectory)
            ProjectEditorHelp(L10n.pick("Where notes and other local files for this project are stored.",
                                        "该项目的笔记及其他本地文件的存放位置。"))
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

    private var projectInitial: String {
        trimmedName.first.map { String($0).uppercased() } ?? "F"
    }

    private var hasDistinctItemSaveLocations: Bool {
        !reminderListName.isEmpty
            && !calendarName.isEmpty
            && !noteCalendarName.isEmpty
            && !literatureListName.isEmpty
            && reminderListName != literatureListName
            && calendarName != noteCalendarName
    }

    private func create() {
        let prefix = trimmedPrefix.isEmpty ? nil : trimmedPrefix
        let repo = githubRepo.trimmingCharacters(in: .whitespaces)
        onCreate(trimmedName, prefix, tagline.trimmingCharacters(in: .whitespaces),
                 reminderListName.isEmpty ? nil : reminderListName,
                 calendarName.isEmpty ? nil : calendarName,
                 noteCalendarName.isEmpty ? nil : noteCalendarName,
                 weekGoalCalendarName.isEmpty ? nil : weekGoalCalendarName,
                 literatureListName.isEmpty ? nil : literatureListName,
                 dataDirectory.isEmpty ? nil : dataDirectory,
                 colorName,
                 iconName,
                 repo.isEmpty ? nil : repo)
    }
}
