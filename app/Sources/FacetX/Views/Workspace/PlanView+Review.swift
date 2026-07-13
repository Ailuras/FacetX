import AppKit
import FacetXCore
import SwiftUI

enum WeeklyReviewDocumentResult {
    case created
    case openedExisting
    case failed
}

extension PlanView {
    func carryOpenTasksToNextWeek(_ tasks: [ProjectItem]) async -> Int {
        let calendar = Calendar.current
        var moved = 0
        for item in tasks where item.facetKind == .task && !item.isCompleted {
            let base = item.date ?? week.startDate
            guard let nextDate = calendar.date(byAdding: .day, value: 7, to: base) else { continue }
            let newStart = ItemActionHelpers.startDate(for: item, toDay: nextDate, calendar: calendar)
            let success = await ek.updateItem(
                id: item.id,
                project: item.projectPrefix,
                content: item.content,
                date: newStart,
                useDate: true,
                dateIncludesTime: item.hasTime,
                containerName: item.containerName,
                tags: item.tags,
                priority: item.priority,
                url: item.url,
                updateURL: false,
                isAllDay: nil,
                endDate: nil
            )
            if success { moved += 1 }
        }
        await reload()
        return moved
    }

    func createWeeklyReviewDocument(_ body: String) async -> WeeklyReviewDocumentResult {
        let relativePath = ".facetx/review-\(week.id).md"
        do {
            let existed = RepositoryDocumentStore.exists(
                repositoryPath: project.githubLocalPath,
                relativePath: relativePath
            )
            if !existed {
                try RepositoryDocumentStore.save(
                    repositoryPath: project.githubLocalPath,
                    relativePath: relativePath,
                    body: body
                )
            }
            let url = try RepositoryDocumentStore.url(
                repositoryPath: project.githubLocalPath,
                relativePath: relativePath
            )
            NSWorkspace.shared.open(url)
            return existed ? .openedExisting : .created
        } catch {
            return .failed
        }
    }
}

struct PlanReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    let project: Project
    let week: ISOWeek
    let goal: WeekGoal?
    let items: [ProjectItem]
    let onCarryOpenTasks: ([ProjectItem]) async -> Int
    let onCreateWeeklyDocument: (String) async -> WeeklyReviewDocumentResult

    @State private var commits: [GitHubCommit] = []
    @State private var loadingCommits = false
    @State private var commitError: String?
    @State private var carrying = false
    @State private var creatingDocument = false
    @State private var statusMessage: String?

    private var completedTasks: [ProjectItem] {
        items.filter { $0.facetKind == .task && $0.isCompleted }
    }

    private var openTasks: [ProjectItem] {
        items.filter { $0.facetKind == .task && !$0.isCompleted }
    }

    private var overdueTasks: [ProjectItem] {
        openTasks.filter(\.isOverdue)
    }

    private var paperTitles: [String] {
        let ids = Set(items.flatMap(\.linkedPaperIDs))
        return PaperStore.shared.papers
            .filter { ids.contains($0.id) }
            .map(\.title)
            .sorted()
    }

    private var documentPaths: [String] {
        Array(Set(items.flatMap(\.linkedDocumentPaths))).sorted()
    }

    private var linkedCommitIDs: [String] {
        Array(Set(items.flatMap(\.linkedCommits))).sorted()
    }

    private var weekLoad: PlanDayLoad {
        PlanDayLoad.measure(
            items,
            eventDefaultMinutes: settings.defaultEventDurationMinutes,
            paperDefaultMinutes: settings.defaultPaperSessionMinutes,
            noteDefaultMinutes: settings.defaultNoteSessionMinutes
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    metrics
                    goalSection
                    taskSection
                    resourceSection
                    gitSection
                }
                .padding(16)
            }
            .thinScrollIndicators()
            Divider()
            footer
        }
        .frame(width: 560)
        .frame(minHeight: 560)
        .background(FacetTheme.canvas)
        .task(id: "\(project.githubRepo ?? "")-\(week.id)") {
            await loadCommits()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.pick("Weekly Review", "周回顾"))
                    .font(.system(size: 15, weight: .semibold))
                Text(weekRangeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(L10n.pick("Close", "关闭"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            reviewMetric(L10n.pick("Done", "完成"), value: completedTasks.count, systemImage: "checkmark.circle.fill", tint: .green)
            reviewMetric(L10n.pick("Open", "未完成"), value: openTasks.count, systemImage: "circle", tint: .orange)
            reviewMetric(L10n.pick("Late", "延期"), value: overdueTasks.count, systemImage: "clock.badge.exclamationmark", tint: .red)
            reviewMetric(L10n.pick("Hours", "时长"), value: weekLoad.hoursLabel, systemImage: "calendar.badge.clock", tint: weekLoad.level.color)
        }
    }

    private func reviewMetric(_ title: String, value: Int, systemImage: String, tint: Color) -> some View {
        reviewMetric(title, value: "\(value)", systemImage: systemImage, tint: tint)
    }

    private func reviewMetric(_ title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var goalSection: some View {
        reviewSection(title: L10n.pick("Goal", "目标"), systemImage: "target") {
            if let goal {
                Text(goal.title)
                    .font(.system(size: 13, weight: .semibold))
                if !goal.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(goal.body)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            } else {
                emptyLine(L10n.pick("No goal set for this week.", "本周还没有设置目标。"))
            }
        }
    }

    private var taskSection: some View {
        reviewSection(title: L10n.pick("Tasks", "任务"), systemImage: FacetKind.task.systemImage) {
            reviewList(title: L10n.pick("Completed", "已完成"), items: completedTasks, empty: L10n.pick("No completed tasks.", "暂无已完成任务。"))
            Divider().opacity(0.45)
            reviewList(title: L10n.pick("Still Open", "仍未完成"), items: openTasks, empty: L10n.pick("No open tasks.", "暂无未完成任务。"))
        }
    }

    private var resourceSection: some View {
        reviewSection(title: L10n.pick("Resources", "资源"), systemImage: "folder") {
            reviewTextList(title: L10n.pick("Literature", "文献"), values: paperTitles, empty: L10n.pick("No linked literature this week.", "本周没有关联文献。"))
            Divider().opacity(0.45)
            reviewTextList(title: L10n.pick("Documents", "文档"), values: documentPaths, empty: L10n.pick("No linked documents this week.", "本周没有关联文档。"))
            Divider().opacity(0.45)
            reviewTextList(title: L10n.pick("Attached Commits", "关联提交"), values: linkedCommitIDs, empty: L10n.pick("No attached commits this week.", "本周没有关联提交。"))
        }
    }

    private var gitSection: some View {
        reviewSection(title: L10n.pick("Git", "Git"), systemImage: "curlybraces") {
            if loadingCommits {
                ProgressView().controlSize(.small)
            } else if let commitError {
                emptyLine(commitError)
            } else if commits.isEmpty {
                emptyLine(project.githubRepo == nil
                          ? L10n.pick("No repository configured.", "尚未配置仓库。")
                          : L10n.pick("No commits this week.", "本周暂无提交。"))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(commits.prefix(8)) { commit in
                        HStack(spacing: 8) {
                            Text(commit.shortSHA)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(commit.summary)
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    if commits.count > 8 {
                        Text(L10n.pick("+ \(commits.count - 8) more", "另有 \(commits.count - 8) 次提交"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func reviewSection<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.86))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private func reviewList(title: String, items: [ProjectItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(title) · \(items.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if items.isEmpty {
                emptyLine(empty)
            } else {
                ForEach(items.prefix(6)) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.facetKind.systemImage)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(item.facetKind.color)
                        Text(item.content)
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                        Spacer()
                    }
                }
                if items.count > 6 {
                    Text(L10n.pick("+ \(items.count - 6) more", "另有 \(items.count - 6) 项"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func reviewTextList(title: String, values: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(title) · \(values.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if values.isEmpty {
                emptyLine(empty)
            } else {
                ForEach(values.prefix(6), id: \.self) { value in
                    Text("• \(value)")
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                }
                if values.count > 6 {
                    Text(L10n.pick("+ \(values.count - 6) more", "另有 \(values.count - 6) 项"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await carryOpenTasks() }
            } label: {
                Label(L10n.pick("Carry Open", "带到下周"), systemImage: "arrowshape.turn.up.right")
            }
            .controlSize(.small)
            .disabled(openTasks.isEmpty || carrying || creatingDocument)

            Button {
                Task { await createWeeklyDocument() }
            } label: {
                Label(L10n.pick("Create Review Document", "生成周记文档"), systemImage: "doc.text")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(creatingDocument || carrying || project.githubLocalPath == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func carryOpenTasks() async {
        carrying = true
        defer { carrying = false }
        let moved = await onCarryOpenTasks(openTasks)
        statusMessage = L10n.pick("Moved \(moved) tasks to next week.", "已将 \(moved) 个任务带到下周。")
    }

    private func createWeeklyDocument() async {
        creatingDocument = true
        defer { creatingDocument = false }
        switch await onCreateWeeklyDocument(markdownBody()) {
        case .created:
            statusMessage = L10n.pick("Review document created.", "周记文档已生成。")
        case .openedExisting:
            statusMessage = L10n.pick("Existing review document opened.", "已打开现有周记文档。")
        case .failed:
            statusMessage = L10n.pick("Could not create the review document.", "无法生成周记文档。")
        }
    }

    private func loadCommits() async {
        guard let repo = project.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines),
              !repo.isEmpty else {
            commits = []
            commitError = nil
            return
        }
        loadingCommits = true
        commitError = nil
        defer { loadingCommits = false }
        do {
            let token = settings.githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
            commits = try await GitHubService().fetchCommits(
                repo: repo,
                token: token.isEmpty ? nil : token,
                perPage: 100,
                since: week.startDate,
                until: week.endDate
            )
        } catch let error as GitHubService.APIError {
            commits = []
            commitError = error.message
        } catch let error as URLError {
            commits = []
            commitError = L10n.pick("Network error: \(error.localizedDescription)",
                                    "网络错误：\(error.localizedDescription)")
        } catch {
            commits = []
            commitError = error.localizedDescription
        }
    }

    private func markdownBody() -> String {
        """
        # \(L10n.pick("Weekly Review", "周回顾")) \(week.id)

        **\(L10n.pick("Project", "项目")):** \(project.name)
        **\(L10n.pick("Range", "范围")):** \(weekRangeLabel)

        ## \(L10n.pick("Goal", "目标"))
        \(goal.map { "- \($0.title)" } ?? L10n.pick("- No goal set.", "- 未设置目标。"))
        \(goalBodyMarkdown)

        ## \(L10n.pick("Completed", "已完成"))
        \(markdownItems(completedTasks, empty: L10n.pick("- No completed tasks.", "- 暂无已完成任务。")))

        ## \(L10n.pick("Still Open", "仍未完成"))
        \(markdownItems(openTasks, empty: L10n.pick("- No open tasks.", "- 暂无未完成任务。")))

        ## \(L10n.pick("Resources", "资源"))
        ### \(L10n.pick("Literature", "文献"))
        \(markdownValues(paperTitles, empty: L10n.pick("- No linked literature.", "- 无关联文献。")))

        ### \(L10n.pick("Documents", "文档"))
        \(markdownValues(documentPaths, empty: L10n.pick("- No linked documents.", "- 无关联文档。")))

        ### \(L10n.pick("Attached Commits", "关联提交"))
        \(markdownValues(linkedCommitIDs, empty: L10n.pick("- No attached commits.", "- 无关联提交。")))

        ## Git
        \(markdownCommits)
        """
    }

    private var goalBodyMarkdown: String {
        guard let body = goal?.body.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else {
            return ""
        }
        return "\n\(body)"
    }

    private func markdownItems(_ items: [ProjectItem], empty: String) -> String {
        guard !items.isEmpty else { return empty }
        return items.map { "- \($0.content)" }.joined(separator: "\n")
    }

    private func markdownValues(_ values: [String], empty: String) -> String {
        guard !values.isEmpty else { return empty }
        return values.map { "- \($0)" }.joined(separator: "\n")
    }

    private var markdownCommits: String {
        guard !commits.isEmpty else {
            return L10n.pick("- No commits.", "- 暂无提交。")
        }
        return commits.map { "- `\($0.shortSHA)` \($0.summary)" }.joined(separator: "\n")
    }

    private var weekRangeLabel: String {
        let end = Calendar(identifier: .iso8601).date(byAdding: .day, value: 6, to: week.startDate) ?? week.startDate
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: week.startDate)) - \(formatter.string(from: end))"
    }
}
