import Foundation

/// Minimal native client for the Anthropic Messages API (there is no official
/// Swift SDK, so this speaks raw HTTP per the documented wire format).
///
/// Payloads are untyped `[String: Any]` dictionaries on purpose: the agent
/// loop must echo assistant content blocks (text / tool_use / thinking) back
/// verbatim on the next turn, and a lossless passthrough is simpler and safer
/// than mirroring every block type in Codable structs.
///
/// MainActor-bound because those dictionaries are not Sendable; the only work
/// that crosses actors is URLSession's own Data/URLRequest transfer, and the
/// await never blocks the main thread.
@MainActor
struct AnthropicClient {
    struct Response {
        let content: [[String: Any]]
        let stopReason: String
        let model: String
        let inputTokens: Int
        let outputTokens: Int

        /// Concatenated text blocks.
        var text: String {
            content
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
        }

        var toolUses: [(id: String, name: String, input: [String: Any])] {
            content.compactMap { block in
                guard block["type"] as? String == "tool_use",
                      let id = block["id"] as? String,
                      let name = block["name"] as? String else { return nil }
                return (id, name, block["input"] as? [String: Any] ?? [:])
            }
        }
    }

    enum ClientError: LocalizedError {
        case missingKey
        case api(status: Int, type: String, message: String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return L10n.pick("No API key. Add one in Settings → Integrations.",
                                 "未配置 API Key，请在 设置 → 集成 中添加。")
            case .api(let status, let type, let message):
                return "[\(status) \(type)] \(message)"
            case .malformedResponse:
                return L10n.pick("Malformed API response.", "API 返回格式异常。")
            }
        }
    }

    let apiKey: String
    let model: String
    let baseURL: String

    private var endpoint: URL {
        let base = baseURL.trimmingCharacters(in: .whitespaces)
        let root = base.isEmpty ? "https://api.anthropic.com" : base
        return URL(string: root.hasSuffix("/") ? "\(root)v1/messages" : "\(root)/v1/messages")!
    }

    /// One non-streaming Messages API call. The caller owns the agent loop:
    /// on `stop_reason == "tool_use"` it executes the tools and calls again
    /// with the assistant content + tool_result blocks appended.
    func send(system: String,
              messages: [[String: Any]],
              tools: [[String: Any]],
              maxTokens: Int = 16000) async throws -> Response {
        guard !apiKey.isEmpty else { throw ClientError.missingKey }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages,
        ]
        if !tools.isEmpty {
            body["tools"] = tools
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else {
            throw ClientError.malformedResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.malformedResponse
        }

        if http.statusCode != 200 {
            let error = json["error"] as? [String: Any]
            throw ClientError.api(
                status: http.statusCode,
                type: error?["type"] as? String ?? "unknown_error",
                message: error?["message"] as? String ?? String(data: data, encoding: .utf8) ?? ""
            )
        }

        guard let content = json["content"] as? [[String: Any]] else {
            throw ClientError.malformedResponse
        }
        let usage = json["usage"] as? [String: Any]
        return Response(
            content: content,
            stopReason: json["stop_reason"] as? String ?? "end_turn",
            model: json["model"] as? String ?? model,
            inputTokens: usage?["input_tokens"] as? Int ?? 0,
            outputTokens: usage?["output_tokens"] as? Int ?? 0
        )
    }
}
