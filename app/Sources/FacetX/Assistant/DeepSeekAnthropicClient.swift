import Foundation

/// DeepSeek's Anthropic-compatible endpoint. It intentionally has its own
/// adapter because its supported fields differ from Anthropic's native API.
@MainActor
struct DeepSeekAnthropicClient: LLMChatClient {
    let apiKey: String
    let model: String
    let baseURL: String
    let thinkingEnabled: Bool
    let reasoningEffort: AssistantReasoningEffort

    func send(system: String,
              messages: [[String: Any]],
              tools: [[String: Any]]) async throws -> LLMResponse {
        guard !apiKey.isEmpty else { throw LLMClientError.missingKey }
        let thinking: [String: Any] = thinkingEnabled
            ? ["type": "enabled", "budget_tokens": 16_000]
            : ["type": "disabled"]
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16_000,
            "system": system,
            "messages": messages,
            "thinking": thinking,
        ]
        if thinkingEnabled {
            body["output_config"] = ["effort": deepSeekEffort]
        }
        if !tools.isEmpty { body["tools"] = tools }

        var request = URLRequest(url: try endpoint())
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw LLMClientError.malformedResponse
        }

        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
        let reasoning = content
            .filter { $0["type"] as? String == "thinking" }
            .compactMap { $0["thinking"] as? String }
            .joined(separator: "\n")
        let toolCalls: [LLMToolCall] = content.compactMap { block in
            guard block["type"] as? String == "tool_use",
                  let id = block["id"] as? String,
                  let name = block["name"] as? String else { return nil }
            return LLMToolCall(id: id, name: name, input: block["input"] as? [String: Any] ?? [:])
        }
        let stop: LLMStopReason
        switch json["stop_reason"] as? String {
        case "tool_use": stop = .toolUse
        case "pause_turn": stop = .pauseTurn
        case "refusal": stop = .refusal
        case "max_tokens": stop = .maxTokens
        default: stop = toolCalls.isEmpty ? .endTurn : .toolUse
        }
        let usage = json["usage"] as? [String: Any]
        return LLMResponse(
            stop: stop,
            text: text,
            reasoning: reasoning,
            toolCalls: toolCalls,
            rawAssistantMessages: [["role": "assistant", "content": content]],
            inputTokens: usage?["input_tokens"] as? Int ?? 0,
            outputTokens: usage?["output_tokens"] as? Int ?? 0
        )
    }

    func userMessage(_ text: String) -> [String: Any] { ["role": "user", "content": text] }
    func assistantMessages(_ response: LLMResponse) -> [[String: Any]] { response.rawAssistantMessages }
    func toolResultMessages(_ results: [LLMToolResult]) -> [[String: Any]] {
        let blocks: [[String: Any]] = results.map {
            ["type": "tool_result", "tool_use_id": $0.id,
             "content": $0.isError ? "Error: \($0.content)" : $0.content]
        }
        return [["role": "user", "content": blocks]]
    }

    private var deepSeekEffort: String {
        reasoningEffort == .max || reasoningEffort == .xhigh ? "max" : "high"
    }

    private func endpoint() throws -> URL {
        var root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") { root.removeLast() }
        if !root.hasSuffix("/anthropic") && !root.hasSuffix("/anthropic/v1") {
            root += "/anthropic"
        }
        if !root.hasSuffix("/v1") { root += "/v1" }
        guard let base = URL(string: root),
              let scheme = base.scheme?.lowercased(),
              ["http", "https"].contains(scheme), base.host != nil,
              base.query == nil, base.fragment == nil,
              let url = URL(string: root + "/messages") else {
            throw LLMClientError.invalidBaseURL(baseURL)
        }
        return url
    }
}
