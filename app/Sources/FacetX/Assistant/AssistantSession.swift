import Foundation
import SwiftUI

/// One chat transcript entry as rendered in the UI.
struct AssistantEntry: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
        case tool(name: String)
        case error
    }

    let id = UUID()
    let role: Role
    var text: String
    var mentions: [AssistantItemMention] = []
}

/// Drives the assistant conversation: keeps the UI transcript, the raw API
/// message history (content blocks echoed verbatim, as tool use requires),
/// and runs the agent loop — send → execute tool calls → send results →
/// repeat until the model stops calling tools.
@MainActor
final class AssistantSession: ObservableObject {
    @Published private(set) var entries: [AssistantEntry] = []
    @Published private(set) var isBusy = false
    @Published private(set) var totalInputTokens = 0
    @Published private(set) var totalOutputTokens = 0

    private var apiMessages: [[String: Any]] = []
    /// Wire format owner of `apiMessages`; switching providers mid-chat resets
    /// the API history (the transcript stays visible, context restarts).
    private var historyProvider: String = ""
    private var toolbox: AgentToolbox?
    private weak var projectStore: ProjectStore?
    private var configured = false

    private static let maxLoopIterations = 12

    func configure(eventKit: EventKitService, store: ProjectStore, settings: AppSettings) {
        guard !configured else { return }
        configured = true
        self.projectStore = store
        self.toolbox = AgentToolbox(eventKit: eventKit, projectStore: store, settings: settings)
    }

    // ── Shared LLM API config (Settings → Integrations → LLM API) ────────────

    /// Build the wire client for whichever provider the shared config selects:
    /// DeepSeek/OpenAI speak OpenAI chat-completions, Anthropic its own format.
    private func makeClient() -> LLMChatClient {
        let lit = LibrarySettings.shared
        let provider = lit.apiProvider
        let apiKey = lit.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredBase = lit.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredModel = lit.apiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = configuredBase.isEmpty ? provider.defaultBaseURL : configuredBase
        let model = configuredModel.isEmpty ? provider.defaultModel : configuredModel
        let effort = provider.supportedAssistantEfforts.contains(lit.assistantReasoningEffort)
            ? lit.assistantReasoningEffort
            : provider.defaultAssistantEffort
        switch provider {
        case .anthropic:
            return AnthropicClient(
                apiKey: apiKey,
                model: model,
                baseURL: base,
                thinkingEnabled: lit.assistantThinkingEnabled,
                reasoningEffort: effort
            )
        case .deepseek, .openai:
            return OpenAIChatClient(
                provider: provider,
                apiKey: apiKey,
                model: model,
                baseURL: base,
                thinkingEnabled: lit.assistantThinkingEnabled,
                reasoningEffort: effort
            )
        }
    }

    func clear() {
        entries.removeAll()
        apiMessages.removeAll()
        historyProvider = ""
        totalInputTokens = 0
        totalOutputTokens = 0
    }

    func send(_ text: String, mentions: [AssistantItemMention] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !mentions.isEmpty, !isBusy else { return }
        let visibleText = trimmed.isEmpty
            ? L10n.pick("Review the referenced items.", "查看这些提及的项目条目。")
            : trimmed
        entries.append(AssistantEntry(role: .user, text: visibleText, mentions: mentions))
        isBusy = true
        Task {
            await runLoop(userText: promptText(trimmed, mentions: mentions))
            isBusy = false
        }
    }

    private func promptText(_ text: String, mentions: [AssistantItemMention]) -> String {
        guard !mentions.isEmpty else { return text }
        let objects = mentions.map(\.promptObject)
        let data = try? JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys])
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let request = text.isEmpty ? "Review the referenced items." : text
        return """
        The user explicitly referenced these exact FacetX items. Titles can be duplicated; use reference_id whenever a tool accepts one.
        <facetx_references>\(json)</facetx_references>
        <user_request>\(request)</user_request>
        """
    }

    // ── Agent loop ───────────────────────────────────────────────────────────

    private func runLoop(userText: String) async {
        guard let toolbox else { return }
        let client = makeClient()
        let tools = toolbox.definitions
        let system = buildSystemPrompt()

        let providerKey = LibrarySettings.shared.apiProvider.rawValue
        if providerKey != historyProvider {
            apiMessages.removeAll()
            historyProvider = providerKey
        }
        apiMessages.append(client.userMessage(userText))

        for _ in 0..<Self.maxLoopIterations {
            let response: LLMResponse
            do {
                response = try await client.send(system: system,
                                                 messages: apiMessages,
                                                 tools: tools)
            } catch {
                entries.append(AssistantEntry(role: .error, text: error.localizedDescription))
                return
            }

            totalInputTokens += response.inputTokens
            totalOutputTokens += response.outputTokens

            // Echo the assistant message verbatim in the provider's own format.
            apiMessages.append(client.assistantMessage(response))

            let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                entries.append(AssistantEntry(role: .assistant, text: text))
            }

            switch response.stop {
            case .toolUse:
                guard !response.toolCalls.isEmpty else {
                    entries.append(AssistantEntry(
                        role: .error,
                        text: L10n.pick("The model returned an invalid tool request.",
                                        "模型返回了无效的工具调用。")))
                    return
                }
                var results: [LLMToolResult] = []
                for call in response.toolCalls {
                    entries.append(AssistantEntry(role: .tool(name: call.name),
                                                  text: toolSummary(call.name, call.input)))
                    let (result, isError) = await toolbox.execute(name: call.name, input: call.input)
                    results.append(LLMToolResult(id: call.id, content: result, isError: isError))
                }
                apiMessages.append(contentsOf: client.toolResultMessages(results))
                continue

            case .pauseTurn:
                // Server-side pause: re-send as-is to resume.
                continue

            case .refusal:
                entries.append(AssistantEntry(
                    role: .error,
                    text: L10n.pick("The model declined this request.", "模型拒绝了这次请求。")))
                return

            case .maxTokens:
                entries.append(AssistantEntry(
                    role: .error,
                    text: L10n.pick("Response truncated (max tokens).", "回复因长度限制被截断。")))
                return

            case .endTurn:
                return
            }
        }

        entries.append(AssistantEntry(
            role: .error,
            text: L10n.pick("Stopped after too many tool rounds.", "工具调用轮数过多，已停止。")))
    }

    /// Short human-readable line shown under a tool-call chip.
    private func toolSummary(_ name: String, _ input: [String: Any]) -> String {
        let interesting = ["project", "title", "query", "scope", "paper_id", "item_id", "date", "due_date", "mode"]
        let parts = interesting.compactMap { key -> String? in
            guard let value = input[key] else { return nil }
            return "\(key): \(value)"
        }
        return parts.joined(separator: " · ")
    }

    // ── System prompt ────────────────────────────────────────────────────────

    private func buildSystemPrompt() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd (EEEE)"
        fmt.locale = Locale(identifier: "en_US")
        let today = fmt.string(from: Date())
        let projectNames = projectStore?.activeProjects.map(\.name).joined(separator: ", ") ?? ""
        let language = L10n.language == "zh"
            ? "Respond in Chinese (中文) unless the user writes in another language."
            : "Respond in the user's language."

        return """
        You are the built-in assistant of FacetX, a macOS app that organizes Apple \
        Calendar and Reminders items into projects (an item belongs to a project when \
        its title starts with "ProjectPrefix: ") and manages an academic literature \
        library with local PDFs.

        Today is \(today). Active projects: \(projectNames.isEmpty ? "(none yet)" : projectNames).

        Use the tools to read and change the user's real data:
        - Turning a plan into concrete work: list_projects and list_items first, then \
        create tasks/events one per item; put timed appointments in events, action \
        items in tasks. Summarize what you created at the end.
        - Saving reference material or a written plan: create_note with markdown.
        - Papers: list_papers to find ids; read_paper (abstract first, then full_text \
        in page chunks for long PDFs); when the user asks for a summary, offer to \
        save it with save_paper_note.

        Rules: never invent project names — resolve them via list_projects. Check \
        list_items before creating to avoid duplicates. Ask before deleting or bulk \
        changes (you have no delete tool; say so if asked). Dates you pass to tools \
        are in the user's local timezone. Keep answers concise and lead with the \
        outcome. \(language)
        """
    }
}
