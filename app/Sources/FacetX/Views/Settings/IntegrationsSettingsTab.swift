import SwiftUI

struct IntegrationsSettingsTab: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    @State private var githubToken = ""
    @State private var githubStatus = ""
    @State private var validating = false

    var body: some View {
        SettingsPage(title: "Integrations",
                     subtitle: "External services and credentials",
                     systemImage: "curlybraces",
                     warning: persistenceWarning) {
            SettingsCard(title: "GitHub", systemImage: "curlybraces") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if githubStatus.isEmpty {
                            Text("No token configured.")
                                .font(SettingsUI.secondaryFont)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: githubConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(githubConnected ? .green : .orange)
                                Text(githubStatus)
                                    .font(SettingsUI.secondaryFont)
                            }
                        }

                        Spacer()

                        if !githubStatus.isEmpty {
                            Button("Remove") {
                                settings.githubToken = ""
                                githubToken = ""
                                githubStatus = ""
                            }
                            .controlSize(.small)
                        }
                    }

                    HStack(spacing: 8) {
                        SecureField("Personal Access Token", text: $githubToken)
                            .textFieldStyle(.roundedBorder)

                        Button(validating ? "Validating..." : "Save") {
                            saveGitHubToken()
                        }
                        .disabled(githubToken.isEmpty || validating)
                    }
                }
            }
        }
        .onAppear(perform: loadGitHubStatus)
    }

    private var persistenceWarning: String? {
        store.persistenceError ?? settings.persistenceError
    }

    private var githubConnected: Bool {
        githubStatus.hasPrefix("Connected as ")
    }

    private func loadGitHubStatus() {
        let token = settings.githubToken
        guard githubToken.isEmpty, !token.isEmpty else { return }
        githubToken = token
        Task {
            do {
                let username = try await GitHubService().validateToken(token)
                await MainActor.run { githubStatus = "Connected as \(username)" }
            } catch {
                await MainActor.run { githubStatus = "Token invalid" }
            }
        }
    }

    private func saveGitHubToken() {
        let token = githubToken.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return }
        validating = true
        Task {
            do {
                let username = try await GitHubService().validateToken(token)
                await MainActor.run {
                    settings.githubToken = token
                    githubStatus = "Connected as \(username)"
                    validating = false
                }
            } catch {
                await MainActor.run {
                    githubStatus = "Validation failed"
                    validating = false
                }
            }
        }
    }
}
