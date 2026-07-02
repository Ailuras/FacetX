import Foundation

/// One tool invocation requested by the model.
struct LLMToolCall {
    let id: String
    let name: String
    let input: [String: Any]
}

/// The outcome of executing one tool call.
struct LLMToolResult {
    let id: String
    let content: String
    let isError: Bool
}

enum LLMStopReason {
    case endTurn
    case toolUse
    /// Server paused mid-turn; re-send the same history to resume (Anthropic).
    case pauseTurn
    case refusal
    case maxTokens
}

/// Provider-agnostic view of one model response. `rawAssistantMessage` is the
/// provider-native assistant message, kept verbatim so the next request can
/// echo it losslessly (required for tool-use continuity on every provider).
struct LLMResponse {
    let stop: LLMStopReason
    let text: String
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
            return L10n.pick("No API key. Configure one in Settings → Integrations → LLM API.",
                             "未配置 API Key，请在 设置 → 集成 → 大模型 API 中填写。")
        case .invalidBaseURL(let value):
            return L10n.pick("Invalid LLM API base URL: \(value)",
                             "大模型 API 地址无效：\(value)")
        case .api(let status, let message):
            return "[\(status)] \(message)"
        case .malformedResponse:
            return L10n.pick("Malformed API response.", "API 返回格式异常。")
        }
    }
}

/// A chat-completions client for one provider. History entries are
/// provider-native dictionaries produced only by the same client's builder
/// methods, so each implementation controls its own wire format end to end.
///
/// MainActor-bound because the untyped payload dictionaries are not Sendable;
/// only URLSession's Data/URLRequest transfer crosses actors.
@MainActor
protocol LLMChatClient {
    /// Tools arrive in Anthropic-style shape ({name, description, input_schema});
    /// implementations convert to their wire format as needed.
    func send(system: String,
              messages: [[String: Any]],
              tools: [[String: Any]]) async throws -> LLMResponse

    func userMessage(_ text: String) -> [String: Any]
    func assistantMessage(_ response: LLMResponse) -> [String: Any]
    /// Tool results after a `toolUse` stop; may map to one message (Anthropic)
    /// or one per result (OpenAI-compatible).
    func toolResultMessages(_ results: [LLMToolResult]) -> [[String: Any]]
}

/// OpenAI-compatible chat-completions client — used for DeepSeek and OpenAI
/// (both speak `POST {base}/chat/completions` with function calling).
@MainActor
struct OpenAIChatClient: LLMChatClient {
    let provider: TranslationProvider
    let apiKey: String
    let model: String
    let baseURL: String
    let thinkingEnabled: Bool
    let reasoningEffort: AssistantReasoningEffort

    private func endpoint() throws -> URL {
        var root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") { root.removeLast() }
        guard let base = URL(string: root),
              let scheme = base.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              base.host != nil,
              base.query == nil,
              base.fragment == nil,
              let endpoint = URL(string: root + "/chat/completions") else {
            throw LLMClientError.invalidBaseURL(baseURL)
        }
        return endpoint
    }

    func send(system: String,
              messages: [[String: Any]],
              tools: [[String: Any]]) async throws -> LLMResponse {
        guard !apiKey.isEmpty else { throw LLMClientError.missingKey }

        var wireMessages: [[String: Any]] = [["role": "system", "content": system]]
        wireMessages.append(contentsOf: messages)

        var body: [String: Any] = [
            "model": model,
            "messages": wireMessages,
            "parallel_tool_calls": true,
        ]
        switch provider {
        case .deepseek:
            body["max_tokens"] = 8192
            body["thinking"] = ["type": thinkingEnabled ? "enabled" : "disabled"]
            if thinkingEnabled {
                body["reasoning_effort"] = reasoningEffort == .max || reasoningEffort == .xhigh
                    ? "max" : "high"
            }
        case .openai:
            body["max_completion_tokens"] = 8192
            if supportsOpenAIReasoning {
                body["reasoning_effort"] = thinkingEnabled ? openAIEffort : "none"
            }
        case .anthropic:
            break
        }
        if !tools.isEmpty {
            body["tools"] = tools.map { def in
                let function: [String: Any] = [
                    "name": def["name"] ?? "",
                    "description": def["description"] ?? "",
                    "parameters": def["input_schema"] ?? [:],
                ]
                return [
                    "type": "function",
                    "function": function,
                ] as [String: Any]
            }
        }

        var request = URLRequest(url: try endpoint())
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else {
            throw LLMClientError.malformedResponse
        }
        if http.statusCode != 200 {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = json?["error"] as? [String: Any]
            throw LLMClientError.api(
                status: http.statusCode,
                message: error?["message"] as? String
                    ?? String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMClientError.malformedResponse
        }

        guard let choice = (json["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else {
            throw LLMClientError.malformedResponse
        }

        // tool_calls carry arguments as a JSON *string* — parse per call.
        let toolCalls: [LLMToolCall] = (message["tool_calls"] as? [[String: Any]] ?? [])
            .compactMap { call in
                guard let id = call["id"] as? String,
                      let function = call["function"] as? [String: Any],
                      let name = function["name"] as? String else { return nil }
                let argsRaw = function["arguments"] as? String ?? "{}"
                let input = (try? JSONSerialization.jsonObject(
                    with: Data(argsRaw.utf8))) as? [String: Any] ?? [:]
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
        // Echo the provider's own message verbatim (content may be NSNull when
        // only tool_calls are present — JSONSerialization round-trips it fine).
        response.rawAssistantMessage
    }

    func toolResultMessages(_ results: [LLMToolResult]) -> [[String: Any]] {
        results.map { result in
            [
                "role": "tool",
                "tool_call_id": result.id,
                "content": result.isError ? "Error: \(result.content)" : result.content,
            ]
        }
    }

    private var supportsOpenAIReasoning: Bool {
        let value = model.lowercased()
        return value.hasPrefix("gpt-5")
            || value.hasPrefix("o1")
            || value.hasPrefix("o3")
            || value.hasPrefix("o4")
    }

    private var openAIEffort: String {
        switch reasoningEffort {
        case .max, .xhigh: return "xhigh"
        case .high: return "high"
        case .medium: return "medium"
        case .low: return "low"
        }
    }
}
