import Foundation
import SwiftUI

/// One chat transcript entry as rendered in the UI.
struct AssistantEntry: Identifiable, Equatable, Codable {
    enum Role: Equatable, Codable {
        case user
        case assistant
        case reasoning
        case tool(name: String)
        case error
    }

    let id: UUID
    let role: Role
    var text: String
    var mentions: [AssistantItemMention] = []

    init(id: UUID = UUID(), role: Role, text: String, mentions: [AssistantItemMention] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.mentions = mentions
    }
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
    @Published private(set) var conversations: [AssistantConversationSummary] = []
    @Published private(set) var activeConversationID = UUID()

    private var apiMessages: [[String: Any]] = []
    private var toolbox: AgentToolbox?
    private weak var projectStore: ProjectStore?
    private var configured = false
    private let conversationStore = AssistantConversationStore()
    private var conversationCreatedAt = Date()

    private static let maxLoopIterations = 12

    init() {
        refreshConversationList()
        if let latest = conversationStore.records.first {
            restore(latest)
        }
    }

    func configure(eventKit: EventKitService, store: ProjectStore, settings: AppSettings) {
        guard !configured else { return }
        configured = true
        self.projectStore = store
        self.toolbox = AgentToolbox(eventKit: eventKit, projectStore: store, settings: settings)
        registerVisibleReferences()
    }

    // ── DeepSeek API config (Settings → Integrations) ───────────────────────

    private func makeClient() -> DeepSeekClient {
        let lit = LibrarySettings.shared
        let apiKey = lit.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredBase = lit.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredModel = lit.apiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = configuredBase.isEmpty ? DeepSeekAPI.defaultBaseURL : configuredBase
        let model = configuredModel.isEmpty ? DeepSeekAPI.defaultModel : configuredModel
        let effort = DeepSeekAPI.supportedAssistantEfforts.contains(lit.assistantReasoningEffort)
            ? lit.assistantReasoningEffort
            : .high
        return DeepSeekClient(
            apiKey: apiKey,
            model: model,
            baseURL: base,
            thinkingEnabled: lit.assistantThinkingEnabled,
            reasoningEffort: effort
        )
    }

    func newConversation() {
        guard !isBusy else { return }
        persistCurrentConversation()
        activeConversationID = UUID()
        conversationCreatedAt = Date()
        entries.removeAll()
        apiMessages.removeAll()
        totalInputTokens = 0
        totalOutputTokens = 0
    }

    func openConversation(_ id: UUID) {
        guard !isBusy, id != activeConversationID,
              let record = conversationStore.record(id: id) else { return }
        persistCurrentConversation()
        restore(record)
    }

    func deleteCurrentConversation() {
        guard !isBusy else { return }
        conversationStore.delete(id: activeConversationID)
        refreshConversationList()
        if let next = conversationStore.records.first {
            restore(next)
        } else {
            activeConversationID = UUID()
            conversationCreatedAt = Date()
            entries = []
            apiMessages = []
            totalInputTokens = 0
            totalOutputTokens = 0
        }
    }

    func send(_ text: String, mentions: [AssistantItemMention] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !mentions.isEmpty, !isBusy else { return }
        let visibleText = trimmed.isEmpty
            ? L10n.pick("Review the referenced items.", "查看这些提及的项目条目。")
            : trimmed
        entries.append(AssistantEntry(role: .user, text: visibleText, mentions: mentions))
        toolbox?.registerReferences(mentions)
        persistCurrentConversation()
        isBusy = true
        Task {
            await runLoop(userText: promptText(trimmed, mentions: mentions))
            isBusy = false
            persistCurrentConversation()
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

        apiMessages.append(client.userMessage(userText))
        persistCurrentConversation()

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

            // DeepSeek requires reasoning_content to be replayed unchanged
            // when a thinking turn performs tool calls.
            apiMessages.append(client.assistantMessage(response))

            let reasoning = response.reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reasoning.isEmpty {
                entries.append(AssistantEntry(
                    role: .reasoning,
                    text: reasoning
                ))
            }

            let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                entries.append(AssistantEntry(role: .assistant, text: text))
            }
            persistCurrentConversation()

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
                persistCurrentConversation()
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

    // ── Conversation persistence ────────────────────────────────────────────

    private func persistCurrentConversation() {
        guard !entries.isEmpty else { return }
        guard JSONSerialization.isValidJSONObject(apiMessages),
              let rawMessages = try? JSONSerialization.data(withJSONObject: apiMessages) else { return }
        let settings = LibrarySettings.shared
        let title = entries.first(where: { if case .user = $0.role { return true }; return false })?
            .text.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(48)
        let record = StoredAssistantConversation(
            id: activeConversationID,
            title: title.map(String.init) ?? L10n.pick("New conversation", "新会话"),
            createdAt: conversationCreatedAt,
            updatedAt: Date(),
            model: settings.apiModel,
            baseURL: settings.apiBaseURL,
            entries: entries,
            apiMessages: rawMessages,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens
        )
        conversationStore.upsert(record)
        refreshConversationList()
    }

    private func restore(_ record: StoredAssistantConversation) {
        activeConversationID = record.id
        conversationCreatedAt = record.createdAt
        entries = record.entries
        apiMessages = ((try? JSONSerialization.jsonObject(with: record.apiMessages)) as? [[String: Any]]) ?? []
        totalInputTokens = record.totalInputTokens
        totalOutputTokens = record.totalOutputTokens
        let settings = LibrarySettings.shared
        settings.apiBaseURL = record.baseURL
        settings.apiModel = record.model
        registerVisibleReferences()
    }

    private func registerVisibleReferences() {
        toolbox?.registerReferences(entries.flatMap(\.mentions))
    }

    private func refreshConversationList() {
        conversations = conversationStore.records.map(\.summary)
    }

    /// Short human-readable line shown under a tool-call chip.
    private func toolSummary(_ name: String, _ input: [String: Any]) -> String {
        let interesting = ["project", "title", "query", "scope", "reference_id", "paper_id", "start", "due_at", "mode"]
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
        - Dragged references are exact items. Use their reference_id with get_item, \
        update_item, set_task_completion, or update_note; never identify an item by title.
        - Turning a plan into concrete work: list_projects and list_items first, then \
        create tasks/events one per item; put timed appointments in events, action \
        items in tasks. Summarize what you created at the end.
        - Use local ISO timestamps (YYYY-MM-DDTHH:mm) for timed work and YYYY-MM-DD \
        for all-day work. Set task priority only when the user states or clearly implies it.
        - Saving reference material or a written plan: create_note with markdown. Use \
        update_note only for an exact referenced note.
        - Papers: list_papers to find ids; read_paper (abstract first, then full_text \
        in page chunks for long PDFs); when the user asks for a summary, offer to \
        save it with save_paper_note.

        Rules: never invent project names — resolve them via list_projects. Check \
        list_items before creating to avoid duplicates. Never guess which duplicate-title \
        item the user means; ask them to drag it in. Ask before bulk changes. Dates you \
        pass to tools are in the user's local timezone. Keep answers concise and lead \
        with the outcome. \(language)
        """
    }
}
