import SwiftUI

struct ProjectEditorGitHubRepoPicker: View {
    @EnvironmentObject private var settings: AppSettings

    @Binding var selection: String

    @State private var repositories: [GitHubRepository] = []
    @State private var loading = false
    @State private var status: String?

    private var repositoryNames: [String] {
        repositories.map(\.fullName)
    }

    private var pickerOptions: [String] {
        let trimmed = selection.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !repositoryNames.contains(trimmed) {
            return [trimmed] + repositoryNames
        }
        return repositoryNames
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(L10n.pick("GitHub Repo", "GitHub 仓库"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if loading {
                    ProgressView()
                        .controlSize(.small)
                }
                Picker("", selection: $selection) {
                    Text(L10n.pick("None", "无")).tag("")
                    ForEach(pickerOptions, id: \.self) { repo in
                        Text(repo).tag(repo)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 230, alignment: .trailing)
                .disabled(loading || pickerOptions.isEmpty)

                Button {
                    Task { await loadRepositories() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L10n.pick("Refresh GitHub repositories", "刷新 GitHub 仓库"))
                .disabled(loading)
            }

            TextField("owner/repo", text: $selection)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(FacetTheme.panel.opacity(0.70))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(FacetTheme.hairline, lineWidth: 1)
                )

            if let status {
                ProjectEditorHelp(status)
            } else {
                ProjectEditorHelp("Choose a repository from GitHub, or enter owner/repo manually.")
            }
        }
        .task { await loadRepositories() }
    }

    private func loadRepositories() async {
        guard !loading else { return }
        let token = settings.githubToken.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else {
            status = "No GitHub token configured. Add one in Settings -> GitHub, or enter owner/repo manually."
            return
        }

        loading = true
        status = nil
        do {
            let fetched = try await GitHubService().fetchRepositories(token: token)
            repositories = fetched
            status = fetched.isEmpty ? "No repositories were returned by GitHub. You can still enter owner/repo manually." : nil
        } catch let error as GitHubService.APIError {
            status = error.message
        } catch {
            status = "Failed to load GitHub repositories. You can still enter owner/repo manually."
        }
        loading = false
    }
}
