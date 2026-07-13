import FacetXCore
import SwiftUI

/// Git Sidebar Panel: displays the local git repository history and working changes
/// in a native side pane, replacing the Today panel when the git view is active.
struct GitSidebarPanel: View {
    @EnvironmentObject var ek: EventKitService
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var settings: AppSettings
    let project: Project
    @Binding var isPresented: Bool
    @Binding var isFullscreen: Bool

    @State private var repoInfo: LocalGitRepositoryInfo?
    @State private var commits: [LocalGitCommit] = []
    @State private var statusEntries: [LocalGitStatusEntry] = []
    @State private var isLoadingGit = false
    @State private var expandedCommitID: String?
    @State private var items: [ProjectItem] = []

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
        FacetSidebarPane(
            title: L10n.pick("Commit Tree", "代码历史"),
            systemImage: "point.3.connected.trianglepath.dotted",
            closeHelp: L10n.pick("Close panel", "关闭面板"),
            fillWidth: isFullscreen,
            onClose: { withAnimation(FacetTheme.detailSpring) { isPresented = false } },
            accessory: { fullscreenToggle }
        ) {
            if repoURL == nil {
                noRepoState
            } else {
                gitContent
            }
        }
        .onAppear { reload() }
        .onChange(of: project.id) { reload() }
        .onChange(of: project.githubLocalPath) { reload() }
        .onChange(of: ek.changeToken) { reload() }
    }

    private var fullscreenToggle: some View {
        Button {
            withAnimation(FacetTheme.detailSpring) { isFullscreen.toggle() }
        } label: {
            Image(systemName: isFullscreen
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .medium))
        }
        .help(isFullscreen ? L10n.pick("Exit fullscreen", "退出全屏")
                           : L10n.pick("Fullscreen", "全屏"))
    }

    @ViewBuilder private var gitContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Working tree changes
                if !statusEntries.isEmpty {
                    Section {
                        VStack(spacing: 0) {
                            ForEach(statusEntries) { entry in
                                statusRow(entry)
                                if entry.id != statusEntries.last?.id {
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
                            count: statusEntries.count,
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
                    } else if commits.isEmpty {
                        Text(L10n.pick("No commits yet.", "暂无提交记录。"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(commits) { commit in
                                commitRow(commit)
                                if commit.id != commits.last?.id {
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
                        count: commits.count,
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
        case .untracked:  return .secondary
        case .other:      return .secondary
        }
    }

    private func commitRow(_ commit: LocalGitCommit) -> some View {
        let isExpanded = expandedCommitID == commit.id
        let linked = linkedItemsByCommit[commit.id] ?? linkedItemsByCommit[commit.shortSHA] ?? []
        let repoFullName = repoInfo?.fullName ?? project.githubRepo

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    expandedCommitID = isExpanded ? nil : commit.id
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(Color.purple.opacity(0.30), lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                        if !commit.refs.isEmpty {
                            Circle()
                                .fill(Color.purple.opacity(0.65))
                                .frame(width: 8, height: 8)
                        } else {
                            Circle()
                                .fill(Color.purple.opacity(0.30))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(width: 20)
                    .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(commit.summary)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(isExpanded ? 10 : 1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if !commit.refs.isEmpty {
                                ForEach(commit.refs.components(separatedBy: ", ").prefix(2), id: \.self) { ref in
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

                        if isExpanded {
                            VStack(alignment: .leading, spacing: 8) {
                                if let body = commit.body {
                                    Text(body)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(Color.primary.opacity(0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }

                                if !linked.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(linked, id: \.id) { item in
                                            HStack(spacing: 6) {
                                                Image(systemName: item.facetKind.systemImage)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(item.facetKind.color)
                                                Text(item.content)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
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
                                }
                            }
                            .padding(.top, 6)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
        }
        .background(expandedCommitID == commit.id ? Color.purple.opacity(0.04) : Color.clear)
    }

    private func refBadge(_ ref: String) -> some View {
        let isHEAD = ref.hasPrefix("HEAD")
        let isOrigin = ref.hasPrefix("origin/")
        let tint: Color = isHEAD ? .orange : (isOrigin ? .blue : .purple)
        return Text(ref)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
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
            let prefixes = Set([project.prefix])
            let fetchedItems = await ek.items(
                forProjects: prefixes,
                enabledReminderLists: settings.effectiveReminderListNames,
                enabledCalendars: settings.effectiveCalendarNames,
                noteCalendarByProject: [:]
            )
            async let log = LocalGitRepository.gitLog(rootPath: rootPath)
            async let status = LocalGitRepository.gitStatus(rootPath: rootPath)
            let (c, s) = await (log, status)
            await MainActor.run {
                commits = c
                statusEntries = s
                items = fetchedItems
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
