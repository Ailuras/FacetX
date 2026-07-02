import SwiftUI

/// The assistant pane: a chat transcript over the agent session, with tool
/// calls rendered as inline chips so the user can see what the model did.
struct AssistantView: View {
    @ObservedObject var session: AssistantSession
    @State private var llmSettings = LibrarySettings.shared

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if !hasAPIKey {
                keyMissingState
            } else if session.entries.isEmpty {
                emptyState
            } else {
                transcript
            }

            Divider()
            inputBar
        }
        .background(FacetTheme.canvas)
    }

    // ── Header ───────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(L10n.pick("Assistant", "AI 助手"))
                .font(.system(size: 14, weight: .semibold))
            Text("\(llmSettings.apiProvider.displayName) · \(modelLabel)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.05)))

            Spacer()

            if session.totalOutputTokens > 0 {
                Text("\(session.totalInputTokens)↑ \(session.totalOutputTokens)↓ tokens")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Button {
                session.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.pick("Clear conversation", "清空对话"))
            .disabled(session.entries.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // ── Transcript ───────────────────────────────────────────────────────────

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(session.entries) { entry in
                        entryView(entry)
                            .id(entry.id)
                    }
                    if session.isBusy {
                        thinkingIndicator
                            .id("busy")
                    }
                }
                .padding(16)
            }
            .onChange(of: session.entries.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(session.entries.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: session.isBusy) {
                if session.isBusy {
                    withAnimation { proxy.scrollTo("busy", anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func entryView(_ entry: AssistantEntry) -> some View {
        switch entry.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(entry.text)
                    .font(.system(size: 12.5))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    )
            }

        case .assistant:
            HStack {
                Text(LocalizedStringKey(entry.text))
                    .font(.system(size: 12.5))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(FacetTheme.quietPanel)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1)
                    )
                Spacer(minLength: 60)
            }

        case .tool(let name):
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.purple)
                Text(name)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.purple)
                if !entry.text.isEmpty {
                    Text(entry.text)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.purple.opacity(0.08))
            )

        case .error:
            Label(entry.text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11.5))
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.pick("Working…", "思考中…"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // ── Empty / setup states ─────────────────────────────────────────────────

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(Color.accentColor.opacity(0.55))
            Text(L10n.pick("Ask the assistant to plan, organize, or read papers.",
                           "让助手帮你拆解计划、整理日程或阅读文献。"))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                suggestionButton(L10n.pick("What's on my plate this week?", "我这周都有什么安排？"))
                suggestionButton(L10n.pick("Here's my plan — turn it into tasks and events: …",
                                           "这是我的计划，帮我整理成具体的任务和日程：…"))
                suggestionButton(L10n.pick("Summarize the paper 《…》 and save it as a note.",
                                           "帮我总结文献《…》，并把总结保存为笔记。"))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func suggestionButton(_ text: String) -> some View {
        Button {
            draft = text
            inputFocused = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(FacetTheme.quietPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var keyMissingState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "key.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(L10n.pick("Configure the LLM API (Settings → Integrations) to enable the assistant.",
                           "在 设置 → 集成 → 大模型 API 中配置 API Key 后即可使用助手。"))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Button(L10n.pick("Open Settings → Integrations", "打开 设置 → 集成")) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Input ────────────────────────────────────────────────────────────────

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(L10n.pick("Message the assistant…", "向助手描述你的需求…"),
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit(submit)
                .disabled(!hasAPIKey)

            Button(action: submit) {
                Image(systemName: session.isBusy ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(FacetTheme.panel.opacity(0.4))
    }

    private var canSend: Bool {
        hasAPIKey && !session.isBusy
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasAPIKey: Bool {
        !llmSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var modelLabel: String {
        let model = llmSettings.apiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? llmSettings.apiProvider.defaultModel : model
    }

    private func submit() {
        guard canSend else { return }
        let text = draft
        draft = ""
        session.send(text)
    }
}
