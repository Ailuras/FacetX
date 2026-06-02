import SwiftUI

/// Displays recent GitHub commits for a project's configured repository.
struct CommitsView: View {
    @EnvironmentObject private var settings: AppSettings

    let project: Project

    @State private var commits: [GitHubCommit] = []
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
        HSplitView {
            gitSidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)

            VStack(spacing: 0) {
                commitsHeader
                Divider()
                commitsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(FacetTheme.canvas)
        }
        .background(FacetTheme.canvas)
        .task(id: project.id) { await reload() }
    }

    // MARK: – Sidebar

    private var gitSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let repo = project.githubRepo {
                    repoInfoCard(repo: repo)

                    if !commits.isEmpty {
                        statsCard
                        contributorsCard
                    }
                }
            }
            .padding(14)
        }
        .background(FacetTheme.canvas)
        .overlay(
            Rectangle().fill(FacetTheme.hairline).frame(width: 1),
            alignment: .trailing
        )
    }

    private func repoInfoCard(repo: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Repository")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.86))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(repo)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                if let url = URL(string: "https://github.com/\(repo)") {
                    Button("Open on GitHub") {
                        NSWorkspace.shared.open(url)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Statistics")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.86))
            }

            VStack(alignment: .leading, spacing: 8) {
                statRow(icon: "number", label: "Commits", value: "\(commits.count)")
                statRow(icon: "person.2", label: "Contributors", value: "\(uniqueAuthors.count)")

                if let period = commitPeriodString {
                    statRow(icon: "calendar", label: "Period", value: period)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private var contributorsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Contributors")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.86))
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(uniqueAuthors.prefix(8), id: \.name) { author in
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(authorColor(for: author.name))
                                .frame(width: 22, height: 22)
                            Text(String(author.name.prefix(1)).uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        Text(author.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text("\(author.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(FacetTheme.panel.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
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
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            NSWorkspace.shared.open(commit.htmlURL)
        }
        .help("Open commit on GitHub")
    }

    // MARK: – Helpers

    private func reload() async {
        guard let repo = project.githubRepo else { return }
        loading = commits.isEmpty
        errorMessage = nil

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
}
