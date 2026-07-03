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
    case pauseTurn
    case refusal
    case maxTokens
}

/// Provider-neutral response plus the provider-native items that must be
/// replayed unchanged for tool and reasoning continuity.
struct LLMResponse {
    let stop: LLMStopReason
    let text: String
    let reasoning: String
    let toolCalls: [LLMToolCall]
    let rawAssistantMessages: [[String: Any]]
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
            return L10n.pick("Invalid LLM API base URL: \(value)", "大模型 API 地址无效：\(value)")
        case .api(let status, let message): return "[\(status)] \(message)"
        case .malformedResponse: return L10n.pick("Malformed API response.", "API 返回格式异常。")
        }
    }
}

@MainActor
protocol LLMChatClient {
    func send(system: String,
              messages: [[String: Any]],
              tools: [[String: Any]]) async throws -> LLMResponse
    func userMessage(_ text: String) -> [String: Any]
    func assistantMessages(_ response: LLMResponse) -> [[String: Any]]
    func toolResultMessages(_ results: [LLMToolResult]) -> [[String: Any]]
}

// MARK: - DeepSeek OpenAI-compatible Chat Completions

@MainActor
struct DeepSeekOpenAIClient: LLMChatClient {
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
            body["reasoning_effort"] = reasoningEffort == .max || reasoningEffort == .xhigh
                ? "max" : "high"
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

        let json = try await postJSON(body, to: endpoint(), bearer: apiKey)
        guard let choice = (json["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else {
            throw LLMClientError.malformedResponse
        }
        let toolCalls = parseOpenAIToolCalls(message["tool_calls"])
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
            rawAssistantMessages: [message],
            inputTokens: usage?["prompt_tokens"] as? Int ?? 0,
            outputTokens: usage?["completion_tokens"] as? Int ?? 0
        )
    }

    func userMessage(_ text: String) -> [String: Any] { ["role": "user", "content": text] }
    func assistantMessages(_ response: LLMResponse) -> [[String: Any]] { response.rawAssistantMessages }
    func toolResultMessages(_ results: [LLMToolResult]) -> [[String: Any]] {
        results.map {
            ["role": "tool", "tool_call_id": $0.id,
             "content": $0.isError ? "Error: \($0.content)" : $0.content]
        }
    }

    private func endpoint() throws -> URL {
        try endpointURL(baseURL: baseURL, path: "/chat/completions")
    }
}

// MARK: - OpenAI Responses API

@MainActor
struct OpenAIResponsesClient: LLMChatClient {
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
            "instructions": system,
            "input": messages,
            "max_output_tokens": 16_000,
            "parallel_tool_calls": true,
            "store": false,
        ]
        if supportsReasoning {
            if thinkingEnabled {
                body["reasoning"] = ["effort": openAIEffort, "summary": "auto"]
                body["include"] = ["reasoning.encrypted_content"]
            } else {
                body["reasoning"] = ["effort": "none"]
            }
        }
        if !tools.isEmpty {
            body["tools"] = tools.map { definition in
                [
                    "type": "function",
                    "name": definition["name"] ?? "",
                    "description": definition["description"] ?? "",
                    "parameters": definition["input_schema"] ?? [:],
                    "strict": true,
                ] as [String: Any]
            }
        }

        let json = try await postJSON(body, to: endpoint(), bearer: apiKey)
        guard let output = json["output"] as? [[String: Any]] else {
            throw LLMClientError.malformedResponse
        }
        let text = output.compactMap { item -> String? in
            guard item["type"] as? String == "message" else { return nil }
            return (item["content"] as? [[String: Any]])?
                .compactMap { $0["type"] as? String == "output_text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
        }.joined(separator: "\n")
        let reasoning = output.compactMap { item -> String? in
            guard item["type"] as? String == "reasoning" else { return nil }
            return (item["summary"] as? [[String: Any]])?
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
        }.joined(separator: "\n")
        let toolCalls: [LLMToolCall] = output.compactMap { item in
            guard item["type"] as? String == "function_call",
                  let id = item["call_id"] as? String,
                  let name = item["name"] as? String else { return nil }
            let raw = item["arguments"] as? String ?? "{}"
            let input = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
            return LLMToolCall(id: id, name: name, input: input)
        }
        let incompleteReason = (json["incomplete_details"] as? [String: Any])?["reason"] as? String
        let stop: LLMStopReason = !toolCalls.isEmpty
            ? .toolUse
            : (incompleteReason == "max_output_tokens" ? .maxTokens : .endTurn)
        let usage = json["usage"] as? [String: Any]
        return LLMResponse(
            stop: stop,
            text: text,
            reasoning: reasoning,
            toolCalls: toolCalls,
            rawAssistantMessages: output,
            inputTokens: usage?["input_tokens"] as? Int ?? 0,
            outputTokens: usage?["output_tokens"] as? Int ?? 0
        )
    }

    func userMessage(_ text: String) -> [String: Any] {
        ["role": "user", "content": text]
    }

    func assistantMessages(_ response: LLMResponse) -> [[String: Any]] {
        response.rawAssistantMessages
    }

    func toolResultMessages(_ results: [LLMToolResult]) -> [[String: Any]] {
        results.map {
            ["type": "function_call_output", "call_id": $0.id,
             "output": $0.isError ? "Error: \($0.content)" : $0.content]
        }
    }

    private func endpoint() throws -> URL { try endpointURL(baseURL: baseURL, path: "/responses") }

    private var supportsReasoning: Bool {
        let value = model.lowercased()
        return value.hasPrefix("gpt-5") || value.hasPrefix("o1")
            || value.hasPrefix("o3") || value.hasPrefix("o4")
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

@MainActor
private func endpointURL(baseURL: String, path: String) throws -> URL {
    var root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    while root.hasSuffix("/") { root.removeLast() }
    guard let base = URL(string: root),
          let scheme = base.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          base.host != nil, base.query == nil, base.fragment == nil,
          let endpoint = URL(string: root + path) else {
        throw LLMClientError.invalidBaseURL(baseURL)
    }
    return endpoint
}

@MainActor
private func postJSON(_ body: [String: Any], to url: URL, bearer: String) async throws -> [String: Any] {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 300
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw LLMClientError.malformedResponse }
    guard http.statusCode == 200 else {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        throw LLMClientError.api(
            status: http.statusCode,
            message: error?["message"] as? String ?? String(data: data, encoding: .utf8) ?? ""
        )
    }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw LLMClientError.malformedResponse
    }
    return json
}

@MainActor
private func parseOpenAIToolCalls(_ value: Any?) -> [LLMToolCall] {
    (value as? [[String: Any]] ?? []).compactMap { call in
        guard let id = call["id"] as? String,
              let function = call["function"] as? [String: Any],
              let name = function["name"] as? String else { return nil }
        let raw = function["arguments"] as? String ?? "{}"
        let input = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
        return LLMToolCall(id: id, name: name, input: input)
    }
}
