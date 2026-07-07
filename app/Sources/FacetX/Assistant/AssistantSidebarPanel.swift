import SwiftUI

struct AssistantSidebarPanel: View {
    @ObservedObject var session: AssistantSession
    @Binding var isPresented: Bool
    @Binding var isFullscreen: Bool

    @State private var showingHistory = false
    @State private var historySearch = ""

    var body: some View {
        FacetSidebarPane(
            title: L10n.pick("Assistant", "AI 助手"),
            systemImage: "sparkles",
            closeHelp: L10n.pick("Close AI assistant", "关闭 AI 助手"),
            fillWidth: isFullscreen,
            onClose: {
                withAnimation(FacetTheme.detailSpring) { isPresented = false }
            },
            accessory: { headerActions }
        ) {
            AssistantView(session: session)
        }
    }

    private var tokenSummary: String {
        let cacheable = session.totalCacheHitTokens + session.totalCacheMissTokens
        guard cacheable > 0 else {
            return "\(session.totalInputTokens)↑ \(session.totalOutputTokens)↓"
        }
        let hitRate = Int((Double(session.totalCacheHitTokens) / Double(cacheable) * 100).rounded())
        return "\(session.totalInputTokens)↑ \(session.totalOutputTokens)↓ · \(hitRate)% cached"
    }

    private var headerActions: some View {
        HStack(spacing: 2) {
            if session.totalOutputTokens > 0 {
                Text(tokenSummary)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 4)
                    .help(L10n.pick("Input tokens ↑ · output tokens ↓ · % served from DeepSeek's prompt cache",
                                    "输入 ↑ · 输出 ↓ · 命中 DeepSeek 提示缓存的比例"))
            }

            Button {
                showingHistory = true
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.pick("Conversation history", "历史会话"))
            .popover(isPresented: $showingHistory, arrowEdge: .bottom) {
                AssistantHistoryPopover(
                    session: session,
                    searchText: $historySearch,
                    onSelect: { id in
                        session.openConversation(id)
                        showingHistory = false
                    }
                )
            }

            Button {
                session.newConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy)
            .help(L10n.pick("New conversation", "新建会话"))

            Button {
                session.deleteCurrentConversation()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.entries.isEmpty || session.isBusy)
            .help(L10n.pick("Delete conversation", "删除当前会话"))

            Button {
                withAnimation(FacetTheme.detailSpring) { isFullscreen.toggle() }
            } label: {
                Image(systemName: isFullscreen
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isFullscreen
                  ? L10n.pick("Exit fullscreen", "退出全屏")
                  : L10n.pick("Fullscreen", "全屏"))
        }
    }
}

/// Search box on top, matching conversations below — mirrors the pattern used
/// by the other history/command pickers in the app so the toolbar icon opens
/// a consistent affordance instead of a plain dropdown menu.
private struct AssistantHistoryPopover: View {
    @ObservedObject var session: AssistantSession
    @Binding var searchText: String
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchField

            Divider()

            if filteredConversations.isEmpty {
                Text(session.conversations.isEmpty
                     ? L10n.pick("No history", "暂无历史会话")
                     : L10n.pick("No matches", "没有匹配结果"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredConversations) { conversation in
                            AssistantHistoryRow(
                                conversation: conversation,
                                isActive: conversation.id == session.activeConversationID,
                                onSelect: { onSelect(conversation.id) },
                                onDelete: { session.deleteConversation(conversation.id) }
                            )
                            if conversation.id != filteredConversations.last?.id {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                    .hideScrollIndicators()
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 280)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(L10n.pick("Search conversations", "搜索历史会话"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var filteredConversations: [AssistantConversationSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return session.conversations }
        return session.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct AssistantHistoryRow: View {
    let conversation: AssistantConversationSummary
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(conversation.title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(Self.compactRelativeTime(conversation.updatedAt))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? FacetTheme.quietPanel : Color.clear)
        .onHover { isHovering = $0 }
    }

    private static func compactRelativeTime(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86400))d"
        }
    }
}
