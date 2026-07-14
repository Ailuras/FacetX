import AppKit
import FacetXCore
import SwiftUI

/// Repository progress workspace for one FacetX project.
struct GitView: View {
    let project: Project
    let items: [ProjectItem]
    let searchText: String
    let refreshTrigger: Int

    @State private var repoInfo: LocalGitRepositoryInfo?
    @State private var commits: [LocalGitCommit] = []
    @State private var statusEntries: [LocalGitStatusEntry] = []
    @State private var isLoadingGit = false
    @State private var expandedCommitID: String?
    @State private var hoveredCommitID: String? = nil

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredStatusEntries: [LocalGitStatusEntry] {
        guard !query.isEmpty else { return statusEntries }
        return statusEntries.filter { $0.path.lowercased().contains(query) }
    }

    private var filteredCommits: [LocalGitCommit] {
        guard !query.isEmpty else { return commits }
        return commits.filter {
            $0.message.lowercased().contains(query)
                || $0.authorName.lowercased().contains(query)
                || $0.id.lowercased().contains(query)
        }
    }

    private var openItems: [ProjectItem] { items.filter { !$0.isCompleted } }
    private var completedItems: [ProjectItem] { items.filter(\.isCompleted) }

    private var repoPath: String? {
        guard let path = project.githubLocalPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return path
    }

    private var repoURL: URL? {
        repoPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
    }

    private var linkedItemsByCommit: [String: [ProjectItem]] {
        var result: [String: [ProjectItem]] = [:]
        let repoFullName = repoInfo?.fullName ?? project.githubRepo
        for item in items {
            for commitStr in item.linkedCommits {
                let parts = commitStr.split(separator: "@")
                guard parts.count == 2 else { continue }
                let commitRepo = String(parts[0])
                let sha = String(parts[1])
                if let repoFullName, !commitRepo.isEmpty, commitRepo != repoFullName {
                    continue
                }
                result[sha, default: []].append(item)
                let short = String(sha.prefix(7))
                if short != sha {
                    result[short, default: []].append(item)
                }
            }
        }
        return result
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
        .onAppear { reload() }
        .onChange(of: project.id) { reload() }
        .onChange(of: project.githubLocalPath) { reload() }
        .onChange(of: refreshTrigger) { reload() }
    }

    private var gitWorkspace: some View {
        VStack(spacing: 0) {
            repositoryHeader
            Divider()
            gitContent
        }
    }

    private var repositoryHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: statusEntries.isEmpty ? "checkmark.seal.fill" : "point.3.filled.connected.trianglepath.dotted")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(statusEntries.isEmpty ? Color.green : Color.orange)
                .frame(width: 42, height: 42)
                .background((statusEntries.isEmpty ? Color.green : Color.orange).opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(repoInfo?.fullName ?? repoURL?.lastPathComponent ?? project.name)
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 6) {
                    Label(repoInfo?.branch ?? L10n.pick("Detached", "游离状态"), systemImage: "arrow.triangle.branch")
                    Text("·")
                    Text(statusEntries.isEmpty
                         ? L10n.pick("Working tree clean", "工作区干净")
                         : L10n.pick("\(statusEntries.count) local changes", "\(statusEntries.count) 项本地变更"))
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }

            Spacer()

            summaryMetric(value: "\(openItems.count)", label: L10n.pick("Open", "未完成"), tint: .blue)
            summaryMetric(value: "\(completedItems.count)", label: L10n.pick("Done", "已完成"), tint: .green)
            summaryMetric(value: "\(commits.count)", label: L10n.pick("Commits", "提交"), tint: .purple)

            Button {
                if let repoURL { NSWorkspace.shared.open(repoURL) }
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: FacetTheme.chipHeight, height: FacetTheme.chipHeight)
                    .contentShape(Rectangle())
                    .facetHoverSurface(tint: .secondary,
                                       fill: Color.primary.opacity(0.04),
                                       hoverFill: Color.primary.opacity(0.07),
                                       hoverStroke: FacetTheme.hairline)
            }
            .buttonStyle(.plain)
            .help(L10n.pick("Open Repository", "打开仓库"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(FacetTheme.panel)
    }

    private func summaryMetric(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 48)
    }

    @ViewBuilder private var gitContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Working tree changes
                if !filteredStatusEntries.isEmpty {
                    Section {
                        VStack(spacing: 0) {
                            ForEach(filteredStatusEntries) { entry in
                                statusRow(entry)
                                if entry.id != filteredStatusEntries.last?.id {
                                    Divider().padding(.leading, 38)
                                }
                            }
                        }
                        .background(FacetTheme.quietPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    } header: {
                        sectionHeader(
                            icon: "circle.dotted",
                            title: L10n.pick("Working Changes", "工作区变更"),
                            count: filteredStatusEntries.count,
                            tint: statusEntries.contains { !$0.staged } ? .orange : .green
                        )
                    }
                }

                // Commit log
                Section {
                    if isLoadingGit {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    } else if filteredCommits.isEmpty {
                        Text(L10n.pick("No commits yet.", "暂无提交记录。"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(filteredCommits.indices, id: \.self) { index in
                                let commit = filteredCommits[index]
                                let isLast = index == filteredCommits.count - 1
                                commitRow(commit, isLast: isLast)
                                if !isLast {
                                    Divider().padding(.leading, 38)
                                }
                            }
                        }
                        .background(FacetTheme.quietPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                } header: {
                    sectionHeader(
                        icon: "clock.arrow.circlepath",
                        title: L10n.pick("Commit History", "提交历史"),
                        count: filteredCommits.count,
                        tint: .purple
                    )
                }
            }
        }
        .thinScrollIndicators()
    }

    private func sectionHeader(icon: String, title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(tint.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private func statusRow(_ entry: LocalGitStatusEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(stateColor(entry.state))
                .frame(width: 20)

            Text(entry.path)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Text(entry.staged
                 ? L10n.pick("Staged", "已暂存")
                 : L10n.pick("Unstaged", "未暂存"))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(entry.staged ? Color.green : .orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((entry.staged ? Color.green : Color.orange).opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func stateColor(_ state: LocalGitStatusEntry.State) -> Color {
        switch state {
        case .modified:   return .orange
        case .added:      return .green
        case .deleted:    return .red
        case .renamed:    return .blue
        case .copied:     return .teal
        case .untracked:  return .secondary
        case .conflicted: return .red
        case .other:      return .secondary
        }
    }

    private func commitRow(_ commit: LocalGitCommit, isLast: Bool) -> some View {
        let isExpanded = expandedCommitID == commit.id
        let isHovered = hoveredCommitID == commit.id
        let linked = linkedItemsByCommit[commit.id] ?? linkedItemsByCommit[commit.shortSHA] ?? []
        let repoFullName = repoInfo?.fullName ?? project.githubRepo

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    expandedCommitID = isExpanded ? nil : commit.id
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    // Timeline axis rendering
                    ZStack(alignment: .top) {
                        if !isLast {
                            Rectangle()
                                .fill(Color.purple.opacity(0.14))
                                .frame(width: 2)
                                .padding(.top, 14)
                                .padding(.bottom, -12) // Connects to the next item
                        }
                        
                        Circle()
                            .fill(commit.refs.isEmpty ? Color.purple.opacity(0.18) : Color.purple)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color.purple.opacity(0.35), lineWidth: 1.5)
                                    .frame(width: 14, height: 14)
                            )
                            .padding(.top, 4)
                    }
                    .frame(width: 14)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top, spacing: 6) {
                            Text(commit.summary)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(isExpanded ? 10 : 1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if !commit.refs.isEmpty {
                                ForEach(commit.refs.components(separatedBy: ", ").prefix(1), id: \.self) { ref in
                                    refBadge(ref)
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Text(commit.shortSHA)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.purple.opacity(0.8))
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(commit.authorName)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(relativeDate(commit.date))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)

                            if !linked.isEmpty {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Image(systemName: "link")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                Text("\(linked.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                hoveredCommitID = hovering ? commit.id : nil
            }

            // Expanded details block - rendered outside the Button wrapper
            // to allow copy and click events inside the panel
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let body = commit.body {
                        Text(body)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    if !linked.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L10n.pick("Linked Tasks", "关联任务"))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                            
                            ForEach(linked, id: \.id) { item in
                                HStack(spacing: 6) {
                                    Image(systemName: item.kind.systemImage)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(item.kind.color)
                                    Text(item.content)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.accentColor.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    if let url = commit.htmlURL(repoFullName: repoFullName) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label(L10n.pick("View on GitHub", "在 GitHub 查看"),
                                  systemImage: "arrow.up.right.square")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .hoverCursor(.pointingHand)
                    }
                }
                .padding(.leading, 38) // Offset to align under details, not tree line
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
        }
        .background(isExpanded ? Color.purple.opacity(0.03) : (isHovered ? Color.primary.opacity(0.02) : .clear))
    }

    private func refBadge(_ ref: String) -> some View {
        let isHEAD = ref.hasPrefix("HEAD")
        let isOrigin = ref.hasPrefix("origin/")
        let tint: Color = isHEAD ? .orange : (isOrigin ? .blue : .purple)
        return Text(ref)
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var noRepoState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L10n.pick("No Repository Bound", "未绑定仓库"))
                .font(.system(size: 14, weight: .semibold))
            Text(L10n.pick(
                "Please select a local Git repository in project settings.",
                "请在项目编辑中选择一个本地 Git 仓库路径。"))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func reload() {
        repoInfo = repoPath.flatMap(LocalGitRepository.inspect(path:))
        guard let rootPath = repoInfo?.rootPath else {
            commits = []; statusEntries = []; return
        }
        isLoadingGit = true
        Task {
            async let log = LocalGitRepository.gitLog(rootPath: rootPath)
            async let status = LocalGitRepository.gitStatus(rootPath: rootPath)
            let (c, s) = await (log, status)
            await MainActor.run {
                commits = c
                statusEntries = s
                isLoadingGit = false
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
