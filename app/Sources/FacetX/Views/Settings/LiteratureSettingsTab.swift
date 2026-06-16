import SwiftUI

struct LiteratureSettingsTab: View {
    @State private var settings = LibrarySettings.shared

    @State private var isTesting = false
    @State private var connectionMessage: String?
    @State private var connectionIsError = false
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false

    var body: some View {
        SettingsPage(title: L10n.pick("Literature", "文献"),
                     subtitle: L10n.pick("Translation, fetching and recommendations", "翻译、拉取与推荐"),
                     systemImage: "books.vertical",
                     warning: nil) {
            translationCard
            fetchCard
            recommendationCard
        }
        .onAppear {
            if availableModels.isEmpty, !settings.apiKey.isEmpty { loadModels() }
        }
    }

    // MARK: - Translation

    private var translationCard: some View {
        SettingsCard(title: L10n.pick("Translation API", "翻译 API"), systemImage: "character.book.closed") {
            SettingsRow(title: L10n.pick("Enable Translation", "启用翻译"), systemImage: "globe") {
                Toggle("", isOn: $settings.translateEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("Provider", "服务商"), systemImage: "server.rack") {
                Picker("", selection: $settings.apiProvider) {
                    ForEach(TranslationProvider.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                .onChange(of: settings.apiProvider) { _, p in
                    settings.apiBaseURL = p.defaultBaseURL
                    settings.apiModel = p.defaultModel
                    availableModels = []
                    connectionMessage = nil
                }
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("Target Language", "目标语言"), systemImage: "text.bubble") {
                TextField("", text: $settings.targetLanguage)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsUI.controlWidth)
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("Base URL", "接口地址"), systemImage: "link") {
                TextField("", text: $settings.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsUI.controlWidth)
                    .onChange(of: settings.apiBaseURL) { _, _ in connectionMessage = nil }
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("API Key", "API 密钥"), systemImage: "key") {
                HStack(spacing: 8) {
                    SecureField("", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .onChange(of: settings.apiKey) { _, _ in connectionMessage = nil }
                    Button { testConnection() } label: {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.pick("Test", "测试"))
                        }
                    }
                    .controlSize(.small)
                    .disabled(isTesting || settings.apiKey.isEmpty)
                }
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("Model", "模型"), systemImage: "cpu") {
                HStack(spacing: 6) {
                    Picker("", selection: $settings.apiModel) {
                        if availableModels.isEmpty {
                            Text(settings.apiModel.isEmpty ? L10n.pick("Unavailable", "不可用") : settings.apiModel)
                                .tag(settings.apiModel)
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

    // MARK: - Fetch

    private var fetchCard: some View {
        SettingsCard(title: L10n.pick("OpenAlex Fetch", "OpenAlex 拉取"), systemImage: "magnifyingglass") {
            SettingsRow(title: L10n.pick("Contact Email", "联系邮箱"), systemImage: "envelope") {
                TextField("", text: $settings.openAlexMailto)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsUI.controlWidth)
            }
            ProjectEditorHelp(L10n.pick("Recommended by OpenAlex for higher rate limits.",
                                        "OpenAlex 建议填写以提升速率限制。"))
                .padding(.leading, 28)
            SettingsDivider()
            numberRow(L10n.pick("Results per Page", "每页结果"), systemImage: "list.number",
                      value: $settings.perPage, range: 1...200)
            SettingsDivider()
            numberRow(L10n.pick("Max Results", "最大结果数"), systemImage: "number",
                      value: $settings.defaultMaxResults, range: 1...1000)
            SettingsDivider()
            SettingsRow(title: L10n.pick("Topic Filter", "主题过滤"), systemImage: "line.3.horizontal.decrease.circle") {
                TextField(L10n.pick("optional OpenAlex filter", "可选 OpenAlex 过滤"), text: $settings.topicFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsUI.controlWidth)
            }
        }
    }

    // MARK: - Recommendations

    private var recommendationCard: some View {
        SettingsCard(title: L10n.pick("Daily Recommendations", "每日推荐"), systemImage: "sparkles") {
            stepperRow(L10n.pick("Daily Count", "每日数量"), systemImage: "number.circle",
                       value: $settings.dailyCount, range: 1...20)
            SettingsDivider()
            stepperRow(L10n.pick("Quality Slots", "高分名额"), systemImage: "star.circle",
                       value: $settings.qualitySlots, range: 0...20)
            SettingsDivider()
            stepperRow(L10n.pick("High-Score Threshold", "高分阈值"), systemImage: "chart.line.uptrend.xyaxis",
                       value: $settings.highScoreThreshold, range: 0...100)
            SettingsDivider()
            stepperRow(L10n.pick("Recent Window (days)", "近期窗口（天）"), systemImage: "calendar.badge.clock",
                       value: $settings.recentDays, range: 1...365)
        }
    }

    // MARK: - Helpers

    private func numberRow(_ title: String, systemImage: String,
                           value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        SettingsRow(title: title, systemImage: systemImage) {
            TextField("", value: clamped(value, to: range), format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func stepperRow(_ title: String, systemImage: String,
                            value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        SettingsRow(title: title, systemImage: systemImage) {
            HStack(spacing: 4) {
                TextField("", value: clamped(value, to: range), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .textFieldStyle(.roundedBorder)
                Stepper("", value: value, in: range)
                    .labelsHidden().controlSize(.mini)
            }
        }
    }

    private func clamped(_ value: Binding<Int>, to range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

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
        let service = TranslationService(config: ConfigManager.shared.effectiveConfig, apiKey: settings.apiKey)
        return try await service.fetchModels()
    }

    private func apply(models: [String]) {
        availableModels = models
        if !models.isEmpty, !models.contains(settings.apiModel) {
            settings.apiModel = models[0]
        }
    }
}
