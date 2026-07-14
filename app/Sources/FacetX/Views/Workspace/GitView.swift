import AppKit
import FacetXCore
import SwiftUI

struct GitView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var toast: ToastController

    let project: Project
    let items: [ProjectItem]
    let searchText: String
    let refreshTrigger: Int
    let onItemsChanged: () async -> Void

    private enum WorkspaceSection: String, CaseIterable, Identifiable {
        case changes
        case history

        var id: String { rawValue }
    }

    @State private var section: WorkspaceSection = .changes
    @State private var repoInfo: LocalGitRepositoryInfo?
    @State private var branchState = LocalGitBranchState(
        current: nil,
        upstream: nil,
        ahead: 0,
        behind: 0,
        localBranches: []
    )
    @State private var commits: [LocalGitCommit] = []
    @State private var statusEntries: [LocalGitStatusEntry] = []
    @State private var selectedChangeID: String?
    @State private var selectedCommitID: String?
    @State private var diffText = ""
    @State private var isLoadingRepository = false
    @State private var isLoadingDiff = false
    @State private var isPerformingOperation = false
    @State private var operationMessage: String?
    @State private var operationFailed = false

    @State private var commitTitle = ""
    @State private var commitBody = ""
    @State private var pendingCommitItemIDs: Set<String> = []
    @State private var showingPendingItems = false
    @State private var showingCommitLinks = false
    @State private var attachmentVersion = 0
    @State private var showingBranchSheet = false

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var repoPath: String? {
        guard let path = project.githubLocalPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return path
    }

    private var repoURL: URL? {
        repoPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
    }

    private var rootPath: String? { repoInfo?.rootPath }

    private var repoKey: String? {
        repoInfo?.fullName ?? project.githubRepo ?? repoURL?.lastPathComponent
    }

    private var filteredStatusEntries: [LocalGitStatusEntry] {
        guard !query.isEmpty else { return statusEntries }
        return statusEntries.filter { $0.path.lowercased().contains(query) }
    }

    private var stagedEntries: [LocalGitStatusEntry] {
        filteredStatusEntries.filter { $0.area == .staged }
    }

    private var unstagedEntries: [LocalGitStatusEntry] {
        filteredStatusEntries.filter { $0.area == .unstaged }
    }

    private var filteredCommits: [LocalGitCommit] {
        guard !query.isEmpty else { return commits }
        return commits.filter {
            $0.message.lowercased().contains(query)
                || $0.authorName.lowercased().contains(query)
                || $0.id.lowercased().contains(query)
        }
    }

    private var selectedChange: LocalGitStatusEntry? {
        statusEntries.first { $0.id == selectedChangeID }
    }

    private var selectedCommit: LocalGitCommit? {
        commits.first { $0.id == selectedCommitID }
    }

    private var workItems: [ProjectItem] {
        items.filter { $0.kind == .reminder || $0.kind == .event }
    }

    var body: some View {
        Group {
            if repoURL == nil {
                noRepoState
            } else {
                gitWorkspace
            }
        }
        .background(FacetTheme.canvas)
        .task(id: project.id) { await refreshRepository() }
        .onChange(of: project.githubLocalPath) { Task { await refreshRepository() } }
        .onChange(of: refreshTrigger) { Task { await refreshRepository() } }
        .onChange(of: section) {
            Task {
                if section == .changes { await loadChangeDiff() }
                else { await loadCommitDiff() }
            }
        }
        .sheet(isPresented: $showingBranchSheet) {
            BranchNameSheet(
                onCancel: { showingBranchSheet = false },
                onCreate: { name in createBranch(name) }
            )
        }
    }

    private var gitWorkspace: some View {
        VStack(spacing: 0) {
            repositoryHeader
            Divider()
            sectionBar
            Divider()
            Group {
                switch section {
                case .changes: changesWorkspace
                case .history: historyWorkspace
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Repository header

    private var repositoryHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: statusEntries.isEmpty ? "checkmark.seal.fill" : "arrow.triangle.branch")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(statusEntries.isEmpty ? Color.green : Color.orange)
                .frame(width: 38, height: 38)
                .background((statusEntries.isEmpty ? Color.green : Color.orange).opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(repoInfo?.fullName ?? repoURL?.lastPathComponent ?? project.name)
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 6) {
                    Text(statusEntries.isEmpty
                         ? L10n.pick("Working tree clean", "工作区干净")
                         : L10n.pick("\(statusEntries.count) changes", "\(statusEntries.count) 项变更"))
                    if let upstream = branchState.upstream {
                        Text("·")
                        Text(upstream)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            branchMenu

            if branchState.ahead > 0 {
                syncBadge(icon: "arrow.up", value: branchState.ahead, tint: .blue,
                          help: L10n.pick("Commits ahead of upstream", "领先上游的提交"))
            }
            if branchState.behind > 0 {
                syncBadge(icon: "arrow.down", value: branchState.behind, tint: .orange,
                          help: L10n.pick("Commits behind upstream", "落后上游的提交"))
            }

            Spacer()

            if let operationMessage {
                Label(operationMessage, systemImage: operationFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(operationFailed ? Color.red : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 220)
            }

            if isPerformingOperation {
                ProgressView().controlSize(.small)
            }

            headerButton("arrow.triangle.2.circlepath", help: L10n.pick("Fetch", "获取")) { fetch() }
            headerButton("arrow.down.circle", help: L10n.pick("Pull (fast-forward only)", "拉取（仅快进）"),
                         disabled: !statusEntries.isEmpty || branchState.upstream == nil) { pull() }
            headerButton("arrow.up.circle", help: L10n.pick("Push", "推送")) { push() }
            headerButton("arrow.up.forward.app", help: L10n.pick("Open Repository", "打开仓库")) {
                if let repoURL { NSWorkspace.shared.open(repoURL) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(FacetTheme.panel)
    }

    private var branchMenu: some View {
        Menu {
            ForEach(branchState.localBranches, id: \.self) { branch in
                Button {
                    switchBranch(branch)
                } label: {
                    HStack {
                        Text(branch)
                        if branch == branchState.current { Image(systemName: "checkmark") }
                    }
                }
                .disabled(branch == branchState.current || !statusEntries.isEmpty)
            }
            Divider()
            Button(L10n.pick("New Branch…", "新建分支…")) { showingBranchSheet = true }
                .disabled(!statusEntries.isEmpty)
        } label: {
            Label(branchState.current ?? L10n.pick("Detached", "游离状态"), systemImage: "arrow.triangle.branch")
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: FacetTheme.chipHeight)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(statusEntries.isEmpty
              ? L10n.pick("Switch branch", "切换分支")
              : L10n.pick("Commit or remove changes before switching", "切换分支前请先提交或处理变更"))
    }

    private func syncBadge(icon: String, value: Int, tint: Color, help: String) -> some View {
        Label("\(value)", systemImage: icon)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
            .help(help)
    }

    private func headerButton(_ systemImage: String,
                              help: String,
                              disabled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: FacetTheme.chipHeight, height: FacetTheme.chipHeight)
                .contentShape(Rectangle())
                .facetHoverSurface(tint: .secondary,
                                   fill: Color.primary.opacity(0.04),
                                   hoverFill: Color.primary.opacity(0.07),
                                   hoverStroke: FacetTheme.hairline)
        }
        .buttonStyle(.plain)
        .disabled(disabled || isPerformingOperation)
        .help(help)
    }

    private var sectionBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $section) {
                Text(L10n.pick("Changes \(statusEntries.count)", "变更 \(statusEntries.count)"))
                    .tag(WorkspaceSection.changes)
                Text(L10n.pick("History", "历史"))
                    .tag(WorkspaceSection.history)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .fixedSize()

            if !query.isEmpty {
                Label(L10n.pick("Filtering results", "正在筛选结果"), systemImage: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            Spacer()

            Button {
                Task { await refreshRepository() }
            } label: {
                Label(L10n.pick("Refresh", "刷新"), systemImage: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(isLoadingRepository)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(FacetTheme.quietPanel)
    }

    // MARK: - Changes

    private var changesWorkspace: some View {
        HSplitView {
            VStack(spacing: 0) {
                changesList
                Divider()
                commitComposer
            }
            .frame(minWidth: 250, idealWidth: 290, maxWidth: 350, maxHeight: .infinity)
            .background(FacetTheme.quietPanel)

            diffPane(
                title: selectedChange?.path ?? L10n.pick("Working Changes", "工作区变更"),
                subtitle: selectedChange.map(changeSubtitle)
            )
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            changeInspector
                .frame(minWidth: 205, idealWidth: 225, maxWidth: 250, maxHeight: .infinity)
                .background(FacetTheme.quietPanel)
        }
    }

    private var changesList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.pick("Working Tree", "工作区"))
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                if !unstagedEntries.isEmpty {
                    Button(L10n.pick("Stage All", "全部暂存")) { stageAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                } else if !stagedEntries.isEmpty {
                    Button(L10n.pick("Unstage All", "全部取消暂存")) { unstageAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            Divider()

            if isLoadingRepository && statusEntries.isEmpty {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredStatusEntries.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? L10n.pick("Clean Working Tree", "工作区干净") : L10n.pick("No Matching Changes", "没有匹配的变更"),
                    systemImage: query.isEmpty ? "checkmark.seal" : "magnifyingglass",
                    description: Text(query.isEmpty
                                      ? L10n.pick("There is nothing to commit.", "当前没有需要提交的内容。")
                                      : L10n.pick("Try another search.", "请尝试其他搜索词。"))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if !stagedEntries.isEmpty {
                            changeGroup(L10n.pick("Staged", "已暂存"), entries: stagedEntries, tint: .green)
                        }
                        if !unstagedEntries.isEmpty {
                            changeGroup(L10n.pick("Changes", "未暂存"), entries: unstagedEntries, tint: .orange)
                        }
                    }
                }
                .thinScrollIndicators()
            }
        }
    }

    private func changeGroup(_ title: String,
                             entries: [LocalGitStatusEntry],
                             tint: Color) -> some View {
        Section {
            ForEach(entries) { entry in changeRow(entry) }
        } header: {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(title)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(entries.count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(.ultraThinMaterial)
        }
    }

    private func changeRow(_ entry: LocalGitStatusEntry) -> some View {
        let selected = selectedChangeID == entry.id
        return HStack(spacing: 4) {
            Button {
                selectChange(entry)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: entry.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(stateColor(entry.state))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(URL(fileURLWithPath: entry.path).lastPathComponent)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        let parent = (entry.path as NSString).deletingLastPathComponent
                        if parent != "." && !parent.isEmpty {
                            Text(parent)
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                toggleStage(entry)
            } label: {
                Image(systemName: entry.area == .staged ? "minus.circle" : "plus.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.area == .staged ? Color.orange : .green)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(entry.area == .staged ? L10n.pick("Unstage", "取消暂存") : L10n.pick("Stage", "暂存"))
            .disabled(isPerformingOperation || entry.state == .conflicted)
        }
        .padding(.trailing, 6)
        .background(selected ? FacetTheme.softAccent : .clear)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(Color.accentColor).frame(width: 2) }
        }
    }

    private var commitComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L10n.pick("Commit", "提交"), systemImage: "checkmark.circle")
                    .font(.system(size: 10.5, weight: .bold))
                Spacer()
                Text(L10n.pick("\(stagedEntries.count) staged", "已暂存 \(stagedEntries.count)"))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(stagedEntries.isEmpty ? Color.secondary.opacity(0.6) : Color.green)
            }

            TextField(L10n.pick("Commit title", "提交标题"), text: $commitTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))

            TextEditor(text: $commitBody)
                .font(.system(size: 10.5))
                .scrollContentBackground(.hidden)
                .padding(5)
                .frame(height: 54)
                .background(Color.primary.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1))

            HStack(spacing: 8) {
                Button {
                    showingPendingItems = true
                } label: {
                    Label(pendingCommitItemIDs.isEmpty
                          ? L10n.pick("Link Work Item", "关联工作项")
                          : L10n.pick("\(pendingCommitItemIDs.count) linked", "已关联 \(pendingCommitItemIDs.count) 项"),
                          systemImage: "link")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(pendingCommitItemIDs.isEmpty ? .secondary : Color.accentColor)
                .popover(isPresented: $showingPendingItems, arrowEdge: .bottom) {
                    pendingItemsPopover
                }

                Spacer()

                Button {
                    createCommit()
                } label: {
                    Label(L10n.pick("Commit", "提交"), systemImage: "checkmark")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(stagedEntries.isEmpty
                          || commitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || isPerformingOperation)
            }
        }
        .padding(12)
        .background(FacetTheme.panel)
    }

    private var changeInspector: some View {
        ScrollView {
            if let entry = selectedChange {
                VStack(alignment: .leading, spacing: 18) {
                    inspectorHeader(L10n.pick("Change", "变更"), systemImage: "doc.text.magnifyingglass")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.path)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                        if let original = entry.originalPath {
                            Label(original, systemImage: "arrow.turn.up.right")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        metadataRow(L10n.pick("State", "状态"), value: stateName(entry.state))
                        metadataRow(L10n.pick("Area", "区域"), value: entry.area == .staged
                                    ? L10n.pick("Staged", "已暂存")
                                    : L10n.pick("Working tree", "工作区"))
                    }

                    inspectorHeader(L10n.pick("Diff Summary", "差异摘要"), systemImage: "plus.forwardslash.minus")
                    HStack(spacing: 12) {
                        diffMetric("+\(additionCount)", tint: .green)
                        diffMetric("−\(deletionCount)", tint: .red)
                    }

                    Button {
                        reveal(entry.path)
                    } label: {
                        Label(L10n.pick("Reveal in Finder", "在 Finder 中显示"), systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        toggleStage(entry)
                    } label: {
                        Label(entry.area == .staged ? L10n.pick("Unstage", "取消暂存") : L10n.pick("Stage", "暂存"),
                              systemImage: entry.area == .staged ? "minus.circle" : "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(entry.state == .conflicted || isPerformingOperation)
                }
                .padding(14)
            } else {
                ContentUnavailableView(
                    L10n.pick("Select a Change", "选择变更"),
                    systemImage: "cursorarrow.click",
                    description: Text(L10n.pick("Inspect and stage files from here.", "在这里检查并暂存文件。"))
                )
            }
        }
        .thinScrollIndicators()
    }

    // MARK: - History

    private var historyWorkspace: some View {
        HSplitView {
            historyList
                .frame(minWidth: 270, idealWidth: 310, maxWidth: 370, maxHeight: .infinity)
                .background(FacetTheme.quietPanel)

            diffPane(
                title: selectedCommit?.summary ?? L10n.pick("Commit Diff", "提交差异"),
                subtitle: selectedCommit.map { "\($0.shortSHA) · \(relativeDate($0.date))" }
            )
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            commitInspector
                .frame(minWidth: 215, idealWidth: 235, maxWidth: 270, maxHeight: .infinity)
                .background(FacetTheme.quietPanel)
        }
    }

    private var historyList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.pick("Commit History", "提交历史"))
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Text("\(filteredCommits.count)")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.purple)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            Divider()

            if isLoadingRepository && commits.isEmpty {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredCommits.isEmpty {
                ContentUnavailableView(
                    L10n.pick("No Commits", "暂无提交"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(L10n.pick("No commits match the current filter.", "没有提交符合当前筛选。"))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCommits) { commit in
                            historyRow(commit)
                        }
                    }
                }
                .thinScrollIndicators()
            }
        }
    }

    private func historyRow(_ commit: LocalGitCommit) -> some View {
        let selected = selectedCommitID == commit.id
        let linked = linkedItems(for: commit)
        return Button {
            selectCommit(commit)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                VStack(spacing: 0) {
                    Circle()
                        .fill(commit.refs.isEmpty ? Color.purple.opacity(0.45) : Color.purple)
                        .frame(width: 7, height: 7)
                    Rectangle().fill(Color.purple.opacity(0.14)).frame(width: 1, height: 36)
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(commit.summary)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        Text(commit.shortSHA)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.purple)
                        Text(commit.authorName)
                        Text("·")
                        Text(relativeDate(commit.date))
                        if !linked.isEmpty {
                            Image(systemName: "link")
                                .foregroundStyle(Color.accentColor)
                            Text("\(linked.count)")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? FacetTheme.softAccent : .clear)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(Color.accentColor).frame(width: 2) }
        }
    }

    private var commitInspector: some View {
        ScrollView {
            if let commit = selectedCommit {
                VStack(alignment: .leading, spacing: 18) {
                    inspectorHeader(L10n.pick("Commit", "提交"), systemImage: "point.3.connected.trianglepath.dotted")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(commit.summary)
                            .font(.system(size: 12, weight: .semibold))
                            .textSelection(.enabled)
                        if let body = commit.body {
                            Text(body)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        metadataRow("SHA", value: commit.shortSHA)
                        metadataRow(L10n.pick("Author", "作者"), value: commit.authorName)
                        metadataRow(L10n.pick("Date", "日期"), value: relativeDate(commit.date))
                    }

                    inspectorHeader(L10n.pick("Linked Work Items", "关联工作项"), systemImage: "link")
                    let linked = linkedItems(for: commit)
                    if linked.isEmpty {
                        Text(L10n.pick("No work items attached.", "尚未关联工作项。"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    } else {
                        VStack(spacing: 5) {
                            ForEach(linked) { item in
                                Button {
                                    NotificationCenter.default.post(
                                        name: .selectItemInProjectDetail,
                                        object: nil,
                                        userInfo: ["itemID": item.id]
                                    )
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: item.kind.systemImage)
                                            .foregroundStyle(item.kind.color)
                                        Text(item.content).lineLimit(2)
                                        Spacer(minLength: 0)
                                    }
                                    .font(.system(size: 10.5, weight: .medium))
                                    .padding(8)
                                    .background(Color.primary.opacity(0.035))
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        showingCommitLinks = true
                    } label: {
                        Label(L10n.pick("Attach Work Items", "关联工作项"), systemImage: "paperclip")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .popover(isPresented: $showingCommitLinks, arrowEdge: .bottom) {
                        commitLinksPopover(commit)
                    }

                    Button {
                        createTodo(from: commit)
                    } label: {
                        Label(L10n.pick("Create Todo and Attach", "创建 Todo 并关联"), systemImage: "checkmark.circle.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let url = commit.htmlURL(repoFullName: repoInfo?.fullName ?? project.githubRepo) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label(L10n.pick("View on GitHub", "在 GitHub 查看"), systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(14)
                .id(attachmentVersion)
            } else {
                ContentUnavailableView(
                    L10n.pick("Select a Commit", "选择提交"),
                    systemImage: "cursorarrow.click",
                    description: Text(L10n.pick("Inspect its diff and linked work items.", "检查其差异和关联工作项。"))
                )
            }
        }
        .thinScrollIndicators()
    }

    // MARK: - Shared panes and popovers

    private func diffPane(title: String, subtitle: String?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "plus.forwardslash.minus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text("·")
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if !diffText.isEmpty {
                    Text(L10n.pick("+\(additionCount) −\(deletionCount)", "+\(additionCount) −\(deletionCount)"))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(FacetTheme.panel)
            Divider()
            GitDiffView(text: diffText, isLoading: isLoadingDiff)
        }
    }

    private var pendingItemsPopover: some View {
        workItemPicker(
            title: L10n.pick("Attach New Commit", "关联新提交"),
            isSelected: { item in item.facetID.map { pendingCommitItemIDs.contains($0) } ?? false },
            toggle: { item in
                guard let id = item.facetID else { return }
                if pendingCommitItemIDs.contains(id) { pendingCommitItemIDs.remove(id) }
                else { pendingCommitItemIDs.insert(id) }
            }
        )
    }

    private func commitLinksPopover(_ commit: LocalGitCommit) -> some View {
        let reference = commitReference(commit)
        return workItemPicker(
            title: L10n.pick("Attach Commit", "关联提交"),
            isSelected: { item in
                guard let id = item.facetID, let reference else { return false }
                return ItemStore.shared.commits(for: id).contains(reference)
            },
            toggle: { item in
                guard let id = item.facetID, let reference else { return }
                var values = ItemStore.shared.commits(for: id)
                if values.contains(reference) { values.removeAll { $0 == reference } }
                else { values.append(reference) }
                ItemStore.shared.setCommits(values, for: id)
                attachmentVersion += 1
                Task { await onItemsChanged() }
            }
        )
    }

    private func workItemPicker(title: String,
                                isSelected: @escaping (ProjectItem) -> Bool,
                                toggle: @escaping (ProjectItem) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            if workItems.isEmpty {
                Text(L10n.pick("No tasks or events in this project.", "该项目暂无任务或事件。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(workItems) { item in
                            Button { toggle(item) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: item.kind.systemImage)
                                        .foregroundStyle(item.kind.color)
                                    Text(item.content).lineLimit(1)
                                    Spacer()
                                    if isSelected(item) {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                                .font(.system(size: 11.5))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(width: 320, height: min(CGFloat(workItems.count) * 34 + 12, 280))
            }
        }
        .id(attachmentVersion)
    }

    private func inspectorHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.secondary)
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 10))
    }

    private func diffMetric(_ value: String, tint: Color) -> some View {
        Text(value)
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(tint.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var additionCount: Int {
        diffText.components(separatedBy: .newlines)
            .filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
    }

    private var deletionCount: Int {
        diffText.components(separatedBy: .newlines)
            .filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
    }

    // MARK: - Loading and operations

    @MainActor
    private func refreshRepository() async {
        repoInfo = repoPath.flatMap(LocalGitRepository.inspect(path:))
        guard let rootPath else {
            commits = []
            statusEntries = []
            diffText = ""
            return
        }
        isLoadingRepository = true
        async let history = LocalGitRepository.gitLog(rootPath: rootPath)
        async let status = LocalGitRepository.gitStatus(rootPath: rootPath)
        async let branches = LocalGitRepository.branchState(rootPath: rootPath)
        let (newCommits, newStatus, newBranchState) = await (history, status, branches)
        commits = newCommits
        statusEntries = newStatus
        branchState = newBranchState
        repoInfo = LocalGitRepository.inspect(path: rootPath)
        isLoadingRepository = false

        if selectedChangeID == nil || !newStatus.contains(where: { $0.id == selectedChangeID }) {
            selectedChangeID = newStatus.first?.id
        }
        if selectedCommitID == nil || !newCommits.contains(where: { $0.id == selectedCommitID }) {
            selectedCommitID = newCommits.first?.id
        }
        if section == .changes { await loadChangeDiff() }
        else { await loadCommitDiff() }
    }

    private func selectChange(_ entry: LocalGitStatusEntry) {
        selectedChangeID = entry.id
        Task { await loadChangeDiff() }
    }

    private func selectCommit(_ commit: LocalGitCommit) {
        selectedCommitID = commit.id
        Task { await loadCommitDiff() }
    }

    @MainActor
    private func loadChangeDiff() async {
        guard let rootPath, let entry = selectedChange else {
            diffText = ""
            return
        }
        let requestID = entry.id
        isLoadingDiff = true
        let value = await LocalGitRepository.diff(rootPath: rootPath, entry: entry)
        guard selectedChangeID == requestID else { return }
        diffText = value
        isLoadingDiff = false
    }

    @MainActor
    private func loadCommitDiff() async {
        guard let rootPath, let commit = selectedCommit else {
            diffText = ""
            return
        }
        let requestID = commit.id
        isLoadingDiff = true
        let value = await LocalGitRepository.commitDiff(rootPath: rootPath, commitID: commit.id)
        guard selectedCommitID == requestID else { return }
        diffText = value
        isLoadingDiff = false
    }

    private func toggleStage(_ entry: LocalGitStatusEntry) {
        guard let rootPath else { return }
        runOperation(entry.area == .staged ? L10n.pick("Unstaged", "已取消暂存") : L10n.pick("Staged", "已暂存")) {
            if entry.area == .staged {
                return await LocalGitRepository.unstage(rootPath: rootPath, path: entry.path)
            }
            return await LocalGitRepository.stage(rootPath: rootPath, path: entry.path)
        }
    }

    private func stageAll() {
        guard let rootPath else { return }
        runOperation(L10n.pick("All changes staged", "已暂存全部变更")) {
            await LocalGitRepository.stageAll(rootPath: rootPath)
        }
    }

    private func unstageAll() {
        guard let rootPath else { return }
        runOperation(L10n.pick("All changes unstaged", "已取消全部暂存")) {
            await LocalGitRepository.unstageAll(rootPath: rootPath)
        }
    }

    private func createCommit() {
        guard let rootPath else { return }
        let title = commitTitle
        let body = commitBody
        let linkedIDs = pendingCommitItemIDs
        isPerformingOperation = true
        Task {
            let result = await LocalGitRepository.commit(rootPath: rootPath, title: title, body: body)
            if result.succeeded {
                let latest = await LocalGitRepository.gitLog(rootPath: rootPath, limit: 1).first
                if let latest, let reference = commitReference(latest) {
                    for id in linkedIDs {
                        var values = ItemStore.shared.commits(for: id)
                        if !values.contains(reference) { values.append(reference) }
                        ItemStore.shared.setCommits(values, for: id)
                    }
                }
                await MainActor.run {
                    commitTitle = ""
                    commitBody = ""
                    pendingCommitItemIDs = []
                    operationMessage = L10n.pick("Commit created", "提交已创建")
                    operationFailed = false
                    toast.show(L10n.pick("Commit created", "提交已创建"), type: .success)
                }
                await onItemsChanged()
                await refreshRepository()
            } else {
                showOperationFailure(result)
            }
            await MainActor.run { isPerformingOperation = false }
        }
    }

    private func fetch() {
        guard let rootPath else { return }
        runOperation(L10n.pick("Fetched remote updates", "已获取远程更新")) {
            await LocalGitRepository.fetch(rootPath: rootPath)
        }
    }

    private func pull() {
        guard let rootPath else { return }
        runOperation(L10n.pick("Repository updated", "仓库已更新")) {
            await LocalGitRepository.pull(rootPath: rootPath)
        }
    }

    private func push() {
        guard let rootPath else { return }
        runOperation(L10n.pick("Changes pushed", "变更已推送")) {
            await LocalGitRepository.push(
                rootPath: rootPath,
                branch: branchState.current,
                hasUpstream: branchState.upstream != nil
            )
        }
    }

    private func switchBranch(_ branch: String) {
        guard let rootPath else { return }
        runOperation(L10n.pick("Switched to \(branch)", "已切换到 \(branch)")) {
            await LocalGitRepository.switchBranch(rootPath: rootPath, branch: branch)
        }
    }

    private func createBranch(_ name: String) {
        guard let rootPath else { return }
        showingBranchSheet = false
        runOperation(L10n.pick("Created branch \(name)", "已创建分支 \(name)")) {
            await LocalGitRepository.createBranch(rootPath: rootPath, branch: name)
        }
    }

    private func runOperation(_ successMessage: String,
                              operation: @escaping () async -> LocalGitCommandResult) {
        isPerformingOperation = true
        operationMessage = nil
        Task {
            let result = await operation()
            if result.succeeded {
                await MainActor.run {
                    operationMessage = successMessage
                    operationFailed = false
                    toast.show(successMessage, type: .success, duration: 1.8)
                }
                await refreshRepository()
            } else {
                showOperationFailure(result)
            }
            await MainActor.run { isPerformingOperation = false }
        }
    }

    @MainActor
    private func showOperationFailure(_ result: LocalGitCommandResult) {
        let message = result.message.isEmpty ? L10n.pick("Git operation failed", "Git 操作失败") : result.message
        operationMessage = message
        operationFailed = true
        toast.show(message, type: .error, duration: 4)
    }

    private func createTodo(from commit: LocalGitCommit) {
        guard let reference = commitReference(commit) else { return }
        let listName = settings.reminderSaveTarget(projectListName: project.reminderListName)
        guard !listName.isEmpty else {
            toast.show(L10n.pick("Choose a reminder list first", "请先选择提醒事项列表"), type: .warning)
            return
        }
        let stableID = UUID().uuidString
        Task {
            guard await ek.createReminder(
                project: project.prefix,
                content: L10n.pick("Follow up: \(commit.summary)", "跟进：\(commit.summary)"),
                listName: listName,
                dueDate: nil,
                dueIncludesTime: false,
                itemReference: FacetItemReference(itemID: stableID),
                enabledLists: settings.effectiveReminderListNames
            ) != nil else {
                toast.show(L10n.pick("Could not create Todo", "无法创建 Todo"), type: .error)
                return
            }
            ItemStore.shared.setCommits([reference], for: stableID)
            await onItemsChanged()
            toast.show(L10n.pick("Todo created and attached", "Todo 已创建并关联"), type: .success)
        }
    }

    private func commitReference(_ commit: LocalGitCommit) -> String? {
        guard let repoKey, !repoKey.isEmpty else { return nil }
        return "\(repoKey)@\(commit.id)"
    }

    private func linkedItems(for commit: LocalGitCommit) -> [ProjectItem] {
        guard let reference = commitReference(commit) else { return [] }
        return workItems.filter { item in
            item.facetID.map { ItemStore.shared.commits(for: $0).contains(reference) } ?? false
        }
    }

    private func reveal(_ relativePath: String) {
        guard let repoURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([repoURL.appendingPathComponent(relativePath)])
    }

    private func stateColor(_ state: LocalGitStatusEntry.State) -> Color {
        switch state {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .renamed: return .blue
        case .copied: return .teal
        case .untracked: return .secondary
        case .conflicted: return .red
        case .other: return .secondary
        }
    }

    private func stateName(_ state: LocalGitStatusEntry.State) -> String {
        switch state {
        case .modified: return L10n.pick("Modified", "已修改")
        case .added: return L10n.pick("Added", "已添加")
        case .deleted: return L10n.pick("Deleted", "已删除")
        case .renamed: return L10n.pick("Renamed", "已重命名")
        case .copied: return L10n.pick("Copied", "已复制")
        case .untracked: return L10n.pick("Untracked", "未跟踪")
        case .conflicted: return L10n.pick("Conflicted", "冲突")
        case .other: return L10n.pick("Changed", "已变更")
        }
    }

    private func changeSubtitle(_ entry: LocalGitStatusEntry) -> String {
        "\(stateName(entry.state)) · \(entry.area == .staged ? L10n.pick("Staged", "已暂存") : L10n.pick("Working tree", "工作区"))"
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var noRepoState: some View {
        ContentUnavailableView(
            L10n.pick("No Repository Bound", "未绑定仓库"),
            systemImage: "folder.badge.questionmark",
            description: Text(L10n.pick(
                "Select a local Git repository in project settings.",
                "请在项目编辑中选择一个本地 Git 仓库。"))
        )
    }
}

private struct BranchNameSheet: View {
    @State private var name = ""
    let onCancel: () -> Void
    let onCreate: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.pick("New Branch", "新建分支"), systemImage: "arrow.triangle.branch")
                .font(.system(size: 15, weight: .semibold))
            TextField(L10n.pick("Branch name", "分支名称"), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { create() }
            HStack {
                Spacer()
                Button(L10n.t(.cancel), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(L10n.pick("Create", "创建"), action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { focused = true }
    }

    private func create() {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onCreate(value)
    }
}
