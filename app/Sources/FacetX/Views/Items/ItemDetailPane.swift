import AppKit
import FacetXCore
import SwiftUI

struct ItemDetailPane: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var toast: ToastController
    @State private var noteStore = ItemNoteStore.shared
    @State private var paperStore = PaperStore.shared

    let item: ProjectItem
    let project: Project
    let focusTitleOnAppear: Bool
    let onClose: () -> Void
    let onReplacementStart: () -> Void
    let onUpdate: (String?) -> Void

    @State private var kind: ProjectItem.Kind
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
    @State private var loadingFields = false
    @State private var autoSaveTask: Task<Void, Never>? = nil
    @State private var noteAutoSaveTask: Task<Void, Never>? = nil
    @State private var savedEditSignature = ""
    @State private var savedNoteSignature = ""
    @State private var didEdit = false
    @State private var itemMetadata = FacetItemMetadata()
    @State private var metadataNeedsRepair = false

    private let labelWidth: CGFloat = 76
    private let scheduleBoxHorizontalPadding: CGFloat = 8
    private let durationPresets = [30, 60, 120, 180, 240]

    init(item: ProjectItem,
         project: Project,
         focusTitleOnAppear: Bool = false,
         onClose: @escaping () -> Void,
         onReplacementStart: @escaping () -> Void = {},
         onUpdate: @escaping (String?) -> Void) {
        self.item = item
        self.project = project
        self.focusTitleOnAppear = focusTitleOnAppear
        self.onClose = onClose
        self.onReplacementStart = onReplacementStart
        self.onUpdate = onUpdate
        _kind = State(initialValue: item.kind)
    }

    private var modeIdentity: String {
        item.id
    }

    private var hasChanges: Bool {
        editSignature != savedEditSignature
    }

    private var kindSelection: Binding<ProjectItem.Kind> {
        Binding(
            get: { kind },
            set: { newKind in
                guard newKind != kind else { return }
                convertItem(to: newKind)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            FacetSidebarContent {
                titleCard
                scheduleCard
                linkCard
                tagsCard
                resourcesCard
                notesCard
            }

            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FacetTheme.canvas)
        .onAppear(perform: loadFields)
        .onChange(of: modeIdentity) {
            loadFields()
        }
        .onChange(of: content) { scheduleAutosave() }
        .onChange(of: notes) { scheduleNoteAutosave() }
        .onChange(of: tagsText) { scheduleAutosave() }
        .onChange(of: priority) { scheduleAutosave() }
        .onChange(of: useDate) { handleUseDateChanged() }
        .onChange(of: reminderHasTime) { handleReminderHasTimeChanged() }
        .onChange(of: endDate) { scheduleAutosave() }
        .onChange(of: urlString) { scheduleAutosave() }
        .onChange(of: date) { handleDateChanged() }
        .onChange(of: durationMinutes) { handleDurationChanged() }
        .onChange(of: isAllDay) { handleAllDayChanged() }
        .onDisappear {
            autoSaveTask?.cancel()
            noteAutoSaveTask?.cancel()
            saveLocalNoteIfNeeded()
            if hasChanges {
                saveChanges()
            }
        }
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                let isLit = !item.linkedPaperIDs.isEmpty
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isLit ? Color.yellow.opacity(0.14) : (kind == .reminder ? Color.green.opacity(0.14) : Color.blue.opacity(0.14)))
                    Image(systemName: isLit ? "books.vertical" : (kind == .reminder ? "checkmark.circle" : "calendar"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isLit ? .yellow : (kind == .reminder ? .green : .blue))
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 5) {
                    TitleEditingField(
                        text: $content,
                        placeholder: kind == .reminder ? L10n.pick("What needs doing?", "要做什么？")
                                                       : L10n.pick("What is scheduled?", "安排什么？"),
                        focusOnAppear: focusTitleOnAppear
                    )
                    .frame(height: 24)

                    Text(project.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                titleActions
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

    @ViewBuilder private var titleActions: some View {
        if item.linkedPaperIDs.isEmpty {
            Picker("", selection: kindSelection) {
                Text(L10n.pick("Task", "任务")).tag(ProjectItem.Kind.reminder)
                Text(L10n.pick("Event", "事件")).tag(ProjectItem.Kind.event)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 116)
            .disabled(saving)
            .help(L10n.pick("Choose item type", "选择条目类型"))
        }
    }

    private var scheduleCard: some View {
        FacetDetailBox {
            VStack(spacing: 0) {
                if kind == .reminder {
                    propertyRow(label: L10n.pick("Priority", "优先级"), icon: "exclamationmark.circle") {
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
        FacetDetailSection(title: L10n.pick("Link", "链接"), systemImage: "link") {
            HStack(spacing: 6) {
                TextField(L10n.pick("Link associated...", "关联链接…"), text: $urlString)
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
                    .help(L10n.pick("Open link", "打开链接"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var tagsCard: some View {
        FacetDetailSection(title: L10n.pick("Tags", "标签"), systemImage: "tag") {
            TagChipEditor(tagsText: $tagsText, knownColors: settings)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var resourcesCard: some View {
        FacetDetailSection(title: L10n.pick("Linked Resources", "关联资源"), systemImage: "link.badge.plus") {
            VStack(alignment: .leading, spacing: 10) {
                if !itemMetadata.paperIDs.isEmpty {
                    linkedPapersSection
                } else {
                    linkedCommitsSection
                }
            }
            .padding(10)
        }
    }

    // MARK: - Literature section

    private var linkedPapersSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            resourceHeader(
                title: L10n.pick("Literature", "文献"),
                count: itemMetadata.paperIDs.count,
                systemImage: "books.vertical"
            ) {
                EmptyView()
            }
            ForEach(itemMetadata.paperIDs, id: \.self) { paperID in
                paperResourceRow(paperID: paperID) {
                    updateItemMetadata(itemMetadata.removingPaper(paperID))
                }
            }
        }
    }

    private func paperResourceRow(paperID: String, onRemove: @escaping () -> Void) -> some View {
        let paper = paperStore.papers.first(where: { $0.id == paperID })
        let subtitle: String = {
            var parts: [String] = []
            if let first = paper?.authors.first { parts.append(first) }
            if let year = paper?.publicationDate, !year.isEmpty { parts.append(year) }
            return parts.joined(separator: " · ")
        }()


        return HStack(spacing: 8) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.yellow)
                .frame(width: 16, height: 16)
                .background(Color.yellow.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(paper?.title ?? paperID)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)

                    Button {
                        NotificationCenter.default.post(name: .navigateToPaper, object: nil, userInfo: ["paperID": paperID])
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.pick("View in Library", "在文献库中查看"))
                    .hoverCursor(.pointingHand)
                }

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if item.linkedPaperIDs.isEmpty {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(saving)
                .help(L10n.pick("Unlink paper", "取消文献关联"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Commits section

    private var linkedCommitsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            resourceHeader(
                title: L10n.pick("Commits", "提交"),
                count: itemMetadata.commits.count,
                systemImage: "curlybraces"
            ) {
                EmptyView()
            }

            if itemMetadata.commits.isEmpty {
                emptyResourceText(L10n.pick("No linked commits.", "暂无关联提交。"))
            } else {
                ForEach(itemMetadata.commits, id: \.self) { commit in
                    commitResourceRow(commitString: commit) {
                        updateItemMetadata(itemMetadata.removingCommit(commit))
                    }
                }
            }
        }
    }

    private func parseCommit(_ commitString: String) -> (repo: String, sha: String, shortSha: String, url: URL?)? {
        let parts = commitString.split(separator: "@")
        guard parts.count == 2 else { return nil }
        let repo = String(parts[0])
        let sha = String(parts[1])
        let shortSha = String(sha.prefix(7))
        let url = URL(string: "https://github.com/\(repo)/commit/\(sha)")
        return (repo: repo, sha: sha, shortSha: shortSha, url: url)
    }

    private func commitResourceRow(commitString: String, onRemove: @escaping () -> Void) -> some View {
        let parsed = parseCommit(commitString)
        let titleText = parsed?.shortSha ?? commitString
        let subtitleText = parsed?.repo
        
        return HStack(spacing: 8) {
            Image(systemName: "curlybraces")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.purple)
                .frame(width: 16, height: 16)
                .background(Color.purple.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(titleText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                    
                    if let url = parsed?.url {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                if let subtitleText {
                    Text(subtitleText)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 8)
            
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(saving)
            .help(L10n.pick("Unlink", "取消关联"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func resourceHeader<Action: View>(title: String, count: Int, systemImage: String,
                                              @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.10))
                .clipShape(Capsule())
            Spacer()
            action()
        }
    }

    private func emptyResourceText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }

    private var notesCard: some View {
        FacetDetailSection(title: L10n.pick("Notes", "笔记"), systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 8) {
                if metadataNeedsRepair {
                    HStack(spacing: 8) {
                        Label(L10n.pick("Metadata needs rebuild", "元数据需要重建"), systemImage: "wrench.and.screwdriver")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button {
                            rebuildMetadata()
                        } label: {
                            Label(L10n.pick("Rebuild", "重建"), systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .disabled(saving)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                }

                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text(L10n.pick("Add notes and details here...", "在此添加笔记和详情…"))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $notes)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.hidden)
                        .hideTextEditorScroller()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var eventScheduleSection: some View {
        VStack(spacing: 0) {
            propertyRow(label: L10n.pick("Date", "日期"), icon: "calendar") {
                eventDateControl
            }

            if !isAllDay {
                propertyDivider
                propertyRow(label: L10n.pick("Time", "时间"), icon: "clock") {
                    eventTimeControl
                }
            }
        }
    }

    private var reminderScheduleSection: some View {
        VStack(spacing: 0) {
            propertyRow(label: L10n.pick("Due Date", "截止日期"), icon: "calendar") {
                reminderDueDateControl
            }

            if useDate {
                propertyDivider
                propertyRow(label: L10n.pick("Time", "时间"), icon: "clock") {
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
                Text(L10n.pick("All day", "全天"))
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
                Text("-")
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
                Text("-")
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
            saveStatus
            Spacer()
            Button(role: .destructive) {
                deleteItem()
            } label: {
                Label(L10n.pick("Delete", "删除"), systemImage: "trash")
            }
            .controlSize(.small)
            .disabled(saving)
            .help(L10n.pick("Delete item", "删除条目"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(FacetTheme.canvas)
    }

    @ViewBuilder private var saveStatus: some View {
        if saving || hasChanges || didEdit {
            Label(saving ? L10n.pick("Saving...", "保存中…")
                         : (hasChanges ? L10n.pick("Autosaving...", "自动保存中…") : L10n.pick("Saved", "已保存")),
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

        kind = item.kind
        content = item.content
        itemMetadata = FacetItemMetadata(
            itemID: item.facetID ?? UUID().uuidString,
            noteID: item.noteID ?? UUID().uuidString,
            paperIDs: item.linkedPaperIDs,
            commits: item.linkedCommits,
            tags: item.tags
        )
        metadataNeedsRepair = item.needsMetadataRepair
        let localNotes = noteStore.body(for: itemMetadata.noteID)
        notes = localNotes.isEmpty && metadataNeedsRepair ? (item.notes ?? "") : localNotes
        savedNoteSignature = notes
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
            isAllDay = false
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
        let shouldUseDate = kind == .event || useDate
        let datePart: String
        if kind == .event {
            datePart = shouldUseDate ? minuteSignature(date) : "none"
        } else if shouldUseDate {
            datePart = reminderHasTime ? minuteSignature(date) : daySignature(date)
        } else {
            datePart = "none"
        }
        let endPart = kind == .event ? (isAllDay ? daySignature(endDate) : minuteSignature(endDate)) : "none"
        let reminderTimePart = kind == .reminder && useDate ? "\(reminderHasTime)" : "false"
        return [
            content.trimmingCharacters(in: .whitespaces),
            FacetMetadata.tags(from: tagsText).joined(separator: ","),
            "\(priority)",
            "\(useDate)",
            datePart,
            reminderTimePart,
            "\(isAllDay)",
            endPart,
            urlString.trimmingCharacters(in: .whitespaces),
            containerName,
            "\(kind)"
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

    private func scheduleNoteAutosave() {
        guard !loadingFields else { return }
        noteAutoSaveTask?.cancel()
        guard notes != savedNoteSignature else { return }

        noteAutoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveLocalNoteIfNeeded()
            }
        }
    }

    private func saveLocalNoteIfNeeded() {
        guard notes != savedNoteSignature else { return }
        noteStore.save(id: itemMetadata.noteID, body: notes)
        savedNoteSignature = notes
    }

    private func handleUseDateChanged() {
        guard !loadingFields else { return }
        if useDate, kind == .reminder {
            date = reminderHasTime ? defaultTimedDate() : defaultDayDate()
        } else if !useDate {
            reminderHasTime = false
        }
        scheduleAutosave()
    }

    private func handleReminderHasTimeChanged() {
        guard !loadingFields else { return }
        if kind == .reminder, useDate {
            date = reminderHasTime ? defaultTimedDate() : defaultDayDate()
        }
        scheduleAutosave()
    }

    private func handleDateChanged() {
        alignEventEndAfterStartChange()
        scheduleAutosave()
    }

    private func handleDurationChanged() {
        alignEventEndAfterDurationChange()
        scheduleAutosave()
    }

    private func handleAllDayChanged() {
        guard !loadingFields else { return }
        if kind == .event {
            date = isAllDay ? defaultDayDate() : defaultTimedDate()
        }
        alignEventEndAfterAllDayToggle()
        scheduleAutosave()
    }

    private func alignEventEndAfterStartChange() {
        guard kind == .event else { return }
        if isAllDay {
            endDate = oneDayAfterStart()
        } else {
            endDate = timedEndDate()
        }
    }

    private func alignEventEndAfterDurationChange() {
        guard kind == .event, !isAllDay else { return }
        endDate = timedEndDate()
    }

    private func alignEventEndAfterAllDayToggle() {
        guard kind == .event else { return }
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
        return FacetDateDefaults.dayDefault()
    }

    private func defaultTimedDate() -> Date {
        return FacetDateDefaults.nextWholeHour()
    }

    private func saveChanges() {
        let text = content.trimmingCharacters(in: .whitespaces)
        let targetContainer = containerName.isEmpty ? item.containerName : containerName
        guard !text.isEmpty, !targetContainer.isEmpty, hasChanges else { return }

        saving = true
        let signature = editSignature
        let trimmedURL = urlString.trimmingCharacters(in: .whitespaces)
        let urlParam = trimmedURL.isEmpty ? nil : URL(string: trimmedURL)
        let shouldUseDate = kind == .event || useDate
        let tags = FacetMetadata.tags(from: tagsText)

        Task {
            if metadataNeedsRepair {
                await rebuildMetadata(tags: tags)
            }
            let ok = await ek.updateItem(
                id: item.id,
                project: project.prefix,
                content: text,
                date: shouldUseDate ? date : nil,
                useDate: shouldUseDate,
                dateIncludesTime: kind == .reminder && reminderHasTime,
                containerName: targetContainer,
                notes: nil,
                tags: tags,
                priority: priority,
                url: urlParam,
                updateURL: true,
                isAllDay: kind == .event ? isAllDay : nil,
                endDate: kind == .event ? endDate : nil
            )
            saving = false
            if ok {
                savedEditSignature = signature
                onUpdate(nil)
            } else {
                toast.show(L10n.pick("Failed to save changes", "保存更改失败"), type: .error)
            }
        }
    }

    private func rebuildMetadata() {
        let tags = FacetMetadata.tags(from: tagsText)
        Task {
            await rebuildMetadata(tags: tags)
        }
    }

    @discardableResult
    private func rebuildMetadata(tags: [String]) async -> Bool {
        saveLocalNoteIfNeeded()
        noteStore.absorbLegacyNotes(id: itemMetadata.noteID, legacyBody: item.notes ?? "")
        itemMetadata.tags = tags
        saving = true
        let ok = await ek.rewriteItemMetadata(id: item.id, metadata: itemMetadata)
        saving = false
        if ok {
            metadataNeedsRepair = false
            notes = noteStore.body(for: itemMetadata.noteID)
            savedNoteSignature = notes
            onUpdate(item.id)
        } else {
            toast.show(L10n.pick("Failed to rebuild metadata", "重建元数据失败"), type: .error)
        }
        return ok
    }

    private func updateItemMetadata(_ metadata: FacetItemMetadata) {
        saveLocalNoteIfNeeded()
        noteStore.absorbLegacyNotes(id: metadata.noteID, legacyBody: item.notes ?? "")
        var updated = metadata
        updated.tags = FacetMetadata.tags(from: tagsText)
        saving = true
        Task {
            let ok = await ek.rewriteItemMetadata(id: item.id, metadata: updated)
            saving = false
            if ok {
                itemMetadata = updated
                metadataNeedsRepair = false
                onUpdate(item.id)
            } else {
                toast.show(L10n.pick("Failed to update links", "更新关联失败"), type: .error)
            }
        }
    }

    private func deleteItem() {
        saving = true
        Task {
            let ok = await ek.deleteItem(id: item.id)
            saving = false
            if ok {
                onUpdate(nil)
                onClose()
            } else {
                toast.show(L10n.pick("Failed to delete item", "删除条目失败"), type: .error)
            }
        }
    }

    private func convertItem(to newKind: ProjectItem.Kind) {
        guard item.linkedPaperIDs.isEmpty else { return }
        guard newKind != item.kind else { return }
        saving = true
        onReplacementStart()
        saveLocalNoteIfNeeded()
        noteStore.absorbLegacyNotes(id: itemMetadata.noteID, legacyBody: item.notes ?? "")
        Task {
            let newId: String?
            if item.kind == .reminder {
                let calName = project.calendarName ?? ""
                newId = await ek.convertReminderToEvent(
                    reminderId: item.id,
                    project: project.prefix,
                    content: item.content,
                    notes: nil,
                    tags: item.tags,
                    itemMetadata: itemMetadata,
                    dueDate: item.date,
                    durationMinutes: settings.defaultEventDurationMinutes,
                    calendarName: calName.isEmpty ? settings.defaultCalendarName : calName,
                    enabledCalendars: settings.effectiveCalendarNames
                )
            } else {
                let listName = project.reminderListName ?? ""
                newId = await ek.convertEventToReminder(
                    eventId: item.id,
                    project: project.prefix,
                    content: item.content,
                    notes: nil,
                    tags: item.tags,
                    itemMetadata: itemMetadata,
                    priority: item.priority,
                    startDate: item.date,
                    hasTime: item.hasTime,
                    listName: listName.isEmpty ? settings.defaultReminderListName : listName,
                    enabledLists: settings.effectiveReminderListNames
                )
            }
            saving = false
            if let newId {
                toast.show(
                    item.kind == .reminder ? L10n.pick("Converted to schedule", "已转为事件")
                                           : L10n.pick("Converted to reminder", "已转为任务"),
                    type: .success
                )
                onUpdate(newId)
            } else {
                kind = item.kind
                toast.show(L10n.pick("Conversion failed", "转换失败"), type: .error)
            }
        }
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
}

private struct TitleEditingField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusOnAppear: Bool

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 17, weight: .semibold)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.delegate = context.coordinator
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder
        if focusOnAppear && !context.coordinator.didFocus {
            context.coordinator.focusWhenReady(field)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        weak var field: NSTextField?
        var didFocus = false

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }

        func focusWhenReady(_ field: NSTextField, attempts: Int = 0) {
            guard !didFocus else { return }
            DispatchQueue.main.async {
                if field.window == nil, attempts < 4 {
                    self.focusWhenReady(field, attempts: attempts + 1)
                    return
                }
                guard field.window != nil else { return }
                self.didFocus = true
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }
}
