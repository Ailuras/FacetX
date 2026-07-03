import Foundation

/// DeepSeek-only text translation and model discovery.
final class TranslationService {
    let config: AppConfig
    let apiKey: String

    init(config: AppConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey
    }

    func translateAbstract(
        id: String,
        abstract: String,
        cachedAbstractZh: String
    ) async throws -> String {
        if !cachedAbstractZh.isEmpty {
            print("Translation cache hit for paper \(id)")
            return cachedAbstractZh
        }

        let target = config.translate.target_language
        let prompt = "You are a professional academic translator. Translate the following paper abstract into \(target). Preserve technical terms in English where appropriate. Return ONLY the translated text, no explanations."
        print("Translating paper abstract to \(target) via DeepSeek...")
        return try await chatCompletion(systemPrompt: prompt, userContent: abstract)
    }

    func translateText(_ text: String) async throws -> String {
        let target = config.translate.target_language
        let prompt = "You are a professional academic translator. Translate the following text into \(target). Preserve technical terms in English where appropriate. Return ONLY the translated text, no explanations."
        print("Translating text to \(target) via DeepSeek...")
        return try await chatCompletion(systemPrompt: prompt, userContent: text)
    }

    func fetchModels() async throws -> [String] {
        guard !apiKey.isEmpty else { throw TranslationError.noAPIKey }
        var request = URLRequest(url: try endpointURL(path: "/models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TranslationError.apiError(apiErrorMessage(data: data, response: response))
        }

        struct ModelsResponse: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        return try JSONDecoder().decode(ModelsResponse.self, from: data).data.map(\.id).sorted()
    }

    private func chatCompletion(systemPrompt: String, userContent: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.noAPIKey }
        var request = URLRequest(url: try endpointURL(path: "/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.translate.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent],
            ],
            "thinking": ["type": "disabled"],
            "temperature": 0.3,
            "max_tokens": 2_048,
        ] as [String: Any])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TranslationError.apiError(apiErrorMessage(data: data, response: response))
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let result = try JSONDecoder().decode(ChatResponse.self, from: data)
        return result.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func endpointURL(path: String) throws -> URL {
        var root = config.translate.base_url.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") { root.removeLast() }
        guard !root.isEmpty,
              let base = URL(string: root),
              let scheme = base.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              base.host != nil,
              base.query == nil,
              base.fragment == nil,
              let url = URL(string: root + path) else {
            throw TranslationError.invalidBaseURL(config.translate.base_url)
        }
        return url
    }

    private func apiErrorMessage(data: Data, response: URLResponse) -> String {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return body?.isEmpty == false ? "DeepSeek API error \(status): \(body!)" : "DeepSeek API error \(status)"
    }

    enum TranslationError: LocalizedError {
        case noAPIKey
        case invalidBaseURL(String)
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return L10n.pick("DeepSeek API key is not configured.", "未配置 DeepSeek API Key。")
            case .invalidBaseURL(let value):
                return L10n.pick("Invalid DeepSeek API base URL: \(value)", "DeepSeek API 地址无效：\(value)")
            case .apiError(let message):
                return message
            }
        }
    }
}
