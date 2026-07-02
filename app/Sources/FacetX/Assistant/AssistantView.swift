import SwiftUI

/// The assistant pane: a chat transcript over the agent session, with tool
/// calls rendered as inline chips so the user can see what the model did.
struct AssistantView: View {
    @ObservedObject var session: AssistantSession
    let contextProject: Project?

    @EnvironmentObject private var store: ProjectStore
    @State private var llmSettings = LibrarySettings.shared

    @State private var draft = ""
    @State private var quickProjectID: Project.ID?
    @FocusState private var inputFocused: Bool

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
        .onAppear { synchronizeQuickProject() }
        .onChange(of: contextProject?.id) { synchronizeQuickProject() }
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
            Text(L10n.pick("Quick @ commands remain available without an API key.",
                           "即使没有 API Key，也可以使用 @ 快捷命令。"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
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
            if !quickCommandSuggestions.isEmpty {
                quickSuggestionBar
                Divider().opacity(0.5)
            }

            modelControls

            Divider().opacity(0.5)

            HStack(alignment: .bottom, spacing: 8) {
                quickCommandMenu
                projectMenu

                TextField(L10n.pick("Message or type @…", "输入消息或 @ 快捷命令…"),
                          text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .onSubmit(submit)
                    .disabled(session.isBusy)

                Button(action: submit) {
                    Image(systemName: session.isBusy ? "hourglass" : "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(FacetTheme.panel.opacity(0.4))
    }

    private var modelControls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(TranslationProvider.allCases, id: \.self) { provider in
                    Button {
                        selectProvider(provider)
                    } label: {
                        if provider == llmSettings.apiProvider {
                            Label(provider.displayName, systemImage: "checkmark")
                        } else {
                            Text(provider.displayName)
                        }
                    }
                }
            } label: {
                Label(llmSettings.apiProvider.displayName, systemImage: "server.rack")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L10n.pick("Switch provider", "切换服务商"))

            Divider().frame(height: 16)

            Image(systemName: "cpu")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            TextField(llmSettings.apiProvider.defaultModel, text: $llmSettings.apiModel)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, design: .monospaced))
                .lineLimit(1)
                .help(L10n.pick("Model identifier", "模型标识"))

            Button {
                llmSettings.apiModel = llmSettings.apiProvider.defaultModel
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(L10n.pick("Use provider default model", "使用服务商默认模型"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var quickCommandMenu: some View {
        Menu {
            ForEach(AssistantQuickItemKind.allCases) { kind in
                Button {
                    insertQuickCommand(kind)
                } label: {
                    Label("\(kind.command)  \(kind.title)", systemImage: kind.systemImage)
                }
            }
        } label: {
            Text("@")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.pick("Quick add task, event, or note", "快捷添加任务、日程或笔记"))
    }

    private var projectMenu: some View {
        Menu {
            if store.activeProjects.isEmpty {
                Text(L10n.pick("No projects", "暂无项目"))
            } else {
                ForEach(store.activeProjects) { project in
                    Button {
                        quickProjectID = project.id
                    } label: {
                        if project.id == quickProject?.id {
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "folder")
                Text(quickProject?.prefix ?? "—")
                    .lineLimit(1)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: 72)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L10n.pick("Quick-add project", "快捷添加到项目"))
    }

    private var quickSuggestionBar: some View {
        HStack(spacing: 6) {
            ForEach(quickCommandSuggestions) { kind in
                Button {
                    insertQuickCommand(kind)
                } label: {
                    Label(kind.command, systemImage: kind.systemImage)
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.borderless)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var canSend: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !session.isBusy, !trimmed.isEmpty else { return false }
        if let command = parsedQuickCommand {
            return quickProject != nil && !command.title.isEmpty
        }
        return hasAPIKey
    }

    private var hasAPIKey: Bool {
        !llmSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var quickProject: Project? {
        if let quickProjectID,
           let project = store.activeProjects.first(where: { $0.id == quickProjectID }) {
            return project
        }
        return contextProject ?? store.activeProjects.first
    }

    private var parsedQuickCommand: (kind: AssistantQuickItemKind, title: String)? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.firstIndex(where: { $0.isWhitespace }) else {
            return AssistantQuickItemKind.allCases.first(where: { $0.command == trimmed.lowercased() })
                .map { ($0, "") }
        }
        let token = String(trimmed[..<separator]).lowercased()
        guard let kind = AssistantQuickItemKind.allCases.first(where: { $0.command == token }) else {
            return nil
        }
        let title = trimmed[separator...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (kind, title)
    }

    private var quickCommandSuggestions: [AssistantQuickItemKind] {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("@"), !trimmed.contains(where: { $0.isWhitespace }) else { return [] }
        return AssistantQuickItemKind.allCases.filter { $0.command.hasPrefix(trimmed) }
    }

    private func synchronizeQuickProject() {
        if let contextProject {
            quickProjectID = contextProject.id
        } else if quickProject == nil {
            quickProjectID = store.activeProjects.first?.id
        }
    }

    private func selectProvider(_ provider: TranslationProvider) {
        guard provider != llmSettings.apiProvider else { return }
        llmSettings.apiProvider = provider
        llmSettings.apiBaseURL = provider.defaultBaseURL
        llmSettings.apiModel = provider.defaultModel
    }

    private func insertQuickCommand(_ kind: AssistantQuickItemKind) {
        draft = "\(kind.command) "
        inputFocused = true
    }

    private func submit() {
        guard canSend else { return }
        if let command = parsedQuickCommand, let project = quickProject {
            draft = ""
            session.quickAdd(kind: command.kind, title: command.title, project: project)
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        session.send(text)
    }
}
