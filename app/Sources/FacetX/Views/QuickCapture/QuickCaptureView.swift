import SwiftUI

/// Menu-bar quick-capture: jot one reminder into a project in ~3 seconds without
/// opening the main window. The project decides the target list.
struct QuickCaptureView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    let onDismiss: () -> Void
    let onOpenMain: () -> Void

    @State private var text = ""
    @State private var projectID: Project.ID?
    @State private var captureKind: CaptureKind = .task
    @State private var datePreset: CaptureDatePreset = .none
    @State private var justAdded = false
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    init(onDismiss: @escaping () -> Void = {}, onOpenMain: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
        self.onOpenMain = onOpenMain
    }

    private var project: Project? {
        store.activeProjects.first { $0.id == projectID } ?? store.activeProjects.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if store.activeProjects.isEmpty {
                emptyProjectsView
            } else {
                captureForm
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .onAppear {
            projectID = project?.id
            fieldFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: MenuBarController.templateImage())
                .resizable()
                .frame(width: 15, height: 15)
                .opacity(0.72)
            Text("Quick Capture")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var emptyProjectsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No projects yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
            footer
        }
    }

    private var captureForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { project?.id ?? store.activeProjects.first?.id },
                    set: { projectID = $0 }
                )) {
                    ForEach(store.activeProjects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .labelsHidden()
                .help("Select project")
                .frame(width: 128, alignment: .leading)

                Picker("", selection: $captureKind) {
                    ForEach(CaptureKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }

            Picker("", selection: $datePreset) {
                ForEach(CaptureDatePreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            HStack(spacing: 8) {
                Image(systemName: captureKind.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                TextField(captureKind.placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit(add)

                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(canAdd ? Color.accentColor : .secondary)
                .disabled(!canAdd)
                .help("Add")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            statusLine
            footer
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        } else if justAdded {
            Label("Added", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Text(targetSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var footer: some View {
        HStack {
            Button(action: onOpenMain) {
                Label("Open FacetX", systemImage: "arrow.up.right.square")
                    .foregroundStyle(.primary.opacity(0.82))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .foregroundStyle(.primary.opacity(0.66))
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
    }

    private var targetReminderList: String {
        settings.reminderSaveTarget(projectListName: project?.reminderListName)
    }

    private var targetCalendar: String {
        settings.calendarSaveTarget(projectCalendarName: project?.calendarName)
    }

    private var targetSummary: String {
        switch captureKind {
        case .task:
            return targetReminderList.isEmpty ? "No reminder list selected" : "Task -> \(targetReminderList)"
        case .schedule:
            return targetCalendar.isEmpty ? "No calendar selected" : "Schedule -> \(targetCalendar)"
        }
    }

    private var canAdd: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        guard let project else { return }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard targetIsReady else {
            error = captureKind == .task ? "Choose a reminder list first." : "Choose a calendar first."
            return
        }
        error = nil
        Task {
            let created = await createItem(project: project, content: content)
            handleCreateResult(created)
        }
    }

    private var targetIsReady: Bool {
        switch captureKind {
        case .task:
            return !targetReminderList.isEmpty
        case .schedule:
            return !targetCalendar.isEmpty
        }
    }

    private func createItem(project: Project, content: String) async -> String? {
        switch captureKind {
        case .task:
            return await ek.createReminder(
                project: project.prefix,
                content: content,
                listName: targetReminderList,
                dueDate: taskDueDate,
                dueIncludesTime: false,
                enabledLists: settings.effectiveReminderListNames
            )
        case .schedule:
            return await ek.createEvent(
                project: project.prefix,
                content: content,
                calendarName: targetCalendar,
                startDate: eventStartDate,
                durationMinutes: settings.defaultEventDurationMinutes,
                enabledCalendars: settings.effectiveCalendarNames
            )
        }
    }

    private var taskDueDate: Date? {
        guard let baseDate = datePreset.baseDate else { return nil }
        return FacetDateDefaults.dayDefault(reference: baseDate)
    }

    private var eventStartDate: Date {
        if let baseDate = datePreset.baseDate {
            return FacetDateDefaults.nextWholeHour(on: baseDate)
        }
        return FacetDateDefaults.nextWholeHour()
    }

    private func handleCreateResult(_ createdId: String?) {
        if createdId != nil {
            text = ""
            justAdded = true
            fieldFocused = true
            Task {
                try? await Task.sleep(for: .seconds(1.3))
                justAdded = false
            }
        } else {
            error = captureKind == .task ? "Could not save to \(targetReminderList)." : "Could not save to \(targetCalendar)."
        }
    }
}

private enum CaptureKind: String, CaseIterable, Identifiable {
    case task = "Task"
    case schedule = "Schedule"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .task: return "checklist"
        case .schedule: return "calendar"
        }
    }

    var placeholder: String {
        switch self {
        case .task: return "What needs doing?"
        case .schedule: return "What is scheduled?"
        }
    }
}

private enum CaptureDatePreset: String, CaseIterable, Identifiable {
    case none = "No Date"
    case today = "Today"
    case tomorrow = "Tomorrow"
    case nextSevenDays = "7 Days"

    var id: String { rawValue }

    var baseDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .none:
            return nil
        case .today:
            return Date()
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: Date())
        case .nextSevenDays:
            return calendar.date(byAdding: .day, value: 7, to: Date())
        }
    }
}
