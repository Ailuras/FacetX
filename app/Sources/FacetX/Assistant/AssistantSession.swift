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
    private var toolbox: AgentToolbox?
    private weak var settings: AppSettings?
    private weak var projectStore: ProjectStore?
    private var configured = false

    private static let maxLoopIterations = 12

    func configure(eventKit: EventKitService, store: ProjectStore, settings: AppSettings) {
        guard !configured else { return }
        configured = true
        self.settings = settings
        self.projectStore = store
        self.toolbox = AgentToolbox(eventKit: eventKit, projectStore: store, settings: settings)
    }

    var hasAPIKey: Bool {
        !(settings?.anthropicApiKey.isEmpty ?? true)
    }

    func clear() {
        entries.removeAll()
        apiMessages.removeAll()
        totalInputTokens = 0
        totalOutputTokens = 0
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        entries.append(AssistantEntry(role: .user, text: trimmed))
        apiMessages.append(["role": "user", "content": trimmed])
        isBusy = true
        Task {
            await runLoop()
            isBusy = false
        }
    }

    // ── Agent loop ───────────────────────────────────────────────────────────

    private func runLoop() async {
        guard let settings, let toolbox else { return }
        let client = AnthropicClient(apiKey: settings.anthropicApiKey,
                                     model: settings.anthropicModel,
                                     baseURL: settings.anthropicBaseURL)
        let tools = toolbox.definitions
        let system = buildSystemPrompt()

        for _ in 0..<Self.maxLoopIterations {
            let response: AnthropicClient.Response
            do {
                response = try await client.send(system: system,
                                                 messages: apiMessages,
                                                 tools: tools)
            } catch {
                entries.append(AssistantEntry(role: .error, text: error.localizedDescription))
                // Drop the dangling user turn so a retry starts clean.
                if apiMessages.last?["role"] as? String == "user" {
                    apiMessages.removeLast()
                }
                return
            }

            totalInputTokens += response.inputTokens
            totalOutputTokens += response.outputTokens

            // Echo the assistant content verbatim (text/tool_use/thinking blocks).
            apiMessages.append(["role": "assistant", "content": response.content])

            let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                entries.append(AssistantEntry(role: .assistant, text: text))
            }

            switch response.stopReason {
            case "tool_use":
                var results: [[String: Any]] = []
                for call in response.toolUses {
                    entries.append(AssistantEntry(role: .tool(name: call.name),
                                                  text: toolSummary(call.name, call.input)))
                    let (result, isError) = await toolbox.execute(name: call.name, input: call.input)
                    var block: [String: Any] = [
                        "type": "tool_result",
                        "tool_use_id": call.id,
                        "content": result,
                    ]
                    if isError { block["is_error"] = true }
                    results.append(block)
                }
                // All results for parallel calls go back in ONE user message.
                apiMessages.append(["role": "user", "content": results])
                continue

            case "pause_turn":
                // Server-side pause: re-send as-is to resume.
                continue

            case "refusal":
                entries.append(AssistantEntry(
                    role: .error,
                    text: L10n.pick("The model declined this request.", "模型拒绝了这次请求。")))
                return

            case "max_tokens":
                entries.append(AssistantEntry(
                    role: .error,
                    text: L10n.pick("Response truncated (max tokens).", "回复因长度限制被截断。")))
                return

            default: // end_turn
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
