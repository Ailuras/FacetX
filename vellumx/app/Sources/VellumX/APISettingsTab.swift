import SwiftUI

struct APISettingsTab: View {
    @State private var settings = AppSettings.shared
    @State private var isTestingConnection = false
    @State private var connectionMessage: String?
    @State private var connectionIsError = false
    @State private var isLoadingModels = false
    @State private var availableModels: [String] = []
    @State private var modelMessage: String?
    @State private var modelIsError = false

    enum ConnectionStatus: Equatable {
        case untested
        case testing
        case connected(modelCount: Int)
        case failed(String)
    }

    @State private var connectionStatus: ConnectionStatus = .untested
    @State private var isPulseAnimating = false

    var body: some View {
        Form {
            Section(L10n.t(.translationSection)) {
                Toggle(L10n.t(.enableTranslation), isOn: $settings.translateEnabled)
                TextField(L10n.t(.targetLanguage), text: $settings.targetLanguage)
            }

            Section {
                LabeledContent(L10n.t(.provider)) {
                    Picker("", selection: $settings.apiProvider) {
                        ForEach(TranslationProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: settings.apiProvider) { _, newValue in
                        applyPreset(for: newValue)
                        connectionStatus = .untested
                    }
                }

                LabeledContent(L10n.t(.apiKey)) {
                    HStack(spacing: 8) {
                        SecureField("", text: $settings.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { loadModels() }

                        Button {
                            testConnection()
                        } label: {
                            if isTestingConnection {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(L10n.t(.testConnection), systemImage: "checkmark.circle")
                            }
                        }
                        .controlSize(.small)
                        .disabled(isTestingConnection)
                    }
                }

                LabeledContent(L10n.t(.baseURL)) {
                    TextField("", text: $settings.apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { loadModels() }
                }

                if let connectionMessage {
                    statusText(connectionMessage, isError: connectionIsError, successColor: .green)
                }

                Text(L10n.t(.apiKeyHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text(L10n.t(.apiConnection))
                    Spacer()
                    statusIndicator
                }
            }

            Section(L10n.t(.modelSelection)) {
                HStack(spacing: 8) {
                    Text(L10n.t(.model))
                    Spacer()
                    Picker("", selection: $settings.apiModel) {
                        if availableModels.isEmpty {
                            Text(settings.apiModel.isEmpty ? L10n.t(.modelsUnavailable) : settings.apiModel)
                                .tag(settings.apiModel)
                        } else {
                            ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(availableModels.isEmpty)

                    Button {
                        loadModels()
                    } label: {
                        if isLoadingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingModels)
                    .help(L10n.t(.refreshModels))
                }

                if let modelMessage {
                    statusText(modelMessage, isError: modelIsError, successColor: .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            isPulseAnimating = true
            if !availableModels.isEmpty {
                connectionStatus = .connected(modelCount: availableModels.count)
            } else if !settings.apiKey.isEmpty {
                loadModels()
            }
        }
        .onChange(of: settings.apiKey) { _, _ in
            connectionStatus = .untested
        }
        .onChange(of: settings.apiBaseURL) { _, _ in
            connectionStatus = .untested
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 5) {
            switch connectionStatus {
            case .untested:
                Circle()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(L10n.t(.connectionUntested))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .testing:
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
                Text(L10n.t(.testingConnection))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            case .connected(let count):
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .scaleEffect(isPulseAnimating ? 1.3 : 1.0)
                    .opacity(isPulseAnimating ? 0.6 : 1.0)
                    .animation(
                        isPulseAnimating ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default,
                        value: isPulseAnimating
                    )
                Text("\(L10n.t(.connectionOK)) (\(count))")
                    .font(.caption2)
                    .foregroundStyle(.green)
            case .failed:
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                Text(L10n.t(.connectionFailed))
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func statusText(_ text: String, isError: Bool, successColor: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.caption)
            Text(text)
                .font(.caption)
                .lineLimit(2)
        }
        .foregroundStyle(isError ? .red : successColor)
    }

    private func applyPreset(for provider: TranslationProvider) {
        settings.apiBaseURL = provider.defaultBaseURL
        settings.apiModel = provider.defaultModel
        availableModels = []
        connectionStatus = .untested
    }

    private func testConnection() {
        isTestingConnection = true
        connectionStatus = .testing
        connectionIsError = false
        connectionMessage = L10n.t(.testingConnection)

        Task {
            do {
                let models = try await fetchModels()
                apply(models: models)
                connectionIsError = false
                connectionMessage = "\(L10n.t(.connectionOK)) · \(models.count) models"
                connectionStatus = .connected(modelCount: models.count)
            } catch {
                connectionIsError = true
                connectionMessage = "\(L10n.t(.connectionFailed)): \(error.localizedDescription)"
                connectionStatus = .failed(error.localizedDescription)
            }
            isTestingConnection = false
        }
    }

    private func loadModels() {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        modelIsError = false
        modelMessage = L10n.t(.loadingModels)
        connectionStatus = .testing

        Task {
            do {
                let models = try await fetchModels()
                apply(models: models)
                modelIsError = false
                modelMessage = "\(L10n.t(.modelsLoaded)) · \(models.count)"
                connectionStatus = .connected(modelCount: models.count)
            } catch {
                modelIsError = true
                modelMessage = error.localizedDescription
                connectionStatus = .failed(error.localizedDescription)
            }
            isLoadingModels = false
        }
    }

    private func fetchModels() async throws -> [String] {
        let config = ConfigManager.shared.effectiveConfig
        let service = TranslationService(config: config, apiKey: settings.apiKey)
        return try await service.fetchModels()
    }

    private func apply(models: [String]) {
        availableModels = models
        if !models.isEmpty, !models.contains(settings.apiModel) {
            settings.apiModel = models[0]
        }
    }
}
