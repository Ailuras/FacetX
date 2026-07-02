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

    var body: some View {
        SettingsPage(title: L10n.pick("Integrations", "集成"),
                     subtitle: L10n.pick("External services and credentials", "外部服务与凭据"),
                     systemImage: "curlybraces",
                     warning: persistenceWarning) {
            assistantCard
            githubCard
            apiCard
            openAlexCard
        }
        .onAppear {
            loadGitHubStatus()
        }
    }

    // MARK: - Assistant (Claude API)

    private var assistantCard: some View {
        SettingsCard(title: L10n.pick("Assistant (Claude API)", "AI 助手（Claude API）"),
                     systemImage: "sparkles",
                     subtitle: L10n.pick("Credentials and model for the built-in assistant.",
                                         "内置 AI 助手使用的凭据与模型。")) {
            HStack(spacing: 8) {
                serviceMetric(title: L10n.pick("Key", "密钥"),
                              value: settings.anthropicApiKey.isEmpty
                                  ? L10n.pick("Not Set", "未设置")
                                  : L10n.pick("Saved", "已保存"),
                              systemImage: "key",
                              tint: settings.anthropicApiKey.isEmpty ? .orange : .green)
                serviceMetric(title: L10n.pick("Model", "模型"),
                              value: settings.anthropicModel,
                              systemImage: "cpu",
                              tint: .blue)
            }

            VStack(spacing: 0) {
                SettingsRow(title: "API Key", systemImage: "key") {
                    SecureField("sk-ant-…", text: $settings.anthropicApiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }
                SettingsDivider()
                SettingsRow(title: L10n.pick("Model", "模型"), systemImage: "cpu") {
                    Picker("", selection: $settings.anthropicModel) {
                        Text("Claude Opus 4.8").tag("claude-opus-4-8")
                        Text("Claude Sonnet 5").tag("claude-sonnet-5")
                        Text("Claude Haiku 4.5").tag("claude-haiku-4-5")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(title: L10n.pick("Base URL (optional)", "Base URL（可选）"),
                            systemImage: "network") {
                    TextField("https://api.anthropic.com", text: $settings.anthropicBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - GitHub

    private var githubCard: some View {
        SettingsCard(title: "GitHub", systemImage: "curlybraces",
                     subtitle: L10n.pick("Personal access token for commit history.",
                                         "用于读取提交历史的个人访问令牌。")) {
            HStack(spacing: 8) {
                serviceMetric(title: L10n.pick("Status", "状态"),
                              value: githubStatusText,
                              systemImage: githubConnected ? "checkmark.circle" : "key",
                              tint: githubConnected ? .green : .orange)
                serviceMetric(title: L10n.pick("Access", "访问"),
                              value: settings.githubToken.isEmpty ? L10n.pick("Not Set", "未设置") : L10n.pick("Token Saved", "令牌已保存"),
                              systemImage: "lock.shield",
                              tint: .blue)
            }

            SettingsRow(title: L10n.pick("Token", "令牌"), systemImage: "key") {
                HStack(spacing: 8) {
                    SecureField(L10n.pick("Personal Access Token", "个人访问令牌"), text: $githubToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 138)

                    Button {
                        saveGitHubToken()
                    } label: {
                        if validating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(L10n.pick("Test", "测试"))
                        }
                    }
                    .controlSize(.small)
                    .disabled(githubToken.isEmpty || validating)

                    if !settings.githubToken.isEmpty || !githubStatus.isEmpty {
                        Button(role: .destructive) {
                            settings.githubToken = ""
                            githubToken = ""
                            githubStatus = ""
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help(L10n.pick("Remove token", "移除令牌"))
                    }
                }
                .frame(width: SettingsUI.controlWidth, alignment: .trailing)
            }
        }
    }

    // MARK: - LLM API

    private var apiCard: some View {
        SettingsCard(title: L10n.pick("LLM API", "大模型 API"), systemImage: "character.book.closed",
                     subtitle: L10n.pick("Provider and credentials shared by features such as translation.",
                                         "供翻译等功能共用的服务商与凭据。")) {
            HStack(spacing: 8) {
                serviceMetric(title: L10n.pick("Provider", "服务商"),
                              value: litSettings.apiProvider.displayName,
                              systemImage: "server.rack",
                              tint: .purple)
                serviceMetric(title: L10n.pick("Model", "模型"),
                              value: litSettings.apiModel.isEmpty ? L10n.pick("Unset", "未设置") : litSettings.apiModel,
                              systemImage: "cpu",
                              tint: .blue)
                serviceMetric(title: L10n.pick("Connection", "连接"),
                              value: apiConnectionStatus,
                              systemImage: apiConnectionIcon,
                              tint: apiConnectionTint)
            }

            VStack(spacing: 0) {
                SettingsRow(title: L10n.pick("Provider", "服务商"), systemImage: "server.rack") {
                    Picker("", selection: $litSettings.apiProvider) {
                        ForEach(TranslationProvider.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                    .onChange(of: litSettings.apiProvider) { _, p in
                        litSettings.apiBaseURL = p.defaultBaseURL
                        litSettings.apiModel = p.defaultModel
                        availableModels = []
                        connectionMessage = nil
                    }
                }
                compactDivider
                SettingsRow(title: L10n.pick("API", "接口"), systemImage: "link") {
                    TextField("", text: $litSettings.apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: SettingsUI.controlWidth)
                        .onChange(of: litSettings.apiBaseURL) { _, _ in connectionMessage = nil }
                }
                compactDivider
                SettingsRow(title: L10n.pick("Credential", "凭据"), systemImage: "key") {
                    SecureField("", text: $litSettings.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: SettingsUI.controlWidth)
                        .onChange(of: litSettings.apiKey) { _, _ in connectionMessage = nil }
                }
                compactDivider
                SettingsRow(title: L10n.pick("Model", "模型"), systemImage: "cpu") {
                    HStack(spacing: 8) {
                        Picker("", selection: $litSettings.apiModel) {
                            if availableModels.isEmpty {
                                Text(litSettings.apiModel.isEmpty ? L10n.pick("Unavailable", "不可用") : litSettings.apiModel)
                                    .tag(litSettings.apiModel)
                            } else {
                                ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 172, alignment: .trailing)
                        .disabled(availableModels.isEmpty)

                        Button { testConnection() } label: {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(L10n.pick("Test", "测试"))
                            }
                        }
                        .controlSize(.small)
                        .disabled(isTesting || litSettings.apiKey.isEmpty)
                    }
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(FacetTheme.panel.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )

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
                     subtitle: L10n.pick("Fetch scope, field filter and request identity.",
                                         "拉取范围、领域过滤与请求身份。")) {
            HStack(spacing: 8) {
                serviceMetric(title: L10n.pick("Window", "时间窗口"),
                              value: L10n.pick("\(litSettings.defaultDays) days", "\(litSettings.defaultDays) 天"),
                              systemImage: "calendar.badge.clock",
                              tint: .blue)
                serviceMetric(title: L10n.pick("Per Request", "每次请求"),
                              value: "\(litSettings.perPage)",
                              systemImage: "list.number",
                              tint: .green)
                serviceMetric(title: L10n.pick("Library Cap", "单库上限"),
                              value: "\(litSettings.defaultMaxResults)",
                              systemImage: "number",
                              tint: .orange)
            }

            VStack(spacing: 0) {
                compactStepperRow(L10n.pick("Publication Window", "发表时间窗口"),
                                  value: $litSettings.defaultDays,
                                  range: 1...365,
                                  unit: L10n.pick("days", "天"),
                                  valueWidth: 56)
                compactDivider
                compactStepperRow(L10n.pick("Results per Request", "每次请求数量"),
                                  value: $litSettings.perPage,
                                  range: 1...200,
                                  unit: L10n.pick("items", "条"),
                                  valueWidth: 56)
                compactDivider
                compactStepperRow(L10n.pick("Total Cap per Library", "单库总上限"),
                                  value: $litSettings.defaultMaxResults,
                                  range: 1...1000,
                                  unit: L10n.pick("items", "条"),
                                  valueWidth: 64)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(FacetTheme.panel.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )

            SettingsRow(title: L10n.pick("Contact Email", "联系邮箱"), systemImage: "envelope") {
                TextField("", text: $litSettings.openAlexMailto)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsUI.controlWidth)
            }
            SettingsRow(title: L10n.pick("Field Filter", "领域过滤"), systemImage: "line.3.horizontal.decrease.circle") {
                TextField(L10n.pick("topics.field.id:17", "topics.field.id:17"), text: $litSettings.topicFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsUI.controlWidth)
            }
        }
    }

    // MARK: - Shared controls

    private func serviceMetric(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(SettingsUI.smallFont)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(FacetTheme.panel.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private func compactStepperRow(_ title: String,
                                   value: Binding<Int>, range: ClosedRange<Int>,
                                   unit: String, valueWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(SettingsUI.rowFont)
                .lineLimit(1)
            Spacer()
            TextField("", value: clamped(value, to: range), format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: valueWidth)
                .textFieldStyle(.roundedBorder)
            Text(unit)
                .font(SettingsUI.smallFont)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
            Stepper("", value: value, in: range)
                .labelsHidden()
                .controlSize(.mini)
        }
        .padding(.vertical, 4)
    }

    private var compactDivider: some View {
        Divider()
            .opacity(0.36)
            .padding(.leading, 2)
    }

    private func clamped(_ value: Binding<Int>, to range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

    // MARK: - GitHub helpers

    private var persistenceWarning: String? {
        store.persistenceError ?? settings.persistenceError
    }

    private var githubConnected: Bool {
        githubStatus.hasPrefix("Connected as ")
    }

    private var githubStatusText: String {
        if githubStatus.isEmpty { return L10n.pick("Not Tested", "未测试") }
        if githubConnected {
            return githubStatus.replacingOccurrences(of: "Connected as ", with: "@")
        }
        return githubStatus
    }

    private var apiConnectionStatus: String {
        guard let connectionMessage else {
            return litSettings.apiKey.isEmpty ? L10n.pick("No Key", "无密钥") : L10n.pick("Not Tested", "未测试")
        }
        if connectionIsError { return L10n.pick("Failed", "失败") }
        return connectionMessage.hasPrefix("Connected") || connectionMessage.hasPrefix("已连接")
            ? L10n.pick("Connected", "已连接")
            : connectionMessage
    }

    private var apiConnectionIcon: String {
        if connectionMessage == nil {
            return litSettings.apiKey.isEmpty ? "key.slash" : "questionmark.circle"
        }
        return connectionIsError ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private var apiConnectionTint: Color {
        if connectionMessage == nil {
            return litSettings.apiKey.isEmpty ? .orange : .secondary
        }
        return connectionIsError ? .red : .green
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
