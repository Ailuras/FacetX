import SwiftUI

/// Displays recent GitHub commits for a project's configured repository.
struct CommitsView: View {
    @EnvironmentObject private var settings: AppSettings

    let project: Project

    @State private var commits: [GitHubCommit] = []
    @State private var selectedCommit: GitHubCommit?
    @State private var loading = false
    @State private var errorMessage: String?

    private var listAnimation: Animation { FacetTheme.listSpring }

    // MARK: – Derived stats

    private var uniqueAuthors: [(name: String, count: Int)] {
        let counts = Dictionary(grouping: commits, by: \.authorName)
            .mapValues { $0.count }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var latestCommitDate: Date? {
        commits.map(\.date).max()
    }

    private var oldestCommitDate: Date? {
        commits.map(\.date).min()
    }

    private var commitPeriodString: String? {
        guard let oldest = oldestCommitDate, let latest = latestCommitDate else { return nil }
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: oldest, to: latest)
    }

    var body: some View {
        VStack(spacing: 0) {
            commitsHeader
            Divider()

            if !commits.isEmpty {
                projectInfoBar
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                Divider()
            }

            HStack(spacing: 0) {
                commitsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let commit = selectedCommit {
                    Divider()
                    commitDetailPane(commit)
                        .frame(width: 320)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .background(FacetTheme.canvas)
        .task(id: project.id) { await reload() }
    }

    // MARK: – Project Info Bar

    private var projectInfoBar: some View {
        HStack(spacing: 16) {
            if let repo = project.githubRepo {
                HStack(spacing: 6) {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(repo)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }

                Divider().frame(height: 14)

                HStack(spacing: 4) {
                    Image(systemName: "number")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(commits.count) commits")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 14)

                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(uniqueAuthors.count) contributors")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if let period = commitPeriodString {
                    Divider().frame(height: 14)
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(period)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Top contributors avatars
                HStack(spacing: -6) {
                    ForEach(uniqueAuthors.prefix(4), id: \.name) { author in
                        Circle()
                            .fill(authorColor(for: author.name))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Text(String(author.name.prefix(1)).uppercased())
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                            .overlay(
                                Circle().stroke(FacetTheme.canvas, lineWidth: 1.5)
                            )
                    }
                }
            }
        }
    }

    // MARK: – Header

    private var commitsHeader: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("GitHub Activity")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh commits")
            .disabled(loading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
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
            } else {
                List {
                    ForEach(commits) { commit in
                        commitRow(commit)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(listAnimation, value: commits.map(\.id))
            }
        } else {
            ContentUnavailableView {
                Label("No GitHub Repo", systemImage: "curlybraces")
            } description: {
                Text("Add a GitHub repository in the project settings to see commits here.")
            }
        }
    }

    private func commitRow(_ commit: GitHubCommit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commit.message)
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
        VStack(spacing: 0) {
            // Pane header
            HStack(spacing: 10) {
                Label {
                    Text("Commit")
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedCommit = nil
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close sidebar")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Commit message card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.14))
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .frame(width: 30, height: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Commit")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary.opacity(0.86))
                                Text(commit.shortSHA)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(commit.message)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(nil)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FacetTheme.quietPanel)
                    .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1)
                    )

                    // Details card
                    VStack(alignment: .leading, spacing: 0) {
                        detailRow(label: "Author", icon: "person") {
                            Text(commit.authorName)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                        }

                        detailDivider

                        detailRow(label: "Date", icon: "calendar") {
                            Text(formattedDate(commit.date))
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                        }

                        detailDivider

                        detailRow(label: "SHA", icon: "number") {
                            Text(commit.id)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .help(commit.id)
                        }

                        detailDivider

                        detailRow(label: "Repository", icon: "curlybraces") {
                            if let repo = project.githubRepo {
                                Text(repo)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(FacetTheme.quietPanel)
                    .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }

            Divider()

            // Footer with open button
            HStack {
                Spacer()
                Button {
                    NSWorkspace.shared.open(commit.htmlURL)
                } label: {
                    Label("Open on GitHub", systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(FacetTheme.canvas)
        }
        .frame(maxHeight: .infinity)
        .background(FacetTheme.canvas)
    }

    private func detailRow<Content: View>(label: String, icon: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon)
                    .frame(width: 13)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 80, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }

    private var detailDivider: some View {
        Divider()
            .padding(.leading, 92)
            .opacity(0.38)
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

    // MARK: – Helpers

    private func reload() async {
        guard let repo = project.githubRepo else { return }
        loading = commits.isEmpty
        errorMessage = nil
        selectedCommit = nil

        let token = settings.githubToken.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else {
            loading = false
            errorMessage = "No GitHub token configured.\nAdd one in Settings → GitHub."
            return
        }

        do {
            let fetched = try await GitHubService().fetchCommits(repo: repo, token: token)
            withAnimation(listAnimation) {
                commits = fetched
            }
        } catch let error as GitHubService.APIError {
            errorMessage = error.message
        } catch {
            errorMessage = "Failed to load commits."
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
