import SwiftUI
import FacetXCore

struct ItemDetailPane: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var toast: ToastController

    let item: ProjectItem
    let project: Project
    let onClose: () -> Void
    let onUpdate: () -> Void

    @State private var content = ""
    @State private var notes = ""
    @State private var tagsText = ""
    @State private var priority = 0
    @State private var useDate = false
    @State private var date = Date()
    @State private var reminderHasTime = false
    @State private var endDate = Date()
    @State private var durationMinutes = 60
    @State private var isAllDay = false
    @State private var urlString = ""
    @State private var containerName = ""
    @State private var saving = false
    @State private var showConvertConfirm = false
    @State private var loadingFields = false
    @State private var autoSaveTask: Task<Void, Never>? = nil
    @State private var savedEditSignature = ""
    /// Stays false until the user actually edits a field, so a freshly opened
    /// pane shows no save status (rather than an immediate "Saved").
    @State private var didEdit = false

    private let labelWidth: CGFloat = 76
    private let scheduleBoxHorizontalPadding: CGFloat = 8
    private let durationPresets = [30, 60, 120, 180, 240]

    private var hasChanges: Bool {
        editSignature != savedEditSignature
    }

    var body: some View {
        VStack(spacing: 0) {
            FacetSidebarContent {
                titleCard
                scheduleCard
                linkCard
                tagsCard
                notesCard
            }

            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FacetTheme.canvas)
        .onAppear(perform: loadFields)
        .onChange(of: item) {
            loadFields()
        }
        .onChange(of: content) { scheduleAutosave() }
        .onChange(of: notes) { scheduleAutosave() }
        .onChange(of: tagsText) { scheduleAutosave() }
        .onChange(of: priority) { scheduleAutosave() }
        .onChange(of: useDate) {
            guard !loadingFields else { return }
            if useDate, item.kind == .reminder {
                date = reminderHasTime ? defaultTimedDate() : defaultDayDate()
            } else if !useDate {
                reminderHasTime = false
            }
            scheduleAutosave()
        }
        .onChange(of: reminderHasTime) {
            guard !loadingFields else { return }
            if item.kind == .reminder, useDate {
                date = reminderHasTime ? defaultTimedDate() : defaultDayDate()
            }
            scheduleAutosave()
        }
        .onChange(of: endDate) { scheduleAutosave() }
        .onChange(of: urlString) { scheduleAutosave() }
        .onChange(of: date) {
            alignEventEndAfterStartChange()
            scheduleAutosave()
        }
        .onChange(of: durationMinutes) {
            alignEventEndAfterDurationChange()
            scheduleAutosave()
        }
        .onChange(of: isAllDay) {
            guard !loadingFields else { return }
            if item.kind == .event {
                date = isAllDay ? defaultDayDate() : defaultTimedDate()
            }
            alignEventEndAfterAllDayToggle()
            scheduleAutosave()
        }
        .onDisappear {
            autoSaveTask?.cancel()
            if hasChanges {
                saveChanges()
            }
        }
        .alert(
            item.kind == .reminder ? "Convert to Event?" : "Convert to Reminder?",
            isPresented: $showConvertConfirm
        ) {
            Button("Cancel", role: .cancel) {}
            Button(item.kind == .reminder ? "Convert to Event" : "Convert to Reminder") {
                convertItem()
            }
        } message: {
            Text(item.kind == .reminder
                ? "This reminder will be moved to your calendar as an event."
                : "This event will be moved to your reminders.")
        }
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.kind == .reminder ? Color.green.opacity(0.14) : Color.blue.opacity(0.14))
                    Image(systemName: item.kind == .reminder ? "checkmark.circle" : "calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.kind == .reminder ? .green : .blue)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 5) {
                    TextField("What needs doing?", text: $content, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1...4)

                    Text(project.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var scheduleCard: some View {
        FacetDetailSection(title: item.kind == .event ? "Schedule" : "Task",
                           systemImage: item.kind == .event ? "calendar" : "checklist") {
            VStack(spacing: 0) {
                if item.kind == .reminder {
                    propertyRow(label: "Priority", icon: "exclamationmark.circle") {
                        PriorityPillPicker(selection: $priority)
                    }
                    propertyDivider
                    reminderScheduleSection
                } else {
                    eventScheduleSection
                }
            }
            .padding(.horizontal, scheduleBoxHorizontalPadding)
            .padding(.vertical, 4)
        }
    }

    private var linkCard: some View {
        FacetDetailSection(title: "Link", systemImage: "link") {
            HStack(spacing: 6) {
                TextField("Link associated...", text: $urlString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(minWidth: 0)

                if let parsedURL = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
                   !urlString.trimmingCharacters(in: .whitespaces).isEmpty {
                    Link(destination: parsedURL) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Open link")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var tagsCard: some View {
        FacetDetailSection(title: "Tags", systemImage: "tag") {
            TextField("deep, waiting, writing", text: $tagsText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notesCard: some View {
        FacetDetailSection(title: "Notes", systemImage: "doc.text") {
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Add notes and details here...")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $notes)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var eventScheduleSection: some View {
        VStack(spacing: 0) {
            propertyRow(label: "Date", icon: "calendar") {
                eventDateControl
            }

            if !isAllDay {
                propertyDivider
                propertyRow(label: "Time", icon: "clock") {
                    eventTimeControl
                }
            }
        }
    }

    private var reminderScheduleSection: some View {
        VStack(spacing: 0) {
            propertyRow(label: "Due Date", icon: "calendar") {
                reminderDueDateControl
            }

            if useDate {
                propertyDivider
                propertyRow(label: "Time", icon: "clock") {
                    reminderTimeControl
                }
            }
        }
    }

    private var eventDateControl: some View {
        HStack(spacing: 8) {
            dateField($date, components: [.date], width: 116)

            Spacer(minLength: 6)

            Toggle(isOn: $isAllDay) {
                Text("All day")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var eventTimeControl: some View {
        HStack(spacing: 8) {
            timeField

            Spacer(minLength: 6)

            durationPresetMenu
            durationStepper
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var timeField: some View {
        dateField($date, components: [.hourAndMinute], width: 74)
    }

    private var reminderDueDateControl: some View {
        HStack(spacing: 12) {
            if useDate {
                dateField($date, components: [.date], width: 128)
            } else {
                Text("—")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $useDate)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private var reminderTimeControl: some View {
        HStack(spacing: 12) {
            if reminderHasTime {
                dateField($date, components: [.hourAndMinute], width: 74)
            } else {
                Text("—")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $reminderHasTime)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private var durationPresetMenu: some View {
        Menu {
            ForEach(durationPresets, id: \.self) { preset in
                Button(durationLabel(preset)) {
                    durationMinutes = preset
                }
            }
        } label: {
            Text(durationLabel(durationMinutes))
                .font(.system(size: 11, weight: .medium))
                .frame(width: 58, alignment: .center)
        }
        .menuStyle(.button)
        .controlSize(.small)
    }

    private var durationStepper: some View {
        Stepper("", value: $durationMinutes, in: 5...1440, step: 15)
            .labelsHidden()
            .controlSize(.mini)
            .fixedSize()
    }

    private func dateField(_ selection: Binding<Date>, components: DatePickerComponents,
                           width: CGFloat? = nil) -> some View {
        DatePicker("", selection: selection, displayedComponents: components)
            .labelsHidden()
            .datePickerStyle(.field)
            .controlSize(.small)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private var propertyDivider: some View {
        Divider()
            .padding(.leading, labelWidth + 12)
            .opacity(0.38)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                deleteItem()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.82))
                    .frame(width: 32, height: 32)
                    .background(Color.red.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Delete item")

            Button {
                showConvertConfirm = true
            } label: {
                Image(systemName: "arrow.2.squarepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue.opacity(0.82))
                    .frame(width: 32, height: 32)
                    .background(Color.blue.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(item.kind == .reminder ? "Convert to calendar event" : "Convert to reminder")

            Spacer()

            saveStatus
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(FacetTheme.canvas)
    }

    @ViewBuilder private var saveStatus: some View {
        if saving || hasChanges || didEdit {
            Label(saving ? "Saving..." : (hasChanges ? "Autosaving..." : "Saved"),
                  systemImage: saving || hasChanges ? "clock" : "checkmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func propertyRow<Control: View>(label: String, icon: String,
                                            @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon)
                    .frame(width: 13)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: labelWidth, alignment: .leading)

            control()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .clipped()
        }
        .padding(.vertical, 9)
    }

    private func loadFields() {
        loadingFields = true
        didEdit = false
        autoSaveTask?.cancel()
        content = item.content
        notes = item.notes ?? ""
        tagsText = item.tags.joined(separator: ", ")
        priority = item.priority
        containerName = item.containerName
        urlString = item.url?.absoluteString ?? ""
        if item.kind == .event {
            useDate = true
            date = item.date ?? defaultTimedDate()
            reminderHasTime = false
            isAllDay = item.isAllDay
            if let end = item.endDate {
                endDate = end
            } else {
                endDate = Calendar.current.date(byAdding: .hour, value: 2, to: date) ?? date
            }
            durationMinutes = durationMinutesBetween(start: date, end: endDate)
        } else if let d = item.date {
            useDate = true
            date = d
            reminderHasTime = item.hasTime
            isAllDay = false
            endDate = Calendar.current.date(byAdding: .hour, value: 2, to: date) ?? d
            durationMinutes = clampedDurationMinutes(settings.defaultEventDurationMinutes)
        } else {
            useDate = false
            date = defaultDayDate()
            reminderHasTime = false
            isAllDay = false
            endDate = Calendar.current.date(byAdding: .hour, value: 2, to: date) ?? date
            durationMinutes = clampedDurationMinutes(settings.defaultEventDurationMinutes)
        }

        DispatchQueue.main.async {
            savedEditSignature = editSignature
            loadingFields = false
        }
    }

    private var editSignature: String {
        let shouldUseDate = item.kind == .event || useDate
        let datePart: String
        if item.kind == .event {
            datePart = shouldUseDate ? minuteSignature(date) : "none"
        } else if shouldUseDate {
            datePart = reminderHasTime ? minuteSignature(date) : daySignature(date)
        } else {
            datePart = "none"
        }
        let endPart = item.kind == .event ? (isAllDay ? daySignature(endDate) : minuteSignature(endDate)) : "none"
        let reminderTimePart = item.kind == .reminder && useDate ? "\(reminderHasTime)" : "false"
        return [
            content.trimmingCharacters(in: .whitespaces),
            notes.trimmingCharacters(in: .whitespacesAndNewlines),
            FacetMetadata.tags(from: tagsText).joined(separator: ","),
            "\(priority)",
            "\(useDate)",
            datePart,
            reminderTimePart,
            "\(isAllDay)",
            endPart,
            urlString.trimmingCharacters(in: .whitespaces)
        ].joined(separator: "\n")
    }

    private func minuteSignature(_ value: Date) -> String {
        String(Int((value.timeIntervalSinceReferenceDate / 60).rounded()))
    }

    private func daySignature(_ value: Date) -> String {
        let startOfDay = Calendar.current.startOfDay(for: value)
        return String(Int((startOfDay.timeIntervalSinceReferenceDate / 86_400).rounded()))
    }

    private func scheduleAutosave() {
        guard !loadingFields else { return }
        didEdit = true
        autoSaveTask?.cancel()
        guard hasChanges, !content.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveChanges()
            }
        }
    }

    private func alignEventEndAfterStartChange() {
        guard item.kind == .event else { return }
        if isAllDay {
            endDate = oneDayAfterStart()
        } else {
            endDate = timedEndDate()
        }
    }

    private func alignEventEndAfterDurationChange() {
        guard item.kind == .event, !isAllDay else { return }
        endDate = timedEndDate()
    }

    private func alignEventEndAfterAllDayToggle() {
        guard item.kind == .event else { return }
        endDate = isAllDay ? oneDayAfterStart() : timedEndDate()
    }

    private func oneDayAfterStart() -> Date {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
    }

    private func timedEndDate() -> Date {
        let minutes = clampedDurationMinutes(durationMinutes)
        return Calendar.current.date(byAdding: .minute, value: minutes, to: date)
            ?? date.addingTimeInterval(3600)
    }

    private func durationMinutesBetween(start: Date, end: Date) -> Int {
        let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
        return clampedDurationMinutes(minutes)
    }

    private func clampedDurationMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 5), 1440)
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainder)m"
    }

    private func defaultDayDate() -> Date {
        FacetDateDefaults.dayDefault()
    }

    private func defaultTimedDate() -> Date {
        FacetDateDefaults.nextWholeHour()
    }

    private func saveChanges() {
        let text = content.trimmingCharacters(in: .whitespaces)
        let targetContainer = containerName.isEmpty ? item.containerName : containerName
        guard !text.isEmpty, !targetContainer.isEmpty, hasChanges else { return }

        saving = true
        let signature = editSignature
        let trimmedURL = urlString.trimmingCharacters(in: .whitespaces)
        let urlParam = trimmedURL.isEmpty ? nil : URL(string: trimmedURL)
        let shouldUseDate = item.kind == .event || useDate
        let tags = FacetMetadata.tags(from: tagsText)

        Task {
            let ok = await ek.updateItem(
                id: item.id,
                project: project.prefix,
                content: text,
                date: shouldUseDate ? date : nil,
                useDate: shouldUseDate,
                dateIncludesTime: item.kind == .reminder && reminderHasTime,
                containerName: targetContainer,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
                tags: tags,
                priority: priority,
                url: urlParam,
                updateURL: true,
                isAllDay: item.kind == .event ? isAllDay : nil,
                endDate: item.kind == .event ? endDate : nil
            )
            saving = false
            if ok {
                savedEditSignature = signature
                onUpdate()
            } else {
                toast.show("Failed to save changes", type: .error)
            }
        }
    }

    private func deleteItem() {
        saving = true
        Task {
            let ok = await ek.deleteItem(id: item.id)
            saving = false
            if ok {
                onUpdate()
                onClose()
            } else {
                toast.show("Failed to delete item", type: .error)
            }
        }
    }

    private func convertItem() {
        saving = true
        Task {
            let ok: Bool
            if item.kind == .reminder {
                let calName = project.calendarName ?? ""
                ok = await ek.convertReminderToEvent(
                    reminderId: item.id,
                    project: project.prefix,
                    content: item.content,
                    notes: item.notes,
                    tags: item.tags,
                    dueDate: item.date,
                    durationMinutes: settings.defaultEventDurationMinutes,
                    calendarName: calName.isEmpty ? settings.defaultCalendarName : calName
                )
            } else {
                let listName = project.reminderListName ?? ""
                ok = await ek.convertEventToReminder(
                    eventId: item.id,
                    project: project.prefix,
                    content: item.content,
                    notes: item.notes,
                    tags: item.tags,
                    priority: item.priority,
                    startDate: item.date,
                    hasTime: item.hasTime,
                    listName: listName.isEmpty ? settings.defaultReminderListName : listName
                )
            }
            saving = false
            if ok {
                toast.show(
                    item.kind == .reminder ? "Converted to event" : "Converted to reminder",
                    type: .success
                )
                onUpdate()
                onClose()
            } else {
                toast.show("Conversion failed", type: .error)
            }
        }
    }
}
