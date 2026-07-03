import Foundation

struct LLMToolCall {
    let id: String
    let name: String
    let input: [String: Any]
}

struct LLMToolResult {
    let id: String
    let content: String
    let isError: Bool
}

enum LLMStopReason {
    case endTurn
    case toolUse
    case refusal
    case maxTokens
}

/// One DeepSeek response plus the original assistant message that must be
/// replayed unchanged when a thinking turn calls tools.
struct LLMResponse {
    let stop: LLMStopReason
    let text: String
    let reasoning: String
    let toolCalls: [LLMToolCall]
    let rawAssistantMessage: [String: Any]
    let inputTokens: Int
    let outputTokens: Int
}

enum LLMClientError: LocalizedError {
    case missingKey
    case invalidBaseURL(String)
    case api(status: Int, message: String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return L10n.pick(
                "Configure a DeepSeek API key in Settings → Integrations.",
                "请在 设置 → 集成 中配置 DeepSeek API Key。"
            )
        case .invalidBaseURL(let value):
            return L10n.pick("Invalid DeepSeek API base URL: \(value)", "DeepSeek API 地址无效：\(value)")
        case .api(let status, let message):
            return "[\(status)] \(message)"
        case .malformedResponse:
            return L10n.pick("Malformed DeepSeek API response.", "DeepSeek API 返回格式异常。")
        }
    }
}

@MainActor
struct DeepSeekClient {
    let apiKey: String
    let model: String
    let baseURL: String
    let thinkingEnabled: Bool
    let reasoningEffort: AssistantReasoningEffort

    func send(system: String,
              messages: [[String: Any]],
              tools: [[String: Any]]) async throws -> LLMResponse {
        guard !apiKey.isEmpty else { throw LLMClientError.missingKey }
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system]] + messages,
            "max_tokens": 16_000,
            "parallel_tool_calls": true,
            "thinking": ["type": thinkingEnabled ? "enabled" : "disabled"],
        ]
        if thinkingEnabled {
            body["reasoning_effort"] = reasoningEffort.rawValue
        }
        if !tools.isEmpty {
            body["tools"] = tools.map { definition in
                [
                    "type": "function",
                    "function": [
                        "name": definition["name"] ?? "",
                        "description": definition["description"] ?? "",
                        "parameters": definition["input_schema"] ?? [:],
                    ],
                ] as [String: Any]
            }
        }

        var request = URLRequest(url: try endpoint())
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMClientError.malformedResponse
        }
        guard http.statusCode == 200 else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = json?["error"] as? [String: Any]
            throw LLMClientError.api(
                status: http.statusCode,
                message: error?["message"] as? String ?? String(data: data, encoding: .utf8) ?? ""
            )
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else {
            throw LLMClientError.malformedResponse
        }

        let toolCalls: [LLMToolCall] = (message["tool_calls"] as? [[String: Any]] ?? [])
            .compactMap { call in
                guard let id = call["id"] as? String,
                      let function = call["function"] as? [String: Any],
                      let name = function["name"] as? String else { return nil }
                let raw = function["arguments"] as? String ?? "{}"
                let input = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
                return LLMToolCall(id: id, name: name, input: input)
            }

        let stop: LLMStopReason
        switch choice["finish_reason"] as? String {
        case "tool_calls": stop = .toolUse
        case "length": stop = .maxTokens
        case "content_filter": stop = .refusal
        default: stop = toolCalls.isEmpty ? .endTurn : .toolUse
        }
        let usage = json["usage"] as? [String: Any]
        return LLMResponse(
            stop: stop,
            text: message["content"] as? String ?? "",
            reasoning: thinkingEnabled ? (message["reasoning_content"] as? String ?? "") : "",
            toolCalls: toolCalls,
            rawAssistantMessage: message,
            inputTokens: usage?["prompt_tokens"] as? Int ?? 0,
            outputTokens: usage?["completion_tokens"] as? Int ?? 0
        )
    }

    func userMessage(_ text: String) -> [String: Any] {
        ["role": "user", "content": text]
    }

    func assistantMessage(_ response: LLMResponse) -> [String: Any] {
        response.rawAssistantMessage
    }

    func toolResultMessages(_ results: [LLMToolResult]) -> [[String: Any]] {
        results.map {
            [
                "role": "tool",
                "tool_call_id": $0.id,
                "content": $0.isError ? "Error: \($0.content)" : $0.content,
            ]
        }
    }

    private func endpoint() throws -> URL {
        var root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") { root.removeLast() }
        guard let base = URL(string: root),
              let scheme = base.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              base.host != nil,
              base.query == nil,
              base.fragment == nil,
              let url = URL(string: root + "/chat/completions") else {
            throw LLMClientError.invalidBaseURL(baseURL)
        }
        return url
    }
}
