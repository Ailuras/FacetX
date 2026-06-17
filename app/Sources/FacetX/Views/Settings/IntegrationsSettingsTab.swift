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
            apiCard
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

    // MARK: - LLM API

    private var apiCard: some View {
        SettingsCard(title: L10n.pick("LLM API", "大模型 API"), systemImage: "character.book.closed",
                     subtitle: L10n.pick("Provider and credentials shared by features such as translation.",
                                         "供翻译等功能共用的服务商与凭据。")) {
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
            SettingsDivider()
            SettingsRow(title: L10n.pick("Field Filter", "领域过滤"), systemImage: "line.3.horizontal.decrease.circle") {
                TextField(L10n.pick("topics.field.id:17", "topics.field.id:17"), text: $litSettings.topicFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsUI.controlWidth)
            }
            ProjectEditorHelp(L10n.pick("OpenAlex receives this as an extra filter expression on every fetch. The preset topics.field.id:17 limits results to Computer Science. Contact email is recommended by OpenAlex for higher rate limits.",
                                        "FacetX 会把它作为额外 filter 表达式附加到每次 OpenAlex 拉取。预设 topics.field.id:17 表示限制在计算机科学领域；联系邮箱有助于获得更好的速率限制。"))
                .padding(.leading, 28)
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
                    .monospacedDigit()
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
