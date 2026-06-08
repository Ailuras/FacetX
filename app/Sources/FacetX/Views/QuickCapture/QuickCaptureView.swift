import FacetXCore
import SwiftUI

/// Menu-bar quick-capture: jot one item into a project in seconds without
/// opening the main window. Supports reminders or schedule events, a quick due
/// date, and inline tags. The project decides the target list/calendar.
struct QuickCaptureView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    private enum CaptureKind: CaseIterable {
        case reminder, event
        var label: String { self == .reminder ? "Reminder" : "Schedule" }
        var icon: String { self == .reminder ? "checkmark.circle" : "calendar" }
    }

    private enum QuickDate: CaseIterable {
        case none, today, tomorrow
        var label: String {
            switch self {
            case .none: return "No date"
            case .today: return "Today"
            case .tomorrow: return "Tomorrow"
            }
        }
        var date: Date? {
            let cal = Calendar.current
            switch self {
            case .none: return nil
            case .today: return cal.startOfDay(for: Date())
            case .tomorrow: return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))
            }
        }
    }

    @State private var text = ""
    @State private var tagsText = ""
    @State private var projectID: Project.ID?
    @State private var captureKind: CaptureKind = .reminder
    @State private var quickDate: QuickDate = .none
    @State private var justAdded = false
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    private var project: Project? {
        store.activeProjects.first { $0.id == projectID } ?? store.activeProjects.first
    }

    /// Events must land on a day, so the "no date" option is reminder-only.
    private var dateOptions: [QuickDate] {
        captureKind == .reminder ? QuickDate.allCases : [.today, .tomorrow]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header

            if store.activeProjects.isEmpty {
                emptyState
            } else {
                kindPicker
                composer
                datePicker
                addButton
                status
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { fieldFocused = true }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: MenuBarController.templateImage())
                .resizable()
                .frame(width: 15, height: 15)
                .opacity(0.70)
            Text("Quick add")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        Text("No projects yet. Open FacetX and create one.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .cardChrome()
    }

    private var kindPicker: some View {
        HStack(spacing: 3) {
            ForEach(CaptureKind.allCases, id: \.self) { kind in
                segmentPill(
                    title: kind.label,
                    systemImage: kind.icon,
                    selected: captureKind == kind
                ) {
                    captureKind = kind
                    if kind == .event, quickDate == .none { quickDate = .today }
                    fieldFocused = true
                }
            }
        }
        .padding(2)
        .cardChrome()
    }

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Picker("", selection: Binding(
                    get: { project?.id ?? store.activeProjects.first?.id },
                    set: { projectID = $0 }
                )) {
                    ForEach(store.activeProjects) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .help("Select project")
                .frame(width: 106, alignment: .leading)

                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: 1, height: 18)

                TextField(captureKind == .reminder ? "What needs doing?" : "What's scheduled?", text: $text)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit(add)
            }
            .padding(.leading, 7)
            .padding(.trailing, 9)
            .padding(.vertical, 7)

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TagChipEditor(tagsText: $tagsText, knownColors: settings)
            }
            .padding(.leading, 8)
            .padding(.trailing, 9)
            .padding(.vertical, 5)
        }
        .cardChrome()
    }

    private var datePicker: some View {
        HStack(spacing: 3) {
            ForEach(dateOptions, id: \.self) { option in
                segmentPill(
                    title: option.label,
                    systemImage: nil,
                    selected: quickDate == option
                ) {
                    quickDate = option
                    fieldFocused = true
                }
            }
        }
        .padding(2)
        .cardChrome()
    }

    private var addButton: some View {
        Button(action: add) {
            HStack(spacing: 6) {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                Text("Add to \(project?.name ?? "project")")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(canAdd ? Color.accentColor : Color.secondary.opacity(0.25))
            .foregroundStyle(canAdd ? Color.white : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
    }

    @ViewBuilder
    private var status: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
        } else if justAdded {
            Label("Added", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                let windows = NSApp.windows.filter { $0.canBecomeMain }
                if windows.isEmpty {
                    NSWorkspace.shared.open(Bundle.main.bundleURL)
                } else {
                    for w in windows { w.makeKeyAndOrderFront(nil) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(nsImage: MenuBarController.templateImage())
                        .resizable()
                        .frame(width: 14, height: 14)
                        .opacity(0.62)
                    Text("Open FacetX")
                }
                .foregroundStyle(Color.primary.opacity(0.82))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .foregroundStyle(.primary.opacity(0.68))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Building blocks

    private func segmentPill(title: String, systemImage: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private var canAdd: Bool {
        project != nil && !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func add() {
        guard let project else { return }
        let content = text.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return }

        let tags = FacetMetadata.tags(from: tagsText)
        let notes = FacetMetadata.compose(userNotes: "", metadata: FacetMetadata(userNotes: "", tags: tags))
        let day = quickDate.date
        error = nil

        Task {
            let created: String?
            switch captureKind {
            case .reminder:
                let listName = settings.reminderSaveTarget(projectListName: project.reminderListName)
                guard !listName.isEmpty else {
                    error = "Choose a reminder list for this project."
                    return
                }
                created = await ek.createReminder(
                    project: project.prefix, content: content,
                    listName: listName, dueDate: day, dueIncludesTime: false,
                    notes: notes,
                    enabledLists: settings.effectiveReminderListNames
                )
            case .event:
                let calName = settings.calendarSaveTarget(projectCalendarName: project.calendarName)
                guard !calName.isEmpty else {
                    error = "Choose a calendar for this project."
                    return
                }
                let start = day ?? Calendar.current.startOfDay(for: Date())
                created = await ek.createEvent(
                    project: project.prefix, content: content,
                    calendarName: calName, startDate: start,
                    durationMinutes: settings.defaultEventDurationMinutes,
                    notes: notes, isAllDay: true,
                    enabledCalendars: settings.effectiveCalendarNames
                )
            }

            if created != nil {
                text = ""
                tagsText = ""
                justAdded = true
                fieldFocused = true
                try? await Task.sleep(for: .seconds(1.5))
                justAdded = false
            } else {
                error = "Could not save the item."
            }
        }
    }
}

private extension View {
    /// The quiet rounded panel used by every quick-capture card.
    func cardChrome() -> some View {
        background(FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
    }
}
