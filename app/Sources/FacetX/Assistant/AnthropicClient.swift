import Foundation

/// Anthropic Messages API client (used when the shared LLM API provider is
/// set to Anthropic). Content blocks are kept as untyped dictionaries so the
/// agent loop echoes them back verbatim across turns.
@MainActor
struct AnthropicClient: LLMChatClient {
    let apiKey: String
    let model: String
    let baseURL: String
    let thinkingEnabled: Bool
    let reasoningEffort: AssistantReasoningEffort

    private func endpoint() throws -> URL {
        var root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if root.isEmpty { root = "https://api.anthropic.com/v1" }
        while root.hasSuffix("/") { root.removeLast() }
        if !root.hasSuffix("/v1") { root += "/v1" }
        guard let base = URL(string: root),
              let scheme = base.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              base.host != nil,
              base.query == nil,
              base.fragment == nil,
              let endpoint = URL(string: root + "/messages") else {
            throw LLMClientError.invalidBaseURL(baseURL)
        }
        return endpoint
    }

    func send(system: String,
              messages: [[String: Any]],
              tools: [[String: Any]]) async throws -> LLMResponse {
        guard !apiKey.isEmpty else { throw LLMClientError.missingKey }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "messages": messages,
        ]
        if !tools.isEmpty {
            body["tools"] = tools
        }
        applyThinking(to: &body)

        var request = URLRequest(url: try endpoint())
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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

        guard let content = json["content"] as? [[String: Any]] else {
            throw LLMClientError.malformedResponse
        }

        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")

        let toolCalls: [LLMToolCall] = content.compactMap { block in
            guard block["type"] as? String == "tool_use",
                  let id = block["id"] as? String,
                  let name = block["name"] as? String else { return nil }
            return LLMToolCall(id: id, name: name,
                               input: block["input"] as? [String: Any] ?? [:])
        }

        let stop: LLMStopReason
        switch json["stop_reason"] as? String {
        case "tool_use": stop = .toolUse
        case "pause_turn": stop = .pauseTurn
        case "refusal": stop = .refusal
        case "max_tokens": stop = .maxTokens
        default: stop = .endTurn
        }

        let usage = json["usage"] as? [String: Any]
        return LLMResponse(
            stop: stop,
            text: text,
            toolCalls: toolCalls,
            rawAssistantMessage: ["role": "assistant", "content": content],
            inputTokens: usage?["input_tokens"] as? Int ?? 0,
            outputTokens: usage?["output_tokens"] as? Int ?? 0
        )
    }

    func userMessage(_ text: String) -> [String: Any] {
        ["role": "user", "content": text]
    }

    func assistantMessage(_ response: LLMResponse) -> [String: Any] {
        response.rawAssistantMessage
    }

    func toolResultMessages(_ results: [LLMToolResult]) -> [[String: Any]] {
        // Anthropic wants every result in ONE user message.
        let blocks: [[String: Any]] = results.map { result in
            var block: [String: Any] = [
                "type": "tool_result",
                "tool_use_id": result.id,
                "content": result.content,
            ]
            if result.isError { block["is_error"] = true }
            return block
        }
        return [["role": "user", "content": blocks]]
    }

    private func applyThinking(to body: inout [String: Any]) {
        let slug = model.lowercased()
        let isHaiku45 = slug.contains("haiku-4-5")
        let isSonnet5 = slug.contains("sonnet-5")
        let supportsEffort = !isHaiku45

        if thinkingEnabled {
            if isHaiku45 {
                body["thinking"] = [
                    "type": "enabled",
                    "budget_tokens": anthropicThinkingBudget,
                    "display": "omitted",
                ] as [String: Any]
            } else {
                body["thinking"] = ["type": "adaptive", "display": "omitted"]
            }
        } else if isSonnet5 {
            body["thinking"] = ["type": "disabled"]
        }

        if supportsEffort {
            body["output_config"] = ["effort": reasoningEffort.rawValue]
        }
    }

    private var anthropicThinkingBudget: Int {
        switch reasoningEffort {
        case .low: return 2_048
        case .medium: return 4_096
        case .high: return 8_192
        case .xhigh: return 12_288
        case .max: return 15_000
        }
    }
}
