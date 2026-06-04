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
    @State private var endDate = Date()
    @State private var isAllDay = false
    @State private var urlString = ""
    @State private var containerName = ""
    @State private var saving = false

    private let labelWidth: CGFloat = 76

    private var hasChanges: Bool {
        if content.trimmingCharacters(in: .whitespaces) != item.content { return true }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines) != (item.notes ?? "") { return true }
        if FacetMetadata.tags(from: tagsText) != item.tags { return true }
        if priority != item.priority { return true }
        let itemHasDate = item.date != nil
        if item.kind == .reminder, useDate != itemHasDate { return true }
        if (item.kind == .event || useDate),
           let d = item.date,
           Calendar.current.compare(date, to: d, toGranularity: .minute) != .orderedSame { return true }
        if item.kind == .event {
            if isAllDay != item.isAllDay { return true }
            if let e = item.endDate {
                let granularity: Calendar.Component = isAllDay ? .day : .minute
                if Calendar.current.compare(endDate, to: e, toGranularity: granularity) != .orderedSame { return true }
            }
        }
        if containerName != item.containerName { return true }
        if urlString.trimmingCharacters(in: .whitespaces) != (item.url?.absoluteString ?? "") { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleCard
                    propertyCard
                    tagsCard
                    notesCard
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }

            Divider()
            footer
        }
        .frame(maxHeight: .infinity)
        .background(FacetTheme.canvas)
        .onAppear(perform: loadFields)
        .onChange(of: item) {
            loadFields()
        }
        .onChange(of: date) {
            alignEventEndAfterStartChange()
        }
        .onChange(of: isAllDay) {
            alignEventEndAfterAllDayToggle()
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

                    Text("\(project.name) · \(containerName.isEmpty ? item.containerName : containerName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var propertyCard: some View {
        VStack(spacing: 0) {
            propertyRow(label: item.kind == .reminder ? "List" : "Calendar",
                        icon: item.kind == .reminder ? "list.bullet" : "calendar") {
                Picker("", selection: $containerName) {
                    ForEach(containerOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if item.kind == .reminder {
                propertyDivider
                propertyRow(label: "Priority", icon: "exclamationmark.circle") {
                    PriorityPillPicker(selection: $priority)
                }
            }

            propertyDivider
            if item.kind == .event {
                eventScheduleSection
            } else {
                propertyRow(label: "Due Date", icon: "calendar") {
                    reminderDateControl
                }
            }

            propertyDivider
            propertyRow(label: "URL", icon: "link") {
                HStack(spacing: 6) {
                    TextField("Link associated...", text: $urlString)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(FacetTheme.panel.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(FacetTheme.hairline, lineWidth: 1)
                        )
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
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "doc.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

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
                    .frame(minHeight: 210)
            }
            .background(FacetTheme.quietPanel)
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
        }
    }

    private var tagsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tags", systemImage: "tag")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            TextField("deep, waiting, writing", text: $tagsText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(FacetTheme.quietPanel)
                .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                        .stroke(FacetTheme.hairline, lineWidth: 1)
                )
        }
    }

    private var eventScheduleSection: some View {
        VStack(spacing: 0) {
            propertyRow(label: "All day", icon: "clock") {
                allDayToggle
            }

            propertyDivider

            scheduleDateRow(label: "Starts", icon: "calendar", selection: $date)

            propertyDivider

            scheduleDateRow(label: "Ends", icon: "arrow.right", selection: $endDate)
        }
    }

    private func scheduleDateRow(label: String, icon: String, selection: Binding<Date>) -> some View {
        propertyRow(label: label, icon: icon) {
            HStack(spacing: 6) {
                dateField(selection, components: [.date], width: isAllDay ? nil : 126)

                if !isAllDay {
                    dateField(selection, components: [.hourAndMinute], width: 84)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var reminderDateControl: some View {
        HStack(spacing: 12) {
            if useDate {
                dateField($date, components: [.date], width: 148)
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

    private func dateField(_ selection: Binding<Date>, components: DatePickerComponents,
                           width: CGFloat? = nil) -> some View {
        DatePicker("", selection: selection, displayedComponents: components)
            .labelsHidden()
            .datePickerStyle(.field)
            .controlSize(.small)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private var allDayToggle: some View {
        Toggle("", isOn: $isAllDay)
            .labelsHidden()
            .toggleStyle(.checkbox)
            .controlSize(.small)
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

            Spacer()

            Button {
                saveChanges()
            } label: {
                Label("Save", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!hasChanges || content.trimmingCharacters(in: .whitespaces).isEmpty || saving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(FacetTheme.canvas)
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

    private var containerOptions: [String] {
        switch item.kind {
        case .reminder:
            return ek.reminderListNames(enabled: settings.effectiveReminderListNames)
        case .event:
            return ek.calendarNames(enabled: settings.effectiveCalendarNames)
        }
    }

    private func loadFields() {
        content = item.content
        notes = item.notes ?? ""
        tagsText = item.tags.joined(separator: ", ")
        priority = item.priority
        containerName = item.containerName
        urlString = item.url?.absoluteString ?? ""
        if item.kind == .event {
            useDate = true
            date = item.date ?? Date()
            isAllDay = item.isAllDay
            if let end = item.endDate {
                endDate = end
            } else {
                endDate = Calendar.current.date(byAdding: .hour, value: 2, to: date) ?? date
            }
        } else if let d = item.date {
            useDate = true
            date = d
            isAllDay = false
            endDate = Calendar.current.date(byAdding: .hour, value: 2, to: date) ?? d
        } else {
            useDate = false
            date = Date()
            isAllDay = false
            endDate = Calendar.current.date(byAdding: .hour, value: 2, to: date) ?? date
        }
    }

    private func alignEventEndAfterStartChange() {
        guard item.kind == .event else { return }
        if isAllDay {
            endDate = oneDayAfterStart()
        } else if endDate <= date {
            endDate = defaultTimedEndDate()
        }
    }

    private func alignEventEndAfterAllDayToggle() {
        guard item.kind == .event else { return }
        endDate = isAllDay ? oneDayAfterStart() : defaultTimedEndDate()
    }

    private func oneDayAfterStart() -> Date {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
    }

    private func defaultTimedEndDate() -> Date {
        let minutes = max(settings.defaultEventDurationMinutes, 5)
        return Calendar.current.date(byAdding: .minute, value: minutes, to: date)
            ?? date.addingTimeInterval(3600)
    }

    private func saveChanges() {
        let text = content.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !containerName.isEmpty else { return }

        saving = true
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
                containerName: containerName,
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
}
