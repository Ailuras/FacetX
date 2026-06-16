import SwiftUI

/// Displays recent GitHub commits for a project's configured repository.
struct CommitsView: View {
    @EnvironmentObject private var settings: AppSettings

    let project: Project
    let searchText: String
    let refreshTrigger: Int

    @State private var commits: [GitHubCommit] = []
    @State private var selectedCommit: GitHubCommit?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var dateRange: DateRange = .none
    @State private var selectedWeekDay: Date? = Calendar.current.startOfDay(for: Date())

    private var listAnimation: Animation { FacetTheme.listSpring }
    private var detailPaneAnimation: Animation { FacetTheme.detailSpring }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasActiveSearch: Bool {
        !searchQuery.isEmpty
    }

    private var visibleCommits: [GitHubCommit] {
        let query = searchQuery
        guard !query.isEmpty else { return commits }
        return commits.filter { commitMatchesSearch($0, query: query) }
    }

    enum DateRange: String, CaseIterable, Identifiable {
        case none = "None"
        case week = "7 days"
        case month = "30 days"
        case quarter = "90 days"
        case all = "All time"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .none: "calendar.day.timeline.left"
            case .week: "calendar.badge.clock"
            case .month: "calendar"
            case .quarter: "calendar.badge.exclamationmark"
            case .all: "clock.arrow.circlepath"
            }
        }

        var sinceDate: Date? {
            let calendar = Calendar.current
            let now = Date()
            switch self {
            case .none:
                return nil
            case .week:
                return calendar.date(byAdding: .day, value: -7, to: now)
            case .month:
                return calendar.date(byAdding: .day, value: -30, to: now)
            case .quarter:
                return calendar.date(byAdding: .day, value: -90, to: now)
            case .all:
                return nil
            }
        }
    }

    // MARK: – Week selector helpers

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysToSunday = weekday - 1
        guard let sunday = calendar.date(byAdding: .day, value: -daysToSunday, to: today) else { return [] }
        return (0...6).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: sunday)
        }
    }

    private func weekdayShortName(for date: Date) -> String {
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekdays[weekday - 1]
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }

    private func isFuture(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.compare(date, to: calendar.startOfDay(for: Date()), toGranularity: .day) == .orderedDescending
    }

    // MARK: – Derived stats

    private var uniqueAuthors: [(name: String, count: Int)] {
        let counts = Dictionary(grouping: visibleCommits, by: \.authorName)
            .mapValues { $0.count }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                unifiedHeader
                commitsContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let commit = selectedCommit {
                commitDetailPane(commit)
            }
        }
        .animation(detailPaneAnimation, value: selectedCommit != nil)
        .background(FacetTheme.canvas)
        .task(id: project.id) { await reload() }
        .onChange(of: refreshTrigger) { Task { await reload() } }
        .onChange(of: searchText) {
            guard let selectedCommit,
                  !visibleCommits.contains(where: { $0.id == selectedCommit.id }) else { return }
            withAnimation(detailPaneAnimation) {
                self.selectedCommit = nil
            }
        }
    }

    // MARK: – Unified Header

    private var unifiedHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                if !commits.isEmpty {
                    statsCluster
                }

                Spacer(minLength: 10)

                filterCluster
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    if !commits.isEmpty {
                        statsCluster
                    }

                    Spacer()

                    dateRangeMenu
                }

                weekSelector
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(minHeight: 30, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }

    private var statsCluster: some View {
        HStack(spacing: 6) {
            statBadge(icon: hasActiveSearch ? "magnifyingglass" : "number",
                      value: "\(visibleCommits.count)",
                      label: hasActiveSearch ? "results" : "commits")
            statBadge(icon: "person.2", value: "\(uniqueAuthors.count)", label: "contributors")
        }
    }

    private var filterCluster: some View {
        HStack(spacing: 8) {
            weekSelector

            Divider()
                .frame(height: 22)

            dateRangeMenu
        }
    }

    private var dateRangeMenu: some View {
        Menu {
            ForEach(DateRange.allCases) { range in
                Button {
                    setDateRange(range)
                } label: {
                    Label(range.rawValue, systemImage: range == dateRange ? "checkmark" : range.systemImage)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: dateRange.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Text(dateRange.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(FacetTheme.panel.opacity(0.70))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func setDateRange(_ range: DateRange) {
        dateRange = range
        if range != .none {
            selectedWeekDay = nil
        } else if selectedWeekDay == nil {
            selectedWeekDay = Calendar.current.startOfDay(for: Date())
        }
        Task { await reload() }
    }

    private func statBadge(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var weekSelector: some View {
        HStack(spacing: 2) {
            ForEach(weekDates, id: \.self) { date in
                weekDayCell(date)
            }
        }
        .padding(2)
        .background(FacetTheme.panel.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private func weekDayCell(_ date: Date) -> some View {
        let calendar = Calendar.current
        let isSelected = selectedWeekDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let isTodayDate = isToday(date)
        let isFutureDate = isFuture(date)
        let isEnabled = dateRange == .none && !isFutureDate

        return VStack(spacing: 1) {
            Text(weekdayShortName(for: date))
                .font(.system(size: 8, weight: .semibold))
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
        }
        .foregroundStyle(
            !isEnabled ? Color.gray.opacity(0.4) :
            isSelected ? Color.white :
            isTodayDate ? Color.accentColor :
            Color.primary.opacity(0.8)
        )
        .frame(width: 30, height: 30)
        .background(
            isSelected ? Color.accentColor :
            isTodayDate && !isSelected ? Color.accentColor.opacity(0.1) :
            Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if isEnabled {
                selectedWeekDay = date
                dateRange = .none
                Task { await reload() }
            }
        }
        .opacity(isEnabled ? 1.0 : 0.5)
    }

    // MARK: – Content

    @ViewBuilder private var commitsContent: some View {
        if let repo = project.githubRepo {
            if loading && commits.isEmpty {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if commits.isEmpty {
                ContentUnavailableView {
                    Label("No commits", systemImage: "curlybraces")
                } description: {
                    Text("No recent commits found in \(repo).")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleCommits.isEmpty {
                ContentUnavailableView {
                    Label("No results", systemImage: "magnifyingglass")
                } description: {
                    Text("No commits match “\(searchQuery)”.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleCommits) { commit in
                        commitRow(commit)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .thinScrollIndicators()
                .animation(listAnimation, value: visibleCommits.map(\.id))
            }
        } else {
            ContentUnavailableView {
                Label("No GitHub Repo", systemImage: "curlybraces")
            } description: {
                Text("Add a GitHub repository in the project settings to see commits here.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func commitRow(_ commit: GitHubCommit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commit.summary)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(commit.authorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(relativeDate(commit.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(commit.shortSHA)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(FacetTheme.quietPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedCommit?.id == commit.id
                    ? Color.accentColor.opacity(0.08)
                    : FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(selectedCommit?.id == commit.id
                        ? Color.accentColor.opacity(0.35)
                        : FacetTheme.hairline,
                        lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                if selectedCommit?.id == commit.id {
                    selectedCommit = nil
                } else {
                    selectedCommit = commit
                }
            }
        }
    }

    // MARK: – Commit Detail Pane

    private func commitDetailPane(_ commit: GitHubCommit) -> some View {
        FacetSidebarPane(
            title: "Commit Detail",
            systemImage: "curlybraces",
            onClose: { selectedCommit = nil }
        ) {
            FacetSidebarContent {
                commitTitleCard(commit)

                commitMetadataCard(commit)

                if let body = commit.body {
                    commitBodyCard(body)
                }

                commitGitHubCard(commit)
            }
        }
    }

    private func commitTitleCard(_ commit: GitHubCommit) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(authorColor(for: commit.authorName).opacity(0.14))
                Image(systemName: "curlybraces")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(authorColor(for: commit.authorName))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 5) {
                Text(commit.summary)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                Text(project.githubRepo ?? project.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    private func commitMetadataCard(_ commit: GitHubCommit) -> some View {
        FacetDetailSection(title: "Details", systemImage: "info.circle") {
            VStack(spacing: 0) {
                metadataRow(label: "SHA", systemImage: "number") {
                    Text(commit.id)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                metadataDivider

                metadataRow(label: "Author", systemImage: "person") {
                    Text(commit.authorName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }

                metadataDivider

                metadataRow(label: "Date", systemImage: "calendar") {
                    Text(formattedDate(commit.date))
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private func metadataRow<Value: View>(label: String, systemImage: String,
                                          @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 8) {
            Label {
                Text(label)
            } icon: {
                Image(systemName: systemImage)
                    .frame(width: 13)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 76, alignment: .leading)

            value()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }

    private var metadataDivider: some View {
        Divider()
            .padding(.leading, 88)
            .opacity(0.38)
    }

    private func commitBodyCard(_ body: String) -> some View {
        FacetDetailSection(title: "Body", systemImage: "doc.text") {
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func commitGitHubCard(_ commit: GitHubCommit) -> some View {
        FacetDetailSection(title: "GitHub", systemImage: "arrow.up.right.square") {
            Button {
                NSWorkspace.shared.open(commit.htmlURL)
            } label: {
                HStack(spacing: 7) {
                    Text("View on GitHub")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func authorColor(for name: String) -> Color {
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .pink, .teal, .indigo, .red
        ]
        var hash = 0
        for byte in name.utf8 {
            hash = Int(byte) + ((hash << 5) - hash)
        }
        return colors[abs(hash) % colors.count]
    }

    private func commitMatchesSearch(_ commit: GitHubCommit, query: String) -> Bool {
        containsSearch(commit.summary, query: query)
            || containsSearch(commit.message, query: query)
            || containsSearch(commit.authorName, query: query)
            || containsSearch(commit.shortSHA, query: query)
            || containsSearch(commit.id, query: query)
    }

    private func containsSearch(_ value: String, query: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // MARK: – Helpers

    private func reload() async {
        guard let repo = project.githubRepo else { return }
        loading = commits.isEmpty
        errorMessage = nil
        let selectedCommitId = selectedCommit?.id

        let token = settings.githubToken.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else {
            loading = false
            selectedCommit = nil
            errorMessage = "No GitHub token configured.\nAdd one in Settings → GitHub."
            return
        }

        do {
            var since: Date?
            var until: Date?
            let calendar = Calendar.current

            if let selectedDay = selectedWeekDay, dateRange == .none {
                since = calendar.startOfDay(for: selectedDay)
                until = calendar.date(byAdding: .day, value: 1, to: since!)
            } else {
                since = dateRange.sinceDate
            }

            let fetched = try await GitHubService().fetchCommits(repo: repo, token: token, since: since, until: until)
            withAnimation(listAnimation) {
                commits = fetched
                selectedCommit = selectedCommitId.flatMap { id in
                    fetched.first { $0.id == id }
                }
            }
        } catch let error as GitHubService.APIError {
            selectedCommit = nil
            errorMessage = error.message
        } catch let error as URLError {
            selectedCommit = nil
            errorMessage = "Network error: \(error.localizedDescription)"
        } catch let error as DecodingError {
            selectedCommit = nil
            errorMessage = "Data error: \(error.localizedDescription)"
        } catch {
            selectedCommit = nil
            errorMessage = "Failed to load commits: \(error.localizedDescription)"
        }
        loading = false
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
