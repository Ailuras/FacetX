import AppKit
import FacetXCore
import SwiftUI

struct ItemDetailPane: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var toast: ToastController
    @State private var itemStore = ItemStore.shared
    @State private var paperStore = PaperStore.shared

    let item: WorkItem
    let work: Work
    let focusTitleOnAppear: Bool
    let onClose: () -> Void
    let onReplacementStart: () -> Void
    let onUpdate: (String?) -> Void

    @State private var kind: WorkItem.Kind
    @State private var content = ""
    @State private var details = ""
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
    @State private var detailsAutoSaveTask: Task<Void, Never>? = nil
    @State private var savedEditSignature = ""
    @State private var savedDetailsSignature = ""
    @State private var didEdit = false
    @State private var itemReference = FacetItemReference()
    @State private var paperIDs: [String] = []
    @State private var commits: [String] = []
    @State private var documentPaths: [String] = []
    @State private var showingPaperPicker = false
    @State private var paperSearchText = ""
    @State private var showingCommitPicker = false
    @State private var commitSearchText = ""
    @State private var commitCandidates: [LocalGitCommit] = []

    private let labelWidth: CGFloat = 76
    private let scheduleBoxHorizontalPadding: CGFloat = 8
    private let durationPresets = [30, 60, 120, 180, 240]

    init(item: WorkItem,
         work: Work,
         focusTitleOnAppear: Bool = false,
         onClose: @escaping () -> Void,
         onReplacementStart: @escaping () -> Void = {},
         onUpdate: @escaping (String?) -> Void) {
        self.item = item
        self.work = work
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

    private var kindSelection: Binding<WorkItem.Kind> {
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
                detailsCard
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
        .onChange(of: details) { scheduleDetailsAutosave() }
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
            detailsAutoSaveTask?.cancel()
            saveLocalDetailsIfNeeded()
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

                    Text(work.name)
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
                Text(L10n.pick("Task", "任务")).tag(WorkItem.Kind.reminder)
                Text(L10n.pick("Event", "事件")).tag(WorkItem.Kind.event)
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
            VStack(spacing: 0) {
                linkedDocumentsSection
                Divider().padding(.horizontal, 10)
                linkedPapersSection
                Divider().padding(.horizontal, 10)
                linkedCommitsSection
            }
        }
    }

    // MARK: - Documents section

    private var linkedDocumentsSection: some View {
        let available = (try? RepositoryDocumentStore.list(repositoryPath: work.githubLocalPath)) ?? []
        let linkedPaths: [String] = documentPaths
        return FacetResourceGroup(
            title: L10n.pick("Documents", "文档"),
            count: documentPaths.count,
            systemImage: "doc.text",
            tint: .blue,
            emptyText: L10n.pick("No linked documents.", "暂无关联文档。"),
            action: {
                Menu {
                    if work.githubLocalPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                        Text(L10n.pick("Bind a local repository first.", "请先绑定本地仓库。"))
                    } else if available.isEmpty {
                        Text(L10n.pick("No repository documents.", "仓库中暂无文档。"))
                    } else {
                        ForEach(available) { document in
                            Button {
                                var updated = documentPaths
                                if updated.contains(document.relativePath) {
                                    updated.removeAll { $0 == document.relativePath }
                                } else {
                                    updated.append(document.relativePath)
                                }
                                updateDocumentPaths(updated)
                            } label: {
                                Label(document.title,
                                      systemImage: documentPaths.contains(document.relativePath) ? "checkmark" : "doc.text")
                            }
                        }
                    }
                } label: {
                    WorkspaceActionIcon(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(work.githubLocalPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                .help(L10n.pick("Attach Document", "关联文档"))
            },
            content: {
                ForEach(linkedPaths, id: \.self) { (path: String) in
                    let exists = RepositoryDocumentStore.exists(repositoryPath: work.githubLocalPath, relativePath: path)
                    FacetDetailResourceRow(
                        title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                        subtitle: exists ? path : L10n.pick("Missing · \(path)", "文件缺失 · \(path)"),
                        systemImage: exists ? "doc.text" : "exclamationmark.triangle",
                        tint: exists ? .blue : .orange
                    ) {
                        if exists, let url = try? RepositoryDocumentStore.url(
                            repositoryPath: work.githubLocalPath,
                            relativePath: path
                        ) {
                            FacetDetailRowAction(
                                systemImage: "arrow.up.right",
                                help: L10n.pick("Open Document", "打开文档"),
                                tint: .blue
                            ) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        FacetDetailRowAction(
                            systemImage: "xmark",
                            help: L10n.pick("Unlink Document", "取消文档关联")
                        ) {
                            updateDocumentPaths(documentPaths.filter { $0 != path })
                        }
                    }
                }
            }
        )
    }

    // MARK: - Literature section

    private var linkedPapersSection: some View {
        FacetResourceGroup(
            title: L10n.pick("Literature", "文献"),
            count: paperIDs.count,
            systemImage: "books.vertical",
            tint: .yellow,
            emptyText: L10n.pick("No linked literature.", "暂无关联文献。"),
            action: {
                FacetDetailRowAction(
                    systemImage: "plus",
                    help: L10n.pick("Attach Literature", "关联文献"),
                    tint: .yellow
                ) {
                    showingPaperPicker.toggle()
                }
                .popover(isPresented: $showingPaperPicker) { paperPicker }
            },
            content: {
                ForEach(paperIDs, id: \.self) { paperID in
                    paperResourceRow(paperID: paperID) {
                        updatePaperIDs(paperIDs.filter { $0 != paperID })
                    }
                }
            }
        )
    }

    private var paperPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L10n.pick("Search literature", "搜索文献"), text: $paperSearchText)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(availablePapers.prefix(80), id: \.id) { paper in
                        Button {
                            updatePaperIDs(paperIDs + [paper.id])
                            showingPaperPicker = false
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(paper.title).lineLimit(2)
                                Text(paper.authors.prefix(2).joined(separator: ", "))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .background(FacetTheme.quietPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 320, height: 340)
    }

    private var availablePapers: [Paper] {
        let query = paperSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return paperStore.papers.filter { paper in
            !paperIDs.contains(paper.id)
                && (query.isEmpty || paper.searchText.contains(query))
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


        return FacetDetailResourceRow(
            title: paper?.title ?? paperID,
            subtitle: subtitle,
            systemImage: "books.vertical.fill",
            tint: .yellow
        ) {
            FacetDetailRowAction(
                systemImage: "arrow.up.right",
                help: L10n.pick("View in Library", "在文献库中查看"),
                tint: .yellow
            ) {
                NotificationCenter.default.post(
                    name: .navigateToPaper,
                    object: nil,
                    userInfo: ["paperID": paperID]
                )
            }
            FacetDetailRowAction(
                systemImage: "xmark",
                help: L10n.pick("Unlink paper", "取消文献关联")
            ) {
                onRemove()
            }
            .disabled(saving)
        }
    }

    // MARK: - Commits section

    private var linkedCommitsSection: some View {
        FacetResourceGroup(
            title: L10n.pick("Commits", "提交"),
            count: commits.count,
            systemImage: "curlybraces",
            tint: .purple,
            emptyText: L10n.pick("No linked commits.", "暂无关联提交。"),
            action: {
                FacetDetailRowAction(
                    systemImage: "plus",
                    help: L10n.pick("Attach Commit", "关联提交"),
                    tint: .purple
                ) {
                    showingCommitPicker.toggle()
                }
                .disabled(work.githubLocalPath?.isEmpty != false)
                .popover(isPresented: $showingCommitPicker) { commitPicker }
            },
            content: {
                ForEach(commits, id: \.self) { commit in
                    commitResourceRow(commitString: commit) {
                        updateCommits(commits.filter { $0 != commit })
                    }
                }
            }
        )
    }

    private var commitPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L10n.pick("Search commits", "搜索提交"), text: $commitSearchText)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(availableCommits.prefix(80)) { commit in
                        Button {
                            let repo = work.githubRepo ?? "local"
                            updateCommits(commits + ["\(repo)@\(commit.id)"])
                            showingCommitPicker = false
                        } label: {
                            HStack(spacing: 8) {
                                Text(commit.shortSHA)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(commit.summary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .background(FacetTheme.quietPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 340, height: 340)
    }

    private var availableCommits: [LocalGitCommit] {
        let query = commitSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return commitCandidates.filter { commit in
            let repo = work.githubRepo ?? "local"
            return !commits.contains("\(repo)@\(commit.id)")
                && (query.isEmpty
                    || commit.summary.lowercased().contains(query)
                    || commit.id.lowercased().contains(query)
                    || commit.authorName.lowercased().contains(query))
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
        
        return FacetDetailResourceRow(
            title: titleText,
            subtitle: subtitleText,
            systemImage: "curlybraces",
            tint: .purple,
            titleDesign: .monospaced
        ) {
            if let url = parsed?.url {
                FacetDetailRowAction(
                    systemImage: "arrow.up.right",
                    help: L10n.pick("Open in browser", "在浏览器中打开"),
                    tint: .purple
                ) {
                    NSWorkspace.shared.open(url)
                }
            }
            FacetDetailRowAction(
                systemImage: "xmark",
                help: L10n.pick("Unlink", "取消关联")
            ) {
                onRemove()
            }
            .disabled(saving)
        }
    }

    private var detailsCard: some View {
        FacetDetailSection(title: L10n.pick("Details", "说明"), systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if details.isEmpty {
                        Text(L10n.pick("Add details here...", "在此添加说明…"))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $details)
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
        .padding(.vertical, 8)
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
        itemReference = item.facetItemReference()
        let stableID = item.facetID ?? itemReference.itemID
        documentPaths = itemStore.documentPaths(for: stableID)
        paperIDs = itemStore.paperIDs(for: stableID)
        commits = itemStore.commits(for: stableID)
        if let repo = LocalGitRepository.inspect(path: work.githubLocalPath ?? "") {
            Task { commitCandidates = await LocalGitRepository.gitLog(rootPath: repo.rootPath) }
        } else {
            commitCandidates = []
        }
        details = itemStore.body(for: stableID)
        savedDetailsSignature = details
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

    private func scheduleDetailsAutosave() {
        guard !loadingFields else { return }
        detailsAutoSaveTask?.cancel()
        guard details != savedDetailsSignature else { return }

        detailsAutoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveLocalDetailsIfNeeded()
            }
        }
    }

    private func saveLocalDetailsIfNeeded() {
        guard details != savedDetailsSignature else { return }
        let stableID = item.facetID ?? itemReference.itemID
        itemStore.save(id: stableID, body: details)
        savedDetailsSignature = details
        if item.facetID == nil {
            Task {
                _ = await ek.rewriteItemReference(id: item.id, reference: FacetItemReference(itemID: stableID))
                onUpdate(item.id)
            }
        }
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
            let ok = await ek.updateItem(
                id: item.id,
                work: work.prefix,
                content: text,
                date: shouldUseDate ? date : nil,
                useDate: shouldUseDate,
                dateIncludesTime: kind == .reminder && reminderHasTime,
                containerName: targetContainer,
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

    private func updatePaperIDs(_ values: [String]) {
        let stableID = item.facetID ?? itemReference.itemID
        itemStore.setPaperIDs(values, for: stableID)
        paperIDs = values
        persistReferenceIfNeeded(stableID)
    }

    private func updateCommits(_ values: [String]) {
        let stableID = item.facetID ?? itemReference.itemID
        itemStore.setCommits(values, for: stableID)
        commits = values
        persistReferenceIfNeeded(stableID)
    }

    private func persistReferenceIfNeeded(_ stableID: String) {
        guard item.facetID == nil else {
            onUpdate(item.id)
            return
        }
        Task {
            let ok = await ek.rewriteItemReference(id: item.id, reference: FacetItemReference(itemID: stableID))
            if ok { onUpdate(item.id) }
            else { toast.show(L10n.pick("Failed to update links", "更新关联失败"), type: .error) }
        }
    }

    private func updateDocumentPaths(_ paths: [String]) {
        let stableID = item.facetID ?? itemReference.itemID
        let normalized = Array(Set(paths.filter(RepositoryDocumentStore.isValid(relativePath:)))).sorted()
        itemStore.setDocumentPaths(normalized, for: stableID)
        documentPaths = normalized
        if item.facetID == nil {
            Task {
                let ok = await ek.rewriteItemReference(id: item.id, reference: FacetItemReference(itemID: stableID))
                if ok { onUpdate(item.id) }
            }
        } else {
            onUpdate(item.id)
        }
    }

    private func deleteItem() {
        saving = true
        Task {
            let ok = await ek.deleteItem(id: item.id)
            saving = false
            if ok {
                itemStore.deleteLocalState(for: item.facetID ?? item.id)
                onUpdate(nil)
                onClose()
            } else {
                toast.show(L10n.pick("Failed to delete item", "删除条目失败"), type: .error)
            }
        }
    }

    private func convertItem(to newKind: WorkItem.Kind) {
        guard item.linkedPaperIDs.isEmpty else { return }
        guard newKind != item.kind else { return }
        saving = true
        onReplacementStart()
        saveLocalDetailsIfNeeded()
        Task {
            let newId: String?
            if item.kind == .reminder {
                let calName = work.calendarName ?? ""
                newId = await ek.convertReminderToEvent(
                    reminderId: item.id,
                    work: work.prefix,
                    content: item.content,
                    tags: item.tags,
                    itemReference: itemReference,
                    dueDate: item.date,
                    durationMinutes: settings.defaultEventDurationMinutes,
                    calendarName: calName.isEmpty ? settings.defaultCalendarName : calName,
                    enabledCalendars: settings.effectiveCalendarNames
                )
            } else {
                let listName = work.reminderListName ?? ""
                newId = await ek.convertEventToReminder(
                    eventId: item.id,
                    work: work.prefix,
                    content: item.content,
                    tags: item.tags,
                    itemReference: itemReference,
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
