import Foundation

class TranslationService {
    private static let anthropicAPIVersion = "2023-06-01"

    let config: AppConfig
    let apiKey: String

    init(config: AppConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey
    }

    // MARK: - Translation

    func translateAbstract(
        id: String,
        abstract: String,
        cachedAbstractZh: String
    ) async throws -> String {
        if !cachedAbstractZh.isEmpty {
            print("Translation cache hit for paper \(id)")
            return cachedAbstractZh
        }

        let provider = config.translate.provider
        let targetLang = config.translate.target_language
        let abstractPrompt = "You are a professional academic translator. Translate the following paper abstract into \(targetLang). Preserve technical terms in English where appropriate. Return ONLY the translated text, no explanations."

        print("Translating paper abstract to \(targetLang) via \(provider.displayName)...")
        return try await chatCompletion(systemPrompt: abstractPrompt, userContent: abstract)
    }

    // MARK: - Model List

    func fetchModels() async throws -> [String] {
        let provider = config.translate.provider
        guard !apiKey.isEmpty else {
            throw TranslationError.noAPIKey
        }

        if provider == .anthropic {
            let model = config.translate.model.trimmingCharacters(in: .whitespacesAndNewlines)
            let selectedModel = model.isEmpty ? provider.defaultModel : model
            try await validateAnthropicConnection(model: selectedModel)
            return [selectedModel]
        }

        let url = try endpointURL(path: provider.modelsEndpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("\(provider.authHeaderValuePrefix)\(apiKey)", forHTTPHeaderField: provider.authHeaderName)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TranslationError.apiError(apiErrorMessage(data: data, response: response))
        }

        struct OpenAIModelsResponse: Decodable {
            struct Model: Decodable { var id: String }
            var data: [Model]
        }

        let result = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return result.data.map(\.id).sorted()
    }

    // MARK: - Core Chat Completion

    private func chatCompletion(systemPrompt: String, userContent: String) async throws -> String {
        let provider = config.translate.provider
        let model = config.translate.model

        guard !apiKey.isEmpty else {
            throw TranslationError.noAPIKey
        }

        let url = try endpointURL(path: provider.chatEndpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\(provider.authHeaderValuePrefix)\(apiKey)", forHTTPHeaderField: provider.authHeaderName)

        if provider.requiresVersionHeader {
            request.setValue(Self.anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")
        }

        let bodyData: Data
        switch provider {
        case .deepseek, .openai:
            bodyData = try buildOpenAIChatBody(model: model, system: systemPrompt, user: userContent)
        case .anthropic:
            bodyData = try buildAnthropicChatBody(model: model, system: systemPrompt, user: userContent)
        }

        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TranslationError.apiError(apiErrorMessage(data: data, response: response))
        }

        switch provider {
        case .deepseek, .openai:
            return try parseOpenAIChatResponse(data: data)
        case .anthropic:
            return try parseAnthropicChatResponse(data: data)
        }
    }

    private func endpointURL(path: String) throws -> URL {
        let trimmed = config.translate.base_url
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty,
              let base = URL(string: trimmed),
              let scheme = base.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              base.host != nil,
              let url = URL(string: "\(trimmed)\(path)") else {
            throw TranslationError.invalidBaseURL(config.translate.base_url)
        }
        return url
    }

    private func apiErrorMessage(data: Data, response: URLResponse) -> String {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return body?.isEmpty == false ? "API error \(status): \(body!)" : "API error \(status)"
    }

    private func validateAnthropicConnection(model: String) async throws {
        let provider = TranslationProvider.anthropic
        let url = try endpointURL(path: provider.chatEndpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: provider.authHeaderName)
        request.setValue(Self.anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try buildAnthropicChatBody(
            model: model,
            system: "You are validating an API connection.",
            user: "Reply with OK.",
            maxTokens: 1
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TranslationError.apiError(apiErrorMessage(data: data, response: response))
        }
        _ = try parseAnthropicChatResponse(data: data)
    }

    // MARK: - OpenAI-compatible request/response

    private func buildOpenAIChatBody(model: String, system: String, user: String) throws -> Data {
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.3,
            "max_tokens": 2048
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private func parseOpenAIChatResponse(data: Data) throws -> String {
        struct OpenAIChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { var content: String }
                var message: Message
            }
            var choices: [Choice]
        }
        let result = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        return result.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Anthropic request/response

    private func buildAnthropicChatBody(model: String, system: String, user: String, maxTokens: Int = 2048) throws -> Data {
        let payload: [String: Any] = [
            "model": model,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ],
            "max_tokens": maxTokens,
            "temperature": 0.3
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private func parseAnthropicChatResponse(data: Data) throws -> String {
        struct AnthropicChatResponse: Decodable {
            struct ContentBlock: Decodable {
                var type: String
                var text: String?
            }
            var content: [ContentBlock]
        }
        let result = try JSONDecoder().decode(AnthropicChatResponse.self, from: data)
        return result.content.first { $0.type == "text" }?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Errors

    enum TranslationError: Error, LocalizedError {
        case noAPIKey
        case invalidBaseURL(String)
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "API key not set — add it in Settings ▸ API"
            case .invalidBaseURL(let value):
                return "Invalid API base URL: \(value)"
            case .apiError(let message):
                return message
            }
        }
    }
}
