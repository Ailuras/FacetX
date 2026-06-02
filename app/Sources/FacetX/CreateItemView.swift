import FacetXCore
import SwiftUI

/// Sheet to create a new item in a project. The app composes the
/// `ProjectName:` prefix automatically, so the user only types the content —
/// the project-association contract is enforced by construction, not by the
/// user remembering to prefix.
struct CreateItemView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings

    let project: Project
    let initialDate: Date?
    /// Called after a successful create so the detail view can refresh.
    let onCreated: () -> Void

    enum Kind: String, CaseIterable, Identifiable {
        case reminder = "Reminder", event = "Event"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .reminder
    @State private var content = ""
    @State private var notes = ""
    @State private var priority: Int = 0
    @State private var useDate: Bool
    @State private var date: Date
    @State private var isAllDay = false
    @State private var durationMinutes: Int
    @State private var saving = false
    @State private var error: String?

    init(project: Project, initialDate: Date? = nil, onCreated: @escaping () -> Void) {
        self.project = project
        self.initialDate = initialDate
        self.onCreated = onCreated
        _date = State(initialValue: initialDate ?? Date())
        _useDate = State(initialValue: initialDate != nil)
        _durationMinutes = State(initialValue: 120) // Default 2 hours
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.7)

            VStack(alignment: .leading, spacing: 14) {
                captureCard
                detailsCard
                if let error { errorCard(error) }
            }
            .padding(18)

            Divider().opacity(0.7)
            footer
        }
        .background(FacetTheme.canvas)
        .frame(width: 500)
        .onAppear {
            durationMinutes = settings.defaultEventDurationMinutes
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Text(projectInitial)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Add to \(project.name)")
                    .font(.system(size: 18, weight: .semibold))
                Text(targetContainer.isEmpty ? "Choose a default save location first" : targetContainer)
                    .font(.caption)
                    .foregroundStyle(targetContainer.isEmpty ? .red : .secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Type", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("What needs doing?", text: $content, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1...3)
                .padding(12)
                .background(FacetTheme.panel.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                        .stroke(FacetTheme.hairline, lineWidth: 1)
                )

            Text("Saved as “\(ProjectPrefix.makeTitle(project: project.prefix, content: content.isEmpty ? "…" : content))”.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            settingRow(title: kind == .reminder ? "Reminder List" : "Calendar",
                       systemImage: kind == .reminder ? "list.bullet" : "calendar") {
                Text(targetContainer.isEmpty ? "None" : targetContainer)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(targetContainer.isEmpty ? .red : .secondary)
                    .lineLimit(1)
            }

            cardDivider

            if kind == .reminder {
                settingRow(title: "Priority", systemImage: "exclamationmark.circle") {
                    PriorityPillPicker(selection: $priority)
                }
                cardDivider
            }

            settingRow(title: kind == .reminder ? "Due Date" : "Start", systemImage: "calendar") {
                dateControl
            }

            cardDivider

            VStack(alignment: .leading, spacing: 7) {
                Label("Notes", systemImage: "doc.text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Add details...", text: $notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(2...4)
                    .padding(10)
                    .background(FacetTheme.panel.opacity(0.60))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1)
                    )
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var dateControl: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                if kind == .event {
                    if isAllDay {
                        DatePicker("", selection: $date, displayedComponents: [.date])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .controlSize(.small)
                    } else {
                        DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .controlSize(.small)
                    }
                    Toggle("All day", isOn: $isAllDay)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                } else {
                    Toggle("", isOn: $useDate)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                    if useDate {
                        DatePicker("", selection: $date, displayedComponents: [.date])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .controlSize(.small)
                    } else {
                        Text("No date")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if kind == .event && !isAllDay {
                HStack(spacing: 4) {
                    Text("Duration:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("", value: $durationMinutes, format: .number)
                        .textFieldStyle(.plain)
                        .frame(width: 40)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 12))
                    Text("min")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Stepper("", value: $durationMinutes, in: 5...1440, step: 15)
                        .labelsHidden()
                        .controlSize(.small)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel") { dismiss() }
                .controlSize(.small)
            Button { save() } label: {
                Label(saving ? "Adding..." : "Add", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
            .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty
                      || targetContainer.isEmpty || saving)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func settingRow<Content: View>(title: String, systemImage: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            content()
        }
        .padding(.vertical, 9)
    }

    private var cardDivider: some View {
        Divider().opacity(0.38)
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
    }

    private var projectInitial: String {
        project.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .first.map { String($0).uppercased() } ?? "F"
    }

    private var targetContainer: String {
        switch kind {
        case .reminder:
            return project.reminderListName.nonEmpty ?? settings.defaultReminderListName
        case .event:
            return project.calendarName.nonEmpty ?? settings.defaultCalendarName
        }
    }

    private func save() {
        let text = content.trimmingCharacters(in: .whitespaces)
        let container = targetContainer
        guard !text.isEmpty, !container.isEmpty else { return }
        saving = true
        error = nil
        Task {
            let ok: Bool
            switch kind {
            case .reminder:
                ok = await ek.createReminder(project: project.prefix, content: text,
                                             listName: container, dueDate: useDate ? date : nil,
                                             notes: notes.isEmpty ? nil : notes,
                                             priority: priority) != nil
            case .event:
                ok = await ek.createEvent(project: project.prefix, content: text,
                                          calendarName: container, startDate: date,
                                          durationMinutes: durationMinutes,
                                          notes: notes.isEmpty ? nil : notes,
                                          isAllDay: isAllDay)
            }
            saving = false
            if ok { onCreated(); dismiss() }
            else { error = "Could not save to \(container). Check access." }
        }
    }
}
