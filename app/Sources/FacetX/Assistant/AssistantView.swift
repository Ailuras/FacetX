import SwiftUI
import UniformTypeIdentifiers

/// The assistant pane: a chat transcript over the agent session, with tool
/// calls rendered as inline chips so the user can see what the model did.
struct AssistantView: View {
    @ObservedObject var session: AssistantSession
    @State private var llmSettings = LibrarySettings.shared

    @State private var draft = ""
    @State private var mentions: [AssistantItemMention] = []
    @State private var isMentionDropTarget = false
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var editingEntryID: UUID?
    @State private var editDraft = ""
    /// Tool-call entry IDs whose details are currently expanded.
    @State private var expandedToolEntries: Set<UUID> = []
    @FocusState private var inputFocused: Bool
    @FocusState private var editFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
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
        .onDrop(
            of: [.facetXProjectItem],
            delegate: AssistantMentionDropDelegate(
                isTargeted: $isMentionDropTarget,
                onMention: addMention
            )
        )
        .overlay {
            if isMentionDropTarget { mentionDropOverlay }
        }
        .onChange(of: llmSettings.apiModel) {
            if !selectedModelEfforts.contains(llmSettings.assistantReasoningEffort) {
                llmSettings.assistantReasoningEffort = .high
            }
        }
        .onChange(of: session.activeConversationID) { cancelEdit() }
        .task(id: modelCatalogKey) { await refreshModels() }
    }

    // ── Transcript ───────────────────────────────────────────────────────────

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
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
                .hideScrollIndicators()
            }
            .scrollIndicators(.hidden)
            .onChange(of: session.entries.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(session.entries.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: session.entries.last) {
                // Streamed replies grow the last entry in place rather than
                // appending new ones, so follow it without re-animating on
                // every delta — that would fight itself many times a second.
                proxy.scrollTo(session.entries.last?.id, anchor: .bottom)
            }
            .onChange(of: session.isBusy) {
                if session.isBusy {
                    withAnimation { proxy.scrollTo("busy", anchor: .bottom) }
                }
            }
        }
    }

    /// Claude Code–style transcript: turns stack top-to-bottom in a single
    /// left-aligned column instead of left/right chat bubbles. A user turn
    /// gets a thin accent rule to mark where the human spoke; everything
    /// else — assistant prose, reasoning, tool calls — flows as plain,
    /// full-width text so long replies don't fight a bubble for width.
    @ViewBuilder
    private func entryView(_ entry: AssistantEntry) -> some View {
        switch entry.role {
        case .user:
            UserEntryView(
                entry: entry,
                isEditing: editingEntryID == entry.id,
                onEdit: { beginEditing(entry) },
                editorContent: { userEditor(for: entry) },
                mentionContent: { mentionFlow(entry.mentions, removable: false) }
            )

        case .assistant:
            AssistantMarkdownText(text: entry.text)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .reasoning:
            AssistantReasoningView(text: entry.text)

        case .tool(let name):
            VStack(alignment: .leading, spacing: 4) {
                // Header row — always visible, click to expand/collapse.
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        if expandedToolEntries.contains(entry.id) {
                            expandedToolEntries.remove(entry.id)
                        } else {
                            expandedToolEntries.insert(entry.id)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.purple)
                        Text(name)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.purple)
                        Spacer(minLength: 0)
                        Image(systemName: expandedToolEntries.contains(entry.id)
                              ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.purple.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                // Expanded detail.
                if expandedToolEntries.contains(entry.id), !entry.text.isEmpty {
                    Text(entry.text)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.purple.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else if !entry.text.isEmpty {
                    Text(entry.text)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .error:
            VStack(alignment: .leading, spacing: 6) {
                Label(entry.text, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Retry button — only show when the session is idle so
                // tapping it while a run is already in flight is impossible.
                if !session.isBusy {
                    Button {
                        session.retryLastUserMessage()
                    } label: {
                        Label(L10n.pick("Retry", "重试"),
                              systemImage: "arrow.clockwise")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Inline editor shown in place of a user turn after a double-click. Sending
    /// rewrites that turn and drops everything after it.
    private func userEditor(for entry: AssistantEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $editDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1...12)
                .focused($editFocused)
                .onSubmit(commitEdit)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(L10n.pick("Cancel", "取消")) { cancelEdit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button(L10n.pick("Resend", "重发")) { commitEdit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(editDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(9)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
        )
    }

    private func beginEditing(_ entry: AssistantEntry) {
        guard !session.isBusy else { return }
        editingEntryID = entry.id
        editDraft = entry.text
        editFocused = true
    }

    private func cancelEdit() {
        editingEntryID = nil
        editDraft = ""
    }

    private func commitEdit() {
        guard let id = editingEntryID else { return }
        let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        editingEntryID = nil
        editDraft = ""
        session.editAndResend(entryID: id, newText: text)
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
            Text(L10n.pick("Configure the DeepSeek API (Settings → Integrations) to enable the assistant.",
                           "在 设置 → 集成 中配置 DeepSeek API Key 后即可使用助手。"))
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
        VStack(spacing: 0) {
            modelControls

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 8) {
                if !mentions.isEmpty {
                    mentionFlow(mentions, removable: true)
                }

                if let selection = session.pendingSelection, !selection.isEmpty {
                    selectionQuote(selection)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    TextField(L10n.pick("Ask about your work…", "询问或处理你的工作…"),
                              text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(3...10)
                        .frame(minHeight: 68, alignment: .topLeading)
                        .focused($inputFocused)
                        .onSubmit(submit)
                        .disabled(session.isBusy)

                    Button(action: submit) {
                        Image(systemName: session.isBusy ? "hourglass" : "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)

                    if session.isBusy {
                        // Stop button — tap to cancel the running agent loop.
                        Button { session.cancel() } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.red.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .help(L10n.pick("Stop generation", "停止生成"))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FacetTheme.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(inputFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.14),
                            lineWidth: inputFocused ? 1.5 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { inputFocused = true }
            .padding(10)
        }
        .background(FacetTheme.panel.opacity(0.4))
    }

    private var modelControls: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Label("DeepSeek", systemImage: "server.rack")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()

            Divider().frame(height: 16)

            Menu {
                ForEach(modelChoices, id: \.self) { model in
                    Button {
                        llmSettings.apiModel = model
                    } label: {
                        if model == selectedModel {
                            Label(model, systemImage: "checkmark")
                        } else {
                            Text(model)
                        }
                    }
                }
                Divider()
                Button {
                    Task { await refreshModels() }
                } label: {
                    Label(L10n.pick("Refresh models", "刷新模型"), systemImage: "arrow.clockwise")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                    Text(selectedModel)
                        .font(.system(size: 10.5, design: .monospaced))
                        .lineLimit(1)
                    if isLoadingModels {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                }
                .foregroundStyle(.secondary)
                .fixedSize()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L10n.pick("Switch model", "切换模型"))

            Divider().frame(height: 16)

            Toggle(L10n.pick("Think", "思考"), isOn: $llmSettings.assistantThinkingEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 10.5, weight: .medium))
                .fixedSize()

            Picker("", selection: $llmSettings.assistantReasoningEffort) {
                ForEach(selectedModelEfforts) { effort in
                    Text(effort.title).tag(effort)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.mini)
            .fixedSize()
            .disabled(!llmSettings.assistantThinkingEnabled)
            .help(L10n.pick("Reasoning effort", "思考强度"))

            // Token usage pill — only visible after the first message.
            if session.totalInputTokens > 0 {
                Divider().frame(height: 16)
                let totalK = Double(session.totalInputTokens) / 1000.0
                let pillColor: Color = totalK > 110 ? .red : (totalK > 60 ? .orange : .secondary)
                HStack(spacing: 3) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .bold))
                    Text(String(format: "%.1fk", totalK))
                }
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(pillColor)
                .help(L10n.pick(
                    "\(session.totalInputTokens) input tokens · \(session.totalOutputTokens) output tokens",
                    "已消耗 \(session.totalInputTokens) 输入 token，\(session.totalOutputTokens) 输出 token"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var canSend: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSelection = !(session.pendingSelection ?? "").isEmpty
        return hasAPIKey && !session.isBusy && (!trimmed.isEmpty || !mentions.isEmpty || hasSelection)
    }

    private var hasAPIKey: Bool {
        !llmSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func mentionFlow(_ items: [AssistantItemMention], removable: Bool) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 6, alignment: .leading) {
            ForEach(items) { mention in
                HStack(spacing: 5) {
                    Image(systemName: mention.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                    Text("\(mention.projectPrefix): \(mention.title)")
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                    if removable {
                        Button {
                            mentions.removeAll { $0.id == mention.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.10))
                .clipShape(Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                )
            }
        }
    }

    /// The PDF passage the user selected while reading, shown as a removable
    /// quote so it's clear the next question is scoped to it.
    private func selectionQuote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "quote.opening")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            Button {
                session.pendingSelection = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor.opacity(0.5))
                .frame(width: 2)
                .padding(.vertical, 4)
        }
    }

    private var mentionDropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                        )
                )

            VStack(spacing: 9) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(L10n.pick("Drop to reference this item", "松手以提及此条目"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.pick("Drop more items to reference them together.",
                               "可继续拖入多个条目，一起交给助手处理。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .allowsHitTesting(false)
    }

    private func addMention(_ mention: AssistantItemMention) {
        guard !mentions.contains(where: { $0.id == mention.id }) else { return }
        mentions.append(mention)
        inputFocused = true
    }

    private var selectedModel: String {
        let configured = llmSettings.apiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return configured.isEmpty ? DeepSeekAPI.defaultModel : configured
    }

    private var modelChoices: [String] {
        var seen = Set<String>()
        let catalog = availableModels.filter(isAssistantModel)
        return ([selectedModel] + catalog + DeepSeekAPI.suggestedModels)
            .filter { seen.insert($0).inserted }
    }

    private var selectedModelEfforts: [AssistantReasoningEffort] {
        DeepSeekAPI.supportedAssistantEfforts
    }

    private func isAssistantModel(_ model: String) -> Bool {
        model.lowercased().hasPrefix("deepseek-")
    }

    private var modelCatalogKey: String {
        "\(llmSettings.apiBaseURL)|\(llmSettings.apiKey)"
    }

    private func refreshModels() async {
        guard !llmSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            availableModels = []
            return
        }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let service = TranslationService(
                config: ConfigManager.shared.effectiveConfig,
                apiKey: llmSettings.apiKey
            )
            availableModels = try await service.fetchModels()
        } catch {
            availableModels = []
        }
    }

    private func submit() {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let referencedItems = mentions
        draft = ""
        mentions = []
        session.send(text, mentions: referencedItems)
    }
}

/// A user-turn bubble with a tinted background and a hover-revealed edit button.
private struct UserEntryView<EditorContent: View, MentionContent: View>: View {
    let entry: AssistantEntry
    let isEditing: Bool
    let onEdit: () -> Void
    @ViewBuilder let editorContent: () -> EditorContent
    @ViewBuilder let mentionContent: () -> MentionContent

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Accent rule
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.accentColor.opacity(isEditing ? 0.9 : 0.55))
                .frame(width: 2)
                .padding(.trailing, 10)

            VStack(alignment: .leading, spacing: 6) {
                if !entry.mentions.isEmpty {
                    mentionContent()
                }
                if isEditing {
                    editorContent()
                } else {
                    Text(entry.text)
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { onEdit() }
                }
            }

            Spacer(minLength: 8)

            // Edit button — always visible but more prominent on hover
            if !isEditing {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isHovered ? Color.accentColor : Color.secondary.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isHovered
                                      ? Color.accentColor.opacity(0.12)
                                      : Color.primary.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
                .help(L10n.pick("Edit and resend from here", "编辑并从此处重新开始"))
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.accentColor.opacity(isEditing ? 0.1 : (isHovered ? 0.08 : 0.06)))
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isEditing)
    }
}


/// same markdown-it + KaTeX bundle used for note previews, sized to fit its
/// content instead of scrolling internally like a full-page preview.
private struct AssistantMarkdownText: View {
    let text: String
    var variant: String = "chat"
    @State private var height: CGFloat = 18

    var body: some View {
        MarkdownPreviewWeb(text: text, variant: variant) { measured in
            guard abs(measured - height) > 0.5 else { return }
            height = measured
        }
        .frame(height: height)
    }
}

private struct AssistantReasoningView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            AssistantMarkdownText(text: text, variant: "chat reasoning")
                .padding(.top, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(
                L10n.pick("Thought", "思考过程"),
                systemImage: "brain.head.profile"
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssistantMentionDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onMention: (AssistantItemMention) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.facetXProjectItem])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let providers = info.itemProviders(for: [.facetXProjectItem])
        guard !providers.isEmpty else { return false }
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.facetXProjectItem.identifier) { data, _ in
                guard let data,
                      let mention = try? JSONDecoder().decode(AssistantItemMention.self, from: data) else {
                    return
                }
                Task { @MainActor in onMention(mention) }
            }
        }
        return true
    }
}
