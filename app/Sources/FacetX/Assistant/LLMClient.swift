import Foundation

/// `@unchecked Sendable`: these cross the `AsyncThrowingStream` continuation
/// boundary in `DeepSeekClient.stream`, but producer and consumer are both
/// pinned to the main actor, and the payload is immutable value data — the
/// `[String: Any]` fields are the only reason the compiler can't infer
/// Sendable on its own.
struct LLMToolCall: @unchecked Sendable {
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
struct LLMResponse: @unchecked Sendable {
    let stop: LLMStopReason
    let text: String
    let reasoning: String
    let toolCalls: [LLMToolCall]
    let rawAssistantMessage: [String: Any]
    let inputTokens: Int
    let outputTokens: Int
    /// DeepSeek's automatic disk-based prefix cache: tokens billed at the
    /// cached rate vs. the full rate. Our append-only message history keeps
    /// a stable prefix turn to turn, so this is normally nonzero after the
    /// first message in a conversation.
    let cacheHitTokens: Int
    let cacheMissTokens: Int
}

/// Incremental events emitted while a streamed completion is in flight.
/// `.done` always arrives last and carries the same fully-assembled response
/// shape `send` used to return in one shot, so callers only branch on
/// streaming vs not at the call site, not throughout the agent loop.
enum LLMStreamEvent: @unchecked Sendable {
    case textDelta(String)
    case reasoningDelta(String)
    case done(LLMResponse)
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

    /// A tool call as it accumulates across streamed deltas: DeepSeek sends
    /// `function.arguments` as string fragments that only parse as JSON once
    /// fully concatenated.
    private struct StreamToolCallBuilder {
        var id = ""
        var name = ""
        var argumentsRaw = ""
    }

    func stream(system: String,
                messages: [[String: Any]],
                tools: [[String: Any]]) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty else { throw LLMClientError.missingKey }
                    var body: [String: Any] = [
                        "model": model,
                        "messages": [["role": "system", "content": system]] + messages,
                        "max_tokens": 16_000,
                        "parallel_tool_calls": true,
                        "thinking": ["type": thinkingEnabled ? "enabled" : "disabled"],
                        "stream": true,
                        "stream_options": ["include_usage": true],
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

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMClientError.malformedResponse
                    }
                    guard http.statusCode == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                        let error = json?["error"] as? [String: Any]
                        throw LLMClientError.api(
                            status: http.statusCode,
                            message: error?["message"] as? String ?? String(data: data, encoding: .utf8) ?? ""
                        )
                    }

                    var contentBuffer = ""
                    var reasoningBuffer = ""
                    var toolBuilders: [Int: StreamToolCallBuilder] = [:]
                    var finishReason: String?
                    var usage: [String: Any]?

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let chunkUsage = json["usage"] as? [String: Any] { usage = chunkUsage }
                        guard let choice = (json["choices"] as? [[String: Any]])?.first else { continue }
                        if let reason = choice["finish_reason"] as? String { finishReason = reason }
                        guard let delta = choice["delta"] as? [String: Any] else { continue }

                        if let piece = delta["content"] as? String, !piece.isEmpty {
                            contentBuffer += piece
                            continuation.yield(.textDelta(piece))
                        }
                        if let piece = delta["reasoning_content"] as? String, !piece.isEmpty {
                            reasoningBuffer += piece
                            continuation.yield(.reasoningDelta(piece))
                        }
                        if let calls = delta["tool_calls"] as? [[String: Any]] {
                            for callDelta in calls {
                                guard let index = callDelta["index"] as? Int else { continue }
                                var builder = toolBuilders[index] ?? StreamToolCallBuilder()
                                if let id = callDelta["id"] as? String { builder.id = id }
                                if let function = callDelta["function"] as? [String: Any] {
                                    if let name = function["name"] as? String { builder.name += name }
                                    if let arguments = function["arguments"] as? String { builder.argumentsRaw += arguments }
                                }
                                toolBuilders[index] = builder
                            }
                        }
                    }

                    let orderedIndices = toolBuilders.keys.sorted()
                    let toolCalls: [LLMToolCall] = orderedIndices.compactMap { index in
                        let builder = toolBuilders[index]!
                        guard !builder.id.isEmpty else { return nil }
                        let input = (try? JSONSerialization.jsonObject(with: Data(builder.argumentsRaw.utf8))) as? [String: Any] ?? [:]
                        return LLMToolCall(id: builder.id, name: builder.name, input: input)
                    }

                    var message: [String: Any] = ["role": "assistant", "content": contentBuffer]
                    if thinkingEnabled {
                        message["reasoning_content"] = reasoningBuffer
                    }
                    if !toolCalls.isEmpty {
                        message["tool_calls"] = orderedIndices.map { index -> [String: Any] in
                            let builder = toolBuilders[index]!
                            return [
                                "id": builder.id,
                                "type": "function",
                                "function": ["name": builder.name, "arguments": builder.argumentsRaw],
                            ]
                        }
                    }

                    let stop: LLMStopReason
                    switch finishReason {
                    case "tool_calls": stop = .toolUse
                    case "length": stop = .maxTokens
                    case "content_filter": stop = .refusal
                    default: stop = toolCalls.isEmpty ? .endTurn : .toolUse
                    }

                    continuation.yield(.done(LLMResponse(
                        stop: stop,
                        text: contentBuffer,
                        reasoning: thinkingEnabled ? reasoningBuffer : "",
                        toolCalls: toolCalls,
                        rawAssistantMessage: message,
                        inputTokens: usage?["prompt_tokens"] as? Int ?? 0,
                        outputTokens: usage?["completion_tokens"] as? Int ?? 0,
                        cacheHitTokens: usage?["prompt_cache_hit_tokens"] as? Int ?? 0,
                        cacheMissTokens: usage?["prompt_cache_miss_tokens"] as? Int ?? 0
                    )))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
