import SwiftUI

struct IntegrationsSettingsTab: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @State private var litSettings = LibrarySettings.shared

    @State private var githubToken = ""
    @State private var githubStatus = ""
    @State private var validating = false

    // Translation API
    @State private var isTesting = false
    @State private var connectionMessage: String?
    @State private var connectionIsError = false
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false

    var body: some View {
        SettingsPage(title: L10n.pick("Integrations", "集成"),
                     subtitle: L10n.pick("External services and credentials", "外部服务与凭据"),
                     systemImage: "curlybraces",
                     warning: persistenceWarning) {
            githubCard
            translationCard
            openAlexCard
        }
        .onAppear {
            loadGitHubStatus()
            if availableModels.isEmpty, !litSettings.apiKey.isEmpty { loadModels() }
        }
    }

    // MARK: - GitHub

    private var githubCard: some View {
        SettingsCard(title: "GitHub", systemImage: "curlybraces",
                     subtitle: L10n.pick("Personal access token for commit history.",
                                         "用于读取提交历史的个人访问令牌。")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if githubStatus.isEmpty {
                        Text(L10n.pick("No token configured.", "尚未配置令牌。"))
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
                        Button(L10n.pick("Remove", "移除")) {
                            settings.githubToken = ""
                            githubToken = ""
                            githubStatus = ""
                        }
                        .controlSize(.small)
                    }
                }

                HStack(spacing: 8) {
                    SecureField(L10n.pick("Personal Access Token", "个人访问令牌"), text: $githubToken)
                        .textFieldStyle(.roundedBorder)

                    Button(validating ? L10n.pick("Validating...", "验证中…") : L10n.pick("Save", "保存")) {
                        saveGitHubToken()
                    }
                    .disabled(githubToken.isEmpty || validating)
                }
            }
        }
    }

    // MARK: - Translation API

    private var translationCard: some View {
        SettingsCard(title: L10n.pick("Translation API", "翻译 API"), systemImage: "character.book.closed",
                     subtitle: L10n.pick("LLM provider used to translate paper abstracts.",
                                         "用于翻译文献摘要的大模型服务。")) {
            SettingsRow(title: L10n.pick("Enable Translation", "启用翻译"), systemImage: "globe") {
                Toggle("", isOn: $litSettings.translateEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("Provider", "服务商"), systemImage: "server.rack") {
                Picker("", selection: $litSettings.apiProvider) {
                    ForEach(TranslationProvider.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                .onChange(of: litSettings.apiProvider) { _, p in
                    litSettings.apiBaseURL = p.defaultBaseURL
                    litSettings.apiModel = p.defaultModel
                    availableModels = []
                    connectionMessage = nil
                }
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("Target Language", "目标语言"), systemImage: "text.bubble") {
                TextField("", text: $litSettings.targetLanguage)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsUI.controlWidth)
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("Base URL", "接口地址"), systemImage: "link") {
                TextField("", text: $litSettings.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsUI.controlWidth)
                    .onChange(of: litSettings.apiBaseURL) { _, _ in connectionMessage = nil }
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("API Key", "API 密钥"), systemImage: "key") {
                HStack(spacing: 8) {
                    SecureField("", text: $litSettings.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .onChange(of: litSettings.apiKey) { _, _ in connectionMessage = nil }
                    Button { testConnection() } label: {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.pick("Test", "测试"))
                        }
                    }
                    .controlSize(.small)
                    .disabled(isTesting || litSettings.apiKey.isEmpty)
                }
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("Model", "模型"), systemImage: "cpu") {
                HStack(spacing: 6) {
                    Picker("", selection: $litSettings.apiModel) {
                        if availableModels.isEmpty {
                            Text(litSettings.apiModel.isEmpty ? L10n.pick("Unavailable", "不可用") : litSettings.apiModel)
                                .tag(litSettings.apiModel)
                        } else {
                            ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                    .disabled(availableModels.isEmpty)
                    Button { loadModels() } label: {
                        if isLoadingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain).disabled(isLoadingModels)
                }
            }
            if let connectionMessage {
                HStack(spacing: 6) {
                    Image(systemName: connectionIsError ? "exclamationmark.triangle" : "checkmark.circle")
                    Text(connectionMessage).lineLimit(2)
                }
                .font(SettingsUI.smallFont)
                .foregroundStyle(connectionIsError ? .red : .green)
                .padding(.leading, 28)
            }
        }
    }

    // MARK: - OpenAlex

    private var openAlexCard: some View {
        SettingsCard(title: "OpenAlex", systemImage: "magnifyingglass",
                     subtitle: L10n.pick("Contact email sent with OpenAlex requests.",
                                         "随 OpenAlex 请求发送的联系邮箱。")) {
            SettingsRow(title: L10n.pick("Contact Email", "联系邮箱"), systemImage: "envelope") {
                TextField("", text: $litSettings.openAlexMailto)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsUI.controlWidth)
            }
            ProjectEditorHelp(L10n.pick("Recommended by OpenAlex for higher rate limits.",
                                        "OpenAlex 建议填写以提升速率限制。"))
                .padding(.leading, 28)
        }
    }

    // MARK: - GitHub helpers

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
                await MainActor.run { githubStatus = L10n.pick("Token invalid", "令牌无效") }
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
                    githubStatus = L10n.pick("Validation failed", "验证失败")
                    validating = false
                }
            }
        }
    }

    // MARK: - Translation helpers

    private func testConnection() {
        isTesting = true
        connectionMessage = nil
        Task {
            do {
                let models = try await fetchModels()
                apply(models: models)
                connectionIsError = false
                connectionMessage = L10n.pick("Connected · \(models.count) models", "已连接 · \(models.count) 个模型")
            } catch {
                connectionIsError = true
                connectionMessage = L10n.pick("Failed: \(error.localizedDescription)", "失败：\(error.localizedDescription)")
            }
            isTesting = false
        }
    }

    private func loadModels() {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        Task {
            if let models = try? await fetchModels() { apply(models: models) }
            isLoadingModels = false
        }
    }

    private func fetchModels() async throws -> [String] {
        let service = TranslationService(config: ConfigManager.shared.effectiveConfig, apiKey: litSettings.apiKey)
        return try await service.fetchModels()
    }

    private func apply(models: [String]) {
        availableModels = models
        if !models.isEmpty, !models.contains(litSettings.apiModel) {
            litSettings.apiModel = models[0]
        }
    }
}
