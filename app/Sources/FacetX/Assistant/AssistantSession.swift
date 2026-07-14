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

/// The paper the user is actively reading, surfaced to the model as context.
/// The full extracted text is injected once (on the first turn after the toggle
/// turns on); later turns get a compact reminder, since the full text already
/// lives in the conversation history and DeepSeek's prefix cache keeps it cheap.
struct ActivePaperContext: Equatable {
    let paperID: String
    let title: String
    let authors: String
    let abstract: String
    let fullText: String
    let truncated: Bool
    var currentPage: Int
    var pageCount: Int

    private var head: String {
        "Title: \(title)\nAuthors: \(authors.isEmpty ? "(unknown)" : authors)"
    }

    /// First turn: hand the model the whole paper.
    var fullInjectionBlock: String {
        let body: String
        if fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let abstractText = abstract.trimmingCharacters(in: .whitespacesAndNewlines)
            body = "Abstract: \(abstractText.isEmpty ? "(none on file — no PDF text available)" : abstractText)"
        } else {
            let tail = truncated
                ? "\n…(truncated — call read_paper(paper_id, page_start, page_end) for later pages)"
                : ""
            body = "Full text:\n\(fullText)\(tail)"
        }
        return """
        The user is reading this paper in FacetX's PDF reader; treat it as the subject of the conversation.
        <paper paper_id="\(paperID)">
        \(head)
        \(body)
        </paper>
        """
    }

    /// Later turns: the full text is already above in the history.
    var reminderBlock: String {
        let page = pageCount > 0 ? "\(currentPage) of \(pageCount)" : "\(currentPage)"
        return """
        Still discussing the paper provided earlier (paper_id="\(paperID)", "\(title)"), reader is on page \(page). \
        Its full text is already in this conversation; call read_paper only if you need a page verbatim again.
        """
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
    @Published private(set) var totalCacheHitTokens = 0
    @Published private(set) var totalCacheMissTokens = 0
    @Published private(set) var conversations: [AssistantConversationSummary] = []
    @Published private(set) var activeConversationID = UUID()
    /// Set by the literature reading view while its "AI reading context" toggle
    /// is on. Its full text is injected on the first turn, then referenced from
    /// history on later turns (see `promptText`).
    @Published var activePaperContext: ActivePaperContext?
    /// A snippet the user selected in the PDF, shown as a removable quote above
    /// the composer and attached to the next message they send.
    @Published var pendingSelection: String?
    /// The paper whose full text is already present in this conversation's
    /// history, so we inject it once rather than every turn.
    private var injectedPaperID: String?

    private var apiMessages: [[String: Any]] = []
    private var toolbox: AgentToolbox?
    private weak var workStore: WorkStore?
    private var configured = false
    private let conversationStore = AssistantConversationStore()
    private var conversationCreatedAt = Date()
    /// The running agent loop task; cancelled by `cancel()`.
    private var loopTask: Task<Void, Never>?

    private static let maxLoopIterations = 12

    init() {
        refreshConversationList()
        if let latest = conversationStore.records.first {
            restore(latest)
        }
    }

    func configure(eventKit: EventKitService, store: WorkStore, settings: AppSettings) {
        guard !configured else { return }
        configured = true
        self.workStore = store
        self.toolbox = AgentToolbox(eventKit: eventKit, workStore: store, settings: settings)
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
        totalCacheHitTokens = 0
        totalCacheMissTokens = 0
        injectedPaperID = nil
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
            totalCacheHitTokens = 0
            totalCacheMissTokens = 0
            injectedPaperID = nil
        }
    }

    func deleteConversation(_ id: UUID) {
        guard !isBusy else { return }
        if id == activeConversationID {
            deleteCurrentConversation()
            return
        }
        conversationStore.delete(id: id)
        refreshConversationList()
    }

    func send(_ text: String, mentions: [AssistantItemMention] = [], displayText: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSelection = !(pendingSelection ?? "").isEmpty
        guard !trimmed.isEmpty || !mentions.isEmpty || hasSelection, !isBusy else { return }
        let display = displayText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleText: String
        if let display, !display.isEmpty {
            visibleText = display
        } else if trimmed.isEmpty {
            visibleText = hasSelection
                ? L10n.pick("Explain the selected passage.", "解释选中的这段内容。")
                : L10n.pick("Review the referenced items.", "查看这些提及的项目条目。")
        } else {
            visibleText = trimmed
        }
        entries.append(AssistantEntry(role: .user, text: visibleText, mentions: mentions))
        toolbox?.registerReferences(mentions)
        // Build the augmented prompt now (it consumes the pending selection and
        // records the paper injection) so those one-shot inputs are captured at
        // send time rather than whenever the async loop happens to read them.
        let prompt = promptText(trimmed, mentions: mentions)
        pendingSelection = nil
        persistCurrentConversation()
        isBusy = true
        loopTask = Task {
            await runLoop(userText: prompt)
            isBusy = false
            loopTask = nil
            persistCurrentConversation()
        }
    }

    /// Cancel the running agent loop immediately.
    func cancel() {
        loopTask?.cancel()
        loopTask = nil
        isBusy = false
        entries.append(AssistantEntry(
            role: .error,
            text: L10n.pick("Stopped.", "已中断。")))
        persistCurrentConversation()
    }

    /// Re-send the last user message, discarding everything after it.
    func retryLastUserMessage() {
        guard !isBusy,
              let lastUserIndex = entries.lastIndex(where: { if case .user = $0.role { return true }; return false })
        else { return }
        let entry = entries[lastUserIndex]
        let text = entry.text
        let mentions = entry.mentions
        // Count how many user turns precede this one so we can cut apiMessages.
        let userOrdinal = entries[..<lastUserIndex]
            .reduce(0) { count, e in if case .user = e.role { return count + 1 }; return count }
        entries.removeSubrange(lastUserIndex...)
        var seenUsers = 0
        var cut = apiMessages.count
        for (index, message) in apiMessages.enumerated() where (message["role"] as? String) == "user" {
            if seenUsers == userOrdinal { cut = index; break }
            seenUsers += 1
        }
        apiMessages.removeSubrange(cut...)
        injectedPaperID = nil
        send(text, mentions: mentions)
    }

    /// Rewind the conversation to a past user turn, replace its text, and run
    /// again from there — everything after that turn (in both the transcript and
    /// the raw API history) is discarded, matching the "edit & resend" model
    /// where later exchanges no longer make sense once the prompt changed.
    func editAndResend(entryID: UUID, newText: String) {
        guard !isBusy else { return }
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              case .user = entries[entryIndex].role else { return }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Which user turn is this (0-based)? Used to find the matching cut point
        // in apiMessages, whose entries don't map 1:1 to transcript entries.
        let userOrdinal = entries[..<entryIndex]
            .reduce(0) { count, entry in
                if case .user = entry.role { return count + 1 }
                return count
            }
        let mentions = entries[entryIndex].mentions

        entries.removeSubrange(entryIndex...)

        var seenUsers = 0
        var cut = apiMessages.count
        for (index, message) in apiMessages.enumerated() where (message["role"] as? String) == "user" {
            if seenUsers == userOrdinal { cut = index; break }
            seenUsers += 1
        }
        apiMessages.removeSubrange(cut...)
        // The kept history may no longer contain the paper's full text, so allow
        // it to be re-injected on this fresh turn if the context is still on.
        injectedPaperID = nil

        send(trimmed, mentions: mentions)
    }

    private func promptText(_ text: String, mentions: [AssistantItemMention]) -> String {
        var blocks: [String] = []

        if let paper = activePaperContext {
            if injectedPaperID == paper.paperID {
                blocks.append(paper.reminderBlock)
            } else {
                blocks.append(paper.fullInjectionBlock)
                injectedPaperID = paper.paperID
            }
        }

        if let selection = pendingSelection?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selection.isEmpty {
            blocks.append("""
            The user selected this passage in the PDF and wants the question to focus on it:
            <selected_excerpt>\(selection)</selected_excerpt>
            """)
        }

        if !mentions.isEmpty {
            let objects = mentions.map(\.promptObject)
            let data = try? JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys])
            let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            blocks.append("""
            The user explicitly referenced these exact FacetX items. Titles can be duplicated; use reference_id whenever a tool accepts one.
            <facetx_references>\(json)</facetx_references>
            """)
        }

        guard !blocks.isEmpty else { return text }
        let request = text.isEmpty
            ? (activePaperContext != nil ? "Discuss the paper I'm reading." : "Review the referenced items.")
            : text
        return blocks.joined(separator: "\n") + "\n<user_request>\(request)</user_request>"
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
            var reasoningEntryID: UUID?
            var textEntryID: UUID?
            var response: LLMResponse?
            do {
                for try await event in client.stream(system: system, messages: apiMessages, tools: tools) {
                    switch event {
                    case .reasoningDelta(let piece):
                        if let id = reasoningEntryID, let idx = entries.firstIndex(where: { $0.id == id }) {
                            entries[idx].text += piece
                        } else {
                            let entry = AssistantEntry(role: .reasoning, text: piece)
                            reasoningEntryID = entry.id
                            entries.append(entry)
                        }
                    case .textDelta(let piece):
                        if let id = textEntryID, let idx = entries.firstIndex(where: { $0.id == id }) {
                            entries[idx].text += piece
                        } else {
                            let entry = AssistantEntry(role: .assistant, text: piece)
                            textEntryID = entry.id
                            entries.append(entry)
                        }
                    case .done(let finalResponse):
                        response = finalResponse
                    }
                }
            } catch {
                entries.append(AssistantEntry(role: .error, text: error.localizedDescription))
                return
            }
            guard let response else { return }

            totalInputTokens += response.inputTokens
            totalOutputTokens += response.outputTokens
            totalCacheHitTokens += response.cacheHitTokens
            totalCacheMissTokens += response.cacheMissTokens

            // DeepSeek requires reasoning_content to be replayed unchanged
            // when a thinking turn performs tool calls.
            apiMessages.append(client.assistantMessage(response))

            if let id = reasoningEntryID, let idx = entries.firstIndex(where: { $0.id == id }) {
                entries[idx].text = entries[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let id = textEntryID, let idx = entries.firstIndex(where: { $0.id == id }) {
                entries[idx].text = entries[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        // Cache hit/miss counts aren't persisted per conversation — they're a
        // live "savings this session" indicator, not conversation history.
        totalCacheHitTokens = 0
        totalCacheMissTokens = 0
        // A restored conversation may already contain a paper's full text, but
        // we can't cheaply tell which — clear so the next context-on turn
        // re-injects once rather than silently referencing text that isn't there.
        injectedPaperID = nil
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
        let interesting = ["work", "target_work", "title", "query", "scope",
                           "reference_id", "paper_id", "start", "due_at", "mode", "week"]
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
        let workNames = workStore?.activeWorks.map(\.name).joined(separator: ", ") ?? ""
        let language = L10n.language == "zh"
            ? "Respond in Chinese (中文) unless the user writes in another language."
            : "Respond in the user's language."

        return """
        You are the built-in assistant of FacetX, a macOS app that organizes Apple \
        Calendar and Reminders items into works (an item belongs to a work when \
        its title starts with "WorkPrefix: ") and manages an academic literature \
        library with local PDFs.

        Today is \(today). Active works: \(workNames.isEmpty ? "(none yet)" : workNames).

        Use the tools to read and change the user's real data:
        - Dragged references are exact tasks or events. Use their reference_id with \
        get_item, update_item, or set_task_completion; never identify an item by title.
        - Turning a plan into concrete work: list_works and list_items first, then \
        create tasks/events one per item; put timed appointments in events, action \
        items in tasks. Summarize what you created at the end.
        - Use local ISO timestamps (YYYY-MM-DDTHH:mm) for timed work and YYYY-MM-DD \
        for all-day work. Set task priority only when the user states or clearly implies it.
        - Written plans, notes, and summaries are Git documents. Use \
        list_work_documents, read_work_document, create_work_document, and \
        update_work_document. A document requires an explicit work with a local repository.
        - Papers: list_papers to find ids; read_paper (abstract first, then full_text \
        in page chunks for long PDFs). To save a paper summary, require an explicit \
        work and target task/event, create a work document, then attach both the \
        document and paper to that work item.

        Rules: never invent work names — resolve them via list_works. Check \
        list_items before creating to avoid duplicates. Never guess which duplicate-title \
        item the user means; ask them to drag it in. Ask before bulk changes. Dates you \
        pass to tools are in the user's local timezone. Keep answers concise and lead \
        with the outcome. \(language)
        """
    }
}
