import SwiftUI

/// Displays recent GitHub commits for a project's configured repository.
struct CommitsView: View {
    let project: Project

    @State private var commits: [GitHubCommit] = []
    @State private var loading = false
    @State private var errorMessage: String?

    private var listAnimation: Animation { FacetTheme.listSpring }

    var body: some View {
        VStack(spacing: 0) {
            commitsHeader
            Divider()
            commitsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FacetTheme.canvas)
        .task(id: project.id) { await reload() }
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

        let token = GitHubTokenStore.loadToken()
        guard token != nil else {
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
