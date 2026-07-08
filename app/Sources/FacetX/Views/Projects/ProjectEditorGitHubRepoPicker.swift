import AppKit
import SwiftUI

struct ProjectEditorGitHubRepoPicker: View {
    @EnvironmentObject private var settings: AppSettings

    @Binding var selection: String
    @Binding var localPath: String

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
                Text(L10n.pick("Local Repo", "本地仓库"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(localPath.isEmpty ? L10n.pick("Not set", "未设置") : (localPath as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(localPath.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .trailing)
                if !localPath.isEmpty {
                    Button {
                        localPath = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.pick("Clear local repository", "清除本地仓库"))
                }
                Button(L10n.pick("Choose...", "选择...")) {
                    chooseLocalRepository()
                }
                .controlSize(.small)
            }

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
                ProjectEditorHelp(L10n.pick("Choose a local repository to auto-detect owner/repo, or enter it manually.",
                                            "选择本地仓库可自动识别 owner/repo，也可以手动输入。"))
            }
        }
        .task { await loadRepositories() }
    }

    private func chooseLocalRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.pick("Choose", "选择")
        if !localPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: localPath)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let info = LocalGitRepository.inspect(path: url.path) else {
            status = L10n.pick("The selected folder is not inside a Git repository.",
                               "所选文件夹不在 Git 仓库中。")
            return
        }
        localPath = info.rootPath
        if let fullName = info.fullName {
            selection = fullName
            status = L10n.pick("Detected \(fullName) from local origin.",
                               "已从本地 origin 识别出 \(fullName)。")
        } else {
            status = L10n.pick("Local Git repository selected, but origin is not a GitHub remote.",
                               "已选择本地 Git 仓库，但 origin 不是 GitHub 远程地址。")
        }
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
