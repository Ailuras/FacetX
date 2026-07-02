import SwiftUI

struct AssistantSidebarPanel: View {
    @ObservedObject var session: AssistantSession
    @Binding var isPresented: Bool
    @Binding var isFullscreen: Bool

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

    private var headerActions: some View {
        HStack(spacing: 2) {
            if session.totalOutputTokens > 0 {
                Text("\(session.totalInputTokens)↑ \(session.totalOutputTokens)↓")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 4)
            }

            Button {
                session.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.entries.isEmpty)
            .help(L10n.pick("Clear conversation", "清空对话"))

            Button {
                withAnimation(FacetTheme.detailSpring) { isFullscreen.toggle() }
            } label: {
                Image(systemName: isFullscreen
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .medium))
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
